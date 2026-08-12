import 'dart:math';
import 'dart:typed_data';

/// 本地静音判定：对齐服务端 VAD 约 800ms 静音收手，避免追问页每轮点两次。
class SpeechEndDetector {
  SpeechEndDetector({
    this.silenceRmsThreshold = 450,
    this.silenceDurationMs = 800,
    this.maxDurationMs = 15000,
    this.noSpeechTimeoutMs = 5000,
    this.sampleRate = 16000,
  });

  final int silenceRmsThreshold;
  final int silenceDurationMs;
  final int maxDurationMs;
  final int noSpeechTimeoutMs;
  final int sampleRate;

  bool _speechDetected = false;
  int _silenceMs = 0;
  int _totalMs = 0;
  int _noSpeechMs = 0;

  bool get hadSpeech => _speechDetected;

  void reset() {
    _speechDetected = false;
    _silenceMs = 0;
    _totalMs = 0;
    _noSpeechMs = 0;
  }

  /// 喂入 PCM16 块；返回 true 表示应结束录音。
  bool feed(Uint8List pcmChunk) {
    if (pcmChunk.isEmpty) return false;

    final chunkMs = (pcmChunk.length / (sampleRate * 2) * 1000).round();
    _totalMs += chunkMs;

    final rms = _computeRms(pcmChunk);
    if (rms >= silenceRmsThreshold) {
      _speechDetected = true;
      _silenceMs = 0;
      _noSpeechMs = 0;
    } else if (_speechDetected) {
      _silenceMs += chunkMs;
      if (_silenceMs >= silenceDurationMs) return true;
    } else {
      _noSpeechMs += chunkMs;
      if (_noSpeechMs >= noSpeechTimeoutMs) return true;
    }

    if (_totalMs >= maxDurationMs) return true;
    return false;
  }

  int _computeRms(Uint8List pcm) {
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
}
