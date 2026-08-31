import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:coco/core/audio/mic_pcm_stream.dart';
import 'package:coco/core/audio/pcm_stream_player.dart';
import 'package:coco/core/screen/screen_wake_lock.dart';
import 'package:coco/features/parent/application/voice_call_controller.dart';
import 'package:coco/features/parent/data/realtime_voice_socket.dart';
import 'package:coco/features/parent/domain/voice_call_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('播报中收到 speech.started 不会停播', () async {
    final socket = _FakeSocket(emitReady: true);
    final player = _FakePlayer();
    final env = _envFor(socket: socket, player: player);
    addTearDown(env.container.dispose);

    await env.controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(env.controller.state.phase, VoiceCallPhase.listening);

    socket.emit('assistant.audio', {
      'audio': base64Encode(Uint8List(8)),
      'sample_rate': 24000,
    });
    await Future<void>.delayed(Duration.zero);
    expect(env.controller.state.phase, VoiceCallPhase.speaking);

    socket.emit('speech.started');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(env.controller.state.phase, VoiceCallPhase.speaking);
    expect(socket.cancelCount, 0);
    expect(player.clearCount, 0);
  });

  test('播报中开口足够响也不会本地插话', () async {
    final socket = _FakeSocket(emitReady: true);
    final mic = _FakeMic();
    final player = _FakePlayer();
    final env = _envFor(socket: socket, mic: mic, player: player);
    addTearDown(env.container.dispose);

    await env.controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    socket.emit('assistant.audio', {
      'audio': base64Encode(Uint8List(8)),
      'sample_rate': 24000,
    });
    await Future<void>.delayed(Duration.zero);
    expect(env.controller.state.phase, VoiceCallPhase.speaking);
    final sentBefore = socket.sentAudioCount;

    // suppress 开着时麦流本不会到 controller；再喂一块也不得打断
    mic.forceAdd(_pcm(samples: 1600, amplitude: 8000));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(env.controller.state.phase, VoiceCallPhase.speaking);
    expect(socket.cancelCount, 0);
    expect(player.clearCount, 0);
    expect(socket.sentAudioCount, sentBefore);
  });

  test('播完后尾音保护期内不把麦流送给服务端', () async {
    final socket = _FakeSocket(emitReady: true);
    final mic = _FakeMic();
    final player = _FakePlayer();
    final env = _envFor(socket: socket, mic: mic, player: player);
    addTearDown(env.container.dispose);

    await env.controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    socket.emit('assistant.audio', {
      'audio': base64Encode(Uint8List(8)),
      'sample_rate': 24000,
    });
    await Future<void>.delayed(Duration.zero);
    expect(env.controller.state.phase, VoiceCallPhase.speaking);

    // 模拟播放器缓冲排空
    player.fireDrained();
    await Future<void>.delayed(Duration.zero);
    expect(env.controller.state.phase, VoiceCallPhase.listening);

    final sentAtDrain = socket.sentAudioCount;
    // 保护期内即使绕过 mic.suppress，controller 闸门仍应丢弃
    mic.forceAdd(_pcm(samples: 1600, amplitude: 8000));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(socket.sentAudioCount, sentAtDrain);

    // 保护期结束后才允许上行
    await Future<void>.delayed(kPostPlaybackEchoGuard);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    mic.forceAdd(_pcm(samples: 1600, amplitude: 8000));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(socket.sentAudioCount, greaterThan(sentAtDrain));
  });

  test('点打断后尾音保护期内不把麦流送给服务端', () async {
    final socket = _FakeSocket(emitReady: true);
    final mic = _FakeMic();
    final player = _FakePlayer();
    final env = _envFor(socket: socket, mic: mic, player: player);
    addTearDown(env.container.dispose);

    await env.controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    socket.emit('assistant.audio', {
      'audio': base64Encode(Uint8List(8)),
      'sample_rate': 24000,
    });
    await Future<void>.delayed(Duration.zero);
    expect(env.controller.state.phase, VoiceCallPhase.speaking);

    await env.controller.interrupt();
    expect(env.controller.state.phase, VoiceCallPhase.listening);
    expect(socket.cancelCount, 1);
    expect(player.clearCount, 1);

    final sentAtInterrupt = socket.sentAudioCount;
    // 硬停播同样有喇叭尾音，保护期内不得上行
    mic.forceAdd(_pcm(samples: 1600, amplitude: 8000));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(socket.sentAudioCount, sentAtInterrupt);

    await Future<void>.delayed(kPostPlaybackEchoGuard);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    mic.forceAdd(_pcm(samples: 1600, amplitude: 8000));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(socket.sentAudioCount, greaterThan(sentAtInterrupt));
  });
}

({ProviderContainer container, VoiceCallController controller}) _envFor({
  required _FakeSocket socket,
  _FakeMic? mic,
  _FakePlayer? player,
}) {
  final container = ProviderContainer(
    overrides: [
      voiceCallControllerProvider.overrideWith((ref) {
        return VoiceCallController(
          ref: ref,
          readAccessToken: () => 'token',
          httpBaseUrl: 'http://127.0.0.1',
          mic: mic ?? _FakeMic(),
          player: player ?? _FakePlayer(),
          socket: socket,
          wakeLock: _FakeWakeLock(),
        );
      }),
    ],
  );
  return (
    container: container,
    controller: container.read(voiceCallControllerProvider.notifier),
  );
}

Uint8List _pcm({required int samples, required int amplitude}) {
  final bytes = Uint8List(samples * 2);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    bd.setInt16(i * 2, amplitude, Endian.little);
  }
  return bytes;
}

class _FakeWakeLock implements ScreenWakeLock {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

class _FakeMic implements MicPcmStream {
  final _controller = StreamController<Uint8List>.broadcast();
  bool _suppress = false;

  @override
  Stream<Uint8List> get pcmStream => _controller.stream;

  @override
  bool get isRecording => true;

  @override
  set suppress(bool value) => _suppress = value;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void addPcm(Uint8List chunk) {
    if (_suppress) return;
    _controller.add(chunk);
  }

  /// 测试用：绕过 suppress，确认 controller 闸门仍丢弃播报中麦流。
  void forceAdd(Uint8List chunk) => _controller.add(chunk);
}

class _FakePlayer implements PcmStreamPlayer {
  int clearCount = 0;
  void Function()? _onDrained;

  @override
  set onDrained(void Function()? callback) => _onDrained = callback;

  /// 测试用：模拟缓冲排空。
  void fireDrained() => _onDrained?.call();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> feed(Uint8List pcm, {required int sampleRate}) async {}

  @override
  void markResponseComplete() {}

  @override
  Future<void> clear() async {
    clearCount++;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeSocket extends RealtimeVoiceSocket {
  _FakeSocket({this.emitReady = false});

  final bool emitReady;
  final _controller = StreamController<RealtimeSocketEvent>.broadcast();
  int cancelCount = 0;
  int sentAudioCount = 0;

  @override
  Stream<RealtimeSocketEvent> get events => _controller.stream;

  void emit(String type, [Map<String, Object?> payload = const {}]) {
    if (!_controller.isClosed) {
      _controller.add(RealtimeSocketEvent(type, payload));
    }
  }

  @override
  Future<void> connect(Uri uri) async {
    if (emitReady) {
      unawaited(
        Future<void>.delayed(Duration.zero, () {
          emit('session.ready');
        }),
      );
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> endSession() async {}

  @override
  Future<void> cancelResponse() async {
    cancelCount++;
  }

  @override
  Future<void> sendAudioPcm(Uint8List pcm) async {
    sentAudioCount++;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
