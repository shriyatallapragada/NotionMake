import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/notion/notion_client.dart';
import '../../core/notion/notion_exceptions.dart';
import '../../core/notion/page_publisher.dart';
import '../../core/notion/template_validation.dart';
import '../editor/providers/editor_provider.dart';
import '../editor/providers/providers.dart';

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

  Future<void> _publish() async {
    final template = ref.read(editorProvider).template;
    final problem = validateTemplate(template);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _authFailed = false;
    });
    try {
      final r = await ref
          .read(publisherProvider)!
          .publish(
            template,
            _selected!.id,
            onProgress: (m) {
              if (mounted) setState(() => _status = m);
            },
          );
      if (mounted) setState(() => _done = r);
    } on PartialPublishException catch (e) {
      if (mounted) {
        setState(() {
          _done = e.page;
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
              'created page before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: _done != null ? _success(context) : _picker(context),
    );
  }

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
      Text(_error ?? 'Page created in Notion!', textAlign: TextAlign.center),
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
        const Text('The new page is created inside the page you pick.'),
        const SizedBox(height: 12),
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
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 320),
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
        ),
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
                : const Text('Publish'),
          ),
        ),
      ],
    );
  }
}
