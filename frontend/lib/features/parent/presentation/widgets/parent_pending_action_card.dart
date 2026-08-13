import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_loading.dart';
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

  static const double _avatarSize = 64;
  static const String _avatarAsset =
      'assets/images/parent/home/coco_chat_avatar.png';

  @override
  Widget build(BuildContext context) {
    final isReminder = action.kind == PendingVoiceActionKind.createReminder;
    final title = isReminder ? '确认提醒内容' : '确认告诉家人';
    final rows = isReminder
        ? <(String, String)>[
            ('是否重复', _repeatText(action)),
            ('时间', action.scheduleTime.isEmpty ? '—' : action.scheduleTime),
            ('提醒什么', action.title.isEmpty ? '—' : action.title),
          ]
        : <(String, String)>[
            ('告诉家人什么', action.summary.isEmpty ? '—' : action.summary),
            ('给谁', action.shareTo),
          ];
    final confirmLabel = isReminder ? '点击创建' : '告诉家人';

    // 铺满中间区：摘要再长也只滚内容区，「告诉家人 / 先不要了」钉在卡片底
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _avatarSize / 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CocoColors.white,
              borderRadius: BorderRadius.circular(CocoRadius.xl),
              boxShadow: const [
                BoxShadow(
                  color: CocoColors.onboardingShadow,
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CocoRadius.xl),
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
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
                    Expanded(
                      child: SingleChildScrollView(
                        child: DecoratedBox(
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
                                  if (i > 0)
                                    const SizedBox(height: CocoSpace.s3),
                                  _DetailRow(
                                    label: rows[i].$1,
                                    value: rows[i].$2,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: CocoSpace.s5),
                    _ConfirmPrimaryButton(
                      label: confirmLabel,
                      busy: busy,
                      onPressed: busy ? null : onConfirm,
                    ),
                    const SizedBox(height: CocoSpace.s3),
                    _ConfirmSecondaryButton(
                      label: '先不要了',
                      busy: busy,
                      onPressed: busy ? null : onCancel,
                    ),
                  ],
                ),
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

  /// 交付稿用语「仅今天」；每日重复仍显示「每天」。
  static String _repeatText(PendingVoiceAction action) {
    if (action.repeatLabel.isNotEmpty) return action.repeatLabel;
    return action.scheduleType == 'DAILY' ? '每天' : '仅今天';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  /// 与最长标签「是否重复：」对齐，冒号竖线齐。
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

class _ConfirmPrimaryButton extends StatelessWidget {
  const _ConfirmPrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: CocoColors.parentPrimary,
          foregroundColor: CocoColors.white,
          disabledBackgroundColor: CocoColors.parentPrimary,
          disabledForegroundColor: CocoColors.white,
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
        child: busy
            ? const CocoLoadingLabel(
                label: '正在确认…',
                indicatorColor: CocoColors.white,
              )
            : Text(label),
      ),
    );
  }
}

class _ConfirmSecondaryButton extends StatelessWidget {
  const _ConfirmSecondaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: CocoColors.parentPrimary,
          disabledForegroundColor: CocoColors.parentPrimary,
          side: const BorderSide(color: CocoColors.parentPrimary, width: 1.5),
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
        child: busy
            ? const CocoLoadingLabel(
                label: '请稍候…',
                indicatorColor: CocoColors.parentPrimary,
              )
            : Text(label),
      ),
    );
  }
}
