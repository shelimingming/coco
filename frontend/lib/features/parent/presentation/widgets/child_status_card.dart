import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_button.dart';
import '../../../notifications/domain/models.dart';

/// 父母端收到子女报平安：转述正文 +「知道了」结束本次互动。
class ChildStatusCard extends StatelessWidget {
  const ChildStatusCard({
    super.key,
    required this.notification,
    required this.onAcknowledge,
    this.busy = false,
  });

  final AppNotification notification;
  final VoidCallback onAcknowledge;
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
          Text('孩子给您报了个平安', style: theme.textTheme.titleLarge),
          const SizedBox(height: CocoSpace.s2),
          Text(notification.body, style: theme.textTheme.bodyLarge),
          const SizedBox(height: CocoSpace.s5),
          CocoPrimaryButton(
            label: '知道了',
            loading: busy,
            loadingLabel: '正在确认…',
            onPressed: busy ? null : onAcknowledge,
          ),
        ],
      ),
    );
  }
}
