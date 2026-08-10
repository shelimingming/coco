import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class LookApi {
  LookApi(this._dio);

  final Dio _dio;

  /// 上传照片识图；图片仅本次请求传输，服务端不落盘。
  Future<LookResult> look({required File imageFile, String? question}) async {
    try {
      final form = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.uri.pathSegments.isNotEmpty
              ? imageFile.uri.pathSegments.last
              : 'look.jpg',
        ),
        if (question != null && question.trim().isNotEmpty)
          'question': question.trim(),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/vision/look',
        data: form,
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          contentType: 'multipart/form-data',
        ),
      );
      return LookResult.fromJson(asJsonMap(response.data));
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  /// 同图多轮追问（qwen3.7-plus）。
  Future<String> followUp({
    required String conversationId,
    required String text,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/vision/follow-up',
        data: {'conversation_id': conversationId, 'text': text},
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      final map = asJsonMap(response.data);
      final reply = map['reply_text']?.toString().trim() ?? '';
      if (reply.isEmpty) {
        throw const FormatException('empty reply');
      }
      return reply;
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

class AudioApi {
  AudioApi(this._dio);

  final Dio _dio;

  Future<String> transcribe(Uint8List wavBytes) async {
    try {
      final form = FormData.fromMap({
        'audio': MultipartFile.fromBytes(
          wavBytes,
          filename: 'ask.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/audio/transcriptions',
        data: form,
        queryParameters: {'language': 'zh'},
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 45),
          contentType: 'multipart/form-data',
        ),
      );
      final text = asJsonMap(response.data)['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        throw const FormatException('empty transcription');
      }
      return text;
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<Uint8List> speech(String text) async {
    try {
      final response = await _dio.post<List<int>>(
        '/v1/audio/speech',
        data: {'text': text, 'speech_rate': 0.9},
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const FormatException('empty speech');
      }
      return Uint8List.fromList(data);
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final lookApiProvider = Provider<LookApi>((ref) {
  return LookApi(ref.watch(dioProvider));
});

final audioApiProvider = Provider<AudioApi>((ref) {
  return AudioApi(ref.watch(dioProvider));
});
