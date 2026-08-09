import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../care/application/care_providers.dart';
import '../../care/domain/models.dart';

/// 关怀摘要详情：查看全部历史（含已读），未读可点「知道了」。
class ChildAttentionPage extends ConsumerWidget {
  const ChildAttentionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sharesAsync = ref.watch(careSharesProvider);

    return CocoScaffold(
      title: '需要关注',
      body: sharesAsync.when(
        loading: () => const CocoPageLoading(),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error is ApiException ? error.message : '加载失败。您可以再试一次，数据没有丢失。',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(careSharesProvider),
            ),
          ],
        ),
        data: (shares) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(careSharesProvider),
          child: shares.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Text(
                      '还没有家人分享需要关注的内容。',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: CocoColors.neutral700,
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: shares.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CocoSpace.s3),
                  itemBuilder: (context, index) {
                    final item = shares[index];
                    return _AttentionDetailCard(item: item);
                  },
                ),
        ),
      ),
    );
  }
}

class _AttentionDetailCard extends ConsumerStatefulWidget {
  const _AttentionDetailCard({required this.item});

  final CareShare item;

  @override
  ConsumerState<_AttentionDetailCard> createState() =>
      _AttentionDetailCardState();
}

class _AttentionDetailCardState extends ConsumerState<_AttentionDetailCard> {
  bool _marking = false;

  Future<void> _markRead() async {
    if (_marking || widget.item.readAt != null) {
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
    final item = widget.item;
    final unread = item.readAt == null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: unread ? CocoColors.childPrimarySoft : CocoColors.childSurface,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        border: Border.all(color: CocoColors.childBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  unread ? '未读' : '已读',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: unread
                        ? CocoColors.childPrimary
                        : CocoColors.neutral500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(item.createdAt),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: CocoColors.neutral500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CocoSpace.s2),
            Text(item.summary, style: theme.textTheme.bodyLarge),
            if (unread) ...[
              const SizedBox(height: CocoSpace.s3),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _marking ? null : _markRead,
                  child: Text(_marking ? '请稍候…' : '知道了'),
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
