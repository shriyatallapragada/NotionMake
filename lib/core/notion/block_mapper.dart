import '../../features/editor/models/template_model.dart';
import '../constants.dart';

typedef Json = Map<String, dynamic>;

/// Splits text into rich_text items of at most 2000 characters.
List<Json> richText(String text) {
  if (text.isEmpty) return [];
  final out = <Json>[];
  final runes = text.runes.toList();
  const n = NotionConstants.maxRichTextLength;
  for (var i = 0; i < runes.length; i += n) {
    final end = i + n < runes.length ? i + n : runes.length;
    out.add({
      'type': 'text',
      'text': {'content': String.fromCharCodes(runes.sublist(i, end))},
    });
  }
  return out;
}

Json _block(String type, Json content) => {'object': 'block', 'type': type, type: content};

List<Json> blocksToNotion(List<TemplateBlock> blocks) => blocks.expand(blockToNotion).toList();

/// One block can expand to several Notion blocks (list blocks: one per line).
List<Json> blockToNotion(TemplateBlock b) => switch (b.type) {
  BlockType.heading => () {
    final t = 'heading_${b.level.clamp(1, 3)}';
    return [
      _block(t, {'rich_text': richText(b.text), 'color': b.color}),
    ];
  }(),
  BlockType.paragraph => [
    _block('paragraph', {'rich_text': richText(b.text)}),
  ],
  BlockType.callout => [
    _block('callout', {
      'rich_text': richText(b.text),
      if (b.emoji.trim().isNotEmpty) 'icon': {'type': 'emoji', 'emoji': b.emoji.trim()},
      'color': b.color,
    }),
  ],
  BlockType.quote => [
    _block('quote', {'rich_text': richText(b.text)}),
  ],
  BlockType.todo => [
    for (final l in b.lines) _block('to_do', {'rich_text': richText(l), 'checked': false}),
  ],
  BlockType.bullet => [
    for (final l in b.lines) _block('bulleted_list_item', {'rich_text': richText(l)}),
  ],
  BlockType.divider => [_block('divider', {})],
  BlockType.embed => [
    _block('embed', {'url': b.text.trim()}),
  ],
  BlockType.toggle => [
    _block('toggle', {
      'rich_text': richText(b.text),
      if (b.children.isNotEmpty) 'children': blocksToNotion(b.children),
    }),
  ],
  // Databases are created by the publisher (see database_mapper.dart).
  BlockType.database => [],
  BlockType.columns => [
    _block('column_list', {
      'children': [
        for (final col in b.columns) _block('column', {'children': blocksToNotion(col)}),
      ],
    }),
  ],
};

/// Body for POST /v1/pages. Only the first chunk of blocks goes here; see
/// [chunkNotionBlocks] for the rest.
Json pagePayload(Template t, String parentId, List<Json> firstChildren) => {
  'parent': {'page_id': parentId},
  if (t.icon.trim().isNotEmpty) 'icon': {'type': 'emoji', 'emoji': t.icon.trim()},
  if (t.coverUrl.trim().isNotEmpty)
    'cover': {
      'type': 'external',
      'external': {'url': t.coverUrl.trim()},
    },
  'properties': {
    'title': {'title': richText(t.title)},
  },
  'children': firstChildren,
};

List<List<T>> chunkBlocks<T>(List<T> items, [int size = NotionConstants.maxChildrenPerRequest]) {
  final out = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    out.add(items.sublist(i, i + size > items.length ? items.length : i + size));
  }
  return out;
}

/// 1 for the block plus all nested blocks in its payload.
int notionWeight(Json block) {
  final content = block[block['type']];
  var n = 1;
  if (content is Map && content['children'] is List) {
    for (final c in content['children'] as List) {
      n += notionWeight(c as Json);
    }
  }
  return n;
}

/// Splits top-level blocks into requests that respect Notion's limits: at most
/// [maxSiblings] blocks per array and [maxTotal] blocks including nested ones.
List<List<Json>> chunkNotionBlocks(
  List<Json> blocks, {
  int maxSiblings = NotionConstants.maxChildrenPerRequest,
  int maxTotal = NotionConstants.maxBlocksPerRequest,
}) {
  final out = <List<Json>>[];
  var cur = <Json>[];
  var weight = 0;
  for (final b in blocks) {
    final w = notionWeight(b);
    if (cur.isNotEmpty && (cur.length >= maxSiblings || weight + w > maxTotal)) {
      out.add(cur);
      cur = [];
      weight = 0;
    }
    cur.add(b);
    weight += w;
  }
  if (cur.isNotEmpty) out.add(cur);
  return out;
}

/// Body for PATCH /v1/pages/{id}: the template's title, icon and cover, for
/// updating an existing page. Empty icons and covers are left unchanged.
Json pageDetailsPayload(Template t) => {
  'properties': {
    'title': {'title': richText(t.title)},
  },
  if (t.icon.trim().isNotEmpty) 'icon': {'type': 'emoji', 'emoji': t.icon.trim()},
  if (t.coverUrl.trim().isNotEmpty)
    'cover': {
      'type': 'external',
      'external': {'url': t.coverUrl.trim()},
    },
};
