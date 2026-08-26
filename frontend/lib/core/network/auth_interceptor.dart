// 命名参数需保持可读，不宜改成 this._xxx 形式。
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

typedef AccessTokenReader = String? Function();
typedef AccessTokenWriter = void Function(String? token);
typedef SessionCleared = FutureOr<void> Function();

/// 注入 Bearer，并在 401 时用 refresh token 单次刷新后重放请求。
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required Dio dio,
    required TokenStorage tokenStorage,
    required AccessTokenReader readAccessToken,
    required AccessTokenWriter writeAccessToken,
    required SessionCleared onSessionCleared,
  }) : _dio = dio,
       _tokenStorage = tokenStorage,
       _readAccessToken = readAccessToken,
       _writeAccessToken = writeAccessToken,
       _onSessionCleared = onSessionCleared;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final AccessTokenReader _readAccessToken;
  final AccessTokenWriter _writeAccessToken;
  final SessionCleared _onSessionCleared;

  static const _skipAuthKey = 'skipAuth';
  static const _retriedKey = 'authRetried';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[_skipAuthKey] == true) {
      handler.next(options);
      return;
    }
    final token = _readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final options = err.requestOptions;
    final alreadyRetried = options.extra[_retriedKey] == true;
    final skipAuth = options.extra[_skipAuthKey] == true;

    if (response?.statusCode != 401 || alreadyRetried || skipAuth) {
      handler.next(err);
      return;
    }

    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _onSessionCleared();
      handler.next(err);
      return;
    }

    try {
      final deviceId = await _tokenStorage.getOrCreateDeviceId();
      final refreshResponse = await _dio.post<Map<String, dynamic>>(
        '/v1/auth/refresh',
        data: {'refresh_token': refreshToken, 'device_id': deviceId},
        options: Options(extra: {_skipAuthKey: true}),
      );
      final data = refreshResponse.data;
      final access = data?['access_token'] as String?;
      final nextRefresh = data?['refresh_token'] as String?;
      if (access == null || nextRefresh == null) {
        throw StateError('refresh response incomplete');
      }

      _writeAccessToken(access);
      await _tokenStorage.writeRefreshToken(nextRefresh);

      options.extra[_retriedKey] = true;
      options.headers['Authorization'] = 'Bearer $access';
      final replay = await _dio.fetch<dynamic>(options);
      handler.resolve(replay);
    } catch (_) {
      await _tokenStorage.clearRefreshToken();
      _writeAccessToken(null);
      await _onSessionCleared();
      handler.next(err);
    }
  }
}
