import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_picker.dart';

CameraPicker createCameraPicker() => StubCameraPicker();

/// 非 web/io 兜底：仍尝试 image_picker。
class StubCameraPicker implements CameraPicker {
  StubCameraPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<CameraPickResult> pick({required BuildContext context}) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return const CameraPickResult.cancelled();
      return CameraPickResult.success(
        await picked.readAsBytes(),
        filename: picked.name.isNotEmpty ? picked.name : 'camera.jpg',
      );
    } catch (_) {
      return const CameraPickResult.failed('请允许可可使用相机，然后再试一次。');
    }
  }
}
