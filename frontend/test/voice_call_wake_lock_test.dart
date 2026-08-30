import 'dart:async';
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

  test('通话开始申请常亮，结束时放开', () async {
    final lock = _RecordingWakeLock();
    final container = _containerFor(token: 'token', lock: lock);
    addTearDown(container.dispose);

    final controller = container.read(voiceCallControllerProvider.notifier);
    await controller.start();
    expect(lock.enabled, isTrue);
    expect(controller.state.phase, VoiceCallPhase.connecting);

    await controller.stop();
    expect(lock.enabled, isFalse);
    expect(controller.state.phase, VoiceCallPhase.idle);
  });

  test('未登录失败时也会放开常亮', () async {
    final lock = _RecordingWakeLock();
    final container = _containerFor(token: '', lock: lock);
    addTearDown(container.dispose);

    final controller = container.read(voiceCallControllerProvider.notifier);
    await controller.start();
    expect(controller.state.phase, VoiceCallPhase.error);
    expect(lock.enabled, isFalse);
    expect(lock.enableCount, 1);
    expect(lock.disableCount, 1);
  });

  test('暂停保留 session，继续不新建连接', () async {
    final lock = _RecordingWakeLock();
    final socket = _FakeSocket(emitReady: true);
    final mic = _FakeMic();
    final container = _containerFor(
      token: 'token',
      lock: lock,
      socket: socket,
      mic: mic,
    );
    addTearDown(container.dispose);

    final controller = container.read(voiceCallControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.state.phase, VoiceCallPhase.listening);
    expect(socket.connectCount, 1);
    expect(mic.startCount, 1);

    await controller.pause();
    expect(controller.state.isPaused, isTrue);
    expect(controller.state.isInSession, isTrue);
    expect(controller.state.isActive, isFalse);
    expect(mic.stopCount, greaterThanOrEqualTo(1));
    expect(socket.connectCount, 1);

    await controller.resume();
    expect(controller.state.phase, VoiceCallPhase.listening);
    expect(controller.state.isActive, isTrue);
    expect(socket.connectCount, 1);
    expect(mic.startCount, greaterThanOrEqualTo(2));
  });

  test('语音 home.action 可暂停通话', () async {
    final lock = _RecordingWakeLock();
    final socket = _FakeSocket(emitReady: true);
    final mic = _FakeMic();
    final container = _containerFor(
      token: 'token',
      lock: lock,
      socket: socket,
      mic: mic,
    );
    addTearDown(container.dispose);

    final controller = container.read(voiceCallControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.state.phase, VoiceCallPhase.listening);

    socket.emit('home.action', {'action': 'pause_call'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.state.isPaused, isTrue);
    expect(controller.state.isInSession, isTrue);
    expect(socket.connectCount, 1);
  });

  test('语音 home.action 看眼前会通知首页', () async {
    final lock = _RecordingWakeLock();
    final socket = _FakeSocket(emitReady: true);
    final container = _containerFor(token: 'token', lock: lock, socket: socket);
    addTearDown(container.dispose);

    final controller = container.read(voiceCallControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    socket.emit('home.action', {'action': 'open_look_front'});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(voicePendingHomeActionProvider), 'open_look_front');
    expect(container.read(voicePendingNavigateProvider), '/parent');
  });
}

ProviderContainer _containerFor({
  required String token,
  required ScreenWakeLock lock,
  RealtimeVoiceSocket? socket,
  MicPcmStream? mic,
}) {
  return ProviderContainer(
    overrides: [
      voiceCallControllerProvider.overrideWith((ref) {
        return VoiceCallController(
          ref: ref,
          readAccessToken: () => token,
          httpBaseUrl: 'http://127.0.0.1',
          mic: mic ?? _FakeMic(),
          player: _FakePlayer(),
          socket: socket ?? _FakeSocket(),
          wakeLock: lock,
        );
      }),
    ],
  );
}

class _RecordingWakeLock implements ScreenWakeLock {
  bool enabled = false;
  int enableCount = 0;
  int disableCount = 0;

  @override
  Future<void> enable() async {
    enabled = true;
    enableCount++;
  }

  @override
  Future<void> disable() async {
    enabled = false;
    disableCount++;
  }
}

class _FakeMic implements MicPcmStream {
  final _controller = StreamController<Uint8List>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<Uint8List> get pcmStream => _controller.stream;

  @override
  bool get isRecording => false;

  @override
  set suppress(bool value) {}

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakePlayer implements PcmStreamPlayer {
  @override
  set onDrained(void Function()? callback) {}

  @override
  Future<void> prepare() async {}

  @override
  Future<void> feed(Uint8List pcm, {required int sampleRate}) async {}

  @override
  void markResponseComplete() {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeSocket extends RealtimeVoiceSocket {
  _FakeSocket({this.emitReady = false});

  final bool emitReady;
  final _controller = StreamController<RealtimeSocketEvent>.broadcast();
  int connectCount = 0;

  @override
  Stream<RealtimeSocketEvent> get events => _controller.stream;

  void emit(String type, [Map<String, Object?> payload = const {}]) {
    if (!_controller.isClosed) {
      _controller.add(RealtimeSocketEvent(type, payload));
    }
  }

  @override
  Future<void> connect(Uri uri) async {
    connectCount++;
    if (emitReady) {
      // Duration.zero 排在 microtask 之后，确保调用方已 listen(events)
      unawaited(
        Future<void>.delayed(Duration.zero, () {
          if (!_controller.isClosed) {
            _controller.add(const RealtimeSocketEvent('session.ready', {}));
          }
        }),
      );
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> endSession() async {}

  @override
  Future<void> cancelResponse() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Future<void> sendAudioPcm(Uint8List pcm) async {}
}
