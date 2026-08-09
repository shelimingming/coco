import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';

/// 子女端设置：常规列表布局，退出登录需二次确认。
class ChildSettingsPage extends ConsumerWidget {
  const ChildSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);

    return CocoScaffold(
      title: '设置',
      body: ListView(
        children: [
          Text('账号', style: theme.textTheme.titleMedium),
          const SizedBox(height: CocoSpace.s3),
          Card(
            child: ListTile(
              title: Text(user?.displayName ?? '家人'),
              subtitle: const Text('当前登录昵称'),
            ),
          ),
          const SizedBox(height: CocoSpace.s8),
          Text('其他', style: theme.textTheme.titleMedium),
          const SizedBox(height: CocoSpace.s3),
          Card(
            child: ListTile(
              title: Text(
                '退出登录',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: CocoColors.danger,
                ),
              ),
              subtitle: Text(
                '退出后需重新验证手机号',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
              trailing: Icon(Icons.logout, color: CocoColors.danger),
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
