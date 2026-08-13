import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_picker.dart';

CameraPicker createCameraPicker() => IoCameraPicker();

/// iOS/Android：系统相机拍照。
class IoCameraPicker implements CameraPicker {
  IoCameraPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

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
