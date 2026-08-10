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

  /// 结果页 / 追问页可朗读的结论短句。
  String get spokenSummary {
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
      return '我看不太清这上面的字。';
    }
    return parts.join(' ');
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

/// 取图成功后带本地路径进入结果页 / 追问页。
class LookSession {
  const LookSession({required this.result, required this.imagePath});

  final LookResult result;
  final String imagePath;
}

/// 追问页入参：同会话继续看图。
class LookAskArgs {
  const LookAskArgs({
    required this.conversationId,
    required this.imagePath,
    required this.headline,
    required this.spokenSummary,
  });

  final String conversationId;
  final String imagePath;
  final String headline;
  final String spokenSummary;
}
