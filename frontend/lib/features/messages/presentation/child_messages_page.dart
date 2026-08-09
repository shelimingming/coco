import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../care/application/care_providers.dart';
import '../application/messages_providers.dart';
import '../domain/models.dart';

/// 子女端留言 Tab：已发报平安列表，主入口进入撰写页。
class ChildMessagesPage extends ConsumerWidget {
  const ChildMessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final messagesAsync = ref.watch(familyMessagesProvider);

    return CocoScaffold(
      title: '留言',
      body: messagesAsync.when(
        loading: () => const _MessagesSkeleton(),
        error: (error, _) {
          if (isFamilyNotFound(error)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '这里是你发给父母的报平安，不是聊天室。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: CocoColors.neutral700,
                  ),
                ),
                const SizedBox(height: CocoSpace.s4),
                Text('请先加入家庭，才能给父母报平安。', style: theme.textTheme.bodyLarge),
                const Spacer(),
                CocoPrimaryButton(
                  label: '去加入家庭',
                  onPressed: () => context.push('/child/join'),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                error is ApiException
                    ? error.message
                    : '留言加载失败。您可以再试一次，数据没有丢失。',
                style: theme.textTheme.bodyLarge,
              ),
              const Spacer(),
              CocoPrimaryButton(
                label: '再试一次',
                onPressed: () => ref.invalidate(familyMessagesProvider),
              ),
            ],
          );
        },
        data: (messages) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(familyMessagesProvider),
          child: messages.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Text(
                      '这里是你发给父母的报平安，不是聊天室。',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: CocoColors.neutral700,
                      ),
                    ),
                    const SizedBox(height: CocoSpace.s2),
                    Text(
                      '报平安会转成父母好听懂的话，发送前可预览。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: CocoColors.neutral700,
                      ),
                    ),
                    const SizedBox(height: CocoSpace.s10),
                    CocoPrimaryButton(
                      label: '报个平安',
                      onPressed: () => context.push('/child/messages/compose'),
                    ),
                  ],
                )
              : ListView(
                  children: [
                    Text(
                      '这里是你发给父母的报平安，不是聊天室。',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: CocoColors.neutral700,
                      ),
                    ),
                    const SizedBox(height: CocoSpace.s4),
                    CocoPrimaryButton(
                      label: '报个平安',
                      onPressed: () => context.push('/child/messages/compose'),
                    ),
                    const SizedBox(height: CocoSpace.s5),
                    ...messages.map(
                      (message) => Padding(
                        padding: const EdgeInsets.only(bottom: CocoSpace.s3),
                        child: _MessageCard(message: message),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final FamilyMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = _formatTime(message.createdAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('你', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  time,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: CocoColors.neutral500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CocoSpace.s2),
            Text(message.deliveredText, style: theme.textTheme.bodyLarge),
            if (message.originalText != message.deliveredText) ...[
              const SizedBox(height: CocoSpace.s2),
              Text(
                '原文：${message.originalText}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$mm-$dd $hh:$min';
  }
}

class _MessagesSkeleton extends StatelessWidget {
  const _MessagesSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        _SkeletonBox(height: 48),
        SizedBox(height: CocoSpace.s4),
        _SkeletonBox(height: 52),
        SizedBox(height: CocoSpace.s5),
        _SkeletonBox(height: 88),
        SizedBox(height: CocoSpace.s3),
        _SkeletonBox(height: 88),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: CocoColors.neutral100,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        border: Border.all(color: CocoColors.childBorder),
      ),
    );
  }
}
