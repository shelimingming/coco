import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import 'parent_home_palette.dart';

/// 对话字幕气泡：半透明圆角 + 朝下小三角，样式对齐身份选择页介绍气泡。
class ParentCaptionBubble extends StatelessWidget {
  const ParentCaptionBubble({
    super.key,
    required this.palette,
    required this.text,
  });

  final ParentHomePalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    final display = text.trim().isEmpty ? '您可以直接说话' : text.trim();
    final empty = text.trim().isEmpty;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.fromLTRB(
            CocoSpace.s5,
            CocoSpace.s4,
            CocoSpace.s5,
            CocoSpace.s5,
          ),
          decoration: BoxDecoration(
            color: palette.captionBubble,
            borderRadius: BorderRadius.circular(CocoRadius.xl),
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
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: empty ? palette.textMuted : palette.captionText,
              ),
            ),
          ),
        ),
        // 尾巴朝下指向可可，偏右一点更自然
        Positioned(
          right: 72,
          bottom: -8,
          child: CustomPaint(
            size: const Size(18, 10),
            painter: _CaptionBubbleTailPainter(color: palette.captionBubble),
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
      label: visible ? '关闭本次对话文字' : '查看本次对话文字',
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

class _CaptionBubbleTailPainter extends CustomPainter {
  const _CaptionBubbleTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.45, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CaptionBubbleTailPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
