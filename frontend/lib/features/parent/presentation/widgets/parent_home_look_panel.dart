import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import 'parent_home_palette.dart';

/// 首页原地识图区：照片框 +「可可正在看」临时条；结论改由语音「字」展示。
class ParentHomeLookPanel extends StatelessWidget {
  const ParentHomeLookPanel({
    super.key,
    required this.palette,
    required this.imageBytes,
    required this.analyzing,
    required this.showCaption,
    required this.captionText,
    this.errorMessage,
    this.statusHint,
  });

  final ParentHomePalette palette;
  final Uint8List imageBytes;
  final bool analyzing;
  final bool showCaption;
  final String captionText;
  final String? errorMessage;

  /// 如「照片正在上传」；分析中默认用「可可正在看」。
  final String? statusHint;

  static const double _photoMinHeight = 220;
  static const double _cornerLen = 18;
  static const double _cornerStroke = 3;
  static const double _cornerInset = 10;

  @override
  Widget build(BuildContext context) {
    final lookingLabel = statusHint ?? (analyzing ? '可可正在看' : null);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: CocoSpace.s2, bottom: CocoSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (lookingLabel != null) ...[
            _LookingStatusBar(label: lookingLabel, palette: palette),
            const SizedBox(height: CocoSpace.s4),
          ],
          _PhotoFrame(imageBytes: imageBytes, palette: palette),
          if (errorMessage != null && errorMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: CocoSpace.s4),
            Container(
              padding: const EdgeInsets.all(CocoSpace.s4),
              decoration: BoxDecoration(
                color: CocoColors.parentSurface,
                borderRadius: BorderRadius.circular(CocoRadius.lg),
                border: Border.all(
                  color: CocoColors.danger.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                errorMessage!,
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: CocoColors.neutral950,
                ),
              ),
            ),
          ],
          // 结论跟语音「字」开关，识图面板不再叠结论气泡
          if (showCaption && captionText.trim().isNotEmpty) ...[
            const SizedBox(height: CocoSpace.s4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                CocoSpace.s5,
                CocoSpace.s4,
                CocoSpace.s5,
                CocoSpace.s4,
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
              child: Text(
                captionText.trim(),
                style: TextStyle(
                  fontSize: 22,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: palette.captionText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LookingStatusBar extends StatelessWidget {
  const _LookingStatusBar({required this.label, required this.palette});

  final String label;
  final ParentHomePalette palette;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CocoRadius.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CocoSpace.s3,
            vertical: CocoSpace.s3,
          ),
          decoration: BoxDecoration(
            color: CocoColors.parentSurface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(CocoRadius.xl),
          ),
          child: Row(
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/images/parent/home/coco_looking_avatar.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(width: CocoSpace.s3),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({required this.imageBytes, required this.palette});

  final Uint8List imageBytes;
  final ParentHomePalette palette;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ParentHomeLookPanel._photoMinHeight,
      ),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CocoRadius.lg),
                border: Border.all(color: palette.link, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: palette.link.withValues(alpha: 0.25),
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CocoRadius.lg - 1),
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
            // 四角括号：分析中与完成后共用
            Positioned.fill(
              child: CustomPaint(
                painter: _CornerBracketsPainter(
                  color: CocoColors.white,
                  length: ParentHomeLookPanel._cornerLen,
                  stroke: ParentHomeLookPanel._cornerStroke,
                  inset: ParentHomeLookPanel._cornerInset,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerBracketsPainter extends CustomPainter {
  const _CornerBracketsPainter({
    required this.color,
    required this.length,
    required this.stroke,
    required this.inset,
  });

  final Color color;
  final double length;
  final double stroke;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * length, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * length), paint);
    }

    corner(inset, inset, 1, 1);
    corner(size.width - inset, inset, -1, 1);
    corner(inset, size.height - inset, 1, -1);
    corner(size.width - inset, size.height - inset, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.length != length ||
        oldDelegate.stroke != stroke ||
        oldDelegate.inset != inset;
  }
}
