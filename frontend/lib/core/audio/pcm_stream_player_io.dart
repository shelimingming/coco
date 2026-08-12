import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import 'pcm_stream_player.dart';

/// iOS/Android：基于 flutter_pcm_sound 的 24kHz PCM 边收边播。
PcmStreamPlayer createPcmStreamPlayer({int sampleRate = 24000}) =>
    FlutterPcmSoundPlayer(sampleRate: sampleRate);

class FlutterPcmSoundPlayer implements PcmStreamPlayer {
  FlutterPcmSoundPlayer({this.sampleRate = 24000});

  final int sampleRate;
  void Function()? _onDrained;
  bool _setupDone = false;
  bool _expectDrain = false;
  bool _disposed = false;

  @override
  set onDrained(void Function()? callback) => _onDrained = callback;

  @override
  Future<void> prepare() => _ensureSetup();

  Future<void> _ensureSetup() async {
    if (_setupDone || _disposed) return;
    // playAndRecord 支持录放同时；麦克风 startStream 须在此之后调用以便外放。
    await FlutterPcmSound.setup(
      sampleRate: sampleRate,
      channelCount: 1,
      iosAudioCategory: IosAudioCategory.playAndRecord,
    );
    await FlutterPcmSound.setFeedThreshold(2000);
    FlutterPcmSound.setFeedCallback(_handleFeedCallback);
    _setupDone = true;
  }

  void _handleFeedCallback(int remainingFrames) {
    if (_disposed) return;
    // remainingFrames==0 且本轮已收到 final，视为播完。
    if (remainingFrames == 0 && _expectDrain) {
      _expectDrain = false;
      _onDrained?.call();
    }
  }

  @override
  Future<void> feed(Uint8List pcm, {required int sampleRate}) async {
    if (_disposed || pcm.isEmpty) return;
    await _ensureSetup();
    _expectDrain = true;
    // 拷贝到独立 buffer，避免 ByteData 视图偏移导致整段底层内存被送入播放器。
    final copy = Uint8List.fromList(pcm);
    await FlutterPcmSound.feed(
      PcmArrayInt16(bytes: ByteData.sublistView(copy)),
    );
  }

  @override
  void markResponseComplete() {
    _expectDrain = true;
    // 若缓冲已空，主动探测一次（start 会触发 remainingFrames=0 回调）。
    FlutterPcmSound.start();
  }

  @override
  Future<void> clear() async {
    _expectDrain = false;
    if (!_setupDone) return;
    await FlutterPcmSound.release();
    _setupDone = false;
  }

  @override
  Future<void> stop() => clear();

  @override
  Future<void> dispose() async {
    _disposed = true;
    _onDrained = null;
    FlutterPcmSound.setFeedCallback(null);
    await clear();
  }
}
