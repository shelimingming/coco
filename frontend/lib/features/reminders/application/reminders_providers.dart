import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/local_notifications.dart';
import '../data/reminders_api.dart';
import '../domain/models.dart';

/// 创建 / 修改 / 反馈后立即重排本地定时，杀进程后仍能到点响。
Future<void> rescheduleLocalReminders({
  required RemindersApi api,
  required LocalNotificationService local,
  LocalReminderSchedule? snoozeOverride,
}) async {
  try {
    final reminders = await api.list();
    final schedules = reminders
        .where((r) => r.isActive && r.nextTriggerAt != null)
        .map(
          (r) => LocalReminderSchedule(
            id: r.id,
            title: r.title,
            nextTriggerAt: r.nextTriggerAt!,
          ),
        )
        .toList();
    if (snoozeOverride != null) {
      schedules.removeWhere((item) => item.id == snoozeOverride.id);
      schedules.add(snoozeOverride);
    }
    await local.scheduleReminders(schedules);
  } catch (_) {
    // 排程失败不阻断主流程；退后台仍有兜底重排
  }
}

final remindersListProvider = FutureProvider.autoDispose<List<Reminder>>((
  ref,
) async {
  return ref.watch(remindersApiProvider).list();
});

/// 子女自己建议过的提醒列表。
final childSuggestionsProvider = FutureProvider.autoDispose<List<Reminder>>((
  ref,
) async {
  return ref.watch(remindersApiProvider).listSuggestions();
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
