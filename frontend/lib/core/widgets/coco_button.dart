import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'coco_loading.dart';

/// 统一主按钮：加载时保留动作语义文案，外观不灰掉以免转圈看不见。
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
    final scheme = Theme.of(context).colorScheme;
    return FilledButton(
      // loading 时禁用点击，但用主色禁用样式，避免灰底 + 白圈对比失效
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        disabledBackgroundColor: scheme.primary,
        disabledForegroundColor: scheme.onPrimary,
      ),
      child: loading
          ? CocoLoadingLabel(
              label: loadingLabel ?? '请稍候…',
              indicatorColor: scheme.onPrimary,
            )
          : Text(label),
    );
  }
}

/// 统一次按钮：与主按钮同一套 loading 语义与尺寸。
class CocoSecondaryButton extends StatelessWidget {
  const CocoSecondaryButton({
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        foregroundColor: scheme.primary,
        disabledForegroundColor: scheme.primary,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          color: scheme.primary,
        ),
        side: BorderSide(color: scheme.primary),
        shape: shape,
      ).copyWith(
        // 加载中保持主色描边，不退化成中性灰
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(
              color: scheme.primary.withValues(alpha: loading ? 1 : 0.38),
            );
          }
          return BorderSide(color: scheme.primary);
        }),
      ),
      child: loading
          ? CocoLoadingLabel(
              label: loadingLabel ?? '请稍候…',
              indicatorColor: scheme.primary,
            )
          : Text(label),
    );
  }
}

/// 老人端顶栏次入口（功能 / 返回）：白底胶囊 + 暖褐字色，轻暖灰阴影。
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
              // 次操作用 elder.secondary，不用 success（完成语义）或子女青绿
              color: CocoColors.parentSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
