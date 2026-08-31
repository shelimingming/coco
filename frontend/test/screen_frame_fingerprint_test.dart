import 'dart:typed_data';

import 'package:coco/features/look/domain/screen_frame_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

  test('相同内容指纹稳定', () {
    final a = _bytes(List<int>.generate(1024, (i) => i % 256));
    final b = _bytes(List<int>.generate(1024, (i) => i % 256));
    expect(screenFrameFingerprint(a), screenFrameFingerprint(b));
  });

  test('明显不同内容判定为 differ', () {
    final a = _bytes(List<int>.filled(512, 10));
    final b = _bytes(List<int>.filled(512, 200));
    final ha = screenFrameFingerprint(a);
    final hb = screenFrameFingerprint(b);
    expect(screenFramesDiffer(ha, hb), isTrue);
  });

  test('连续相近指纹判定为 settled', () {
    expect(screenFramesSettled([100, 101, 100]), isTrue);
    expect(screenFramesSettled([100, 120, 100]), isFalse);
    expect(screenFramesSettled([100]), isFalse);
  });
}
