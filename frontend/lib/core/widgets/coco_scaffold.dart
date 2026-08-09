import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 带安全边距的通用页面壳。
class CocoScaffold extends StatelessWidget {
  const CocoScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.bottom,
    this.padding,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottom;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              actions: actions,
            ),
      body: SafeArea(
        child: Padding(
          padding: padding ??
              const EdgeInsets.symmetric(
                horizontal: CocoSpace.s6,
                vertical: CocoSpace.s5,
              ),
          child: body,
        ),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  CocoSpace.s6,
                  CocoSpace.s2,
                  CocoSpace.s6,
                  CocoSpace.s5,
                ),
                child: bottom,
              ),
            ),
    );
  }
}
