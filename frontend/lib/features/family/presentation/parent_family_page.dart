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
import 'widgets/unbind_family_button.dart';

/// 父母端：分享邀请链接给子女，对方点开登录后确认加入。
class ParentFamilyPage extends ConsumerStatefulWidget {
  const ParentFamilyPage({super.key});

  @override
  ConsumerState<ParentFamilyPage> createState() => _ParentFamilyPageState();
}

class _ParentFamilyPageState extends ConsumerState<ParentFamilyPage> {
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
            final childName = family.childDisplayName ?? '家人';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('已经绑定子女', style: theme.textTheme.titleLarge),
                const SizedBox(height: CocoSpace.s3),
                Text('子女：$childName', style: theme.textTheme.bodyLarge),
                const Spacer(),
                UnbindFamilyButton(
                  partnerName: childName,
                  style: UnbindFamilyButtonStyle.parent,
                ),
              ],
            );
          }

          final invite = _invite;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '把链接发给子女，对方点开登录后点「加入家庭」即可完成绑定。链接长期有效，绑定成功后自动失效。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
              const SizedBox(height: CocoSpace.s8),
              if (invite != null)
                InviteLinkCard(
                  inviteUrl: invite.inviteUrl,
                  backgroundColor: CocoColors.parentPrimarySoft,
                  // 父母端字号略大，方便核对链接
                  urlStyle: theme.textTheme.titleMedium?.copyWith(
                    color: CocoColors.neutral950,
                    height: 1.45,
                  ),
                )
              else
                Text(
                  '正在准备邀请链接…',
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
                label: '分享给子女',
                loading: _busy,
                loadingLabel: '正在准备…',
                onPressed: invite == null ? _generate : () => _share(invite),
              ),
              const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(
                label: '复制链接',
                onPressed: invite == null ? null : () => _copy(invite),
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
