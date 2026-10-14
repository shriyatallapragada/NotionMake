import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notion_make/core/notion/database_mapper.dart';
import 'package:notion_make/core/notion/notion_client.dart';
import 'package:notion_make/core/notion/page_publisher.dart';
import 'package:notion_make/core/notion/template_validation.dart';
import 'package:notion_make/data/template_files.dart';
import 'package:notion_make/features/editor/models/builtin_templates.dart';
import 'package:notion_make/features/editor/models/template_model.dart';

TemplateBlock sampleDb() => TemplateBlock.database(
  'Tasks',
  [
    DbProperty.make('Task', DbPropType.title),
    DbProperty.make('Priority', DbPropType.select, options: 'High, Low, high'),
    DbProperty.make('Tags', DbPropType.multiSelect, options: 'a, b'),
    DbProperty.make('Cost', DbPropType.number),
    DbProperty.make('Due', DbPropType.date),
    DbProperty.make('Done', DbPropType.checkbox),
    DbProperty.make('Link', DbPropType.url),
    DbProperty.make('Notes', DbPropType.text),
  ],
  [
    {
      'Task': 'A',
      'Priority': 'High',
      'Tags': 'a, b',
      'Cost': '3.5',
      'Due': '2026-10-31',
      'Done': 'true',
      'Link': 'https://x.y',
      'Notes': 'n',
    },
    {'Task': 'B'},
  ],
);

http.Response _json(int code, Object body) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

void main() {
  group('database payloads', () {
    test('schema maps every property type; options are de-duplicated', () {
      final p = databasePayload(sampleDb(), 'page1');
      expect(p['parent'], {'type': 'page_id', 'page_id': 'page1'});
      expect(p['is_inline'], true);
      final props = p['properties'] as Map;
      expect(props['Task'], {'title': {}});
      expect((props['Priority']['select']['options'] as List).map((o) => o['name']), [
        'High',
        'Low',
      ]);
      expect(props['Cost']['number']['format'], 'number');
      expect(props.keys, containsAll(['Tags', 'Due', 'Done', 'Link', 'Notes']));
    });

    test('row payload types values and omits empty ones', () {
      final db = sampleDb();
      final full = rowPayload(db, db.rows[0], 'db1');
      expect(full['parent'], {'database_id': 'db1'});
      final props = full['properties'] as Map;
      expect(props['Cost'], {'number': 3.5});
      expect(props['Done'], {'checkbox': true});
      expect(props['Due'], {
        'date': {'start': '2026-10-31'},
      });
      expect(props['Priority'], {
        'select': {'name': 'High'},
      });
      expect((props['Tags']['multi_select'] as List).length, 2);

      final sparse = rowPayload(db, db.rows[1], 'db1')['properties'] as Map;
      expect(sparse.keys, containsAll(['Task', 'Done'])); // title + checkbox always sent
      expect(sparse.containsKey('Cost'), false);
      expect(sparse['Done'], {'checkbox': false});
    });

    test('date validation rejects impossible dates', () {
      expect(isValidDbDate('2026-10-31'), true);
      expect(isValidDbDate('2026-02-31'), false);
      expect(isValidDbDate('10/31/2026'), false);
    });
  });

  group('publisher with databases', () {
    test('keeps the designed order: page, database, rows, then later blocks', () async {
      final calls = <String>[];
      var n = 0;
      final c = NotionClient(
        't',
        httpClient: MockClient((r) async {
          calls.add('${r.method} ${r.url.path}');
          n++;
          return _json(200, {'id': 'id$n', 'url': 'https://notion.so/p'});
        }),
      );
      final t = Template(
        title: 'T',
        blocks: [TemplateBlock.heading('Above'), sampleDb(), TemplateBlock.paragraph('Below')],
      );
      final seen = <String>[];
      await PagePublisher(c).publish(t, 'parent', onProgress: seen.add);
      expect(calls, [
        'POST /v1/pages', // page + "Above"
        'POST /v1/databases',
        'POST /v1/pages', // row 1
        'POST /v1/pages', // row 2
        'PATCH /v1/blocks/id1/children', // "Below" goes after the database
      ]);
      expect(seen.any((s) => s.contains('Adding rows')), true);
    });

    test('a database as the first block still creates the page first', () async {
      final calls = <String>[];
      final c = NotionClient(
        't',
        httpClient: MockClient((r) async {
          calls.add('${r.method} ${r.url.path}');
          return _json(200, {'id': 'x', 'url': 'u'});
        }),
      );
      await PagePublisher(c).publish(Template(title: 'T', blocks: [sampleDb()]), 'p');
      expect(calls.first, 'POST /v1/pages');
      expect(calls[1], 'POST /v1/databases');
    });

    test('row failure reports how many items are missing', () async {
      var n = 0;
      final c = NotionClient(
        't',
        httpClient: MockClient((r) async {
          n++;
          // page ok, database ok, first row fails
          return n <= 2
              ? _json(200, {'id': 'i$n', 'url': 'u'})
              : _json(400, {'code': 'validation_error', 'message': 'bad row'});
        }),
      );
      expect(
        PagePublisher(c).publish(Template(title: 'T', blocks: [sampleDb()]), 'p'),
        throwsA(isA<PartialPublishException>().having((e) => e.missingBlocks, 'missing', 2)),
      );
    });
  });

  group('validation', () {
    Template wrap(TemplateBlock b) => Template(title: 'x', blocks: [b]);

    test('built-in database templates validate', () {
      for (final b in builtinTemplates) {
        expect(validateTemplate(b.build()), isNull, reason: b.name);
      }
    });

    test('catches duplicate names, bad numbers, bad dates, bad select values', () {
      final dup = TemplateBlock.database('d', [
        DbProperty.make('A', DbPropType.title),
        DbProperty.make('a', DbPropType.text),
      ]);
      expect(validateTemplate(wrap(dup)), contains('two columns'));

      final props = [
        DbProperty.make('Name', DbPropType.title),
        DbProperty.make('N', DbPropType.number),
        DbProperty.make('D', DbPropType.date),
        DbProperty.make('S', DbPropType.select, options: 'x, y'),
      ];
      expect(
        validateTemplate(
          wrap(
            TemplateBlock.database('d', props, [
              {'N': 'abc'},
            ]),
          ),
        ),
        contains('must be a number'),
      );
      expect(
        validateTemplate(
          wrap(
            TemplateBlock.database('d', props, [
              {'D': '2026-02-31'},
            ]),
          ),
        ),
        contains('date'),
      );
      expect(
        validateTemplate(
          wrap(
            TemplateBlock.database('d', props, [
              {'S': 'z'},
            ]),
          ),
        ),
        contains('not one of the options'),
      );
    });

    test('select needs options; first column must be the title', () {
      final noOpts = TemplateBlock.database('d', [
        DbProperty.make('Name', DbPropType.title),
        DbProperty.make('S', DbPropType.select),
      ]);
      expect(validateTemplate(wrap(noOpts)), contains('at least one option'));
      final noTitle = TemplateBlock.database('d', [DbProperty.make('X', DbPropType.text)]);
      expect(validateTemplate(wrap(noTitle)), contains('Title column'));
    });
  });

  group('model rules', () {
    test('databases cannot be nested, and import enforces it', () {
      final nested = {
        'blocks': [
          {
            'type': 'toggle',
            'children': [
              {'type': 'database'},
            ],
          },
        ],
      };
      expect(() => TemplateFiles.parse(jsonEncode(nested)), throwsFormatException);
    });

    test('import limits rows and columns', () {
      final rows = {
        'blocks': [
          {
            'type': 'database',
            'rows': List.generate(51, (_) => {'values': {}}),
          },
        ],
      };
      expect(() => TemplateFiles.parse(jsonEncode(rows)), throwsFormatException);
      final props = {
        'blocks': [
          {
            'type': 'database',
            'properties': List.generate(21, (i) => {'name': 'p\$i', 'type': 'text'}),
          },
        ],
      };
      expect(() => TemplateFiles.parse(jsonEncode(props)), throwsFormatException);
      expect(
        () => TemplateFiles.parse(
          jsonEncode({
            'blocks': [
              {
                'type': 'database',
                'properties': [
                  {'type': 'bogus'},
                ],
              },
            ],
          }),
        ),
        throwsFormatException,
      );
    });

    test('round trip keeps columns, options and row values', () {
      final t = Template(title: 'T', blocks: [sampleDb()]);
      final back = TemplateFiles.parse(jsonEncode(t.toFileJson())).blocks.single;
      expect(back.properties.map((p) => p.name), t.blocks.single.properties.map((p) => p.name));
      expect(back.properties[1].optionsText, 'High, Low, high');
      final costId = back.properties.firstWhere((p) => p.name == 'Cost').id;
      expect(back.rows.first.values[costId], '3.5');
    });

    test('duplicating a database gives rows new ids', () {
      final db = sampleDb();
      final copy = db.withFreshIds();
      expect(copy.rows.first.id, isNot(db.rows.first.id));
      expect(copy.rows.first.values, db.rows.first.values);
    });
  });
}
