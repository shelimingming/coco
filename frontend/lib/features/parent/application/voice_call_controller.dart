import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/mic_pcm_stream.dart';
import '../../../core/audio/pcm_stream_player.dart';
import '../../../core/network/api_client.dart';
import '../data/realtime_voice_socket.dart';
import '../domain/coco_companion_pose.dart';
import '../domain/voice_call_state.dart';
import 'coco_companion_controller.dart';

/// 父母端实时通话状态机：连接 → 听 → 想 → 说，并驱动小狗姿态。
class VoiceCallController extends StateNotifier<VoiceCallState> {
  VoiceCallController({
    required this.ref,
    required this._readAccessToken,
    required this._httpBaseUrl,
    MicPcmStream? mic,
    PcmStreamPlayer? player,
    RealtimeVoiceSocket? socket,
  }) : _mic = mic ?? MicPcmStream(),
       _player = player ?? FlutterPcmSoundPlayer(),
       _socket = socket ?? RealtimeVoiceSocket(),
       super(const VoiceCallState()) {
    // 构造期注入播放结束回调，用于恢复麦克风上行。
    _player.onDrained = _onPlaybackDrained;
  }

  final Ref ref;
  final String Function() _readAccessToken;
  final String _httpBaseUrl;
  final MicPcmStream _mic;
  final PcmStreamPlayer _player;
  final RealtimeVoiceSocket _socket;

  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<RealtimeSocketEvent>? _socketSub;
  Timer? _readyTimeout;
  bool _started = false;
  bool _sessionReady = false;
  String _assistantAccum = '';

  Future<void> start() async {
    if (_started || state.isActive) return;
    _started = true;
    _sessionReady = false;
    state = const VoiceCallState(phase: VoiceCallPhase.connecting);
    _syncPose(VoiceCallPhase.connecting);

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
    } on MicPcmException catch (e) {
      await _fail(title: '打不开麦克风', message: e.message);
    } catch (_) {
      await _fail(
        title: '连不上语音服务',
        message: '网络或语音服务暂时不可用。您可以稍后再试，刚才没有录下任何声音。',
      );
    }
  }

  Future<void> stop() async {
    if (!_started && state.phase == VoiceCallPhase.idle) return;
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
    _assistantAccum = '';
    state = state.copyWith(
      phase: VoiceCallPhase.listening,
      assistantCaption: '',
    );
    _syncPose(VoiceCallPhase.listening);
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
          state = state.copyWith(
            phase: VoiceCallPhase.thinking,
            userCaption: text,
          );
          _syncPose(VoiceCallPhase.thinking);
        }
      case 'assistant.partial':
        final text = event.text;
        if (text != null && text.isNotEmpty) {
          _assistantAccum += text;
          state = state.copyWith(
            phase: VoiceCallPhase.speaking,
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
          state = state.copyWith(
            phase: VoiceCallPhase.speaking,
            assistantCaption: text,
          );
        }
        _player.markResponseComplete();
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

  void _onPlaybackDrained() {
    if (!_started) return;
    _mic.suppress = false;
    if (state.phase == VoiceCallPhase.speaking) {
      state = state.copyWith(phase: VoiceCallPhase.listening);
      _syncPose(VoiceCallPhase.listening);
    }
  }

  Future<void> _fail({required String title, required String message}) async {
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

  void _syncPose(VoiceCallPhase phase) {
    final pose = switch (phase) {
      VoiceCallPhase.idle => CocoCompanionPose.idle,
      VoiceCallPhase.connecting => CocoCompanionPose.looking,
      VoiceCallPhase.listening => CocoCompanionPose.listening,
      VoiceCallPhase.thinking => CocoCompanionPose.thinking,
      VoiceCallPhase.speaking => CocoCompanionPose.speaking,
      VoiceCallPhase.error => CocoCompanionPose.uncertain,
    };
    ref.read(cocoCompanionPoseProvider.notifier).state = pose;
  }

  @override
  void dispose() {
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
