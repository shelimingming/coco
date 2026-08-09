import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_button.dart';
import '../../domain/pending_voice_action.dart';

/// 通话中一次确认大卡：创建提醒或告诉家人；点一下或语音说好即可。
class ParentPendingActionCard extends StatelessWidget {
  const ParentPendingActionCard({
    super.key,
    required this.action,
    required this.onConfirm,
    required this.onCancel,
    this.busy = false,
  });

  final PendingVoiceAction action;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReminder = action.kind == PendingVoiceActionKind.createReminder;

    return Container(
      padding: const EdgeInsets.all(CocoSpace.s4),
      decoration: BoxDecoration(
        color: CocoColors.parentPrimarySoft,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        border: Border.all(color: CocoColors.parentPrimary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isReminder ? '确认这个提醒' : '告诉家人',
            style: theme.textTheme.titleLarge?.copyWith(
              color: CocoColors.parentPrimary,
            ),
          ),
          const SizedBox(height: CocoSpace.s3),
          if (isReminder) ...[
            _Field(label: '做什么', value: action.title),
            const SizedBox(height: CocoSpace.s2),
            _Field(
              label: '什么时候',
              value: action.scheduleTime.isEmpty ? '—' : action.scheduleTime,
            ),
            const SizedBox(height: CocoSpace.s2),
            _Field(
              label: '是否每天',
              value: action.repeatLabel.isNotEmpty
                  ? action.repeatLabel
                  : (action.scheduleType == 'DAILY' ? '每天' : '仅一次'),
            ),
          ] else ...[
            _Field(label: '告诉家人什么', value: action.summary),
            const SizedBox(height: CocoSpace.s2),
            _Field(label: '给谁', value: action.shareTo),
          ],
          const SizedBox(height: CocoSpace.s2),
          Text(
            '也可以直接说「好」',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const SizedBox(height: CocoSpace.s4),
          CocoPrimaryButton(
            label: isReminder ? '确认这个提醒' : '告诉家人',
            loading: busy,
            loadingLabel: '正在确认…',
            onPressed: busy ? null : onConfirm,
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(label: '先不要', onPressed: busy ? null : onCancel),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: CocoColors.neutral700,
          ),
        ),
        const SizedBox(height: CocoSpace.s1),
        Text(value.isEmpty ? '—' : value, style: theme.textTheme.titleLarge),
      ],
    );
  }
}
