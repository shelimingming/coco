class LookResult {
  const LookResult({
    required this.confidence,
    required this.headline,
    required this.detail,
    required this.safetyNote,
    required this.sceneDescription,
    this.conversationId,
    this.shouldStopScreen = false,
  });

  final String confidence;
  final String headline;
  final String detail;
  final String safetyNote;

  /// 注入 Realtime 语音的详细读图文本
  final String sceneDescription;
  final String? conversationId;

  /// 投屏场景：服务端判定应停止看手机（支付/验证码等）
  final bool shouldStopScreen;

  bool get isClear => confidence == 'high' && headline.trim().isNotEmpty;

  factory LookResult.fromJson(Map<String, dynamic> json) {
    final headline = json['headline']?.toString() ?? '';
    final detail = json['detail']?.toString() ?? '';
    final safetyNote = json['safety_note']?.toString() ?? '';
    var scene = json['scene_description']?.toString().trim() ?? '';
    // 旧响应无 scene_description 时用短句兜底
    if (scene.isEmpty) {
      final parts = <String>[
        if (headline.trim().isNotEmpty) headline.trim(),
        if (detail.trim().isNotEmpty) detail.trim(),
        if (safetyNote.trim().isNotEmpty) safetyNote.trim(),
      ];
      scene = parts.isEmpty ? '我看不太清这上面的字。' : parts.join(' ');
    }
    final stopRaw = json['should_stop_screen'];
    final shouldStop =
        stopRaw == true ||
        stopRaw == 1 ||
        stopRaw?.toString().toLowerCase() == 'true';
    return LookResult(
      confidence: json['confidence']?.toString() ?? 'low',
      headline: headline,
      detail: detail,
      safetyNote: safetyNote,
      sceneDescription: scene,
      conversationId: json['conversation_id']?.toString(),
      shouldStopScreen: shouldStop,
    );
  }
}
