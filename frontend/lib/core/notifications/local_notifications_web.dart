import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'local_notifications.dart';

LocalNotificationService createLocalNotificationService() =>
    WebLocalNotificationService.instance;

/// Web：浏览器 Notification；不做 zonedSchedule 后台定时。
class WebLocalNotificationService implements LocalNotificationService {
  WebLocalNotificationService._();

  static final WebLocalNotificationService instance =
      WebLocalNotificationService._();

  bool _ready = false;

  @override
  final Set<String> scheduledReminderIds = {};

  @override
  Future<void> ensureInitialized() async {
    if (_ready) return;
    // 尽量请求权限；拒绝则 show 静默，依赖站内 pending 卡。
    await requestPermissions();
    _ready = true;
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      final permission = web.Notification.permission;
      if (permission == 'granted') return true;
      if (permission == 'denied') return false;
      final result = await web.Notification.requestPermission().toDart;
      return result.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await ensureInitialized();
    try {
      if (web.Notification.permission != 'granted') return;
      web.Notification(
        title,
        web.NotificationOptions(body: body, tag: 'coco-$id'),
      );
    } catch (_) {
      // 静默：前台仍有 poller pending 卡
    }
  }

  @override
  Future<Set<String>> scheduleReminders(
    Iterable<LocalReminderSchedule> reminders,
  ) async {
    // 浏览器无法可靠本地定时；依赖前台轮询。
    scheduledReminderIds.clear();
    return {};
  }

  @override
  Future<void> cancelReminder(String reminderId) async {
    scheduledReminderIds.remove(reminderId);
  }

  @override
  Future<void> cancelAll() async {
    scheduledReminderIds.clear();
  }
}
