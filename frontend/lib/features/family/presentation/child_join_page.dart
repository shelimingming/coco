import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../../core/widgets/coco_text_field.dart';
import '../../care/application/care_providers.dart';
import '../application/family_providers.dart';
import '../data/family_api.dart';

/// 子女端：输入 6 位邀请码加入家庭。
class ChildJoinPage extends ConsumerStatefulWidget {
  const ChildJoinPage({super.key});

  @override
  ConsumerState<ChildJoinPage> createState() => _ChildJoinPageState();
}

class _ChildJoinPageState extends ConsumerState<ChildJoinPage> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _controller.text.trim();
    if (code.length < 6) {
      setState(() => _error = '请输入家人告诉您的 6 位邀请码。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(familyApiProvider).joinFamily(code);
      await _goHomeAfterJoin(message: '已加入家庭。');
    } catch (error) {
      if (!mounted) return;
      // 上次其实已绑定成功、只是首页没刷新时，按成功处理并拉最新状态
      if (error is ApiException && error.code == 'family.already_joined') {
        await _goHomeAfterJoin(message: '您已经加入家庭。');
        return;
      }
      setState(() {
        _busy = false;
        _error = error is ApiException
            ? error.message
            : '加入失败。您可以检查邀请码后重试，没有建立任何家庭关系。';
      });
    }
  }

  Future<void> _goHomeAfterJoin({required String message}) async {
    // /child 嵌套路由下首页仍挂载，必须刷新今日状态，否则会继续展示「未绑定」缓存
    ref.invalidate(familyInfoProvider);
    ref.invalidate(childTodayProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    context.go('/child');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CocoScaffold(
      title: '加入家庭',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '请输入父母念给您的 6 位邀请码。绑定后才能看到今日状态。也可以在家庭页生成邀请码请父母加入。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
          ),
          const SizedBox(height: CocoSpace.s6),
          CocoTextField(
            controller: _controller,
            label: '邀请码',
            hint: '例如 123456',
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _join(),
          ),
          if (_error != null) ...[
            const SizedBox(height: CocoSpace.s3),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: CocoColors.danger,
              ),
            ),
          ],
          const Spacer(),
          CocoPrimaryButton(
            label: '确认加入',
            loading: _busy,
            loadingLabel: '正在加入…',
            onPressed: _join,
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(label: '返回', onPressed: () => context.pop()),
        ],
      ),
    );
  }
}
