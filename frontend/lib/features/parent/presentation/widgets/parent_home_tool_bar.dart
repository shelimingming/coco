import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/tokens.dart';
import 'parent_home_palette.dart';

/// 底部两工具：说话 / 看一看。
class ParentHomeToolBar extends StatelessWidget {
  const ParentHomeToolBar({
    super.key,
    required this.palette,
    required this.inCall,
    required this.onTalkPressed,
    required this.onLookPressed,
    this.lookEnabled = true,
  });

  final ParentHomePalette palette;
  final bool inCall;
  final VoidCallback onTalkPressed;
  final VoidCallback onLookPressed;
  final bool lookEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CocoSpace.s4,
        CocoSpace.s2,
        CocoSpace.s4,
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
            label: '看一看',
            assetPath: 'assets/icons/parent/icon-tool-camera-day.svg',
            active: false,
            palette: palette,
            onPressed: lookEnabled ? onLookPressed : null,
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
                  width: 64,
                  height: 64,
                  child: Center(
                    child: SvgPicture.asset(
                      assetPath,
                      width: 30,
                      height: 30,
                      // 暖橙染色：交付 SVG 原色多为墨绿，首页统一滤成父母主色
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
              fontSize: 22,
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
