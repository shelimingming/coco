import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'camera_picker_stub.dart'
    if (dart.library.html) 'camera_picker_web.dart'
    if (dart.library.io) 'camera_picker_io.dart'
    as impl;

/// 看眼前取图：原生走系统相机；Web 走浏览器摄像头预览拍照。
abstract class CameraPicker {
  /// 成功返回 JPEG 字节；取消或失败返回 null（失败时 [errorMessage] 可非空）。
  Future<CameraPickResult> pick({required BuildContext context});
}

class CameraPickResult {
  const CameraPickResult.success(this.bytes, {this.filename = 'camera.jpg'})
    : errorMessage = null;

  const CameraPickResult.cancelled()
    : bytes = null,
      filename = null,
      errorMessage = null;

  const CameraPickResult.failed(this.errorMessage)
    : bytes = null,
      filename = null;

  final Uint8List? bytes;
  final String? filename;
  final String? errorMessage;

  bool get isSuccess => bytes != null && bytes!.isNotEmpty;
}

CameraPicker createCameraPicker() => impl.createCameraPicker();
