import 'package:coco/features/parent/presentation/parent_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('真机高度保持设计位置，爪子在底栏之上', () {
    const viewport = Size(393, 852);
    const bottomUi = 221.0;
    final rect = computeParentHomeCocoRect(
      viewport: viewport,
      entrance: false,
      bottomUi: bottomUi,
    );
    final scale = 393 / 410;
    expect(rect.top, closeTo(190 * scale, 0.5));
    expect(rect.width, closeTo(380 * scale, 0.5));
    expect(
      rect.top + rect.width,
      lessThanOrEqualTo(viewport.height - bottomUi),
    );
  });

  test('手机浏览器矮屏时缩小可可，爪子不超过底栏', () {
    const viewport = Size(390, 640);
    const bottomUi = 195.0;
    final rect = computeParentHomeCocoRect(
      viewport: viewport,
      entrance: false,
      bottomUi: bottomUi,
    );
    expect(rect.width, lessThan(380 * (390 / 410)));
    expect(
      rect.top + rect.width,
      lessThanOrEqualTo(viewport.height - bottomUi),
    );
  });
}
