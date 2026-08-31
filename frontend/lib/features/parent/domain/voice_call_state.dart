import 'pending_voice_action.dart';
import 'voice_call_transcript.dart';

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

  /// 用户暂停：停收音，保留当前 session 与上下文
  paused,

  /// 出错（页内展示说明，不自动消失）
  error,
}

/// 通话 UI 状态：阶段 + 字幕 + 本通聊天记录 + 可展示错误 + 待确认大卡。
class VoiceCallState {
  const VoiceCallState({
    this.phase = VoiceCallPhase.idle,
    this.userCaption = '',
    this.assistantCaption = '',
    this.transcript = const [],
    this.errorTitle,
    this.errorMessage,
    this.pendingAction,
    this.pendingActionBusy = false,
  });

  final VoiceCallPhase phase;
  final String userCaption;
  final String assistantCaption;

  /// 本次通话已落定的对话（结束通话后清空）。
  final List<VoiceCallTranscriptEntry> transcript;
  final String? errorTitle;
  final String? errorMessage;
  final PendingVoiceAction? pendingAction;
  final bool pendingActionBusy;

  /// 正在听/说（不含暂停）；后台恢复时据此判断是否开麦。
  bool get isActive =>
      phase == VoiceCallPhase.connecting ||
      phase == VoiceCallPhase.listening ||
      phase == VoiceCallPhase.thinking ||
      phase == VoiceCallPhase.speaking;

  /// 仍在同一会话（含暂停）；顶栏「字」、返回确认、看图复用会话。
  bool get isInSession => isActive || phase == VoiceCallPhase.paused;

  bool get isPaused => phase == VoiceCallPhase.paused;

  bool get canInterrupt => phase == VoiceCallPhase.speaking;

  String get statusLabel => switch (phase) {
    VoiceCallPhase.idle => '点我，我们说说话',
    VoiceCallPhase.connecting => '正在准备对话…',
    VoiceCallPhase.listening => '正在听您说',
    VoiceCallPhase.thinking => '我想一想',
    // 播报中点小狗可手动打断（无开口插话）
    VoiceCallPhase.speaking => '点我可以打断我～',
    VoiceCallPhase.paused => '聊天已暂停',
    VoiceCallPhase.error => errorTitle ?? '出了点问题',
  };

  /// 「字」面板展示用：已落定记录 + 当前正在说的半句。
  /// 注意：userCaption / assistantCaption 在下一轮 speech.started 前会残留，
  /// 不能在末条已是对方时再追加，否则会出现「您」重复一条。
  List<VoiceCallTranscriptEntry> get displayTranscript {
    final out = List<VoiceCallTranscriptEntry>.from(transcript);

    final user = userCaption.trim();
    if (user.isNotEmpty) {
      final last = out.isEmpty ? null : out.last;
      if (last?.role == VoiceCallTranscriptRole.user) {
        if (last!.text != user) {
          out[out.length - 1] = last.copyWith(text: user);
        }
      } else if (phase == VoiceCallPhase.listening) {
        // 倾听中才展示半句；若上一句「您」已落定且文字相同，不再插一条
        VoiceCallTranscriptEntry? lastUser;
        for (final entry in out.reversed) {
          if (entry.role == VoiceCallTranscriptRole.user) {
            lastUser = entry;
            break;
          }
        }
        if (lastUser?.text != user) {
          out.add(
            VoiceCallTranscriptEntry(
              role: VoiceCallTranscriptRole.user,
              text: user,
            ),
          );
        }
      }
    }

    final asst = assistantCaption.trim();
    if (asst.isNotEmpty) {
      final last = out.isEmpty ? null : out.last;
      if (last?.role == VoiceCallTranscriptRole.assistant) {
        if (last!.text != asst) {
          out[out.length - 1] = last.copyWith(text: asst);
        }
      } else if (phase == VoiceCallPhase.speaking) {
        out.add(
          VoiceCallTranscriptEntry(
            role: VoiceCallTranscriptRole.assistant,
            text: asst,
          ),
        );
      }
    }

    return out;
  }

  /// 看图时「字」只展示当前一轮：最近一条用户话 + 可可正在说/刚说完的话。
  List<VoiceCallTranscriptEntry> get currentRoundEntries {
    final entries = displayTranscript;
    if (entries.isEmpty) return const [];
    var start = 0;
    for (var i = entries.length - 1; i >= 0; i--) {
      if (entries[i].role == VoiceCallTranscriptRole.user) {
        start = i;
        break;
      }
    }
    return entries.sublist(start);
  }

  VoiceCallState copyWith({
    VoiceCallPhase? phase,
    String? userCaption,
    String? assistantCaption,
    List<VoiceCallTranscriptEntry>? transcript,
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
      transcript: transcript ?? this.transcript,
      errorTitle: clearError ? null : (errorTitle ?? this.errorTitle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingAction: clearPendingAction
          ? null
          : (pendingAction ?? this.pendingAction),
      pendingActionBusy: pendingActionBusy ?? this.pendingActionBusy,
    );
  }
}
