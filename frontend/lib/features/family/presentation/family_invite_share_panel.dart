import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../domain/models.dart';

/// 邀请方页面共用：展示链接并提供复制。
class FamilyInviteSharePanel extends StatelessWidget {
  const FamilyInviteSharePanel({
    super.key,
    required this.invite,
    required this.isParent,
    required this.onRegenerate,
    required this.busy,
  });

  final FamilyInvite invite;
  final bool isParent;
  final VoidCallback onRegenerate;
  final bool busy;

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: invite.inviteUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('邀请链接已复制，可粘贴到微信发给家人。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soft = isParent
        ? CocoColors.parentPrimarySoft
        : CocoColors.childPrimarySoft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(CocoSpace.s5),
          decoration: BoxDecoration(
            color: soft,
            borderRadius: BorderRadius.circular(CocoRadius.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('邀请链接', style: theme.textTheme.titleMedium),
              const SizedBox(height: CocoSpace.s3),
              SelectableText(
                invite.inviteUrl,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CocoSpace.s4),
        CocoPrimaryButton(
          label: '复制邀请链接',
          onPressed: () => _copyLink(context),
        ),
        const SizedBox(height: CocoSpace.s3),
        CocoSecondaryButton(
          label: busy ? '正在重新生成…' : '重新生成链接',
          onPressed: busy ? null : onRegenerate,
        ),
      ],
    );
  }
}
