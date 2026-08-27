/// 家庭绑定领域模型。
class FamilyInvite {
  const FamilyInvite({
    required this.code,
    required this.inviteUrl,
    required this.targetRole,
    required this.inviterDisplayName,
    required this.familyId,
  });

  final String code;
  final String inviteUrl;
  final String targetRole;
  final String inviterDisplayName;
  final String familyId;

  factory FamilyInvite.fromJson(Map<String, dynamic> json) {
    return FamilyInvite(
      code: json['code'] as String,
      inviteUrl: json['invite_url'] as String,
      targetRole: json['target_role'] as String,
      inviterDisplayName: json['inviter_display_name'] as String,
      familyId: json['family_id'] as String,
    );
  }
}

class FamilyInvitePreview {
  const FamilyInvitePreview({
    required this.status,
    this.inviterDisplayName,
    this.targetRole,
    this.familyId,
  });

  final String status;
  final String? inviterDisplayName;
  final String? targetRole;
  final String? familyId;

  bool get isValid => status == 'valid';

  factory FamilyInvitePreview.fromJson(Map<String, dynamic> json) {
    return FamilyInvitePreview(
      status: json['status'] as String,
      inviterDisplayName: json['inviter_display_name'] as String?,
      targetRole: json['target_role'] as String?,
      familyId: json['family_id'] as String?,
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
    this.parentPhone,
  });

  final String id;
  // pending 时可能只有一侧
  final String? parentUserId;
  final String? childUserId;
  final String status;
  final String? parentDisplayName;
  final String? childDisplayName;
  // 子女视角下发的长辈 11 位号；父母视角为 null
  final String? parentPhone;

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
      parentPhone: json['parent_phone'] as String?,
    );
  }
}
