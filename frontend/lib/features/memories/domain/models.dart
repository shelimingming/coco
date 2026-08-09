/// 长期记忆领域模型。
class Memory {
  const Memory({
    required this.id,
    required this.content,
    required this.category,
    required this.source,
    required this.confirmed,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String content;
  final String category;
  final String source;
  final bool confirmed;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get categoryLabel {
    switch (category) {
      case 'PROFILE':
        return '关于我';
      case 'FAMILY':
        return '家人';
      case 'PREFERENCE':
        return '喜好';
      case 'ROUTINE':
        return '日常习惯';
      default:
        return category;
    }
  }

  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['id'] as String,
      content: json['content'] as String,
      category: json['category'] as String,
      source: json['source'] as String,
      confirmed: json['confirmed'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
