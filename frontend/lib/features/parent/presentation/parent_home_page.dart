import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';

/// 父母端占位首页：问候 + 大号「和我说话」按钮。
class ParentHomePage extends ConsumerWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final name = user?.displayName ?? '家人';
    final theme = Theme.of(context);

    return CocoScaffold(
      actions: [
        TextButton(
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          child: const Text('退出'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('你好，$name', style: theme.textTheme.titleLarge),
          const SizedBox(height: CocoSpace.s3),
          Text(
            '上午好，我在呢，想聊什么？',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const Spacer(),
          Center(
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: CocoColors.parentPrimarySoft,
                borderRadius: BorderRadius.circular(CocoRadius.pill),
              ),
              alignment: Alignment.center,
              child: Text(
                '可可',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: CocoColors.parentPrimary,
                ),
              ),
            ),
          ),
          const Spacer(),
          CocoPrimaryButton(
            label: '和我说话',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('语音对话即将到来，先完成登录框架。')),
              );
            },
          ),
          const SizedBox(height: CocoSpace.s4),
          Text(
            '今天还没有提醒',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
