import 'pending_voice_action.dart';

/// 父母端实时通话阶段；驱动形象姿态与文案。
enum VoiceCallPhase {
  /// 未通话
  idle,

  /// 正在连接语音服务
  connecting,

  /// 正在听用户说话
  listening,

  /// 用户说完，等待 / 生成回答
  thinking,

  /// Coco 正在播报
  speaking,

  /// 出错（页内展示说明，不自动消失）
  error,
}

/// 通话 UI 状态：阶段 + 字幕 + 可展示错误 + 待确认大卡。
class VoiceCallState {
  const VoiceCallState({
    this.phase = VoiceCallPhase.idle,
    this.userCaption = '',
    this.assistantCaption = '',
    this.errorTitle,
    this.errorMessage,
    this.pendingAction,
    this.pendingActionBusy = false,
  });

  final VoiceCallPhase phase;
  final String userCaption;
  final String assistantCaption;
  final String? errorTitle;
  final String? errorMessage;
  final PendingVoiceAction? pendingAction;
  final bool pendingActionBusy;

  bool get isActive =>
      phase == VoiceCallPhase.connecting ||
      phase == VoiceCallPhase.listening ||
      phase == VoiceCallPhase.thinking ||
      phase == VoiceCallPhase.speaking;

  bool get canInterrupt => phase == VoiceCallPhase.speaking;

  String get statusLabel => switch (phase) {
    VoiceCallPhase.idle => '点我，我们说说话',
    VoiceCallPhase.connecting => '正在准备对话…',
    VoiceCallPhase.listening => '正在听您说',
    VoiceCallPhase.thinking => '我想一想',
    VoiceCallPhase.speaking => '我在说',
    VoiceCallPhase.error => errorTitle ?? '出了点问题',
  };

  VoiceCallState copyWith({
    VoiceCallPhase? phase,
    String? userCaption,
    String? assistantCaption,
    String? errorTitle,
    String? errorMessage,
    bool clearError = false,
    PendingVoiceAction? pendingAction,
    bool clearPendingAction = false,
    bool? pendingActionBusy,
  }) {
    return VoiceCallState(
      phase: phase ?? this.phase,
      userCaption: userCaption ?? this.userCaption,
      assistantCaption: assistantCaption ?? this.assistantCaption,
      errorTitle: clearError ? null : (errorTitle ?? this.errorTitle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingAction: clearPendingAction
          ? null
          : (pendingAction ?? this.pendingAction),
      pendingActionBusy: pendingActionBusy ?? this.pendingActionBusy,
    );
  }
}
