import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/audio/voice_background.dart';
import '../data/screen_share_capture.dart';
import '../domain/look_state.dart';
import '../domain/models.dart';
import '../domain/screen_share_state.dart';
import 'look_controller.dart';

/// 看手机：确认 → 系统投屏 → 按需抽帧识图。
class ScreenShareController extends StateNotifier<ScreenShareState> {
  ScreenShareController(this._ref) : super(const ScreenShareState());

  final Ref _ref;
  final ScreenShareCapture _capture = createScreenShareCapture();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _skipConfirmKey = 'screen_share_skip_confirm';

  Timer? _permissionTimeout;
  int _opGen = 0;

  bool get isSupported => _capture.isSupported;
  bool get isIos => _capture.isIos;

  LookController get _look => _ref.read(lookControllerProvider.notifier);

  /// 点「看手机」：Web/不支持直接 error；否则出说明卡或跳过确认。
  Future<void> onPhonePressed() async {
    if (!_capture.isSupported) {
      state = const ScreenShareState(
        phase: ScreenSharePhase.error,
        errorTitle: '网页端无法看手机',
        errorMessage: '"看手机"功能在网页端无法使用，请用手机 App 体验完整功能',
      );
      return;
    }
    // 已在投屏中：再点视为停止
    if (state.isSharing ||
        state.phase == ScreenSharePhase.awaitingPermission ||
        state.phase == ScreenSharePhase.starting) {
      await stopSharing();
      return;
    }
    final skip = await _storage.read(key: _skipConfirmKey);
    if (skip == '1') {
      await beginPermission();
    } else {
      state = const ScreenShareState(phase: ScreenSharePhase.confirming);
    }
  }

  void cancelConfirm() {
    state = const ScreenShareState();
  }

  /// 说明卡「开始看手机」；[dontAskAgain] 写入本地。
  Future<void> confirmAndStart({bool dontAskAgain = false}) async {
    if (dontAskAgain) {
      await _storage.write(key: _skipConfirmKey, value: '1');
    }
    await beginPermission();
  }

  /// 拉起系统投屏授权。
  Future<bool> beginPermission() async {
    final gen = ++_opGen;
    // 开看手机前先关照片/看眼前会话
    final look = _ref.read(lookControllerProvider);
    if (look.isVisualSession) {
      _look.closeVisualSession();
    }

    state = ScreenShareState(
      phase: ScreenSharePhase.awaitingPermission,
      showIosGuide: _capture.isIos,
    );

    _permissionTimeout?.cancel();
    // iOS 选广播易卡住：超时提示重试
    _permissionTimeout = Timer(const Duration(seconds: 90), () {
      if (!mounted || gen != _opGen) return;
      if (state.phase == ScreenSharePhase.awaitingPermission ||
          state.phase == ScreenSharePhase.starting) {
        state = state.copyWith(
          phase: ScreenSharePhase.error,
          errorTitle: '没有打开看手机',
          errorMessage: _capture.isIos
              ? '请再试一次：选「可可」→ 点开始直播 → 等 3 秒。也可以截屏后用「看照片」。'
              : '没打开看手机权限。你可以截一张屏，用「看照片」发给我。',
          showIosGuide: false,
        );
        unawaited(_capture.stop());
      }
    });

    state = state.copyWith(phase: ScreenSharePhase.starting);
    final ok = await _capture.start();
    if (!mounted || gen != _opGen) return false;
    _permissionTimeout?.cancel();

    if (!ok) {
      state = ScreenShareState(
        phase: ScreenSharePhase.error,
        errorTitle: '没打开看手机权限',
        errorMessage: '你可以截一张屏，用「看照片」发给我。',
      );
      return false;
    }

    state = const ScreenShareState(phase: ScreenSharePhase.sharingIdle);
    // Android：首次引导开启「显示在其他应用上层」，划走后能看到悬浮狗
    final bg = createVoiceBackground();
    if (!(await bg.hasOverlayPermission())) {
      unawaited(bg.requestOverlayPermission());
    }
    return true;
  }

  /// 抽当前帧并识图；成功返回 LookResult 供首页 inject。
  Future<LookResult?> captureAndAnalyze({String? question}) async {
    if (!state.isSharing && state.phase != ScreenSharePhase.sharingIdle) {
      return null;
    }
    final gen = ++_opGen;
    state = state.copyWith(
      phase: ScreenSharePhase.analyzing,
      clearError: true,
      clearBlock: true,
    );

    final still = await _capture.isCapturing();
    if (!still) {
      if (!mounted || gen != _opGen) return null;
      state = const ScreenShareState(
        phase: ScreenSharePhase.error,
        errorTitle: '看手机已经停了',
        errorMessage: '需要的话可以再点一次「看手机」。',
      );
      return null;
    }

    final frame = await _capture.captureLatestFrame();
    if (!mounted || gen != _opGen) return null;
    if (frame == null || frame.isEmpty) {
      state = state.copyWith(
        phase: ScreenSharePhase.sharingIdle,
        errorTitle: '还没看到画面',
        errorMessage: '请先打开要看的页面，再说「你看」或直接问我。',
      );
      return null;
    }

    state = state.copyWith(latestFrame: frame);
    final result = await _look.analyzeBytes(
      source: LookSource.screen,
      bytes: frame,
      filename: 'screen.jpg',
      question: question,
    );
    if (!mounted || gen != _opGen) return null;

    if (result == null) {
      // 识图失败：保持投屏，回到可追问/等待
      state = state.copyWith(
        phase: ScreenSharePhase.sharingIdle,
        latestFrame: frame,
      );
      return null;
    }

    if (result.shouldStopScreen) {
      await _blockAndStop(
        reason: result.safetyNote.trim().isNotEmpty
            ? result.safetyNote.trim()
            : '这类页面我不继续看了，建议先退出，有需要让子女帮忙。',
      );
      return result;
    }

    state = state.copyWith(
      phase: ScreenSharePhase.viewing,
      latestFrame: frame,
      clearError: true,
    );
    return result;
  }

  /// 服务端 / 工具要求停投屏。
  Future<void> applyStopScreen({String? reason}) async {
    await _blockAndStop(
      reason: reason?.trim().isNotEmpty == true ? reason!.trim() : '已停止看屏幕。',
    );
  }

  Future<void> _blockAndStop({required String reason}) async {
    _permissionTimeout?.cancel();
    await _capture.stop();
    _look.closeVisualSession();
    state = ScreenShareState(
      phase: ScreenSharePhase.blocked,
      blockReason: reason,
    );
  }

  /// 用户主动停止；不挂断语音。
  Future<void> stopSharing() async {
    final gen = ++_opGen;
    _permissionTimeout?.cancel();
    await _capture.stop();
    if (!mounted || gen != _opGen) return;
    _look.closeVisualSession();
    state = const ScreenShareState();
  }

  /// 安全终止卡关闭后清状态。
  void dismissBlocked() {
    state = const ScreenShareState();
  }

  void clearError() {
    if (state.phase == ScreenSharePhase.error) {
      state = const ScreenShareState();
    }
  }

  /// 同步服务端 vision.state（投屏看图中）。
  void applyServerVisionPhase(String phase) {
    if (!state.isSharing && state.phase != ScreenSharePhase.viewing) return;
    switch (phase) {
      case 'reanalyzing':
        state = state.copyWith(phase: ScreenSharePhase.reAnalyzing);
      case 'viewing':
        if (state.phase == ScreenSharePhase.reAnalyzing ||
            state.phase == ScreenSharePhase.analyzing) {
          state = state.copyWith(phase: ScreenSharePhase.viewing);
        }
      default:
        break;
    }
  }

  @override
  void dispose() {
    _permissionTimeout?.cancel();
    unawaited(_capture.stop());
    super.dispose();
  }
}

final screenShareControllerProvider =
    StateNotifierProvider<ScreenShareController, ScreenShareState>((ref) {
      return ScreenShareController(ref);
    });
