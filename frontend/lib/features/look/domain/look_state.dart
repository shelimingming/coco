import 'dart:typed_data';

/// 看一看取图/识图阶段；照片在关图前一直留在首页。
enum LookPhase {
  /// 未选图或已清空
  idle,

  /// 首轮上传识图中
  initialAnalyzing,

  /// 照片常驻，可追问
  viewing,

  /// 服务端按当前问题重新识图
  reAnalyzing,

  /// 出错（识图 / 权限等）
  error,
}

/// 图片来源：只影响取图方式与首轮默认问题。
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

  /// 注入 Realtime 时的来源标识。
  String get wireName => switch (this) {
    LookSource.camera => 'camera',
    LookSource.screenshot => 'screenshot',
    LookSource.album => 'album',
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
    this.sceneDescription = '',
    this.isClear = false,
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

  /// 注入 Realtime 的详细读图文本
  final String sceneDescription;
  final bool isClear;

  /// 非错误提示（如截屏降级到相册）
  final String? notice;
  final String? errorTitle;
  final String? errorMessage;

  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;

  /// 正在占用中间区的看图会话（含失败但图还在）
  bool get isVisualSession =>
      hasImage &&
      (phase == LookPhase.initialAnalyzing ||
          phase == LookPhase.viewing ||
          phase == LookPhase.reAnalyzing ||
          phase == LookPhase.error);

  bool get isBusy =>
      phase == LookPhase.initialAnalyzing || phase == LookPhase.reAnalyzing;

  /// 扫描特效只在初次看 / 复看分析中出现
  bool get showScanBrackets =>
      phase == LookPhase.initialAnalyzing || phase == LookPhase.reAnalyzing;

  /// 可交给语音的读图结果
  bool get canInject =>
      phase == LookPhase.viewing && sceneDescription.trim().isNotEmpty;

  String get statusLabel => switch (phase) {
    LookPhase.idle when !hasImage => '选一张图，我帮你看',
    LookPhase.idle => '照片已选好',
    LookPhase.initialAnalyzing => '可可正在看',
    LookPhase.viewing => '可以问可可',
    LookPhase.reAnalyzing => '我再仔细看一下',
    LookPhase.error => errorTitle ?? '出了点问题',
  };

  LookState copyWith({
    LookPhase? phase,
    LookSource? source,
    Uint8List? imageBytes,
    String? conversationId,
    String? headline,
    String? detail,
    String? safetyNote,
    String? sceneDescription,
    bool? isClear,
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
      sceneDescription: clearImage
          ? ''
          : (sceneDescription ?? this.sceneDescription),
      isClear: clearImage ? false : (isClear ?? this.isClear),
      notice: clearNotice ? null : (notice ?? this.notice),
      errorTitle: clearError ? null : (errorTitle ?? this.errorTitle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
