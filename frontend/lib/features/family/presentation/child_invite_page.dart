import 'package:flutter/material.dart';
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
import 'family_invite_share_panel.dart';

/// 子女端：生成邀请链接，请父母在微信里点开加入。
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
            : '邀请链接没生成成功。您可以再试一次，数据没有受影响。';
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
                '生成邀请链接，复制后通过微信发给父母；对方点开链接登录即可加入。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
              const SizedBox(height: CocoSpace.s6),
              if (invite != null)
                FamilyInviteSharePanel(
                  invite: invite,
                  isParent: false,
                  busy: _busy,
                  onRegenerate: _generate,
                )
              else
                Text(
                  '点下面按钮生成邀请链接，复制后发给家人即可。',
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
              if (invite == null)
                CocoPrimaryButton(
                  label: '生成邀请链接',
                  loading: _busy,
                  loadingLabel: '正在生成…',
                  onPressed: _generate,
                ),
              if (invite == null) const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(label: '返回', onPressed: () => context.pop()),
            ],
          );
        },
      ),
    );
  }
}
