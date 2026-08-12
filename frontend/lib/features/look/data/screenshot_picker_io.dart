import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import 'screenshot_picker.dart';

/// iOS/Android：优先读「截屏」相册最新一张。
ScreenshotPicker createScreenshotPicker() => IoScreenshotPicker();

class IoScreenshotPicker implements ScreenshotPicker {
  IoScreenshotPicker({ImagePicker? galleryPicker})
    : _galleryPicker = galleryPicker ?? ImagePicker();

  final ImagePicker _galleryPicker;

  @override
  Future<ScreenshotPickResult> pickLatestOrFallback() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      return _fallbackGallery('相册权限未开，请从相册里选一张截屏。');
    }

    final album = await _findScreenshotAlbum();
    if (album == null) {
      return _fallbackGallery('没找到截屏相册，请从相册里选一张。');
    }

    final assets = await album.getAssetListPaged(page: 0, size: 1);
    if (assets.isEmpty) {
      return _fallbackGallery('截屏相册是空的，请先截屏或从相册里选。');
    }

    final file = await assets.first.file;
    if (file == null) {
      return _fallbackGallery('读不到最近截屏，请从相册里选一张。');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      return _fallbackGallery('读不到最近截屏，请从相册里选一张。');
    }
    return ScreenshotPickSuccess(
      Uint8List.fromList(bytes),
      filename: file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'screenshot.jpg',
    );
  }

  Future<ScreenshotPickResult> _fallbackGallery(String reason) async {
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
        notice: reason,
      );
    } catch (_) {
      return ScreenshotPickFallback(reason);
    }
  }

  Future<AssetPathEntity?> _findScreenshotAlbum() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        containsPathModified: true,
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );

    for (final path in paths) {
      final name = path.name.toLowerCase();
      if (name.contains('screenshot') ||
          path.name.contains('截屏') ||
          path.name.contains('屏幕快照') ||
          path.name.contains('屏幕截图')) {
        return path;
      }
    }
    return null;
  }
}
