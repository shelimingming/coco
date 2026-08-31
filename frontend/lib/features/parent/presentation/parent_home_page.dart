import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_safe_area.dart';
import '../../auth/application/auth_controller.dart';
import '../../look/application/look_controller.dart';
import '../../look/application/screen_share_controller.dart';
import '../../look/domain/look_state.dart';
import '../../look/domain/screen_share_state.dart';
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
import 'widgets/parent_home_chat_controls.dart';
import 'widgets/parent_home_look_panel.dart';
import 'widgets/parent_home_palette.dart';
import 'widgets/parent_home_tool_bar.dart';
import 'widgets/parent_pending_action_card.dart';
import 'widgets/parent_screen_share_panel.dart';
import 'widgets/reminder_suggestion_card.dart';

/// 设计基准画布宽；用于按屏宽缩放可可位置与尺寸。
const double _kDesignWidth = 410;

/// 父母端首页：全屏白天场景；对话控制与三等分工具条分离。
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

  /// 再按一次退出：记录上次系统返回时间
  DateTime? _lastBackAt;

  /// 本次为看图新开的通话；识图失败时挂断，避免空连
  bool _voiceStartedForLook = false;

  @override
  void initState() {
    super.initState();
    // 刚进首页：仅出场动画；须用户点「开始聊天」后再连
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 从其它页回来时消费语音「看眼前/看手机」指令
      _consumeVoiceHomeAction();
      // 通话中从「更多」返回会重新挂载首页；会话还在，不要重播出场
      if (ref.read(voiceCallControllerProvider).isInSession) {
        return;
      }
      _playEntrance();
    });
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

  /// 打开系统设置，方便老人去允许麦克风。
  Future<void> _openAppSettings() async {
    final uri = Uri.parse('app-settings:');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 投屏进入 sharingIdle：接通语音并引导去目标页
    ref.listen<ScreenShareState>(screenShareControllerProvider, (prev, next) {
      final becameSharing =
          next.phase == ScreenSharePhase.sharingIdle &&
          prev?.phase != ScreenSharePhase.sharingIdle &&
          prev?.phase != ScreenSharePhase.analyzing &&
          prev?.phase != ScreenSharePhase.viewing &&
          prev?.phase != ScreenSharePhase.reAnalyzing;
      if (becameSharing) {
        unawaited(_onScreenShareBecameActive());
      }
    });
    // 已在首页时，语音看眼前/看手机直接走按钮同一套逻辑
    ref.listen<String?>(voicePendingHomeActionProvider, (prev, next) {
      if (next == null || next.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _consumeVoiceHomeAction();
      });
    });

    final user = ref.watch(authControllerProvider).user;
    final name = user?.displayName ?? '家人';
    final companionPose = ref.watch(cocoCompanionPoseProvider);
    final callState = ref.watch(voiceCallControllerProvider);
    final callController = ref.read(voiceCallControllerProvider.notifier);
    final inSession =
        callState.isInSession || callState.phase == VoiceCallPhase.error;
    final paused = callState.isPaused;
    final pollerState = ref.watch(notificationPollerProvider);
    final pendingSuggestion = pollerState.pendingSuggestion;
    final pendingChildStatus = pendingSuggestion == null
        ? pollerState.pendingChildStatus
        : null;
    final voicePending = inSession && callState.pendingAction != null;
    final lookState = ref.watch(lookControllerProvider);
    final screenShare = ref.watch(screenShareControllerProvider);
    final lookSession = lookState.isVisualSession;
    final lookAnalyzing = lookState.isBusy || screenShare.isBusy;
    final screenOccupies = screenShare.occupiesCenter;
    final visualSession = lookSession || screenOccupies;

    final palette = ParentHomePalette.standard;
    final greeting = parentHomeGreeting(name);
    final showTranscript = inSession && _captionVisible && !visualSession;
    final showingConfirmCard =
        voicePending ||
        (!inSession && pendingSuggestion != null) ||
        (!inSession && pendingChildStatus != null);
    final blurBackground =
        showTranscript || visualSession || showingConfirmCard;
    // 确认大卡 / 识图时让中间区吃满，对话控制仍保留在底
    final hideCompanion =
        visualSession ||
        showingConfirmCard ||
        callState.phase == VoiceCallPhase.error;

    return PopScope(
      // 会话中拦截返回；首页再按一次才退出，避免老人误触杀进程
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (inSession) {
          final end = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('结束聊天？'),
              content: const Text('现在返回会结束这次对话。您刚才说的话没有额外保存。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('继续聊'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('结束'),
                ),
              ],
            ),
          );
          if (end == true && context.mounted) {
            await _endChat();
          }
          return;
        }
        final now = DateTime.now();
        if (_lastBackAt != null &&
            now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBackAt = now;
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('再按一次返回键退出可可')));
      },
      child: Scaffold(
        backgroundColor: CocoColors.parentBackground,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isEntrance = companionPose == CocoCompanionPose.entrance;
            final safe = CocoSafeInsets.paddingOf(context);
            // 底栏占位 + 安全区；矮屏据此压缩可可，爪底贴按钮上方
            final bottomUi =
                (showingConfirmCard || callState.phase == VoiceCallPhase.error
                    ? 0
                    : ParentHomeChatControls.heightFor(inSession: inSession)) +
                ParentHomeChatControls.gapAboveToolbar +
                ParentHomeToolBar.barHeight +
                CocoSpace.s2 +
                safe.bottom;
            // 顶栏约占：安全区 + 内边距 + 「更多」最小点击高
            final minTop = safe.top + CocoSpace.s2 + 56;
            final coco = computeParentHomeCocoRect(
              viewport: Size(constraints.maxWidth, constraints.maxHeight),
              entrance: isEntrance,
              bottomUi: bottomUi,
              minTop: minTop,
            );
            // 状态字叠在爪底下方，不改 bottomUi / minTop，避免挤布局
            final hideStatusCopy =
                hideCompanion ||
                showTranscript ||
                visualSession ||
                showingConfirmCard;

            return Stack(
              fit: StackFit.expand,
              // 出场右溢出时不硬裁，避免腰斩感
              clipBehavior: Clip.none,
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
                        filter: ImageFilter.blur(
                          sigmaX: lookSession ? 16 : 14,
                          sigmaY: lookSession ? 16 : 14,
                        ),
                        child: ColoredBox(
                          color: lookSession
                              ? CocoColors.parentBackground.withValues(
                                  alpha: 0.4,
                                )
                              : CocoColors.neutral950.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                  ),
                // 正方形定位：与 gif 画布一致，避免竖框居中把爪子压进按钮
                if (!hideCompanion)
                  Positioned(
                    left: coco.left,
                    top: coco.top,
                    width: coco.width,
                    height: coco.height,
                    child: _buildCompanion(
                      companionPose: companionPose,
                      callState: callState,
                      inSession: inSession,
                      showTranscript: showTranscript,
                      size: coco.width,
                    ),
                  ),
                // 状态文案叠在爪底下方；IgnorePointer 避免挡到底部按钮
                if (!hideStatusCopy)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: coco.top + coco.height - 2,
                    child: IgnorePointer(
                      child: _buildCompanionStatusCopy(
                        inSession: inSession,
                        voicePending: voicePending,
                        callState: callState,
                        palette: palette,
                      ),
                    ),
                  ),
                CocoSafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTopBar(
                          greeting: greeting,
                          palette: palette,
                          lookAnalyzing: lookAnalyzing,
                        ),
                        Expanded(
                          child: _buildCenter(
                            callState: callState,
                            callController: callController,
                            palette: palette,
                            showTranscript: showTranscript,
                            voicePending: voicePending,
                            pendingSuggestion: pendingSuggestion,
                            pendingChildStatus: pendingChildStatus,
                            inSession: inSession,
                            lookState: lookState,
                            screenShare: screenShare,
                            captionVisible: _captionVisible,
                          ),
                        ),
                        if (!showingConfirmCard &&
                            callState.phase != VoiceCallPhase.error)
                          ParentHomeChatControls(
                            palette: palette,
                            inSession: inSession,
                            paused: paused,
                            onStart: _onStartChat,
                            onPause: _onPauseChat,
                            onResume: _onResumeChat,
                            onEnd: () => unawaited(_endChat()),
                          ),
                        const SizedBox(
                          height: ParentHomeChatControls.gapAboveToolbar,
                        ),
                        ParentHomeToolBar(
                          palette: palette,
                          visionToolsEnabled: !lookAnalyzing,
                          phoneActive:
                              screenShare.isActive || screenShare.isSharing,
                          onFrontPressed: () {
                            unawaited(_runLookAndHandoff(LookSource.camera));
                          },
                          onPhonePressed: () {
                            unawaited(_onPhonePressed());
                          },
                          onPhotoPressed: () {
                            unawaited(_runLookAndHandoff(LookSource.album));
                          },
                        ),
                        const SizedBox(height: CocoSpace.s2),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar({
    required String greeting,
    required ParentHomePalette palette,
    required bool lookAnalyzing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: CocoSpace.s2),
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
          // 按稿四个状态均保留「字」入口
          ParentCaptionToggle(
            palette: palette,
            visible: _captionVisible,
            onPressed: () {
              setState(() => _captionVisible = !_captionVisible);
            },
          ),
          const SizedBox(width: CocoSpace.s2),
          TextButton(
            // 通话中也要能进「更多」；会话由 VoiceCallController 跨页保留
            onPressed: lookAnalyzing
                ? null
                : () => context.push('/parent/functions'),
            style: TextButton.styleFrom(
              foregroundColor: palette.link,
              disabledForegroundColor: palette.link.withValues(alpha: 0.4),
              textStyle: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
              minimumSize: const Size(56, 56),
              padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s2),
            ),
            child: const Text('更多'),
          ),
        ],
      ),
    );
  }

  /// 狗狗爪底下方单行状态：仅通话中跟 phase；闲置不显示。叠层不占布局。
  Widget _buildCompanionStatusCopy({
    required bool inSession,
    required bool voicePending,
    required VoiceCallState callState,
    required ParentHomePalette palette,
  }) {
    // 闲置不展示；通话中才显示阶段提示
    if (!inSession ||
        voicePending ||
        callState.phase == VoiceCallPhase.error) {
      return const SizedBox.shrink();
    }

    return Text(
      callState.statusLabel,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: palette.text,
      ),
    );
  }

  Widget _buildCompanion({
    required CocoCompanionPose companionPose,
    required VoiceCallState callState,
    required bool inSession,
    required bool showTranscript,
    required double size,
  }) {
    Widget companion = CocoCompanionView(pose: companionPose, size: size);
    if (showTranscript) {
      companion = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: companion,
      );
    }
    return Semantics(
      button: true,
      label: inSession ? callState.statusLabel : '和可可说话',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onCompanionTapped,
        child: companion,
      ),
    );
  }

  void _onStartChat() {
    _entranceTimer?.cancel();
    ref.read(voiceCallControllerProvider.notifier).start();
  }

  void _onPauseChat() {
    unawaited(ref.read(voiceCallControllerProvider.notifier).pause());
  }

  /// 消费语音下发的看眼前 / 看手机；与工具条点按走同一套流程。
  void _consumeVoiceHomeAction() {
    final action = ref.read(voicePendingHomeActionProvider);
    if (action == null || action.isEmpty) return;
    ref.read(voicePendingHomeActionProvider.notifier).state = null;
    unawaited(_handleVoiceHomeAction(action));
  }

  Future<void> _handleVoiceHomeAction(String action) async {
    switch (action) {
      case 'open_look_front':
        await _runLookAndHandoff(LookSource.camera);
      case 'open_look_phone':
        await _onPhonePressed();
      default:
        break;
    }
  }

  void _onResumeChat() {
    unawaited(ref.read(voiceCallControllerProvider.notifier).resume());
  }

  Future<void> _endChat() async {
    final callController = ref.read(voiceCallControllerProvider.notifier);
    final lookController = ref.read(lookControllerProvider.notifier);
    await callController.stop();
    setState(() {
      _captionVisible = false;
      _voiceStartedForLook = false;
    });
    lookController.closeVisualSession();
    unawaited(ref.read(screenShareControllerProvider.notifier).stopSharing());
    unawaited(callController.discardVisionSession());
  }

  Future<void> _retryChat() async {
    await ref.read(voiceCallControllerProvider.notifier).retry();
  }

  /// 点小狗：闲置时与「开始聊天」相同；播报中也可点按打断；出错时重试。
  void _onCompanionTapped() {
    final callState = ref.read(voiceCallControllerProvider);
    final callController = ref.read(voiceCallControllerProvider.notifier);

    if (!callState.isInSession && callState.phase != VoiceCallPhase.error) {
      _onStartChat();
      return;
    }
    if (callState.isPaused) {
      _onResumeChat();
      return;
    }
    if (callState.canInterrupt) {
      unawaited(callController.interrupt());
      return;
    }
    if (callState.phase == VoiceCallPhase.error) {
      unawaited(_retryChat());
    }
  }

  /// 投屏刚成功：接通语音并说引导语（含「不再提醒」直连授权成功）。
  Future<void> _onScreenShareBecameActive() async {
    final callController = ref.read(voiceCallControllerProvider.notifier);
    final voiceOk = await callController.ensureStarted();
    if (!mounted || !voiceOk) return;
    await callController.injectVisionContext(
      sceneDescription:
          '（系统：用户刚打开「看手机」投屏。请用口语说：'
          '${ScreenShareState.coachingSpeech}'
          '不要描述你自己的 App 界面。）',
      source: 'screen',
    );
  }

  Future<void> _onPhonePressed() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('"看手机"功能在网页端无法使用，请用手机 App 体验完整功能')),
      );
      return;
    }
    final share = ref.read(screenShareControllerProvider.notifier);
    final wasSharing =
        ref.read(screenShareControllerProvider).isSharing ||
        ref.read(screenShareControllerProvider).isActive;
    await share.onPhonePressed();
    if (!mounted) return;
    // 再点停止时清视觉会话
    final now = ref.read(screenShareControllerProvider);
    if (wasSharing && now.phase == ScreenSharePhase.idle) {
      unawaited(
        ref.read(voiceCallControllerProvider.notifier).discardVisionSession(),
      );
    }
  }

  /// 说明卡确认后拉起系统投屏。
  Future<void> _confirmScreenShare({bool dontAskAgain = false}) async {
    await ref
        .read(screenShareControllerProvider.notifier)
        .confirmAndStart(dontAskAgain: dontAskAgain);
  }

  /// 取图识图 → 接通/复用 Realtime → 注入读图上下文。
  Future<void> _runLookAndHandoff(LookSource source) async {
    final lookController = ref.read(lookControllerProvider.notifier);
    final callController = ref.read(voiceCallControllerProvider.notifier);
    final callState = ref.read(voiceCallControllerProvider);
    final wasInCall = callState.isActive || callState.isPaused;

    if (wasInCall && callState.isActive) {
      await callController.prepareForVisionLook();
    }
    if (!mounted) return;

    // Web「看眼前」要用 context 弹摄像头预览
    final result = await lookController.pick(source, hostContext: context);
    if (!mounted) return;
    if (result == null) {
      if (wasInCall && callState.isActive) {
        callController.setMicSuppressed(false);
      }
      final look = ref.read(lookControllerProvider);
      if (look.phase == LookPhase.error && _voiceStartedForLook && !wasInCall) {
        await callController.stop();
        _voiceStartedForLook = false;
      }
      return;
    }

    if (!wasInCall) {
      _voiceStartedForLook = true;
    }

    final ok = await callController.ensureStarted();
    if (!mounted) return;
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('照片看完了，但没接上语音。您可以再点「开始聊天」继续聊。')),
        );
      }
      _voiceStartedForLook = false;
      return;
    }

    await callController.injectVisionContext(
      sceneDescription: result.sceneDescription,
      source: source.wireName,
      lookConversationId: result.conversationId,
    );
  }

  Widget _buildCenter({
    required VoiceCallState callState,
    required VoiceCallController callController,
    required ParentHomePalette palette,
    required bool showTranscript,
    required bool voicePending,
    required AppNotification? pendingSuggestion,
    required AppNotification? pendingChildStatus,
    required bool inSession,
    required LookState lookState,
    required ScreenShareState screenShare,
    required bool captionVisible,
  }) {
    // 确认大卡优先
    if (voicePending) {
      return Padding(
        padding: const EdgeInsets.only(top: CocoSpace.s2, bottom: CocoSpace.s2),
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

    // 看手机：说明卡 / 引导 / 投屏画面
    if (screenShare.occupiesCenter &&
        callState.phase != VoiceCallPhase.error &&
        (pendingSuggestion == null && pendingChildStatus == null)) {
      if (screenShare.phase == ScreenSharePhase.confirming) {
        return ParentScreenShareConfirmCard(
          onConfirm: () => unawaited(_confirmScreenShare()),
          onCancel: () {
            ref.read(screenShareControllerProvider.notifier).cancelConfirm();
          },
          onConfirmDontAskAgain: () =>
              unawaited(_confirmScreenShare(dontAskAgain: true)),
        );
      }
      if (screenShare.phase == ScreenSharePhase.awaitingPermission ||
          screenShare.phase == ScreenSharePhase.starting) {
        if (screenShare.showIosGuide) {
          return ParentScreenShareIosGuide(
            onCancel: () {
              unawaited(
                ref.read(screenShareControllerProvider.notifier).stopSharing(),
              );
            },
          );
        }
        return Center(
          child: Text(
            screenShare.statusLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
        );
      }
      if (screenShare.phase == ScreenSharePhase.blocked ||
          screenShare.phase == ScreenSharePhase.error) {
        final msg = screenShare.phase == ScreenSharePhase.blocked
            ? (screenShare.blockReason ?? '已停止看屏幕')
            : [
                if (screenShare.errorTitle != null) screenShare.errorTitle!,
                if (screenShare.errorMessage != null) screenShare.errorMessage!,
              ].join('。');
        final frame = screenShare.latestFrame;
        if (frame != null && frame.isNotEmpty) {
          return ParentHomeLookPanel(
            palette: palette,
            imageBytes: frame,
            showScanBrackets: false,
            statusLabel: screenShare.statusLabel,
            showCaption: false,
            errorMessage: msg,
            onClose: () {
              if (screenShare.phase == ScreenSharePhase.blocked) {
                ref
                    .read(screenShareControllerProvider.notifier)
                    .dismissBlocked();
              } else {
                ref.read(screenShareControllerProvider.notifier).clearError();
              }
            },
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(CocoSpace.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  screenShare.statusLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: CocoSpace.s3),
                Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    height: 1.4,
                    color: CocoColors.neutral700,
                  ),
                ),
                const SizedBox(height: CocoSpace.s4),
                CocoPrimaryButton(
                  label: screenShareCloseLabel(screenShare.phase),
                  onPressed: () {
                    if (screenShare.phase == ScreenSharePhase.blocked) {
                      ref
                          .read(screenShareControllerProvider.notifier)
                          .dismissBlocked();
                    } else {
                      ref
                          .read(screenShareControllerProvider.notifier)
                          .clearError();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      }
      // sharingIdle / analyzing / viewing / reAnalyzing
      final frame = screenShare.latestFrame ?? lookState.imageBytes;
      if (frame != null && frame.isNotEmpty) {
        return ParentHomeLookPanel(
          palette: palette,
          imageBytes: frame,
          showScanBrackets: screenShare.showScanBrackets,
          statusLabel: screenShare.statusLabel,
          showCaption: captionVisible,
          captionEntries: callState.currentRoundEntries,
          onClose: () {
            unawaited(() async {
              await ref
                  .read(screenShareControllerProvider.notifier)
                  .stopSharing();
              await callController.discardVisionSession();
            }());
          },
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    screenShare.statusLabel,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    unawaited(() async {
                      await ref
                          .read(screenShareControllerProvider.notifier)
                          .stopSharing();
                      await callController.discardVisionSession();
                    }());
                  },
                  child: Text(
                    screenShareCloseLabel(screenShare.phase),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: CocoColors.parentPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CocoSpace.s4),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: CocoColors.parentPrimarySoft,
                  borderRadius: BorderRadius.circular(CocoRadius.xl),
                ),
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(CocoSpace.s5),
                    child: Text(
                      '打开短信或卡住的页面后，跟我说一声，我就能看见。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: CocoColors.neutral950,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 首页原地识图优先；语音出错时让错误卡露出来
    final lookSession = lookState.isVisualSession;
    if (lookSession &&
        callState.phase != VoiceCallPhase.error &&
        (pendingSuggestion == null && pendingChildStatus == null)) {
      final errorText = lookState.phase == LookPhase.error
          ? [
              if (lookState.errorTitle != null) lookState.errorTitle!,
              if (lookState.errorMessage != null) lookState.errorMessage!,
            ].where((s) => s.trim().isNotEmpty).join('。')
          : null;

      if (!lookState.hasImage) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(CocoSpace.s6),
            decoration: BoxDecoration(
              color: CocoColors.parentSurface,
              borderRadius: BorderRadius.circular(CocoRadius.xl),
              border: Border.all(
                color: CocoColors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              errorText ?? '这张照片没看清，请再试一次',
              style: const TextStyle(
                fontSize: 22,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: CocoColors.neutral950,
              ),
            ),
          ),
        );
      }

      return ParentHomeLookPanel(
        palette: palette,
        imageBytes: lookState.imageBytes!,
        showScanBrackets: lookState.showScanBrackets,
        statusLabel: lookState.statusLabel,
        showCaption: captionVisible,
        captionEntries: callState.currentRoundEntries,
        errorMessage: errorText,
        onClose: () {
          ref.read(lookControllerProvider.notifier).closeVisualSession();
          unawaited(callController.discardVisionSession());
        },
      );
    }

    if (callState.phase == VoiceCallPhase.error) {
      final title = callState.errorTitle ?? '出了点问题';
      return _HomeVoiceError(
        title: title,
        message: callState.errorMessage ?? '请稍后再试。',
        onRetry: () => unawaited(_retryChat()),
        onOpenSettings: title == '打不开麦克风' ? _openAppSettings : null,
      );
    }

    if (!inSession && pendingSuggestion != null) {
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

    if (!inSession && pendingChildStatus != null) {
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

    // 默认可可已由外层 Positioned；此处只叠「字」字幕
    if (showTranscript) {
      return ParentCallTranscriptPanel(
        palette: palette,
        entries: callState.displayTranscript,
      );
    }

    // 占位，保持 Expanded 结构；可可在 Stack 底层
    return const SizedBox.expand();
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
    this.onOpenSettings,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

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
            if (onOpenSettings != null) ...[
              const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(label: '去系统设置允许', onPressed: onOpenSettings),
            ],
          ],
        ),
      ),
    );
  }
}

/// 设计稿按宽缩放；爪底对齐场景地板，矮屏贴按钮上方（不压按钮、不悬空）。
///
/// gif 为正方形；[height] 恒等于 [width]。爪底设计值 625 对应原 490 高槽内
/// 居中摆放的视觉位置，与白天背景地板齐平。
@visibleForTesting
ParentHomeCocoRect computeParentHomeCocoRect({
  required Size viewport,
  required bool entrance,
  required double bottomUi,
  double minTop = 0,
  double designWidth = _kDesignWidth,
}) {
  final scale = viewport.width / designWidth;
  const designSize = 380.0;
  // 190 顶 + (490-380)/2 居中偏移 + 380 边长
  const designPawBottom = 625.0;
  const pawGap = 8.0;

  var size = designSize * scale;
  final maxPawBottom = viewport.height - bottomUi - pawGap;
  final floorMinTop = math.max(0.0, minTop);

  // 高屏：爪部落在设计地板线；矮屏：不超过底栏上沿
  var pawBottom = math.min(designPawBottom * scale, maxPawBottom);
  var top = pawBottom - size;

  if (top < floorMinTop) {
    // 顶栏挡住时才缩小，优先保爪底贴地、角色尽量大
    top = floorMinTop;
    size = math.max(80.0, pawBottom - top);
    if (top + size > maxPawBottom) {
      pawBottom = maxPawBottom;
      size = math.max(80.0, pawBottom - top);
      top = pawBottom - size;
      if (top < floorMinTop) {
        top = floorMinTop;
        size = math.max(80.0, maxPawBottom - top);
      }
    }
  }

  // 出场仍右贴边并略溢出，只吃透明边
  final left = entrance
      ? viewport.width - size + 36 * scale
      : (viewport.width - size) / 2;
  return ParentHomeCocoRect(left: left, top: top, width: size, height: size);
}

@visibleForTesting
class ParentHomeCocoRect {
  const ParentHomeCocoRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}
