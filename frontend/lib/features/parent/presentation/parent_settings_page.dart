import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/domain/models.dart';

/// 老人端「我的」：身份静态区 + 家庭卡 + 登录与安全（退出低强调 + 二次确认）。
class ParentSettingsPage extends ConsumerWidget {
  const ParentSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final familyAsync = ref.watch(familyInfoProvider);

    return CocoScaffold(
      title: '我的',
      leading: ParentBackButton(onPressed: () => context.pop()),
      leadingWidth: 104,
      bottom: ParentHomeButton(onPressed: () => context.go('/parent')),
      body: familyAsync.when(
        loading: () => const CocoPageLoading(message: '正在加载家庭信息…'),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '家庭信息暂时打不开。您可以再试一次，登录状态没有受影响。',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: CocoColors.neutral700),
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(familyInfoProvider),
            ),
          ],
        ),
        data: (family) => _MyBody(
          displayName: user?.displayName ?? '家人',
          family: family,
          onLogout: () => _confirmLogout(context, ref),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('退出登录？'),
          content: const Text('退出后需要重新验证手机号才能登录。本地已保存的内容不会因此丢失。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: CocoColors.danger),
              child: const Text('退出登录'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && context.mounted) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _MyBody extends StatelessWidget {
  const _MyBody({
    required this.displayName,
    required this.family,
    required this.onLogout,
  });

  final String displayName;
  final FamilyInfo? family;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final bound = family != null && family!.isActive;
    final childName = family?.childDisplayName ?? '家人';
    final initial = displayName.trim().isNotEmpty
        ? String.fromCharCode(displayName.trim().runes.first)
        : '可';

    return ListView(
      children: [
        // 身份区：静态信息，无卡片边框/箭头/点击反馈
        Row(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: CocoColors.parentPrimary,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: CocoColors.white,
                ),
              ),
            ),
            const SizedBox(width: CocoSpace.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: CocoColors.neutral950,
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s1),
                  const Text(
                    '当前登录账号',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: CocoColors.neutral700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: CocoSpace.s8),
        Text(
          bound ? '我的家庭' : '加入家庭',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: CocoColors.neutral950,
          ),
        ),
        const SizedBox(height: CocoSpace.s3),
        _SectionCard(
          iconAsset: 'assets/icons/parent/icon-my-family.svg',
          title: bound ? '$childName的家庭' : '还没有加入家庭',
          subtitle: bound ? '已绑定，可以查看家庭信息' : '把链接发给子女，对方点开登录后确认加入',
          children: bound
              ? [
                  CocoPrimaryButton(
                    label: '查看家庭',
                    onPressed: () => context.push('/parent/family'),
                  ),
                ]
              : [
                  CocoPrimaryButton(
                    label: '邀请子女加入',
                    onPressed: () => context.push('/parent/family'),
                  ),
                ],
        ),
        const SizedBox(height: CocoSpace.s6),
        const Text(
          '登录与安全',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: CocoColors.neutral950,
          ),
        ),
        const SizedBox(height: CocoSpace.s3),
        _SectionCard(
          iconAsset: 'assets/icons/parent/icon-my-security.svg',
          title: '当前已登录',
          subtitle: '退出后，需要重新验证手机号',
          children: [
            const Divider(height: 1, color: CocoColors.neutral300),
            const SizedBox(height: CocoSpace.s4),
            // 低强调危险操作：白底 + danger 描边/字，对比达标
            OutlinedButton(
              onPressed: onLogout,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                foregroundColor: CocoColors.danger,
                side: const BorderSide(color: CocoColors.danger, width: 1.5),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('退出登录'),
            ),
          ],
        ),
        const SizedBox(height: CocoSpace.s8),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.iconAsset,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String iconAsset;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CocoSpace.s6),
      decoration: BoxDecoration(
        color: CocoColors.parentSurface,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        boxShadow: [
          BoxShadow(
            color: CocoColors.neutral950.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SvgPicture.asset(
                iconAsset,
                width: 32,
                height: 32,
                colorFilter: const ColorFilter.mode(
                  CocoColors.parentPrimary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: CocoSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: CocoColors.neutral950,
                      ),
                    ),
                    const SizedBox(height: CocoSpace.s1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.4,
                        color: CocoColors.neutral700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CocoSpace.s6),
          ...children,
        ],
      ),
    );
  }
}
