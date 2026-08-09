import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/memories_providers.dart';
import '../data/memories_api.dart';
import '../domain/models.dart';

/// 父母端「我记住的事」（DESIGN 9.6 E06）。
class MemoriesPage extends ConsumerWidget {
  const MemoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(memoriesListProvider);

    return CocoScaffold(
      title: '我记住的事',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: CocoSpace.s3),
          child: Center(
            child: ParentChipButton(
              label: '返回',
              onPressed: () => context.pop(),
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
                  : '记忆列表加载失败。您可以再试一次，数据没有丢失。',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(memoriesListProvider),
            ),
          ],
        ),
        data: (items) {
          if (items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('还没有记住的事', style: theme.textTheme.titleLarge),
                const SizedBox(height: CocoSpace.s3),
                Text(
                  '和可可聊天时，如果有值得记住的事，可可会问您要不要记住。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: CocoColors.neutral700,
                  ),
                ),
                const Spacer(),
                CocoSecondaryButton(
                  label: '回去找可可说话',
                  onPressed: () => context.go('/parent'),
                ),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(memoriesListProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: CocoSpace.s3),
              itemBuilder: (context, index) {
                final memory = items[index];
                return _MemoryCard(
                  memory: memory,
                  onDelete: () => _delete(context, ref, memory),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Memory memory,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除这条记忆？'),
          content: const Text(
            '删除后，可可以后聊天时就不会再用到这件事。'
            '您可以以后再通过聊天重新告诉可可。',
          ),
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
      await ref.read(memoriesApiProvider).delete(memory.id);
      ref.invalidate(memoriesListProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : '删除失败。您可以再试一次，其他记忆没有受影响。',
          ),
        ),
      );
    }
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.memory, required this.onDelete});

  final Memory memory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CocoSpace.s3,
                vertical: CocoSpace.s1,
              ),
              decoration: BoxDecoration(
                color: CocoColors.parentPrimarySoft,
                borderRadius: BorderRadius.circular(CocoRadius.pill),
              ),
              child: Text(
                memory.categoryLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: CocoSpace.s3),
            Text(memory.content, style: theme.textTheme.bodyLarge),
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
