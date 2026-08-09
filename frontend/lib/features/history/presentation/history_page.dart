import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/history_providers.dart';
import '../domain/models.dart';

/// 父母端聊天历史列表（会话级，非实时通话页）。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(conversationListProvider);

    return CocoScaffold(
      title: '历史记录',
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error is ApiException
                  ? error.message
                  : '历史记录加载失败。您可以再试一次，数据没有丢失。',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(conversationListProvider),
            ),
          ],
        ),
        data: (items) {
          if (items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('还没有聊天记录', style: theme.textTheme.titleLarge),
                const SizedBox(height: CocoSpace.s3),
                Text(
                  '和可可说过话之后，可以在这里回看。只有您自己能看见，不会自动告诉家人。',
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
            onRefresh: () async => ref.invalidate(conversationListProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: CocoSpace.s3),
              itemBuilder: (context, index) {
                final item = items[index];
                return _HistoryCard(
                  summary: item,
                  onTap: () => context.push('/parent/history/${item.id}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.summary, required this.onTap});

  final ConversationSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: CocoColors.neutral100,
      borderRadius: BorderRadius.circular(CocoRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(CocoSpace.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatWhen(summary.startedAt),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: CocoColors.neutral700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: CocoSpace.s2),
              // 优先展示结束通话时生成的短标题，便于老人扫一眼认出
              Text(
                summary.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral950,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_shouldShowPreview(summary)) ...[
                const SizedBox(height: CocoSpace.s2),
                Text(
                  summary.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: CocoColors.neutral700,
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

bool _shouldShowPreview(ConversationSummary summary) {
  final title = summary.title?.trim() ?? '';
  final preview = summary.preview.trim();
  if (title.isEmpty || preview.isEmpty) return false;
  return title != preview;
}

String _formatWhen(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (sameDay) {
    return '今天 $hh:$mm';
  }
  return '${local.month}月${local.day}日 $hh:$mm';
}
