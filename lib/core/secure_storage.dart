import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the Notion integration token in the OS keychain / credential store.
class TokenStorage {
  static const _key = 'notion_integration_token';
  final FlutterSecureStorage _storage;

  /// On macOS we use the regular login keychain. The "data protection"
  /// keychain needs a signed app with a developer certificate, which local
  /// builds don't have.
  const TokenStorage([
    this._storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  ]);

  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null; // keychain unavailable; treat as signed out
    }
  }

  Future<void> write(String token) => _storage.write(key: _key, value: token);
  Future<void> clear() => _storage.delete(key: _key);
}
