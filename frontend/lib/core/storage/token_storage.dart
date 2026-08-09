import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// 安全存储 refresh token 与设备 ID。
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshTokenKey = 'coco_refresh_token';
  static const _deviceIdKey = 'coco_device_id';

  final FlutterSecureStorage _storage;

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  Future<void> clearRefreshToken() => _storage.delete(key: _refreshTokenKey);

  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.length >= 8) {
      return existing;
    }
    final created = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: created);
    return created;
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
