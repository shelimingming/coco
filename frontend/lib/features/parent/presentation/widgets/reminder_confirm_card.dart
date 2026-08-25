import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_button.dart';
import '../../../notifications/domain/models.dart';

/// 父母端到点确认卡：布局对齐语音「确认提醒」大卡（头像压边、白底轻阴影、内容浅底）。
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

  static const double _avatarSize = 64;
  static const String _avatarAsset =
      'assets/images/parent/home/coco_chat_avatar.png';

  @override
  Widget build(BuildContext context) {
    final reminderName = _reminderNameFromBody(notification.body);
    final rows = <(String, String)>[
      if (reminderName != null) ('提醒什么', reminderName),
      ('说明', _promptFromBody(notification.body)),
    ];

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
                    '日常提醒',
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0) const SizedBox(height: CocoSpace.s3),
                            _DetailRow(label: rows[i].$1, value: rows[i].$2),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s5),
                  CocoPrimaryButton(
                    label: '完成了',
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

  /// 从「到「睡觉」时间了…」里取出事项名；解析不到则整段放说明。
  static String? _reminderNameFromBody(String body) {
    final match = RegExp(r'「([^」]+)」').firstMatch(body);
    final name = match?.group(1)?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  static String _promptFromBody(String body) {
    // 正文固定句式，拆成短问句放「说明」，避免与事项名重复
    if (body.contains('还没有确认')) {
      return '刚才提醒过了，已经做过了吗？';
    }
    if (body.contains('已经做过了吗')) {
      return '已经做过了吗？';
    }
    return body.trim();
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  static const double _labelWidth = 118;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(
            '$label：',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: CocoColors.neutral500,
            ),
          ),
        ),
        const SizedBox(width: CocoSpace.s3),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: CocoColors.neutral950,
            ),
          ),
        ),
      ],
    );
  }
}
