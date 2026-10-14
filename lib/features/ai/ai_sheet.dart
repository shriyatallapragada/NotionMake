import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../editor/providers/editor_provider.dart';
import 'ai_convert.dart';
import 'ai_models.dart';
import 'ai_providers.dart';
import 'attachments.dart';
import 'ollama_client.dart';
import 'template_ai.dart';

Future<void> showAiSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 700),
  builder: (_) => const _AiSheet(),
);

const _examples = [
  'A weekly study planner from my attached timetable',
  'A project dashboard with milestones and a task table',
  'A meal planner for the week with a shopping list',
  'A habit tracker with a daily checklist',
];

String _gb(int bytes) => '${(bytes / 1e9).toStringAsFixed(1)} GB';

class _AiSheet extends ConsumerStatefulWidget {
  const _AiSheet();
  @override
  ConsumerState<_AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends ConsumerState<_AiSheet> {
  final _prompt = TextEditingController();
  final _host = TextEditingController();
  final _attachments = <AiAttachment>[];
  bool _refine = false;

  CancelToken? _cancel;
  bool _generating = false;
  bool _downloading = false;
  String _status = '';
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _host.text = ref.read(ollamaHostProvider);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _prompt.dispose();
    _host.dispose();
    super.dispose();
  }

  bool get _busy => _generating || _downloading;

  void _fail(Object e) {
    if (!mounted) return;
    if (e is OllamaException && e.problem == OllamaProblem.cancelled) {
      setState(() => _error = null);
      return;
    }
    setState(
      () => _error = e is AiFormatException || e is AttachmentException || e is OllamaException
          ? '$e'
          : 'Something went wrong. Please try again.',
    );
  }

  Future<void> _attach() async {
    try {
      final added = await AttachmentReader.pick(alreadyAttached: _attachments.length);
      if (added.isEmpty || !mounted) return;
      setState(() {
        _attachments.addAll(added);
        _error = null;
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _download(OllamaClient client, String tag) async {
    _cancel = CancelToken();
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
      _status = 'Starting download…';
    });
    try {
      await for (final p in client.pull(tag, cancel: _cancel)) {
        if (!mounted) return;
        setState(() {
          _progress = p.fraction;
          _status = p.total > 0
              ? 'Downloading ${_gb(p.completed)} of ${_gb(p.total)}'
              : (p.status.isEmpty ? 'Working…' : p.status);
        });
      }
      ref.invalidate(ollamaStatusProvider);
      await ref.read(aiModelProvider.notifier).set(tag);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _generate(OllamaClient client) async {
    final messenger = ScaffoldMessenger.of(context);
    final editor = ref.read(editorProvider.notifier);
    _cancel = CancelToken();
    setState(() {
      _generating = true;
      _error = null;
      _status = 'Starting…';
    });
    try {
      final widgets = [
        for (final p in WidgetPreset.all) (name: p.name, url: p.url),
        for (final w in ref.read(widgetCatalogProvider)) (name: w.name, url: w.url),
      ];
      final outcome = await TemplateAi(client).generate(
        model: ref.read(aiModelProvider),
        prompt: _prompt.text,
        attachments: _attachments,
        widgets: widgets,
        current: _refine ? ref.read(editorProvider).template : null,
        cancel: _cancel,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      editor.loadTemplate(outcome.page.template);
      if (!mounted) return;
      Navigator.pop(context);
      final summary = outcome.page.summary.isEmpty ? 'Template created' : outcome.page.summary;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(
            '$summary (${outcome.took.inSeconds}s)${outcome.warning == null ? '' : '\n${outcome.warning}'}',
          ),
          action: SnackBarAction(label: 'Undo', onPressed: editor.undo),
        ),
      );
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final status = ref.watch(ollamaStatusProvider);
    final client = ref.watch(ollamaClientProvider);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome),
              const SizedBox(width: 8),
              Expanded(child: Text('Create with AI', style: theme.textTheme.titleLarge)),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            client != null && !client.isLocal
                ? 'Warning: your request and documents are sent to ${client.base.host}.'
                : 'Free and private: an open-source model runs on this computer, so nothing is sent online and there are no limits.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          status.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _notRunning(context, '$e'),
            data: (s) => !s.running || client == null
                ? _notRunning(context, s.error)
                : _ready(context, s, client),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Advanced'),
            children: [
              TextField(
                controller: _host,
                decoration: const InputDecoration(
                  labelText: 'Ollama address',
                  helperText: 'Leave as is unless Ollama runs on another computer.',
                ),
                onSubmitted: _saveHost,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _saveHost(_host.text),
                  child: const Text('Save address'),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            ),
        ],
      ),
    );
  }

  void _saveHost(String v) {
    try {
      OllamaClient.parseHost(v);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    ref
        .read(ollamaHostProvider.notifier)
        .set(v.trim().isEmpty ? OllamaClient.defaultHost : v.trim());
    ref.invalidate(ollamaStatusProvider);
    setState(() => _error = null);
  }

  Widget _notRunning(BuildContext context, String? detail) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set up the AI (one time)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'NotionMake uses Ollama, a free open-source app that runs AI models on your computer.\n\n'
              '1. Install Ollama.\n2. Open it (it runs in the background).\n3. Come back here and press "Check again".',
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Get Ollama'),
                  onPressed: () => launchUrl(Uri.parse('https://ollama.com/download')),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check again'),
                  onPressed: () => ref.invalidate(ollamaStatusProvider),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ready(BuildContext context, OllamaStatus s, OllamaClient client) {
    final selected = ref.watch(aiModelProvider);
    final tags = <String>[
      for (final m in RecommendedModel.all) m.tag,
      for (final m in s.models)
        if (RecommendedModel.byTag(m.name) == null) m.name,
    ];
    if (!tags.contains(selected)) tags.add(selected);
    final installed = s.has(selected);
    final rec = RecommendedModel.byTag(selected);

    String label(String tag) {
      final r = RecommendedModel.byTag(tag);
      final name = r?.label ?? tag;
      return s.has(tag) ? '$name  ✓ installed' : '$name  (${r?.size ?? '?'} download)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: const InputDecoration(labelText: 'AI model'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true,
              value: selected,
              items: [
                for (final t in tags)
                  DropdownMenuItem(
                    value: t,
                    child: Text(label(t), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (t) => t == null ? null : ref.read(aiModelProvider.notifier).set(t),
            ),
          ),
        ),
        if (rec != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(rec.note, style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 12),
        if (!installed)
          _download_(context, client, selected, rec?.size)
        else
          _compose(context, client),
      ],
    );
  }

  Widget _download_(BuildContext context, OllamaClient client, String tag, String? size) {
    if (_downloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(_status)),
              TextButton(onPressed: () => _cancel?.cancel(), child: const Text('Cancel')),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This model isn\'t on your computer yet. Download it once (${size ?? 'a few GB'}); after that it works offline.',
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.download),
          label: Text('Download ${size == null ? '' : '($size)'}'),
          onPressed: () => _download(client, tag),
        ),
      ],
    );
  }

  Widget _compose(BuildContext context, OllamaClient client) {
    final hasBlocks = ref.watch(editorProvider.select((s) => s.template.blocks.isNotEmpty));
    final chars = AttachmentReader.totalChars(_attachments);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _prompt,
          enabled: !_generating,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'What should the page be?',
            hintText: 'e.g. A weekly planner from my timetable, with a lo-fi music widget',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final e in _examples)
              ActionChip(
                label: Text(e),
                onPressed: _generating ? null : () => setState(() => _prompt.text = e),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file),
              label: const Text('Attach documents'),
              onPressed: _busy || _attachments.length >= AttachmentReader.maxFiles ? null : _attach,
            ),
            for (final a in _attachments)
              InputChip(
                avatar: Icon(
                  a.kind == AttachmentKind.image
                      ? Icons.image_outlined
                      : Icons.description_outlined,
                  size: 18,
                ),
                label: Text(a.name, overflow: TextOverflow.ellipsis),
                onDeleted: _generating ? null : () => setState(() => _attachments.remove(a)),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Timetables, syllabi, notes: PDF, Word, Excel, CSV, text, calendar (.ics) or images. '
            'Up to ${AttachmentReader.maxFiles} files. They are read on this computer only.'
            '${chars > 0 ? ' (${(chars / 1000).toStringAsFixed(0)}k characters attached)' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (hasBlocks)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Change my current page instead of starting fresh'),
            subtitle: const Text(
              'Describe what to add or change, for example "make it more colorful".',
            ),
            value: _refine,
            onChanged: _generating ? null : (v) => setState(() => _refine = v),
          ),
        const SizedBox(height: 12),
        if (_generating)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Semantics(liveRegion: true, child: Text(_status))),
                  TextButton(onPressed: () => _cancel?.cancel(), child: const Text('Cancel')),
                ],
              ),
              const Text('The first request loads the model, which can take a minute.'),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Create template'),
              onPressed: () => _generate(client),
            ),
          ),
      ],
    );
  }
}
