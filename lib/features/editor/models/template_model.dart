import '../../../core/constants.dart';

enum BlockType {
  heading,
  paragraph,
  callout,
  todo,
  bullet,
  quote,
  divider,
  embed,
  toggle,
  columns,
  database,
}

extension BlockTypeInfo on BlockType {
  String get label => switch (this) {
    BlockType.heading => 'Heading',
    BlockType.paragraph => 'Text',
    BlockType.callout => 'Callout',
    BlockType.todo => 'To-do list',
    BlockType.bullet => 'Bullet list',
    BlockType.quote => 'Quote',
    BlockType.divider => 'Divider',
    BlockType.embed => 'Widget / embed',
    BlockType.toggle => 'Toggle (collapsible)',
    BlockType.columns => 'Columns',
    BlockType.database => 'Database (table)',
  };

  /// Containers can't be nested: Notion allows only 2 levels of nesting per
  /// request, and this keeps every page publishable in one valid request.
  bool get isContainer => this == BlockType.toggle || this == BlockType.columns;

  /// Blocks that may only appear at the top level of a page. Databases are
  /// created as children of the page itself, so they can't sit in a column.
  bool get topLevelOnly => isContainer || this == BlockType.database;
}

int _idCounter = 0;
String newBlockId() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

enum DbPropType { title, text, number, select, multiSelect, checkbox, date, url }

extension DbPropTypeInfo on DbPropType {
  String get label => switch (this) {
    DbPropType.title => 'Title',
    DbPropType.text => 'Text',
    DbPropType.number => 'Number',
    DbPropType.select => 'Select',
    DbPropType.multiSelect => 'Multi-select',
    DbPropType.checkbox => 'Checkbox',
    DbPropType.date => 'Date',
    DbPropType.url => 'Link',
  };

  bool get hasOptions => this == DbPropType.select || this == DbPropType.multiSelect;
}

/// A column of a database. Row values are keyed by [id], so renaming a column
/// never loses data.
class DbProperty {
  final String id;
  final String name;
  final DbPropType type;

  /// Raw comma-separated option names for select types. Kept as typed so the
  /// editor field doesn't rewrite what the user is typing.
  final String optionsText;

  const DbProperty({
    required this.id,
    required this.name,
    required this.type,
    this.optionsText = '',
  });

  factory DbProperty.make(String name, DbPropType type, {String options = ''}) =>
      DbProperty(id: newBlockId(), name: name, type: type, optionsText: options);

  /// Distinct, trimmed option names.
  List<String> get options {
    final seen = <String>{};
    return [
      for (final o in optionsText.split(','))
        if (o.trim().isNotEmpty && seen.add(o.trim().toLowerCase())) o.trim(),
    ];
  }

  DbProperty copyWith({String? name, DbPropType? type, String? optionsText}) => DbProperty(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    optionsText: optionsText ?? this.optionsText,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    if (optionsText.isNotEmpty) 'options': optionsText,
  };

  factory DbProperty.fromJson(Map<String, dynamic> j) {
    final type = DbPropType.values.asNameMap()[j['type']];
    if (type == null) throw FormatException('Unknown column type "${j['type']}"');
    return DbProperty(
      id: (j['id'] as String?) ?? newBlockId(),
      name: (j['name'] as String?) ?? '',
      type: type,
      optionsText: (j['options'] as String?) ?? '',
    );
  }
}

/// A sample row. Values are strings: checkbox "true"/"false", dates
/// "yyyy-MM-dd", multi-select comma separated.
class DbRow {
  final String id;
  final Map<String, String> values;
  const DbRow({required this.id, this.values = const {}});

  DbRow withValue(String propId, String value) => DbRow(id: id, values: {...values, propId: value});

  Map<String, dynamic> toJson() => {'values': values};

  factory DbRow.fromJson(Map<String, dynamic> j) {
    final v = j['values'];
    if (v != null && v is! Map) throw const FormatException('Invalid database row');
    return DbRow(
      id: newBlockId(),
      values: {for (final e in (v as Map? ?? {}).entries) '${e.key}': '${e.value}'},
    );
  }
}

/// One block in a template. A single immutable class keeps copying, undo and
/// JSON simple. Which fields matter depends on [type]:
/// - heading: [level], [text], [color] (text color)
/// - callout: [text], [emoji], [color] (background color)
/// - todo / bullet: [text] holds one item per line
/// - embed: [text] holds the URL
/// - toggle: [text] is the title, [children] its content
/// - columns: [columns] holds 2-3 lists of blocks
/// - database: [text] is the title, [properties] the columns and [rows] sample rows
class TemplateBlock {
  static const maxColumns = 3;
  static const maxDbProperties = 20;
  static const maxDbRows = 50;

  final String id;
  final BlockType type;
  final String text;
  final int level;
  final String color;
  final String emoji;
  final List<TemplateBlock> children;
  final List<List<TemplateBlock>> columns;
  final List<DbProperty> properties;
  final List<DbRow> rows;

  const TemplateBlock({
    required this.id,
    required this.type,
    this.text = '',
    this.level = 1,
    this.color = 'default',
    this.emoji = '✨',
    this.children = const [],
    this.columns = const [],
    this.properties = const [],
    this.rows = const [],
  });

  factory TemplateBlock.heading(String text, {int level = 1, String color = 'default'}) =>
      TemplateBlock(
        id: newBlockId(),
        type: BlockType.heading,
        text: text,
        level: level,
        color: color,
      );
  factory TemplateBlock.paragraph(String text) =>
      TemplateBlock(id: newBlockId(), type: BlockType.paragraph, text: text);
  factory TemplateBlock.callout(
    String text, {
    String emoji = '✨',
    String color = 'gray_background',
  }) => TemplateBlock(
    id: newBlockId(),
    type: BlockType.callout,
    text: text,
    emoji: emoji,
    color: color,
  );
  factory TemplateBlock.todo(String items) =>
      TemplateBlock(id: newBlockId(), type: BlockType.todo, text: items);
  factory TemplateBlock.bullet(String items) =>
      TemplateBlock(id: newBlockId(), type: BlockType.bullet, text: items);
  factory TemplateBlock.quote(String text) =>
      TemplateBlock(id: newBlockId(), type: BlockType.quote, text: text);
  factory TemplateBlock.divider() => TemplateBlock(id: newBlockId(), type: BlockType.divider);
  factory TemplateBlock.embed(String url) =>
      TemplateBlock(id: newBlockId(), type: BlockType.embed, text: url);
  factory TemplateBlock.toggle(String title, List<TemplateBlock> children) =>
      TemplateBlock(id: newBlockId(), type: BlockType.toggle, text: title, children: children);
  factory TemplateBlock.columns(List<List<TemplateBlock>> columns) =>
      TemplateBlock(id: newBlockId(), type: BlockType.columns, columns: columns);

  /// [rows] are given as {column name: value} for convenience.
  factory TemplateBlock.database(
    String title,
    List<DbProperty> props, [
    List<Map<String, String>> rows = const [],
  ]) {
    final byName = {for (final p in props) p.name: p.id};
    return TemplateBlock(
      id: newBlockId(),
      type: BlockType.database,
      text: title,
      properties: props,
      rows: [
        for (final r in rows)
          DbRow(
            id: newBlockId(),
            values: {
              for (final e in r.entries)
                if (byName.containsKey(e.key)) byName[e.key]!: e.value,
            },
          ),
      ],
    );
  }

  /// A sensible new block of [type].
  factory TemplateBlock.blank(BlockType type) => switch (type) {
    BlockType.heading => TemplateBlock.heading('New heading', level: 2),
    BlockType.paragraph => TemplateBlock.paragraph(''),
    BlockType.callout => TemplateBlock.callout(''),
    BlockType.todo => TemplateBlock.todo('Task'),
    BlockType.bullet => TemplateBlock.bullet('Item'),
    BlockType.quote => TemplateBlock.quote(''),
    BlockType.divider => TemplateBlock.divider(),
    BlockType.embed => TemplateBlock.embed(''),
    BlockType.toggle => TemplateBlock.toggle('Toggle', [TemplateBlock.paragraph('')]),
    BlockType.columns => TemplateBlock.columns([
      [TemplateBlock.paragraph('')],
      [TemplateBlock.paragraph('')],
    ]),
    BlockType.database => TemplateBlock.database(
      'Tasks',
      [
        DbProperty.make('Name', DbPropType.title),
        DbProperty.make('Status', DbPropType.select, options: 'To do, Doing, Done'),
        DbProperty.make('Due', DbPropType.date),
      ],
      [
        {'Name': 'First task', 'Status': 'To do'},
      ],
    ),
  };

  TemplateBlock copyWith({
    String? id,
    String? text,
    int? level,
    String? color,
    String? emoji,
    List<TemplateBlock>? children,
    List<List<TemplateBlock>>? columns,
    List<DbProperty>? properties,
    List<DbRow>? rows,
  }) => TemplateBlock(
    id: id ?? this.id,
    type: type,
    text: text ?? this.text,
    level: level ?? this.level,
    color: color ?? this.color,
    emoji: emoji ?? this.emoji,
    children: children ?? this.children,
    columns: columns ?? this.columns,
    properties: properties ?? this.properties,
    rows: rows ?? this.rows,
  );

  /// A deep copy where this block and all descendants get new ids.
  TemplateBlock withFreshIds() => copyWith(
    id: newBlockId(),
    children: children.withFreshIds(),
    columns: [for (final c in columns) c.withFreshIds()],
    rows: [for (final r in rows) DbRow(id: newBlockId(), values: r.values)],
  );

  /// Non-empty lines, for list blocks.
  List<String> get lines =>
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  bool get isValidEmbed {
    final u = Uri.tryParse(text.trim());
    return u != null && u.scheme == 'https' && u.host.isNotEmpty;
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'text': text,
    'level': level,
    'color': color,
    'emoji': emoji,
    if (children.isNotEmpty) 'children': [for (final b in children) b.toJson()],
    if (columns.isNotEmpty)
      'columns': [
        for (final c in columns) [for (final b in c) b.toJson()],
      ],
    if (properties.isNotEmpty) 'properties': [for (final p in properties) p.toJson()],
    if (rows.isNotEmpty) 'rows': [for (final r in rows) r.toJson()],
  };

  /// Parses a block. [depth] 0 is top level; containers are only allowed there.
  /// Throws [FormatException] on bad input.
  factory TemplateBlock.fromJson(Map<String, dynamic> j, {int depth = 0}) {
    final name = j['type'];
    final type = BlockType.values.asNameMap()[name];
    if (type == null) throw FormatException('Unknown block type "$name"');
    if (type.topLevelOnly && depth > 0) {
      throw const FormatException(
        'Toggles, columns and databases can only be placed at the top level of a page',
      );
    }
    List<TemplateBlock> parse(Object? raw) => [
      for (final b in (raw as List? ?? []))
        TemplateBlock.fromJson(b as Map<String, dynamic>, depth: depth + 1),
    ];
    final cols = [for (final c in (j['columns'] as List? ?? [])) parse(c)];
    if (cols.length > maxColumns) throw const FormatException('Too many columns');
    final props = [
      for (final p in (j['properties'] as List? ?? []))
        DbProperty.fromJson(p as Map<String, dynamic>),
    ];
    final rows = [
      for (final r in (j['rows'] as List? ?? [])) DbRow.fromJson(r as Map<String, dynamic>),
    ];
    if (props.length > maxDbProperties) throw const FormatException('Too many database columns');
    if (rows.length > maxDbRows) throw const FormatException('Too many database rows');
    return TemplateBlock(
      id: newBlockId(),
      type: type,
      text: (j['text'] as String?) ?? '',
      level: ((j['level'] as num?)?.toInt() ?? 1).clamp(1, 3),
      color: (j['color'] as String?) ?? 'default',
      emoji: (j['emoji'] as String?) ?? '✨',
      children: parse(j['children']),
      columns: cols,
      properties: props,
      rows: rows,
    );
  }
}

/// Immutable edits on a tree of blocks (top level, toggle children, columns).
extension BlockTree on List<TemplateBlock> {
  List<TemplateBlock> withFreshIds() => [for (final b in this) b.withFreshIds()];

  /// Applies [f] to every block, parents before children.
  List<TemplateBlock> mapAll(TemplateBlock Function(TemplateBlock) f) => [
    for (final b0 in this)
      () {
        final b = f(b0);
        return b.copyWith(
          children: b.children.mapAll(f),
          columns: [for (final c in b.columns) c.mapAll(f)],
        );
      }(),
  ];

  /// Replaces the block with [id] by the blocks [replace] returns (none =
  /// delete, two = duplicate). Searches nested lists too.
  List<TemplateBlock> edit(String id, List<TemplateBlock> Function(TemplateBlock) replace) => [
    for (final b in this)
      if (b.id == id)
        ...replace(b)
      else
        b.copyWith(
          children: b.children.edit(id, replace),
          columns: [for (final c in b.columns) c.edit(id, replace)],
        ),
  ];

  /// Moves the block with [id] by [delta] positions among its siblings.
  List<TemplateBlock> move(String id, int delta) {
    final i = indexWhere((b) => b.id == id);
    if (i >= 0) {
      final j = i + delta;
      if (j < 0 || j >= length) return this;
      final list = [...this];
      list.insert(j, list.removeAt(i));
      return list;
    }
    return [
      for (final b in this)
        b.copyWith(
          children: b.children.move(id, delta),
          columns: [for (final c in b.columns) c.move(id, delta)],
        ),
    ];
  }

  /// Number of blocks including all descendants.
  int get totalCount => fold(
    0,
    (n, b) => n + 1 + b.children.totalCount + b.columns.fold(0, (m, c) => m + c.totalCount),
  );
}

class Template {
  final String title;
  final String icon; // emoji
  final String coverUrl;
  final List<TemplateBlock> blocks;
  const Template({
    required this.title,
    this.icon = '📄',
    this.coverUrl = '',
    this.blocks = const [],
  });

  Template copyWith({String? title, String? icon, String? coverUrl, List<TemplateBlock>? blocks}) =>
      Template(
        title: title ?? this.title,
        icon: icon ?? this.icon,
        coverUrl: coverUrl ?? this.coverUrl,
        blocks: blocks ?? this.blocks,
      );

  /// Recolors headings and callouts (including nested ones) to match [theme].
  Template withTheme(TemplateTheme theme) => copyWith(
    blocks: blocks.mapAll(
      (b) => switch (b.type) {
        BlockType.heading => b.copyWith(color: theme.heading),
        BlockType.callout => b.copyWith(color: theme.callout),
        _ => b,
      },
    ),
  );

  /// Copy with fresh block ids, so loaded templates never share ids.
  Template fresh() => copyWith(blocks: blocks.withFreshIds());

  static const _format = 'notionmake-template';

  Map<String, dynamic> toJson() => {
    'title': title,
    'icon': icon,
    'coverUrl': coverUrl,
    'blocks': [for (final b in blocks) b.toJson()],
  };

  /// JSON for a shareable file.
  Map<String, dynamic> toFileJson() => {'format': _format, 'version': 1, ...toJson()};

  /// Throws [FormatException] if the data isn't a valid template.
  factory Template.fromJson(Map<String, dynamic> j) {
    final f = j['format'];
    if (f != null && f != _format) throw const FormatException('Not a NotionMake template');
    final raw = j['blocks'];
    if (raw != null && raw is! List) throw const FormatException('Invalid blocks');
    return Template(
      title: (j['title'] as String?) ?? 'Untitled',
      icon: (j['icon'] as String?) ?? '📄',
      coverUrl: (j['coverUrl'] as String?) ?? '',
      blocks: [
        for (final b in (raw as List? ?? [])) TemplateBlock.fromJson(b as Map<String, dynamic>),
      ],
    );
  }
}
