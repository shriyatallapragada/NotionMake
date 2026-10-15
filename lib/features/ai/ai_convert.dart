/// Converts between the JSON the local model produces and a [Template].
///
/// The model's output is untrusted input: this file repairs what can be
/// repaired (wrong colors, nested containers, loose date formats...) and drops
/// what can't, so the editor never receives anything the publisher would
/// reject. Embed URLs are checked against an allow-list so the model can't
/// invent or smuggle in links.
library;

import 'dart:convert';

import '../../core/constants.dart';
import '../../core/notion/database_mapper.dart';
import '../../core/widget_library.dart';
import '../editor/models/template_model.dart';
import 'ai_schema.dart';

class AiFormatException implements Exception {
  final String message;
  const AiFormatException(this.message);
  @override
  String toString() => message;
}

class AiPage {
  final Template template;
  final String summary;
  const AiPage(this.template, this.summary);
}

const _maxTopBlocks = 100;
const _maxOptions = 25;

final _urlRe = RegExp(r'https://[^\s<>"\x27)\]]+');

/// https URLs written in [text], with trailing punctuation removed.
Set<String> extractUrls(String text) => {
  for (final m in _urlRe.allMatches(text)) m.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), ''),
};

String _clean(Object? v, {int max = 2000}) {
  if (v == null) return '';
  var s = '$v'.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '').trim();
  if (s.runes.length > max) s = String.fromCharCodes(s.runes.take(max));
  return s;
}

/// A single emoji-looking value, or null.
String? _emoji(Object? v) {
  final s = _clean(v, max: 16);
  if (s.isEmpty || s.runes.length > 8 || RegExp(r'[A-Za-z0-9]').hasMatch(s)) return null;
  return s;
}

int _int(Object? v, int fallback) => v is num ? v.toInt() : int.tryParse('$v') ?? fallback;

List<Map<String, dynamic>> _maps(Object? v) => [
  if (v is List)
    for (final e in v)
      if (e is Map) e.cast<String, dynamic>(),
];

String _typeOf(Map<String, dynamic> m) => _clean(m['type'], max: 30).toLowerCase();

/// Strips list markers the model sometimes adds ("- ", "• ", "[ ] ", "1. ").
String _listText(Object? v) {
  final lines = _clean(v, max: 4000)
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s*(?:[-*•]|\[[ xX]?\]|\d+[.)])\s+'), '').trim())
      .where((l) => l.isNotEmpty);
  return lines.join('\n');
}

/// State shared while converting one page.
class _Ctx {
  static const maxWidgets = 3;
  final Set<String> allowedUrls;

  /// A widget color matching the page, used when the model doesn't pick one.
  final String? theme;
  int widgets = 0;
  _Ctx(this.allowedUrls, this.theme);
}

const _headingToWidgetTheme = {
  'green': 'sage',
  'blue': 'navy',
  'orange': 'terracotta',
  'red': 'rose',
  'pink': 'rose',
  'purple': 'periwinkle',
};

/// The first heading (or callout) color in the model's JSON, mapped to a widget theme.
String? _pageTheme(Object? blocks) {
  for (final m in _maps(blocks)) {
    final c = _clean(m['color'], max: 30).toLowerCase().replaceAll('_background', '');
    final t = _headingToWidgetTheme[c];
    if (t != null && (_typeOf(m) == 'heading' || _typeOf(m) == 'callout')) return t;
    final inner =
        _pageTheme(m['children']) ??
        _pageTheme(_maps(m['columns']).expand((c) => _maps(c['blocks'])).toList());
    if (inner != null) return inner;
  }
  return null;
}

/// Builds a built-in widget from the model's "widget" + "options". Returns null
/// when the page already has the maximum number of widgets.
TemplateBlock? _libraryEmbed(String kind, Object? rawOptions, _Ctx ctx) {
  final options = <String, String>{};
  final entries = rawOptions is Map
      ? [
          for (final e in rawOptions.entries) {'name': e.key, 'value': e.value},
        ]
      : _maps(rawOptions);
  for (final e in entries) {
    final name = _clean(e['name'], max: 20).toLowerCase();
    if (name.isNotEmpty) options[name] = _clean(e['value'], max: 300);
  }
  final w = WidgetLibrary.byKind(kind);
  if (w != null &&
      ctx.theme != null &&
      !options.containsKey('theme') &&
      w.option('theme') != null) {
    options['theme'] = ctx.theme!;
  }
  final built = WidgetLibrary.build(kind, options);
  if (built == null || built.url == null) {
    // Unknown kind, or a required setting (such as the countdown date) was missing.
    final what = w == null ? 'a widget' : 'a ${w.label.toLowerCase()} widget';
    return TemplateBlock.callout(
      'Add $what here: paste a widget link into an embed block.',
      emoji: '💡',
      color: 'yellow_background',
    );
  }
  if (ctx.widgets >= _Ctx.maxWidgets) return null;
  ctx.widgets++;
  return TemplateBlock.embed(built.url!);
}

TemplateBlock? _leaf(Map<String, dynamic> m, _Ctx ctx) {
  final text = _clean(m['text']);
  switch (_typeOf(m)) {
    case 'heading':
      if (text.isEmpty) return null;
      final color = _clean(m['color']).toLowerCase();
      return TemplateBlock.heading(
        text,
        level: _int(m['level'], 2).clamp(1, 3),
        color: NotionConstants.textColors.contains(color) ? color : 'default',
      );
    case 'paragraph':
      return text.isEmpty ? null : TemplateBlock.paragraph(text);
    case 'quote':
      return text.isEmpty ? null : TemplateBlock.quote(text);
    case 'callout':
      if (text.isEmpty) return null;
      final color = _clean(m['color']).toLowerCase();
      return TemplateBlock.callout(
        text,
        emoji: _emoji(m['emoji']) ?? '✨',
        color: calloutColors.contains(color) ? color : 'gray_background',
      );
    case 'todo':
      final items = _listText(m['text']);
      return items.isEmpty ? null : TemplateBlock.todo(items);
    case 'bullet':
      final items = _listText(m['text']);
      return items.isEmpty ? null : TemplateBlock.bullet(items);
    case 'divider':
      return TemplateBlock.divider();
    case 'embed':
      final kind = _clean(m['widget'], max: 30);
      if (kind.isNotEmpty) return _libraryEmbed(kind, m['options'], ctx);
      final url = text.trim();
      if (ctx.allowedUrls.contains(url)) return TemplateBlock.embed(url);
      // Never trust a URL the user didn't give us: leave a placeholder instead.
      final hint = text.isEmpty || text.contains('://') ? 'a widget' : text;
      return TemplateBlock.callout(
        'Add $hint here: paste a widget link into an embed block.',
        emoji: '💡',
        color: 'yellow_background',
      );
  }
  return null;
}

/// Simple blocks for inside a toggle or column. Containers can't nest, so any
/// the model put there are flattened into their contents.
List<TemplateBlock> _leafList(Object? raw, _Ctx ctx, {int depth = 0}) {
  final out = <TemplateBlock>[];
  for (final m in _maps(raw)) {
    switch (_typeOf(m)) {
      case 'toggle':
        if (depth > 1) break;
        final title = _clean(m['text']);
        if (title.isNotEmpty) out.add(TemplateBlock.paragraph(title));
        out.addAll(_leafList(m['children'], ctx, depth: depth + 1));
      case 'columns':
        if (depth > 1) break;
        for (final c in _maps(m['columns'])) {
          out.addAll(_leafList(c['blocks'], ctx, depth: depth + 1));
        }
      case 'database':
        break; // databases can only be top level
      default:
        final b = _leaf(m, ctx);
        if (b != null) out.add(b);
    }
  }
  return out;
}

DbPropType _propType(Object? v) {
  final t = _clean(v, max: 30).toLowerCase().replaceAll(RegExp(r'[_\- ]'), '');
  return switch (t) {
    'title' => DbPropType.title,
    'number' || 'integer' || 'numeric' || 'float' => DbPropType.number,
    'select' || 'status' || 'enum' => DbPropType.select,
    'multiselect' || 'tags' => DbPropType.multiSelect,
    'checkbox' || 'boolean' || 'bool' => DbPropType.checkbox,
    'date' || 'datetime' => DbPropType.date,
    'url' || 'link' => DbPropType.url,
    _ => DbPropType.text,
  };
}

List<String> _splitOptions(String s) => [
  for (final o in s.split(RegExp(r'[,;|\n]')))
    if (o.trim().isNotEmpty) o.trim(),
];

String _normalizeDate(String v) {
  final s = v.trim();
  if (isValidDbDate(s)) return s;
  final m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
  if (m == null) return '';
  final d = '${m[1]}-${m[2]!.padLeft(2, '0')}-${m[3]!.padLeft(2, '0')}';
  return isValidDbDate(d) ? d : '';
}

String _normalizeNumber(String v) {
  final n = double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), ''));
  if (n == null) return '';
  return n == n.roundToDouble() ? n.round().toString() : n.toString();
}

TemplateBlock? _database(Map<String, dynamic> m) {
  final d = m['database'] is Map ? (m['database'] as Map).cast<String, dynamic>() : m;
  var rawProps = _maps(d['properties']);
  if (rawProps.isEmpty) return null;
  // Notion needs exactly one title column, and it must come first. Respect the
  // model's own choice if it marked one; otherwise the first column is it.
  final titleAt = rawProps.indexWhere((p) => _propType(p['type']) == DbPropType.title);
  if (titleAt > 0) {
    rawProps = [
      rawProps[titleAt],
      ...rawProps.sublist(0, titleAt),
      ...rawProps.sublist(titleAt + 1),
    ];
  }

  final names = <String>{};
  final types = <DbPropType>[];
  final labels = <String>[];
  final options = <List<String>>[];
  for (var i = 0; i < rawProps.length && i < TemplateBlock.maxDbProperties; i++) {
    var name = _clean(rawProps[i]['name'], max: 60);
    if (name.isEmpty) name = 'Column ${i + 1}';
    var unique = name;
    for (var n = 2; !names.add(unique.toLowerCase()); n++) {
      unique = '$name $n';
    }
    var type = _propType(rawProps[i]['type']);
    if (i == 0) {
      type = DbPropType.title;
    } else if (type == DbPropType.title) {
      type = DbPropType.text;
    }
    labels.add(unique);
    types.add(type);
    options.add(
      type.hasOptions
          ? [
              for (final o in _splitOptions(
                _clean(rawProps[i]['options'], max: 1000),
              ).take(_maxOptions))
                o,
            ]
          : <String>[],
    );
  }

  // Rows, with each value coerced to what its column can hold.
  final rows = <Map<String, String>>[];
  for (final r in _maps(d['rows']).take(TemplateBlock.maxDbRows)) {
    final cells = <String, String>{};
    for (final c in _maps(r['cells'])) {
      cells[_clean(c['column'], max: 60).toLowerCase()] = _clean(c['value'], max: 500);
    }
    final row = <String, String>{};
    for (var i = 0; i < labels.length; i++) {
      final raw = cells[labels[i].toLowerCase()] ?? '';
      var v = raw;
      switch (types[i]) {
        case DbPropType.number:
          v = _normalizeNumber(raw);
        case DbPropType.checkbox:
          v =
              const {
                'true',
                'yes',
                'y',
                'x',
                '1',
                '✓',
                '✔',
                'done',
                'checked',
              }.contains(raw.toLowerCase())
              ? 'true'
              : 'false';
        case DbPropType.date:
          v = _normalizeDate(raw);
        case DbPropType.url:
          v = (Uri.tryParse(raw)?.hasScheme ?? false) ? raw : '';
        case DbPropType.select:
          v = _pickOption(raw, options[i]);
        case DbPropType.multiSelect:
          v = [
            for (final part in _splitOptions(raw)) _pickOption(part, options[i]),
          ].where((p) => p.isNotEmpty).join(', ');
        case DbPropType.title || DbPropType.text:
          break;
      }
      row[labels[i]] = v;
    }
    if (row.values.any((v) => v.isNotEmpty && v != 'false')) rows.add(row);
  }

  final props = <DbProperty>[];
  for (var i = 0; i < labels.length; i++) {
    var type = types[i];
    if (type.hasOptions && options[i].isEmpty) type = DbPropType.text; // nothing to choose from
    props.add(DbProperty.make(labels[i], type, options: options[i].join(', ')));
  }
  return TemplateBlock.database(_clean(d['title'], max: 100).ifEmpty('Table'), props, rows);
}

/// Matches [value] to an existing option (ignoring case), or adds it.
String _pickOption(String value, List<String> opts) {
  final v = value.trim();
  if (v.isEmpty) return '';
  for (final o in opts) {
    if (o.toLowerCase() == v.toLowerCase()) return o;
  }
  if (opts.length >= _maxOptions) return '';
  opts.add(v);
  return v;
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Builds a template from the model's JSON. Throws [AiFormatException] if
/// nothing usable came back.
AiPage aiJsonToTemplate(
  Map<String, dynamic> json, {
  required Set<String> allowedUrls,
  String coverUrl = '',
}) {
  final ctx = _Ctx(allowedUrls, _pageTheme(json['blocks']));
  final blocks = <TemplateBlock>[];
  for (final m in _maps(json['blocks'])) {
    if (blocks.length >= _maxTopBlocks) break;
    switch (_typeOf(m)) {
      case 'toggle':
        final children = _leafList(m['children'], ctx);
        blocks.add(
          TemplateBlock.toggle(
            _clean(m['text']).ifEmpty('Details'),
            children.isEmpty ? [TemplateBlock.paragraph('')] : children,
          ),
        );
      case 'columns':
        var cols = [for (final c in _maps(m['columns'])) _leafList(c['blocks'], ctx)];
        if (cols.isEmpty && m['children'] is List) {
          // The model put the content in "children": split it in two.
          final all = _leafList(m['children'], ctx);
          final mid = (all.length + 1) ~/ 2;
          cols = [all.sublist(0, mid), all.sublist(mid)];
        }
        if (cols.length > TemplateBlock.maxColumns) {
          cols = [...cols.take(2), cols.skip(2).expand((c) => c).toList()];
        }
        cols = [
          for (final c in cols) c.isEmpty ? [TemplateBlock.paragraph('')] : c,
        ];
        if (cols.length >= 2) {
          blocks.add(TemplateBlock.columns(cols));
        } else {
          for (final c in cols) {
            blocks.addAll(c.where((b) => !(b.type == BlockType.paragraph && b.text.isEmpty)));
          }
        }
      case 'database':
        final db = _database(m);
        if (db != null) blocks.add(db);
      default:
        final b = _leaf(m, ctx);
        if (b != null) blocks.add(b);
    }
  }
  if (blocks.isEmpty) {
    throw const AiFormatException(
      'The AI returned an empty page. Try describing what you want in more detail.',
    );
  }
  return AiPage(
    Template(
      title: _clean(json['title'], max: 150).ifEmpty('Untitled'),
      icon: _emoji(json['icon']) ?? '📄',
      coverUrl: coverUrl,
      blocks: blocks,
    ),
    _clean(json['summary'], max: 300),
  );
}

/// The current page as JSON in the same shape the model produces, so it can
/// be sent along with a request to change it.
Map<String, dynamic> templateToAiJson(Template t) {
  Map<String, dynamic> embed(TemplateBlock b) {
    final lib = WidgetLibrary.parse(b.text);
    if (lib == null) return {'type': 'embed', 'text': b.text};
    return {
      'type': 'embed',
      'widget': lib.widget.kind,
      'options': [
        for (final e in lib.options.entries) {'name': e.key, 'value': e.value},
      ],
    };
  }

  Map<String, dynamic> leaf(TemplateBlock b) => b.type == BlockType.embed
      ? embed(b)
      : {
          'type': b.type.name,
          if (b.text.isNotEmpty) 'text': b.text,
          if (b.type == BlockType.heading) 'level': b.level,
          if (b.type == BlockType.heading || b.type == BlockType.callout) 'color': b.color,
          if (b.type == BlockType.callout) 'emoji': b.emoji,
        };
  return {
    'title': t.title,
    'icon': t.icon,
    'blocks': [
      for (final b in t.blocks)
        switch (b.type) {
          BlockType.toggle => {
            ...leaf(b),
            'children': [for (final c in b.children) leaf(c)],
          },
          BlockType.columns => {
            'type': 'columns',
            'columns': [
              for (final col in b.columns)
                {
                  'blocks': [for (final c in col) leaf(c)],
                },
            ],
          },
          BlockType.database => {
            'type': 'database',
            'database': {
              'title': b.text,
              'properties': [
                for (final p in b.properties)
                  {
                    'name': p.name,
                    'type': p.type.name,
                    if (p.optionsText.isNotEmpty) 'options': p.optionsText,
                  },
              ],
              'rows': [
                for (final r in b.rows)
                  {
                    'cells': [
                      for (final p in b.properties)
                        if ((r.values[p.id] ?? '').isNotEmpty)
                          {'column': p.name, 'value': r.values[p.id]},
                    ],
                  },
              ],
            },
          },
          _ => leaf(b),
        },
    ],
  };
}

/// Pulls the JSON object out of a model reply. Handles ```json fences, text
/// before or after the object, `<think>` blocks, and output that was cut off
/// part-way (open strings and brackets are closed). Throws [AiFormatException].
Map<String, dynamic> extractJsonObject(String reply) {
  var s = reply.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
  if (fence != null) s = fence.group(1)!.trim();
  final start = s.indexOf('{');
  if (start < 0) {
    throw const AiFormatException("The AI didn't answer with a template. Please try again.");
  }
  s = s.substring(start);

  Object? tryDecode(String t) {
    try {
      return jsonDecode(t);
    } catch (_) {
      return null;
    }
  }

  var decoded = tryDecode(s);
  if (decoded == null) {
    final end = s.lastIndexOf('}');
    if (end > 0) decoded = tryDecode(s.substring(0, end + 1));
  }
  decoded ??= tryDecode(_closeOpenJson(s));
  if (decoded is! Map<String, dynamic>) {
    throw const AiFormatException("The AI's answer was cut off or malformed. Please try again.");
  }
  return decoded;
}

/// Closes an unterminated string and any open brackets, for truncated output.
String _closeOpenJson(String s) {
  final stack = <String>[];
  var inString = false, escaped = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    switch (c) {
      case '"':
        inString = true;
      case '{':
        stack.add('}');
      case '[':
        stack.add(']');
      case '}' || ']':
        if (stack.isNotEmpty) stack.removeLast();
    }
  }
  var out = s;
  if (inString) {
    out = out.endsWith(r'\') ? out.substring(0, out.length - 1) : out;
    out += '"';
  }
  out = out.replaceFirst(RegExp(r'[,:\s]+$'), '');
  if (out.endsWith('"') && RegExp(r'[{,]\s*"[^"]*"$').hasMatch(out)) {
    // A dangling key with no value: drop it.
    out = out.replaceFirst(RegExp(r',?\s*"[^"]*"$'), '');
  }
  return out + stack.reversed.join();
}
