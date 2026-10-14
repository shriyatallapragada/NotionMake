import '../../features/editor/models/template_model.dart';
import 'block_mapper.dart';

final _dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isValidDbDate(String v) {
  if (!_dateRe.hasMatch(v)) return false;
  final d = DateTime.tryParse(v);
  // DateTime rolls 2026-02-31 over to March, so compare the round trip.
  return d != null && d.toIso8601String().startsWith(v);
}

Json _schema(DbProperty p) => switch (p.type) {
  DbPropType.title => {'title': {}},
  DbPropType.text => {'rich_text': {}},
  DbPropType.number => {
    'number': {'format': 'number'},
  },
  DbPropType.select => {
    'select': {
      'options': [
        for (final o in p.options) {'name': o},
      ],
    },
  },
  DbPropType.multiSelect => {
    'multi_select': {
      'options': [
        for (final o in p.options) {'name': o},
      ],
    },
  },
  DbPropType.checkbox => {'checkbox': {}},
  DbPropType.date => {'date': {}},
  DbPropType.url => {'url': {}},
};

/// Body for POST /v1/databases, creating an inline database inside [pageId].
Json databasePayload(TemplateBlock db, String pageId) => {
  'parent': {'type': 'page_id', 'page_id': pageId},
  'is_inline': true,
  'title': richText(db.text),
  'properties': {for (final p in db.properties) p.name.trim(): _schema(p)},
};

/// Body for POST /v1/pages creating one sample row. Empty values are omitted.
Json rowPayload(TemplateBlock db, DbRow row, String databaseId) {
  final props = <String, Json>{};
  for (final p in db.properties) {
    final v = (row.values[p.id] ?? '').trim();
    final key = p.name.trim();
    switch (p.type) {
      case DbPropType.title:
        props[key] = {'title': richText(v)};
      case DbPropType.text:
        if (v.isNotEmpty) props[key] = {'rich_text': richText(v)};
      case DbPropType.number:
        final n = double.tryParse(v);
        if (n != null) props[key] = {'number': n};
      case DbPropType.select:
        if (v.isNotEmpty) {
          props[key] = {
            'select': {'name': v},
          };
        }
      case DbPropType.multiSelect:
        final names = [
          for (final n in v.split(','))
            if (n.trim().isNotEmpty) {'name': n.trim()},
        ];
        if (names.isNotEmpty) props[key] = {'multi_select': names};
      case DbPropType.checkbox:
        props[key] = {'checkbox': v == 'true'};
      case DbPropType.date:
        if (v.isNotEmpty) {
          props[key] = {
            'date': {'start': v},
          };
        }
      case DbPropType.url:
        if (v.isNotEmpty) props[key] = {'url': v};
    }
  }
  return {
    'parent': {'database_id': databaseId},
    'properties': props,
  };
}
