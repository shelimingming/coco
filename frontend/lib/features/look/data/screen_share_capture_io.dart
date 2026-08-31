import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'screen_share_capture.dart';

/// iOS / Android：MethodChannel 对接原生投屏。
ScreenShareCapture createPlatformScreenShareCapture() => IoScreenShareCapture();

class IoScreenShareCapture implements ScreenShareCapture {
  static const _channel = MethodChannel('coco/screen_share');

  @override
  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  @override
  bool get isIos => Platform.isIOS;

  @override
  bool get isAndroid => Platform.isAndroid;

  @override
  Future<bool> start() async {
    try {
      final ok = await _channel.invokeMethod<bool>('start');
      return ok == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // 忽略：可能已停
    } on MissingPluginException {
      // Web/未注册插件
    }
  }

  @override
  Future<Uint8List?> captureLatestFrame() async {
    final meta = await captureLatestFrameMeta();
    return meta?.bytes;
  }

  @override
  Future<ScreenShareFrame?> captureLatestFrameMeta() async {
    try {
      // 优先带时间戳的 meta；旧原生回退到裸 bytes
      final raw = await _channel.invokeMethod<dynamic>(
        'captureLatestFrameMeta',
      );
      if (raw is Map) {
        final bytesRaw = raw['bytes'];
        final at = raw['capturedAtMs'];
        Uint8List? bytes;
        if (bytesRaw is Uint8List) {
          bytes = bytesRaw;
        } else if (bytesRaw is List<int>) {
          bytes = Uint8List.fromList(bytesRaw);
        }
        if (bytes == null || bytes.isEmpty) return null;
        final ms = at is int ? at : (at is num ? at.toInt() : 0);
        return ScreenShareFrame(bytes: bytes, capturedAtMs: ms);
      }
      final legacy = await _channel.invokeMethod<dynamic>('captureLatestFrame');
      if (legacy is Uint8List && legacy.isNotEmpty) {
        return ScreenShareFrame(bytes: legacy, capturedAtMs: 0);
      }
      if (legacy is List<int> && legacy.isNotEmpty) {
        return ScreenShareFrame(
          bytes: Uint8List.fromList(legacy),
          capturedAtMs: 0,
        );
      }
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> isCapturing() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isCapturing');
      return ok == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> updateNotification(String text) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updateNotification', {'text': text});
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }
}
