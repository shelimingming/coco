import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../auth/application/auth_controller.dart';
import '../application/family_providers.dart';

/// 子女端家庭 Tab：绑定关系、授权说明、账号与退出。
class ChildFamilyPage extends ConsumerWidget {
  const ChildFamilyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);
    final familyAsync = ref.watch(familyInfoProvider);
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: CocoColors.childBackground,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          CocoSpace.s5,
          top + CocoSpace.s4,
          CocoSpace.s5,
          CocoSpace.s8,
        ),
        children: [
          Text(
            '家庭',
            style: theme.textTheme.displayLarge?.copyWith(fontSize: 28),
          ),
          const SizedBox(height: CocoSpace.s2),
          Text(
            '管理家庭关系与共享范围',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const SizedBox(height: CocoSpace.s6),
          familyAsync.when(
            loading: () => const _CardShell(
              child: Padding(
                padding: EdgeInsets.all(CocoSpace.s5),
                child: LinearProgressIndicator(),
              ),
            ),
            error: (error, _) => _CardShell(
              child: Padding(
                padding: const EdgeInsets.all(CocoSpace.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      error is ApiException
                          ? error.message
                          : '家庭信息加载失败。您可以再试一次，数据没有丢失。',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: CocoSpace.s3),
                    CocoSecondaryButton(
                      label: '再试一次',
                      onPressed: () => ref.invalidate(familyInfoProvider),
                    ),
                  ],
                ),
              ),
            ),
            data: (family) {
              if (family == null || !family.isActive) {
                return _CardShell(
                  child: Padding(
                    padding: const EdgeInsets.all(CocoSpace.s5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('还没有绑定父母。', style: theme.textTheme.titleMedium),
                        const SizedBox(height: CocoSpace.s2),
                        Text(
                          '您可以生成邀请码请父母加入，或输入父母给您的邀请码。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: CocoColors.neutral700,
                          ),
                        ),
                        const SizedBox(height: CocoSpace.s4),
                        CocoPrimaryButton(
                          label: '生成邀请码邀请父母',
                          onPressed: () => context.push('/child/family/invite'),
                        ),
                        const SizedBox(height: CocoSpace.s3),
                        CocoSecondaryButton(
                          label: '输入邀请码加入',
                          onPressed: () => context.push('/child/join'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final parentName = family.parentDisplayName ?? '父母';
              return _BoundParentCard(parentName: parentName);
            },
          ),
          const SizedBox(height: CocoSpace.s6),
          Text('我的账号', style: theme.textTheme.titleMedium),
          const SizedBox(height: CocoSpace.s3),
          _CardShell(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: CocoSpace.s4,
                vertical: CocoSpace.s1,
              ),
              leading: SvgPicture.asset(
                'assets/icons/child/icon-user.svg',
                width: 22,
                height: 22,
                colorFilter: const ColorFilter.mode(
                  CocoColors.childPrimary,
                  BlendMode.srcIn,
                ),
              ),
              title: Text(
                user?.displayName ?? '家人',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '当前登录昵称',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: CocoColors.neutral500,
                ),
              ),
            ),
          ),
          const SizedBox(height: CocoSpace.s6),
          Text('其他', style: theme.textTheme.titleMedium),
          const SizedBox(height: CocoSpace.s3),
          _CardShell(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: CocoSpace.s4,
                vertical: CocoSpace.s1,
              ),
              leading: SvgPicture.asset(
                'assets/icons/child/icon-logout.svg',
                width: 22,
                height: 22,
                colorFilter: const ColorFilter.mode(
                  CocoColors.danger,
                  BlendMode.srcIn,
                ),
              ),
              title: Text(
                '退出登录',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: CocoColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: CocoColors.danger.withValues(alpha: 0.7),
              ),
              onTap: () => _confirmLogout(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('退出登录？'),
          content: const Text('将退出当前账号并返回登录页。本地已保存的内容不会因此丢失。'),
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

class _BoundParentCard extends StatelessWidget {
  const _BoundParentCard({required this.parentName});

  final String parentName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: CocoColors.childPrimarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    parentName.isNotEmpty ? parentName.substring(0, 1) : '亲',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: CocoColors.childPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: CocoSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(parentName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '长辈',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: CocoColors.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CocoSpace.s3,
                    vertical: CocoSpace.s1,
                  ),
                  decoration: BoxDecoration(
                    color: CocoColors.childPrimarySoft,
                    borderRadius: BorderRadius.circular(CocoRadius.pill),
                  ),
                  child: Text(
                    '● 已绑定',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: CocoColors.success,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: CocoSpace.s4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CocoSpace.s4),
              decoration: BoxDecoration(
                color: CocoColors.childBackground,
                borderRadius: BorderRadius.circular(CocoRadius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvgPicture.asset(
                    'assets/icons/child/icon-shield.svg',
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(
                      CocoColors.childPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: CocoSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '由长辈决定分享范围',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: CocoSpace.s1),
                        Text(
                          '仅展示长辈授权后的摘要，看不到完整聊天，保护彼此隐私。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: CocoColors.neutral700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
