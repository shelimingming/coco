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
    this.pendingChildStatus,
    this.seenIds = const {},
  });

  final AppNotification? pendingReminder;
  // 子女报平安：需在父母首页落卡，不能只依赖系统横幅
  final AppNotification? pendingChildStatus;
  final Set<String> seenIds;

  NotificationPollerState copyWith({
    AppNotification? pendingReminder,
    bool clearPendingReminder = false,
    AppNotification? pendingChildStatus,
    bool clearPendingChildStatus = false,
    Set<String>? seenIds,
  }) {
    return NotificationPollerState(
      pendingReminder: clearPendingReminder
          ? null
          : (pendingReminder ?? this.pendingReminder),
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
        state = const NotificationPollerState();
      }
    });
  }

  final Ref _ref;
  Timer? _timer;
  // 报平安依赖前台轮询落卡；过长会感觉「没收到」
  static const _interval = Duration(seconds: 8);

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
      final items = await _ref
          .read(notificationsApiProvider)
          .list(unreadOnly: true);
      final seen = Set<String>.from(state.seenIds);
      // 每次按未读列表重算待办卡，避免只弹系统通知、首页空白
      AppNotification? latestReminder;
      AppNotification? latestChildStatus;
      final local = _ref.read(localNotificationServiceProvider);
      final role = auth.user?.role;

      for (final item in items) {
        final isNew = !seen.contains(item.id);
        if (isNew) seen.add(item.id);

        if (role == UserRole.parent) {
          if (item.isReminder) {
            latestReminder = _newer(latestReminder, item);
            if (isNew) {
              await local.show(
                id: item.id.hashCode,
                title: item.title,
                body: item.body,
              );
            }
          } else if (item.isChildStatus) {
            latestChildStatus = _newer(latestChildStatus, item);
            if (isNew) {
              await local.show(
                id: item.id.hashCode,
                title: item.title,
                body: item.body,
              );
            }
          }
        } else if (item.isCareMessage && role == UserRole.child) {
          if (isNew) {
            _ref.invalidate(childTodayProvider);
          }
        }
      }

      state = NotificationPollerState(
        pendingReminder: latestReminder,
        pendingChildStatus: latestChildStatus,
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
      await dismissPendingReminder(markRead: true);
      return;
    }
    await _ref
        .read(remindersApiProvider)
        .confirm(reminderId: reminderId, occurrenceId: occurrenceId);
    await dismissPendingReminder(markRead: true);
  }

  Future<void> delayPendingReminder({int minutes = 30}) async {
    final pending = state.pendingReminder;
    if (pending == null) return;
    final reminderId = pending.reminderId;
    final occurrenceId = pending.occurrenceId;
    if (reminderId == null || occurrenceId == null) {
      await dismissPendingReminder(markRead: true);
      return;
    }
    await _ref
        .read(remindersApiProvider)
        .delay(
          reminderId: reminderId,
          occurrenceId: occurrenceId,
          minutes: minutes,
        );
    await dismissPendingReminder(markRead: true);
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

  Future<void> dismissPendingReminder({bool markRead = false}) async {
    final pending = state.pendingReminder;
    if (pending != null && markRead) {
      try {
        await _ref.read(notificationsApiProvider).markRead(pending.id);
      } catch (_) {}
    }
    state = state.copyWith(clearPendingReminder: true);
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
