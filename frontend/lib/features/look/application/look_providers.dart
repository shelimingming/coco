/// 识图追问页阶段（点按说话，不切实时语音模型）。
enum LookAskPhase { idle, listening, thinking, speaking, error }

class LookAskUiState {
  const LookAskUiState({
    this.phase = LookAskPhase.idle,
    this.replyText = '',
    this.userCaption = '',
    this.errorTitle,
    this.errorMessage,
  });

  final LookAskPhase phase;
  final String replyText;
  final String userCaption;
  final String? errorTitle;
  final String? errorMessage;

  LookAskUiState copyWith({
    LookAskPhase? phase,
    String? replyText,
    String? userCaption,
    String? errorTitle,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LookAskUiState(
      phase: phase ?? this.phase,
      replyText: replyText ?? this.replyText,
      userCaption: userCaption ?? this.userCaption,
      errorTitle: clearError ? null : (errorTitle ?? this.errorTitle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
