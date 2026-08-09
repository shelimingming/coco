import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/history_providers.dart';
import '../domain/models.dart';

/// 单次通话详情：对话原文 + 工具白话说明。
class HistoryDetailPage extends ConsumerWidget {
  const HistoryDetailPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(conversationDetailProvider(conversationId));

    final pageTitle = async.maybeWhen(
      data: (detail) {
        final t = detail.title?.trim();
        return (t != null && t.isNotEmpty) ? t : '这次聊天';
      },
      orElse: () => '这次聊天',
    );

    return CocoScaffold(
      title: pageTitle,
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
                  : '这段聊天加载失败。您可以再试一次，数据没有丢失。',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () =>
                  ref.invalidate(conversationDetailProvider(conversationId)),
            ),
          ],
        ),
        data: (detail) {
          if (detail.items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('这次还没有记下说话内容', style: theme.textTheme.titleLarge),
                const SizedBox(height: CocoSpace.s3),
                Text(
                  '可能通话很快结束了，或者当时网络不太好。您可以再和可可说说话。',
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

          return ListView.separated(
            itemCount: detail.items.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: CocoSpace.s3),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Text(
                  _formatHeader(detail.startedAt),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: CocoColors.neutral700,
                  ),
                );
              }
              return _TimelineItem(item: detail.items[index - 1]);
            },
          );
        },
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.item});

  final ConversationItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (item.isTool) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CocoSpace.s4),
        decoration: BoxDecoration(
          color: CocoColors.neutral100,
          borderRadius: BorderRadius.circular(CocoRadius.md),
        ),
        child: Text(
          item.displaySummary?.trim().isNotEmpty == true
              ? item.displaySummary!
              : '可可帮你办了一件事',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: CocoColors.neutral700,
          ),
        ),
      );
    }

    final isUser = item.isUser;
    final label = isUser ? '您' : '可可';
    final background = isUser
        ? CocoColors.parentPrimarySoft
        : Color.alphaBlend(
            CocoColors.parentSecondary.withValues(alpha: 0.14),
            CocoColors.neutral100,
          );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          padding: const EdgeInsets.all(CocoSpace.s4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(CocoRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: CocoColors.neutral700,
                ),
              ),
              const SizedBox(height: CocoSpace.s2),
              Text(
                (item.text ?? '').trim().isEmpty ? '（没有文字）' : item.text!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral950,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatHeader(DateTime value) {
  final local = value.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.year}年${local.month}月${local.day}日 $hh:$mm';
}
