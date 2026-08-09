import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/messages_api.dart';
import '../domain/models.dart';

/// 子女端家庭留言列表（报平安记录）。
final familyMessagesProvider = FutureProvider.autoDispose<List<FamilyMessage>>((
  ref,
) async {
  return ref.watch(messagesApiProvider).list();
});
