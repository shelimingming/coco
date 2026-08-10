import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../../care/application/care_providers.dart';
import '../../care/domain/models.dart';

/// 子女端近况：结论优先，回答「今天要不要管」。
class ChildHomePage extends ConsumerWidget {
  const ChildHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);
    final todayAsync = ref.watch(childTodayProvider);

    return CocoScaffold(
      title: '近况',
      body: todayAsync.when(
        loading: () => const _TodaySkeleton(),
        error: (error, _) {
          if (isFamilyNotFound(error)) {
            return _JoinFamilyGuide(
              name: user?.displayName ?? '家人',
              onRefresh: () => ref.refresh(childTodayProvider.future),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                error is ApiException
                    ? error.message
                    : '近况加载失败。您可以再试一次，数据没有丢失。',
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
              const SizedBox(height: CocoSpace.s6),
              _StatusSection(today: today),
              const SizedBox(height: CocoSpace.s4),
              _AttentionSection(items: today.attentionItems),
              const SizedBox(height: CocoSpace.s4),
              _ReminderSection(items: today.reminderItems),
              // NORMAL 时轻量次入口，主入口在「留言」Tab
              if (today.status == ChildTodayStatus.normal) ...[
                const SizedBox(height: CocoSpace.s8),
                TextButton(
                  onPressed: () => context.push('/child/messages/compose'),
                  child: Text(
                    '给父母报个平安',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: CocoColors.childPrimary,
                    ),
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

class _TodaySkeleton extends StatelessWidget {
  const _TodaySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _SkeletonBox(height: 28, width: 160),
        const SizedBox(height: CocoSpace.s6),
        const _SkeletonBox(height: 96),
        const SizedBox(height: CocoSpace.s4),
        const _SkeletonBox(height: 120),
        const SizedBox(height: CocoSpace.s4),
        const _SkeletonBox(height: 100),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: CocoColors.neutral100,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        border: Border.all(color: CocoColors.childBorder),
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
            '还没有绑定父母。您可以输入父母的邀请码，或自己生成邀请码请父母加入。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const SizedBox(height: CocoSpace.s10),
          CocoPrimaryButton(
            label: '输入邀请码加入',
            onPressed: () => context.push('/child/join'),
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(
            label: '生成邀请码邀请父母',
            onPressed: () => context.push('/child/family/invite'),
          ),
        ],
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({required this.today});

  final ChildToday today;

  Future<void> _openPhoneApp() async {
    // 无通讯录号码时只打开系统电话，不预填、不自动拨号
    final uri = Uri(scheme: 'tel');
    await launchUrl(uri);
  }

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            if (today.status == ChildTodayStatus.needContact) ...[
              const SizedBox(height: CocoSpace.s4),
              CocoPrimaryButton(label: '打开电话 App', onPressed: _openPhoneApp),
              const SizedBox(height: CocoSpace.s2),
              Text(
                '建议电话联系一下。系统不会自动拨号。',
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
}

class _AttentionSection extends ConsumerWidget {
  const _AttentionSection({required this.items});

  final List<CareShare> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      color: CocoColors.childSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CocoRadius.md),
        side: const BorderSide(color: CocoColors.childBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('需要关注', style: theme.textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => context.push('/child/attention'),
                  style: TextButton.styleFrom(
                    foregroundColor: CocoColors.childPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: CocoSpace.s2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('查看全部'),
                ),
              ],
            ),
            const SizedBox(height: CocoSpace.s3),
            if (items.isEmpty)
              Text(
                '今天没有需要你处理的事。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              )
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: CocoSpace.s3),
                  child: _AttentionItem(item: item),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttentionItem extends ConsumerStatefulWidget {
  const _AttentionItem({required this.item});

  final CareShare item;

  @override
  ConsumerState<_AttentionItem> createState() => _AttentionItemState();
}

class _AttentionItemState extends ConsumerState<_AttentionItem> {
  bool _marking = false;

  Future<void> _markRead() async {
    if (_marking) {
      return;
    }
    setState(() => _marking = true);
    try {
      await markCareShareRead(ref, widget.item.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is ApiException
          ? error.message
          : '标记失败。您可以再试一次，数据没有丢失。';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _marking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CocoColors.childPrimarySoft,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        border: Border.all(color: CocoColors.childBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.item.summary, style: theme.textTheme.bodyLarge),
            const SizedBox(height: CocoSpace.s2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _marking ? null : _markRead,
                style: TextButton.styleFrom(
                  foregroundColor: CocoColors.childPrimary,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(_marking ? '请稍候…' : '知道了'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderSection extends StatelessWidget {
  const _ReminderSection({required this.items});

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
            Text('提醒概况', style: theme.textTheme.titleMedium),
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
