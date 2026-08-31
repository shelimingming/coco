import 'dart:typed_data';

import 'screen_share_capture.dart';

/// Web：浏览器无法跨 App 读屏。
ScreenShareCapture createPlatformScreenShareCapture() => _WebScreenShare();

class _WebScreenShare implements ScreenShareCapture {
  @override
  bool get isSupported => false;

  @override
  bool get isIos => false;

  @override
  bool get isAndroid => false;

  @override
  Future<bool> start() async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<Uint8List?> captureLatestFrame() async => null;

  @override
  Future<ScreenShareFrame?> captureLatestFrameMeta() async => null;

  @override
  Future<bool> isCapturing() async => false;

  @override
  Future<void> updateNotification(String text) async {}
}
