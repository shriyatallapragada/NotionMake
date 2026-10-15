import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notion_make/core/notion/notion_client.dart';
import 'package:notion_make/core/notion/notion_exceptions.dart';
import 'package:notion_make/core/notion/page_publisher.dart';
import 'package:notion_make/core/secure_storage.dart';
import 'package:notion_make/features/editor/models/template_model.dart';
import 'package:notion_make/features/editor/providers/providers.dart';
import 'package:notion_make/features/publish/last_published.dart';
import 'package:notion_make/features/publish/publish_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef Call = ({String method, String path, Map<String, dynamic> body});

/// A fake Notion that records every call.
class FakeNotion {
  final calls = <Call>[];

  /// What GET /blocks/{id}/children returns. Several entries = several pages.
  List<List<Map<String, String>>> childPages = [];

  /// Status to return for matching calls (e.g. a DELETE of one block).
  int? Function(Call c)? fail;
  String code = 'validation_error';
  var _n = 0;

  NotionClient client() => NotionClient(
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
        return http.Response(jsonEncode({'code': code, 'message': 'nope'}), status);
      }
      if (call.method == 'GET' && call.path.endsWith('/children')) {
        final cursor = r.url.queryParameters['start_cursor'];
        final i = cursor == null ? 0 : int.parse(cursor);
        final page = i < childPages.length ? childPages[i] : <Map<String, String>>[];
        return http.Response(
          jsonEncode({
            'results': [
              for (final b in page) {'id': b['id'], 'type': b['type'] ?? 'paragraph'},
            ],
            'has_more': i + 1 < childPages.length,
            'next_cursor': i + 1 < childPages.length ? '${i + 1}' : null,
          }),
          200,
        );
      }
      if (call.method == 'GET' && call.path.startsWith('/pages/')) {
        return http.Response(
          jsonEncode({'id': 'target', 'url': 'https://notion.so/looked-up'}),
          200,
        );
      }
      if (call.method == 'POST' && call.path == '/search') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 'target',
                'url': 'https://notion.so/target',
                'icon': null,
                'properties': {
                  'title': {
                    'type': 'title',
                    'title': [
                      {'plain_text': 'Exam notes'},
                    ],
                  },
                },
              },
            ],
            'has_more': false,
          }),
          200,
        );
      }
      _n++;
      return http.Response(jsonEncode({'id': 'id$_n', 'url': 'https://notion.so/new'}), 200);
    }),
  );

  List<String> get summary => [for (final c in calls) '${c.method} ${c.path}'];
}

Template page({String icon = '📅', String cover = ''}) => Template(
  title: 'New title',
  icon: icon,
  coverUrl: cover,
  blocks: [TemplateBlock.heading('H'), TemplateBlock.paragraph('body')],
);

void main() {
  group('add to an existing page', () {
    test('appends to the chosen page and touches nothing else', () async {
      final f = FakeNotion();
      final r = await PagePublisher(
        f.client(),
      ).publish(page(), 'target', mode: PublishMode.append, targetUrl: 'https://notion.so/target');
      expect(f.summary, [
        'PATCH /blocks/target/children',
      ]); // no page created, no deletes, no lookups
      expect(r.pageId, 'target');
      expect(r.url, 'https://notion.so/target');
    });

    test('looks the link up when it is not known', () async {
      final f = FakeNotion();
      final r = await PagePublisher(f.client()).publish(page(), 'target', mode: PublishMode.append);
      expect(r.url, 'https://notion.so/looked-up');
    });

    test('the title, icon and cover are changed only when asked', () async {
      final f = FakeNotion();
      await PagePublisher(
        f.client(),
      ).publish(page(), 'target', mode: PublishMode.append, targetUrl: 'u');
      expect(f.summary.where((s) => s.startsWith('PATCH /pages')), isEmpty);

      final g = FakeNotion();
      await PagePublisher(g.client()).publish(
        page(cover: 'https://img.example/c.png'),
        'target',
        mode: PublishMode.append,
        updateDetails: true,
        targetUrl: 'u',
      );
      final patch = g.calls.firstWhere((c) => c.path == '/pages/target');
      expect(patch.body['properties']['title']['title'][0]['text']['content'], 'New title');
      expect(patch.body['icon'], {'type': 'emoji', 'emoji': '📅'});
      expect(patch.body['cover']['external']['url'], 'https://img.example/c.png');
      expect(g.summary.first, 'PATCH /pages/target'); // details first, then the content

      final h = FakeNotion();
      await PagePublisher(h.client()).publish(
        page(icon: ''),
        'target',
        mode: PublishMode.append,
        updateDetails: true,
        targetUrl: 'u',
      );
      final p2 = h.calls.firstWhere((c) => c.path == '/pages/target').body;
      expect(p2.containsKey('icon'), false); // an empty icon or cover leaves the page's own alone
      expect(p2.containsKey('cover'), false);
    });

    test('a failure says part of the content was added, not that a page was created', () async {
      final f = FakeNotion()..fail = (c) => c.method == 'PATCH' ? 400 : null;
      await expectLater(
        PagePublisher(
          f.client(),
        ).publish(page(), 'target', mode: PublishMode.append, targetUrl: 'u'),
        throwsA(
          isA<PartialPublishException>().having(
            (e) => e.message,
            'message',
            startsWith('Part of the content was added'),
          ),
        ),
      );
    });
  });

  group('replace the content of an existing page', () {
    test('the new content is written first and the old content is removed last', () async {
      final f = FakeNotion()
        ..childPages = [
          [
            {'id': 'old1'},
            {'id': 'old2'},
            {'id': 'old3', 'type': 'child_page'},
          ],
        ];
      final r = await PagePublisher(
        f.client(),
      ).publish(page(), 'target', mode: PublishMode.replace, targetUrl: 'u');
      expect(f.summary, [
        'GET /blocks/target/children', //  remember what is there
        'PATCH /blocks/target/children', // write the new content
        'DELETE /blocks/old1', //          only now remove the old content, in order
        'DELETE /blocks/old2',
        'DELETE /blocks/old3',
      ]);
      expect(r.warnings, isEmpty);
    });

    test('reads every page of a long page', () async {
      final f = FakeNotion()
        ..childPages = [
          [
            {'id': 'a'},
            {'id': 'b'},
          ],
          [
            {'id': 'c'},
          ],
        ];
      await PagePublisher(
        f.client(),
      ).publish(page(), 'target', mode: PublishMode.replace, targetUrl: 'u');
      expect(f.summary.where((s) => s.startsWith('DELETE')), [
        'DELETE /blocks/a',
        'DELETE /blocks/b',
        'DELETE /blocks/c',
      ]);
      expect(f.summary.where((s) => s.startsWith('GET')).length, 2);
    });

    test('if writing the new content fails, nothing is deleted', () async {
      final f = FakeNotion()
        ..childPages = [
          [
            {'id': 'old1'},
          ],
        ]
        ..fail = (c) => c.method == 'PATCH' ? 400 : null;
      await expectLater(
        PagePublisher(
          f.client(),
        ).publish(page(), 'target', mode: PublishMode.replace, targetUrl: 'u'),
        throwsA(isA<PartialPublishException>()),
      );
      expect(f.summary.where((s) => s.startsWith('DELETE')), isEmpty);
    });

    test('a block that cannot be removed is a warning and the others are still removed', () async {
      final f = FakeNotion()
        ..childPages = [
          [
            {'id': 'a'},
            {'id': 'b'},
            {'id': 'c'},
          ],
        ]
        ..fail = (c) => c.path == '/blocks/b' && c.method == 'DELETE' ? 400 : null;
      final r = await PagePublisher(
        f.client(),
      ).publish(page(), 'target', mode: PublishMode.replace, targetUrl: 'u');
      expect(f.summary.where((s) => s.startsWith('DELETE')).length, 3);
      expect(r.warnings.single, allOf(contains('1 of 3'), contains('could not be removed')));
    });

    test('missing permission stops with a message about the Update content capability', () async {
      final f = FakeNotion()
        ..code = 'restricted_resource'
        ..childPages = [
          [
            {'id': 'a'},
          ],
        ]
        ..fail = (c) => c.method == 'DELETE' ? 403 : null;
      await expectLater(
        PagePublisher(
          f.client(),
        ).publish(page(), 'target', mode: PublishMode.replace, targetUrl: 'u'),
        throwsA(
          isA<NotionException>().having((e) => e.message, 'message', contains('Update content')),
        ),
      );
    });

    test('an empty page has nothing to remove', () async {
      final f = FakeNotion();
      await PagePublisher(
        f.client(),
      ).publish(page(), 'target', mode: PublishMode.replace, targetUrl: 'u');
      expect(f.summary.where((s) => s.startsWith('DELETE')), isEmpty);
    });
  });

  test('a new page still works exactly as before', () async {
    final f = FakeNotion();
    final r = await PagePublisher(f.client()).publish(page(), 'parent');
    expect(f.summary, ['POST /pages']);
    expect(f.calls.first.body['parent'], {'page_id': 'parent'});
    expect(r.url, 'https://notion.so/new');
  });

  group('client', () {
    test('listChildren follows pagination and reports types', () async {
      final f = FakeNotion()
        ..childPages = [
          [
            {'id': 'a', 'type': 'child_page'},
          ],
          [
            {'id': 'b', 'type': 'child_database'},
          ],
        ];
      final list = await f.client().listChildren('x');
      expect(list.map((b) => '${b.id}:${b.type}'), ['a:child_page', 'b:child_database']);
    });
  });

  group('publish sheet', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<FakeNotion> open(WidgetTester t, {List<List<Map<String, String>>>? existing}) async {
      t.view.physicalSize = const Size(900, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final f = FakeNotion()..childPages = existing ?? [];
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(_FakeStorage()),
            notionClientProvider.overrideWithValue(f.client()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (c) =>
                  TextButton(onPressed: () => showPublishSheet(c), child: const Text('open')),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return f;
    }

    testWidgets('the safe choice is the default and the other two appear after picking a page', (
      t,
    ) async {
      await open(t);
      expect(find.text('New page inside it'), findsNothing); // nothing picked yet
      await t.tap(find.textContaining('Exam notes'));
      await t.pumpAndSettle();
      expect(find.text('New page inside it'), findsOneWidget);
      expect(find.text('Add to the end of this page'), findsOneWidget);
      expect(find.text("Replace this page's content"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Publish'), findsOneWidget);
      expect(find.textContaining('title, icon and cover'), findsNothing); // only for add / replace
    });

    testWidgets('it still fits on a small window (the sheet scrolls)', (t) async {
      await open(t);
      t.view.physicalSize = const Size(520, 560);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Exam notes'));
      await t.pumpAndSettle();
      await t.tap(find.text("Replace this page's content"));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull); // no "overflowed by N pixels"
      expect(find.widgetWithText(FilledButton, 'Replace content…'), findsOneWidget);
    });

    testWidgets('replace asks first, and cancelling removes nothing', (t) async {
      final f = await open(
        t,
        existing: [
          [
            {'id': 'o1'},
            {'id': 'o2'},
            {'id': 'o3', 'type': 'child_page'},
          ],
        ],
      );
      await t.tap(find.textContaining('Exam notes'));
      await t.pumpAndSettle();
      await t.tap(find.text("Replace this page's content"));
      await t.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Replace content…'), findsOneWidget);
      expect(find.textContaining('title, icon and cover'), findsOneWidget);

      await t.tap(find.widgetWithText(FilledButton, 'Replace content…'));
      // The button behind the dialog shows a spinner, which never "settles", so step time by hand.
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Replace the content of "Exam notes"?'), findsOneWidget);
      expect(find.textContaining('3 blocks'), findsOneWidget);
      expect(find.textContaining('1 sub-page'), findsOneWidget);

      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(f.summary.where((s) => s.startsWith('DELETE') || s.startsWith('PATCH')), isEmpty);
    });

    testWidgets('confirming replaces the content and remembers the page for next time', (t) async {
      final f = await open(
        t,
        existing: [
          [
            {'id': 'o1'},
            {'id': 'o2'},
          ],
        ],
      );
      await t.tap(find.textContaining('Exam notes'));
      await t.pumpAndSettle();
      await t.tap(find.text("Replace this page's content"));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Replace content…'));
      // The button behind the dialog shows a spinner, which never "settles", so step time by hand.
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.widgetWithText(FilledButton, 'Replace content'));
      await t.pumpAndSettle();

      expect(find.text('Your page in Notion was updated!'), findsOneWidget);
      final order = f.summary
          .where((s) => s.startsWith('PATCH') || s.startsWith('DELETE'))
          .toList();
      expect(order, ['PATCH /blocks/target/children', 'DELETE /blocks/o1', 'DELETE /blocks/o2']);

      final container = ProviderScope.containerOf(
        t.element(find.text('Your page in Notion was updated!')),
      );
      expect(container.read(lastPublishedProvider)?.id, 'target');
      expect(container.read(lastPublishedProvider)?.title, 'Exam notes');
    });

    testWidgets('add writes below the existing content without a confirmation', (t) async {
      final f = await open(
        t,
        existing: [
          [
            {'id': 'o1'},
          ],
        ],
      );
      await t.tap(find.textContaining('Exam notes'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add to the end of this page'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Add to this page'));
      await t.pumpAndSettle();
      expect(find.text('Added to your page in Notion!'), findsOneWidget);
      expect(f.summary.where((s) => s.startsWith('DELETE')), isEmpty);
    });

    testWidgets('a page published earlier is offered for one-tap updating', (t) async {
      SharedPreferences.setMockInitialValues({
        'last_published_v1': jsonEncode({
          'id': 'earlier',
          'title': 'My planner',
          'url': 'https://notion.so/earlier',
          'icon': '📅',
        }),
      });
      await open(t);
      expect(find.text('Update "My planner"'), findsOneWidget);
      await t.tap(find.text('Update "My planner"'));
      await t.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Replace content…'),
        findsOneWidget,
      ); // replace is pre-selected
    });
  });
}

class _FakeStorage implements TokenStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String token) async {}
  @override
  Future<void> clear() async {}
}
