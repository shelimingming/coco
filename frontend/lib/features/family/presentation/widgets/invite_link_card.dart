import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';

/// 邀请页直接展示链接，便于核对、长按选中或配合下方「复制链接」。
class InviteLinkCard extends StatelessWidget {
  const InviteLinkCard({
    super.key,
    required this.inviteUrl,
    required this.backgroundColor,
    this.urlStyle,
  });

  final String inviteUrl;
  final Color backgroundColor;
  final TextStyle? urlStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CocoSpace.s6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('邀请链接', style: theme.textTheme.titleMedium),
          const SizedBox(height: CocoSpace.s3),
          SelectableText(
            inviteUrl,
            style:
                urlStyle ??
                theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral950,
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}
