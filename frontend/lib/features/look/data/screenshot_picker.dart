import 'dart:typed_data';

import 'screenshot_picker_stub.dart'
    if (dart.library.html) 'screenshot_picker_web.dart'
    if (dart.library.io) 'screenshot_picker_io.dart'
    as impl;

/// 截屏取图结果：成功路径或需降级到相册。
sealed class ScreenshotPickResult {}

class ScreenshotPickSuccess extends ScreenshotPickResult {
  ScreenshotPickSuccess(
    this.bytes, {
    this.filename = 'screenshot.jpg',
    this.notice,
  });

  final Uint8List bytes;
  final String filename;

  /// 截屏相册不可用时，降级到相册选择器的说明。
  final String? notice;
}

class ScreenshotPickFallback extends ScreenshotPickResult {
  ScreenshotPickFallback(this.reason);

  final String reason;
}

class ScreenshotPickCancelled extends ScreenshotPickResult {}

/// 读系统截屏相册最新一张；Web 降级为相册选择。
abstract class ScreenshotPicker {
  Future<ScreenshotPickResult> pickLatestOrFallback();
}

ScreenshotPicker createScreenshotPicker() => impl.createScreenshotPicker();
