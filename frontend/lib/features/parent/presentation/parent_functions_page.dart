import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';

/// 老人端功能菜单：2×2 大入口，色板仅用父母端 token。
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
        childAspectRatio: 0.95,
        children: [
          _FunctionTile(
            label: '找可可',
            background: CocoColors.parentPrimarySoft,
            icon: Icons.pets_outlined,
            // 回首页，由用户点「和我说话」开始通话
            onTap: () => context.go('/parent'),
          ),
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
              const SizedBox(height: CocoSpace.s4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: CocoColors.neutral950,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
