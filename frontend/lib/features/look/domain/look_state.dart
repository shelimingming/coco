import 'dart:typed_data';

/// 看一看单页阶段，对齐首页语音陪伴的 idle / listening / thinking / speaking。
enum LookPhase {
  /// 未选图或已重置，等待选来源
  idle,

  /// 上传识图中
  analyzing,

  /// 正在听用户追问
  listening,

  /// ASR + follow-up 处理中
  thinking,

  /// TTS 播报结论或回答
  speaking,

  /// 出错（识图 / 追问 / 权限等）
  error,
}

/// 图片来源：只影响取图方式与首轮默认问题，不影响后续追问流程。
enum LookSource { camera, screenshot, album }

extension LookSourceX on LookSource {
  /// 首轮识图默认问题，传给 POST /v1/vision/look 的 question 字段。
  String get defaultQuestion => switch (this) {
    LookSource.camera => '请帮我看看这是什么、上面写了什么。',
    LookSource.screenshot => '请帮我看看这条消息在说什么，有没有需要小心的地方。',
    LookSource.album => '请帮我看看这张照片里有什么。',
  };

  String get label => switch (this) {
    LookSource.camera => '拍一张',
    LookSource.screenshot => '最近截屏',
    LookSource.album => '相册',
  };
}

class LookState {
  const LookState({
    this.phase = LookPhase.idle,
    this.source,
    this.imageBytes,
    this.conversationId,
    this.headline = '',
    this.detail = '',
    this.safetyNote = '',
    this.replyText = '',
    this.userCaption = '',
    this.isClear = false,
    this.canFollowUp = true,
    this.notice,
    this.errorTitle,
    this.errorMessage,
  });

  final LookPhase phase;
  final LookSource? source;
  final Uint8List? imageBytes;
  final String? conversationId;
  final String headline;
  final String detail;
  final String safetyNote;

  /// 当前展示 / 朗读的文案（结论或追问回答）
  final String replyText;
  final String userCaption;
  final bool isClear;
  final bool canFollowUp;

  /// 非错误提示（如截屏降级到相册）
  final String? notice;
  final String? errorTitle;
  final String? errorMessage;

  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;

  bool get isBusy =>
      phase == LookPhase.analyzing ||
      phase == LookPhase.thinking ||
      phase == LookPhase.speaking;

  String get statusLabel => switch (phase) {
    LookPhase.idle when !hasImage => '选一张图，我帮你看',
    LookPhase.idle => '想继续问，直接说就行',
    LookPhase.analyzing => '可可正在看…',
    LookPhase.listening => '正在听您说',
    LookPhase.thinking => '我想一想',
    LookPhase.speaking => '我在说',
    LookPhase.error => errorTitle ?? '出了点问题',
  };

  String get primaryLabel => switch (phase) {
    LookPhase.listening => '我说完了',
    LookPhase.thinking => '可可正在想…',
    LookPhase.speaking => '打断',
    LookPhase.error => '换一张',
    LookPhase.idle when hasImage => '点一下开始说',
    _ => '',
  };

  LookState copyWith({
    LookPhase? phase,
    LookSource? source,
    Uint8List? imageBytes,
    String? conversationId,
    String? headline,
    String? detail,
    String? safetyNote,
    String? replyText,
    String? userCaption,
    bool? isClear,
    bool? canFollowUp,
    String? notice,
    String? errorTitle,
    String? errorMessage,
    bool clearImage = false,
    bool clearNotice = false,
    bool clearError = false,
  }) {
    return LookState(
      phase: phase ?? this.phase,
      source: source ?? this.source,
      imageBytes: clearImage ? null : (imageBytes ?? this.imageBytes),
      conversationId: clearImage
          ? null
          : (conversationId ?? this.conversationId),
      headline: clearImage ? '' : (headline ?? this.headline),
      detail: clearImage ? '' : (detail ?? this.detail),
      safetyNote: clearImage ? '' : (safetyNote ?? this.safetyNote),
      replyText: clearImage ? '' : (replyText ?? this.replyText),
      userCaption: clearImage ? '' : (userCaption ?? this.userCaption),
      isClear: clearImage ? false : (isClear ?? this.isClear),
      canFollowUp: clearImage ? true : (canFollowUp ?? this.canFollowUp),
      notice: clearNotice ? null : (notice ?? this.notice),
      errorTitle: clearError ? null : (errorTitle ?? this.errorTitle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
