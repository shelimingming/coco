import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class HistoryApi {
  HistoryApi(this._dio);

  final Dio _dio;

  Future<List<ConversationSummary>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/v1/conversations');
      return (response.data ?? [])
          .map((e) => ConversationSummary.fromJson(asJsonMap(e)))
          .toList();
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<ConversationDetail> get(String conversationId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/conversations/$conversationId',
      );
      return ConversationDetail.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final historyApiProvider = Provider<HistoryApi>((ref) {
  return HistoryApi(ref.watch(dioProvider));
});
