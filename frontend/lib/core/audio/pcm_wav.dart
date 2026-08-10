import 'dart:typed_data';

/// 将裸 PCM16 LE 包装为可上传的 WAV（不落盘）。
Uint8List pcm16ToWav(
  Uint8List pcm, {
  required int sampleRate,
  int channels = 1,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataLength = pcm.length;
  final buffer = BytesBuilder(copy: false);
  void writeString(String value) => buffer.add(value.codeUnits);
  void writeUint32(int value) {
    buffer.add([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
  }

  void writeUint16(int value) {
    buffer.add([value & 0xff, (value >> 8) & 0xff]);
  }

  writeString('RIFF');
  writeUint32(36 + dataLength);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16);
  writeUint16(1);
  writeUint16(channels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);
  writeString('data');
  writeUint32(dataLength);
  buffer.add(pcm);
  return buffer.toBytes();
}
