import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import 'parent_home_palette.dart';

/// 首页开场白气泡：半透明圆角 + 朝下三角，样式对齐身份选择介绍气泡。
class ParentGreetingBubble extends StatelessWidget {
  const ParentGreetingBubble({
    super.key,
    required this.palette,
    required this.title,
    required this.subtitle,
  });

  final ParentHomePalette palette;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '$title。$subtitle',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 340),
            width: double.infinity,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: palette.captionText,
                  ),
                ),
                const SizedBox(height: CocoSpace.s2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // 尾巴朝下指向可可，偏右一点更自然
          Positioned(
            right: 72,
            bottom: -8,
            child: CustomPaint(
              size: const Size(18, 10),
              painter: _GreetingBubbleTailPainter(color: palette.captionBubble),
            ),
          ),
        ],
      ),
    );
  }
}

class _GreetingBubbleTailPainter extends CustomPainter {
  const _GreetingBubbleTailPainter({required this.color});

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
  bool shouldRepaint(covariant _GreetingBubbleTailPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
