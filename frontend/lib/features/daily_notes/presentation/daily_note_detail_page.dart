import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/daily_notes_providers.dart';
import 'daily_note_diary_body.dart';

/// 父母端每日小记详情：撕边贴图纸手账；pending 时轮询直到完成。
class DailyNoteDetailPage extends ConsumerStatefulWidget {
  const DailyNoteDetailPage({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<DailyNoteDetailPage> createState() =>
      _DailyNoteDetailPageState();
}

class _DailyNoteDetailPageState extends ConsumerState<DailyNoteDetailPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // 后台生成中：每 2 秒拉一次详情
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _maybePoll());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _maybePoll() {
    final async = ref.read(dailyNoteDetailProvider(widget.noteId));
    final note = async.valueOrNull;
    if (note == null || note.isPending) {
      ref.invalidate(dailyNoteDetailProvider(widget.noteId));
      return;
    }
    _poll?.cancel();
    _poll = null;
    ref.invalidate(dailyNotesListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(dailyNoteDetailProvider(widget.noteId));

    return async.when(
      loading: () => CocoScaffold(
        title: '今日小记',
        leading: ParentBackButton(onPressed: () => context.pop()),
        leadingWidth: 104,
        bottom: ParentHomeButton(onPressed: () => context.go('/parent')),
        body: const CocoPageLoading(),
      ),
      error: (error, _) => CocoScaffold(
        title: '今日小记',
        leading: ParentBackButton(onPressed: () => context.pop()),
        leadingWidth: 104,
        bottom: ParentHomeButton(onPressed: () => context.go('/parent')),
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
              onPressed: () =>
                  ref.invalidate(dailyNoteDetailProvider(widget.noteId)),
            ),
          ],
        ),
      ),
      data: (note) {
        if (note.isPending) {
          return CocoScaffold(
            title: '今日小记',
            leading: ParentBackButton(onPressed: () => context.pop()),
            leadingWidth: 104,
            bottom: ParentHomeButton(onPressed: () => context.go('/parent')),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CocoPageLoading(),
                const SizedBox(height: CocoSpace.s4),
                Text(
                  '正在整理今天的日记，请稍候…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: CocoColors.neutral700,
                  ),
                ),
              ],
            ),
          );
        }
        if (note.isFailed) {
          return CocoScaffold(
            title: '今日小记',
            leading: ParentBackButton(onPressed: () => context.pop()),
            leadingWidth: 104,
            bottom: ParentHomeButton(onPressed: () => context.go('/parent')),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '刚才没能整理成日记。请稍后再试，已有小记没有被改丢。',
                  style: theme.textTheme.bodyLarge,
                ),
                const Spacer(),
                CocoPrimaryButton(
                  label: '返回列表再生成',
                  onPressed: () => context.go('/parent/daily-notes'),
                ),
              ],
            ),
          );
        }
        return CocoScaffold(
          title: '今日小记',
          leading: ParentBackButton(onPressed: () => context.pop()),
          leadingWidth: 104,
          bottom: ParentHomeButton(onPressed: () => context.go('/parent')),
          padding: const EdgeInsets.symmetric(vertical: CocoSpace.s3),
          body: ListView(
            children: [
              DailyNoteDiaryBody(
                note: note,
                tone: DailyNoteDiaryTone.parent,
                fallbackTitle: '可可的今日小记',
                onTalkToCoco: () => context.go('/parent'),
              ),
            ],
          ),
        );
      },
    );
  }
}
