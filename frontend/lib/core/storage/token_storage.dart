import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'token_storage_stub.dart'
    if (dart.library.html) 'token_storage_web.dart'
    if (dart.library.io) 'token_storage_io.dart'
    as impl;

/// 持久化 refresh token 与设备 ID（IO 走安全存储，Web 走 localStorage）。
class TokenStorage {
  TokenStorage({TokenStorageBackend? backend})
    : _backend = backend ?? impl.createTokenStorageBackend();

  static const _refreshTokenKey = 'coco_refresh_token';
  static const _deviceIdKey = 'coco_device_id';

  final TokenStorageBackend _backend;

  Future<String?> readRefreshToken() => _backend.read(_refreshTokenKey);

  Future<void> writeRefreshToken(String token) =>
      _backend.write(_refreshTokenKey, token);

  Future<void> clearRefreshToken() => _backend.delete(_refreshTokenKey);

  Future<String> getOrCreateDeviceId() async {
    final existing = await _backend.read(_deviceIdKey);
    if (existing != null && existing.length >= 8) {
      return existing;
    }
    final created = const Uuid().v4();
    await _backend.write(_deviceIdKey, created);
    return created;
  }
}

/// 平台密钥/本地存储后端。
abstract class TokenStorageBackend {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
