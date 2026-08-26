import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/family_providers.dart';
import '../data/family_api.dart';
import '../domain/models.dart';

/// 子女端：生成邀请码，请父母在老人模式输入。
class ChildInvitePage extends ConsumerStatefulWidget {
  const ChildInvitePage({super.key});

  @override
  ConsumerState<ChildInvitePage> createState() => _ChildInvitePageState();
}

class _ChildInvitePageState extends ConsumerState<ChildInvitePage> {
  FamilyInvite? _invite;
  bool _busy = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invite = await ref.read(familyApiProvider).createInvite();
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _busy = false;
      });
      ref.invalidate(familyInfoProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is ApiException
            ? error.message
            : '邀请码没生成成功。您可以再试一次，数据没有受影响。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final familyAsync = ref.watch(familyInfoProvider);

    return CocoScaffold(
      title: '邀请父母',
      body: familyAsync.when(
        loading: () => const CocoPageLoading(),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error is ApiException
                  ? error.message
                  : '家庭信息加载失败。您可以返回重试，数据没有丢失。',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(familyInfoProvider),
            ),
          ],
        ),
        data: (family) {
          if (family != null && family.isActive) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('已经绑定父母', style: theme.textTheme.titleLarge),
                const SizedBox(height: CocoSpace.s3),
                Text(
                  '父母：${family.parentDisplayName ?? '家人'}',
                  style: theme.textTheme.bodyLarge,
                ),
                const Spacer(),
                CocoSecondaryButton(
                  label: '返回',
                  onPressed: () => context.pop(),
                ),
              ],
            );
          }

          final invite = _invite;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '把下面的邀请码告诉父母，让对方在「老人模式」里输入。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
              const SizedBox(height: CocoSpace.s8),
              if (invite != null) ...[
                Container(
                  padding: const EdgeInsets.all(CocoSpace.s6),
                  decoration: BoxDecoration(
                    color: CocoColors.childPrimarySoft,
                    borderRadius: BorderRadius.circular(CocoRadius.xl),
                  ),
                  child: Column(
                    children: [
                      Text(
                        invite.code,
                        style: theme.textTheme.displayLarge?.copyWith(
                          letterSpacing: 8,
                          fontWeight: FontWeight.w700,
                          color: CocoColors.neutral950,
                        ),
                      ),
                      const SizedBox(height: CocoSpace.s3),
                      Text(
                        '有效至 ${_formatTime(invite.expiresAt)}',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CocoSpace.s4),
                CocoSecondaryButton(
                  label: '复制邀请码',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: invite.code));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('邀请码已复制。')));
                  },
                ),
              ] else
                Text(
                  '点下面按钮生成邀请码。邀请码 10 分钟内有效。',
                  style: theme.textTheme.bodyLarge,
                ),
              if (_error != null) ...[
                const SizedBox(height: CocoSpace.s4),
                Text(
                  _error!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: CocoColors.danger,
                  ),
                ),
              ],
              const Spacer(),
              CocoPrimaryButton(
                label: invite == null ? '生成邀请码' : '重新生成',
                loading: _busy,
                loadingLabel: '正在生成…',
                onPressed: _generate,
              ),
              const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(label: '返回', onPressed: () => context.pop()),
            ],
          );
        },
      ),
    );
  }

  String _formatTime(DateTime utc) {
    final local = utc.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
