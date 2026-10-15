import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../core/notion/notion_client.dart';
import '../../core/notion/notion_exceptions.dart';
import '../../core/notion/page_publisher.dart';
import '../../core/notion/template_validation.dart';
import '../editor/providers/editor_provider.dart';
import '../editor/providers/providers.dart';
import 'last_published.dart';

void showPublishSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _PublishSheet(),
  );
}

class _PublishSheet extends ConsumerStatefulWidget {
  const _PublishSheet();
  @override
  ConsumerState<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends ConsumerState<_PublishSheet> {
  String _query = '';
  String _debounced = '';
  NotionPage? _selected;
  bool _busy = false;
  String _status = '';
  String? _error;
  bool _authFailed = false;
  PublishResult? _done;
  PublishMode _mode = PublishMode.newPage;
  bool _updateDetails = false;
  PublishMode? _finishedMode;

  /// Asks before removing anything. Returns true to go ahead.
  Future<bool> _confirmReplace() async {
    final client = ref.read(notionClientProvider)!;
    final page = _selected!;
    final List<BlockSummary> existing;
    try {
      existing = await client.listChildren(page.id);
    } on NotionException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    }
    if (existing.isEmpty || !mounted) return true;
    final subPages = existing.where((b) => b.type == 'child_page').length;
    final databases = existing.where((b) => b.type == 'child_database').length;
    final extras = [
      if (subPages > 0) '$subPages sub-page${subPages == 1 ? '' : 's'}',
      if (databases > 0) '$databases database${databases == 1 ? '' : 's'}',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Replace the content of "${page.title}"?'),
        content: Text(
          'Your new content is added first. Then the ${existing.length} blocks that are on this page now'
          '${extras.isEmpty ? '' : ' (including ${extras.join(' and ')})'} are moved to Notion\'s trash, '
          'where you can restore them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace content'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _publish() async {
    final template = ref.read(editorProvider).template;
    final problem = validateTemplate(template);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final page = _selected!;
    final mode = _mode;
    setState(() {
      _busy = true;
      _error = null;
      _authFailed = false;
      _status = '';
    });
    try {
      if (mode == PublishMode.replace && !await _confirmReplace()) return;
      final r = await ref
          .read(publisherProvider)!
          .publish(
            template,
            page.id,
            mode: mode,
            updateDetails: mode != PublishMode.newPage && _updateDetails,
            targetUrl: mode == PublishMode.newPage ? null : page.url,
            onProgress: (m) {
              if (mounted) setState(() => _status = m);
            },
          );
      await _remember(r, mode, page, template.title, template.icon);
      if (mounted) {
        setState(() {
          _done = r;
          _finishedMode = mode;
        });
      }
    } on PartialPublishException catch (e) {
      await _remember(e.page, mode, page, template.title, template.icon);
      if (mounted) {
        setState(() {
          _done = e.page;
          _finishedMode = mode;
          _error = e.message;
        });
      }
    } on NotionException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _authFailed = e.isAuthProblem;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Something unexpected went wrong. Check Notion for a partly '
              'created or changed page before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remember(
    PublishResult r,
    PublishMode mode,
    NotionPage page,
    String title,
    String icon,
  ) => ref
      .read(lastPublishedProvider.notifier)
      .set(
        mode == PublishMode.newPage
            ? LastPublished(
                id: r.pageId,
                title: title,
                url: r.url,
                icon: icon.isEmpty ? null : icon,
              )
            : LastPublished(
                id: page.id,
                title: page.title,
                url: r.url ?? page.url,
                icon: page.icon,
              ),
      );

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: SingleChildScrollView(child: _done != null ? _success(context) : _picker(context)),
    );
  }

  Widget _modeTile(PublishMode mode, String title, String subtitle) => RadioListTile<PublishMode>(
    dense: true,
    contentPadding: EdgeInsets.zero,
    value: mode,
    enabled: !_busy,
    title: Text(title),
    subtitle: Text(subtitle),
  );

  Widget _reconnectButton() => TextButton(
    onPressed: () {
      ref.read(tokenProvider.notifier).disconnect();
      Navigator.pop(context);
    },
    child: const Text('Reconnect Notion'),
  );

  Widget _success(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        _error == null ? Icons.check_circle : Icons.warning_amber,
        size: 48,
        color: _error == null
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.error,
      ),
      const SizedBox(height: 12),
      Text(
        _error ??
            switch (_finishedMode) {
              PublishMode.append => 'Added to your page in Notion!',
              PublishMode.replace => 'Your page in Notion was updated!',
              _ => 'Page created in Notion!',
            },
        textAlign: TextAlign.center,
      ),
      if (_done!.warnings.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.yellow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A note about this page',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
              ),
              for (final w in _done!.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(w, style: const TextStyle(color: AppColors.ink)),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      if (_done!.url != null)
        FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open in Notion'),
          onPressed: () => launchUrl(Uri.parse(_done!.url!)),
        ),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
    ],
  );

  Widget _picker(BuildContext context) {
    final pages = ref.watch(pagesProvider(_debounced));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Where should it go?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Pick a page, then choose what to do with it.'),
        const SizedBox(height: 12),
        if (ref.watch(lastPublishedProvider) case final last?)
          Card(
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.history),
              title: Text('Update "${last.title}"', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text(
                'The page you published last: replace its content with this page.',
              ),
              onTap: _busy
                  ? null
                  : () => setState(() {
                      _selected = NotionPage(
                        id: last.id,
                        title: last.title,
                        icon: last.icon,
                        url: last.url,
                      );
                      _mode = PublishMode.replace;
                    }),
            ),
          ),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search pages',
          ),
          onChanged: (v) {
            _query = v;
            Future.delayed(const Duration(milliseconds: 350), () {
              if (mounted && _query == v) setState(() => _debounced = v);
            });
          },
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: pages.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e is NotionException ? e.message : "Couldn't load your pages.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (e is NotionException && e.isAuthProblem)
                    _reconnectButton()
                  else
                    TextButton(
                      onPressed: () => ref.invalidate(pagesProvider(_debounced)),
                      child: const Text('Try again'),
                    ),
                ],
              ),
            ),
            data: (list) => list.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No pages found. In Notion, open a page, click '
                        '... > Connections and add your integration, '
                        'then reopen this sheet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : RadioGroup<String>(
                    groupValue: _selected?.id,
                    onChanged: (id) =>
                        setState(() => _selected = list.firstWhere((p) => p.id == id)),
                    child: ListView(
                      children: [
                        for (final p in list)
                          RadioListTile<String>(
                            value: p.id,
                            title: Text(
                              '${p.icon ?? '📄'}  ${p.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
        if (_selected != null) ...[
          const SizedBox(height: 4),
          RadioGroup<PublishMode>(
            groupValue: _mode,
            onChanged: (m) => setState(() => _mode = m ?? PublishMode.newPage),
            child: Column(
              children: [
                _modeTile(
                  PublishMode.newPage,
                  'New page inside it',
                  'Nothing on "${_selected!.title}" is touched.',
                ),
                _modeTile(
                  PublishMode.append,
                  'Add to the end of this page',
                  'Your content goes below what is already there.',
                ),
                _modeTile(
                  PublishMode.replace,
                  "Replace this page's content",
                  "The old content moves to Notion's trash, where you can restore it.",
                ),
              ],
            ),
          ),
          if (_mode != PublishMode.newPage)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _updateDetails,
              onChanged: _busy ? null : (v) => setState(() => _updateDetails = v ?? false),
              title: const Text("Also set the page's title, icon and cover"),
            ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
        if (_authFailed) _reconnectButton(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _selected == null || _busy ? null : _publish,
            child: _busy
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      if (_status.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Flexible(child: Text(_status, overflow: TextOverflow.ellipsis)),
                      ],
                    ],
                  )
                : Text(switch (_mode) {
                    PublishMode.newPage => 'Publish',
                    PublishMode.append => 'Add to this page',
                    PublishMode.replace => 'Replace content…',
                  }),
          ),
        ),
      ],
    );
  }
}
