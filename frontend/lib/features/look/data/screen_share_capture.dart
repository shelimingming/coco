import 'dart:typed_data';

import 'screen_share_capture_stub.dart'
    if (dart.library.html) 'screen_share_capture_web.dart'
    if (dart.library.io) 'screen_share_capture_io.dart';

/// 跨 App 投屏能力；Web 恒为不支持。
abstract class ScreenShareCapture {
  /// 当前平台是否支持跨 App 看手机。
  bool get isSupported;

  /// 是否为 iOS（需系统广播选择器 + 三步引导）。
  bool get isIos;

  /// 请求系统投屏授权并开始捕获最新帧缓冲。
  /// 成功返回 true；用户取消/拒绝返回 false。
  Future<bool> start();

  /// 停止系统投屏并清空缓冲。
  Future<void> stop();

  /// 取当前最新 JPEG 帧；无帧返回 null。
  Future<Uint8List?> captureLatestFrame();

  /// 投屏是否仍在进行（扩展被系统杀掉时为 false）。
  Future<bool> isCapturing();
}

ScreenShareCapture createScreenShareCapture() =>
    createPlatformScreenShareCapture();
