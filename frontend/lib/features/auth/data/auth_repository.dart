// 命名参数需保持可读，不宜改成 this._xxx 形式。
// ignore_for_file: prefer_initializing_formals

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/token_storage.dart';
import '../domain/models.dart';
import 'auth_api.dart';

class AuthRepository {
  AuthRepository({
    required AuthApi api,
    required TokenStorage tokenStorage,
    required SessionTokenHolder tokenHolder,
  }) : _api = api,
       _tokenStorage = tokenStorage,
       _tokenHolder = tokenHolder;

  final AuthApi _api;
  final TokenStorage _tokenStorage;
  final SessionTokenHolder _tokenHolder;

  Future<PhoneChallenge> requestPhoneCode(String phone) {
    return _api.requestPhoneCode(phone);
  }

  Future<AppUser> loginWithPhone({
    required String challengeId,
    required String phone,
    required String code,
    required UserRole role,
    String? displayName,
  }) async {
    final deviceId = await _tokenStorage.getOrCreateDeviceId();
    final session = await _api.loginWithPhone(
      challengeId: challengeId,
      phone: phone,
      code: code,
      role: role,
      deviceId: deviceId,
      displayName: displayName,
    );
    await _persistSession(session);
    return session.user;
  }

  /// 启动时用 refresh token 静默续期；失败则回到未登录。
  Future<AppUser?> bootstrap() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    try {
      final deviceId = await _tokenStorage.getOrCreateDeviceId();
      final session = await _api.refresh(
        refreshToken: refreshToken,
        deviceId: deviceId,
      );
      await _persistSession(session);
      return session.user;
    } catch (_) {
      await _tokenStorage.clearRefreshToken();
      _tokenHolder.accessToken = null;
      return null;
    }
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    try {
      if (_tokenHolder.accessToken != null) {
        await _api.logout(refreshToken: refreshToken);
      }
    } catch (_) {
      // 退出以本地清理为准，服务端失败不阻塞
    } finally {
      await _tokenStorage.clearRefreshToken();
      _tokenHolder.accessToken = null;
    }
  }

  Future<void> _persistSession(AuthSession session) async {
    _tokenHolder.accessToken = session.accessToken;
    await _tokenStorage.writeRefreshToken(session.refreshToken);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(authApiProvider),
    tokenStorage: ref.watch(tokenStorageProvider),
    tokenHolder: ref.watch(sessionTokenHolderProvider),
  );
});
