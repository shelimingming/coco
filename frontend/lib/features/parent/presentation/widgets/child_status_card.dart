import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_button.dart';
import '../../../notifications/domain/models.dart';

/// 父母端收到子女报平安：布局对齐提醒确认卡（头像压边、白底轻阴影、内容浅底）。
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

  static const double _avatarSize = 64;
  static const String _avatarAsset =
      'assets/images/parent/home/coco_chat_avatar.png';

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 卡片整体下移半个头像，让头像压在上沿
        Padding(
          padding: const EdgeInsets.only(top: _avatarSize / 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CocoColors.parentSurface,
              borderRadius: BorderRadius.circular(CocoRadius.xl),
              boxShadow: [
                BoxShadow(
                  color: CocoColors.neutral950.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CocoSpace.s5,
                CocoSpace.s6,
                CocoSpace.s5,
                CocoSpace.s5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '孩子给您报了个平安',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: CocoColors.neutral950,
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s4),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: CocoColors.neutral300,
                  ),
                  const SizedBox(height: CocoSpace.s4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: CocoColors.parentPrimarySoft,
                      borderRadius: BorderRadius.circular(CocoRadius.lg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CocoSpace.s5,
                        vertical: CocoSpace.s5,
                      ),
                      child: Text(
                        notification.body,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          color: CocoColors.neutral950,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s5),
                  CocoPrimaryButton(
                    label: '知道了',
                    loading: busy,
                    loadingLabel: '正在确认…',
                    onPressed: busy ? null : onAcknowledge,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: CocoSpace.s5,
          child: Container(
            width: _avatarSize,
            height: _avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: CocoColors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: CocoColors.neutral950.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                _avatarAsset,
                width: _avatarSize,
                height: _avatarSize,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
