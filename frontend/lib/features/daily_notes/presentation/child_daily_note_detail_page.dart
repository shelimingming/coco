import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../family/application/family_providers.dart';
import '../application/daily_notes_providers.dart';
import 'daily_note_diary_body.dart';

/// 子女端：今日小记完整图文（撕边贴图纸，从近况摘要点入）。
class ChildDailyNoteDetailPage extends ConsumerWidget {
  const ChildDailyNoteDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(childDailyNoteTodayProvider);
    final parentName =
        ref.watch(familyInfoProvider).valueOrNull?.parentDisplayName ?? '家人';

    return async.when(
      loading: () => CocoScaffold(
        title: '今日小记',
        leading: BackButton(onPressed: () => context.pop()),
        body: const CocoPageLoading(),
      ),
      error: (error, _) => CocoScaffold(
        title: '今日小记',
        leading: BackButton(onPressed: () => context.pop()),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error is ApiException ? error.message : '小记加载失败。您可以再试一次，数据没有丢失。',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(childDailyNoteTodayProvider),
            ),
          ],
        ),
      ),
      data: (note) {
        if (note == null || !note.isReady) {
          return CocoScaffold(
            title: '今日小记',
            leading: BackButton(onPressed: () => context.pop()),
            body: Text('今天还没有可看的小记。', style: theme.textTheme.bodyLarge),
          );
        }
        return CocoScaffold(
          title: '今日小记',
          leading: BackButton(onPressed: () => context.pop()),
          padding: const EdgeInsets.symmetric(vertical: CocoSpace.s3),
          body: ListView(
            children: [
              DailyNoteDiaryBody(
                note: note,
                tone: DailyNoteDiaryTone.child,
                fallbackTitle: '$parentName的今日小记',
              ),
            ],
          ),
        );
      },
    );
  }
}
