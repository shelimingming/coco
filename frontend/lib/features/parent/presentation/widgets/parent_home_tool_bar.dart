import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import 'parent_home_palette.dart';

/// 底部三等分工具条：看眼前 / 看手机 / 看照片。
/// 「看照片」为瞬时动作，不保持高亮；投屏中「看手机」保持高亮。
class ParentHomeToolBar extends StatelessWidget {
  const ParentHomeToolBar({
    super.key,
    required this.palette,
    required this.onFrontPressed,
    required this.onPhonePressed,
    required this.onPhotoPressed,
    this.visionToolsEnabled = true,
    this.phoneActive = false,
  });

  final ParentHomePalette palette;
  final VoidCallback onFrontPressed;
  final VoidCallback onPhonePressed;
  final VoidCallback onPhotoPressed;

  /// 分析中为 false：禁用看眼前 / 看照片（投屏中看手机仍可点以停止）。
  final bool visionToolsEnabled;

  /// 投屏会话进行中：看手机高亮。
  final bool phoneActive;

  /// 工具条高度，供首页计算可可可摆放区域
  static const double barHeight = 93;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.toolbarFill,
        borderRadius: BorderRadius.circular(27),
        boxShadow: [
          BoxShadow(
            color: CocoColors.neutral950.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        height: barHeight,
        child: Row(
          children: [
            Expanded(
              child: _ToolItem(
                label: '看眼前',
                assetPath: 'assets/icons/parent/icon-tool-camera-day.png',
                active: false,
                palette: palette,
                onPressed: visionToolsEnabled ? onFrontPressed : null,
              ),
            ),
            _ToolbarDivider(color: palette.toolbarDivider),
            Expanded(
              child: _ToolItem(
                label: '看手机',
                assetPath: 'assets/icons/parent/icon-tool-phone-day.png',
                active: phoneActive,
                palette: palette,
                // 投屏中仍可点以停止；其它视觉分析中禁用
                onPressed: (visionToolsEnabled || phoneActive)
                    ? onPhonePressed
                    : null,
              ),
            ),
            _ToolbarDivider(color: palette.toolbarDivider),
            Expanded(
              child: _ToolItem(
                label: '看照片',
                assetPath: 'assets/icons/parent/icon-tool-photo-day.png',
                active: false,
                palette: palette,
                onPressed: visionToolsEnabled ? onPhotoPressed : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 1, height: 64, child: ColoredBox(color: color));
  }
}

class _ToolItem extends StatelessWidget {
  const _ToolItem({
    required this.label,
    required this.assetPath,
    required this.active,
    required this.palette,
    required this.onPressed,
  });

  final String label;
  final String assetPath;
  final bool active;
  final ParentHomePalette palette;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final iconColor = active ? palette.toolActiveIcon : palette.toolIdleIcon;
    final textColor = active ? CocoColors.white : palette.text;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              // 热区至少 56×56；整格可点更易点中
              height: ParentHomeToolBar.barHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 看手机持续工作时：图标+文字同块橙底变白，不改三等分尺寸
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: active ? palette.toolActiveFill : null,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: active ? 16 : 0,
                        vertical: active ? 8 : 0,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            assetPath,
                            width: 27,
                            height: 27,
                            color: iconColor,
                            excludeFromSemantics: true,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
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
