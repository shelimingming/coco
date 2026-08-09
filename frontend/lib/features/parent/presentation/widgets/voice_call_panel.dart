import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_button.dart';
import '../../domain/voice_call_state.dart';

/// 通话态面板：大字状态、字幕、打断 / 结束；错误用页内 StateNotice。
class VoiceCallPanel extends StatelessWidget {
  const VoiceCallPanel({
    super.key,
    required this.state,
    required this.onEnd,
    required this.onInterrupt,
    required this.onRetry,
  });

  final VoiceCallState state;
  final VoidCallback onEnd;
  final VoidCallback onInterrupt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.phase == VoiceCallPhase.error) {
      return _VoiceErrorNotice(
        title: state.errorTitle ?? '出了点问题',
        message: state.errorMessage ?? '请稍后再试。',
        onRetry: onRetry,
      );
    }

    final theme = Theme.of(context);
    final caption = state.assistantCaption.isNotEmpty
        ? state.assistantCaption
        : state.userCaption;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          state.statusLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            color: CocoColors.parentPrimary,
          ),
        ),
        const SizedBox(height: CocoSpace.s3),
        // 字幕区：当前句始终清晰；过长时可滚动
        SizedBox(
          height: 88,
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              caption.isEmpty ? '您可以直接说话' : caption,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: caption.isEmpty
                    ? CocoColors.neutral500
                    : CocoColors.neutral950,
              ),
            ),
          ),
        ),
        const SizedBox(height: CocoSpace.s4),
        if (state.canInterrupt) ...[
          CocoSecondaryButton(label: '打断', onPressed: onInterrupt),
          const SizedBox(height: CocoSpace.s3),
        ],
        CocoPrimaryButton(label: '结束说话', onPressed: onEnd),
      ],
    );
  }
}

/// 页内持久错误说明：发生了什么、现在能做什么、有没有保存内容。
class _VoiceErrorNotice extends StatelessWidget {
  const _VoiceErrorNotice({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CocoSpace.s6),
      decoration: BoxDecoration(
        color: CocoColors.white,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        border: Border.all(color: CocoColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: CocoColors.danger, size: 28),
              const SizedBox(width: CocoSpace.s3),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: CocoColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CocoSpace.s3),
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const SizedBox(height: CocoSpace.s5),
          CocoPrimaryButton(label: '再试一次', onPressed: onRetry),
        ],
      ),
    );
  }
}
