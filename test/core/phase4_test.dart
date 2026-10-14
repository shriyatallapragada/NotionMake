import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notion_make/core/constants.dart';
import 'package:notion_make/core/notion/block_mapper.dart';
import 'package:notion_make/core/notion/template_validation.dart';
import 'package:notion_make/data/template_files.dart';
import 'package:notion_make/features/editor/models/builtin_templates.dart';
import 'package:notion_make/features/editor/models/template_model.dart';
import 'package:notion_make/features/editor/providers/editor_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

TemplateBlock cols() => TemplateBlock.columns([
  [TemplateBlock.paragraph('a')],
  [TemplateBlock.heading('b'), TemplateBlock.todo('x\ny')],
]);

void main() {
  group('mapper', () {
    test('columns become column_list > column > children', () {
      final j = blockToNotion(cols()).single;
      expect(j['type'], 'column_list');
      final columns = j['column_list']['children'] as List;
      expect(columns.length, 2);
      expect(columns[0]['type'], 'column');
      // second column: heading + 2 to_do items
      expect((columns[1]['column']['children'] as List).length, 3);
    });

    test('toggle carries children; omitted when empty', () {
      final withKids = blockToNotion(
        TemplateBlock.toggle('t', [TemplateBlock.paragraph('x')]),
      ).single;
      expect(withKids['toggle']['children'], hasLength(1));
      final none = blockToNotion(TemplateBlock.toggle('t', [])).single;
      expect(none['toggle'].containsKey('children'), false);
    });

    test('weight counts nested blocks', () {
      expect(notionWeight(blockToNotion(cols()).single), 1 + 2 + 1 + 3);
      expect(notionWeight(blockToNotion(TemplateBlock.divider()).single), 1);
    });

    test('chunking respects sibling and total limits', () {
      final divs = [for (var i = 0; i < 250; i++) ...blockToNotion(TemplateBlock.divider())];
      expect(chunkNotionBlocks(divs).map((c) => c.length), [100, 100, 50]);

      final big = blockToNotion(
        TemplateBlock.toggle('t', [for (var i = 0; i < 90; i++) TemplateBlock.divider()]),
      ).single; // weight 91
      final chunks = chunkNotionBlocks([big, big, big, big, big, big], maxTotal: 200);
      expect(chunks.map((c) => c.length), [2, 2, 2]);
    });
  });

  group('validation', () {
    test('columns need content in every column', () {
      final t = Template(
        title: 'x',
        blocks: [
          TemplateBlock.columns([
            [TemplateBlock.paragraph('ok')],
            [TemplateBlock.todo('')], // expands to nothing
          ]),
        ],
      );
      expect(validateTemplate(t), contains('column 2 is empty'));
    });

    test('bad embed inside a toggle is found', () {
      final t = Template(
        title: 'x',
        blocks: [
          TemplateBlock.toggle('t', [TemplateBlock.embed('http://x.com')]),
        ],
      );
      expect(validateTemplate(t), contains('Block 1'));
    });

    test('built-in templates all validate', () {
      for (final b in builtinTemplates) {
        expect(validateTemplate(b.build()), isNull, reason: b.name);
      }
    });
  });

  group('tree helpers', () {
    test('edit/remove/duplicate work at any depth', () {
      final inner = TemplateBlock.paragraph('deep');
      final list = [
        TemplateBlock.toggle('t', [inner]),
      ];
      expect(list.edit(inner.id, (_) => []).single.children, isEmpty);
      final dup = list.edit(inner.id, (b) => [b, b.withFreshIds()]);
      expect(dup.single.children.length, 2);
      expect(dup.single.children.map((b) => b.id).toSet().length, 2);
    });

    test('move nudges within siblings only', () {
      final a = TemplateBlock.paragraph('a'), b = TemplateBlock.paragraph('b');
      final list = [
        TemplateBlock.toggle('t', [a, b]),
      ];
      final moved = list.move(b.id, -1).single.children;
      expect(moved.map((x) => x.text), ['b', 'a']);
      expect(list.move(a.id, -1).single.children.map((x) => x.text), ['a', 'b']); // at edge
    });

    test('totalCount includes nested blocks', () {
      expect([cols()].totalCount, 1 + 1 + 2);
    });

    test('theme recolors nested headings', () {
      final t = Template(title: 'x', blocks: [cols()]).withTheme(TemplateTheme.all[3]);
      expect(t.blocks.single.columns[1].first.color, 'orange');
    });
  });

  group('import/export', () {
    test('round trip keeps nested structure', () {
      final t = Template(
        title: 'T',
        blocks: [
          cols(),
          TemplateBlock.toggle('x', [TemplateBlock.quote('q')]),
        ],
      );
      final back = TemplateFiles.parse(jsonEncode(t.toFileJson()));
      expect(back.blocks[0].columns[1].length, 2);
      expect(back.blocks[1].children.single.text, 'q');
    });

    test('rejects garbage with friendly errors', () {
      expect(() => TemplateFiles.parse('not json'), throwsFormatException);
      expect(() => TemplateFiles.parse('[1,2]'), throwsFormatException);
      expect(() => TemplateFiles.parse('{"format":"other"}'), throwsFormatException);
      expect(() => TemplateFiles.parse('{"blocks":[{"type":"nope"}]}'), throwsFormatException);
    });

    test('rejects nested containers and too many columns', () {
      final nested = {
        'blocks': [
          {
            'type': 'toggle',
            'children': [
              {'type': 'toggle'},
            ],
          },
        ],
      };
      expect(() => TemplateFiles.parse(jsonEncode(nested)), throwsFormatException);
      final many = {
        'blocks': [
          {
            'type': 'columns',
            'columns': [[], [], [], []],
          },
        ],
      };
      expect(() => TemplateFiles.parse(jsonEncode(many)), throwsFormatException);
    });
  });

  group('editor notifier with nesting', () {
    late ProviderContainer c;
    EditorNotifier ed() => c.read(editorProvider.notifier);
    Template t() => c.read(editorProvider).template;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      c = ProviderContainer();
      c.read(editorProvider);
    });
    tearDown(() => c.dispose());

    test('add into a column and a toggle; containers are refused inside', () {
      ed().addBlock(BlockType.columns);
      ed().addBlock(BlockType.toggle);
      final colId = t().blocks[t().blocks.length - 2].id;
      final togId = t().blocks.last.id;
      ed().addBlock(BlockType.embed, parentId: colId, column: 1);
      ed().addBlock(BlockType.quote, parentId: togId);
      ed().addBlock(BlockType.columns, parentId: togId); // refused
      final col = t().blocks[t().blocks.length - 2];
      expect(col.columns[1].last.type, BlockType.embed);
      expect(t().blocks.last.children.length, 2); // original paragraph + quote
    });

    test('column count can grow to 3 and shrink to 2 but not beyond', () {
      ed().addBlock(BlockType.columns);
      final id = t().blocks.last.id;
      ed().setColumnCount(id, 3);
      expect(t().blocks.last.columns.length, 3);
      ed().setColumnCount(id, 4);
      expect(t().blocks.last.columns.length, 3);
      ed().setColumnCount(id, 2);
      expect(t().blocks.last.columns.length, 2);
    });

    test('nested edits are undoable', () {
      ed().addBlock(BlockType.toggle);
      final id = t().blocks.last.id;
      ed().addBlock(BlockType.bullet, parentId: id);
      expect(t().blocks.last.children.length, 2);
      ed().undo();
      expect(t().blocks.last.children.length, 1);
    });
  });
}
