import 'dart:typed_data';

import 'screen_share_capture.dart';

/// 非 IO/Web 占位。
ScreenShareCapture createPlatformScreenShareCapture() =>
    _UnsupportedScreenShare();

class _UnsupportedScreenShare implements ScreenShareCapture {
  @override
  bool get isSupported => false;

  @override
  bool get isIos => false;

  @override
  Future<bool> start() async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<Uint8List?> captureLatestFrame() async => null;

  @override
  Future<bool> isCapturing() async => false;
}
