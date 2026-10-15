import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../models/template_model.dart';
import '../providers/editor_provider.dart';
import 'notion_colors.dart';
import '../../../core/widget_library.dart';
import 'database_editor.dart';
import 'widget_dialog.dart';
import 'synced_field.dart';

/// Editor card for one block: drag handle, fields for its type, and a menu.
class BlockCard extends ConsumerWidget {
  final TemplateBlock block;
  final int index;

  /// Nested cards (inside a toggle or column) have no drag handle; they use
  /// "Move up/down" in their menu instead.
  final bool nested;
  const BlockCard({super.key, required this.block, required this.index, this.nested = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ed = ref.read(editorProvider.notifier);
    void edit(TemplateBlock Function(TemplateBlock) f, {bool typing = false}) =>
        ed.updateBlock(block.id, f, typing: typing);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nested)
              const SizedBox(width: 8)
            else
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(8, 12, 8, 8),
                  child: Tooltip(
                    message: 'Drag to reorder',
                    child: Icon(Icons.drag_indicator, size: 20, semanticLabel: 'Drag to reorder'),
                  ),
                ),
              ),
            Expanded(child: _body(context, edit)),
            PopupMenuButton<String>(
              tooltip: 'Block options',
              onSelected: (v) => switch (v) {
                'dup' => ed.duplicateBlock(block.id),
                'up' => ed.nudgeBlock(block.id, -1),
                'down' => ed.nudgeBlock(block.id, 1),
                _ => ed.removeBlock(block.id),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'dup', child: Text('Duplicate')),
                if (nested) ...const [
                  PopupMenuItem(value: 'up', child: Text('Move up')),
                  PopupMenuItem(value: 'down', child: Text('Move down')),
                ],
                const PopupMenuItem(value: 'del', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    void Function(TemplateBlock Function(TemplateBlock), {bool typing}) edit,
  ) {
    final label = Theme.of(context).textTheme.labelMedium;
    switch (block.type) {
      case BlockType.heading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Heading', style: label),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        segments: const [
                          ButtonSegment(value: 1, label: Text('H1')),
                          ButtonSegment(value: 2, label: Text('H2')),
                          ButtonSegment(value: 3, label: Text('H3')),
                        ],
                        selected: {block.level},
                        onSelectionChanged: (s) => edit((b) => b.copyWith(level: s.first)),
                      ),
                    ],
                  ),
                ),
                _ColorPicker(
                  current: block.color,
                  colors: {for (final c in NotionConstants.textColors) c: notionTextColors[c]!},
                  onPick: (c) => edit((b) => b.copyWith(color: c)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SyncedField(
              value: block.text,
              onChanged: (v) => edit((b) => b.copyWith(text: v), typing: true),
            ),
          ],
        );
      case BlockType.callout:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Callout', style: label),
                const Spacer(),
                _ColorPicker(
                  current: block.color,
                  colors: {
                    for (final c in NotionConstants.textColors.where((c) => c != 'default'))
                      '${c}_background': notionBgColors['${c}_background']!,
                  },
                  onPick: (c) => edit((b) => b.copyWith(color: c)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: SyncedField(
                    value: block.emoji,
                    textAlign: TextAlign.center,
                    onChanged: (v) => edit((b) => b.copyWith(emoji: v), typing: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SyncedField(
                    value: block.text,
                    maxLines: 4,
                    onChanged: (v) => edit((b) => b.copyWith(text: v), typing: true),
                  ),
                ),
              ],
            ),
          ],
        );
      case BlockType.divider:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Text('Divider'),
              SizedBox(width: 12),
              Expanded(child: Divider()),
            ],
          ),
        );
      case BlockType.embed:
        return _EmbedEditor(block: block, edit: edit);
      case BlockType.database:
        return DatabaseEditor(block: block, edit: edit);
      case BlockType.toggle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Toggle · collapsible', style: label),
            const SizedBox(height: 8),
            SyncedField(
              value: block.text,
              decoration: const InputDecoration(labelText: 'Toggle title'),
              onChanged: (v) => edit((b) => b.copyWith(text: v), typing: true),
            ),
            const SizedBox(height: 8),
            Text('Inside the toggle', style: label),
            _ChildList(parentId: block.id, items: block.children),
          ],
        );
      case BlockType.columns:
        return Consumer(
          builder: (context, ref, _) {
            final ed = ref.read(editorProvider.notifier);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text('Columns', style: label),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: 2, label: Text('2')),
                        ButtonSegment(value: 3, label: Text('3')),
                      ],
                      selected: {block.columns.length.clamp(2, 3)},
                      onSelectionChanged: (s) => ed.setColumnCount(block.id, s.first),
                    ),
                  ],
                ),
                for (var c = 0; c < block.columns.length; c++)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Column ${c + 1}', style: label),
                        _ChildList(parentId: block.id, column: c, items: block.columns[c]),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      case BlockType.todo:
      case BlockType.bullet:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${block.type.label} · one item per line', style: label),
            const SizedBox(height: 8),
            SyncedField(
              value: block.text,
              maxLines: 8,
              onChanged: (v) => edit((b) => b.copyWith(text: v), typing: true),
            ),
          ],
        );
      case BlockType.paragraph:
      case BlockType.quote:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(block.type.label, style: label),
            const SizedBox(height: 8),
            SyncedField(
              value: block.text,
              maxLines: 6,
              onChanged: (v) => edit((b) => b.copyWith(text: v), typing: true),
            ),
          ],
        );
    }
  }
}

class _ColorPicker extends StatelessWidget {
  final String current;
  final Map<String, Color> colors;
  final ValueChanged<String> onPick;
  const _ColorPicker({required this.current, required this.colors, required this.onPick});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Color',
    onSelected: onPick,
    itemBuilder: (_) => [
      for (final e in colors.entries)
        PopupMenuItem(
          value: e.key,
          child: Row(
            children: [
              _dot(context, e.value, e.key == current),
              const SizedBox(width: 10),
              Text(e.key.replaceAll('_background', '')),
            ],
          ),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dot(context, colors[current] ?? colors.values.first, true),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    ),
  );

  Widget _dot(BuildContext context, Color c, bool selected) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? Theme.of(context).colorScheme.tertiary : Colors.black26,
        width: selected ? 2 : 1,
      ),
    ),
  );
}

/// Cards for the blocks inside a toggle or column, plus an add button.
class _ChildList extends ConsumerWidget {
  final String parentId;
  final int? column;
  final List<TemplateBlock> items;
  const _ChildList({required this.parentId, required this.items, this.column});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ed = ref.read(editorProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          BlockCard(key: ValueKey(items[i].id), block: items[i], index: i, nested: true),
        PopupMenuButton<BlockType>(
          onSelected: (t) => ed.addBlock(t, parentId: parentId, column: column),
          itemBuilder: (_) => [
            for (final t in BlockType.values.where((t) => !t.topLevelOnly))
              PopupMenuItem(value: t, child: Text(t.label)),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 18),
                SizedBox(width: 4),
                Flexible(child: Text('Add block here', overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmbedEditor extends ConsumerWidget {
  final TemplateBlock block;
  final void Function(TemplateBlock Function(TemplateBlock), {bool typing}) edit;
  const _EmbedEditor({required this.block, required this.edit});

  Future<void> _saveLink(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save widget link'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name (e.g. My clock)'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (name != null && name.trim().isNotEmpty) {
      ref.read(widgetCatalogProvider.notifier).add(name.trim(), block.text.trim());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(widgetCatalogProvider);
    final bad = block.text.isNotEmpty && !block.isValidEmbed;
    final isSaved = saved.any((w) => w.url == block.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Widget / embed', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Text('Built-in widgets', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final w in WidgetLibrary.all)
              ActionChip(
                avatar: Text(w.icon),
                label: Text(w.label),
                tooltip: w.description,
                onPressed: () async {
                  final url = await showWidgetDialog(context, w);
                  if (url != null) edit((b) => b.copyWith(text: url));
                },
              ),
          ],
        ),
        if (WidgetLibrary.parse(block.text) case final lib?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    WidgetLibrary.describe(block.text) ?? '',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Customize'),
                  onPressed: () async {
                    final url = await showWidgetDialog(context, lib.widget, initial: lib.options);
                    if (url != null) edit((b) => b.copyWith(text: url));
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text('Or paste any link', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        SyncedField(
          value: block.text,
          decoration: InputDecoration(
            hintText: 'https://…',
            helperText: 'Paste a link from any widget site (clock, weather, calendar…).',
            helperMaxLines: 2,
            errorText: bad ? 'Must be an https:// link' : null,
          ),
          onChanged: (v) => edit((b) => b.copyWith(text: v), typing: true),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in WidgetPreset.all)
              ActionChip(
                label: Text(p.name),
                onPressed: () => edit((b) => b.copyWith(text: p.url)),
              ),
            for (final w in saved)
              InputChip(
                avatar: const Icon(Icons.bookmark, size: 16),
                label: Text(w.name),
                onPressed: () => edit((b) => b.copyWith(text: w.url)),
                onDeleted: () => ref.read(widgetCatalogProvider.notifier).remove(w),
              ),
            if (block.isValidEmbed && !isSaved)
              ActionChip(
                avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: const Text('Save this link'),
                onPressed: () => _saveLink(context, ref),
              ),
          ],
        ),
      ],
    );
  }
}
