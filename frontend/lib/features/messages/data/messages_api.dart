import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class MessagesApi {
  MessagesApi(this._dio);

  final Dio _dio;

  Future<MessagePreview> preview(String text) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/messages/preview',
        data: {'text': text},
      );
      return MessagePreview.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<FamilyMessage> send({
    required String originalText,
    required String deliveredText,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/messages',
        data: {
          'original_text': originalText,
          'delivered_text': deliveredText,
        },
      );
      return FamilyMessage.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<List<FamilyMessage>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/v1/messages');
      return (response.data ?? [])
          .map((e) => FamilyMessage.fromJson(asJsonMap(e)))
          .toList();
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final messagesApiProvider = Provider<MessagesApi>((ref) {
  return MessagesApi(ref.watch(dioProvider));
});
