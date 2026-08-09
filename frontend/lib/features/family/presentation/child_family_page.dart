import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../application/family_providers.dart';

/// 子女端家庭 Tab：绑定关系 + 账号与退出（合并原设置页）。
class ChildFamilyPage extends ConsumerWidget {
  const ChildFamilyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);
    final familyAsync = ref.watch(familyInfoProvider);

    return CocoScaffold(
      title: '家庭',
      body: ListView(
        children: [
          Text('家庭绑定', style: theme.textTheme.titleMedium),
          const SizedBox(height: CocoSpace.s3),
          familyAsync.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(CocoSpace.s5),
                child: LinearProgressIndicator(),
              ),
            ),
            error: (error, _) => Card(
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
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(CocoSpace.s5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('还没有绑定父母。', style: theme.textTheme.bodyLarge),
                        const SizedBox(height: CocoSpace.s2),
                        Text(
                          '长辈决定分享什么；这里看不到完整聊天。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: CocoColors.neutral700,
                          ),
                        ),
                        const SizedBox(height: CocoSpace.s4),
                        CocoPrimaryButton(
                          label: '输入邀请码加入',
                          onPressed: () => context.push('/child/join'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final parentName = family.parentDisplayName ?? '父母';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(CocoSpace.s5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '已与「$parentName」绑定',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: CocoSpace.s2),
                      Text(
                        '摘要由长辈授权后才会出现。长辈决定分享什么；这里看不到完整聊天。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: CocoColors.neutral700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: CocoSpace.s8),
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
