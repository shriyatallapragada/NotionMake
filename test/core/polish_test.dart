import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notion_make/core/constants.dart';
import 'package:notion_make/core/notion/block_mapper.dart';
import 'package:notion_make/core/notion/notion_exceptions.dart';
import 'package:notion_make/core/notion/template_validation.dart';
import 'package:notion_make/core/secure_storage.dart';
import 'package:notion_make/features/editor/models/template_model.dart';
import 'package:notion_make/features/editor/providers/editor_provider.dart';
import 'package:notion_make/features/editor/providers/providers.dart';
import 'package:notion_make/features/editor/screens/builder_screen.dart';
import 'package:notion_make/features/onboarding/connect_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStorage implements TokenStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String token) async {}
  @override
  Future<void> clear() async {}
}

Widget app(Widget home) => ProviderScope(
  overrides: [tokenStorageProvider.overrideWithValue(_FakeStorage())],
  child: MaterialApp(home: home),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('release hygiene', () {
    test('appVersion matches pubspec.yaml', () {
      final line = File(
        'pubspec.yaml',
      ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
      expect(line.split(':')[1].trim().split('+').first, appVersion);
    });
  });

  group('page payload and validation polish', () {
    test('an empty icon is omitted instead of sent as an invalid emoji', () {
      final p = pagePayload(const Template(title: 'T', icon: '  '), 'parent', []);
      expect(p.containsKey('icon'), false);
      final callout = blockToNotion(TemplateBlock.callout('x', emoji: '')).single;
      expect((callout['callout'] as Map).containsKey('icon'), false);
    });

    test('title, icon and cover problems are explained', () {
      expect(validateTemplate(const Template(title: '  ')), contains('title'));
      expect(validateTemplate(const Template(title: 'x', icon: 'abc')), contains('emoji'));
      expect(validateTemplate(const Template(title: 'x', icon: '📅')), isNull);
      expect(
        validateTemplate(const Template(title: 'x', coverUrl: 'http://a.b/c.png')),
        contains('https://'),
      );
      expect(validateTemplate(const Template(title: 'x', coverUrl: 'https://a.b/c.png')), isNull);
    });

    test('a bad callout emoji is reported with its position', () {
      final t = Template(
        title: 'x',
        blocks: [TemplateBlock.callout('hi', emoji: 'ok')],
      );
      expect(validateTemplate(t), contains('Block 1'));
    });
  });

  group('error wording', () {
    test('server trouble gets a calm retry message', () {
      for (final code in ['conflict_error', 'internal_server_error', 'service_unavailable']) {
        final e = NotionException.fromResponse(500, {'code': code});
        expect(e.message, contains('try again'));
      }
    });

    test('auth problems are detectable so the UI can offer Reconnect', () {
      expect(NotionException.fromResponse(401, {'code': 'unauthorized'}).isAuthProblem, true);
      expect(NotionException.fromResponse(404, {'code': 'object_not_found'}).isAuthProblem, false);
    });
  });

  group('screens', () {
    testWidgets('connect screen explains the steps and rejects an empty token', (t) async {
      t.view.physicalSize = const Size(900, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(const ConnectScreen()));
      expect(find.text('Connect to Notion'), findsOneWidget);
      expect(find.text('Create an integration'), findsOneWidget);
      expect(find.text('Share a page'), findsOneWidget);

      await t.tap(find.text('Test connection & continue'));
      await t.pump();
      expect(find.text('Paste your integration token first.'), findsOneWidget);
    });

    testWidgets('builder shows the editor and an enabled Add block', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(const BuilderScreen()));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Publish to Notion'), findsOneWidget);
      expect(find.text('Approximate preview'), findsOneWidget);
      // The editor list is lazy: scroll down to reach the footer button.
      await t.scrollUntilVisible(
        find.text('Add block'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Add block'), findsOneWidget);
    });

    testWidgets('an empty page shows a helpful hint', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(const BuilderScreen()));
      final c = ProviderScope.containerOf(t.element(find.byType(BuilderScreen)));
      for (final b in c.read(editorProvider).template.blocks) {
        c.read(editorProvider.notifier).removeBlock(b.id);
      }
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('This page is empty'), findsOneWidget);
    });

    testWidgets('Ctrl+Enter opens the publish sheet', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(const BuilderScreen()));
      await t.pump(const Duration(milliseconds: 100));

      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Where should it go?'), findsOneWidget);
    });

    testWidgets('narrow layout uses Edit and Preview tabs', (t) async {
      t.view.physicalSize = const Size(500, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(const BuilderScreen()));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Publish'), findsOneWidget);
    });
  });
}
