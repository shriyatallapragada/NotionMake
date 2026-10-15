import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notion_make/core/constants.dart';
import 'package:notion_make/core/notion/template_validation.dart';
import 'package:notion_make/core/widget_library.dart';
import 'package:notion_make/features/ai/ai_convert.dart';
import 'package:notion_make/features/ai/ai_schema.dart';
import 'package:notion_make/features/editor/models/template_model.dart';
import 'package:notion_make/features/editor/widgets/widget_dialog.dart';

Map<String, dynamic> page(List<Map<String, dynamic>> blocks) => {'title': 't', 'blocks': blocks};

Map<String, dynamic> embed(String kind, [Map<String, String> options = const {}]) => {
  'type': 'embed',
  'widget': kind,
  'options': [
    for (final e in options.entries) {'name': e.key, 'value': e.value},
  ],
};

void main() {
  group('WidgetLibrary.build', () {
    test('no options gives the plain widget link', () {
      expect(WidgetLibrary.build('clock', {})!.url, '$widgetsBaseUrl/clock.html');
      expect(
        WidgetLibrary.build('QUOTE', {})!.url,
        '$widgetsBaseUrl/quote.html',
      ); // kind is case-insensitive
      expect(WidgetLibrary.build('nope', {}), isNull);
    });

    test('options are normalised and encoded', () {
      final url = WidgetLibrary.build('timer', {
        'mode': 'POMODORO',
        'focus': '45.4',
        'break': '999',
        'auto': 'yes',
      })!.url!;
      final q = Uri.parse(url).queryParameters;
      expect(q, {'mode': 'pomodoro', 'focus': '45', 'break': '60', 'auto': '1'}); // clamped to 1-60
    });

    test('invalid optional options are dropped and reported, not fatal', () {
      final b = WidgetLibrary.build('clock', {
        'tz': 'Atlantis',
        'style': 'fancy',
        'theme': 'neon',
        'seconds': '0',
      })!;
      expect(b.url, isNotNull);
      expect(Uri.parse(b.url!).queryParameters, {'seconds': '0'});
      expect(b.errors.keys, containsAll(['tz', 'style', 'theme']));
    });

    test('time zones accept city names and IANA names', () {
      String? tz(String v) => WidgetLibrary.normalizeTimezone(v);
      expect(tz('India'), 'Asia/Kolkata');
      expect(tz('india standard time'), 'Asia/Kolkata');
      expect(tz('asia/kolkata'), 'Asia/Kolkata');
      expect(tz('New York'), 'America/New_York');
      expect(tz('America/New_York'), 'America/New_York');
      expect(tz('Mars'), isNull);
    });

    test('a countdown needs a real date', () {
      expect(WidgetLibrary.build('countdown', {})!.url, isNull);
      expect(WidgetLibrary.build('countdown', {'date': '2026-02-31'})!.url, isNull);
      final ok = WidgetLibrary.build('countdown', {
        'date': '2026-12-14',
        'time': '09:30',
        'label': 'Exam',
      })!;
      expect(Uri.parse(ok.url!).queryParameters, {
        'date': '2026-12-14',
        'time': '09:30',
        'label': 'Exam',
      });
      // a bad optional time is dropped, the widget still works
      expect(
        WidgetLibrary.build('countdown', {'date': '2026-12-14', 'time': '25:99'})!.url,
        isNotNull,
      );
    });

    test('a custom progress bar needs a valid range', () {
      expect(WidgetLibrary.build('progress', {'type': 'custom'})!.url, isNull);
      expect(
        WidgetLibrary.build('progress', {'type': 'custom', 'start': '2026-09-01'})!.url,
        isNull,
      );
      expect(
        WidgetLibrary.build('progress', {
          'type': 'custom',
          'start': '2026-12-01',
          'end': '2026-09-01',
        })!.url,
        isNull,
      );
      expect(
        WidgetLibrary.build('progress', {
          'type': 'custom',
          'start': '2026-09-01',
          'end': '2026-12-20',
        })!.url,
        isNotNull,
      );
      expect(WidgetLibrary.build('progress', {'type': 'year'})!.url, isNotNull);
    });

    test('calendar marks keep valid dates only', () {
      final q = Uri.parse(
        WidgetLibrary.build('calendar', {'mark': '2026-11-02, nope 2026-11-09;2026-13-01'})!.url!,
      ).queryParameters;
      expect(q['mark'], '2026-11-02,2026-11-09');
    });

    test('hostile text is only ever encoded into the query string', () {
      final url = WidgetLibrary.build('countdown', {
        'date': '2026-12-14',
        'label': '<script>alert(1)</script>&date=1999-01-01',
      })!.url!;
      final u = Uri.parse(url);
      expect(u.host, Uri.parse(widgetsBaseUrl).host);
      expect(
        u.queryParameters['date'],
        '2026-12-14',
      ); // the injected "&date=" did not become a second parameter
      expect(u.queryParameters['label'], contains('<script>')); // kept as harmless text
      expect(url, isNot(contains('<'))); // and encoded in the link itself
    });
  });

  group('parse and describe', () {
    test('round trip', () {
      final url = WidgetLibrary.build('clock', {'tz': 'India', 'style': 'analog'})!.url!;
      final p = WidgetLibrary.parse(url)!;
      expect(p.widget.kind, 'clock');
      expect(p.options['tz'], 'Asia/Kolkata');
      expect(WidgetLibrary.describe(url), 'Clock · Asia/Kolkata');
      expect(
        WidgetLibrary.describe('$widgetsBaseUrl/timer.html?mode=pomodoro&focus=50&break=10'),
        'Timer · 50/10 min Pomodoro',
      );
      expect(WidgetLibrary.describe('$widgetsBaseUrl/quote.html'), 'Quote');
    });

    test('links to other sites or schemes are not library widgets', () {
      expect(WidgetLibrary.parse('https://evil.example/widgets/clock.html'), isNull);
      expect(
        WidgetLibrary.parse('${widgetsBaseUrl.replaceFirst('https', 'http')}/clock.html'),
        isNull,
      );
      expect(WidgetLibrary.parse('$widgetsBaseUrl/unknown.html'), isNull);
      expect(WidgetLibrary.describe('https://youtube.com/watch?v=1'), isNull);
    });

    test('the prompt lists every widget and option', () {
      final s = WidgetLibrary.promptSection();
      for (final w in WidgetLibrary.all) {
        expect(s, contains('- ${w.kind}:'));
        for (final o in w.options) {
          expect(s, contains(o.name));
        }
      }
      expect(aiSystemPrompt([]), contains('Asia/Kolkata'));
    });
  });

  group('AI conversion of library widgets', () {
    AiPage convert(Map<String, dynamic> json) => aiJsonToTemplate(json, allowedUrls: {});

    test('builds the link itself and matches the page color', () {
      final p = convert(
        page([
          {'type': 'heading', 'text': 'Plan', 'color': 'green'},
          embed('clock', {'tz': 'Tokyo'}),
        ]),
      );
      final url = p.template.blocks[1].text;
      expect(p.template.blocks[1].type, BlockType.embed);
      expect(Uri.parse(url).queryParameters, {'tz': 'Asia/Tokyo', 'theme': 'sage'});
      expect(validateTemplate(p.template), isNull);
    });

    test('an explicit theme wins; no heading color means no theme is added', () {
      final a = convert(
        page([
          {'type': 'heading', 'text': 'P', 'color': 'blue'},
          embed('quote', {'theme': 'rose'}),
        ]),
      );
      expect(Uri.parse(a.template.blocks[1].text).queryParameters['theme'], 'rose');
      final b = convert(page([embed('quote')]));
      expect(Uri.parse(b.template.blocks.single.text).queryParameters, isEmpty);
    });

    test('options can also arrive as an object', () {
      final p = convert(
        page([
          {
            'type': 'embed',
            'widget': 'timer',
            'options': {'mode': 'countdown', 'minutes': '15'},
          },
        ]),
      );
      expect(Uri.parse(p.template.blocks.single.text).queryParameters, {
        'mode': 'countdown',
        'minutes': '15',
      });
    });

    test('a widget missing something required becomes a helpful note', () {
      final p = convert(page([embed('countdown'), embed('weather'), embed('clock')]));
      expect(p.template.blocks[0].type, BlockType.callout);
      expect(p.template.blocks[0].text, contains('countdown'));
      expect(p.template.blocks[1].type, BlockType.callout); // not in the library
      expect(p.template.blocks[2].type, BlockType.embed);
    });

    test('at most three widgets per page, also inside columns', () {
      final p = convert(
        page([
          embed('clock'),
          embed('timer'),
          {
            'type': 'columns',
            'columns': [
              {
                'blocks': [embed('quote'), embed('calendar')],
              },
              {
                'blocks': [
                  {'type': 'paragraph', 'text': 'x'},
                ],
              },
            ],
          },
        ]),
      );
      final all = [
        ...p.template.blocks,
        for (final c in p.template.blocks.last.columns) ...c,
      ].where((b) => b.type == BlockType.embed);
      expect(all.length, 3);
    });

    test('saved links still work through the allow-list', () {
      final p = aiJsonToTemplate(
        page([
          {'type': 'embed', 'text': 'https://saved.example/w'},
          {'type': 'embed', 'text': 'https://other.example/w'},
        ]),
        allowedUrls: {'https://saved.example/w'},
      );
      expect(p.template.blocks[0].type, BlockType.embed);
      expect(p.template.blocks[1].type, BlockType.callout);
    });

    test('the current page is described to the model with structured widgets', () {
      final url = WidgetLibrary.build('timer', {'focus': '30'})!.url!;
      final json = templateToAiJson(
        Template(
          title: 'x',
          blocks: [TemplateBlock.embed(url), TemplateBlock.embed('https://a.b/c')],
        ),
      );
      final blocks = json['blocks'] as List;
      expect(blocks[0]['widget'], 'timer');
      expect(blocks[0]['options'], [
        {'name': 'focus', 'value': '30'},
      ]);
      expect(blocks[1]['text'], 'https://a.b/c');
      // and it converts back to the same link
      final back = aiJsonToTemplate(json, allowedUrls: {'https://a.b/c'});
      expect(back.template.blocks[0].text, url);
    });
  });

  group('customize dialog', () {
    Future<String?> open(
      WidgetTester t,
      String kind, [
      Map<String, String> initial = const {},
    ]) async {
      String? result;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await showWidgetDialog(
                  c,
                  WidgetLibrary.byKind(kind)!,
                  initial: initial,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('a countdown cannot be added until it has a date', (t) async {
      t.view.physicalSize = const Size(900, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await open(t, 'countdown');
      final use = find.widgetWithText(FilledButton, 'Use this widget');
      expect(t.widget<FilledButton>(use).onPressed, isNull);
      await t.enterText(find.widgetWithText(TextField, 'Date *'), '2026-12-14');
      await t.pump();
      expect(t.widget<FilledButton>(use).onPressed, isNotNull);
    });

    testWidgets('returns the built link', (t) async {
      t.view.physicalSize = const Size(900, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      String? got;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async =>
                  got = await showWidgetDialog(c, WidgetLibrary.byKind('clock')!),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Time zone'), 'London');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Use this widget'));
      await t.pumpAndSettle();
      expect(got, '$widgetsBaseUrl/clock.html?tz=Europe%2FLondon');
    });

    testWidgets('reopening shows the existing settings', (t) async {
      t.view.physicalSize = const Size(900, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await open(t, 'countdown', {'date': '2026-12-14', 'label': 'Exam'});
      expect(find.text('2026-12-14'), findsOneWidget);
      expect(find.text('Exam'), findsOneWidget);
    });
  });

  group('checklist widget', () {
    Map<String, String> q(String? url) => Uri.parse(url!).queryParameters;

    test('tasks are cleaned up and limited', () {
      final b = WidgetLibrary.build('checklist', {
        'items': '- Read ch. 1\n[ ] Write essay | 3) Revise ||  \n* Practice',
        'title': 'Exam prep',
      })!;
      expect(q(b.url)['items'], 'Read ch. 1|Write essay|Revise|Practice');
      expect(q(b.url)['title'], 'Exam prep');

      final many = WidgetLibrary.build('checklist', {
        'items': [for (var i = 1; i <= 40; i++) 'Task $i'].join('\n'),
      })!;
      expect(q(many.url)['items']!.split('|').length, 30);

      final long = WidgetLibrary.build('checklist', {'items': 'x' * 200})!;
      expect(q(long.url)['items']!.length, 60);
    });

    test('at least one task is required', () {
      expect(WidgetLibrary.build('checklist', {})!.url, isNull);
      expect(WidgetLibrary.build('checklist', {'items': ' | \n '})!.url, isNull);
    });

    test('already-done numbers are validated', () {
      final b = WidgetLibrary.build('checklist', {'items': 'a|b|c', 'done': '3, 1, 99, x, 1'})!;
      expect(q(b.url)['done'], '1,3');
    });

    test('tasks with special characters stay safely encoded', () {
      final url = WidgetLibrary.build('checklist', {'items': '<b>bold</b> & "quotes"|#hash'})!.url!;
      expect(url, isNot(contains('<')));
      expect(
        q(url)['items'],
        '<b>bold</b> & "quotes"|#hash',
      ); // survives the round trip as plain text
    });

    test('describe names it by title or task count', () {
      expect(
        WidgetLibrary.describe(
          WidgetLibrary.build('checklist', {'items': 'a|b', 'title': 'Exam'})!.url!,
        ),
        'Checklist · Exam',
      );
      expect(
        WidgetLibrary.describe(WidgetLibrary.build('checklist', {'items': 'a|b|c'})!.url!),
        'Checklist · 3 tasks',
      );
    });

    test('the AI is told to use it for task progress, and the converter builds it', () {
      final prompt = aiSystemPrompt([]);
      expect(prompt, contains('checklist'));
      expect(prompt, contains('TASKS'));
      final p = aiJsonToTemplate({
        'title': 't',
        'blocks': [
          {'type': 'heading', 'text': 'Plan', 'color': 'green'},
          embed('checklist', {'items': 'Read\nWrite\nRevise', 'title': 'Essay', 'done': '1'}),
        ],
      }, allowedUrls: {});
      final block = p.template.blocks[1];
      expect(block.type, BlockType.embed);
      expect(q(block.text), {
        'items': 'Read|Write|Revise',
        'title': 'Essay',
        'done': '1',
        'theme': 'sage',
      });
      // a checklist without tasks becomes a helpful note instead of a broken widget
      final bad = aiJsonToTemplate({
        'title': 't',
        'blocks': [
          embed('checklist'),
          {'type': 'paragraph', 'text': 'x'},
        ],
      }, allowedUrls: {});
      expect(bad.template.blocks.first.type, BlockType.callout);
    });

    testWidgets('the dialog needs a task, shows one per line, and builds the link', (t) async {
      t.view.physicalSize = const Size(900, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      String? got;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async => got = await showWidgetDialog(
                c,
                WidgetLibrary.byKind('checklist')!,
                initial: got == null ? const {} : const {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final use = find.widgetWithText(FilledButton, 'Use this widget');
      expect(t.widget<FilledButton>(use).onPressed, isNull);
      await t.enterText(find.widgetWithText(TextField, 'Tasks *'), 'Read\nWrite');
      await t.pump();
      expect(t.widget<FilledButton>(use).onPressed, isNotNull);
      await t.tap(use);
      await t.pumpAndSettle();
      expect(q(got), {'items': 'Read|Write'});
    });

    testWidgets('reopening shows existing tasks one per line', (t) async {
      t.view.physicalSize = const Size(900, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => showWidgetDialog(
                c,
                WidgetLibrary.byKind('checklist')!,
                initial: const {'items': 'Read|Write'},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Read\nWrite'), findsOneWidget);
    });
  });
}
