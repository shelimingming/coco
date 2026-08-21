import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

class MemoriesApi {
  MemoriesApi(this._dio);

  final Dio _dio;

  Future<List<Memory>> list() async {
    try {
      final response = await _dio.get<List<dynamic>>('/v1/memories');
      return (response.data ?? [])
          .map((e) => Memory.fromJson(asJsonMap(e)))
          .toList();
    } on DioException catch (error) {
      throwApiException(error);
    }
  }

  Future<void> delete(String memoryId) async {
    try {
      await _dio.delete<Map<String, dynamic>>('/v1/memories/$memoryId');
    } on DioException catch (error) {
      throwApiException(error);
    }
  }
}

final memoriesApiProvider = Provider<MemoriesApi>((ref) {
  return MemoriesApi(ref.watch(dioProvider));
});
