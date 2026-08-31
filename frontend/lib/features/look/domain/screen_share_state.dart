import 'dart:typed_data';

/// 看手机投屏会话阶段（与看照片 LookPhase 并行，由 ScreenShareController 持有）。
enum ScreenSharePhase {
  /// 未投屏
  idle,

  /// 说明确认卡
  confirming,

  /// 等待系统投屏授权
  awaitingPermission,

  /// 广播/投屏拉起中
  starting,

  /// 已共享，尚无可用帧 / 等用户去目标页
  sharingIdle,

  /// 抽帧识图中
  analyzing,

  /// 有帧，可追问
  viewing,

  /// 服务端重识图或新帧分析中
  reAnalyzing,

  /// 安全终止（投屏已停）
  blocked,

  /// 权限/系统失败
  error,
}

/// 投屏会话 UI / 编排状态。
class ScreenShareState {
  const ScreenShareState({
    this.phase = ScreenSharePhase.idle,
    this.latestFrame,
    this.blockReason,
    this.errorTitle,
    this.errorMessage,
    this.showIosGuide = false,
    this.appInForeground = true,
    this.needsOverlayHint = false,
  });

  final ScreenSharePhase phase;
  final Uint8List? latestFrame;
  final String? blockReason;
  final String? errorTitle;
  final String? errorMessage;

  /// iOS 系统广播三步引导叠层
  final bool showIosGuide;

  /// App 是否在前台（安卓自动首看 / 前台开口拦截用）
  final bool appInForeground;

  /// 投屏成功但无悬浮窗权限时提示一次
  final bool needsOverlayHint;

  bool get isActive =>
      phase != ScreenSharePhase.idle &&
      phase != ScreenSharePhase.error &&
      phase != ScreenSharePhase.blocked;

  /// 占用中间区（含确认卡、引导、有帧/无帧共享）
  bool get occupiesCenter =>
      phase == ScreenSharePhase.confirming ||
      phase == ScreenSharePhase.awaitingPermission ||
      phase == ScreenSharePhase.starting ||
      phase == ScreenSharePhase.sharingIdle ||
      phase == ScreenSharePhase.analyzing ||
      phase == ScreenSharePhase.viewing ||
      phase == ScreenSharePhase.reAnalyzing ||
      phase == ScreenSharePhase.blocked ||
      (phase == ScreenSharePhase.error && errorMessage != null);

  bool get isSharing =>
      phase == ScreenSharePhase.sharingIdle ||
      phase == ScreenSharePhase.analyzing ||
      phase == ScreenSharePhase.viewing ||
      phase == ScreenSharePhase.reAnalyzing;

  bool get isBusy =>
      phase == ScreenSharePhase.analyzing ||
      phase == ScreenSharePhase.reAnalyzing ||
      phase == ScreenSharePhase.starting ||
      phase == ScreenSharePhase.awaitingPermission;

  bool get showScanBrackets =>
      phase == ScreenSharePhase.analyzing ||
      phase == ScreenSharePhase.reAnalyzing;

  String get statusLabel => switch (phase) {
    ScreenSharePhase.idle => '',
    ScreenSharePhase.confirming => '让可可看看你的手机',
    ScreenSharePhase.awaitingPermission ||
    ScreenSharePhase.starting => '按提示打开看手机权限',
    ScreenSharePhase.sharingIdle => '去打开要看的页面，然后问我',
    ScreenSharePhase.analyzing => '可可正在看',
    ScreenSharePhase.viewing => '可以问可可',
    ScreenSharePhase.reAnalyzing => '我再仔细看一下',
    ScreenSharePhase.blocked => '已停止看屏幕',
    ScreenSharePhase.error => errorTitle ?? '看手机出了点问题',
  };

  /// 投屏成功后可可开口话术
  static const coachingSpeech = '好，我开始看手机了。你去打开那条短信或卡住的页面，打开后跟我说一声，或直接问我。';

  /// 仍在可可前台开口时的引导（不识图，避免描述自己界面）
  static const stayOnCocoSpeech = '请先打开要看的页面，再说一遍或直接问我。我在可可里时先不看屏幕内容。';

  ScreenShareState copyWith({
    ScreenSharePhase? phase,
    Uint8List? latestFrame,
    String? blockReason,
    String? errorTitle,
    String? errorMessage,
    bool? showIosGuide,
    bool? appInForeground,
    bool? needsOverlayHint,
    bool clearFrame = false,
    bool clearBlock = false,
    bool clearError = false,
  }) {
    return ScreenShareState(
      phase: phase ?? this.phase,
      latestFrame: clearFrame ? null : (latestFrame ?? this.latestFrame),
      blockReason: clearBlock ? null : (blockReason ?? this.blockReason),
      errorTitle: clearError ? null : (errorTitle ?? this.errorTitle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      showIosGuide: showIosGuide ?? this.showIosGuide,
      appInForeground: appInForeground ?? this.appInForeground,
      needsOverlayHint: needsOverlayHint ?? this.needsOverlayHint,
    );
  }
}
