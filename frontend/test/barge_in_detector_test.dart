import 'dart:typed_data';

import 'package:coco/core/audio/barge_in_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连续足够响的人声触发插话', () {
    final detector = BargeInDetector(rmsThreshold: 700, minSpeechMs: 100);
    expect(detector.feed(_pcm(samples: 1600, amplitude: 8000)), isTrue);
  });

  test('回声级能量不触发', () {
    final detector = BargeInDetector(rmsThreshold: 700, minSpeechMs: 100);
    expect(detector.feed(_pcm(samples: 1600, amplitude: 80)), isFalse);
    expect(detector.feed(_pcm(samples: 1600, amplitude: 80)), isFalse);
  });

  test('短促响声不够时长则不触发', () {
    final detector = BargeInDetector(rmsThreshold: 700, minSpeechMs: 100);
    expect(detector.feed(_pcm(samples: 320, amplitude: 8000)), isFalse);
  });
}

Uint8List _pcm({required int samples, required int amplitude}) {
  final bytes = Uint8List(samples * 2);
  final bd = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    bd.setInt16(i * 2, amplitude, Endian.little);
  }
  return bytes;
}
