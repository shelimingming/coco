import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/daily_notes_providers.dart';
import 'daily_note_image.dart';

/// 父母端每日小记详情：正文 + 配图。
class DailyNoteDetailPage extends ConsumerWidget {
  const DailyNoteDetailPage({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(dailyNoteDetailProvider(noteId));

    return CocoScaffold(
      title: '小记详情',
      leading: ParentBackButton(onPressed: () => context.pop()),
      leadingWidth: 104,
      bottom: ParentHomeButton(onPressed: () => context.go('/parent')),
      body: async.when(
        loading: () => const CocoPageLoading(),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error is ApiException
                  ? error.message
                  : '小记加载失败。您可以再试一次，数据没有丢失。',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(dailyNoteDetailProvider(noteId)),
            ),
          ],
        ),
        data: (note) {
          final dateLabel =
              '${note.noteDate.year}年${note.noteDate.month}月${note.noteDate.day}日';
          return ListView(
            children: [
              Text(dateLabel, style: theme.textTheme.titleLarge),
              const SizedBox(height: CocoSpace.s4),
              Container(
                padding: const EdgeInsets.all(CocoSpace.s4),
                decoration: BoxDecoration(
                  color: CocoColors.parentPrimarySoft.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(CocoRadius.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in note.items) ...[
                      Text(
                        line,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                      ),
                      const SizedBox(height: CocoSpace.s2),
                    ],
                    if (note.items.isEmpty && note.bodyText.isNotEmpty)
                      Text(
                        note.bodyText,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                      ),
                    const SizedBox(height: CocoSpace.s2),
                    Text(
                      '可可根据今天的交流整理',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: CocoColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              if (note.images.isNotEmpty) ...[
                const SizedBox(height: CocoSpace.s5),
                for (final image in note.images) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(CocoRadius.lg),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DailyNoteImage(urlPath: image.urlPath),
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s3),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}
