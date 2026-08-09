import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../application/coco_companion_controller.dart';
import '../application/voice_call_controller.dart';
import '../domain/voice_call_state.dart';
import 'widgets/coco_companion_view.dart';
import 'widgets/voice_call_panel.dart';

/// 父母端首页：点小狗或「和我说话」进入实时陪伴，通话原地切换不跳页。
class ParentHomePage extends ConsumerWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final name = user?.displayName ?? '家人';
    final theme = Theme.of(context);
    final companionPose = ref.watch(cocoCompanionPoseProvider);
    final callState = ref.watch(voiceCallControllerProvider);
    final callController = ref.read(voiceCallControllerProvider.notifier);
    final inCall =
        callState.isActive || callState.phase == VoiceCallPhase.error;

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
                onPressed: inCall
                    ? null
                    : () => context.push('/parent/functions'),
              ),
            ],
          ),
          const SizedBox(height: CocoSpace.s3),
          if (!inCall)
            Text(
              '点我，我们说说话',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: CocoColors.neutral700,
              ),
            ),
          const Spacer(),
          // 整只小狗可点：未通话=开始；说话中=打断
          Center(
            child: Semantics(
              button: true,
              label: callState.canInterrupt ? '打断可可说话' : '和可可说话',
              child: GestureDetector(
                onTap: () {
                  if (callState.canInterrupt) {
                    callController.interrupt();
                  } else if (!inCall) {
                    callController.start();
                  }
                },
                child: CocoCompanionView(pose: companionPose),
              ),
            ),
          ),
          const Spacer(),
          if (inCall)
            VoiceCallPanel(
              state: callState,
              onEnd: callController.stop,
              onInterrupt: callController.interrupt,
              onRetry: callController.retry,
            )
          else ...[
            CocoPrimaryButton(label: '和我说话', onPressed: callController.start),
            const SizedBox(height: CocoSpace.s4),
            Text(
              '今天还没有提醒',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
