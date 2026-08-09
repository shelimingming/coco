import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_button.dart';
import '../../../notifications/domain/models.dart';

/// 父母端到点确认卡：主操作「吃过了」，次操作「稍后提醒」上下排列，避免误触。
class ReminderConfirmCard extends StatelessWidget {
  const ReminderConfirmCard({
    super.key,
    required this.notification,
    required this.onConfirm,
    required this.onDelay,
    this.busy = false,
  });

  final AppNotification notification;
  final VoidCallback onConfirm;
  final VoidCallback onDelay;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CocoSpace.s5),
      decoration: BoxDecoration(
        color: CocoColors.parentPrimarySoft,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        border: Border.all(color: CocoColors.parentPrimary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(notification.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: CocoSpace.s2),
          Text(notification.body, style: theme.textTheme.bodyLarge),
          const SizedBox(height: CocoSpace.s5),
          CocoPrimaryButton(
            label: '吃过了 / 做完了',
            loading: busy,
            loadingLabel: '正在确认…',
            onPressed: busy ? null : onConfirm,
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(
            label: '稍后提醒',
            onPressed: busy ? null : onDelay,
          ),
        ],
      ),
    );
  }
}
