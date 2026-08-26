import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class FamilyApi {
  FamilyApi(this._dio);

  final Dio _dio;

  Future<FamilyInvite> createInvite() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/family/invite',
      );
      return FamilyInvite.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<FamilyInvitePreview> previewInvite(String token) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/family/invite/$token',
        options: Options(extra: {'skipAuth': true}),
      );
      return FamilyInvitePreview.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<FamilyInfo> joinFamily(String token) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/family/join',
        data: {'token': token},
      );
      return FamilyInfo.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<FamilyInfo> getFamily() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/family');
      return FamilyInfo.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final familyApiProvider = Provider<FamilyApi>((ref) {
  return FamilyApi(ref.watch(dioProvider));
});
