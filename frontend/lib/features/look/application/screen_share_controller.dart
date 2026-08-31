import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/audio/voice_background.dart';
import '../data/screen_share_capture.dart';
import '../domain/look_state.dart';
import '../domain/models.dart';
import '../domain/screen_frame_fingerprint.dart';
import '../domain/screen_share_state.dart';
import 'look_controller.dart';

/// 帧龄超过该值视为偏旧，抽帧时短暂重试。
const Duration kScreenFrameMaxAge = Duration(milliseconds: 800);

/// 换屏自动再看防抖。
const Duration kScreenChangeDebounce = Duration(milliseconds: 1800);

/// 看手机：确认 → 系统投屏 → 按需抽帧识图（安卓：离开后自动首看）。
class ScreenShareController extends StateNotifier<ScreenShareState> {
  ScreenShareController(this._ref) : super(const ScreenShareState());

  final Ref _ref;
  final ScreenShareCapture _capture = createScreenShareCapture();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final VoiceBackground _voiceBg = createVoiceBackground();
  static const _skipConfirmKey = 'screen_share_skip_confirm';

  Timer? _permissionTimeout;
  Timer? _watchTimer;
  Timer? _changeDebounce;
  int _opGen = 0;

  /// 前台可可界面的帧指纹（自动首看须异于它）
  int? _cocoBaselineHash;

  /// 上次成功识图的帧指纹（换屏检测）
  int? _lastAnalyzedHash;

  /// 后台监视用的最近指纹窗口
  final List<int> _recentHashes = <int>[];

  /// 是否已完成离开可可后的自动首看
  bool _didAutoFirstLook = false;

  /// 自动识图结果回调：由首页挂接 inject
  void Function(LookResult result, {required String kind})? onAutoLookResult;

  /// 仅口语引导（不识图）回调
  void Function(String coaching)? onCoachingOnly;

  bool get isSupported => _capture.isSupported;
  bool get isIos => _capture.isIos;
  bool get isAndroid => !kIsWeb && _capture.isAndroid;

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

    _didAutoFirstLook = false;
    _lastAnalyzedHash = null;
    _recentHashes.clear();
    _cocoBaselineHash = null;

    final bg = createVoiceBackground();
    final hasOverlay = await bg.hasOverlayPermission();
    state = ScreenShareState(
      phase: ScreenSharePhase.sharingIdle,
      appInForeground: true,
      needsOverlayHint: isAndroid && !hasOverlay,
    );

    // 前台基线：记下可可自己界面；禁止把实时投屏帧塞进 UI（会套娃）
    unawaited(_captureForegroundBaseline());
    unawaited(_syncPresence(looking: false));

    if (isAndroid && !hasOverlay) {
      unawaited(bg.requestOverlayPermission());
    }
    return true;
  }

  Future<void> _captureForegroundBaseline() async {
    final frame = await _waitForFreshFrame(maxAttempts: 4);
    if (!mounted || frame == null) return;
    _cocoBaselineHash = screenFrameFingerprint(frame.bytes);
    // 若当前预览已是可可自己 / 套娃帧，清掉改回占位文案
    _clearPreviewIfLooksLikeCoco();
  }

  /// 前台禁止直播投屏帧：只保留「已识过的外屏」静态图，避免镜子套娃。
  void _clearPreviewIfLooksLikeCoco() {
    final bytes = state.latestFrame;
    final baseline = _cocoBaselineHash;
    if (bytes == null || bytes.isEmpty || baseline == null) return;
    final hash = screenFrameFingerprint(bytes);
    // 与基线相近 → 多半是可可界面或套娃，不要展示
    if (!screenFramesDiffer(hash, baseline, minDelta: 12)) {
      state = state.copyWith(clearFrame: true);
      return;
    }
    // 已有外屏静态帧则保留（不直播刷新）
  }

  /// App 前后台变化：安卓后台开启自动首看监视。
  void onAppLifecycle({required bool inForeground}) {
    if (!state.isSharing) {
      state = state.copyWith(appInForeground: inForeground);
      return;
    }
    state = state.copyWith(appInForeground: inForeground);
    if (inForeground) {
      _stopWatchTimer();
      _changeDebounce?.cancel();
      // 回前台：更新基线；绝不启动直播预览轮询
      unawaited(_captureForegroundBaseline());
      unawaited(_syncPresence(looking: state.isBusy));
    } else {
      if (isAndroid) {
        _startBackgroundWatch();
      }
      unawaited(_syncPresence(looking: state.isBusy));
    }
  }

  void _startBackgroundWatch() {
    _watchTimer?.cancel();
    _recentHashes.clear();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      unawaited(_tickBackgroundWatch());
    });
  }

  void _stopWatchTimer() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  Future<void> _tickBackgroundWatch() async {
    if (!mounted || !state.isSharing || state.appInForeground) return;
    if (state.isBusy) return;

    final frame = await _capture.captureLatestFrameMeta();
    if (!mounted || frame == null || frame.bytes.isEmpty) return;
    final hash = screenFrameFingerprint(frame.bytes);
    _recentHashes.add(hash);
    if (_recentHashes.length > 4) {
      _recentHashes.removeAt(0);
    }

    final baseline = _cocoBaselineHash;
    final leftCoco =
        baseline == null || screenFramesDiffer(hash, baseline, minDelta: 12);
    final settled = screenFramesSettled(_recentHashes, maxDelta: 6);
    if (!leftCoco || !settled) return;

    if (!_didAutoFirstLook) {
      _didAutoFirstLook = true;
      await _runAutoAnalyze(kind: 'autoFirst', preferredBytes: frame.bytes);
      return;
    }

    final last = _lastAnalyzedHash;
    if (last != null && screenFramesDiffer(hash, last, minDelta: 16)) {
      // 换屏：防抖后再看，避免滑动过程连发
      _changeDebounce?.cancel();
      _changeDebounce = Timer(kScreenChangeDebounce, () {
        if (!mounted || !state.isSharing || state.appInForeground) return;
        if (state.isBusy) return;
        unawaited(_runAutoAnalyze(kind: 'autoChange'));
      });
    }
  }

  Future<void> _runAutoAnalyze({
    required String kind,
    Uint8List? preferredBytes,
  }) async {
    if (!mounted || !state.isSharing) return;
    final result = await captureAndAnalyze(
      question: null,
      preferredBytes: preferredBytes,
      requireLeftCoco: true,
    );
    if (result == null) {
      if (kind == 'autoFirst') {
        // 首看失败允许再试（例如仍像基线）
        _didAutoFirstLook = false;
      }
      return;
    }
    onAutoLookResult?.call(result, kind: kind);
  }

  /// 用户开口：前台只 coaching；后台 settle 后识图。
  Future<LookResult?> analyzeForUtterance({String? question}) async {
    if (!state.isSharing) return null;

    if (isAndroid && state.appInForeground) {
      onCoachingOnly?.call(ScreenShareState.stayOnCocoSpeech);
      return null;
    }

    if (isAndroid && !state.appInForeground) {
      final settled = await _waitUntilSettledAwayFromBaseline();
      if (!settled) {
        onCoachingOnly?.call(ScreenShareState.stayOnCocoSpeech);
        return null;
      }
    }

    return captureAndAnalyze(question: question, requireLeftCoco: isAndroid);
  }

  /// 抽当前帧并识图；成功返回 LookResult 供首页 inject。
  Future<LookResult?> captureAndAnalyze({
    String? question,
    Uint8List? preferredBytes,
    bool requireLeftCoco = false,
  }) async {
    if (!state.isSharing && state.phase != ScreenSharePhase.sharingIdle) {
      return null;
    }
    final gen = ++_opGen;
    final wasViewing = state.phase == ScreenSharePhase.viewing;
    state = state.copyWith(
      phase: wasViewing
          ? ScreenSharePhase.reAnalyzing
          : ScreenSharePhase.analyzing,
      clearError: true,
      clearBlock: true,
    );
    unawaited(_syncPresence(looking: true));

    final still = await _capture.isCapturing();
    if (!still) {
      if (!mounted || gen != _opGen) return null;
      state = const ScreenShareState(
        phase: ScreenSharePhase.error,
        errorTitle: '看手机已经停了',
        errorMessage: '需要的话可以再点一次「看手机」。',
      );
      unawaited(_syncPresence(looking: false));
      return null;
    }

    Uint8List? frameBytes = preferredBytes;
    if (frameBytes == null || frameBytes.isEmpty) {
      final fresh = await _waitForFreshFrame(maxAttempts: 3);
      if (!mounted || gen != _opGen) return null;
      frameBytes = fresh?.bytes;
    }

    if (frameBytes == null || frameBytes.isEmpty) {
      state = state.copyWith(
        phase: ScreenSharePhase.sharingIdle,
        errorTitle: '还没看到画面',
        errorMessage: '请先打开要看的页面，再说「你看」或直接问我。',
      );
      unawaited(_syncPresence(looking: false));
      return null;
    }

    final hash = screenFrameFingerprint(frameBytes);
    if (requireLeftCoco &&
        _cocoBaselineHash != null &&
        !screenFramesDiffer(hash, _cocoBaselineHash!, minDelta: 12)) {
      state = state.copyWith(
        phase: ScreenSharePhase.sharingIdle,
        latestFrame: frameBytes,
      );
      unawaited(_syncPresence(looking: false));
      onCoachingOnly?.call(ScreenShareState.stayOnCocoSpeech);
      return null;
    }

    state = state.copyWith(latestFrame: frameBytes);
    final result = await _look.analyzeBytes(
      source: LookSource.screen,
      bytes: frameBytes,
      filename: 'screen.jpg',
      question: question,
    );
    if (!mounted || gen != _opGen) return null;

    if (result == null) {
      // 识图失败：保持投屏，回到可追问/等待
      state = state.copyWith(
        phase: ScreenSharePhase.sharingIdle,
        latestFrame: frameBytes,
      );
      unawaited(_syncPresence(looking: false));
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

    _lastAnalyzedHash = hash;
    _didAutoFirstLook = true;
    state = state.copyWith(
      phase: ScreenSharePhase.viewing,
      latestFrame: frameBytes,
      clearError: true,
    );
    unawaited(_syncPresence(looking: false));
    return result;
  }

  /// 等待画面离开可可基线并 settle；超时返回 false。
  Future<bool> _waitUntilSettledAwayFromBaseline() async {
    _recentHashes.clear();
    for (var i = 0; i < 8; i++) {
      if (!mounted || !state.isSharing) return false;
      final frame = await _waitForFreshFrame(maxAttempts: 2);
      if (frame == null) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final hash = screenFrameFingerprint(frame.bytes);
      _recentHashes.add(hash);
      if (_recentHashes.length > 3) _recentHashes.removeAt(0);
      final baseline = _cocoBaselineHash;
      final left =
          baseline == null || screenFramesDiffer(hash, baseline, minDelta: 12);
      if (left && screenFramesSettled(_recentHashes, maxDelta: 6)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  /// 取够新的帧；过旧则短暂重试。
  Future<ScreenShareFrame?> _waitForFreshFrame({int maxAttempts = 3}) async {
    for (var i = 0; i < maxAttempts; i++) {
      final meta = await _capture.captureLatestFrameMeta();
      if (meta != null &&
          meta.bytes.isNotEmpty &&
          meta.age() <= kScreenFrameMaxAge) {
        return meta;
      }
      // 无时间戳的旧原生：有 bytes 也接受
      if (meta != null &&
          meta.bytes.isNotEmpty &&
          meta.capturedAtMs <= 0 &&
          i == maxAttempts - 1) {
        return meta;
      }
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
    final last = await _capture.captureLatestFrameMeta();
    if (last != null && last.bytes.isNotEmpty) return last;
    return null;
  }

  Future<void> _syncPresence({required bool looking}) async {
    if (!isAndroid || !state.isSharing) return;
    final text = looking ? '可可正在看你的屏幕' : '打开要看的页面后跟我说';
    unawaited(_capture.updateNotification(text));
    // 悬浮球只在后台更新，避免盖住可可自己界面
    if (!state.appInForeground) {
      final mode = looking ? 'looking' : 'watching';
      unawaited(_voiceBg.updateBubbleMode(mode));
    }
  }

  /// 服务端 / 工具要求停投屏。
  Future<void> applyStopScreen({String? reason}) async {
    await _blockAndStop(
      reason: reason?.trim().isNotEmpty == true ? reason!.trim() : '已停止看屏幕。',
    );
  }

  Future<void> _blockAndStop({required String reason}) async {
    _permissionTimeout?.cancel();
    _stopAllTimers();
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
    _stopAllTimers();
    await _capture.stop();
    if (!mounted || gen != _opGen) return;
    _look.closeVisualSession();
    _cocoBaselineHash = null;
    _lastAnalyzedHash = null;
    _didAutoFirstLook = false;
    state = const ScreenShareState();
  }

  void _stopAllTimers() {
    _stopWatchTimer();
    _changeDebounce?.cancel();
    _changeDebounce = null;
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

  void clearOverlayHint() {
    if (state.needsOverlayHint) {
      state = state.copyWith(needsOverlayHint: false);
    }
  }

  /// 同步服务端 vision.state（投屏看图中）。
  void applyServerVisionPhase(String phase) {
    if (!state.isSharing && state.phase != ScreenSharePhase.viewing) return;
    switch (phase) {
      case 'reanalyzing':
        state = state.copyWith(phase: ScreenSharePhase.reAnalyzing);
        unawaited(_syncPresence(looking: true));
      case 'viewing':
        if (state.phase == ScreenSharePhase.reAnalyzing ||
            state.phase == ScreenSharePhase.analyzing) {
          state = state.copyWith(phase: ScreenSharePhase.viewing);
          unawaited(_syncPresence(looking: false));
        }
      default:
        break;
    }
  }

  @override
  void dispose() {
    _permissionTimeout?.cancel();
    _stopAllTimers();
    unawaited(_capture.stop());
    super.dispose();
  }
}

final screenShareControllerProvider =
    StateNotifierProvider<ScreenShareController, ScreenShareState>((ref) {
      return ScreenShareController(ref);
    });
