import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/daily_notes_providers.dart';
import '../data/daily_notes_api.dart';
import '../domain/models.dart';
import 'daily_note_image.dart';

/// 父母端每日小记：右上角进设置；列表为主，「立即生成」固定在底栏。
class DailyNotesPage extends ConsumerStatefulWidget {
  const DailyNotesPage({super.key});

  @override
  ConsumerState<DailyNotesPage> createState() => _DailyNotesPageState();
}

class _DailyNotesPageState extends ConsumerState<DailyNotesPage> {
  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listAsync = ref.watch(dailyNotesListProvider);

    return CocoScaffold(
      title: '每日小记',
      leading: ParentBackButton(onPressed: () => context.pop()),
      leadingWidth: 104,
      // 设置收进右上角，避免挤占列表首屏
      actions: [
        TextButton(
          onPressed: () => context.push('/parent/daily-notes/settings'),
          style: TextButton.styleFrom(
            foregroundColor: CocoColors.parentPrimary,
            textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            minimumSize: const Size(48, 48),
          ),
          child: const Text('设置'),
        ),
      ],
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CocoPrimaryButton(
            label: '立即生成',
            loading: _generating,
            loadingLabel: '正在生成…',
            onPressed: _onGenerate,
          ),
          const SizedBox(height: CocoSpace.s3),
          ParentHomeButton(onPressed: () => context.go('/parent')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dailyNotesListProvider);
        },
        child: ListView(
          children: [
            Text('往日小记', style: theme.textTheme.titleLarge),
            const SizedBox(height: CocoSpace.s3),
            listAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: CocoSpace.s6),
                child: CocoPageLoading(),
              ),
              error: (error, _) => Text(
                error is ApiException
                    ? error.message
                    : '列表加载失败。您可以下拉重试，数据没有丢失。',
                style: theme.textTheme.bodyLarge,
              ),
              data: (items) {
                final ready = items.where((e) => e.isReady).toList();
                if (ready.isEmpty) {
                  return Text(
                    '还没有生成过小记。晚上 20:00 会自动整理，也可以点下方「立即生成」。',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: CocoColors.neutral700,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final note in ready) ...[
                      _NoteListTile(
                        note: note,
                        onTap: () =>
                            context.push('/parent/daily-notes/${note.id}'),
                      ),
                      const SizedBox(height: CocoSpace.s3),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onGenerate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final note = await ref.read(dailyNotesApiProvider).generate();
      ref.invalidate(dailyNotesListProvider);
      if (!mounted) return;
      if (note.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('今天聊到的日常还不够，暂时没有生成小记。')),
        );
      } else if (note.isReady) {
        context.push('/parent/daily-notes/${note.id}');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({required this.note, required this.onTap});

  final DailyNote note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel =
        '${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}-${note.noteDate.day.toString().padLeft(2, '0')}';
    final preview = note.items.isNotEmpty
        ? note.items.first
        : (note.bodyText.isNotEmpty ? note.bodyText : '（无正文）');

    return Material(
      color: CocoColors.white,
      borderRadius: BorderRadius.circular(CocoRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(CocoSpace.s4),
          child: Row(
            children: [
              if (note.images.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(CocoRadius.md),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: DailyNoteImage(url: note.images.first.url),
                  ),
                )
              else
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: CocoColors.parentPrimarySoft,
                    borderRadius: BorderRadius.circular(CocoRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '记',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: CocoColors.parentPrimary,
                    ),
                  ),
                ),
              const SizedBox(width: CocoSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateLabel, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: CocoColors.neutral700,
                      ),
                    ),
                    if (note.sharedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '已发给家人',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: CocoColors.parentPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: CocoColors.neutral500),
            ],
          ),
        ),
      ),
    );
  }
}
