import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'local_notifications.dart';

LocalNotificationService createLocalNotificationService() =>
    IoLocalNotificationService.instance;

/// iOS/Android：flutter_local_notifications + zonedSchedule。
class IoLocalNotificationService implements LocalNotificationService {
  IoLocalNotificationService._();

  static final IoLocalNotificationService instance =
      IoLocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  @override
  final Set<String> scheduledReminderIds = {};

  @override
  Future<void> ensureInitialized() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    // 产品面向国内用户；本地定时按上海时区解释 next_trigger_at
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(iOS: ios, macOS: ios, android: android);
    await _plugin.initialize(settings: init);

    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Android 13+ 运行时通知权限（当前工程可无 android 目录，调用安全）
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _ready = true;
  }

  @override
  Future<bool> requestPermissions() async {
    await ensureInitialized();
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    return (ios ?? true) && (android ?? true);
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await ensureInitialized();
    final details = NotificationDetails(
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      android: AndroidNotificationDetails(
        'coco_default',
        '可可通知',
        channelDescription: '提醒、报平安与关怀消息',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  @override
  Future<Set<String>> scheduleReminders(
    Iterable<LocalReminderSchedule> reminders,
  ) async {
    await ensureInitialized();
    await cancelAll();
    scheduledReminderIds.clear();
    final now = tz.TZDateTime.now(tz.local);
    final scheduled = <String>{};

    for (final reminder in reminders) {
      // 用绝对时间戳转上海时区，避免设备时区与业务时区不一致
      final when = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.local,
        reminder.nextTriggerAt.millisecondsSinceEpoch,
      );
      // 至少 3 秒后，避免「刚创建就弹」与调度竞态
      if (!when.isAfter(now.add(const Duration(seconds: 3)))) continue;

      final id = _reminderNotifId(reminder.id);
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: when,
        title: '日常提醒',
        body: '到「${reminder.title}」时间了。已经做过了吗？',
        notificationDetails: NotificationDetails(
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          android: AndroidNotificationDetails(
            'coco_reminders',
            '日常提醒',
            channelDescription: '到点提醒（本地定时，无需推送证书）',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'reminder:${reminder.id}',
      );
      scheduled.add(reminder.id);
    }
    scheduledReminderIds.addAll(scheduled);
    return scheduled;
  }

  @override
  Future<void> cancelReminder(String reminderId) async {
    await ensureInitialized();
    await _plugin.cancel(id: _reminderNotifId(reminderId));
    scheduledReminderIds.remove(reminderId);
  }

  @override
  Future<void> cancelAll() async {
    await ensureInitialized();
    await _plugin.cancelAll();
    scheduledReminderIds.clear();
  }

  /// 稳定正整数 id，避免 hashCode 负数。
  static int _reminderNotifId(String reminderId) {
    return reminderId.hashCode & 0x7fffffff;
  }
}
