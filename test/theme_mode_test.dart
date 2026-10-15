import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notion_make/core/secure_storage.dart';
import 'package:notion_make/app_theme.dart';
import 'package:notion_make/features/editor/models/template_model.dart';
import 'package:notion_make/features/editor/providers/editor_provider.dart';
import 'package:notion_make/features/editor/providers/providers.dart';
import 'package:notion_make/features/editor/widgets/preview.dart';
import 'package:notion_make/main.dart';
import 'package:notion_make/theme_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Connected implements TokenStorage {
  @override
  Future<String?> read() async => 'token';
  @override
  Future<void> write(String token) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ThemeModeNotifier', () {
    test('defaults to following the computer and remembers a choice', () async {
      final a = ProviderContainer();
      addTearDown(a.dispose);
      expect(a.read(themeModeProvider), ThemeMode.system);
      await a.read(themeModeProvider.notifier).set(ThemeMode.dark);
      expect(a.read(themeModeProvider), ThemeMode.dark);

      // A fresh start (new container) loads what was saved.
      final b = ProviderContainer();
      addTearDown(b.dispose);
      expect(b.read(themeModeProvider), ThemeMode.system); // until the saved value loads
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(b.read(themeModeProvider), ThemeMode.dark);
    });

    test('ignores a damaged saved value', () async {
      SharedPreferences.setMockInitialValues({'theme_mode_v1': 'purple'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(themeModeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(themeModeProvider), ThemeMode.system);
    });
  });

  group('in the app', () {
    Future<void> pumpApp(WidgetTester t, {double width = 1300}) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ProviderScope(
          overrides: [tokenStorageProvider.overrideWithValue(_Connected())],
          child: const NotionMakeApp(),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
    }

    Brightness brightness(WidgetTester t) =>
        Theme.of(t.element(find.byType(Scaffold).first)).brightness;

    testWidgets('the sun/moon button switches between light and dark on a wide window', (t) async {
      await pumpApp(t);
      expect(brightness(t), Brightness.light);
      await t.tap(find.byTooltip('Switch to dark theme'));
      await t.pumpAndSettle();
      expect(brightness(t), Brightness.dark);
      expect(find.byTooltip('Switch to light theme'), findsOneWidget);
      await t.tap(find.byTooltip('Switch to light theme'));
      await t.pumpAndSettle();
      expect(brightness(t), Brightness.light);
    });

    testWidgets('the More menu offers Light, Dark and Match my computer, with a check mark', (
      t,
    ) async {
      await pumpApp(t, width: 420); // narrow: no toggle button, so the menu is the way
      expect(find.byTooltip('Switch to dark theme'), findsNothing);
      await t.tap(find.byTooltip('More'));
      await t.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Match my computer'), findsOneWidget);

      await t.tap(find.text('Dark'));
      await t.pumpAndSettle();
      expect(brightness(t), Brightness.dark);

      await t.tap(find.byTooltip('More'));
      await t.pumpAndSettle();
      // The current choice is ticked.
      expect(find.byIcon(Icons.done), findsOneWidget);
      await t.tap(find.text('Match my computer'));
      await t.pumpAndSettle();
      expect(brightness(t), Brightness.light); // the test "computer" is in light mode
    });
  });

  group('preview', () {
    testWidgets('stays a light, Notion-like page when the app is dark, so its icons stay visible', (
      t,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(editorProvider.notifier)
          .loadTemplate(
            Template(
              title: 'x',
              blocks: [
                TemplateBlock.todo('a\nb'),
                TemplateBlock.toggle('t', [TemplateBlock.paragraph('p')]),
              ],
            ),
          );
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(Brightness.light),
            darkTheme: buildAppTheme(Brightness.dark),
            themeMode: ThemeMode.dark,
            home: const Scaffold(body: PreviewPane()),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 700)); // let the autosave timer finish
      // The app itself is dark...
      expect(Theme.of(t.element(find.byType(Scaffold))).brightness, Brightness.dark);
      // ...but the checkbox and toggle arrow inside the page preview use the light theme.
      for (final icon in [Icons.check_box_outline_blank, Icons.arrow_right]) {
        final theme = Theme.of(t.element(find.byIcon(icon).first));
        expect(theme.brightness, Brightness.light, reason: '$icon would be white on white');
        expect(
          IconTheme.of(t.element(find.byIcon(icon).first)).color ?? theme.colorScheme.onSurface,
          isNot(const Color(0xFFEAE8DF)),
        );
      }
    });
  });
}
