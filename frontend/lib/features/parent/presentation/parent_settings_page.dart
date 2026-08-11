import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/domain/models.dart';

/// 老人端设置：按是否已绑定家庭切换文案与入口，退出需二次确认。
class ParentSettingsPage extends ConsumerWidget {
  const ParentSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final familyAsync = ref.watch(familyInfoProvider);
    final theme = Theme.of(context);

    return CocoScaffold(
      title: '设置',
      body: familyAsync.when(
        loading: () => const CocoPageLoading(message: '正在加载家庭信息…'),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '家庭信息暂时打不开。您可以再试一次，登录状态没有受影响。',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: CocoColors.neutral700,
              ),
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(familyInfoProvider),
            ),
            const SizedBox(height: CocoSpace.s4),
            CocoSecondaryButton(label: '返回', onPressed: () => context.pop()),
          ],
        ),
        data: (family) => _SettingsBody(
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

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.displayName,
    required this.family,
    required this.onLogout,
  });

  final String displayName;
  final FamilyInfo? family;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bound = family != null && family!.isActive;
    final childName = family?.childDisplayName ?? '家人';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(displayName, style: theme.textTheme.titleLarge),
        const SizedBox(height: CocoSpace.s2),
        Text(
          bound
              ? '已与「$childName」绑定家庭。可以查看家庭信息，或管理登录状态。退出后需要重新验证手机号。'
              : '这里可以邀请子女、用邀请码加入家庭、管理登录状态。退出后需要重新验证手机号。',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: CocoColors.neutral700,
          ),
        ),
        const SizedBox(height: CocoSpace.s6),
        if (bound) ...[
          CocoPrimaryButton(
            label: '查看家庭',
            onPressed: () => context.push('/parent/family'),
          ),
        ] else ...[
          CocoPrimaryButton(
            label: '邀请子女加入',
            onPressed: () => context.push('/parent/family'),
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(
            label: '输入邀请码加入',
            onPressed: () => context.push('/parent/join'),
          ),
        ],
        const Spacer(),
        // 危险操作：大点击区 + 确认，避免误触
        FilledButton(
          onPressed: onLogout,
          style: FilledButton.styleFrom(
            backgroundColor: CocoColors.danger,
            foregroundColor: CocoColors.white,
          ),
          child: const Text('退出登录'),
        ),
        const SizedBox(height: CocoSpace.s4),
        CocoSecondaryButton(label: '返回', onPressed: () => context.pop()),
      ],
    );
  }
}
