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

/// 父母端：大字邀请码，便于老人念给子女。
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
            : '邀请码没生成成功。您可以再试一次，数据没有受影响。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final familyAsync = ref.watch(familyInfoProvider);

    return CocoScaffold(
      title: '邀请子女',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: CocoSpace.s3),
          child: Center(
            child: ParentChipButton(
              label: '返回',
              onPressed: () => context.pop(),
            ),
          ),
        ),
      ],
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
                '把下面的邀请码告诉子女，让对方在「子女模式」里输入。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
              const SizedBox(height: CocoSpace.s8),
              if (invite != null) ...[
                Container(
                  padding: const EdgeInsets.all(CocoSpace.s6),
                  decoration: BoxDecoration(
                    color: CocoColors.parentPrimarySoft,
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
