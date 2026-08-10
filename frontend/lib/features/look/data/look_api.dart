import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          // 识图比普通 API 慢，单独放宽超时
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
}

final lookApiProvider = Provider<LookApi>((ref) {
  return LookApi(ref.watch(dioProvider));
});
