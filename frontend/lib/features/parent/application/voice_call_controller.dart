import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/barge_in_detector.dart';
import '../../../core/audio/mic_pcm_stream.dart';
import '../../../core/audio/pcm_stream_player.dart';
import '../../../core/audio/voice_background.dart';
import '../../../core/network/api_client.dart';
import '../../../core/screen/screen_wake_lock.dart';
import '../data/realtime_voice_socket.dart';
import '../domain/coco_companion_pose.dart';
import '../domain/pending_voice_action.dart';
import '../domain/voice_call_state.dart';
import '../../look/application/look_controller.dart';
import '../../look/application/screen_share_controller.dart';
import '../../look/domain/screen_share_state.dart';
import '../domain/voice_call_transcript.dart';
import 'coco_companion_controller.dart';

/// 语音 open_screen 允许跳转的父母端路径（与后端 OPEN_SCREEN_ROUTES 对齐）。
const _voiceOpenRoutes = <String>{
  '/parent',
  '/parent/reminders',
  '/parent/memories',
  '/parent/daily-notes',
  '/parent/history',
  '/parent/settings',
  '/parent/functions',
};

/// 语音要打开的路由；由 [CocoApp] 监听后 go，避免 feature→app 循环依赖。
final voicePendingNavigateProvider = StateProvider<String?>((ref) => null);

/// 语音要触发的首页动作：看眼前 / 看手机；由首页消费。
final voicePendingHomeActionProvider = StateProvider<String?>((ref) => null);

/// 父母端实时通话状态机：连接 → 听 → 想 → 说；小狗姿态仅倾听 / 说话。
class VoiceCallController extends StateNotifier<VoiceCallState>
    with WidgetsBindingObserver {
  VoiceCallController({
    required this.ref,
    required String Function() readAccessToken,
    required String httpBaseUrl,
    MicPcmStream? mic,
    PcmStreamPlayer? player,
    RealtimeVoiceSocket? socket,
    ScreenWakeLock? wakeLock,
    BargeInDetector? bargeIn,
    Duration bargeInGrace = const Duration(milliseconds: 200),
  }) : // 公开命名参数 readAccessToken / httpBaseUrl，内部存私有字段
       _readAccessToken = readAccessToken,
       _httpBaseUrl = httpBaseUrl,
       _mic = mic ?? createMicPcmStream(),
       _player = player ?? createPcmStreamPlayer(),
       _socket = socket ?? RealtimeVoiceSocket(),
       _wakeLock = wakeLock ?? createScreenWakeLock(),
       _bargeIn = bargeIn ?? BargeInDetector(),
       _bargeInGrace = bargeInGrace,
       super(const VoiceCallState()) {
    // 构造期注入播放结束回调，用于恢复麦克风上行。
    _player.onDrained = _onPlaybackDrained;
    // 监听来电 / 切后台等音频焦点丢失，进入明确中断态
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref ref;
  final String Function() _readAccessToken;
  final String _httpBaseUrl;
  final MicPcmStream _mic;
  final PcmStreamPlayer _player;
  final RealtimeVoiceSocket _socket;
  final ScreenWakeLock _wakeLock;
  final VoiceBackground _voiceBackground = createVoiceBackground();
  final BargeInDetector _bargeIn;
  final Duration _bargeInGrace;

  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<RealtimeSocketEvent>? _socketSub;
  Timer? _readyTimeout;
  bool _started = false;
  bool _sessionReady = false;
  String _assistantAccum = '';
  Completer<bool>? _readyWaiter;

  /// 串行化常亮开关，避免 start / teardown 交错导致挂断后仍亮屏
  Future<void> _wakeLockChain = Future.value();

  /// 用户暂停后仍有下行播报未播完；播完前恢复会话时暂不开麦。
  bool _playbackPending = false;

  /// 插话进行中：后续麦块直接上行，避免打断过程中再被闸门吞掉。
  bool _interrupting = false;

  /// 插话后丢掉已取消回答的尾包，但不挡住工具追问等新一轮播报。
  bool _dropCancelledAssistant = false;

  /// 本轮首包音频时刻；短宽限内不插话，躲开开播瞬态回声。
  DateTime? _playbackBeganAt;

  /// 播报中暂存的上行块，插话时作为句首补发给模型。
  final List<Uint8List> _gatedPrefix = [];

  /// 语音挂断：等告别播完再拆连接，避免一调工具就把话掐掉。
  bool _awaitingHangupSpeech = false;
  bool _hangupSpeechStarted = false;
  Timer? _hangupFallback;

  Future<void> start() async {
    if (_started || state.isActive) return;
    _started = true;
    _sessionReady = false;
    state = const VoiceCallState(phase: VoiceCallPhase.connecting);
    _syncPose(VoiceCallPhase.connecting);
    // 须在其它 await 之前申请，Web 的 Wake Lock 依赖这次点击手势
    await _setWakeLock(true);

    final token = _readAccessToken();
    if (token.isEmpty) {
      await _fail(title: '还没有登录', message: '请先登录后再和我说话。刚才没有开始录音。');
      return;
    }

    try {
      // 先 setup 播放器（playAndRecord），再开麦，保证 iOS 外放。
      await _player.prepare();

      final uri = RealtimeVoiceSocket.buildUri(
        httpBaseUrl: _httpBaseUrl,
        accessToken: token,
      );
      await _socket.connect(uri);
      _socketSub = _socket.events.listen(_onSocketEvent);
      _readyTimeout?.cancel();
      _readyTimeout = Timer(const Duration(seconds: 15), () {
        if (!_sessionReady && _started) {
          unawaited(
            _fail(title: '连不上语音服务', message: '等待太久没有接通。您可以稍后再试，刚才没有录下任何声音。'),
          );
        }
      });

      await _mic.start();
      _attachMicListener();
      // Android：麦克风前台服务，划到后台仍可继续听
      unawaited(_voiceBackground.startVoiceKeepAlive());
    } on MicPcmException catch (e) {
      await _fail(title: '打不开麦克风', message: e.message);
    } catch (_) {
      await _fail(
        title: '连不上语音服务',
        message: '网络或语音服务暂时不可用。您可以稍后再试，刚才没有录下任何声音。',
      );
    }
  }

  /// 已接通则立即返回；否则 start 并等到 session.ready（或失败）。
  Future<bool> ensureStarted() async {
    // 暂停态已有 session：先恢复收音再复用
    if (_sessionReady && state.isPaused) {
      await resume();
      return state.isActive;
    }
    if (_sessionReady && state.isActive) return true;
    if (state.phase == VoiceCallPhase.error) {
      await _teardown(resetToIdle: true);
    }
    if (!_started) {
      final waiter = Completer<bool>();
      _readyWaiter = waiter;
      await start();
      if (_sessionReady && state.isActive) {
        _completeReadyWaiter(true);
        return true;
      }
      if (state.phase == VoiceCallPhase.error) {
        _completeReadyWaiter(false);
        return false;
      }
      return waiter.future;
    }
    if (_sessionReady && state.isActive) return true;
    if (state.phase == VoiceCallPhase.error) return false;
    final waiter = Completer<bool>();
    _readyWaiter = waiter;
    return waiter.future;
  }

  void _completeReadyWaiter(bool ok) {
    final waiter = _readyWaiter;
    _readyWaiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(ok);
    }
  }

  /// 识图开始前：打断播报并抑制麦克风，避免抢话。
  Future<void> prepareForVisionLook() async {
    if (!_started) return;
    _mic.suppress = true;
    try {
      await _socket.cancelResponse();
    } catch (_) {}
    await _player.clear();
    _assistantAccum = '';
    if (state.isActive) {
      state = state.copyWith(
        phase: VoiceCallPhase.listening,
        assistantCaption: '',
      );
      _syncPose(VoiceCallPhase.listening);
    }
  }

  /// 识图期间暂时不把麦克风上行发给模型，避免抢话。
  void setMicSuppressed(bool suppressed) {
    _mic.suppress = suppressed;
  }

  /// 注入读图上下文并让可可开口；须已 ensureStarted。
  Future<void> injectVisionContext({
    required String sceneDescription,
    String? source,
    String? lookConversationId,
  }) async {
    if (!_sessionReady || !_started) return;
    final scene = sceneDescription.trim();
    if (scene.isEmpty) return;
    try {
      await _socket.cancelResponse();
    } catch (_) {}
    await _player.clear();
    _assistantAccum = '';
    // 注入后等模型开口；播报中开口即可插话，不再关麦
    _mic.suppress = false;
    state = state.copyWith(
      phase: VoiceCallPhase.thinking,
      userCaption: '',
      assistantCaption: '',
    );
    _syncPose(VoiceCallPhase.thinking);
    await _socket.injectVisionContext(
      sceneDescription: scene,
      source: source,
      lookConversationId: lookConversationId,
    );
  }

  /// 关掉看图会话，不结束语音。
  Future<void> discardVisionSession() async {
    await _socket.discardVisionSession();
  }

  /// 投屏中用户开口：打断当前回答 → 抽帧识图 → 再注入让可可按新画面说。
  Future<void> _refreshScreenForUtterance(String userText) async {
    await prepareForVisionLook();
    final result = await ref
        .read(screenShareControllerProvider.notifier)
        .captureAndAnalyze(question: userText);
    if (result == null) {
      setMicSuppressed(false);
      return;
    }
    if (!_started) {
      final ok = await ensureStarted();
      if (!ok) return;
    }
    await injectVisionContext(
      sceneDescription: result.sceneDescription,
      source: 'screen',
      lookConversationId: result.conversationId,
    );
  }

  Future<void> stop() async {
    if (!_started && state.phase == VoiceCallPhase.idle) return;
    // 挂断语音时一并停投屏
    final share = ref.read(screenShareControllerProvider);
    if (share.phase != ScreenSharePhase.idle) {
      unawaited(ref.read(screenShareControllerProvider.notifier).stopSharing());
    }
    try {
      await _socket.endSession();
    } catch (_) {}
    await _teardown(resetToIdle: true);
  }

  /// 暂停一下：只闭麦，保留 session；可可未说完的话继续播完。
  Future<void> pause() async {
    if (!_started || !state.isActive) return;
    final wasSpeaking = state.phase == VoiceCallPhase.speaking;
    await _micSub?.cancel();
    _micSub = null;
    await _mic.stop();
    _mic.suppress = true;
    state = state.copyWith(phase: VoiceCallPhase.paused);
    // 正在播报时保持说话姿态，等 drained 再回待机
    _syncPose(wasSpeaking ? VoiceCallPhase.speaking : VoiceCallPhase.paused);
  }

  /// 继续聊天：同一 session 恢复收音。
  Future<void> resume() async {
    if (!_started || !state.isPaused || !_sessionReady) return;
    try {
      await _mic.start();
      _attachMicListener();
      // 可可还在说完刚才那句：保持播报，开口即可插话
      if (_playbackPending) {
        _mic.suppress = false;
        state = state.copyWith(phase: VoiceCallPhase.speaking);
        _syncPose(VoiceCallPhase.speaking);
      } else {
        _mic.suppress = false;
        state = state.copyWith(phase: VoiceCallPhase.listening);
        _syncPose(VoiceCallPhase.listening);
      }
    } on MicPcmException catch (e) {
      await _fail(title: '打不开麦克风', message: e.message);
    } catch (_) {
      await _fail(title: '麦克风暂时没准备好', message: '您可以再点「继续聊天」。刚才的对话还在，没有额外保存。');
    }
  }

  /// 打断当前播报；开口插话与点小狗共用。
  Future<void> interrupt() async {
    if (_interrupting) return;
    if (!state.canInterrupt && !_playbackPending) return;
    _interrupting = true;
    try {
      try {
        await _socket.cancelResponse();
      } catch (_) {}
      await _player.clear();
      _playbackPending = false;
      _playbackBeganAt = null;
      _dropCancelledAssistant = true;
      _bargeIn.reset();
      _gatedPrefix.clear();
      _mic.suppress = false;
      // 已说出的半句仍记入本通记录，方便「字」面板回看
      final spoken = _assistantAccum.trim();
      if (spoken.isNotEmpty) {
        _appendTranscript(VoiceCallTranscriptRole.assistant, spoken);
      }
      _assistantAccum = '';
      if (state.isPaused) return;
      state = state.copyWith(
        phase: VoiceCallPhase.listening,
        assistantCaption: '',
      );
      _syncPose(VoiceCallPhase.listening);
    } finally {
      _interrupting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive：控制中心/短暂遮挡，不要停麦；paused：用户划走 App。
    // 产品允许显式会话在后台继续听/说（看手机场景必需）。
    if (state == AppLifecycleState.paused) {
      if (_started && this.state.isActive) {
        final sharing = ref.read(screenShareControllerProvider).isSharing;
        unawaited(_voiceBackground.onEnteredBackground(screenSharing: sharing));
      }
    } else if (state == AppLifecycleState.resumed) {
      // 用户主动暂停时不得误开麦
      if (_started && this.state.isActive) {
        // 确保上行未因旧逻辑卡住；播报中保持开麦以便插话
        _mic.suppress = false;
        unawaited(_setWakeLock(true));
        unawaited(_voiceBackground.onEnteredForeground());
      } else if (_started && this.state.isPaused) {
        unawaited(_setWakeLock(true));
      }
    }
  }

  /// 音频被系统抢占后的明确中断态：停播、恢复听，不挂断会话。
  /// 保留供来电等真音频焦点丢失时调用（划到后台不再走此路径）。
  // ignore: unused_element
  Future<void> _onAudioInterrupted() async {
    if (!_started || !state.isActive) return;
    try {
      await _socket.cancelResponse();
    } catch (_) {}
    await _player.clear();
    _mic.suppress = false;
    final spoken = _assistantAccum.trim();
    if (spoken.isNotEmpty) {
      _appendTranscript(VoiceCallTranscriptRole.assistant, spoken);
    }
    _assistantAccum = '';
    state = state.copyWith(
      phase: VoiceCallPhase.listening,
      assistantCaption: '刚才被系统声音打断了。您可以继续说，或点结束。',
    );
    _syncPose(VoiceCallPhase.listening);
  }

  /// 大卡主按钮：点一下确认（与语音说「好」二选一）。
  Future<void> confirmPendingAction() async {
    final pending = state.pendingAction;
    if (pending == null || state.pendingActionBusy) return;
    state = state.copyWith(pendingActionBusy: true);
    try {
      await _socket.confirmPendingAction(pending.draftId);
    } catch (_) {
      state = state.copyWith(pendingActionBusy: false);
    }
  }

  /// 大卡次按钮：先不要。
  Future<void> cancelPendingAction() async {
    final pending = state.pendingAction;
    if (pending == null || state.pendingActionBusy) return;
    state = state.copyWith(pendingActionBusy: true);
    try {
      await _socket.cancelPendingAction(pending.draftId);
    } catch (_) {
      state = state.copyWith(pendingActionBusy: false);
    }
  }

  /// 错误态点「再试一次」：先清错误再 start。
  Future<void> retry() async {
    await _teardown(resetToIdle: true);
    await start();
  }

  void _onSocketEvent(RealtimeSocketEvent event) {
    // 用户暂停：闭麦，但仍放行可可播报相关下行，让未说完的话播完
    if (state.isPaused) {
      const allowedWhilePaused = {
        'assistant.partial',
        'assistant.audio',
        'assistant.final',
        'error',
        'closed',
        'navigate.open',
        'action.pending',
        'action.resolved',
        'vision.state',
        'vision.closed',
        'vision.stop_screen',
        'home.action',
      };
      if (!allowedWhilePaused.contains(event.type)) return;
    }

    switch (event.type) {
      case 'session.ready':
        _sessionReady = true;
        _readyTimeout?.cancel();
        _completeReadyWaiter(true);
        state = state.copyWith(
          phase: VoiceCallPhase.listening,
          clearError: true,
        );
        _syncPose(VoiceCallPhase.listening);
      case 'speech.started':
        // 播报中开口：先停本地播放，再切倾听（点小狗打断同源）
        if (state.phase == VoiceCallPhase.speaking || _playbackPending) {
          unawaited(interrupt());
          return;
        }
        state = state.copyWith(
          phase: VoiceCallPhase.listening,
          userCaption: '',
          assistantCaption: '',
        );
        _assistantAccum = '';
        _syncPose(VoiceCallPhase.listening);
      case 'speech.stopped':
        _dropCancelledAssistant = false;
        state = state.copyWith(phase: VoiceCallPhase.thinking);
        _syncPose(VoiceCallPhase.thinking);
      case 'user.partial':
        final text = event.text;
        if (text != null && text.isNotEmpty) {
          state = state.copyWith(
            phase: VoiceCallPhase.listening,
            userCaption: '${state.userCaption}$text',
          );
        }
      case 'user.final':
        final text = event.text;
        if (text != null && text.isNotEmpty) {
          _dropCancelledAssistant = false;
          _appendTranscript(VoiceCallTranscriptRole.user, text);
          // 已写入 transcript，清空 caption，避免「字」面板在可可说完后又叠一句「您」
          state = state.copyWith(
            phase: VoiceCallPhase.thinking,
            userCaption: '',
          );
          _syncPose(VoiceCallPhase.thinking);
          // 投屏中：先抽当前帧再注入，让回答对着最新屏幕
          final share = ref.read(screenShareControllerProvider);
          if (share.isSharing) {
            unawaited(_refreshScreenForUtterance(text));
          }
        }
      case 'assistant.partial':
        // 插话后供应商可能仍推已取消回答的尾包
        if (_dropCancelledAssistant) return;
        if (_awaitingHangupSpeech) {
          _hangupSpeechStarted = true;
        }
        final text = event.text;
        if (text != null && text.isNotEmpty) {
          _assistantAccum += text;
          // 暂停中只更新字幕与姿态，不离开 paused，避免 UI 变回「暂停一下」
          if (state.isPaused) {
            state = state.copyWith(
              userCaption: '',
              assistantCaption: _assistantAccum,
            );
            _syncPose(VoiceCallPhase.speaking);
          } else {
            state = state.copyWith(
              phase: VoiceCallPhase.speaking,
              userCaption: '',
              assistantCaption: _assistantAccum,
            );
            _syncPose(VoiceCallPhase.speaking);
          }
        }
      case 'assistant.audio':
        if (_dropCancelledAssistant) return;
        if (_awaitingHangupSpeech) {
          _hangupSpeechStarted = true;
        }
        final b64 = event.audioBase64;
        if (b64 == null || b64.isEmpty) return;
        if (!_playbackPending) {
          _bargeIn.reset();
          _playbackBeganAt = DateTime.now();
        }
        _playbackPending = true;
        // 播报中保持开麦：本地能量闸门挡回声，人声即可插话
        if (!state.isPaused) {
          _mic.suppress = false;
          state = state.copyWith(phase: VoiceCallPhase.speaking);
        }
        _syncPose(VoiceCallPhase.speaking);
        try {
          final pcm = base64Decode(b64);
          unawaited(
            _player.feed(Uint8List.fromList(pcm), sampleRate: event.sampleRate),
          );
        } catch (_) {}
      case 'assistant.final':
        if (_dropCancelledAssistant) return;
        final text = event.text;
        if (text != null && text.isNotEmpty) {
          _assistantAccum = text;
          _appendTranscript(VoiceCallTranscriptRole.assistant, text);
          if (state.isPaused) {
            state = state.copyWith(userCaption: '', assistantCaption: text);
          } else {
            state = state.copyWith(
              phase: VoiceCallPhase.speaking,
              userCaption: '',
              assistantCaption: text,
            );
          }
        }
        _player.markResponseComplete();
      case 'action.pending':
        _onActionPending(event.payload);
      case 'action.resolved':
        _onActionResolved(event.payload);
      case 'navigate.open':
        // 语音打开页面：会话跨页保留，不挂断
        _onNavigateOpen(event.payload);
      case 'home.action':
        _onHomeAction(event.payload);
      case 'vision.state':
        final phase = event.payload['phase']?.toString();
        if (phase != null && phase.isNotEmpty) {
          ref
              .read(lookControllerProvider.notifier)
              .applyServerVisionPhase(phase);
          ref
              .read(screenShareControllerProvider.notifier)
              .applyServerVisionPhase(phase);
        }
      case 'vision.closed':
        ref.read(lookControllerProvider.notifier).closeVisualSession();
        // 关图工具也可能用于停投屏
        final sharePhase = ref.read(screenShareControllerProvider).phase;
        if (sharePhase != ScreenSharePhase.idle &&
            sharePhase != ScreenSharePhase.blocked) {
          unawaited(
            ref.read(screenShareControllerProvider.notifier).stopSharing(),
          );
        }
      case 'vision.stop_screen':
        final reason = event.payload['reason']?.toString();
        unawaited(
          ref
              .read(screenShareControllerProvider.notifier)
              .applyStopScreen(reason: reason),
        );
      case 'error':
        unawaited(
          _fail(
            title: '语音出了点问题',
            message: event.message ?? '语音通话出了点问题。您可以稍后再试，刚才的内容没有额外保存。',
          ),
        );
      case 'closed':
        if (state.isActive ||
            state.isPaused ||
            state.phase == VoiceCallPhase.connecting) {
          unawaited(_teardown(resetToIdle: true));
        }
      default:
        // 未知下行事件静默忽略，保证后续扩展兼容。
        break;
    }
  }

  /// 服务端 open_screen 成功后写入待跳转路由；会话跨页保留，不挂断。
  void _onNavigateOpen(Map<String, Object?> payload) {
    final route = payload['route']?.toString().trim() ?? '';
    if (route.isEmpty || !_voiceOpenRoutes.contains(route)) return;
    ref.read(voicePendingNavigateProvider.notifier).state = route;
  }

  /// 语音首页能力：暂停/挂断本地执行；看眼前/看手机交给首页。
  void _onHomeAction(Map<String, Object?> payload) {
    final action = payload['action']?.toString().trim() ?? '';
    switch (action) {
      case 'pause_call':
        unawaited(pause());
      case 'end_call':
        _scheduleHangupAfterGoodbye();
      case 'open_look_front':
      case 'open_look_phone':
        // 先记下动作再回首页，避免跳转后指令还没写上
        ref.read(voicePendingHomeActionProvider.notifier).state = action;
        ref.read(voicePendingNavigateProvider.notifier).state = '/parent';
      default:
        break;
    }
  }

  /// 等告别播完再挂；若没有下行语音，超时兜底拆线。
  void _scheduleHangupAfterGoodbye() {
    _awaitingHangupSpeech = true;
    _hangupSpeechStarted = false;
    _hangupFallback?.cancel();
    _hangupFallback = Timer(const Duration(seconds: 8), () {
      if (_awaitingHangupSpeech && _started) {
        unawaited(stop());
      }
    });
  }

  void _onActionPending(Map<String, Object?> payload) {
    try {
      final action = PendingVoiceAction.fromPayload(payload);
      state = state.copyWith(pendingAction: action, pendingActionBusy: false);
    } catch (_) {
      // 畸形帧忽略，不影响通话
    }
  }

  void _onActionResolved(Map<String, Object?> payload) {
    final draftId = payload['draft_id'];
    final kind = payload['kind'];
    final current = state.pendingAction;
    if (current == null) {
      state = state.copyWith(pendingActionBusy: false);
      return;
    }
    final matchDraft = draftId is String && draftId == current.draftId;
    final matchKind =
        kind is String && pendingVoiceActionKindFromWire(kind) == current.kind;
    // 按 draft_id 或 kind 收卡（语音确认成功会带 kind）
    if (matchDraft || matchKind) {
      state = state.copyWith(
        clearPendingAction: true,
        pendingActionBusy: false,
      );
    } else {
      state = state.copyWith(pendingActionBusy: false);
    }
  }

  void _onPlaybackDrained() {
    if (!_started) return;
    _playbackPending = false;
    _playbackBeganAt = null;
    _bargeIn.reset();
    // 告别已播完：拆掉通话
    if (_awaitingHangupSpeech && _hangupSpeechStarted) {
      unawaited(stop());
      return;
    }
    // 用户仍在暂停：说完就回待机姿态，绝不自动开麦
    if (state.isPaused) {
      _syncPose(VoiceCallPhase.paused);
      return;
    }
    _mic.suppress = false;
    if (state.phase == VoiceCallPhase.speaking) {
      state = state.copyWith(phase: VoiceCallPhase.listening);
      _syncPose(VoiceCallPhase.listening);
    }
  }

  Future<void> _fail({required String title, required String message}) async {
    _completeReadyWaiter(false);
    await _teardown(resetToIdle: false);
    state = VoiceCallState(
      phase: VoiceCallPhase.error,
      errorTitle: title,
      errorMessage: message,
    );
    _syncPose(VoiceCallPhase.error);
  }

  Future<void> _teardown({required bool resetToIdle}) async {
    _started = false;
    _sessionReady = false;
    _assistantAccum = '';
    _playbackPending = false;
    _playbackBeganAt = null;
    _interrupting = false;
    _dropCancelledAssistant = false;
    _awaitingHangupSpeech = false;
    _hangupSpeechStarted = false;
    _hangupFallback?.cancel();
    _hangupFallback = null;
    _bargeIn.reset();
    _gatedPrefix.clear();
    _mic.suppress = false;
    await _setWakeLock(false);
    unawaited(_voiceBackground.stopVoiceKeepAlive());
    _completeReadyWaiter(false);
    _readyTimeout?.cancel();
    _readyTimeout = null;
    await _micSub?.cancel();
    _micSub = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _mic.stop();
    await _player.clear();
    await _socket.close();
    if (resetToIdle) {
      state = const VoiceCallState();
      _syncPose(VoiceCallPhase.idle);
    }
  }

  /// 只在通话进行中常亮；挂断 / 出错立刻放开，避免 idle 页一直亮屏耗电。
  Future<void> _setWakeLock(bool enabled) {
    _wakeLockChain = _wakeLockChain.catchError((_) {}).then((_) async {
      if (enabled) {
        await _wakeLock.enable();
      } else {
        await _wakeLock.disable();
      }
    });
    return _wakeLockChain;
  }

  void _syncPose(VoiceCallPhase phase) {
    // 通话过程只切倾听 / 说话；连接与思考并入倾听，暂停/结束/出错回待机
    final pose = switch (phase) {
      VoiceCallPhase.idle => CocoCompanionPose.idle,
      VoiceCallPhase.connecting => CocoCompanionPose.listening,
      VoiceCallPhase.listening => CocoCompanionPose.listening,
      VoiceCallPhase.thinking => CocoCompanionPose.listening,
      VoiceCallPhase.speaking => CocoCompanionPose.speaking,
      VoiceCallPhase.paused => CocoCompanionPose.idle,
      VoiceCallPhase.error => CocoCompanionPose.idle,
    };
    ref.read(cocoCompanionPoseProvider.notifier).state = pose;
  }

  void _attachMicListener() {
    final previous = _micSub;
    _micSub = null;
    if (previous != null) {
      unawaited(previous.cancel());
    }
    _micSub = _mic.pcmStream.listen(_onMicChunk);
  }

  bool get _inBargeInGrace {
    final began = _playbackBeganAt;
    if (began == null) return false;
    return DateTime.now().difference(began) < _bargeInGrace;
  }

  /// 播报中只把足够响的人声送给模型；确认插话后立刻停播。
  void _onMicChunk(Uint8List chunk) {
    if (state.isPaused) return;
    final gating =
        !_interrupting &&
        (_playbackPending || state.phase == VoiceCallPhase.speaking);
    if (gating) {
      if (_inBargeInGrace) return;
      // 保留最近几块，插话时一并送出，避免 Server VAD 丢掉句首
      _gatedPrefix.add(chunk);
      if (_gatedPrefix.length > 6) {
        _gatedPrefix.removeAt(0);
      }
      if (_bargeIn.feed(chunk)) {
        unawaited(interrupt());
        for (final prefix in _gatedPrefix) {
          unawaited(_socket.sendAudioPcm(prefix));
        }
        _gatedPrefix.clear();
      }
      return;
    }
    _gatedPrefix.clear();
    unawaited(_socket.sendAudioPcm(chunk));
  }

  /// 写入本通记录；同角色连续定稿则替换末条，避免 partial→final 重复。
  void _appendTranscript(VoiceCallTranscriptRole role, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final current = List<VoiceCallTranscriptEntry>.from(state.transcript);
    if (current.isNotEmpty && current.last.role == role) {
      current[current.length - 1] = VoiceCallTranscriptEntry(
        role: role,
        text: trimmed,
      );
    } else {
      current.add(VoiceCallTranscriptEntry(role: role, text: trimmed));
    }
    state = state.copyWith(transcript: current);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_teardown(resetToIdle: false));
    unawaited(_mic.dispose());
    unawaited(_player.dispose());
    unawaited(_socket.dispose());
    super.dispose();
  }
}

final voiceCallControllerProvider =
    StateNotifierProvider<VoiceCallController, VoiceCallState>((ref) {
      final dio = ref.watch(dioProvider);
      final tokenHolder = ref.watch(sessionTokenHolderProvider);
      return VoiceCallController(
        ref: ref,
        // 对应构造函数私有字段 this._readAccessToken / this._httpBaseUrl
        readAccessToken: () => tokenHolder.accessToken ?? '',
        httpBaseUrl: dio.options.baseUrl,
      );
    });
