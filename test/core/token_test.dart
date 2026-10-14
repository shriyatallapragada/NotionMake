import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notion_make/core/secure_storage.dart';
import 'package:notion_make/features/editor/providers/providers.dart';

class _BrokenStorage implements TokenStorage {
  @override
  Future<String?> read() async => null; // the real read() swallows errors
  @override
  Future<void> write(String token) async => throw Exception('-25293');
  @override
  Future<void> clear() async => throw Exception('keychain locked');
}

void main() {
  test('save falls back to session-only when the keychain write fails', () async {
    final c = ProviderContainer(
      overrides: [tokenStorageProvider.overrideWithValue(_BrokenStorage())],
    );
    addTearDown(c.dispose);
    await c.read(tokenProvider.future);
    await c.read(tokenProvider.notifier).save('abc');
    expect(c.read(tokenProvider).value, 'abc'); // still connected
    expect(c.read(keychainOkProvider), false); // and the UI is told
  });
}
