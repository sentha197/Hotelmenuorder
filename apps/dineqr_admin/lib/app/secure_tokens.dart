import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Staff refresh tokens in the platform's secure storage (Keychain,
/// Android Keystore-backed storage, Windows Credential Locker, …), never in
/// shared preferences.
class SecureTokenStorage implements TokenStorage {
  const SecureTokenStorage([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
