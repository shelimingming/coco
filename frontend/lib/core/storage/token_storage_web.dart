import 'package:web/web.dart' as web;

import 'token_storage.dart';

TokenStorageBackend createTokenStorageBackend() =>
    WebLocalTokenStorageBackend();

/// Web：用 localStorage。
/// HTTP 演示站不是安全上下文，FlutterSecureStorage / WebCrypto 会失败。
class WebLocalTokenStorageBackend implements TokenStorageBackend {
  @override
  Future<String?> read(String key) async {
    final value = web.window.localStorage.getItem(key);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    web.window.localStorage.setItem(key, value);
  }

  @override
  Future<void> delete(String key) async {
    web.window.localStorage.removeItem(key);
  }
}
