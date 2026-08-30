import 'dart:math';
import 'dart:typed_data';

/// 播报中的本地插话检测：能量明显高于喇叭回声残量，才视为老人开口。
///
/// 不把回声送给 Realtime，避免 Server VAD 误打断；人声连续超过短窗再触发。
class BargeInDetector {
  BargeInDetector({
    this.rmsThreshold = 700,
    this.minSpeechMs = 100,
    this.sampleRate = 16000,
  });

  /// 高于此 RMS 才算人声；静音判定约 450，回声残量通常更低。
  final int rmsThreshold;
  final int minSpeechMs;
  final int sampleRate;

  int _speechMs = 0;

  void reset() {
    _speechMs = 0;
  }

  /// 喂入 16k PCM16；连续足够响则返回 true，并自行清零。
  bool feed(Uint8List pcmChunk) {
    if (pcmChunk.length < 2) return false;
    final chunkMs = (pcmChunk.length / (sampleRate * 2) * 1000).round();
    if (chunkMs <= 0) return false;

    if (pcm16Rms(pcmChunk) >= rmsThreshold) {
      _speechMs += chunkMs;
      if (_speechMs >= minSpeechMs) {
        reset();
        return true;
      }
    } else {
      _speechMs = 0;
    }
    return false;
  }
}

int pcm16Rms(Uint8List pcm) {
  if (pcm.length < 2) return 0;
  var sum = 0.0;
  final samples = pcm.length ~/ 2;
  for (var i = 0; i < samples; i++) {
    final lo = pcm[i * 2];
    final hi = pcm[i * 2 + 1];
    var sample = (hi << 8) | lo;
    if (sample >= 0x8000) sample -= 0x10000;
    sum += sample * sample;
  }
  return sqrt(sum / samples).round();
}
