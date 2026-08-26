import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../web/presentation_slot.dart';
import 'coco_safe_area.dart';

/// Web 桌面用的 iPhone 外框：按真机逻辑分辨率等比缩放，避免拉高后底部大块留白。
class WebIphoneShell extends StatelessWidget {
  const WebIphoneShell({super.key, required this.child});

  final Widget child;

  /// 短于此宽度视为手机视口。手机开「桌面版网站」时 UA 会伪装成电脑，用尺寸再挡一层。
  static const double desktopShortestSide = 600;

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

  /// 仅电脑浏览器用外壳对照真机比例；手机 / 平板 Web 铺满真实屏幕。
  /// 双端演示页 iframe 往往窄于 [desktopShortestSide]，仍要套框。
  static bool enabledOf(BuildContext context) {
    return useShellFor(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      viewportSize: MediaQuery.sizeOf(context),
      inPresentationSlot: readPresentationSlot() != null,
    );
  }

  /// 抽出判定方便单测：原生 App、手机 UA、窄视口都不套框。
  /// [inPresentationSlot] 为演示页 iframe：不受视口和 UA 限制，始终套框。
  @visibleForTesting
  static bool useShellFor({
    required bool isWeb,
    required TargetPlatform platform,
    required Size viewportSize,
    bool inPresentationSlot = false,
  }) {
    if (!isWeb) return false;
    // 演示页左右两栏 iframe 接近真机宽，不能当成「手机浏览器铺满」
    if (inPresentationSlot) return true;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.android) {
      return false;
    }
    return viewportSize.shortestSide >= desktopShortestSide;
  }

  @override
  Widget build(BuildContext context) {
    // 演示页桌面底与 presentation.html --bg 同色，iframe 四周不露出另一块底色
    final deskBg = readPresentationSlot() != null
        ? CocoColors.neutral100
        : Theme.of(context).scaffoldBackgroundColor;

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
