import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../care/application/care_providers.dart';
import '../../care/domain/models.dart';
import '../../family/application/family_providers.dart';
import '../../family/presentation/call_parent_phone.dart';

/// 子女端近况：需要关注 + 今日信息同步，顶部铺交付稿背景。
class ChildHomePage extends ConsumerWidget {
  const ChildHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);
    final todayAsync = ref.watch(childTodayProvider);
    final familyAsync = ref.watch(familyInfoProvider);
    final parentName = familyAsync.valueOrNull?.parentDisplayName ?? '父母';

    return Scaffold(
      backgroundColor: CocoColors.childBackground,
      body: todayAsync.when(
        loading: () => const _TodaySkeleton(),
        error: (error, _) {
          if (isFamilyNotFound(error)) {
            return _JoinFamilyGuide(
              name: user?.displayName ?? '家人',
              onRefresh: () => ref.refresh(childTodayProvider.future),
            );
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(CocoSpace.s5),
              child: Column(
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
              ),
            ),
          );
        },
        data: (today) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(childTodayProvider);
            ref.invalidate(familyInfoProvider);
            await ref.read(childTodayProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _StatusHeader(parentName: parentName)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  CocoSpace.s4,
                  CocoSpace.s2,
                  CocoSpace.s4,
                  CocoSpace.s8,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _AttentionBlock(
                      today: today,
                      parentUserId: familyAsync.valueOrNull?.parentUserId,
                      parentName: parentName,
                    ),
                    const SizedBox(height: CocoSpace.s5),
                    _SyncBlock(items: today.reminderItems),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.parentName});

  final String parentName;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    // 顶部背景 cover，不横向压缩；可可在素材里，不与卡片同层
    return SizedBox(
      height: top + 168,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/child/status_header_bg.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            excludeFromSemantics: true,
          ),
          Positioned(
            left: CocoSpace.s5,
            top: top + CocoSpace.s4,
            right: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '近况',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: 28,
                    color: CocoColors.neutral950,
                  ),
                ),
                const SizedBox(height: CocoSpace.s1),
                Text(
                  '$parentName · 今天',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CocoColors.neutral700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionBlock extends StatelessWidget {
  const _AttentionBlock({
    required this.today,
    required this.parentUserId,
    required this.parentName,
  });

  final ChildToday today;
  final String? parentUserId;
  final String parentName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = today.attentionItems;
    final count = items.isEmpty && today.status == ChildTodayStatus.needContact
        ? 1
        : items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('需要关注', style: theme.textTheme.titleMedium),
            if (count > 0) ...[
              const SizedBox(width: CocoSpace.s2),
              // 数量角标用 warning 浅底，避免监控感大红数字
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CocoSpace.s2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    CocoColors.warning.withValues(alpha: 0.16),
                    CocoColors.white,
                  ),
                  borderRadius: BorderRadius.circular(CocoRadius.pill),
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: CocoColors.warning,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/child/attention'),
              style: TextButton.styleFrom(
                foregroundColor: CocoColors.childPrimary,
                padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('查看全部'),
            ),
          ],
        ),
        const SizedBox(height: CocoSpace.s3),
        if (items.isEmpty && today.status != ChildTodayStatus.needContact)
          _EmptyAttentionCard()
        else if (items.isEmpty)
          _AttentionCard(
            tag: '需要联系',
            title: today.headline.isNotEmpty ? today.headline : '建议联系确认',
            summary: today.needsContactReason ?? '可可建议及时联系确认长辈状况。',
            updatedAt: DateTime.now(),
            showActions: true,
            parentUserId: parentUserId,
            parentName: parentName,
          )
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: CocoSpace.s3),
              child: _AttentionCard(
                tag: _tagFor(item),
                title: _titleFor(item, today),
                summary: item.summary,
                updatedAt: item.createdAt,
                showActions: true,
                parentUserId: parentUserId,
                parentName: parentName,
              ),
            ),
          ),
      ],
    );
  }

  String _tagFor(CareShare item) {
    switch (item.urgency.toUpperCase()) {
      case 'HIGH':
      case 'URGENT':
        return '身体近况';
      default:
        return '关怀摘要';
    }
  }

  String _titleFor(CareShare item, ChildToday today) {
    if (today.headline.isNotEmpty && today.status != ChildTodayStatus.normal) {
      return today.headline;
    }
    final text = item.summary.trim();
    if (text.length <= 12) return text;
    final cut = text.indexOf(RegExp(r'[，。；！？]'));
    if (cut > 0 && cut <= 16) return text.substring(0, cut);
    return '${text.substring(0, 12)}…';
  }
}

class _EmptyAttentionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CocoSpace.s5),
      decoration: BoxDecoration(
        color: CocoColors.childSurface,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
        border: Border.all(color: CocoColors.childBorder),
      ),
      child: Text(
        '今天没有需要你处理的事。',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: CocoColors.neutral700,
        ),
      ),
    );
  }
}

class _AttentionCard extends ConsumerWidget {
  const _AttentionCard({
    required this.tag,
    required this.title,
    required this.summary,
    required this.updatedAt,
    required this.showActions,
    required this.parentUserId,
    required this.parentName,
  });

  final String tag;
  final String title;
  final String summary;
  final DateTime updatedAt;
  final bool showActions;
  final String? parentUserId;
  final String parentName;

  Future<void> _openWeChat(BuildContext context) async {
    final uri = Uri.parse('weixin://');
    final ok = await canLaunchUrl(uri) && await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未能打开微信。请确认已安装微信后重试。')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final soft = Color.alphaBlend(
      CocoColors.warning.withValues(alpha: 0.12),
      CocoColors.white,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CocoSpace.s5),
      decoration: BoxDecoration(
        color: CocoColors.childSurface,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
        border: Border.all(color: CocoColors.childBorder),
        boxShadow: [
          BoxShadow(
            color: CocoColors.neutral950.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CocoSpace.s3,
              vertical: CocoSpace.s1,
            ),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(CocoRadius.pill),
            ),
            child: Text(
              '● $tag',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: CocoColors.warning,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: CocoSpace.s3),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: CocoSpace.s2),
          Text(
            summary,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: CocoSpace.s3),
          Text(
            _formatUpdated(updatedAt),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: CocoColors.neutral500,
              fontSize: 13,
            ),
          ),
          if (showActions) ...[
            const SizedBox(height: CocoSpace.s4),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: '打电话',
                    iconAsset: 'assets/icons/child/icon-action-phone.svg',
                    filled: true,
                    // 短按拨打；长按可改本地保存的号码
                    onPressed: () => callParentPhone(
                      context,
                      ref,
                      parentUserId: parentUserId,
                      parentName: parentName,
                    ),
                    onLongPress: () => callParentPhone(
                      context,
                      ref,
                      parentUserId: parentUserId,
                      parentName: parentName,
                      forceEdit: true,
                    ),
                  ),
                ),
                const SizedBox(width: CocoSpace.s3),
                Expanded(
                  child: _ActionButton(
                    label: '微信',
                    iconAsset: 'assets/icons/child/icon-action-wechat.svg',
                    filled: false,
                    onPressed: () => _openWeChat(context),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatUpdated(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    if (sameDay) return '今天 $hh:$min 更新';
    return '${local.month}/${local.day} $hh:$min 更新';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.iconAsset,
    required this.filled,
    required this.onPressed,
    this.onLongPress,
  });

  final String label;
  final String iconAsset;
  final bool filled;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? CocoColors.childPrimary : CocoColors.childSurface;
    final fg = filled ? CocoColors.white : CocoColors.childPrimary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(CocoRadius.md),
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CocoRadius.md),
            border: filled ? null : Border.all(color: CocoColors.childPrimary),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                iconAsset,
                width: 18,
                height: 18,
                colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
              ),
              const SizedBox(width: CocoSpace.s2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncBlock extends StatelessWidget {
  const _SyncBlock({required this.items});

  final List<ChildTodayReminderItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('今日信息同步', style: theme.textTheme.titleMedium),
        const SizedBox(height: CocoSpace.s3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CocoSpace.s5),
          decoration: BoxDecoration(
            color: CocoColors.childPrimarySoft,
            borderRadius: BorderRadius.circular(CocoRadius.lg),
          ),
          child: items.isEmpty
              ? Row(
                  children: [
                    SvgPicture.asset(
                      'assets/icons/child/icon-calendar.svg',
                      width: 22,
                      height: 22,
                      colorFilter: const ColorFilter.mode(
                        CocoColors.childPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: CocoSpace.s3),
                    Expanded(
                      child: Text(
                        '暂无需要关注的提醒',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: CocoColors.neutral700,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((item) {
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
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _TodaySkeleton extends StatelessWidget {
  const _TodaySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(CocoSpace.s5),
      children: const [
        _SkeletonBox(height: 160),
        SizedBox(height: CocoSpace.s5),
        _SkeletonBox(height: 28, width: 120),
        SizedBox(height: CocoSpace.s3),
        _SkeletonBox(height: 180),
        SizedBox(height: CocoSpace.s5),
        _SkeletonBox(height: 28, width: 140),
        SizedBox(height: CocoSpace.s3),
        _SkeletonBox(height: 72),
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
        padding: const EdgeInsets.all(CocoSpace.s5),
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top),
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
