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
import 'widgets/parent_call_transcript_panel.dart';
import 'widgets/parent_caption_bubble.dart';
import 'widgets/parent_home_palette.dart';
import 'widgets/parent_home_tool_bar.dart';
import 'widgets/parent_pending_action_card.dart';
import 'widgets/reminder_confirm_card.dart';
import 'widgets/reminder_suggestion_card.dart';

/// 父母端首页：全屏白天场景，说话原地进对话；默认只语音，开「字」才看本通文字。
class ParentHomePage extends ConsumerStatefulWidget {
  const ParentHomePage({super.key});

  @override
  ConsumerState<ParentHomePage> createState() => _ParentHomePageState();
}

class _ParentHomePageState extends ConsumerState<ParentHomePage> {
  bool _actionBusy = false;

  /// 「字」开关：开时显示本通全部对话；关时不叠气泡，专心听说。
  bool _captionVisible = false;

  /// 出场播完切待机；进语音时会被取消，避免盖住倾听/说话
  Timer? _entranceTimer;

  /// 底栏「我在呢」两行文案所需高度（含底 padding），进对话后文案变短也占同一槽位
  static const double _bottomCopySlotHeight = 96;

  /// 「字」开时底栏几乎不占文案槽，把高度让给聊天列表
  static const double _bottomCopySlotWhenTranscript = CocoSpace.s3;

  @override
  void initState() {
    super.initState();
    // 刚进首页：先出场一轮，再进入待机循环
    WidgetsBinding.instance.addPostFrameCallback((_) => _playEntrance());
  }

  @override
  void dispose() {
    _entranceTimer?.cancel();
    super.dispose();
  }

  void _playEntrance() {
    if (!mounted) return;
    ref.read(cocoCompanionPoseProvider.notifier).state =
        CocoCompanionPose.entrance;
    _entranceTimer?.cancel();
    _entranceTimer = Timer(CocoCompanionPoseAsset.entranceDuration, () {
      if (!mounted) return;
      // 仅仍在出场态时切待机，避免打断已开始的语音姿态
      if (ref.read(cocoCompanionPoseProvider) == CocoCompanionPose.entrance) {
        ref.read(cocoCompanionPoseProvider.notifier).state =
            CocoCompanionPose.idle;
      }
    });
  }

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
    final pendingSuggestion = pollerState.pendingSuggestion;
    final pendingReminder = pollerState.pendingReminder;
    // 一屏一事：建议确认 > 到点完成 > 报平安
    final pendingChildStatus =
        pendingSuggestion == null && pendingReminder == null
        ? pollerState.pendingChildStatus
        : null;
    final voicePending = inCall && callState.pendingAction != null;
    final palette = ParentHomePalette.standard;
    final greeting = parentHomeGreeting(name);
    // 默认对话不叠气泡；仅「字」开时展示本通记录
    final showTranscript = inCall && _captionVisible;
    // 「字」开、或确认大卡（建议 / 到点 / 报平安 / 语音待确认）时虚化场景
    final blurBackground =
        showTranscript ||
        voicePending ||
        (!inCall && pendingSuggestion != null) ||
        (!inCall && pendingReminder != null) ||
        (!inCall && pendingChildStatus != null);
    final bottomCopyHeight = showTranscript
        ? _bottomCopySlotWhenTranscript
        : _bottomCopySlotHeight;

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
                        // 「字」面板需要更明显虚化，方便读聊天记录
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: ColoredBox(
                          color: CocoColors.neutral950.withValues(alpha: 0.18),
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
                            showTranscript: showTranscript,
                            voicePending: voicePending,
                            pendingSuggestion: pendingSuggestion,
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
                  // 闲置/通话状态文案槽；开「字」时压矮，把垂直空间还给聊天列表
                  SizedBox(
                    height: bottomCopyHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CocoSpace.s6,
                        0,
                        CocoSpace.s6,
                        CocoSpace.s3,
                      ),
                      child: _buildBottomCopy(
                        inCall: inCall,
                        voicePending: voicePending,
                        pendingSuggestion: pendingSuggestion,
                        pendingReminder: pendingReminder,
                        pendingChildStatus: pendingChildStatus,
                        callState: callState,
                        palette: palette,
                        hideStatusCopy: showTranscript,
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

  /// 底栏状态文案：闲置引导 / 通话状态；无文案时仍占位，避免背景高度变化。
  Widget _buildBottomCopy({
    required bool inCall,
    required bool voicePending,
    required AppNotification? pendingSuggestion,
    required AppNotification? pendingReminder,
    required AppNotification? pendingChildStatus,
    required VoiceCallState callState,
    required ParentHomePalette palette,
    required bool hideStatusCopy,
  }) {
    if (!inCall &&
        !voicePending &&
        pendingSuggestion == null &&
        pendingReminder == null &&
        pendingChildStatus == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
      );
    }

    // 聊天记录已展示时底栏不再重复状态
    if (inCall &&
        !hideStatusCopy &&
        callState.phase != VoiceCallPhase.error &&
        !voicePending) {
      return Center(
        child: Text(
          callState.statusLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildCenter({
    required VoiceCallState callState,
    required VoiceCallController callController,
    required CocoCompanionPose companionPose,
    required ParentHomePalette palette,
    required bool showTranscript,
    required bool voicePending,
    required AppNotification? pendingSuggestion,
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
      // 对话状态已由底栏「对话中」表达，卡片下不再重复状态文案
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: CocoSpace.s4),
        child: ParentPendingActionCard(
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
      );
    }

    if (!inCall && pendingSuggestion != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: CocoSpace.s4),
        child: ReminderSuggestionCard(
          notification: pendingSuggestion,
          busy: _actionBusy,
          onAccept: () => _runAction(() {
            return ref
                .read(notificationPollerProvider.notifier)
                .acceptPendingSuggestion();
          }),
          onReject: () => _runAction(() {
            return ref
                .read(notificationPollerProvider.notifier)
                .rejectPendingSuggestion();
          }),
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
      return Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: CocoSpace.s4),
          child: ChildStatusCard(
            notification: pendingChildStatus,
            busy: _actionBusy,
            onAcknowledge: () => _runAction(() {
              return ref
                  .read(notificationPollerProvider.notifier)
                  .acknowledgePendingChildStatus();
            }),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 主角色尽量占满中间区，老人端更易看见可可
        final side = (constraints.biggest.shortestSide * 0.95)
            .clamp(240.0, 420.0)
            .toDouble();
        // 「字」开时小狗与背景同虚化，避免抢文字可读性
        Widget companion = CocoCompanionView(pose: companionPose, size: side);
        if (showTranscript) {
          companion = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: companion,
          );
        }

        return Stack(
          children: [
            // 开「字」时小狗再下沉，列表几乎铺满到工具栏上方
            Align(
              alignment: Alignment(0, showTranscript ? 0.78 : 0.48),
              child: Semantics(
                label: inCall ? callState.statusLabel : '和可可说话',
                child: companion,
              ),
            ),
            if (showTranscript)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                // 只留一小段给虚化小狗露头，减少列表下方空白
                bottom: side * 0.12,
                child: ParentCallTranscriptPanel(
                  palette: palette,
                  entries: callState.displayTranscript,
                ),
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
