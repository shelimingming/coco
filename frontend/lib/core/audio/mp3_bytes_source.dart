// StreamAudioSource 是 just_audio 官方推荐的内存字节播法。
// ignore_for_file: experimental_member_use

import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// 用内存中的音频字节作为 [just_audio] 音源（服务端 TTS 直出，不落盘）。
/// 兼容 WAV（百炼 Qwen3-TTS）与 MP3。
class Mp3BytesSource extends StreamAudioSource {
  Mp3BytesSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= bytes.length;
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(bytes.sublist(start, end)),
      contentType: _sniffContentType(bytes),
    );
  }
}

String _sniffContentType(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46) {
    return 'audio/wav';
  }
  return 'audio/mpeg';
}
