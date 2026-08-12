import 'package:image_picker/image_picker.dart';

import 'screenshot_picker.dart';

/// Web：无系统截屏相册，直接引导从相册选图。
ScreenshotPicker createScreenshotPicker() => WebScreenshotPicker();

class WebScreenshotPicker implements ScreenshotPicker {
  WebScreenshotPicker({ImagePicker? galleryPicker})
    : _galleryPicker = galleryPicker ?? ImagePicker();

  final ImagePicker _galleryPicker;

  @override
  Future<ScreenshotPickResult> pickLatestOrFallback() async {
    try {
      final picked = await _galleryPicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return ScreenshotPickCancelled();
      final bytes = await picked.readAsBytes();
      return ScreenshotPickSuccess(
        bytes,
        filename: picked.name.isNotEmpty ? picked.name : 'screenshot.jpg',
        notice: '网页版请从相册选截屏。',
      );
    } catch (_) {
      return ScreenshotPickFallback('网页版请从相册选截屏。选图失败，请再试一次。');
    }
  }
}
