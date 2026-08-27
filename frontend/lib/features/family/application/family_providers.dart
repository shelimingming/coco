import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/family_api.dart';
import '../domain/models.dart';

/// 落地页登录前后传递邀请码，避免跳转时丢掉链接里的 code。
final pendingInviteCodeProvider = StateProvider<String?>((ref) => null);

/// 当前家庭；未绑定时为 null（不抛错，方便页面分支）。
final familyInfoProvider = FutureProvider.autoDispose<FamilyInfo?>((ref) async {
  try {
    return await ref.watch(familyApiProvider).getFamily();
  } on ApiException catch (error) {
    if (error.code == 'family.not_found' || error.statusCode == 404) {
      return null;
    }
    rethrow;
  }
});
