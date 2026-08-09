import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 全局统一加载指示器：跟随当前角色主色，尺寸与描边固定。
class CocoLoadingIndicator extends StatelessWidget {
  const CocoLoadingIndicator({
    super.key,
    this.size = 22,
    this.strokeWidth = 2.5,
    this.color,
  });

  final double size;
  final double strokeWidth;

  /// 未指定时用 [ColorScheme.primary]；主按钮内应传 onPrimary。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: resolved,
      ),
    );
  }
}

/// 按钮内加载行：转圈 + 保留动作语义文案（DESIGN §8.1 / §10）。
class CocoLoadingLabel extends StatelessWidget {
  const CocoLoadingLabel({super.key, required this.label, this.indicatorColor});

  final String label;
  final Color? indicatorColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        CocoLoadingIndicator(color: indicatorColor),
        const SizedBox(width: CocoSpace.s3),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// 页面级加载：居中转圈 + 说明，避免裸 CircularProgressIndicator。
class CocoPageLoading extends StatelessWidget {
  const CocoPageLoading({super.key, this.message = '正在加载…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CocoLoadingIndicator(size: 28, strokeWidth: 3),
            const SizedBox(height: CocoSpace.s4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: CocoColors.neutral700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
