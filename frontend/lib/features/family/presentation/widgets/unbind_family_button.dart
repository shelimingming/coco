import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/tokens.dart';
import '../../../care/application/care_providers.dart';
import '../../application/family_providers.dart';
import '../../data/family_api.dart';

/// 解除绑定：危险操作，二次确认后调用 API。
class UnbindFamilyButton extends ConsumerStatefulWidget {
  const UnbindFamilyButton({
    super.key,
    required this.partnerName,
    this.style = UnbindFamilyButtonStyle.child,
  });

  final String partnerName;
  final UnbindFamilyButtonStyle style;

  @override
  ConsumerState<UnbindFamilyButton> createState() => _UnbindFamilyButtonState();
}

enum UnbindFamilyButtonStyle { child, parent }

class _UnbindFamilyButtonState extends ConsumerState<UnbindFamilyButton> {
  bool _busy = false;

  Future<void> _confirmAndUnbind() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('解除绑定？'),
          content: Text(
            '将与${widget.partnerName}解除家人关系，解绑后无法再查看对方近况和留言。'
            '历史留言和报平安记录会保留，但 App 内不再展示。'
            '解除后可重新邀请其他家人。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: CocoColors.danger),
              child: const Text('解除绑定'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(familyApiProvider).unbindFamily();
      ref.invalidate(familyInfoProvider);
      ref.invalidate(childTodayProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已解除绑定。您可以重新邀请家人。')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : '解除绑定失败。请再试一次，绑定关系没有变化。',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == UnbindFamilyButtonStyle.parent) {
      return OutlinedButton(
        onPressed: _busy ? null : _confirmAndUnbind,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: CocoColors.danger,
          side: const BorderSide(color: CocoColors.danger, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        child: _busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('解除绑定'),
      );
    }

    return OutlinedButton(
      onPressed: _busy ? null : _confirmAndUnbind,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: CocoColors.danger,
        side: const BorderSide(color: CocoColors.danger, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CocoRadius.md),
        ),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      child: _busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('解除绑定'),
    );
  }
}
