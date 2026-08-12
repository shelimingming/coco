import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_notifications_stub.dart'
    if (dart.library.html) 'local_notifications_web.dart'
    if (dart.library.io) 'local_notifications_io.dart'
    as impl;

/// 待排本地定时的提醒摘要（避免 core 依赖 features 模型）。
class LocalReminderSchedule {
  const LocalReminderSchedule({
    required this.id,
    required this.title,
    required this.nextTriggerAt,
  });

  final String id;
  final String title;
  final DateTime nextTriggerAt;
}

/// 本地系统通知：前台即时弹出 +（原生）退后台定时；Web 用浏览器 Notification。
abstract class LocalNotificationService {
  /// 兼容旧调用：统一落到单例，避免 main 与 Riverpod 各初始化一份。
  factory LocalNotificationService() => instance;

  static LocalNotificationService get instance =>
      impl.createLocalNotificationService();

  /// 本次退后台时已为哪些 reminder 排了本地定时，供回前台去重。
  Set<String> get scheduledReminderIds;

  Future<void> ensureInitialized();

  Future<bool> requestPermissions();

  /// 立即弹出系统横幅（前台轮询到站内通知时用）。
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  });

  /// 为活跃提醒的下次触发时间排本地定时；Web 为空实现。
  Future<Set<String>> scheduleReminders(
    Iterable<LocalReminderSchedule> reminders,
  );

  Future<void> cancelReminder(String reminderId);

  Future<void> cancelAll();
}

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  return LocalNotificationService.instance;
});
