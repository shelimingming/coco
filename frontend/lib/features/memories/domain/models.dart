/// 长期记忆领域模型（Mem0 代理）。
class Memory {
  const Memory({
    required this.id,
    required this.content,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String content;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Memory.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(Object? value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value);
    }

    return Memory(
      id: json['id'] as String,
      content: json['content'] as String,
      createdAt: parseTs(json['created_at']),
      updatedAt: parseTs(json['updated_at']),
    );
  }
}
