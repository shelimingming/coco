import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class CareApi {
  CareApi(this._dio);

  final Dio _dio;

  Future<CareShare> createShare({
    required String summary,
    String urgency = 'LOW',
    bool userConfirmed = true,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/care-shares',
        data: {
          'summary': summary,
          'urgency': urgency,
          'user_confirmed': userConfirmed,
        },
      );
      final map = asJsonMap(response.data);
      if (map['status'] == 'need_confirmation') {
        throw const FormatException('need_confirmation');
      }
      return CareShare.fromJson(map);
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<List<CareShare>> listShares({bool unreadOnly = false}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/v1/care-shares',
        queryParameters: {'unread_only': unreadOnly},
      );
      return (response.data ?? [])
          .map((e) => CareShare.fromJson(asJsonMap(e)))
          .toList();
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  /// 子女按条「知道了」；服务端幂等。
  Future<CareShare> markShareRead(String shareId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/care-shares/$shareId/read',
      );
      return CareShare.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<ChildToday> childToday() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/child/today');
      return ChildToday.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final careApiProvider = Provider<CareApi>((ref) {
  return CareApi(ref.watch(dioProvider));
});
