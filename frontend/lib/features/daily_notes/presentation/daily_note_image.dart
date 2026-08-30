import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_loading.dart';

/// 每日小记配图：直连 BOS 签名 URL；加载中呼吸占位，避免大图空白。
class DailyNoteImage extends StatefulWidget {
  const DailyNoteImage({super.key, required this.url});

  final String url;

  @override
  State<DailyNoteImage> createState() => _DailyNoteImageState();
}

class _DailyNoteImageState extends State<DailyNoteImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        final total = progress.expectedTotalBytes;
        final loaded = progress.cumulativeBytesLoaded;
        final ratio = (total != null && total > 0)
            ? (loaded / total).clamp(0.0, 1.0)
            : null;
        return _LoadingPlaceholder(pulse: _pulse, progress: ratio);
      },
      errorBuilder: (_, _, _) => Container(
        color: CocoColors.neutral100,
        alignment: Alignment.center,
        child: const Icon(
          Icons.broken_image_outlined,
          color: CocoColors.neutral500,
        ),
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({required this.pulse, this.progress});

  final Animation<double> pulse;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final t = pulse.value;
        final soft = Color.lerp(
          CocoColors.neutral100,
          primary.withValues(alpha: 0.12),
          t,
        )!;
        return Container(
          color: soft,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CocoLoadingIndicator(size: 28, strokeWidth: 3, color: primary),
              const SizedBox(height: CocoSpace.s3),
              Text(
                progress == null
                    ? '图片加载中…'
                    : '图片加载中 ${((progress ?? 0) * 100).round()}%',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: CocoColors.neutral700.withValues(
                    alpha: 0.85 + 0.15 * t,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
