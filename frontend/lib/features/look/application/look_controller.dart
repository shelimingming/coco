import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../data/camera_picker.dart';
import '../data/look_api.dart';
import '../data/screenshot_picker.dart';
import '../domain/look_state.dart';
import '../domain/models.dart';

/// 看一看：取图 → 识图；追问与播报交给 Realtime 语音陪伴。
class LookController extends StateNotifier<LookState> {
  LookController(this._ref) : super(const LookState());

  final Ref _ref;
  final ImagePicker _picker = ImagePicker();
  final ScreenshotPicker _screenshotPicker = createScreenshotPicker();
  final CameraPicker _cameraPicker = createCameraPicker();
  int _opGen = 0;

  LookApi get _lookApi => _ref.read(lookApiProvider);

  /// 按来源取图，成功后自动识图。
  /// [hostContext] 供 Web「看眼前」弹出摄像头预览；相册/截屏可不传。
  /// 分析中可再次选择：取消旧任务，以最后一次为准。
  Future<LookResult?> pick(
    LookSource source, {
    BuildContext? hostContext,
  }) async {
    if (state.phase == LookPhase.analyzing) {
      // 打断进行中的分析；若用户取消相册，勿卡在 analyzing
      _opGen++;
      if (state.hasImage) {
        state = state.copyWith(phase: LookPhase.idle, clearError: true);
      }
    } else {
      _opGen++;
    }

    try {
      final picked = await _pickBytes(source, hostContext: hostContext);
      if (picked == null) return null;

      state = LookState(
        phase: LookPhase.analyzing,
        source: source,
        imageBytes: picked.bytes,
      );
      return await _analyze(
        source: source,
        bytes: picked.bytes,
        filename: picked.filename,
      );
    } catch (_) {
      _fail(title: '打不开相机或相册', message: '请允许可可使用相机和相册，然后再试一次。');
      return null;
    }
  }

  Future<({Uint8List bytes, String filename})?> _pickBytes(
    LookSource source, {
    BuildContext? hostContext,
  }) async {
    switch (source) {
      case LookSource.camera:
        // Web 需 context 弹预览；无 context 时无法开摄像头
        final ctx = hostContext;
        if (ctx == null || !ctx.mounted) {
          _fail(title: '打不开相机', message: '请回到首页再点「看眼前」。');
          return null;
        }
        final cam = await _cameraPicker.pick(context: ctx);
        if (cam.isSuccess) {
          return (bytes: cam.bytes!, filename: cam.filename ?? 'camera.jpg');
        }
        if (cam.errorMessage != null) {
          _fail(title: '打不开相机', message: cam.errorMessage!);
        }
        return null;
      case LookSource.album:
        final picked = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (picked == null) return null;
        return (
          bytes: await picked.readAsBytes(),
          filename: picked.name.isNotEmpty ? picked.name : 'album.jpg',
        );
      case LookSource.screenshot:
        final result = await _screenshotPicker.pickLatestOrFallback();
        switch (result) {
          case ScreenshotPickSuccess(
            :final bytes,
            :final filename,
            :final notice,
          ):
            if (notice != null) {
              state = state.copyWith(notice: notice);
            }
            return (bytes: bytes, filename: filename);
          case ScreenshotPickFallback(:final reason):
            _fail(title: '读不到截屏', message: reason);
            return null;
          case ScreenshotPickCancelled():
            return null;
        }
    }
  }

  Future<LookResult?> _analyze({
    required LookSource source,
    required Uint8List bytes,
    required String filename,
  }) async {
    final gen = ++_opGen;
    try {
      final result = await _lookApi.look(
        imageBytes: bytes,
        filename: filename,
        question: source.defaultQuestion,
      );
      if (!_alive(gen)) return null;

      state = state.copyWith(
        phase: LookPhase.ready,
        conversationId: result.conversationId,
        headline: result.headline,
        detail: result.detail,
        safetyNote: result.safetyNote,
        sceneDescription: result.sceneDescription,
        isClear: result.isClear,
        clearError: true,
      );
      return result;
    } on ApiException catch (e) {
      if (!_alive(gen)) return null;
      _fail(title: '这张照片没看清', message: e.message);
      return null;
    } catch (_) {
      if (!_alive(gen)) return null;
      _fail(title: '这张照片没看清', message: '请再试一次。照片没有保存在可可这边。');
      return null;
    }
  }

  /// 清空当前识图会话（首页交接后、失败重选、离开页面）。
  Future<void> reset() async {
    _opGen++;
    state = const LookState();
  }

  /// 注入语音成功后收起照片面板，保留不必要字段清掉。
  void clearAfterHandoff() {
    _opGen++;
    state = const LookState();
  }

  void _fail({required String title, required String message}) {
    state = state.copyWith(
      phase: LookPhase.error,
      errorTitle: title,
      errorMessage: message,
    );
  }

  bool _alive(int gen) => mounted && gen == _opGen;
}

/// 非 autoDispose：首页原地识图需跨「更多」往返保留会话。
final lookControllerProvider = StateNotifierProvider<LookController, LookState>(
  (ref) {
    return LookController(ref);
  },
);
