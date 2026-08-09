/// 应用内通知领域模型。
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String type; // REMINDER / CARE_MESSAGE / CHILD_STATUS
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;
  bool get isReminder => type == 'REMINDER';
  bool get isCareMessage => type == 'CARE_MESSAGE';
  bool get isChildStatus => type == 'CHILD_STATUS';

  String? get reminderId => payload['reminder_id']?.toString();
  String? get occurrenceId => payload['occurrence_id']?.toString();

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    Map<String, dynamic> payload = {};
    if (rawPayload is Map<String, dynamic>) {
      payload = rawPayload;
    } else if (rawPayload is Map) {
      payload = rawPayload.map(
        (key, dynamic item) => MapEntry(key.toString(), item),
      );
    }
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      payload: payload,
      readAt: json['read_at'] == null
          ? null
          : DateTime.parse(json['read_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
