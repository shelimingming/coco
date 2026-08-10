import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../../notifications/application/notification_poller.dart';
import '../../reminders/application/reminders_providers.dart';
import '../application/coco_companion_controller.dart';
import '../application/voice_call_controller.dart';
import '../domain/voice_call_state.dart';
import 'widgets/child_status_card.dart';
import 'widgets/coco_companion_view.dart';
import 'widgets/parent_pending_action_card.dart';
import 'widgets/reminder_confirm_card.dart';
import 'widgets/voice_call_panel.dart';

/// 父母端首页：点小狗或「和我说话」进入实时陪伴，通话原地切换不跳页。
class ParentHomePage extends ConsumerStatefulWidget {
  const ParentHomePage({super.key});

  @override
  ConsumerState<ParentHomePage> createState() => _ParentHomePageState();
}

class _ParentHomePageState extends ConsumerState<ParentHomePage> {
  bool _actionBusy = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final name = user?.displayName ?? '家人';
    final theme = Theme.of(context);
    final companionPose = ref.watch(cocoCompanionPoseProvider);
    final callState = ref.watch(voiceCallControllerProvider);
    final callController = ref.read(voiceCallControllerProvider.notifier);
    final inCall =
        callState.isActive || callState.phase == VoiceCallPhase.error;
    // 确保轮询器在首页被挂载
    final pollerState = ref.watch(notificationPollerProvider);
    final nextReminder = ref.watch(nextReminderProvider);
    // 一屏一事：到点提醒优先于报平安
    final pendingReminder = pollerState.pendingReminder;
    final pendingChildStatus = pendingReminder == null
        ? pollerState.pendingChildStatus
        : null;
    final hasPendingCard =
        pendingReminder != null || pendingChildStatus != null;
    // 通话中出确认卡：一屏一事，大卡可滚动，不与小狗抢高度
    final voicePending = inCall && callState.pendingAction != null;

    return CocoScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶栏自绘：避免无 title 时 AppBar 不渲染，功能入口始终可见
          Row(
            children: [
              Expanded(
                child: Text('你好，$name', style: theme.textTheme.titleLarge),
              ),
              const SizedBox(width: CocoSpace.s3),
              ParentChipButton(
                label: '功能',
                onPressed: inCall
                    ? null
                    : () => context.push('/parent/functions'),
              ),
            ],
          ),
          const SizedBox(height: CocoSpace.s3),
          if (voicePending)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ParentPendingActionCard(
                      action: callState.pendingAction!,
                      busy: callState.pendingActionBusy,
                      onConfirm: () {
                        unawaited(() async {
                          await callController.confirmPendingAction();
                          ref.invalidate(remindersListProvider);
                        }());
                      },
                      onCancel: () {
                        unawaited(callController.cancelPendingAction());
                      },
                    ),
                    const SizedBox(height: CocoSpace.s4),
                    VoiceCallPanel(
                      state: callState,
                      compact: true,
                      onEnd: callController.stop,
                      onInterrupt: callController.interrupt,
                      onRetry: callController.retry,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (!inCall && !hasPendingCard)
              Text(
                '点我，我们说说话',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
            if (!inCall && pendingReminder != null) ...[
              const SizedBox(height: CocoSpace.s3),
              ReminderConfirmCard(
                notification: pendingReminder,
                busy: _actionBusy,
                onConfirm: () => _runAction(() {
                  return ref
                      .read(notificationPollerProvider.notifier)
                      .confirmPendingReminder();
                }),
                onDelay: () => _runAction(() {
                  return ref
                      .read(notificationPollerProvider.notifier)
                      .delayPendingReminder();
                }),
              ),
              const SizedBox(height: CocoSpace.s4),
            ] else if (!inCall && pendingChildStatus != null) ...[
              const SizedBox(height: CocoSpace.s3),
              ChildStatusCard(
                notification: pendingChildStatus,
                busy: _actionBusy,
                onAcknowledge: () => _runAction(() {
                  return ref
                      .read(notificationPollerProvider.notifier)
                      .acknowledgePendingChildStatus();
                }),
              ),
              const SizedBox(height: CocoSpace.s4),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.biggest.shortestSide
                      .clamp(160.0, 280.0)
                      .toDouble();
                  return Center(
                    child: Semantics(
                      button: true,
                      label: callState.canInterrupt ? '打断可可说话' : '和可可说话',
                      child: GestureDetector(
                        onTap: () {
                          if (callState.canInterrupt) {
                            callController.interrupt();
                          } else if (!inCall) {
                            callController.start();
                          }
                        },
                        child: CocoCompanionView(
                          pose: companionPose,
                          size: side,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (inCall)
              VoiceCallPanel(
                state: callState,
                onEnd: callController.stop,
                onInterrupt: callController.interrupt,
                onRetry: callController.retry,
              )
            else ...[
              CocoPrimaryButton(label: '和我说话', onPressed: callController.start),
              const SizedBox(height: CocoSpace.s4),
              nextReminder.when(
                data: (reminder) {
                  if (reminder == null) {
                    return Text(
                      '今天还没有提醒',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    );
                  }
                  return GestureDetector(
                    onTap: () => context.push('/parent/reminders'),
                    child: Text(
                      '最近：${reminder.timeLabel} ${reminder.title}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: CocoColors.parentSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
                loading: () => Text(
                  '正在查看提醒…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                error: (_, _) => Text(
                  '提醒暂时看不了，点「功能」可再试。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _actionBusy = true);
    try {
      await action();
      ref.invalidate(remindersListProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : '刚才没办成。您可以再试一次，数据没有错误写入。',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }
}
