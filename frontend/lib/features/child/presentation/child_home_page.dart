import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../../care/application/care_providers.dart';
import '../../care/domain/models.dart';

/// 子女端今日状态：接真实 API，未绑定则引导加入家庭。
class ChildHomePage extends ConsumerWidget {
  const ChildHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);
    final todayAsync = ref.watch(childTodayProvider);

    return CocoScaffold(
      title: '今日状态',
      actions: [
        IconButton(
          tooltip: '报平安',
          onPressed: () => context.push('/child/messages'),
          icon: const Icon(Icons.favorite_outline),
        ),
        IconButton(
          tooltip: '设置',
          onPressed: () => context.push('/child/settings'),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      body: todayAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (isFamilyNotFound(error)) {
            return _JoinFamilyGuide(
              name: user?.displayName ?? '家人',
              // 加入成功后若仍残留未绑定错误，下拉可重新拉取
              onRefresh: () => ref.refresh(childTodayProvider.future),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                error is ApiException
                    ? error.message
                    : '今日状态加载失败。您可以再试一次，数据没有丢失。',
                style: theme.textTheme.bodyLarge,
              ),
              const Spacer(),
              CocoPrimaryButton(
                label: '再试一次',
                onPressed: () => ref.invalidate(childTodayProvider),
              ),
            ],
          );
        },
        data: (today) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(childTodayProvider),
          child: ListView(
            children: [
              Text(
                '你好，${user?.displayName ?? '家人'}',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: CocoSpace.s2),
              Text(
                '打开 App，先看父母今天是否安稳。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
              const SizedBox(height: CocoSpace.s6),
              _StatusCard(today: today),
              const SizedBox(height: CocoSpace.s4),
              _AttentionCard(items: today.attentionItems),
              const SizedBox(height: CocoSpace.s4),
              _ReminderStatusCard(items: today.reminderItems),
              const SizedBox(height: CocoSpace.s6),
              Card(
                color: CocoColors.childPrimarySoft,
                child: InkWell(
                  onTap: () => context.push('/child/messages'),
                  borderRadius: BorderRadius.circular(CocoRadius.lg),
                  child: Padding(
                    padding: const EdgeInsets.all(CocoSpace.s5),
                    child: Row(
                      children: [
                        Icon(
                          Icons.favorite,
                          color: CocoColors.childAccent,
                          size: 28,
                        ),
                        const SizedBox(width: CocoSpace.s3),
                        Expanded(
                          child: Text(
                            '发条报平安',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: CocoColors.neutral950,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinFamilyGuide extends StatelessWidget {
  const _JoinFamilyGuide({required this.name, required this.onRefresh});

  final String name;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('你好，$name', style: theme.textTheme.titleLarge),
          const SizedBox(height: CocoSpace.s3),
          Text(
            '还没有绑定父母。请向父母索取邀请码，完成绑定后这里会显示今日状态。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const SizedBox(height: CocoSpace.s10),
          CocoPrimaryButton(
            label: '输入邀请码加入',
            onPressed: () => context.push('/child/join'),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.today});

  final ChildToday today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color soft;
    switch (today.status) {
      case ChildTodayStatus.needContact:
        soft = Color.alphaBlend(
          CocoColors.warning.withValues(alpha: 0.18),
          CocoColors.white,
        );
      case ChildTodayStatus.attention:
        soft = CocoColors.childPrimarySoft;
      case ChildTodayStatus.normal:
        soft = CocoColors.white;
    }

    return Card(
      color: soft,
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(today.headline, style: theme.textTheme.titleMedium),
            if (today.needsContactReason != null) ...[
              const SizedBox(height: CocoSpace.s2),
              Text(
                today.needsContactReason!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.items});

  final List<CareShare> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('需要关注', style: theme.textTheme.titleMedium),
            const SizedBox(height: CocoSpace.s2),
            if (items.isEmpty)
              Text(
                '暂无待处理事项。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              )
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: CocoSpace.s3),
                  child: Text(item.summary, style: theme.textTheme.bodyLarge),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReminderStatusCard extends StatelessWidget {
  const _ReminderStatusCard({required this.items});

  final List<ChildTodayReminderItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('提醒状态', style: theme.textTheme.titleMedium),
            const SizedBox(height: CocoSpace.s2),
            if (items.isEmpty)
              Text(
                '今天没有需要关注的提醒。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              )
            else
              ...items.map((item) {
                // 措辞严格：只描述未确认，不说「没有吃药」
                final label = item.state == 'ESCALATED'
                    ? '经过两次提醒后仍未确认'
                    : '暂未确认';
                return Padding(
                  padding: const EdgeInsets.only(bottom: CocoSpace.s2),
                  child: Text(
                    '「${item.title}」$label',
                    style: theme.textTheme.bodyLarge,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
