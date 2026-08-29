import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// 每日小记配图：直连 BOS 签名 URL。
class DailyNoteImage extends StatelessWidget {
  const DailyNoteImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return Container(
          color: CocoColors.neutral100,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
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
