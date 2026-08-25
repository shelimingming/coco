import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'coco_safe_area.dart';

/// 带安全边距的通用页面壳。
class CocoScaffold extends StatelessWidget {
  const CocoScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.bottom,
    this.padding,
    this.leading,
    this.leadingWidth,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottom;
  final EdgeInsetsGeometry? padding;
  final Widget? leading;
  final double? leadingWidth;

  @override
  Widget build(BuildContext context) {
    final hasAppBar = title != null;
    final hasBottom = bottom != null;
    return Scaffold(
      appBar: hasAppBar
          ? AppBar(
              title: Text(title!),
              leading: leading,
              leadingWidth: leadingWidth,
              actions: actions,
            )
          : null,
      // AppBar 已吃掉刘海；底栏负责 Home Indicator。两边再 SafeArea 会多出一块留白挡住正文。
      body: CocoSafeArea(
        top: !hasAppBar,
        bottom: !hasBottom,
        child: Padding(
          padding:
              padding ??
              const EdgeInsets.symmetric(
                horizontal: CocoSpace.s6,
                vertical: CocoSpace.s5,
              ),
          child: body,
        ),
      ),
      bottomNavigationBar: hasBottom
          ? CocoSafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  CocoSpace.s6,
                  CocoSpace.s2,
                  CocoSpace.s6,
                  CocoSpace.s3,
                ),
                child: bottom,
              ),
            )
          : null,
    );
  }
}
