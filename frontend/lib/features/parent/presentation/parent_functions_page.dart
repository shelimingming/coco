import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_safe_area.dart';

/// 老人端「更多功能」：低密度列表入口；返回后恢复进入前的首页状态。
class ParentFunctionsPage extends StatelessWidget {
  const ParentFunctionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <_MoreEntry>[
      const _MoreEntry(
        label: '提醒',
        iconAsset: 'assets/icons/parent/icon-more-reminder.svg',
        route: '/parent/reminders',
      ),
      const _MoreEntry(
        label: '可可记得的我',
        iconAsset: 'assets/icons/parent/icon-more-memory.svg',
        route: '/parent/memories',
      ),
      const _MoreEntry(
        label: '历史记录',
        iconAsset: 'assets/icons/parent/icon-more-history.svg',
        route: '/parent/history',
      ),
      const _MoreEntry(
        label: '我的',
        iconAsset: 'assets/icons/parent/icon-more-my.svg',
        route: '/parent/settings',
      ),
    ];

    return Scaffold(
      backgroundColor: CocoColors.parentBackground,
      body: CocoSafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MoreAppBar(onBack: () => context.pop()),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  CocoSpace.s6,
                  CocoSpace.s4,
                  CocoSpace.s6,
                  CocoSpace.s8,
                ),
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: CocoSpace.s4),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _MoreRow(
                    label: entry.label,
                    iconAsset: entry.iconAsset,
                    onTap: () => context.push(entry.route),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreEntry {
  const _MoreEntry({
    required this.label,
    required this.iconAsset,
    required this.route,
  });

  final String label;
  final String iconAsset;
  final String route;
}

class _MoreAppBar extends StatelessWidget {
  const _MoreAppBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s3),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ParentBackButton(onPressed: onBack),
            ),
            const Text(
              '更多功能',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: CocoColors.neutral950,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.label,
    required this.iconAsset,
    required this.onTap,
  });

  final String label;
  final String iconAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CocoColors.white,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        boxShadow: const [
          BoxShadow(
            color: CocoColors.onboardingShadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CocoRadius.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CocoSpace.s5,
                vertical: CocoSpace.s5,
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: CocoColors.parentPrimarySoft,
                      shape: BoxShape.circle,
                    ),
                    // SVG 源为墨绿描边，滤镜统一成父母暖橙
                    child: SvgPicture.asset(
                      iconAsset,
                      width: 28,
                      height: 28,
                      colorFilter: const ColorFilter.mode(
                        CocoColors.parentPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  const SizedBox(width: CocoSpace.s4),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: CocoColors.neutral950,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 28,
                    color: CocoColors.neutral500,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
