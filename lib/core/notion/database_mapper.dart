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

// ---- progress bar: a small linked database that Notion calculates itself ----
//
// For a database with a checkbox column, the app also creates a "progress"
// database above it: one row, linked to every task, with Notion rollups that
// count the checked boxes. Notion recalculates them whenever a box is ticked,
// so the bar is live on every device and nothing is hosted anywhere.

/// Property names in the progress database.
const progressGoal = 'Goal';
const progressTasks = 'Tasks';
const progressDone = 'Done';
const progressTotal = 'Total';
const progressPercent = 'Percent';
const progressBar = 'Progress';

/// The progress database starts with just its title column; the link to the
/// tasks and the rollups are added once the tasks database exists.
Json progressDatabasePayload(TemplateBlock db, String pageId) => {
  'parent': {'type': 'page_id', 'page_id': pageId},
  'is_inline': true,
  'title': richText('${db.text.trim().isEmpty ? 'Tasks' : db.text.trim()} progress'),
  'properties': {
    progressGoal: {'title': {}},
  },
};

/// Step 1 after both databases exist: a two-way relation between the progress
/// row and the tasks. Two-way adds a column to the tasks table, so a task added
/// later in Notion can be counted by picking its goal there.
Json progressRelationPatch(String tasksDatabaseId) => {
  'properties': {
    progressTasks: {
      'relation': {'database_id': tasksDatabaseId, 'type': 'dual_property', 'dual_property': {}},
    },
  },
};

/// Step 2: rollups over that relation. Plain rollups are the most dependable
/// part, so the percentage is a rollup too, not a formula.
Json progressRollupsPatch(TemplateBlock db) {
  final check = db.progressColumn!.name.trim();
  final title = db.properties.first.name.trim();
  Json rollup(String property, String fn) => {
    'rollup': {
      'relation_property_name': progressTasks,
      'rollup_property_name': property,
      'function': fn,
    },
  };
  return {
    'properties': {
      progressDone: rollup(check, 'checked'),
      progressTotal: rollup(title, 'count'),
      progressPercent: rollup(check, 'percent_checked'),
    },
  };
}

const _bar = '██████████';
const _gap = '░░░░░░░░░░';

/// Step 3 (best effort): a text bar such as "████░░░░░░  40%". Two spellings,
/// because Notion's formula language has changed over time; the first that the
/// workspace accepts is used.
List<String> progressFormulaExpressions() {
  const n = 'round(prop("$progressDone") / prop("$progressTotal") * 10)';
  const pct = 'format(round(prop("$progressDone") / prop("$progressTotal") * 100))';
  return [
    'if(prop("$progressTotal") == 0, "No tasks yet", slice("$_bar", 0, $n) + slice("$_gap", 0, 10 - $n) + "  " + $pct + "%")',
    'if(prop("$progressTotal") == 0, "No tasks yet", concat(slice("$_bar", 0, $n), slice("$_gap", 0, 10 - $n), "  ", $pct, "%"))',
  ];
}

Json progressFormulaPatch(String expression) => {
  'properties': {
    progressBar: {
      'formula': {'expression': expression},
    },
  },
};

/// The single row of the progress database, linked to every task.
Json progressRowPayload(TemplateBlock db, String progressDatabaseId, List<String> taskPageIds) => {
  'parent': {'database_id': progressDatabaseId},
  'properties': {
    progressGoal: {'title': richText(db.text.trim().isEmpty ? 'Tasks' : db.text.trim())},
    progressTasks: {
      'relation': [
        for (final id in taskPageIds) {'id': id},
      ],
    },
  },
};
