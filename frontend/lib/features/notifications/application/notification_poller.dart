import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/local_notifications.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/models.dart';
import '../../care/application/care_providers.dart';
import '../../reminders/application/reminders_providers.dart';
import '../../reminders/data/reminders_api.dart';
import '../../reminders/domain/models.dart';
import '../data/notifications_api.dart';
import '../domain/models.dart';

/// 前台轮询未读通知；退到后台改为本地定时提醒，避免无谓耗电。
class NotificationPollerState {
  const NotificationPollerState({
    this.pendingReminder,
    this.pendingSuggestion,
    this.pendingChildStatus,
    this.seenIds = const {},
  });

  final AppNotification? pendingReminder;
  // 子女建议提醒：父母确认后才调度
  final AppNotification? pendingSuggestion;
  // 子女报平安：需在父母首页落卡，不能只依赖系统横幅
  final AppNotification? pendingChildStatus;
  final Set<String> seenIds;

  NotificationPollerState copyWith({
    AppNotification? pendingReminder,
    bool clearPendingReminder = false,
    AppNotification? pendingSuggestion,
    bool clearPendingSuggestion = false,
    AppNotification? pendingChildStatus,
    bool clearPendingChildStatus = false,
    Set<String>? seenIds,
  }) {
    return NotificationPollerState(
      pendingReminder: clearPendingReminder
          ? null
          : (pendingReminder ?? this.pendingReminder),
      pendingSuggestion: clearPendingSuggestion
          ? null
          : (pendingSuggestion ?? this.pendingSuggestion),
      pendingChildStatus: clearPendingChildStatus
          ? null
          : (pendingChildStatus ?? this.pendingChildStatus),
      seenIds: seenIds ?? this.seenIds,
    );
  }
}

class NotificationPoller extends StateNotifier<NotificationPollerState>
    with WidgetsBindingObserver {
  NotificationPoller(this._ref) : super(const NotificationPollerState()) {
    WidgetsBinding.instance.addObserver(this);
    _startIfNeeded();
    _ref.listen(authControllerProvider, (previous, next) {
      if (next.isAuthenticated) {
        _startIfNeeded();
      } else {
        _stop();
        unawaited(_ref.read(localNotificationServiceProvider).cancelAll());
        state = const NotificationPollerState();
      }
    });
  }

  final Ref _ref;
  Timer? _timer;
  // 报平安/关怀消息依赖前台轮询落卡；过长会感觉「没收到」
  static const _interval = Duration(seconds: 5);
  // 退后台期间为哪些提醒排过本地定时；回前台时 REMINDER 横幅去重
  Set<String> _scheduledWhileBackground = {};
  DateTime? _backgroundedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
    } else if (state == AppLifecycleState.paused) {
      unawaited(_onPaused());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stop();
    }
  }

  Future<void> _onPaused() async {
    _stop();
    final auth = _ref.read(authControllerProvider);
    if (!auth.isAuthenticated || auth.user?.role != UserRole.parent) {
      return;
    }
    _backgroundedAt = DateTime.now();
    try {
      final reminders = await _ref.read(remindersApiProvider).list();
      final schedules = reminders
          .where((r) => r.isActive && r.nextTriggerAt != null)
          .map(
            (r) => LocalReminderSchedule(
              id: r.id,
              title: r.title,
              nextTriggerAt: r.nextTriggerAt!,
            ),
          );
      final local = _ref.read(localNotificationServiceProvider);
      _scheduledWhileBackground = await local.scheduleReminders(schedules);
    } catch (_) {
      // 排程失败不阻断退后台；回前台仍靠轮询
      _scheduledWhileBackground = {};
    }
  }

  Future<void> _onResumed() async {
    final local = _ref.read(localNotificationServiceProvider);
    // 回前台取消本地定时，改由轮询 + 首页卡片承接
    await local.cancelAll();
    _startIfNeeded();
    await pollOnce(skipReminderBannerIfScheduled: true);
    _scheduledWhileBackground = {};
    _backgroundedAt = null;
  }

  void _startIfNeeded() {
    final auth = _ref.read(authControllerProvider);
    if (!auth.isAuthenticated) return;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(pollOnce()));
    unawaited(pollOnce());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> pollOnce({bool skipReminderBannerIfScheduled = false}) async {
    final auth = _ref.read(authControllerProvider);
    if (!auth.isAuthenticated) return;
    try {
      final items = await _ref
          .read(notificationsApiProvider)
          .list(unreadOnly: true);
      final seen = Set<String>.from(state.seenIds);
      // 每次按未读列表重算待办卡，避免只弹系统通知、首页空白
      AppNotification? latestReminder;
      AppNotification? latestSuggestion;
      AppNotification? latestChildStatus;
      final local = _ref.read(localNotificationServiceProvider);
      final role = auth.user?.role;
      final bgAt = _backgroundedAt;

      for (final item in items) {
        final isNew = !seen.contains(item.id);
        if (isNew) seen.add(item.id);

        if (role == UserRole.parent) {
          if (item.isReminderSuggestion) {
            latestSuggestion = _newer(latestSuggestion, item);
            if (isNew) {
              await local.show(
                id: item.id.hashCode & 0x7fffffff,
                title: item.title,
                body: item.body,
                payload: 'notification:${item.id}',
              );
            }
          } else if (item.isReminder) {
            latestReminder = _newer(latestReminder, item);
            if (isNew) {
              final skipBanner = shouldSkipReminderBanner(
                skipIfScheduled: skipReminderBannerIfScheduled,
                reminderId: item.reminderId,
                scheduledReminderIds: _scheduledWhileBackground,
                backgroundedAt: bgAt,
                createdAt: item.createdAt,
              );
              // 后台本地定时已弹过的首次到点，回前台只落卡、不再弹横幅
              if (!skipBanner) {
                await local.show(
                  id: item.id.hashCode & 0x7fffffff,
                  title: '可可有一条提醒',
                  body: '可可有一条提醒',
                  payload: item.occurrenceId == null
                      ? 'notification:${item.id}'
                      : 'occurrence:${item.occurrenceId}',
                );
              }
            }
          } else if (item.isChildStatus) {
            latestChildStatus = _newer(latestChildStatus, item);
            if (isNew) {
              await local.show(
                id: item.id.hashCode & 0x7fffffff,
                title: item.title,
                body: item.body,
                payload: 'notification:${item.id}',
              );
            }
          }
        } else if (role == UserRole.child) {
          if (item.isCareMessage && isNew) {
            _ref.invalidate(childTodayProvider);
            _ref.invalidate(childSuggestionsProvider);
            await local.show(
              id: item.id.hashCode & 0x7fffffff,
              title: item.title,
              body: item.body,
              payload: 'notification:${item.id}',
            );
          }
        }
      }

      state = NotificationPollerState(
        pendingReminder: latestReminder,
        pendingSuggestion: latestSuggestion,
        pendingChildStatus: latestChildStatus,
        seenIds: seen,
      );
    } catch (_) {
      // 轮询失败静默，不打断用户主流程
    }
  }

  Future<ReminderOccurrence?> confirmPendingReminder() async {
    final pending = state.pendingReminder;
    if (pending == null) return null;
    final reminderId = pending.reminderId;
    final occurrenceId = pending.occurrenceId;
    if (reminderId == null || occurrenceId == null) {
      await dismissPendingReminder(markRead: true);
      return null;
    }
    try {
      final occ = await _ref
          .read(remindersApiProvider)
          .respond(
            occurrenceId: occurrenceId,
            status: 'COMPLETED_SELF_REPORTED',
          );
      await _ref
          .read(localNotificationServiceProvider)
          .cancelReminder(reminderId);
      await _rescheduleLocal();
      // 后端会按 occurrence 批量已读；本地再扫一遍防竞态叠弹
      await _markOccurrenceNotificationsRead(occurrenceId);
      await dismissPendingReminder(markRead: true);
      return occ;
    } catch (_) {
      // 计划已删等陈旧通知：仍收起并标已读，避免浮层关不掉
      await _markOccurrenceNotificationsRead(occurrenceId);
      await dismissPendingReminder(markRead: true);
      return null;
    }
  }

  Future<ReminderOccurrence?> delayPendingReminder({int minutes = 30}) async {
    final pending = state.pendingReminder;
    if (pending == null) return null;
    final reminderId = pending.reminderId;
    final occurrenceId = pending.occurrenceId;
    if (reminderId == null || occurrenceId == null) {
      await dismissPendingReminder(markRead: true);
      return null;
    }
    try {
      final occ = await _ref
          .read(remindersApiProvider)
          .respond(
            occurrenceId: occurrenceId,
            status: 'SNOOZED',
            snoozeMinutes: minutes,
          );
      await _ref
          .read(localNotificationServiceProvider)
          .cancelReminder(reminderId);
      await _rescheduleLocal(
        snoozeOverride: occ.snoozeUntil == null
            ? null
            : LocalReminderSchedule(
                id: reminderId,
                title: pending.title,
                nextTriggerAt: occ.snoozeUntil!,
                occurrenceId: occ.id,
              ),
      );
      await _markOccurrenceNotificationsRead(occurrenceId);
      await dismissPendingReminder(markRead: true);
      return occ;
    } catch (_) {
      await _markOccurrenceNotificationsRead(occurrenceId);
      await dismissPendingReminder(markRead: true);
      return null;
    }
  }

  /// 同一次到点可能因调度刷屏产生多条未读，确认时一并清掉。
  Future<void> _markOccurrenceNotificationsRead(String occurrenceId) async {
    final api = _ref.read(notificationsApiProvider);
    try {
      final unread = await api.list(unreadOnly: true);
      for (final item in unread) {
        if (item.isReminder && item.occurrenceId == occurrenceId) {
          try {
            await api.markRead(item.id);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> acceptPendingSuggestion() async {
    final pending = state.pendingSuggestion;
    if (pending == null) return;
    final reminderId = pending.reminderId;
    if (reminderId == null) {
      await dismissPendingSuggestion(markRead: true);
      return;
    }
    await _ref.read(remindersApiProvider).acceptSuggestion(reminderId);
    _ref.invalidate(remindersListProvider);
    await _rescheduleLocal();
    await dismissPendingSuggestion(markRead: true);
  }

  Future<void> rejectPendingSuggestion() async {
    final pending = state.pendingSuggestion;
    if (pending == null) return;
    final reminderId = pending.reminderId;
    if (reminderId == null) {
      await dismissPendingSuggestion(markRead: true);
      return;
    }
    await _ref.read(remindersApiProvider).rejectSuggestion(reminderId);
    _ref.invalidate(remindersListProvider);
    await dismissPendingSuggestion(markRead: true);
  }

  /// 父母确认「知道了」：标记已读并收起卡片，不制造等待回复状态。
  Future<void> acknowledgePendingChildStatus() async {
    final pending = state.pendingChildStatus;
    if (pending == null) return;
    try {
      await _ref.read(notificationsApiProvider).markRead(pending.id);
    } catch (_) {}
    state = state.copyWith(clearPendingChildStatus: true);
  }

  Future<void> _rescheduleLocal({LocalReminderSchedule? snoozeOverride}) {
    return rescheduleLocalReminders(
      api: _ref.read(remindersApiProvider),
      local: _ref.read(localNotificationServiceProvider),
      snoozeOverride: snoozeOverride,
    );
  }

  Future<void> dismissPendingReminder({bool markRead = false}) async {
    final pending = state.pendingReminder;
    if (pending != null && markRead) {
      try {
        await _ref.read(notificationsApiProvider).markRead(pending.id);
      } catch (_) {}
    }
    state = state.copyWith(clearPendingReminder: true);
  }

  Future<void> dismissPendingSuggestion({bool markRead = false}) async {
    final pending = state.pendingSuggestion;
    if (pending != null && markRead) {
      try {
        await _ref.read(notificationsApiProvider).markRead(pending.id);
      } catch (_) {}
    }
    state = state.copyWith(clearPendingSuggestion: true);
  }

  /// 兼容旧调用名。
  Future<void> dismissPending({bool markRead = false}) =>
      dismissPendingReminder(markRead: markRead);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }
}

AppNotification? _newer(AppNotification? current, AppNotification candidate) {
  if (current == null) return candidate;
  return candidate.createdAt.isAfter(current.createdAt) ? candidate : current;
}

final notificationPollerProvider =
    StateNotifierProvider<NotificationPoller, NotificationPollerState>((ref) {
      return NotificationPoller(ref);
    });

/// 纯函数：过滤出尚未见过的通知 id，便于单测去重逻辑。
Set<String> filterUnseenNotificationIds({
  required Iterable<String> incomingIds,
  required Set<String> seenIds,
}) {
  return incomingIds.where((id) => !seenIds.contains(id)).toSet();
}

/// 回前台时：若后台已为该提醒排过本地定时且通知在退后台后产生，则跳过横幅。
bool shouldSkipReminderBanner({
  required bool skipIfScheduled,
  required String? reminderId,
  required Set<String> scheduledReminderIds,
  required DateTime? backgroundedAt,
  required DateTime createdAt,
}) {
  if (!skipIfScheduled || reminderId == null || backgroundedAt == null) {
    return false;
  }
  if (!scheduledReminderIds.contains(reminderId)) return false;
  return !createdAt.isBefore(backgroundedAt);
}
