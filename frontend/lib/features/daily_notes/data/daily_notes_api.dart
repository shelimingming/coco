import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class DailyNotesApi {
  DailyNotesApi(this._dio);

  final Dio _dio;

  Future<DailyNoteSettings> getSettings() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/daily-notes/settings',
      );
      return DailyNoteSettings.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<DailyNoteSettings> updateSettings({
    bool? generateEnabled,
    bool? shareToChildEnabled,
    String? gender,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (generateEnabled != null) {
        body['generate_enabled'] = generateEnabled;
      }
      if (shareToChildEnabled != null) {
        body['share_to_child_enabled'] = shareToChildEnabled;
      }
      if (gender != null) {
        body['gender'] = gender;
      }
      final response = await _dio.patch<Map<String, dynamic>>(
        '/v1/daily-notes/settings',
        data: body,
      );
      return DailyNoteSettings.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<List<DailyNote>> list() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/daily-notes');
      final items = asJsonMap(response.data)['items'] as List<dynamic>? ?? [];
      return items
          .map((e) => DailyNote.fromJson(asJsonMap(e)))
          .toList();
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<DailyNote> get(String noteId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/daily-notes/$noteId',
      );
      return DailyNote.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<DailyNote> generate() async {
    try {
      // 生图可能较慢，单独放宽超时
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/daily-notes/generate',
        data: const <String, dynamic>{},
        options: Options(
          receiveTimeout: const Duration(seconds: 180),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return DailyNote.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<DailyNote?> childToday() async {
    try {
      final response = await _dio.get<dynamic>('/v1/child/daily-notes/today');
      if (response.data == null) {
        return null;
      }
      return DailyNote.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<Uint8List> loadImageBytes(String urlPath) async {
    try {
      final response = await _dio.get<List<int>>(
        urlPath,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null) {
        return Uint8List(0);
      }
      return Uint8List.fromList(data);
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final dailyNotesApiProvider = Provider<DailyNotesApi>((ref) {
  return DailyNotesApi(ref.watch(dioProvider));
});
