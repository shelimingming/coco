/// 家庭绑定领域模型。
class FamilyInvite {
  const FamilyInvite({
    required this.code,
    required this.expiresAt,
    required this.familyId,
  });

  final String code;
  final DateTime expiresAt;
  final String familyId;

  factory FamilyInvite.fromJson(Map<String, dynamic> json) {
    return FamilyInvite(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      familyId: json['family_id'] as String,
    );
  }
}

class FamilyInfo {
  const FamilyInfo({
    required this.id,
    required this.status,
    this.parentUserId,
    this.childUserId,
    this.parentDisplayName,
    this.childDisplayName,
  });

  final String id;
  // pending 时可能只有一侧
  final String? parentUserId;
  final String? childUserId;
  final String status;
  final String? parentDisplayName;
  final String? childDisplayName;

  bool get isActive =>
      status == 'active' && parentUserId != null && childUserId != null;

  factory FamilyInfo.fromJson(Map<String, dynamic> json) {
    return FamilyInfo(
      id: json['id'] as String,
      parentUserId: json['parent_user_id'] as String?,
      childUserId: json['child_user_id'] as String?,
      status: json['status'] as String,
      parentDisplayName: json['parent_display_name'] as String?,
      childDisplayName: json['child_display_name'] as String?,
    );
  }
}
