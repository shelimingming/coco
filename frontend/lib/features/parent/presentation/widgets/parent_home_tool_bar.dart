import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/tokens.dart';
import 'parent_home_palette.dart';

/// 底部四工具：说话 / 看眼前 / 看手机 / 看照片。
/// 「看照片」为瞬时动作，不保持高亮；投屏中「看手机」保持高亮。
class ParentHomeToolBar extends StatelessWidget {
  const ParentHomeToolBar({
    super.key,
    required this.palette,
    required this.inCall,
    required this.onTalkPressed,
    required this.onFrontPressed,
    required this.onPhonePressed,
    required this.onPhotoPressed,
    this.visionToolsEnabled = true,
    this.phoneActive = false,
  });

  final ParentHomePalette palette;
  final bool inCall;
  final VoidCallback onTalkPressed;
  final VoidCallback onFrontPressed;
  final VoidCallback onPhonePressed;
  final VoidCallback onPhotoPressed;

  /// 分析中为 false：禁用看眼前 / 看照片（投屏中看手机仍可点以停止）。
  final bool visionToolsEnabled;

  /// 投屏会话进行中：看手机高亮。
  final bool phoneActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CocoSpace.s2,
        CocoSpace.s2,
        CocoSpace.s2,
        CocoSpace.s2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolItem(
            label: inCall ? '对话中' : '说话',
            assetPath: inCall
                ? 'assets/icons/parent/icon-mic.svg'
                : 'assets/icons/parent/icon-tool-talk-day.svg',
            active: inCall,
            palette: palette,
            onPressed: onTalkPressed,
          ),
          _ToolItem(
            label: '看眼前',
            assetPath: 'assets/icons/parent/icon-tool-camera-day.svg',
            active: false,
            palette: palette,
            onPressed: visionToolsEnabled ? onFrontPressed : null,
          ),
          _ToolItem(
            label: '看手机',
            assetPath: 'assets/icons/parent/icon-tool-phone-day.svg',
            active: phoneActive,
            palette: palette,
            // 投屏中仍可点以停止；其它视觉分析中禁用
            onPressed: (visionToolsEnabled || phoneActive)
                ? onPhonePressed
                : null,
          ),
          _ToolItem(
            label: '看照片',
            assetPath: 'assets/icons/parent/icon-tool-photo-day.svg',
            active: false,
            palette: palette,
            onPressed: visionToolsEnabled ? onPhotoPressed : null,
          ),
        ],
      ),
    );
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
    final fill = active ? palette.toolActiveFill : palette.toolIdleFill;
    final iconColor = active ? palette.toolActiveIcon : palette.toolIdleIcon;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            enabled: enabled,
            label: label,
            child: Material(
              color: fill,
              shape: const CircleBorder(),
              elevation: active ? 0 : 1,
              shadowColor: CocoColors.neutral950.withValues(alpha: 0.12),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: SizedBox(
                  // 直径 64 ≥ DESIGN 老人端热区 56
                  width: 64,
                  height: 64,
                  child: Center(
                    child: SvgPicture.asset(
                      assetPath,
                      width: 28,
                      height: 28,
                      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: CocoSpace.s2),
          Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}
