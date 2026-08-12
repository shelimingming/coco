import 'token_storage.dart';

/// 非 IO/Web 占位，避免条件导入缺实现。
TokenStorageBackend createTokenStorageBackend() {
  throw UnsupportedError('当前平台不支持 TokenStorage');
}
