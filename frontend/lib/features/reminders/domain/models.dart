/// 日常提醒领域模型。
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.scheduleType,
    required this.scheduleTime,
    required this.status,
    required this.createdSource,
    required this.createdAt,
    this.nextTriggerAt,
    this.suggestedByUserId,
    this.suggestedByDisplayName,
  });

  final String id;
  final String title;
  final String scheduleType; // ONCE / DAILY
  final String scheduleTime; // HH:MM:SS
  final String status;
  final String createdSource;
  final DateTime? nextTriggerAt;
  final DateTime createdAt;
  final String? suggestedByUserId;
  final String? suggestedByDisplayName;

  bool get isActive => status == 'ACTIVE';
  bool get isPendingConfirm => status == 'PENDING_CONFIRM';
  bool get isRejected => status == 'REJECTED';
  bool get isDaily => scheduleType == 'DAILY';
  bool get isChildSuggested => createdSource == 'CHILD';

  /// 展示用时刻，如 20:00
  String get timeLabel {
    final parts = scheduleTime.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return scheduleTime;
  }

  String get scheduleMeta => '${isDaily ? '每天' : '一次'} $timeLabel';

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as String,
      title: json['title'] as String,
      scheduleType: json['schedule_type'] as String,
      scheduleTime: json['schedule_time'] as String,
      status: json['status'] as String,
      createdSource: json['created_source'] as String,
      nextTriggerAt: json['next_trigger_at'] == null
          ? null
          : DateTime.parse(json['next_trigger_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      suggestedByUserId: json['suggested_by_user_id']?.toString(),
      suggestedByDisplayName: json['suggested_by_display_name'] as String?,
    );
  }
}

class ReminderOccurrence {
  const ReminderOccurrence({
    required this.id,
    required this.reminderId,
    required this.dueAt,
    required this.deliveryState,
    required this.responseStatus,
    this.reminderRevision = 1,
    this.titleSnapshot = '',
    this.snoozeUntil,
    this.attemptCount = 0,
    this.responseSource = 'NONE',
    this.firstNotifiedAt,
    this.secondNotifiedAt,
    this.confirmedAt,
    this.escalatedAt,
  });

  final String id;
  final String reminderId;
  final DateTime dueAt;
  final String deliveryState;
  final String responseStatus;
  final int reminderRevision;
  final String titleSnapshot;
  final DateTime? snoozeUntil;
  final int attemptCount;
  final String responseSource;
  final DateTime? firstNotifiedAt;
  final DateTime? secondNotifiedAt;
  final DateTime? confirmedAt;
  final DateTime? escalatedAt;

  bool get isOpen =>
      deliveryState == 'PENDING' ||
      deliveryState == 'NOTIFIED_1' ||
      deliveryState == 'NOTIFIED_2';

  factory ReminderOccurrence.fromJson(Map<String, dynamic> json) {
    return ReminderOccurrence(
      id: json['id'] as String,
      reminderId: json['reminder_id'] as String,
      dueAt: DateTime.parse(json['due_at'] as String),
      deliveryState: json['delivery_state'] as String? ?? 'PENDING',
      responseStatus: json['response_status'] as String? ?? 'NONE',
      reminderRevision: json['reminder_revision'] as int? ?? 1,
      titleSnapshot: json['title_snapshot'] as String? ?? '',
      snoozeUntil: json['snooze_until'] == null
          ? null
          : DateTime.parse(json['snooze_until'] as String),
      attemptCount: json['attempt_count'] as int? ?? 0,
      responseSource: json['response_source'] as String? ?? 'NONE',
      firstNotifiedAt: json['first_notified_at'] == null
          ? null
          : DateTime.parse(json['first_notified_at'] as String),
      secondNotifiedAt: json['second_notified_at'] == null
          ? null
          : DateTime.parse(json['second_notified_at'] as String),
      confirmedAt: json['confirmed_at'] == null
          ? null
          : DateTime.parse(json['confirmed_at'] as String),
      escalatedAt: json['escalated_at'] == null
          ? null
          : DateTime.parse(json['escalated_at'] as String),
    );
  }
}
