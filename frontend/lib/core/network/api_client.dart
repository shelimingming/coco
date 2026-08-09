import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../storage/token_storage.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// 内存中的 access token；refresh token 落安全存储。
class SessionTokenHolder {
  String? accessToken;
}

final sessionTokenHolderProvider = Provider<SessionTokenHolder>((ref) {
  return SessionTokenHolder();
});

final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  final tokenHolder = ref.watch(sessionTokenHolderProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment(
        'COCO_API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8000',
      ),
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 12),
      headers: const {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['X-Request-ID'] = const Uuid().v4();
        handler.next(options);
      },
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      tokenStorage: tokenStorage,
      readAccessToken: () => tokenHolder.accessToken,
      writeAccessToken: (token) => tokenHolder.accessToken = token,
      onSessionCleared: () {
        tokenHolder.accessToken = null;
      },
    ),
  );

  return dio;
});

Map<String, dynamic> asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, dynamic item) => MapEntry(key.toString(), item));
  }
  throw const ApiException('服务返回格式不正确。');
}

Never throwApiException(DioException error) {
  final data = error.response?.data;
  String? code;
  String? message;
  if (data is Map) {
    final err = data['error'];
    if (err is Map) {
      code = err['code']?.toString();
      message = err['message']?.toString();
    }
  }

  if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout) {
    throw const ApiException('网络有点慢，请稍后再试。');
  }
  if (error.type == DioExceptionType.connectionError) {
    throw const ApiException('连不上服务器，请检查网络后重试。');
  }

  throw ApiException(
    message ?? ApiException.messageForCode(code),
    code: code,
    statusCode: error.response?.statusCode,
  );
}
