import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/family_providers.dart';
import '../data/family_api.dart';
import '../domain/models.dart';
import 'widgets/invite_link_card.dart';

/// 子女端：分享邀请链接请父母加入。
class ChildInvitePage extends ConsumerStatefulWidget {
  const ChildInvitePage({super.key});

  @override
  ConsumerState<ChildInvitePage> createState() => _ChildInvitePageState();
}

class _ChildInvitePageState extends ConsumerState<ChildInvitePage> {
  FamilyInvite? _invite;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureInvite());
  }

  Future<void> _ensureInvite() async {
    final family = ref.read(familyInfoProvider).asData?.value;
    if (family != null && family.isActive) return;
    if (_invite != null || _busy) return;
    await _generate();
  }

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
            : '邀请链接没准备好。您可以再试一次，数据没有受影响。';
      });
    }
  }

  Future<void> _share(FamilyInvite invite) async {
    await SharePlus.instance.share(
      ShareParams(text: '点开就能加入我的家庭：${invite.inviteUrl}'),
    );
  }

  Future<void> _copy(FamilyInvite invite) async {
    await Clipboard.setData(ClipboardData(text: invite.inviteUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('邀请链接已复制。')));
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
                '把链接发给父母，对方点开登录后点「加入家庭」即可完成绑定。链接长期有效，绑定成功后自动失效。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
              const SizedBox(height: CocoSpace.s8),
              if (invite != null)
                InviteLinkCard(
                  inviteUrl: invite.inviteUrl,
                  backgroundColor: CocoColors.childPrimarySoft,
                )
              else
                Text('正在准备邀请链接…', style: theme.textTheme.bodyLarge),
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
                label: '分享给父母',
                loading: _busy,
                loadingLabel: '正在准备…',
                onPressed: invite == null ? _generate : () => _share(invite),
              ),
              const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(
                label: '复制链接',
                onPressed: invite == null ? null : () => _copy(invite),
              ),
              const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(label: '返回', onPressed: () => context.pop()),
            ],
          );
        },
      ),
    );
  }
}
