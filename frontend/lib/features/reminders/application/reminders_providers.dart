import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reminders_api.dart';
import '../domain/models.dart';

final remindersListProvider =
    FutureProvider.autoDispose<List<Reminder>>((ref) async {
  return ref.watch(remindersApiProvider).list();
});

/// 最近一项活跃提醒，供父母首页展示。
final nextReminderProvider = Provider.autoDispose<AsyncValue<Reminder?>>((ref) {
  return ref.watch(remindersListProvider).whenData((list) {
    final active = list.where((r) => r.isActive).toList()
      ..sort((a, b) {
        final at = a.nextTriggerAt;
        final bt = b.nextTriggerAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
    return active.isEmpty ? null : active.first;
  });
});
