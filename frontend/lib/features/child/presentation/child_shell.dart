import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';

/// 子女端底部三栏：近况 / 报平安 / 家庭，三项同权（图标+文字）。
class ChildShell extends StatelessWidget {
  const ChildShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Material(
        color: CocoColors.childSurface,
        elevation: 8,
        shadowColor: CocoColors.neutral950.withValues(alpha: 0.08),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    iconAsset: 'assets/icons/child/icon-nav-status.svg',
                    label: '近况',
                    selected: index == 0,
                    onTap: () => _go(0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    iconAsset: 'assets/icons/child/icon-nav-peace.svg',
                    label: '报平安',
                    selected: index == 1,
                    onTap: () => _go(1),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    iconAsset: 'assets/icons/child/icon-nav-family.svg',
                    label: '家庭',
                    selected: index == 2,
                    onTap: () => _go(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _go(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.iconAsset,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String iconAsset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 未选中中性灰，选中青绿；三项同一套，避免中间入口凸起/默认选中感
    final color = selected ? CocoColors.childPrimary : CocoColors.neutral500;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            iconAsset,
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
