import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_storage.dart';

TokenStorageBackend createTokenStorageBackend() =>
    SecureTokenStorageBackend();

/// iOS/Android：系统钥匙串 / Keystore。
class SecureTokenStorageBackend implements TokenStorageBackend {
  SecureTokenStorageBackend({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
