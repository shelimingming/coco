import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class NotificationsApi {
  NotificationsApi(this._dio);

  final Dio _dio;

  Future<List<AppNotification>> list({bool unreadOnly = false}) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/v1/notifications',
        queryParameters: {'unread_only': unreadOnly},
      );
      return (response.data ?? [])
          .map((e) => AppNotification.fromJson(asJsonMap(e)))
          .toList();
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<AppNotification> markRead(String notificationId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/notifications/$notificationId/read',
      );
      return AppNotification.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final notificationsApiProvider = Provider<NotificationsApi>((ref) {
  return NotificationsApi(ref.watch(dioProvider));
});
