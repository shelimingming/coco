import 'dart:async';
import 'dart:typed_data';

import 'mic_pcm_stream_stub.dart'
    if (dart.library.html) 'mic_pcm_stream_web.dart'
    if (dart.library.io) 'mic_pcm_stream_io.dart'
    as impl;

/// 麦克风权限或采麦失败时抛出；文案可直接展示给老人。
class MicPcmException implements Exception {
  const MicPcmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 上行 16kHz / 16bit / mono PCM 流；与播放器解耦，便于单测与 Web/IO 分流。
abstract class MicPcmStream {
  Stream<Uint8List> get pcmStream;

  bool get isRecording;

  /// 暂停 / 识图等场景完全停发上行；播报中的插话改走能量闸门，不用此开关。
  set suppress(bool value);

  Future<bool> hasPermission();

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}

/// 按平台创建采麦实现（Web Audio / record）。
MicPcmStream createMicPcmStream() => impl.createMicPcmStream();
