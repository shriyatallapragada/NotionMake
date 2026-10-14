import '../../features/editor/models/template_model.dart';
import '../constants.dart';
import 'block_mapper.dart';
import 'database_mapper.dart';

/// Returns a user-facing description of the first thing Notion would reject,
/// or null if the template is fine to publish.
String? validateTemplate(Template t) {
  if (t.title.trim().isEmpty) return 'Give the page a title first.';
  final iconProblem = _emojiProblem(t.icon, 'The page icon');
  if (iconProblem != null) return iconProblem;
  final cover = t.coverUrl.trim();
  if (cover.isNotEmpty) {
    final u = Uri.tryParse(cover);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      return 'The cover image link must start with https://';
    }
  }
  for (var i = 0; i < t.blocks.length; i++) {
    final p = _check(t.blocks[i], 'Block ${i + 1}');
    if (p != null) return p;
  }
  return null;
}

/// Notion only accepts an emoji as an icon. Letters and digits are a typo.
String? _emojiProblem(String value, String what) {
  final v = value.trim();
  if (v.isEmpty) return null;
  if (v.runes.length > 8 || RegExp(r'[A-Za-z0-9]').hasMatch(v)) {
    return '$what must be a single emoji (or empty).';
  }
  return null;
}

String? _check(TemplateBlock b, String where) {
  switch (b.type) {
    case BlockType.callout:
      return _emojiProblem(b.emoji, "$where's icon");
    case BlockType.embed:
      return b.isValidEmbed ? null : '$where is a widget with a missing or non-https URL.';
    case BlockType.toggle:
      if (b.children.length > NotionConstants.maxChildrenPerRequest) {
        return '$where has too many blocks inside it (max ${NotionConstants.maxChildrenPerRequest}).';
      }
      return _checkAll(b.children, where);
    case BlockType.columns:
      if (b.columns.length < 2) return '$where needs at least 2 columns.';
      for (var c = 0; c < b.columns.length; c++) {
        if (blocksToNotion(b.columns[c]).isEmpty) {
          return '$where, column ${c + 1} is empty. Add some content to it.';
        }
        if (b.columns[c].length > NotionConstants.maxChildrenPerRequest) {
          return '$where, column ${c + 1} has too many blocks (max ${NotionConstants.maxChildrenPerRequest}).';
        }
        final p = _checkAll(b.columns[c], '$where, column ${c + 1}');
        if (p != null) return p;
      }
      return null;
    case BlockType.database:
      return _checkDatabase(b, where);
    default:
      return null;
  }
}

String? _checkDatabase(TemplateBlock b, String where) {
  final w = '$where (database "${b.text}")';
  final props = b.properties;
  if (props.isEmpty || props.first.type != DbPropType.title) {
    return '$w needs a Title column as its first column.';
  }
  if (props.length > TemplateBlock.maxDbProperties) {
    return '$w has too many columns (max ${TemplateBlock.maxDbProperties}).';
  }
  if (b.rows.length > TemplateBlock.maxDbRows) {
    return '$w has too many sample rows (max ${TemplateBlock.maxDbRows}).';
  }
  final names = <String>{};
  for (var i = 0; i < props.length; i++) {
    final p = props[i];
    final name = p.name.trim();
    if (name.isEmpty) return '$w: column ${i + 1} has no name.';
    if (!names.add(name.toLowerCase())) return '$w: two columns are named "$name".';
    if (i > 0 && p.type == DbPropType.title) return '$w: only the first column can be the Title.';
    if (p.type.hasOptions) {
      if (p.optionsText.trim().isEmpty) return '$w: "$name" needs at least one option.';
      if (p.options.length > 25) return '$w: "$name" has too many options (max 25).';
    }
  }
  for (var r = 0; r < b.rows.length; r++) {
    for (final p in props) {
      final v = (b.rows[r].values[p.id] ?? '').trim();
      if (v.isEmpty) continue;
      if (p.type == DbPropType.number && double.tryParse(v) == null) {
        return '$w, row ${r + 1}: "${p.name}" must be a number.';
      }
      if (p.type == DbPropType.date && !isValidDbDate(v)) {
        return '$w, row ${r + 1}: "${p.name}" must be a date like 2026-10-31.';
      }
      if (p.type == DbPropType.url && !(Uri.tryParse(v)?.hasScheme ?? false)) {
        return '$w, row ${r + 1}: "${p.name}" must be a link starting with https://';
      }
      if (p.type == DbPropType.select && !p.options.contains(v)) {
        return '$w, row ${r + 1}: "$v" is not one of the options for "${p.name}".';
      }
    }
  }
  return null;
}

String? _checkAll(List<TemplateBlock> list, String where) {
  for (var i = 0; i < list.length; i++) {
    final p = _check(list[i], '$where, item ${i + 1}');
    if (p != null) return p;
  }
  return null;
}
