class LookResult {
  const LookResult({
    required this.confidence,
    required this.headline,
    required this.detail,
    required this.safetyNote,
    this.conversationId,
  });

  final String confidence;
  final String headline;
  final String detail;
  final String safetyNote;
  final String? conversationId;

  bool get isClear => confidence == 'high' && headline.trim().isNotEmpty;

  /// 注入语音开场的短摘要（限长，适配 WS query）。
  String get voiceContext {
    final parts = <String>[];
    if (headline.trim().isNotEmpty) {
      parts.add(headline.trim());
    }
    if (detail.trim().isNotEmpty) {
      parts.add(detail.trim());
    }
    if (safetyNote.trim().isNotEmpty) {
      parts.add(safetyNote.trim());
    }
    if (parts.isEmpty) {
      return '刚才看了一张图，但看不太清。';
    }
    final text = parts.join(' ');
    if (text.length <= 360) return text;
    return '${text.substring(0, 360)}…';
  }

  factory LookResult.fromJson(Map<String, dynamic> json) {
    return LookResult(
      confidence: json['confidence']?.toString() ?? 'low',
      headline: json['headline']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      safetyNote: json['safety_note']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString(),
    );
  }
}
