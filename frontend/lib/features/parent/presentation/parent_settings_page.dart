import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';

/// 老人端设置：账号相关操作，退出需二次确认。
class ParentSettingsPage extends ConsumerWidget {
  const ParentSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);

    return CocoScaffold(
      title: '设置',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(user?.displayName ?? '家人', style: theme.textTheme.titleLarge),
          const SizedBox(height: CocoSpace.s2),
          Text(
            '这里可以管理登录状态。退出后需要重新验证手机号。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const Spacer(),
          // 危险操作：大点击区 + 确认，避免误触
          FilledButton(
            onPressed: () => _confirmLogout(context, ref),
            style: FilledButton.styleFrom(
              backgroundColor: CocoColors.danger,
              foregroundColor: CocoColors.white,
            ),
            child: const Text('退出登录'),
          ),
          const SizedBox(height: CocoSpace.s4),
          CocoSecondaryButton(label: '返回', onPressed: () => context.pop()),
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
