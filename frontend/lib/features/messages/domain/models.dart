/// 子女报平安领域模型。
class MessagePreview {
  const MessagePreview({
    required this.originalText,
    required this.deliveredText,
    required this.translated,
  });

  final String originalText;
  final String deliveredText;
  final bool translated;

  factory MessagePreview.fromJson(Map<String, dynamic> json) {
    return MessagePreview(
      originalText: json['original_text'] as String,
      deliveredText: json['delivered_text'] as String,
      translated: json['translated'] as bool? ?? false,
    );
  }
}

class FamilyMessage {
  const FamilyMessage({
    required this.id,
    required this.familyId,
    required this.fromUserId,
    required this.toUserId,
    required this.kind,
    required this.originalText,
    required this.deliveredText,
    required this.createdAt,
    this.acknowledgedAt,
  });

  final String id;
  final String familyId;
  final String fromUserId;
  final String toUserId;
  final String kind;
  final String originalText;
  final String deliveredText;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;

  factory FamilyMessage.fromJson(Map<String, dynamic> json) {
    return FamilyMessage(
      id: json['id'] as String,
      familyId: json['family_id'] as String,
      fromUserId: json['from_user_id'] as String,
      toUserId: json['to_user_id'] as String,
      kind: json['kind'] as String,
      originalText: json['original_text'] as String,
      deliveredText: json['delivered_text'] as String,
      acknowledgedAt: json['acknowledged_at'] == null
          ? null
          : DateTime.parse(json['acknowledged_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
