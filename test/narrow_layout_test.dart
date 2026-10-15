import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notion_make/features/editor/models/template_model.dart';
import 'package:notion_make/features/editor/widgets/block_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Editor cards sit inside columns and toggles, so they can get quite narrow.
/// None of them may overflow ("RIGHT OVERFLOWED BY n PIXELS").
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester t, TemplateBlock b, double width, {bool nested = false}) async {
    t.view.physicalSize = const Size(900, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  child: BlockCard(block: b, index: 0, nested: nested),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
  }

  for (final width in [260.0, 300.0, 340.0]) {
    for (final type in BlockType.values) {
      testWidgets('${type.name} card fits at ${width.toInt()}px, top level', (t) async {
        await pump(t, TemplateBlock.blank(type), width);
        expect(t.takeException(), isNull);
      });
      if (!type.topLevelOnly) {
        testWidgets('${type.name} card fits at ${width.toInt()}px, nested in a column', (t) async {
          // A nested card is inside a column card (extra padding), so it is narrower than its parent.
          await pump(t, TemplateBlock.blank(type), width - 60, nested: true);
          expect(t.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('a column containing every simple block fits at 340px', (t) async {
    final inner = [
      for (final type in BlockType.values.where((x) => !x.topLevelOnly)) TemplateBlock.blank(type),
    ];
    await pump(t, TemplateBlock.columns([inner, inner]), 340);
    expect(t.takeException(), isNull);
  });
}
