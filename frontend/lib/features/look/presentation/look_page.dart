import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../parent/domain/coco_companion_pose.dart';
import '../../parent/presentation/widgets/coco_companion_view.dart';
import '../application/look_controller.dart';
import '../domain/look_state.dart';

/// 旧独立「看一看」页（兼容/调试）。主路径在父母首页：识图后注入 Realtime。
class LookPage extends ConsumerWidget {
  const LookPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lookControllerProvider);
    final controller = ref.read(lookControllerProvider.notifier);
    final theme = Theme.of(context);

    return CocoScaffold(
      title: '看一看',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: CocoSpace.s3),
          child: Center(
            child: ParentChipButton(
              label: '返回',
              onPressed: state.isBusy
                  ? null
                  : () {
                      unawaited(controller.reset());
                      context.pop();
                    },
            ),
          ),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: CocoSpace.s4),
                  const CocoCompanionView(
                    pose: CocoCompanionPose.idle,
                    size: 132,
                  ),
                  const SizedBox(height: CocoSpace.s5),
                  Text(
                    state.statusLabel,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: CocoColors.neutral700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s4),
                  Text(
                    '请从首页用「看照片」或「看眼前」。看完后会直接和您语音聊。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: CocoColors.neutral500,
                      height: 1.4,
                    ),
                  ),
                  if (state.phase == LookPhase.error) ...[
                    const SizedBox(height: CocoSpace.s4),
                    Text(
                      [
                        if (state.errorTitle != null) state.errorTitle!,
                        if (state.errorMessage != null) state.errorMessage!,
                      ].join('。'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        color: CocoColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: CocoSpace.s6),
                  if (!state.isBusy)
                    _SourceButtons(
                      onPick: (source) {
                        unawaited(
                          controller.pick(source, hostContext: context),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CocoSpace.s5,
                0,
                CocoSpace.s5,
                CocoSpace.s4,
              ),
              child: CocoSecondaryButton(
                label: '回首页',
                onPressed: () {
                  unawaited(controller.reset());
                  context.go('/parent');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceButtons extends StatelessWidget {
  const _SourceButtons({required this.onPick});

  final void Function(LookSource source) onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: CocoSpace.s3,
      runSpacing: CocoSpace.s3,
      children: [
        for (final source in LookSource.values.where(
          (s) => s != LookSource.screen,
        ))
          ParentChipButton(
            label: source.label,
            onPressed: () => onPick(source),
          ),
      ],
    );
  }
}
