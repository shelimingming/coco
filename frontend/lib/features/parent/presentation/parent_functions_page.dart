import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';

/// 老人端功能菜单：大入口网格；说话回首页即可，不单独放「找可可」。
class ParentFunctionsPage extends StatelessWidget {
  const ParentFunctionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CocoScaffold(
      title: '今天想做什么？',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: CocoSpace.s3),
          child: Center(
            child: ParentChipButton(
              label: '返回',
              onPressed: () => context.pop(),
            ),
          ),
        ),
      ],
      body: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: CocoSpace.s4,
        crossAxisSpacing: CocoSpace.s4,
        // 两行标题（如「我记住的事」）需要更高格子，避免底部溢出
        childAspectRatio: 0.85,
        children: [
          _FunctionTile(
            label: '今天',
            // 软绿底：success 叠中性底，不用子女端青绿
            background: Color.alphaBlend(
              CocoColors.success.withValues(alpha: 0.14),
              CocoColors.neutral100,
            ),
            icon: Icons.check_rounded,
            onTap: () => context.push('/parent/reminders'),
          ),
          _FunctionTile(
            label: '我记住的事',
            background: CocoColors.neutral100,
            icon: Icons.menu_book_outlined,
            onTap: () => context.push('/parent/memories'),
          ),
          _FunctionTile(
            label: '历史记录',
            // 暖色中性底：介于记忆与设置之间，仍只用父母端 token
            background: Color.alphaBlend(
              CocoColors.parentPrimary.withValues(alpha: 0.10),
              CocoColors.neutral100,
            ),
            icon: Icons.history_rounded,
            onTap: () => context.push('/parent/history'),
          ),
          _FunctionTile(
            label: '我的',
            background: Color.alphaBlend(
              CocoColors.parentSecondary.withValues(alpha: 0.16),
              CocoColors.neutral100,
            ),
            icon: Icons.settings_outlined,
            onTap: () => context.push('/parent/settings'),
          ),
        ],
      ),
    );
  }
}

class _FunctionTile extends StatelessWidget {
  const _FunctionTile({
    required this.label,
    required this.background,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Color background;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(CocoRadius.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        child: Padding(
          padding: const EdgeInsets.all(CocoSpace.s5),
          // 极窄屏时等比缩小，避免 Column 硬溢出
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: CocoColors.white,
                    borderRadius: BorderRadius.circular(CocoRadius.md),
                  ),
                  child: Icon(icon, size: 36, color: CocoColors.neutral950),
                ),
                const SizedBox(height: CocoSpace.s3),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: CocoColors.neutral950,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
