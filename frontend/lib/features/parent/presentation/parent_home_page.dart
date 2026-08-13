import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/audio/mp3_bytes_source.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../look/application/look_controller.dart';
import '../../look/data/look_api.dart';
import '../../look/domain/look_state.dart';
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
import 'widgets/parent_greeting_bubble.dart';
import 'widgets/parent_home_look_panel.dart';
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

  /// 进首页时刻，用于等出场结束后再播开场白
  DateTime? _enteredAt;

  /// 开场 TTS 播放器；与 Realtime 通话音频分离
  final AudioPlayer _greetingPlayer = AudioPlayer();

  /// 递增以取消进行中的开场白（点说话 / 离页）
  int _greetingGeneration = 0;

  /// 开场白气泡：出场后展示，5 秒后自动收起
  bool _showGreetingBubble = false;

  Timer? _greetingBubbleTimer;

  /// 识图已注入语音，等可可开口后收起照片面板
  bool _awaitingVisionHandoff = false;

  /// 本次为看图新开的通话；识图失败时挂断，避免空连
  bool _voiceStartedForLook = false;

  /// 底栏「我在呢」两行文案所需高度（含底 padding），进对话后文案变短也占同一槽位
  static const double _bottomCopySlotHeight = 96;

  /// 「字」开时底栏几乎不占文案槽，把高度让给聊天列表
  static const double _bottomCopySlotWhenTranscript = CocoSpace.s3;

  @override
  void initState() {
    super.initState();
    // 刚进首页：出场 + TTS 开场白引导点小狗说话
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playEntrance();
      unawaited(_playVoiceGreeting());
    });
  }

  @override
  void dispose() {
    _entranceTimer?.cancel();
    _greetingBubbleTimer?.cancel();
    _greetingGeneration++;
    unawaited(_greetingPlayer.dispose());
    super.dispose();
  }

  void _playEntrance() {
    if (!mounted) return;
    _enteredAt = DateTime.now();
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

  /// 每次挂载首页播一次开场白；失败静默，不挡使用。
  Future<void> _playVoiceGreeting() async {
    final generation = ++_greetingGeneration;
    final name = ref.read(authControllerProvider).user?.displayName ?? '家人';
    final text = parentHomeVoiceGreeting(name);

    // TTS 与出场并行拉取；失败仍可出气泡引导
    final speechFuture = ref
        .read(audioApiProvider)
        .speech(text)
        .then<Uint8List?>((bytes) => bytes)
        .catchError((_) => null);

    // 等出场跑完再开口，避免跑动中抢话
    final entered = _enteredAt ?? DateTime.now();
    final wait =
        CocoCompanionPoseAsset.entranceDuration -
        DateTime.now().difference(entered);
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    }
    if (!_greetingStillActive(generation)) return;

    _entranceTimer?.cancel();
    // 气泡与 TTS 同步出现；气泡固定 5 秒，不跟音频时长
    _revealGreetingBubble();
    ref.read(cocoCompanionPoseProvider.notifier).state =
        CocoCompanionPose.speaking;

    final raw = await speechFuture;
    if (!_greetingStillActive(generation)) return;

    if (raw != null && raw.isNotEmpty) {
      try {
        await _greetingPlayer.setAudioSource(Mp3BytesSource(raw));
        if (!_greetingStillActive(generation)) return;
        await _greetingPlayer.play();
      } catch (_) {
        // Web 自动播放策略或播放失败时忽略
      }
    }

    // 音频先结束但气泡还在：保持说话姿态，等 5 秒定时器收回
    if (mounted &&
        generation == _greetingGeneration &&
        !_showGreetingBubble &&
        ref.read(cocoCompanionPoseProvider) == CocoCompanionPose.speaking &&
        !ref.read(voiceCallControllerProvider).isActive) {
      ref.read(cocoCompanionPoseProvider.notifier).state =
          CocoCompanionPose.idle;
    }
  }

  /// 展示开场气泡，5 秒后自动消失；若仍在说话姿态则切回待机。
  void _revealGreetingBubble() {
    _greetingBubbleTimer?.cancel();
    setState(() => _showGreetingBubble = true);
    _greetingBubbleTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _showGreetingBubble = false);
      // 气泡收起时若未进通话，说话姿态一并收回
      if (ref.read(cocoCompanionPoseProvider) == CocoCompanionPose.speaking &&
          !ref.read(voiceCallControllerProvider).isActive) {
        ref.read(cocoCompanionPoseProvider.notifier).state =
            CocoCompanionPose.idle;
      }
    });
  }

  void _hideGreetingBubble() {
    _greetingBubbleTimer?.cancel();
    if (_showGreetingBubble && mounted) {
      setState(() => _showGreetingBubble = false);
    }
  }

  bool _greetingStillActive(int generation) {
    if (!mounted || generation != _greetingGeneration) return false;
    final call = ref.read(voiceCallControllerProvider);
    return !call.isActive && call.phase != VoiceCallPhase.error;
  }

  /// 用户主动开口或离开前打断开场白，避免与 Realtime 叠音。
  void _cancelVoiceGreeting() {
    _greetingGeneration++;
    unawaited(_greetingPlayer.stop());
    _hideGreetingBubble();
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
    final lookState = ref.watch(lookControllerProvider);
    final lookController = ref.read(lookControllerProvider.notifier);
    // 分析中 / 待交接 / 失败时占用中间区；可可开口后 clear
    final lookSession =
        lookState.phase == LookPhase.analyzing ||
        lookState.phase == LookPhase.ready ||
        lookState.phase == LookPhase.error;
    final lookAnalyzing = lookState.phase == LookPhase.analyzing;

    // 识图注入后：可可一开口就收起照片，回到说话 UI
    ref.listen<VoiceCallState>(voiceCallControllerProvider, (prev, next) {
      if (!_awaitingVisionHandoff) return;
      if (next.phase == VoiceCallPhase.speaking ||
          next.phase == VoiceCallPhase.listening) {
        if (prev?.phase == VoiceCallPhase.thinking ||
            prev?.phase == VoiceCallPhase.connecting ||
            lookState.phase == LookPhase.ready) {
          _awaitingVisionHandoff = false;
          _voiceStartedForLook = false;
          lookController.clearAfterHandoff();
        }
      }
      // 注入失败时勿继续盖着「看完了」，否则语音错误卡被挡住、像卡住
      if (next.phase == VoiceCallPhase.error) {
        _awaitingVisionHandoff = false;
        _voiceStartedForLook = false;
        lookController.clearAfterHandoff();
      }
    });

    final palette = ParentHomePalette.standard;
    final greeting = parentHomeGreeting(name);
    // 默认对话不叠气泡；仅「字」开时展示本通记录；识图结果也跟「字」
    final showTranscript = inCall && _captionVisible && !lookSession;
    // 「字」开、识图、或确认大卡时虚化场景
    final blurBackground =
        showTranscript ||
        lookSession ||
        voicePending ||
        (!inCall && pendingSuggestion != null) ||
        (!inCall && pendingReminder != null) ||
        (!inCall && pendingChildStatus != null);
    final bottomCopyHeight = (showTranscript || lookSession)
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
                        // 识图态按交付：sigma≈16 + 暖白遮罩；「字」面板略加深
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
                            // 「字」全局偏好：通话或识图会话都可切换
                            if (inCall || lookSession) ...[
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
                              onPressed: (inCall || lookAnalyzing)
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
                                minimumSize: const Size(56, 56),
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
                            lookState: lookState,
                            captionVisible: _captionVisible,
                            userName: name,
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
                    // 分析中禁用眼前/手机，减轻一屏多主操作
                    visionToolsEnabled: !lookAnalyzing,
                    onTalkPressed: _onTalkPressed,
                    onFrontPressed: () {
                      unawaited(_runLookAndHandoff(LookSource.camera));
                    },
                    onPhonePressed: () => _showVisionPlaceholder('看手机'),
                    onPhotoPressed: () {
                      unawaited(_runLookAndHandoff(LookSource.album));
                    },
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

  void _showVisionPlaceholder(String label) {
    // Web 无法实现看手机；原生端仍用即将支持的占位提示。
    final message = kIsWeb
        ? '"看手机"功能web端无法实现，请使用IOS体验完整功能'
        : '$label即将支持，您可以先用「看照片」。';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 底栏「说话」：未通话则开始；通话中再点则结束（出错则重试）。
  void _onTalkPressed() {
    final callState = ref.read(voiceCallControllerProvider);
    final callController = ref.read(voiceCallControllerProvider.notifier);
    final lookController = ref.read(lookControllerProvider.notifier);
    final inCall =
        callState.isActive || callState.phase == VoiceCallPhase.error;

    // 进对话前打断开场白，避免与 Realtime 叠音
    _cancelVoiceGreeting();

    if (inCall) {
      if (callState.phase == VoiceCallPhase.error) {
        callController.retry();
      } else {
        callController.stop();
      }
      setState(() {
        _captionVisible = false;
        _awaitingVisionHandoff = false;
        _voiceStartedForLook = false;
      });
      lookController.clearAfterHandoff();
    } else {
      _entranceTimer?.cancel();
      callController.start();
    }
  }

  /// 点小狗：闲置时与「说话」相同开始对话；播报中打断；出错时重试。
  /// 故意不在倾听/思考时挂断，避免大图误触结束通话。
  void _onCompanionTapped() {
    final callState = ref.read(voiceCallControllerProvider);
    final callController = ref.read(voiceCallControllerProvider.notifier);

    if (!callState.isActive && callState.phase != VoiceCallPhase.error) {
      _onTalkPressed();
      return;
    }
    if (callState.canInterrupt) {
      unawaited(callController.interrupt());
      return;
    }
    if (callState.phase == VoiceCallPhase.error) {
      callController.retry();
    }
  }

  /// 取图识图 → 接通/复用 Realtime → 注入读图上下文。
  Future<void> _runLookAndHandoff(LookSource source) async {
    // 看图也会进语音，先停开场白
    _cancelVoiceGreeting();

    final lookController = ref.read(lookControllerProvider.notifier);
    final callController = ref.read(voiceCallControllerProvider.notifier);
    final callState = ref.read(voiceCallControllerProvider);
    final wasInCall = callState.isActive;

    if (wasInCall) {
      await callController.prepareForVisionLook();
    }
    if (!mounted) return;

    // Web「看眼前」要用 context 弹摄像头预览
    final result = await lookController.pick(source, hostContext: context);
    if (!mounted) return;
    if (result == null) {
      // 取消选图或识图失败
      if (wasInCall) {
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
          const SnackBar(content: Text('照片看完了，但没接上语音。您可以再点「说话」继续聊。')),
        );
      }
      lookController.clearAfterHandoff();
      _voiceStartedForLook = false;
      return;
    }

    _awaitingVisionHandoff = true;
    await callController.injectVisionContext(
      sceneDescription: result.sceneDescription,
      source: source.wireName,
    );
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
    required LookState lookState,
    required bool captionVisible,
    required String userName,
  }) {
    // 首页原地识图优先于闲置可可（确认卡仍优先）；语音出错时让错误卡露出来
    final lookSession =
        lookState.phase == LookPhase.analyzing ||
        lookState.phase == LookPhase.ready ||
        lookState.phase == LookPhase.error;
    if (lookSession &&
        callState.phase != VoiceCallPhase.error &&
        !voicePending &&
        (pendingSuggestion == null &&
            pendingReminder == null &&
            pendingChildStatus == null)) {
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
        analyzing:
            lookState.phase == LookPhase.analyzing ||
            lookState.phase == LookPhase.ready,
        showCaption: false,
        captionText: '',
        errorMessage: errorText,
        statusHint: lookState.phase == LookPhase.ready ? '看完了，接着和您说' : null,
      );
    }

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

        final greetingParts = parentHomeVoiceGreetingParts(userName);
        // 闲置时展示开场气泡；进通话 / 开「字」后不再叠
        final showGreeting = _showGreetingBubble && !inCall && !showTranscript;

        return Stack(
          children: [
            // 开「字」时小狗再下沉，列表几乎铺满到工具栏上方
            Align(
              alignment: Alignment(0, showTranscript ? 0.78 : 0.48),
              child: Semantics(
                button: true,
                label: inCall ? callState.statusLabel : '和可可说话',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onCompanionTapped,
                  child: companion,
                ),
              ),
            ),
            if (showGreeting)
              Positioned(
                top: CocoSpace.s2,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ParentGreetingBubble(
                    palette: palette,
                    title: greetingParts.title,
                    subtitle: greetingParts.subtitle,
                  ),
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
