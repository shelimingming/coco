import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/care_api.dart';
import '../domain/models.dart';

/// 子女今日状态；未绑定家庭时抛出带 code 的 ApiException，页面据此引导加入。
final childTodayProvider = FutureProvider.autoDispose<ChildToday>((ref) async {
  return ref.watch(careApiProvider).childToday();
});

/// 关怀摘要全量（含已读），供详情页。
final careSharesProvider = FutureProvider.autoDispose<List<CareShare>>((
  ref,
) async {
  return ref.watch(careApiProvider).listShares();
});

/// 标记单条已读并刷新近况与详情列表。
Future<void> markCareShareRead(WidgetRef ref, String shareId) async {
  await ref.read(careApiProvider).markShareRead(shareId);
  ref.invalidate(childTodayProvider);
  ref.invalidate(careSharesProvider);
}

/// 是否因未绑定家庭而失败（只认业务码，避免其它 404 被误判成未绑定）。
bool isFamilyNotFound(Object error) {
  return error is ApiException && error.code == 'family.not_found';
}
