import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/template_files.dart';
import '../models/builtin_templates.dart';
import '../models/template_model.dart';
import '../providers/editor_provider.dart';

/// Gallery of built-in and saved templates. Loading one replaces the current
/// page, but it is a normal undoable step.
Future<void> showTemplatesSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => const _TemplatesSheet(),
);

class _TemplatesSheet extends ConsumerWidget {
  const _TemplatesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(userTemplatesProvider);
    final ed = ref.read(editorProvider.notifier);

    void load(Template t) {
      ed.loadTemplate(t);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded "${t.title}"'),
          action: SnackBarAction(label: 'Undo', onPressed: ed.undo),
        ),
      );
    }

    Future<void> importFile() async {
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      try {
        final t = await TemplateFiles.import();
        if (t == null) return;
        ed.loadTemplate(t);
        nav.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Imported "${t.title}"'),
            action: SnackBarAction(label: 'Undo', onPressed: ed.undo),
          ),
        );
      } on FormatException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text("Couldn't import: ${e.message}")));
      } catch (_) {
        messenger.showSnackBar(const SnackBar(content: Text("Couldn't read that file.")));
      }
    }

    Future<void> exportFile() async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final ok = await TemplateFiles.export(ref.read(editorProvider).template);
        if (ok) messenger.showSnackBar(const SnackBar(content: Text('Template exported')));
      } catch (_) {
        messenger.showSnackBar(const SnackBar(content: Text("Couldn't save the file.")));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Templates', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Loading a template replaces your current page. You can undo it.'),
        const SizedBox(height: 16),
        Text('Starter templates', style: Theme.of(context).textTheme.titleSmall),
        for (final b in builtinTemplates)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(b.build().icon, style: const TextStyle(fontSize: 28)),
            title: Text(b.name),
            subtitle: Text(b.description),
            onTap: () => load(b.build()),
          ),
        const Divider(height: 32),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import from file'),
              onPressed: importFile,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('Export current page'),
              onPressed: exportFile,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text('My templates', style: Theme.of(context).textTheme.titleSmall)),
            TextButton.icon(
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Save current page'),
              onPressed: () {
                ref.read(userTemplatesProvider.notifier).save(ref.read(editorProvider).template);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Saved to My templates')));
              },
            ),
          ],
        ),
        if (mine.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nothing saved yet.'),
          ),
        for (var i = 0; i < mine.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(mine[i].icon, style: const TextStyle(fontSize: 28)),
            title: Text(mine[i].title),
            subtitle: Text('${mine[i].blocks.totalCount} blocks'),
            trailing: IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(userTemplatesProvider.notifier).delete(i),
            ),
            onTap: () => load(mine[i]),
          ),
      ],
    );
  }
}
