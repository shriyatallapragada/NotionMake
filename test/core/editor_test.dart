import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notion_make/core/constants.dart';
import 'package:notion_make/core/notion/template_validation.dart';
import 'package:notion_make/features/editor/models/builtin_templates.dart';
import 'package:notion_make/features/editor/models/template_model.dart';
import 'package:notion_make/features/editor/providers/editor_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer c;
  EditorNotifier ed() => c.read(editorProvider.notifier);
  Template t() => c.read(editorProvider).template;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = ProviderContainer();
    c.read(editorProvider); // build
  });
  tearDown(() => c.dispose());

  test('add, duplicate, delete blocks', () {
    final n = t().blocks.length;
    ed().addBlock(BlockType.quote);
    expect(t().blocks.length, n + 1);
    final id = t().blocks.last.id;
    ed().duplicateBlock(id);
    expect(t().blocks.length, n + 2);
    expect(t().blocks.map((b) => b.id).toSet().length, n + 2); // unique ids
    ed().removeBlock(id);
    expect(t().blocks.length, n + 1);
  });

  test('undo and redo', () {
    final n = t().blocks.length;
    ed().addBlock(BlockType.divider);
    expect(c.read(editorProvider).canUndo, true);
    ed().undo();
    expect(t().blocks.length, n);
    expect(c.read(editorProvider).canRedo, true);
    ed().redo();
    expect(t().blocks.length, n + 1);
  });

  test('typing in one field merges into a single undo step', () {
    final id = t().blocks.first.id;
    for (final s in ['a', 'ab', 'abc']) {
      ed().updateBlock(id, (b) => b.copyWith(text: s), typing: true);
    }
    expect(t().blocks.first.text, 'abc');
    ed().undo();
    expect(t().blocks.first.text, 'Today'); // back to before typing
  });

  test('moveBlock uses the final index', () {
    final ids = t().blocks.map((b) => b.id).toList();
    ed().moveBlock(0, 2);
    expect(t().blocks.map((b) => b.id).toList(), [ids[1], ids[2], ids[0], ...ids.skip(3)]);
  });

  test('applyTheme recolors headings and callouts only', () {
    ed().applyTheme(TemplateTheme.all[3]); // Sunset
    for (final b in t().blocks) {
      if (b.type == BlockType.heading) expect(b.color, 'orange');
      if (b.type == BlockType.callout) expect(b.color, 'orange_background');
    }
  });

  test('new edit after undo clears redo', () {
    ed().addBlock(BlockType.divider);
    ed().undo();
    ed().addBlock(BlockType.quote);
    expect(c.read(editorProvider).canRedo, false);
  });

  test('json round trip keeps content; ids are regenerated', () {
    final a = dailyPlanner();
    final b = Template.fromJson(a.toJson());
    expect(b.blocks.length, a.blocks.length);
    expect(b.blocks.first.text, a.blocks.first.text);
    expect(b.blocks.first.id, isNot(a.blocks.first.id));
  });

  test('invalid embeds are reported', () {
    final tpl = Template(
      title: 'x',
      blocks: [TemplateBlock.paragraph('hi'), TemplateBlock.embed('http://insecure.com')],
    );
    expect(validateTemplate(tpl), contains('Block 2'));
    expect(
      validateTemplate(Template(title: 'x', blocks: [TemplateBlock.embed('https://ok.com')])),
      isNull,
    );
  });

  test('every built-in template builds and has content', () {
    for (final b in builtinTemplates) {
      expect(b.build().blocks, isNotEmpty, reason: b.name);
    }
  });
}
