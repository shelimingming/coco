import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

/// 流式 PCM 播放抽象；换实现时只替换此类，不改通话控制器。
abstract class PcmStreamPlayer {
  /// 通话开始前准备音频会话（须在开麦之前）。
  Future<void> prepare();

  /// 收到下行音频时立即喂入。
  Future<void> feed(Uint8List pcm, {required int sampleRate});

  /// 本轮下行音频已收完；缓冲排空后触发 onDrained。
  void markResponseComplete();

  /// 打断：立刻清空并停止。
  Future<void> clear();

  /// 停止并释放资源。
  Future<void> stop();

  /// 缓冲区排空时回调（一轮回答播完），用于恢复上行。
  set onDrained(void Function()? callback);

  Future<void> dispose();
}

/// 基于 flutter_pcm_sound 的 24kHz PCM 边收边播实现。
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
