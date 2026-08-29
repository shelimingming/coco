import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 父母端实时通话状态机：连接 → 听 → 想 → 说；小狗姿态仅倾听 / 说话。
class VoiceCallController extends StateNotifier<VoiceCallState>
    with WidgetsBindingObserver {
  VoiceCallController({
    required this.ref,
    required this._readAccessToken,
    required this._httpBaseUrl,
    MicPcmStream? mic,
    PcmStreamPlayer? player,
    RealtimeVoiceSocket? socket,
    ScreenWakeLock? wakeLock,
  }) : _mic = mic ?? createMicPcmStream(),
       _player = player ?? createPcmStreamPlayer(),
       _socket = socket ?? RealtimeVoiceSocket(),
       _wakeLock = wakeLock ?? createScreenWakeLock(),
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

  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<RealtimeSocketEvent>? _socketSub;
  Timer? _readyTimeout;
  bool _started = false;
  bool _sessionReady = false;
  String _assistantAccum = '';
  Completer<bool>? _readyWaiter;

  /// 串行化常亮开关，避免 start / teardown 交错导致挂断后仍亮屏
  Future<void> _wakeLockChain = Future.value();

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
      _micSub = _mic.pcmStream.listen((chunk) {
        unawaited(_socket.sendAudioPcm(chunk));
      });
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
    // 注入后等模型开口；播报时仍由 assistant.audio 抑制麦克风
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

  /// 打断当前播报；点小狗在 speaking 时也走这里。
  Future<void> interrupt() async {
    if (!state.canInterrupt) return;
    try {
      await _socket.cancelResponse();
    } catch (_) {}
    await _player.clear();
    _mic.suppress = false;
    // 已说出的半句仍记入本通记录，方便「字」面板回看
    final spoken = _assistantAccum.trim();
    if (spoken.isNotEmpty) {
      _appendTranscript(VoiceCallTranscriptRole.assistant, spoken);
    }
    _assistantAccum = '';
    state = state.copyWith(
      phase: VoiceCallPhase.listening,
      assistantCaption: '',
    );
    _syncPose(VoiceCallPhase.listening);
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
      if (_started && this.state.isActive) {
        // 确保上行未因旧逻辑卡住
        if (this.state.phase != VoiceCallPhase.speaking) {
          _mic.suppress = false;
        }
        unawaited(_setWakeLock(true));
        unawaited(_voiceBackground.onEnteredForeground());
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
        state = state.copyWith(
          phase: VoiceCallPhase.listening,
          userCaption: '',
          assistantCaption: '',
        );
        _assistantAccum = '';
        _syncPose(VoiceCallPhase.listening);
      case 'speech.stopped':
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
        final text = event.text;
        if (text != null && text.isNotEmpty) {
          _assistantAccum += text;
          // 清空残留 userCaption，避免「字」面板在可可说话时再拼出上一句「您」
          state = state.copyWith(
            phase: VoiceCallPhase.speaking,
            userCaption: '',
            assistantCaption: _assistantAccum,
          );
          _syncPose(VoiceCallPhase.speaking);
        }
      case 'assistant.audio':
        final b64 = event.audioBase64;
        if (b64 == null || b64.isEmpty) return;
        _mic.suppress = true;
        state = state.copyWith(phase: VoiceCallPhase.speaking);
        _syncPose(VoiceCallPhase.speaking);
        try {
          final pcm = base64Decode(b64);
          unawaited(
            _player.feed(Uint8List.fromList(pcm), sampleRate: event.sampleRate),
          );
        } catch (_) {}
      case 'assistant.final':
        final text = event.text;
        if (text != null && text.isNotEmpty) {
          _assistantAccum = text;
          _appendTranscript(VoiceCallTranscriptRole.assistant, text);
          state = state.copyWith(
            phase: VoiceCallPhase.speaking,
            userCaption: '',
            assistantCaption: text,
          );
        }
        _player.markResponseComplete();
      case 'action.pending':
        _onActionPending(event.payload);
      case 'action.resolved':
        _onActionResolved(event.payload);
      case 'navigate.open':
        // 语音打开页面：会话跨页保留，不挂断
        _onNavigateOpen(event.payload);
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
        if (state.isActive || state.phase == VoiceCallPhase.connecting) {
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
    // 通话过程只切倾听 / 说话；连接与思考并入倾听，结束或出错回待机
    final pose = switch (phase) {
      VoiceCallPhase.idle => CocoCompanionPose.idle,
      VoiceCallPhase.connecting => CocoCompanionPose.listening,
      VoiceCallPhase.listening => CocoCompanionPose.listening,
      VoiceCallPhase.thinking => CocoCompanionPose.listening,
      VoiceCallPhase.speaking => CocoCompanionPose.speaking,
      VoiceCallPhase.error => CocoCompanionPose.idle,
    };
    ref.read(cocoCompanionPoseProvider.notifier).state = pose;
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
