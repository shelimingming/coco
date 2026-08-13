// StreamAudioSource 是 just_audio 官方推荐的内存字节播法。
// ignore_for_file: experimental_member_use

import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// 用内存中的 MP3 字节作为 [just_audio] 音源（服务端 TTS 直出，不落盘）。
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
      contentType: 'audio/mpeg',
    );
  }
}
