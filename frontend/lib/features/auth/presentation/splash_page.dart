import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_loading.dart';

/// 启动页品牌图标（与桌面 AppIcon 同源）。
const String kAppIconAsset = 'assets/images/coco_app_icon.png';

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CocoColors.parentBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: '可可',
              image: true,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CocoRadius.xl),
                child: Image.asset(
                  kAppIconAsset,
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
            ),
            const SizedBox(height: CocoSpace.s6),
            Text(
              '可可',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: CocoColors.parentPrimary,
              ),
            ),
            const SizedBox(height: CocoSpace.s6),
            // 启动页无 Theme 角色切换时仍用父母主色，与暖色启动背景一致
            const CocoLoadingIndicator(
              size: 28,
              strokeWidth: 3,
              color: CocoColors.parentPrimary,
            ),
            const SizedBox(height: CocoSpace.s4),
            Text('正在准备…', style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
