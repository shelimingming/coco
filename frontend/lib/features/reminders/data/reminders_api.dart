import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class RemindersApi {
  RemindersApi(this._dio);

  final Dio _dio;

  Future<List<Reminder>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/v1/reminders');
      return (response.data ?? [])
          .map((e) => Reminder.fromJson(asJsonMap(e)))
          .toList();
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<Reminder> create({
    required String title,
    required String scheduleType,
    required String scheduleTime,
    bool userConfirmed = true,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/reminders',
        data: {
          'title': title,
          'schedule_type': scheduleType,
          'schedule_time': scheduleTime,
          'user_confirmed': userConfirmed,
        },
      );
      final map = asJsonMap(response.data);
      // 防御 need_confirmation 形状，正常 UI 路径不会走到
      if (map['status'] == 'need_confirmation') {
        throw const FormatException('need_confirmation');
      }
      return Reminder.fromJson(map);
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<void> delete(String reminderId) async {
    try {
      await _dio.delete<Map<String, dynamic>>('/v1/reminders/$reminderId');
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<ReminderOccurrence> confirm({
    required String reminderId,
    required String occurrenceId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/reminders/$reminderId/occurrences/$occurrenceId/confirm',
      );
      return ReminderOccurrence.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<ReminderOccurrence> delay({
    required String reminderId,
    required String occurrenceId,
    int minutes = 30,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/reminders/$reminderId/occurrences/$occurrenceId/delay',
        data: {'minutes': minutes},
      );
      return ReminderOccurrence.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final remindersApiProvider = Provider<RemindersApi>((ref) {
  return RemindersApi(ref.watch(dioProvider));
});
