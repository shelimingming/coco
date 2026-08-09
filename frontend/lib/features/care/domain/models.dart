/// 关怀摘要与子女今日状态。
class CareShare {
  const CareShare({
    required this.id,
    required this.parentId,
    required this.childId,
    required this.summary,
    required this.urgency,
    required this.replyExpectation,
    required this.source,
    required this.parentConfirmed,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String parentId;
  final String childId;
  final String summary;
  final String urgency;
  final String replyExpectation;
  final String source;
  final bool parentConfirmed;
  final DateTime? readAt;
  final DateTime createdAt;

  factory CareShare.fromJson(Map<String, dynamic> json) {
    return CareShare(
      id: json['id'] as String,
      parentId: json['parent_id'] as String,
      childId: json['child_id'] as String,
      summary: json['summary'] as String,
      urgency: json['urgency'] as String,
      replyExpectation: json['reply_expectation'] as String,
      source: json['source'] as String,
      parentConfirmed: json['parent_confirmed'] as bool? ?? false,
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ChildTodayReminderItem {
  const ChildTodayReminderItem({
    required this.title,
    required this.state,
    required this.dueAt,
  });

  final String title;
  final String state;
  final DateTime dueAt;

  factory ChildTodayReminderItem.fromJson(Map<String, dynamic> json) {
    return ChildTodayReminderItem(
      title: json['title'] as String,
      state: json['state'] as String,
      dueAt: DateTime.parse(json['due_at'] as String),
    );
  }
}

/// 子女首页三级状态：纯规则，不过模型。
enum ChildTodayStatus {
  normal,
  attention,
  needContact;

  static ChildTodayStatus fromJson(String value) {
    switch (value) {
      case 'ATTENTION':
        return ChildTodayStatus.attention;
      case 'NEED_CONTACT':
        return ChildTodayStatus.needContact;
      default:
        return ChildTodayStatus.normal;
    }
  }
}

class ChildToday {
  const ChildToday({
    required this.status,
    required this.headline,
    required this.attentionItems,
    required this.reminderItems,
    this.needsContactReason,
  });

  final ChildTodayStatus status;
  final String headline;
  final List<CareShare> attentionItems;
  final List<ChildTodayReminderItem> reminderItems;
  final String? needsContactReason;

  factory ChildToday.fromJson(Map<String, dynamic> json) {
    final attention = (json['attention_items'] as List<dynamic>? ?? [])
        .map((e) => CareShare.fromJson(asMap(e)))
        .toList();
    final reminders = (json['reminder_items'] as List<dynamic>? ?? [])
        .map((e) => ChildTodayReminderItem.fromJson(asMap(e)))
        .toList();
    return ChildToday(
      status: ChildTodayStatus.fromJson(json['status'] as String? ?? 'NORMAL'),
      headline: json['headline'] as String? ?? '',
      attentionItems: attention,
      reminderItems: reminders,
      needsContactReason: json['needs_contact_reason'] as String?,
    );
  }
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, dynamic item) => MapEntry(key.toString(), item));
  }
  return {};
}
