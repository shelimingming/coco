import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';

/// 子女端占位首页：今日状态卡片。
class ChildHomePage extends ConsumerWidget {
  const ChildHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);

    return CocoScaffold(
      title: '今日状态',
      actions: [
        TextButton(
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          child: const Text('退出'),
        ),
      ],
      body: ListView(
        children: [
          Text(
            '你好，${user?.displayName ?? '家人'}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: CocoSpace.s2),
          Text(
            '打开 App，先看父母今天是否安稳。',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: CocoSpace.s6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(CocoSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今天总体正常', style: theme.textTheme.titleMedium),
                  const SizedBox(height: CocoSpace.s2),
                  Text(
                    '还没有可展示的家庭数据。完成绑定后，这里会显示提醒与关怀摘要。',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: CocoSpace.s4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(CocoSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('需要关注', style: theme.textTheme.titleMedium),
                  const SizedBox(height: CocoSpace.s2),
                  Text(
                    '暂无待处理事项。',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: CocoColors.neutral700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
