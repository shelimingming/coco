/// 父母端对话历史领域模型。
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.channel,
    required this.title,
    required this.preview,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final String channel;

  /// 结束通话时 LLM 生成的短标题；为空时用 preview。
  final String? title;
  final String preview;

  /// 列表主文案：优先标题，再回退预览。
  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    if (preview.trim().isNotEmpty) return preview;
    return '这次还没有记下说话内容';
  }

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.parse(json['ended_at'] as String),
      status: json['status'] as String,
      channel: json['channel'] as String,
      title: json['title'] as String?,
      preview: json['preview'] as String? ?? '',
    );
  }
}

class ConversationItem {
  const ConversationItem({
    required this.id,
    required this.seq,
    required this.kind,
    required this.text,
    required this.toolName,
    required this.displaySummary,
    required this.createdAt,
  });

  final String id;
  final int seq;
  final String kind;
  final String? text;
  final String? toolName;
  final String? displaySummary;
  final DateTime createdAt;

  bool get isUser => kind == 'USER';
  bool get isAssistant => kind == 'ASSISTANT';
  bool get isTool => kind == 'TOOL';

  factory ConversationItem.fromJson(Map<String, dynamic> json) {
    return ConversationItem(
      id: json['id'] as String,
      seq: json['seq'] as int,
      kind: json['kind'] as String,
      text: json['text'] as String?,
      toolName: json['tool_name'] as String?,
      displaySummary: json['display_summary'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ConversationDetail {
  const ConversationDetail({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.channel,
    required this.title,
    required this.items,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final String channel;
  final String? title;
  final List<ConversationItem> items;

  factory ConversationDetail.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return ConversationDetail(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.parse(json['ended_at'] as String),
      status: json['status'] as String,
      channel: json['channel'] as String,
      title: json['title'] as String?,
      items: rawItems
          .map((e) => ConversationItem.fromJson(asHistoryJsonMap(e)))
          .toList(),
    );
  }
}

/// 与 API 层 asJsonMap 解耦的轻量转换，避免 domain 依赖 network。
Map<String, dynamic> asHistoryJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, dynamic v) => MapEntry(key.toString(), v));
  }
  throw FormatException('expected JSON object, got $value');
}
