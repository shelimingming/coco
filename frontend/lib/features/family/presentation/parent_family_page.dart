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

/// 父母端：生成邀请链接，便于微信转发给子女。
class ParentFamilyPage extends ConsumerStatefulWidget {
  const ParentFamilyPage({super.key});

  @override
  ConsumerState<ParentFamilyPage> createState() => _ParentFamilyPageState();
}

class _ParentFamilyPageState extends ConsumerState<ParentFamilyPage> {
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
      title: '邀请子女',
      leading: ParentBackButton(onPressed: () => context.pop()),
      leadingWidth: 104,
      bottom: ParentHomeButton(onPressed: () => context.go('/parent')),
      body: familyAsync.when(
        loading: () => const CocoPageLoading(),
        error: (error, _) => _ErrorBody(
          message: error is ApiException
              ? error.message
              : '家庭信息加载失败。您可以返回重试，数据没有丢失。',
          onRetry: () => ref.invalidate(familyInfoProvider),
        ),
        data: (family) {
          if (family != null && family.isActive) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('已经绑定子女', style: theme.textTheme.titleLarge),
                const SizedBox(height: CocoSpace.s3),
                Text(
                  '子女：${family.childDisplayName ?? '家人'}',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: CocoSpace.s2),
                Text(
                  '目前每位老人只能绑定一位主要子女。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: CocoColors.neutral700,
                  ),
                ),
              ],
            );
          }

          final invite = _invite;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '生成邀请链接，复制后通过微信发给子女；对方点开链接登录即可加入。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
              const SizedBox(height: CocoSpace.s6),
              if (invite != null)
                FamilyInviteSharePanel(
                  invite: invite,
                  isParent: true,
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
            ],
          );
        },
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodyLarge),
        const Spacer(),
        CocoPrimaryButton(label: '再试一次', onPressed: onRetry),
      ],
    );
  }
}
