/// 每日小记领域模型。
class DailyNoteSettings {
  const DailyNoteSettings({
    required this.generateEnabled,
    required this.shareToChildEnabled,
    required this.generateHour,
    required this.gender,
    required this.hasParentPhoto,
    this.parentPhotoUrl,
  });

  final bool generateEnabled;
  final bool shareToChildEnabled;
  final int generateHour;
  final String gender; // male / female / unknown
  final bool hasParentPhoto;
  /// BOS 签名 URL，可 Image.network 直连。
  final String? parentPhotoUrl;

  factory DailyNoteSettings.fromJson(Map<String, dynamic> json) {
    return DailyNoteSettings(
      generateEnabled: json['generate_enabled'] as bool? ?? true,
      shareToChildEnabled: json['share_to_child_enabled'] as bool? ?? false,
      generateHour: json['generate_hour'] as int? ?? 20,
      gender: json['gender'] as String? ?? 'unknown',
      hasParentPhoto: json['has_parent_photo'] as bool? ?? false,
      parentPhotoUrl: json['parent_photo_url'] as String?,
    );
  }
}

class DailyNoteImageMeta {
  const DailyNoteImageMeta({
    required this.id,
    required this.seq,
    required this.mimeType,
    required this.url,
  });

  final String id;
  final int seq;
  final String mimeType;
  /// BOS 签名 URL。
  final String url;

  factory DailyNoteImageMeta.fromJson(Map<String, dynamic> json) {
    return DailyNoteImageMeta(
      id: json['id'] as String,
      seq: json['seq'] as int? ?? 0,
      mimeType: json['mime_type'] as String? ?? 'image/png',
      url: json['url'] as String,
    );
  }
}

class DailyNote {
  const DailyNote({
    required this.id,
    required this.noteDate,
    required this.items,
    required this.bodyText,
    required this.status,
    required this.source,
    required this.images,
    required this.createdAt,
    this.sharedAt,
  });

  final String id;
  final DateTime noteDate;
  final List<String> items;
  final String bodyText;
  final String status;
  final String source;
  final DateTime? sharedAt;
  final List<DailyNoteImageMeta> images;
  final DateTime createdAt;

  bool get isReady => status == 'ready';
  bool get isEmpty => status == 'empty';

  factory DailyNote.fromJson(Map<String, dynamic> json) {
    final dateRaw = json['note_date'] as String;
    final imagesRaw = json['images'] as List<dynamic>? ?? const [];
    final itemsRaw = json['items'] as List<dynamic>? ?? const [];
    return DailyNote(
      id: json['id'] as String,
      noteDate: DateTime.parse(dateRaw),
      items: itemsRaw.map((e) => e.toString()).toList(),
      bodyText: json['body_text'] as String? ?? '',
      status: json['status'] as String? ?? '',
      source: json['source'] as String? ?? '',
      sharedAt: json['shared_at'] == null
          ? null
          : DateTime.parse(json['shared_at'] as String),
      images: imagesRaw
          .map((e) => DailyNoteImageMeta.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
