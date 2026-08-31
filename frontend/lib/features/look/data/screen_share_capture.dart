import 'dart:typed_data';

import 'screen_share_capture_stub.dart'
    if (dart.library.html) 'screen_share_capture_web.dart'
    if (dart.library.io) 'screen_share_capture_io.dart';

/// 带采集时间的 JPEG 帧，用于判是否够新。
class ScreenShareFrame {
  const ScreenShareFrame({required this.bytes, required this.capturedAtMs});

  final Uint8List bytes;

  /// 原生端采集时刻（epoch ms）；未知时为 0。
  final int capturedAtMs;

  /// 相对现在的帧龄；未知时间戳视为「够旧」以触发重试。
  Duration age([DateTime? now]) {
    if (capturedAtMs <= 0) return const Duration(days: 1);
    final n = now ?? DateTime.now();
    return n.difference(DateTime.fromMillisecondsSinceEpoch(capturedAtMs));
  }
}

/// 跨 App 投屏能力；Web 恒为不支持。
abstract class ScreenShareCapture {
  /// 当前平台是否支持跨 App 看手机。
  bool get isSupported;

  /// 是否为 iOS（需系统广播选择器 + 三步引导）。
  bool get isIos;

  /// 是否为 Android（自动首看 / 前台拦截等）。
  bool get isAndroid;

  /// 请求系统投屏授权并开始捕获最新帧缓冲。
  /// 成功返回 true；用户取消/拒绝返回 false。
  Future<bool> start();

  /// 停止系统投屏并清空缓冲。
  Future<void> stop();

  /// 取当前最新 JPEG 帧；无帧返回 null。
  Future<Uint8List?> captureLatestFrame();

  /// 取帧 + 采集时间；无帧返回 null。
  Future<ScreenShareFrame?> captureLatestFrameMeta();

  /// 投屏是否仍在进行（扩展被系统杀掉时为 false）。
  Future<bool> isCapturing();

  /// 更新前台通知文案（仅 Android 有效）。
  Future<void> updateNotification(String text);
}

ScreenShareCapture createScreenShareCapture() =>
    createPlatformScreenShareCapture();
