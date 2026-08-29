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
    try {
      final raw = await _channel.invokeMethod<dynamic>('captureLatestFrame');
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
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
}
