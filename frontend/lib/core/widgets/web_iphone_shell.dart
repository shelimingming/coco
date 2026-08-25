import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'coco_safe_area.dart';

/// Web 桌面用的 iPhone 外框：按真机逻辑分辨率等比缩放，避免拉高后底部大块留白。
class WebIphoneShell extends StatelessWidget {
  const WebIphoneShell({super.key, required this.child});

  final Widget child;

  /// iPhone 15 / 16 Pro 逻辑点尺寸（宽 × 高），与模拟器一致。
  static const Size screenSize = Size(393, 852);

  /// 对齐真机刘海 / Home Indicator；页面 [CocoSafeArea] 在 MediaQuery 被盖掉时仍用此值。
  static const double topInset = 59;
  static const double bottomInset = 34;

  static const Key islandKey = ValueKey<String>('webIphoneIsland');

  static const double _bezel = 10;
  static const double _frameRadius = 55;
  static const double _screenRadius = 47;

  /// 含边框的整机尺寸（393+20 × 852+20）。
  static const Size deviceSize = Size(413, 872);

  @override
  Widget build(BuildContext context) {
    final deskBg = Theme.of(context).scaffoldBackgroundColor;

    return ColoredBox(
      color: deskBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CocoSpace.s4,
            vertical: CocoSpace.s4,
          ),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: deviceSize.width,
              height: deviceSize.height,
              child: _DeviceFrame(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceFrame extends StatelessWidget {
  const _DeviceFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CocoColors.neutral950,
        borderRadius: BorderRadius.circular(WebIphoneShell._frameRadius),
        boxShadow: [
          const BoxShadow(
            color: CocoColors.onboardingShadow,
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
          BoxShadow(
            color: CocoColors.neutral950.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: CocoColors.neutral700, width: 1.2),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    WebIphoneShell._frameRadius,
                  ),
                  border: Border.all(
                    color: CocoColors.white.withValues(alpha: 0.18),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: WebIphoneShell._bezel,
            top: WebIphoneShell._bezel,
            width: WebIphoneShell.screenSize.width,
            height: WebIphoneShell.screenSize.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WebIphoneShell._screenRadius),
              child: MediaQuery(
                data: _screenMediaQuery(context),
                // 保底 inset 走 InheritedWidget，不依赖各页读到的 MediaQuery.padding
                child: CocoSafeInsets(
                  minimum: const EdgeInsets.only(
                    top: WebIphoneShell.topInset,
                    bottom: WebIphoneShell.bottomInset,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
          // Dynamic Island：接近真机视觉占比
          Positioned(
            top: WebIphoneShell._bezel + 11,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: WebIphoneShell.islandKey,
                  width: 126,
                  height: 37,
                  decoration: BoxDecoration(
                    color: CocoColors.neutral950,
                    borderRadius: BorderRadius.circular(CocoRadius.pill),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: WebIphoneShell._bezel + 8,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 134,
                  height: 5,
                  decoration: BoxDecoration(
                    color: CocoColors.neutral950.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(CocoRadius.pill),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 固定为真机逻辑尺寸与安全区，首页 Expanded 不会被桌面视口拉高。
  MediaQueryData _screenMediaQuery(BuildContext context) {
    final base = MediaQuery.of(context);
    return base.copyWith(
      size: WebIphoneShell.screenSize,
      padding: const EdgeInsets.only(
        top: WebIphoneShell.topInset,
        bottom: WebIphoneShell.bottomInset,
      ),
      viewPadding: const EdgeInsets.only(
        top: WebIphoneShell.topInset,
        bottom: WebIphoneShell.bottomInset,
      ),
      viewInsets: EdgeInsets.zero,
      devicePixelRatio: 3,
    );
  }
}
