import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 统一主按钮：加载时保留动作语义文案。
class CocoPrimaryButton extends StatelessWidget {
  const CocoPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: CocoSpace.s3),
                Text(loadingLabel ?? '请稍候…'),
              ],
            )
          : Text(label),
    );
  }
}

class CocoSecondaryButton extends StatelessWidget {
  const CocoSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryStyle = theme.filledButtonTheme.style;
    // 次按钮尺寸/圆角跟随主按钮主题，避免子女端仍是父母大点击区
    final minSize =
        primaryStyle?.minimumSize?.resolve({}) ?? const Size.fromHeight(56);
    final shape =
        primaryStyle?.shape?.resolve({}) ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CocoRadius.md),
        );

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        foregroundColor: theme.colorScheme.primary,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
        side: BorderSide(color: theme.colorScheme.primary),
        shape: shape,
      ),
      child: Text(label),
    );
  }
}

/// 老人端顶栏次入口（功能 / 返回）：白底胶囊 + success 字色，轻暖灰阴影。
class ParentChipButton extends StatelessWidget {
  const ParentChipButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(CocoRadius.pill);
    return Material(
      color: CocoColors.white,
      elevation: 1,
      shadowColor: CocoColors.neutral950.withValues(alpha: 0.08),
      borderRadius: radius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CocoSpace.s5,
            vertical: CocoSpace.s3,
          ),
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: CocoColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
