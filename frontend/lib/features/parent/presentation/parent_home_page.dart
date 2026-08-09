import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../application/coco_companion_controller.dart';
import 'widgets/coco_companion_view.dart';

/// 父母端占位首页：问候 + 功能入口 + Coco 形象 + 大号「和我说话」按钮。
class ParentHomePage extends ConsumerWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final name = user?.displayName ?? '家人';
    final theme = Theme.of(context);
    // 形象随姿态切换；语音接通后由业务侧更新 cocoCompanionPoseProvider
    final companionPose = ref.watch(cocoCompanionPoseProvider);

    return CocoScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶栏自绘：避免无 title 时 AppBar 不渲染，功能入口始终可见
          Row(
            children: [
              Expanded(
                child: Text('你好，$name', style: theme.textTheme.titleLarge),
              ),
              const SizedBox(width: CocoSpace.s3),
              ParentChipButton(
                label: '功能',
                onPressed: () => context.push('/parent/functions'),
              ),
            ],
          ),
          const SizedBox(height: CocoSpace.s3),
          Text(
            '上午好，我在呢，想聊什么？',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const Spacer(),
          // 老人端首页主视觉：一屏一事，突出陪伴形象
          Center(
            child: CocoCompanionView(pose: companionPose),
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
