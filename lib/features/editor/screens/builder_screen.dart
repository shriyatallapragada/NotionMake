import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../theme_mode.dart';
import '../../ai/ai_sheet.dart';
import '../../publish/publish_sheet.dart';
import '../models/template_model.dart';
import '../providers/editor_provider.dart';
import '../providers/providers.dart';
import '../widgets/block_card.dart';
import '../widgets/preview.dart';
import '../widgets/synced_field.dart';
import '../widgets/templates_sheet.dart';

/// Responsive builder: editor + preview side by side on wide windows, tabs on
/// narrow ones.
class BuilderScreen extends ConsumerWidget {
  const BuilderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(editorProvider);
    final ed = ref.read(editorProvider.notifier);
    final mod = defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl+';
    void publish() => showPublishSheet(context);
    void templates() => showTemplatesSheet(context);

    void ai() => showAiSheet(context);
    final tools = [
      IconButton(
        tooltip: 'Undo',
        icon: const Icon(Icons.undo),
        onPressed: s.canUndo ? ed.undo : null,
      ),
      IconButton(
        tooltip: 'Redo',
        icon: const Icon(Icons.redo),
        onPressed: s.canRedo ? ed.redo : null,
      ),
      IconButton(
        tooltip: 'Create with AI (${mod}Shift+A)',
        icon: const Icon(Icons.auto_awesome),
        onPressed: ai,
      ),
      IconButton(
        tooltip: 'Templates (${mod}Shift+T)',
        icon: const Icon(Icons.dashboard_customize_outlined),
        onPressed: templates,
      ),
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (v) {
          if (v == 'about') {
            _showAbout(context);
          } else if (v.startsWith('theme:')) {
            ref.read(themeModeProvider.notifier).set(ThemeMode.values.byName(v.substring(6)));
          } else {
            ref.read(tokenProvider.notifier).disconnect();
          }
        },
        itemBuilder: (_) {
          final mode = ref.read(themeModeProvider);
          return [
            const PopupMenuItem(enabled: false, child: Text('Appearance')),
            CheckedPopupMenuItem(
              value: 'theme:light',
              checked: mode == ThemeMode.light,
              child: const Text('Light'),
            ),
            CheckedPopupMenuItem(
              value: 'theme:dark',
              checked: mode == ThemeMode.dark,
              child: const Text('Dark'),
            ),
            CheckedPopupMenuItem(
              value: 'theme:system',
              checked: mode == ThemeMode.system,
              child: const Text('Match my computer'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'about', child: Text('About NotionMake')),
            const PopupMenuItem(value: 'disconnect', child: Text('Disconnect Notion')),
          ];
        },
      ),
    ];

    Widget withShortcuts(Widget child) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): publish,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): publish,
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true, shift: true): templates,
        const SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true): templates,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true, shift: true): ai,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true): ai,
      },
      child: Focus(autofocus: true, child: child),
    );

    final banner = ref.watch(keychainOkProvider)
        ? null
        : MaterialBanner(
            content: const Text(
              "Couldn't save your token to the keychain, so you'll need to reconnect "
              'next time you open the app. (On a Mac, open Keychain Access and check '
              'that the "login" keychain is unlocked.)',
            ),
            leading: const Icon(Icons.warning_amber),
            actions: [
              TextButton(
                onPressed: () => ref.read(keychainOkProvider.notifier).set(true),
                child: const Text('Dismiss'),
              ),
            ],
          );

    Widget withBanner(Widget body) => banner == null
        ? body
        : Column(
            children: [
              banner,
              Expanded(child: body),
            ],
          );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth > 800) {
          return withShortcuts(
            Scaffold(
              appBar: AppBar(
                title: const Text('NotionMake'),
                actions: [
                  IconButton(
                    tooltip: Theme.of(context).brightness == Brightness.dark
                        ? 'Switch to light theme'
                        : 'Switch to dark theme',
                    icon: Icon(
                      Theme.of(context).brightness == Brightness.dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                    onPressed: () => ref
                        .read(themeModeProvider.notifier)
                        .set(
                          Theme.of(context).brightness == Brightness.dark
                              ? ThemeMode.light
                              : ThemeMode.dark,
                        ),
                  ),
                  ...tools,
                  Tooltip(
                    message: 'Publish (${mod}Enter)',
                    child: FilledButton.icon(
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Publish to Notion'),
                      onPressed: publish,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
              body: withBanner(
                const Row(
                  children: [
                    SizedBox(width: 460, child: _EditorPane()),
                    VerticalDivider(width: 1),
                    Expanded(child: PreviewPane()),
                  ],
                ),
              ),
            ),
          );
        }
        return withShortcuts(
          DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('NotionMake'),
                actions: tools,
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'Edit'),
                    Tab(text: 'Preview'),
                  ],
                ),
              ),
              body: withBanner(const TabBarView(children: [_EditorPane(), PreviewPane()])),
              floatingActionButton: FloatingActionButton.extended(
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Publish'),
                onPressed: publish,
              ),
            ),
          ),
        );
      },
    );
  }
}

void _showAbout(BuildContext context) => showAboutDialog(
  context: context,
  applicationName: 'NotionMake',
  applicationVersion: appVersion,
  applicationLegalese: 'Build Notion pages and databases visually.',
  children: const [
    SizedBox(height: 12),
    Text(
      'NotionMake runs entirely on your device. Your Notion token is stored in your '
      "device's secure keychain, and the app talks only to api.notion.com. The AI feature "
      'uses Ollama running on your own computer, so your requests and documents are not '
      'sent online. By default NotionMake creates a new page. It changes an existing page '
      'only when you choose "Add to this page" or "Replace this page\'s content" while '
      'publishing, and replaced content goes to Notion\'s trash, where you can restore it.',
    ),
  ],
);

class _EditorPane extends ConsumerWidget {
  const _EditorPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(editorProvider.select((s) => s.template));
    final ed = ref.read(editorProvider.notifier);

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      header: _PageSettings(t: t),
      footer: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (t.blocks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'This page is empty. Add a block below, or open Templates '
                  'to start from a ready-made layout.',
                ),
              ),
            PopupMenuButton<BlockType>(
              tooltip: 'Add a block',
              onSelected: (t) => ed.addBlock(t),
              itemBuilder: (_) => [
                for (final type in BlockType.values)
                  PopupMenuItem(value: type, child: Text(type.label)),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.primary),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Add block',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      itemCount: t.blocks.length,
      onReorderItem: ed.moveBlock,
      itemBuilder: (context, i) {
        final b = t.blocks[i];
        return BlockCard(key: ValueKey(b.id), block: b, index: i);
      },
    );
  }
}

class _PageSettings extends ConsumerWidget {
  final Template t;
  const _PageSettings({required this.t});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ed = ref.read(editorProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 80,
              child: SyncedField(
                value: t.icon,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: 'Icon'),
                onChanged: (v) => ed.setMeta(icon: v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SyncedField(
                value: t.title,
                decoration: const InputDecoration(labelText: 'Page title'),
                onChanged: (v) => ed.setMeta(title: v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SyncedField(
          value: t.coverUrl,
          decoration: const InputDecoration(labelText: 'Cover image URL (optional)'),
          onChanged: (v) => ed.setMeta(coverUrl: v),
        ),
        const SizedBox(height: 16),
        Text('Apply a color theme', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final th in TemplateTheme.all)
              ActionChip(label: Text(th.name), onPressed: () => ed.applyTheme(th)),
          ],
        ),
        const SizedBox(height: 16),
        Text('Blocks · drag to reorder', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
      ],
    );
  }
}
