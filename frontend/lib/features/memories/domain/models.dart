/// 用户主动要求记住的显式记忆。
class Memory {
  const Memory({
    required this.id,
    required this.content,
    this.category = '',
    this.source = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String content;
  final String category;
  final String source;
  final DateTime? createdAt;
  final DateTime? updatedAt;

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
        return '其他';
    }
  }

  factory Memory.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(Object? value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value);
    }

    return Memory(
      id: json['id'] as String,
      content: json['content'] as String,
      category: (json['category'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
      createdAt: parseTs(json['created_at']),
      updatedAt: parseTs(json['updated_at']),
    );
  }
}
