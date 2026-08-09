import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<PhoneChallenge> requestPhoneCode(String phone) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/auth/phone/code',
        data: {'phone': phone},
        options: Options(extra: {'skipAuth': true}),
      );
      return PhoneChallenge.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<AuthSession> loginWithPhone({
    required String challengeId,
    required String phone,
    required String code,
    required UserRole role,
    required String deviceId,
    String? displayName,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/auth/phone/login',
        data: {
          'challenge_id': challengeId,
          'phone': phone,
          'code': code,
          'role': role.name,
          'device_id': deviceId,
          if (displayName != null && displayName.isNotEmpty)
            'display_name': displayName,
        },
        options: Options(extra: {'skipAuth': true}),
      );
      return AuthSession.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<AuthSession> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/auth/refresh',
        data: {
          'refresh_token': refreshToken,
          'device_id': deviceId,
        },
        options: Options(extra: {'skipAuth': true}),
      );
      return AuthSession.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<AppUser> getMe() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/me');
      return AppUser.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<void> logout({String? refreshToken}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/v1/auth/logout',
        data: {
          'refresh_token': ?refreshToken,
        },
      );
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(dioProvider));
});
