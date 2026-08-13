import 'package:web/web.dart' as web;

import '../web/presentation_slot.dart';
import 'token_storage.dart';

TokenStorageBackend createTokenStorageBackend() =>
    WebLocalTokenStorageBackend();

/// Web：用 localStorage。
/// HTTP 演示站不是安全上下文，FlutterSecureStorage / WebCrypto 会失败。
///
/// 双端演示页（presentation.html）用 `?presentation_slot=` 隔离 key，
/// 避免同域 iframe 互相覆盖登录态。仅 Web 生效；无参数时 key 与线上一致。
class WebLocalTokenStorageBackend implements TokenStorageBackend {
  WebLocalTokenStorageBackend() : _keyPrefix = _resolveKeyPrefix();

  final String _keyPrefix;

  /// 启动时读一次；后续 go_router 可能改写地址，故不每次解析。
  static String _resolveKeyPrefix() {
    final slot = readPresentationSlot();
    if (slot == null) return '';
    return 'presentation_${slot}_';
  }

  String _scoped(String key) => '$_keyPrefix$key';

  @override
  Future<String?> read(String key) async {
    final value = web.window.localStorage.getItem(_scoped(key));
    if (value == null || value.isEmpty) return null;
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    web.window.localStorage.setItem(_scoped(key), value);
  }

  @override
  Future<void> delete(String key) async {
    web.window.localStorage.removeItem(_scoped(key));
  }
}
