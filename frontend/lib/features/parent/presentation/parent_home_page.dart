import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../notifications/application/notification_poller.dart';
import '../../notifications/domain/models.dart';
import '../../reminders/application/reminders_providers.dart';
import '../application/coco_companion_controller.dart';
import '../application/voice_call_controller.dart';
import '../domain/coco_companion_pose.dart';
import '../domain/voice_call_state.dart';
import 'widgets/child_status_card.dart';
import 'widgets/coco_companion_view.dart';
import 'widgets/parent_caption_bubble.dart';
import 'widgets/parent_home_palette.dart';
import 'widgets/parent_home_tool_bar.dart';
import 'widgets/parent_pending_action_card.dart';
import 'widgets/reminder_confirm_card.dart';

/// 父母端首页：全屏白天场景，说话原地进对话；字幕默认关。
class ParentHomePage extends ConsumerStatefulWidget {
  const ParentHomePage({super.key});

  @override
  ConsumerState<ParentHomePage> createState() => _ParentHomePageState();
}

class _ParentHomePageState extends ConsumerState<ParentHomePage> {
  bool _actionBusy = false;

  /// 对话文字默认关闭，避免干扰不希望看转译的老人。
  bool _captionVisible = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final name = user?.displayName ?? '家人';
    final companionPose = ref.watch(cocoCompanionPoseProvider);
    final callState = ref.watch(voiceCallControllerProvider);
    final callController = ref.read(voiceCallControllerProvider.notifier);
    final inCall =
        callState.isActive || callState.phase == VoiceCallPhase.error;
    final pollerState = ref.watch(notificationPollerProvider);
    final pendingReminder = pollerState.pendingReminder;
    final pendingChildStatus = pendingReminder == null
        ? pollerState.pendingChildStatus
        : null;
    final voicePending = inCall && callState.pendingAction != null;
    final palette = ParentHomePalette.standard;
    final greeting = parentHomeGreeting(name);
    final caption = callState.assistantCaption.isNotEmpty
        ? callState.assistantCaption
        : callState.userCaption;
    // 字幕开时虚化背景，主角色尺寸位置保持不变
    final blurBackground = inCall && _captionVisible;

    return Scaffold(
      backgroundColor: CocoColors.parentBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 上半：场景图 + 可可；底边渐变接到纯色区，不再露地板图
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  palette.backgroundAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  excludeFromSemantics: true,
                ),
                if (blurBackground)
                  Positioned.fill(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: ColoredBox(
                          color: CocoColors.neutral950.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                  ),
                // 场景到底栏：透明 → 暖米色，交界处有渐变感
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 140,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          CocoColors.parentBackground.withValues(alpha: 0),
                          CocoColors.parentBackground,
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          CocoSpace.s6,
                          CocoSpace.s3,
                          CocoSpace.s5,
                          CocoSpace.s2,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                greeting,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                  color: palette.text,
                                ),
                              ),
                            ),
                            if (inCall) ...[
                              ParentCaptionToggle(
                                palette: palette,
                                visible: _captionVisible,
                                onPressed: () {
                                  setState(
                                    () => _captionVisible = !_captionVisible,
                                  );
                                },
                              ),
                              const SizedBox(width: CocoSpace.s3),
                            ],
                            TextButton(
                              onPressed: inCall
                                  ? null
                                  : () => context.push('/parent/functions'),
                              style: TextButton.styleFrom(
                                foregroundColor: palette.link,
                                disabledForegroundColor: palette.link
                                    .withValues(alpha: 0.4),
                                textStyle: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: CocoSpace.s2,
                                ),
                              ),
                              child: const Text('更多'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CocoSpace.s6,
                          ),
                          child: _buildCenter(
                            callState: callState,
                            callController: callController,
                            companionPose: companionPose,
                            palette: palette,
                            caption: caption,
                            voicePending: voicePending,
                            pendingReminder: pendingReminder,
                            pendingChildStatus: pendingChildStatus,
                            inCall: inCall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 下半：纯色底（不是图片），放引导文案与工具栏
          ColoredBox(
            color: CocoColors.parentBackground,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!inCall &&
                      !voicePending &&
                      pendingReminder == null &&
                      pendingChildStatus == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CocoSpace.s6,
                        0,
                        CocoSpace.s6,
                        CocoSpace.s3,
                      ),
                      child: Column(
                        children: [
                          Text(
                            '我在呢',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: palette.text,
                            ),
                          ),
                          const SizedBox(height: CocoSpace.s2),
                          Text(
                            '有什么想让我帮忙的？',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (inCall &&
                      !_captionVisible &&
                      callState.phase != VoiceCallPhase.error &&
                      !voicePending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CocoSpace.s3),
                      child: Text(
                        callState.statusLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                        ),
                      ),
                    ),
                  ParentHomeToolBar(
                    palette: palette,
                    inCall: inCall,
                    lookEnabled: !inCall,
                    onTalkPressed: () {
                      if (inCall) {
                        if (callState.phase == VoiceCallPhase.error) {
                          callController.retry();
                        } else {
                          callController.stop();
                        }
                        setState(() => _captionVisible = false);
                      } else {
                        callController.start();
                      }
                    },
                    onLookPressed: () => context.push('/parent/look'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenter({
    required VoiceCallState callState,
    required VoiceCallController callController,
    required CocoCompanionPose companionPose,
    required ParentHomePalette palette,
    required String caption,
    required bool voicePending,
    required AppNotification? pendingReminder,
    required AppNotification? pendingChildStatus,
    required bool inCall,
  }) {
    if (callState.phase == VoiceCallPhase.error) {
      return _HomeVoiceError(
        title: callState.errorTitle ?? '出了点问题',
        message: callState.errorMessage ?? '请稍后再试。',
        onRetry: callController.retry,
      );
    }

    if (voicePending) {
      return SingleChildScrollView(
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
            Text(
              callState.statusLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: palette.link,
              ),
            ),
          ],
        ),
      );
    }

    if (!inCall && pendingReminder != null) {
      return SingleChildScrollView(
        child: ReminderConfirmCard(
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
      );
    }

    if (!inCall && pendingChildStatus != null) {
      return SingleChildScrollView(
        child: ChildStatusCard(
          notification: pendingChildStatus,
          busy: _actionBusy,
          onAcknowledge: () => _runAction(() {
            return ref
                .read(notificationPollerProvider.notifier)
                .acknowledgePendingChildStatus();
          }),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 字幕开/关不改变主角色尺寸：按整区算，气泡叠在上方
        final side = constraints.biggest.shortestSide
            .clamp(200.0, 320.0)
            .toDouble();
        return Stack(
          children: [
            Center(
              child: Semantics(
                label: inCall ? callState.statusLabel : '和可可说话',
                child: CocoCompanionView(pose: companionPose, size: side),
              ),
            ),
            if (inCall && _captionVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ParentCaptionBubble(palette: palette, text: caption),
              ),
          ],
        );
      },
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

/// 首页内联语音错误：发生了什么、现在能做什么。
class _HomeVoiceError extends StatelessWidget {
  const _HomeVoiceError({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(CocoSpace.s6),
        decoration: BoxDecoration(
          color: CocoColors.parentSurface,
          borderRadius: BorderRadius.circular(CocoRadius.xl),
          border: Border.all(color: CocoColors.danger.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: CocoColors.danger,
              ),
            ),
            const SizedBox(height: CocoSpace.s3),
            Text(
              message,
              style: const TextStyle(
                fontSize: 22,
                height: 1.4,
                color: CocoColors.neutral700,
              ),
            ),
            const SizedBox(height: CocoSpace.s5),
            CocoPrimaryButton(label: '再试一次', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
