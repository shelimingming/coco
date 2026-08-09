import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/local_notifications.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/models.dart';
import '../../care/application/care_providers.dart';
import '../../reminders/data/reminders_api.dart';
import '../data/notifications_api.dart';
import '../domain/models.dart';

/// 前台轮询未读通知；退到后台停止，避免无谓耗电。
class NotificationPollerState {
  const NotificationPollerState({
    this.pendingReminder,
    this.seenIds = const {},
  });

  final AppNotification? pendingReminder;
  final Set<String> seenIds;

  NotificationPollerState copyWith({
    AppNotification? pendingReminder,
    bool clearPending = false,
    Set<String>? seenIds,
  }) {
    return NotificationPollerState(
      pendingReminder:
          clearPending ? null : (pendingReminder ?? this.pendingReminder),
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
        state = const NotificationPollerState();
      }
    });
  }

  final Ref _ref;
  Timer? _timer;
  static const _interval = Duration(seconds: 20);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startIfNeeded();
      unawaited(pollOnce());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stop();
    }
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

  Future<void> pollOnce() async {
    final auth = _ref.read(authControllerProvider);
    if (!auth.isAuthenticated) return;
    try {
      final items =
          await _ref.read(notificationsApiProvider).list(unreadOnly: true);
      final seen = Set<String>.from(state.seenIds);
      AppNotification? latestReminder = state.pendingReminder;
      final local = _ref.read(localNotificationServiceProvider);

      for (final item in items) {
        if (seen.contains(item.id)) continue;
        seen.add(item.id);

        // 父母端 REMINDER：本地横幅 + 首页确认卡
        // 子女端 CARE_MESSAGE：只刷新今日状态，不弹打扰性横幅
        if (item.isReminder && auth.user?.role == UserRole.parent) {
          latestReminder = item;
          await local.show(
            id: item.id.hashCode,
            title: item.title,
            body: item.body,
          );
        } else if (item.isChildStatus && auth.user?.role == UserRole.parent) {
          await local.show(
            id: item.id.hashCode,
            title: item.title,
            body: item.body,
          );
        } else if (item.isCareMessage && auth.user?.role == UserRole.child) {
          _ref.invalidate(childTodayProvider);
        }
      }

      state = state.copyWith(
        pendingReminder: latestReminder,
        seenIds: seen,
      );
    } catch (_) {
      // 轮询失败静默，不打断用户主流程
    }
  }

  Future<void> confirmPendingReminder() async {
    final pending = state.pendingReminder;
    if (pending == null) return;
    final reminderId = pending.reminderId;
    final occurrenceId = pending.occurrenceId;
    if (reminderId == null || occurrenceId == null) {
      await dismissPending(markRead: true);
      return;
    }
    await _ref.read(remindersApiProvider).confirm(
          reminderId: reminderId,
          occurrenceId: occurrenceId,
        );
    await dismissPending(markRead: true);
  }

  Future<void> delayPendingReminder({int minutes = 30}) async {
    final pending = state.pendingReminder;
    if (pending == null) return;
    final reminderId = pending.reminderId;
    final occurrenceId = pending.occurrenceId;
    if (reminderId == null || occurrenceId == null) {
      await dismissPending(markRead: true);
      return;
    }
    await _ref.read(remindersApiProvider).delay(
          reminderId: reminderId,
          occurrenceId: occurrenceId,
          minutes: minutes,
        );
    await dismissPending(markRead: true);
  }

  Future<void> dismissPending({bool markRead = false}) async {
    final pending = state.pendingReminder;
    if (pending != null && markRead) {
      try {
        await _ref.read(notificationsApiProvider).markRead(pending.id);
      } catch (_) {}
    }
    state = state.copyWith(clearPending: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }
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
