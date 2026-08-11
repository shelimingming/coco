import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import 'parent_home_palette.dart';

/// 对话字幕气泡：小头像固定尺寸，长文只撑文字区滚动。
class ParentCaptionBubble extends StatelessWidget {
  const ParentCaptionBubble({
    super.key,
    required this.palette,
    required this.text,
  });

  final ParentHomePalette palette;
  final String text;

  static const double _avatarSize = 56;

  @override
  Widget build(BuildContext context) {
    final display = text.trim().isEmpty ? '您可以直接说话' : text.trim();
    final empty = text.trim().isEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(
          child: Image.asset(
            'assets/images/parent/home/coco_chat_avatar.png',
            width: _avatarSize,
            height: _avatarSize,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: CocoSpace.s3),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.symmetric(
              horizontal: CocoSpace.s5,
              vertical: CocoSpace.s4,
            ),
            decoration: BoxDecoration(
              color: palette.captionBubble,
              borderRadius: BorderRadius.circular(CocoRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: CocoColors.neutral950.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Text(
                display,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: empty ? palette.textMuted : palette.captionText,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 右上角「字」开关：代码绘制，避免 SVG 内嵌墨绿底。
class ParentCaptionToggle extends StatelessWidget {
  const ParentCaptionToggle({
    super.key,
    required this.palette,
    required this.visible,
    required this.onPressed,
  });

  final ParentHomePalette palette;
  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: visible ? '隐藏对话文字' : '显示对话文字',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        child: Container(
          width: 44,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: visible ? palette.captionToggleOn : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.captionToggleOffBorder, width: 2),
          ),
          child: Text(
            '字',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1,
              color: visible ? CocoColors.white : palette.link,
            ),
          ),
        ),
      ),
    );
  }
}
