import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notion_make/core/notion/database_mapper.dart';
import 'package:notion_make/core/notion/notion_client.dart';
import 'package:notion_make/core/notion/page_publisher.dart';
import 'package:notion_make/core/notion/template_validation.dart';
import 'package:notion_make/features/ai/ai_convert.dart';
import 'package:notion_make/features/ai/ai_schema.dart';
import 'package:notion_make/features/editor/models/builtin_templates.dart';
import 'package:notion_make/features/editor/models/template_model.dart';
import 'package:notion_make/features/editor/widgets/database_editor.dart';

TemplateBlock tasks({String progress = 'Done'}) => TemplateBlock.database(
  'Exam prep',
  [DbProperty.make('Task', DbPropType.title), DbProperty.make('Done', DbPropType.checkbox)],
  [
    {'Task': 'Read', 'Done': 'true'},
    {'Task': 'Write', 'Done': 'false'},
  ],
  progress,
);

typedef Call = ({String method, String path, Map<String, dynamic> body});

void main() {
  group('model', () {
    test('the progress column is found by id and checked against its type', () {
      final b = tasks();
      expect(b.progressColumn!.name, 'Done');
      expect(b.progressCounts, (done: 1, total: 2));
      expect(tasks(progress: '').progressColumn, isNull);
      expect(tasks(progress: 'Task').progressColumn, isNull); // not a checkbox column
      expect(tasks(progress: 'Nope').progressColumn, isNull);
      // deleting the column or changing its type quietly turns the bar off
      final removed = b.copyWith(properties: [b.properties.first]);
      expect(removed.progressColumn, isNull);
      final retyped = b.copyWith(
        properties: [
          b.properties.first,
          b.properties[1].copyWith(type: DbPropType.text),
        ],
      );
      expect(retyped.progressColumn, isNull);
    });

    test('survives JSON, copying and fresh ids', () {
      final b = tasks();
      final back = TemplateBlock.fromJson(b.toJson());
      expect(back.progressColumn?.name, 'Done');
      expect(b.withFreshIds().progressColumn?.name, 'Done');
      expect(b.copyWith(text: 'x').progress, b.progress);
    });

    test('the Task Tracker starter has a progress bar on Done', () {
      final t = builtinTemplates.firstWhere((x) => x.name == 'Task Tracker').build();
      expect(t.blocks.firstWhere((b) => b.type == BlockType.database).progressColumn?.name, 'Done');
      expect(validateTemplate(t), isNull);
    });
  });

  group('Notion requests', () {
    test('progress database starts with just a title column', () {
      final p = progressDatabasePayload(tasks(), 'page1');
      expect(p['parent'], {'type': 'page_id', 'page_id': 'page1'});
      expect(p['is_inline'], true);
      expect(jsonEncode(p['title']), contains('Exam prep progress'));
      expect(p['properties'], {
        'Goal': {'title': {}},
      });
    });

    test('relation and rollup shapes match the Notion API', () {
      final rel = progressRelationPatch('tasksDb')['properties']['Tasks']['relation'] as Map;
      expect(rel, {'database_id': 'tasksDb', 'type': 'dual_property', 'dual_property': {}});

      final b = TemplateBlock.database(
        't',
        [
          DbProperty.make('Item', DbPropType.title),
          DbProperty.make('Finished', DbPropType.checkbox),
        ],
        [],
        'Finished',
      );
      final r = progressRollupsPatch(b)['properties'] as Map;
      expect(r['Done'], {
        'rollup': {
          'relation_property_name': 'Tasks',
          'rollup_property_name': 'Finished',
          'function': 'checked',
        },
      });
      expect(r['Total']['rollup'], {
        'relation_property_name': 'Tasks',
        'rollup_property_name': 'Item',
        'function': 'count',
      });
      expect(r['Percent']['rollup']['function'], 'percent_checked');
    });

    test('both formula spellings are balanced and read the Done and Total columns', () {
      final all = progressFormulaExpressions();
      expect(all.length, 2);
      for (final e in all) {
        expect(e, contains('prop("Done")'));
        expect(e, contains('prop("Total")'));
        expect(e.split('(').length, e.split(')').length, reason: 'unbalanced parentheses in: $e');
        expect(e.split('"').length.isOdd, true, reason: 'unbalanced quotes in: $e');
      }
      expect(all[1], contains('concat('));
      expect(
        progressFormulaPatch(all[0])['properties']['Progress']['formula']['expression'],
        all[0],
      );
    });

    test('the progress row links every task', () {
      final p = progressRowPayload(tasks(), 'progDb', ['a', 'b']);
      expect(p['parent'], {'database_id': 'progDb'});
      expect(p['properties']['Tasks']['relation'], [
        {'id': 'a'},
        {'id': 'b'},
      ]);
      expect(jsonEncode(p['properties']['Goal']), contains('Exam prep'));
    });
  });

  group('publisher', () {
    /// Fake Notion. [fail] returns a status for a call to simulate an error.
    ({PagePublisher pub, List<Call> calls}) fake({int? Function(Call call)? fail}) {
      final calls = <Call>[];
      var n = 0;
      final client = NotionClient(
        't',
        retryBase: Duration.zero,
        httpClient: MockClient((r) async {
          final call = (
            method: r.method,
            path: r.url.path.replaceFirst('/v1', ''),
            body: r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>,
          );
          calls.add(call);
          final status = fail?.call(call);
          if (status != null) {
            return http.Response(
              jsonEncode({
                'code': status == 401 ? 'unauthorized' : 'validation_error',
                'message': 'nope',
              }),
              status,
            );
          }
          n++;
          return http.Response(jsonEncode({'id': 'id$n', 'url': 'https://notion.so/p'}), 200);
        }),
      );
      return (pub: PagePublisher(client), calls: calls);
    }

    Template page() => Template(
      title: 'T',
      blocks: [TemplateBlock.heading('H'), tasks(), TemplateBlock.paragraph('after')],
    );

    List<String> summary(List<Call> c) => [
      for (final x in c) '${x.method} ${x.path.replaceAll(RegExp(r'id\d+'), 'ID')}',
    ];

    test('creates the progress table first, then the tasks, then links them', () async {
      final f = fake();
      final r = await f.pub.publish(page(), 'parent');
      expect(r.warnings, isEmpty);
      expect(summary(f.calls), [
        'POST /pages', //                          page + heading
        'POST /databases', //                      progress table (above)
        'POST /databases', //                      tasks table
        'POST /pages', //                          task 1
        'POST /pages', //                          task 2
        'PATCH /databases/ID', //                  relation
        'PATCH /databases/ID', //                  rollups
        'PATCH /databases/ID', //                  formula
        'POST /pages', //                          progress row
        'PATCH /blocks/ID/children', //            the paragraph after, still in order
      ]);
      // Ids flow through correctly: page id1, progress db id2, tasks db id3, tasks id4 + id5.
      expect(f.calls[1].body['title'].toString(), contains('progress'));
      expect(f.calls[5].path, '/databases/id2');
      expect(f.calls[5].body['properties']['Tasks']['relation']['database_id'], 'id3');
      expect(f.calls[8].body['parent'], {'database_id': 'id2'});
      expect(f.calls[8].body['properties']['Tasks']['relation'], [
        {'id': 'id4'},
        {'id': 'id5'},
      ]);
    });

    test('a database without a progress bar makes no extra calls', () async {
      final f = fake();
      await f.pub.publish(
        Template(
          title: 'T',
          blocks: [tasks(progress: '')],
        ),
        'p',
      );
      expect(summary(f.calls), ['POST /pages', 'POST /databases', 'POST /pages', 'POST /pages']);
    });

    test('if Notion rejects the first formula spelling, the second is tried', () async {
      var formulaCalls = 0;
      final f = fake(
        fail: (c) {
          if (c.body['properties'] is Map &&
              (c.body['properties'] as Map).containsKey('Progress')) {
            return ++formulaCalls == 1 ? 400 : null;
          }
          return null;
        },
      );
      final r = await f.pub.publish(page(), 'parent');
      expect(formulaCalls, 2);
      expect(r.warnings, isEmpty);
      expect(
        summary(f.calls).where((s) => s.startsWith('PATCH /databases')).length,
        4,
      ); // relation, rollups, 2 formulas
    });

    test(
      'if the text bar is refused both ways, it is a warning and everything else still works',
      () async {
        final f = fake(
          fail: (c) =>
              c.body['properties'] is Map && (c.body['properties'] as Map).containsKey('Progress')
              ? 400
              : null,
        );
        final r = await f.pub.publish(page(), 'parent');
        expect(r.warnings.single, allOf(contains('Percent'), contains('Show as')));
        final s = summary(f.calls);
        expect(s.last, 'PATCH /blocks/ID/children'); // the rest of the page was published
        expect(s.where((x) => x == 'POST /pages').length, 4); // page, 2 tasks, progress row
      },
    );

    test(
      'if linking the tasks fails, it is a warning and the rest of the page continues',
      () async {
        final f = fake(
          fail: (c) =>
              c.body['properties'] is Map &&
                  (c.body['properties'] as Map).containsKey('Tasks') &&
                  c.method == 'PATCH'
              ? 400
              : null,
        );
        final r = await f.pub.publish(page(), 'parent');
        expect(r.warnings.single, contains('could not be linked'));
        expect(summary(f.calls).last, 'PATCH /blocks/ID/children');
      },
    );

    test('a rejected token still stops publishing', () async {
      final f = fake(
        fail: (c) =>
            c.body['properties'] is Map && (c.body['properties'] as Map).containsKey('Progress')
            ? 401
            : null,
      );
      expect(f.pub.publish(page(), 'parent'), throwsA(isA<PartialPublishException>()));
    });

    test('a failure partway reports an accurate number of missing items', () async {
      // progress db ok, then the tasks db fails: 1 (tasks db) + 2 rows + 1 progress row + 1 paragraph are missing
      var dbCalls = 0;
      final f = fake(
        fail: (c) => c.path == '/databases' && c.method == 'POST' && ++dbCalls == 2 ? 400 : null,
      );
      await expectLater(
        f.pub.publish(page(), 'parent'),
        throwsA(
          isA<PartialPublishException>().having(
            (e) => e.missingBlocks,
            'missing',
            1 + 2 + 1 - 1 + 1 + 0,
          ),
        ),
      );
    });
  });

  group('AI', () {
    AiPage convert(Map<String, dynamic> db) => aiJsonToTemplate({
      'title': 't',
      'blocks': [
        {'type': 'database', 'database': db},
      ],
    }, allowedUrls: {});

    Map<String, dynamic> dbJson(String progress) => {
      'title': 'Tasks',
      'progress': progress,
      'properties': [
        {'name': 'Task', 'type': 'title'},
        {'name': 'Done', 'type': 'checkbox'},
      ],
      'rows': [
        {
          'cells': [
            {'column': 'Task', 'value': 'a'},
            {'column': 'Done', 'value': 'yes'},
          ],
        },
      ],
    };

    test('the progress column is matched by name, ignoring case', () {
      expect(convert(dbJson('done')).template.blocks.single.progressColumn?.name, 'Done');
      expect(convert(dbJson('Done')).template.blocks.single.progressColumn?.name, 'Done');
    });

    test('an unknown or non-checkbox column means no progress bar', () {
      expect(convert(dbJson('Nope')).template.blocks.single.progressColumn, isNull);
      expect(convert(dbJson('Task')).template.blocks.single.progressColumn, isNull);
      expect(convert(dbJson('')).template.blocks.single.progressColumn, isNull);
    });

    test('the current page is described to the model with its progress column', () {
      final json = templateToAiJson(Template(title: 'x', blocks: [tasks()]));
      expect(json['blocks'][0]['database']['progress'], 'Done');
      final back = aiJsonToTemplate(json, allowedUrls: {});
      expect(back.template.blocks.single.progressColumn?.name, 'Done');
    });

    test('the prompt prefers a database progress bar over a widget for task progress', () {
      final p = aiSystemPrompt([]);
      expect(p, contains('"progress"'));
      expect(p, contains('Do NOT use a widget for task progress'));
    });
  });

  group('editor', () {
    Future<void> pump(
      WidgetTester t,
      TemplateBlock b,
      void Function(TemplateBlock Function(TemplateBlock)) edit,
    ) async {
      t.view.physicalSize = const Size(900, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DatabaseEditor(block: b, edit: (f, {bool typing = false}) => edit(f)),
            ),
          ),
        ),
      );
    }

    testWidgets('offers a progress bar when there is a checkbox column', (t) async {
      await pump(t, tasks(progress: ''), (_) {});
      expect(find.text('Progress bar'), findsOneWidget);
    });

    testWidgets('does not offer it without a checkbox column', (t) async {
      final b = TemplateBlock.database('x', [DbProperty.make('Name', DbPropType.title)]);
      await pump(t, b, (_) {});
      expect(find.text('Progress bar'), findsNothing);
    });

    testWidgets('choosing a column turns the bar on', (t) async {
      TemplateBlock current = tasks(progress: '');
      await pump(t, current, (f) => current = f(current));
      await t.tap(find.text('None'));
      await t.pumpAndSettle();
      await t.tap(find.text('Follow "Done"').last);
      await t.pumpAndSettle();
      expect(current.progressColumn?.name, 'Done');
    });
  });
}
