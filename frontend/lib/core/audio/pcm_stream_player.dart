import 'dart:typed_data';

import 'pcm_stream_player_stub.dart'
    if (dart.library.html) 'pcm_stream_player_web.dart'
    if (dart.library.io) 'pcm_stream_player_io.dart'
    as impl;

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

/// 按平台创建播放器（flutter_pcm_sound / Web Audio）。
PcmStreamPlayer createPcmStreamPlayer({int sampleRate = 24000}) =>
    impl.createPcmStreamPlayer(sampleRate: sampleRate);
