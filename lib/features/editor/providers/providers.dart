import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notion/notion_client.dart';
import '../../../core/notion/page_publisher.dart';
import '../../../core/secure_storage.dart';

final tokenStorageProvider = Provider((_) => const TokenStorage());

/// The saved token (null = not connected yet).
class TokenNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(tokenStorageProvider).read();

  /// Connects with [token]. If the OS keychain refuses the write (for example
  /// a locked or out-of-sync macOS login keychain), the token is kept for this
  /// session only and [keychainOkProvider] is set to false so the UI can say so.
  Future<void> save(String token) async {
    var persisted = true;
    try {
      await ref.read(tokenStorageProvider).write(token);
    } catch (_) {
      persisted = false;
    }
    ref.read(keychainOkProvider.notifier).set(persisted);
    state = AsyncData(token);
  }

  Future<void> disconnect() async {
    try {
      await ref.read(tokenStorageProvider).clear();
    } catch (_) {} // still disconnect for this session
    ref.read(keychainOkProvider.notifier).set(true);
    state = const AsyncData(null);
  }
}

/// False when the token could not be saved to the keychain this session.
class KeychainOkNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool v) => state = v;
}

final keychainOkProvider = NotifierProvider<KeychainOkNotifier, bool>(KeychainOkNotifier.new);

final tokenProvider = AsyncNotifierProvider<TokenNotifier, String?>(TokenNotifier.new);

final notionClientProvider = Provider<NotionClient?>((ref) {
  final token = ref.watch(tokenProvider).value;
  return token == null ? null : NotionClient(token);
});

/// Pages the integration can see, filtered by search text.
final pagesProvider = FutureProvider.autoDispose.family<List<NotionPage>, String>((ref, q) async {
  final client = ref.watch(notionClientProvider);
  if (client == null) return [];
  final all = <NotionPage>[];
  String? cursor;
  do {
    final r = await client.searchPages(query: q, cursor: cursor);
    all.addAll(r.pages);
    cursor = r.nextCursor;
  } while (cursor != null && all.length < 200);
  return all;
});

final publisherProvider = Provider<PagePublisher?>((ref) {
  final c = ref.watch(notionClientProvider);
  return c == null ? null : PagePublisher(c);
});
