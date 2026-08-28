import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../domain/voice_call_transcript.dart';
import 'parent_home_palette.dart';

/// 首页原地识图区：照片常驻 + 状态条关闭；「字」开时只叠当前一轮。
class ParentHomeLookPanel extends StatelessWidget {
  const ParentHomeLookPanel({
    super.key,
    required this.palette,
    required this.imageBytes,
    required this.showScanBrackets,
    required this.statusLabel,
    required this.showCaption,
    this.captionEntries = const [],
    this.errorMessage,
    this.onClose,
  });

  final ParentHomePalette palette;
  final Uint8List imageBytes;
  final bool showScanBrackets;
  final String statusLabel;
  final bool showCaption;
  final List<VoiceCallTranscriptEntry> captionEntries;
  final String? errorMessage;
  final VoidCallback? onClose;

  static const double _photoMinHeight = 220;
  static const double _cornerLen = 18;
  static const double _cornerStroke = 3;
  static const double _cornerInset = 10;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final photoMaxHeight = (constraints.maxHeight * 0.78).clamp(
          _photoMinHeight,
          520.0,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LookingStatusBar(
              label: statusLabel,
              palette: palette,
              onClose: onClose,
            ),
            const SizedBox(height: CocoSpace.s3),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: _photoMinHeight,
                    maxHeight: photoMaxHeight,
                  ),
                  child: _PhotoFrame(
                    imageBytes: imageBytes,
                    palette: palette,
                    showScanBrackets: showScanBrackets,
                    showCaption: showCaption,
                    captionEntries: captionEntries,
                  ),
                ),
              ),
            ),
            if (errorMessage != null && errorMessage!.trim().isNotEmpty) ...[
              const SizedBox(height: CocoSpace.s3),
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
          ],
        );
      },
    );
  }
}

class _LookingStatusBar extends StatelessWidget {
  const _LookingStatusBar({
    required this.label,
    required this.palette,
    this.onClose,
  });

  final String label;
  final ParentHomePalette palette;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CocoRadius.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            CocoSpace.s3,
            CocoSpace.s2,
            CocoSpace.s2,
            CocoSpace.s2,
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
              if (onClose != null)
                Semantics(
                  button: true,
                  label: '关闭照片，继续说话',
                  child: Material(
                    color: CocoColors.parentPrimarySoft,
                    borderRadius: BorderRadius.circular(CocoRadius.lg),
                    child: InkWell(
                      onTap: onClose,
                      borderRadius: BorderRadius.circular(CocoRadius.lg),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: CocoSpace.s4,
                          vertical: CocoSpace.s3,
                        ),
                        child: Text(
                          '关闭',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: CocoColors.parentPrimary,
                          ),
                        ),
                      ),
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
  const _PhotoFrame({
    required this.imageBytes,
    required this.palette,
    required this.showScanBrackets,
    required this.showCaption,
    required this.captionEntries,
  });

  final Uint8List imageBytes;
  final ParentHomePalette palette;
  final bool showScanBrackets;
  final bool showCaption;
  final List<VoiceCallTranscriptEntry> captionEntries;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
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
          if (showScanBrackets)
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
          if (showCaption && captionEntries.isNotEmpty)
            Positioned(
              left: CocoSpace.s3,
              right: CocoSpace.s3,
              bottom: CocoSpace.s3,
              child: _CurrentRoundCaption(
                palette: palette,
                entries: captionEntries,
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrentRoundCaption extends StatelessWidget {
  const _CurrentRoundCaption({
    required this.palette,
    required this.entries,
  });

  final ParentHomePalette palette;
  final List<VoiceCallTranscriptEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 160),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CocoColors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(CocoRadius.lg),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            CocoSpace.s4,
            CocoSpace.s3,
            CocoSpace.s4,
            CocoSpace.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const SizedBox(height: CocoSpace.s2),
                Text(
                  entries[i].isUser ? '您' : '可可',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: palette.textMuted,
                  ),
                ),
                Text(
                  entries[i].text,
                  style: TextStyle(
                    fontSize: 20,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: palette.captionText,
                  ),
                ),
              ],
            ],
          ),
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
