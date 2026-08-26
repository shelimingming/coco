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
}

ProviderContainer _containerFor({
  required String token,
  required ScreenWakeLock lock,
}) {
  return ProviderContainer(
    overrides: [
      voiceCallControllerProvider.overrideWith((ref) {
        return VoiceCallController(
          ref: ref,
          readAccessToken: () => token,
          httpBaseUrl: 'http://127.0.0.1',
          mic: _FakeMic(),
          player: _FakePlayer(),
          socket: _FakeSocket(),
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

  @override
  Stream<Uint8List> get pcmStream => _controller.stream;

  @override
  bool get isRecording => false;

  @override
  set suppress(bool value) {}

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
  @override
  Future<void> connect(Uri uri) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> endSession() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> sendAudioPcm(Uint8List pcm) async {}
}
