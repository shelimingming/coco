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

/// 看一看单页：取图、识图、朗读、追问全在同屏完成。
class LookPage extends ConsumerWidget {
  const LookPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lookControllerProvider);
    final controller = ref.read(lookControllerProvider.notifier);
    final theme = Theme.of(context);

    final pose = switch (state.phase) {
      LookPhase.idle => CocoCompanionPose.idle,
      LookPhase.analyzing => CocoCompanionPose.idle,
      LookPhase.listening => CocoCompanionPose.listening,
      LookPhase.thinking => CocoCompanionPose.listening,
      LookPhase.speaking => CocoCompanionPose.speaking,
      LookPhase.error => CocoCompanionPose.idle,
    };

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
          if (state.hasImage) ...[
            _ImagePinBar(state: state),
            const SizedBox(height: CocoSpace.s4),
          ],
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (!state.hasImage && state.phase == LookPhase.idle) ...[
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
                    const SizedBox(height: CocoSpace.s6),
                    _SourceButtons(onPick: controller.pick),
                  ] else ...[
                    CocoCompanionView(pose: pose, size: 132),
                    const SizedBox(height: CocoSpace.s3),
                    Text(
                      state.statusLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: CocoColors.neutral700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: CocoSpace.s4),
                    if (state.notice != null) ...[
                      _NoticeBox(message: state.notice!),
                      const SizedBox(height: CocoSpace.s3),
                    ],
                    if (state.userCaption.isNotEmpty) ...[
                      Text(
                        '您说：${state.userCaption}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: CocoColors.neutral700,
                        ),
                      ),
                      const SizedBox(height: CocoSpace.s3),
                    ],
                    if (state.userCaption.isNotEmpty &&
                        state.replyText.isNotEmpty) ...[
                      Text(
                        state.replyText,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: CocoColors.neutral950,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                    ] else if (state.isClear && state.headline.isNotEmpty) ...[
                      Text(
                        state.headline,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: CocoColors.parentPrimary,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      if (state.detail.trim().isNotEmpty) ...[
                        const SizedBox(height: CocoSpace.s3),
                        Text(
                          state.detail,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: CocoColors.neutral700,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (state.safetyNote.trim().isNotEmpty) ...[
                        const SizedBox(height: CocoSpace.s4),
                        _SafetyBox(message: state.safetyNote),
                      ],
                    ] else if (state.replyText.isNotEmpty) ...[
                      Text(
                        state.replyText,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: CocoColors.neutral950,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                    ] else if (state.phase == LookPhase.analyzing) ...[
                      Text(
                        '可可正在看这张图…',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: CocoColors.neutral700,
                        ),
                      ),
                    ],
                    if (state.errorTitle != null) ...[
                      const SizedBox(height: CocoSpace.s4),
                      _ErrorBox(
                        title: state.errorTitle!,
                        message: state.errorMessage ?? '',
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (state.hasImage || state.phase != LookPhase.idle) ...[
            const SizedBox(height: CocoSpace.s4),
            if (state.primaryLabel.isNotEmpty &&
                !(state.phase == LookPhase.idle &&
                    state.hasImage &&
                    !state.canFollowUp))
              CocoPrimaryButton(
                label: state.primaryLabel,
                loading:
                    state.phase == LookPhase.analyzing ||
                    state.phase == LookPhase.thinking,
                loadingLabel: state.phase == LookPhase.analyzing
                    ? '可可正在看'
                    : '可可正在想…',
                onPressed:
                    (state.phase == LookPhase.analyzing ||
                        state.phase == LookPhase.thinking)
                    ? null
                    : () => unawaited(controller.onPrimaryPressed()),
              ),
            if (state.hasImage &&
                (state.phase == LookPhase.idle ||
                    state.phase == LookPhase.error)) ...[
              const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(
                label: '再听一遍',
                onPressed: state.replyText.trim().isNotEmpty
                    ? () => unawaited(controller.replay())
                    : null,
              ),
            ],
            const SizedBox(height: CocoSpace.s3),
            // 旧独立页兼容；首页主路径用再点「看照片」换图
            CocoSecondaryButton(
              label: '清空重选',
              onPressed: state.isBusy
                  ? null
                  : () => unawaited(controller.reset()),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceButtons extends StatelessWidget {
  const _SourceButtons({required this.onPick});

  final Future<void> Function(LookSource source) onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CocoPrimaryButton(
          label: LookSource.camera.label,
          onPressed: () => unawaited(onPick(LookSource.camera)),
        ),
        const SizedBox(height: CocoSpace.s3),
        CocoSecondaryButton(
          label: LookSource.screenshot.label,
          onPressed: () => unawaited(onPick(LookSource.screenshot)),
        ),
        const SizedBox(height: CocoSpace.s3),
        _AlbumSourceButton(
          onPressed: () => unawaited(onPick(LookSource.album)),
        ),
      ],
    );
  }
}

class _AlbumSourceButton extends StatelessWidget {
  const _AlbumSourceButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CocoSecondaryButton(
      label: LookSource.album.label,
      onPressed: onPressed,
    );
  }
}

class _ImagePinBar extends StatelessWidget {
  const _ImagePinBar({required this.state});

  final LookState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = state.imageBytes;
    if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(CocoSpace.s3),
      decoration: BoxDecoration(
        color: CocoColors.neutral100,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(CocoRadius.md),
            child: Image.memory(
              bytes,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 64,
                height: 64,
                color: CocoColors.parentPrimarySoft,
                child: const Icon(Icons.image_outlined),
              ),
            ),
          ),
          const SizedBox(width: CocoSpace.s3),
          Expanded(
            child: Text(
              state.headline.trim().isNotEmpty ? state.headline : '正在看这张图…',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: CocoColors.neutral950,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CocoSpace.s4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          CocoColors.parentPrimarySoft.withValues(alpha: 0.35),
          CocoColors.parentSurface,
        ),
        borderRadius: BorderRadius.circular(CocoRadius.md),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: CocoColors.neutral700,
          height: 1.45,
        ),
      ),
    );
  }
}

class _SafetyBox extends StatelessWidget {
  const _SafetyBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CocoSpace.s4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          CocoColors.warning.withValues(alpha: 0.12),
          CocoColors.parentSurface,
        ),
        borderRadius: BorderRadius.circular(CocoRadius.md),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: CocoColors.warning,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CocoSpace.s4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          CocoColors.warning.withValues(alpha: 0.12),
          CocoColors.parentSurface,
        ),
        borderRadius: BorderRadius.circular(CocoRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: CocoColors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CocoSpace.s2),
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
        ],
      ),
    );
  }
}
