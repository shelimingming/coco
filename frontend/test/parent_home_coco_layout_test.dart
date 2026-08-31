import 'package:coco/features/parent/presentation/parent_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('真机高度爪底落在设计地板线，不压底栏', () {
    const viewport = Size(393, 852);
    const bottomUi = 221.0;
    final rect = computeParentHomeCocoRect(
      viewport: viewport,
      entrance: false,
      bottomUi: bottomUi,
    );
    final scale = 393 / 410;
    expect(rect.width, closeTo(380 * scale, 0.5));
    expect(rect.height, rect.width);
    // 625：原 490 槽居中正方形的爪底，对齐白天背景地板
    expect(rect.top + rect.width, closeTo(625 * scale, 0.5));
    expect(
      rect.top + rect.width,
      lessThanOrEqualTo(viewport.height - bottomUi - kParentHomePawGap),
    );
  });

  test('手机浏览器矮屏时爪底贴底栏上方，不悬空不压按钮', () {
    const viewport = Size(390, 640);
    const bottomUi = 195.0;
    final rect = computeParentHomeCocoRect(
      viewport: viewport,
      entrance: false,
      bottomUi: bottomUi,
    );
    expect(rect.height, rect.width);
    expect(
      rect.top + rect.width,
      closeTo(viewport.height - bottomUi - kParentHomePawGap, 0.5),
    );
  });

  test('iPhone SE 矮屏不压爪子，尽量保持设计尺寸', () {
    const viewport = Size(375, 667);
    const bottomUi = 187.0;
    final rect = computeParentHomeCocoRect(
      viewport: viewport,
      entrance: false,
      bottomUi: bottomUi,
      minTop: 64,
    );
    expect(rect.height, rect.width);
    expect(rect.top, greaterThanOrEqualTo(64));
    expect(
      rect.top + rect.width,
      closeTo(viewport.height - bottomUi - kParentHomePawGap, 0.5),
    );
    // 顶栏未卡住时不缩小，只下移贴地
    expect(rect.width, closeTo(380 * (375 / 410), 0.5));
  });

  test('超矮屏仍贴爪底，必要时缩小且不盖住顶栏', () {
    const viewport = Size(360, 560);
    const bottomUi = 195.0;
    const minTop = 60.0;
    final rect = computeParentHomeCocoRect(
      viewport: viewport,
      entrance: false,
      bottomUi: bottomUi,
      minTop: minTop,
    );
    expect(rect.top, greaterThanOrEqualTo(minTop));
    expect(
      rect.top + rect.width,
      lessThanOrEqualTo(viewport.height - bottomUi - kParentHomePawGap),
    );
  });
}
