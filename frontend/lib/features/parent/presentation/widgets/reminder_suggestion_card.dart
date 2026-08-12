import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_button.dart';
import '../../../notifications/domain/models.dart';

/// 父母确认子女建议的提醒：标题带建议人，展示事项/时间/重复，确认后才调度。
class ReminderSuggestionCard extends StatelessWidget {
  const ReminderSuggestionCard({
    super.key,
    required this.notification,
    required this.onAccept,
    required this.onReject,
    this.busy = false,
  });

  final AppNotification notification;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final bool busy;

  static const double _avatarSize = 64;
  static const String _avatarAsset =
      'assets/images/parent/home/coco_chat_avatar.png';

  @override
  Widget build(BuildContext context) {
    final title = notification.suggestionTitle?.trim().isNotEmpty == true
        ? notification.suggestionTitle!.trim()
        : _fallbackTitle(notification.body);
    // 建议人放进标题，详情区不再重复「由谁建议」
    final who = notification.suggestedByDisplayName?.trim().isNotEmpty == true
        ? notification.suggestedByDisplayName!.trim()
        : '家人';
    final rows = <(String, String)>[
      ('提醒什么', title),
      ('时间', _timeLabel(notification.suggestionScheduleTime)),
      ('是否重复', _repeatLabel(notification.suggestionScheduleType)),
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
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
                  Text(
                    '$who想要我提醒你',
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
                    label: '接受',
                    loading: busy,
                    loadingLabel: '正在确认…',
                    onPressed: busy ? null : onAccept,
                  ),
                  const SizedBox(height: CocoSpace.s3),
                  CocoSecondaryButton(
                    label: '不用了',
                    onPressed: busy ? null : onReject,
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

  static String _fallbackTitle(String body) {
    final match = RegExp(r'建议：(.+?)（').firstMatch(body);
    final name = match?.group(1)?.trim();
    if (name != null && name.isNotEmpty) return name;
    return body.trim().isEmpty ? '提醒' : body.trim();
  }

  static String _timeLabel(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final parts = raw.split(':');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return raw;
  }

  static String _repeatLabel(String? scheduleType) {
    if (scheduleType == 'DAILY') return '每天';
    if (scheduleType == 'ONCE') return '只提醒一次';
    return '—';
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
