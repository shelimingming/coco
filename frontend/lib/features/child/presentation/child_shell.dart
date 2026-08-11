import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';

/// 子女端底部三栏：近况 / 报平安 / 家庭；中间报平安为突出圆形入口。
class ChildShell extends StatelessWidget {
  const ChildShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    return Scaffold(
      body: navigationShell,
      // 自定义底栏，避免 Material NavigationBar 把中间入口做成普通 Tab
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
                _PeaceNavButton(selected: index == 1, onTap: () => _go(1)),
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

/// 中间报平安：圆形主入口，选中/未选中都保持醒目；高度严格落在底栏内。
class _PeaceNavButton extends StatelessWidget {
  const _PeaceNavButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? CocoColors.childPrimary : CocoColors.childPrimarySoft;
    final fg = selected ? CocoColors.white : CocoColors.childPrimary;
    // 44 + 2 + 12 = 58，小于底栏 64，避免 BOTTOM OVERFLOW
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 88,
        height: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: CocoColors.childSurface, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: CocoColors.childPrimary.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: SvgPicture.asset(
                'assets/icons/child/icon-nav-peace.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '报平安',
              style: TextStyle(
                fontSize: 12,
                height: 1,
                fontWeight: FontWeight.w600,
                color: selected
                    ? CocoColors.childPrimary
                    : CocoColors.neutral500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
