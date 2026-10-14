import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_models.dart';
import 'ollama_client.dart';

/// A persisted string setting.
class _PrefNotifier extends Notifier<String> {
  final String key;
  final String fallback;
  _PrefNotifier(this.key, this.fallback);

  @override
  String build() {
    Future.microtask(() async {
      try {
        final v = (await SharedPreferences.getInstance()).getString(key);
        if (v != null && v != state) state = v;
      } catch (_) {}
    });
    return fallback;
  }

  Future<void> set(String v) async {
    state = v;
    try {
      await (await SharedPreferences.getInstance()).setString(key, v);
    } catch (_) {}
  }
}

/// Where Ollama is running. Almost always this computer.
final ollamaHostProvider = NotifierProvider<_PrefNotifier, String>(
  () => _PrefNotifier('ollama_host', OllamaClient.defaultHost),
);

/// The model used for generation.
final aiModelProvider = NotifierProvider<_PrefNotifier, String>(
  () => _PrefNotifier('ollama_model', RecommendedModel.all.first.tag),
);

/// Null if the saved address isn't a valid URL.
final ollamaClientProvider = Provider<OllamaClient?>((ref) {
  try {
    return OllamaClient(ref.watch(ollamaHostProvider));
  } on FormatException {
    return null;
  }
});

class OllamaStatus {
  final bool running;
  final String? version;
  final List<OllamaModel> models;
  final String? error;
  const OllamaStatus({required this.running, this.version, this.models = const [], this.error});

  bool has(String tag) => models.any((m) => m.name == tag || m.name == '$tag:latest');
}

/// Whether Ollama is reachable, and which models it has. Re-run with `ref.invalidate`.
final ollamaStatusProvider = FutureProvider.autoDispose<OllamaStatus>((ref) async {
  final client = ref.watch(ollamaClientProvider);
  if (client == null) {
    return const OllamaStatus(running: false, error: 'That address is not valid.');
  }
  try {
    final version = await client.version();
    return OllamaStatus(running: true, version: version, models: await client.listModels());
  } on OllamaException catch (e) {
    return OllamaStatus(running: false, error: e.message);
  }
});
