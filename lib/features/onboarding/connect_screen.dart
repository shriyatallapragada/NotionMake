import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/notion/notion_client.dart';
import '../../core/notion/notion_exceptions.dart';
import '../editor/providers/providers.dart';

/// First-run setup: create an integration, paste its token, test it.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});
  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final token = _controller.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Paste your integration token first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await NotionClient(token).getBotName();
      await ref.read(tokenProvider.notifier).save(token);
    } on NotionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connect to Notion', style: text.headlineMedium),
                  const SizedBox(height: 8),
                  Text('One-time setup. Takes about two minutes.', style: text.bodyLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Your token stays on this device. NotionMake only talks to Notion '
                    '(and to AI running on your own computer, if you use it). It creates new '
                    'pages unless you choose to update an existing one.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  _step(
                    1,
                    'Create an integration',
                    'Open your integrations page, click "New integration", '
                        'and give it any name.',
                    action: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Notion integrations'),
                      onPressed: () => launchUrl(Uri.parse(NotionConstants.integrationsUrl)),
                    ),
                  ),
                  _step(
                    2,
                    'Paste the token',
                    'Copy the "Internal Integration Secret" and paste it '
                        'here. It is stored in your device keychain only.',
                    action: TextField(
                      controller: _controller,
                      obscureText: _hide,
                      onSubmitted: (_) => _connect(),
                      decoration: InputDecoration(
                        labelText: 'Integration token',
                        errorText: _error,
                        errorMaxLines: 3,
                        suffixIcon: IconButton(
                          icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                    ),
                  ),
                  _step(
                    3,
                    'Share a page',
                    'In Notion, open the page you want templates created '
                        'under, click ... > Connections, and add your '
                        'integration.',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Test connection & continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(int n, String title, String body, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(radius: 14, child: Text('$n')),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(body),
              if (action != null) ...[const SizedBox(height: 10), action],
            ],
          ),
        ),
      ],
    ),
  );
}
