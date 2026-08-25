import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Web iPhone 外壳注入的保底安全区。
///
/// 内层若再包一层 [MediaQuery] 把 padding 盖成 0（例如只改字号却用了外壳外侧的
/// MediaQuery），普通 [SafeArea] 会失效、顶底贴边被裁。有此外壳时仍按刘海 /
/// Home Indicator 留白。
class CocoSafeInsets extends InheritedWidget {
  const CocoSafeInsets({
    super.key,
    required this.minimum,
    required super.child,
  });

  final EdgeInsets minimum;

  static EdgeInsets minimumOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<CocoSafeInsets>()
            ?.minimum ??
        EdgeInsets.zero;
  }

  /// 系统 padding 与外壳保底取较大值，给手动 Positioned / 顶栏高度用。
  static EdgeInsets paddingOf(BuildContext context) {
    final mq = MediaQuery.paddingOf(context);
    final min = minimumOf(context);
    return EdgeInsets.only(
      left: math.max(mq.left, min.left),
      top: math.max(mq.top, min.top),
      right: math.max(mq.right, min.right),
      bottom: math.max(mq.bottom, min.bottom),
    );
  }

  @override
  bool updateShouldNotify(CocoSafeInsets oldWidget) =>
      minimum != oldWidget.minimum;
}

/// 与 [SafeArea] 相同，并叠上 [CocoSafeInsets] 保底。
class CocoSafeArea extends StatelessWidget {
  const CocoSafeArea({
    super.key,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    required this.child,
  });

  final bool left;
  final bool top;
  final bool right;
  final bool bottom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final min = CocoSafeInsets.minimumOf(context);
    // SafeArea.minimum 在对应 side=false 时仍会生效，必须按开关清掉保底
    return SafeArea(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      minimum: EdgeInsets.only(
        left: left ? min.left : 0,
        top: top ? min.top : 0,
        right: right ? min.right : 0,
        bottom: bottom ? min.bottom : 0,
      ),
      child: child,
    );
  }
}
