import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/reminders_providers.dart';
import '../data/reminders_api.dart';
import '../domain/models.dart';

/// 父母端今日提醒列表（DESIGN 9.3 E03）。
class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(remindersListProvider);

    return CocoScaffold(
      title: '今天',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: CocoSpace.s3),
          child: Center(
            child: ParentChipButton(
              label: '新建',
              onPressed: () => context.push('/parent/reminders/new'),
            ),
          ),
        ),
      ],
      body: async.when(
        loading: () => const CocoPageLoading(),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error is ApiException
                  ? error.message
                  : '提醒列表加载失败。您可以再试一次，数据没有丢失。',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(remindersListProvider),
            ),
          ],
        ),
        data: (items) {
          if (items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('今天还没有提醒', style: theme.textTheme.titleLarge),
                const SizedBox(height: CocoSpace.s3),
                Text(
                  '可以点「和我说话」让可可帮您记，也可以在这里手动新建。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: CocoColors.neutral700,
                  ),
                ),
                const Spacer(),
                CocoPrimaryButton(
                  label: '新建提醒',
                  onPressed: () => context.push('/parent/reminders/new'),
                ),
                const SizedBox(height: CocoSpace.s3),
                CocoSecondaryButton(
                  label: '回去找可可说话',
                  onPressed: () => context.go('/parent'),
                ),
              ],
            );
          }

          final active = items.where((r) => r.isActive).toList();
          final done = items.where((r) => !r.isActive).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(remindersListProvider),
            child: ListView(
              children: [
                if (active.isNotEmpty) ...[
                  Text('待办', style: theme.textTheme.titleMedium),
                  const SizedBox(height: CocoSpace.s3),
                  ...active.map(
                    (r) => _ReminderCard(
                      reminder: r,
                      onDelete: () => _delete(context, ref, r),
                    ),
                  ),
                ],
                if (done.isNotEmpty) ...[
                  const SizedBox(height: CocoSpace.s6),
                  Text('已结束', style: theme.textTheme.titleMedium),
                  const SizedBox(height: CocoSpace.s3),
                  ...done.map(
                    (r) => _ReminderCard(
                      reminder: r,
                      onDelete: () => _delete(context, ref, r),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Reminder reminder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除这个提醒？'),
          content: Text('将删除「${reminder.title}」。删除后不可恢复，但不会影响其他提醒。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: CocoColors.danger),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(remindersApiProvider).delete(reminder.id);
      ref.invalidate(remindersListProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : '删除失败。您可以再试一次，其他提醒没有受影响。',
          ),
        ),
      );
    }
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder, required this.onDelete});

  final Reminder reminder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: CocoSpace.s3),
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reminder.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: CocoSpace.s2),
            Text(
              '${reminder.isDaily ? '每天' : '一次'} ${reminder.timeLabel}',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: CocoColors.neutral700,
              ),
            ),
            const SizedBox(height: CocoSpace.s4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: CocoColors.danger),
                child: const Text('删除'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
