import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../application/daily_notes_providers.dart';

/// 带鉴权的每日小记配图（经 Dio 拉 BYTEA）。
class DailyNoteImage extends ConsumerWidget {
  const DailyNoteImage({super.key, required this.urlPath});

  final String urlPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dailyNoteImageBytesProvider(urlPath));
    return async.when(
      loading: () => Container(
        color: CocoColors.neutral100,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => Container(
        color: CocoColors.neutral100,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: CocoColors.neutral500),
      ),
      data: (bytes) {
        if (bytes.isEmpty) {
          return Container(color: CocoColors.neutral100);
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}
