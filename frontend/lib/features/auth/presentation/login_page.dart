import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../../core/widgets/coco_text_field.dart';
import '../application/auth_controller.dart';
import '../domain/models.dart';

/// 登录页：角色选择 → 手机号 → 验证码，页面内 step 切换。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    // 开发环境自动填入验证码
    final devCode = state.challenge?.devCode;
    if (devCode != null &&
        state.step == LoginStep.code &&
        _codeController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_codeController.text.isEmpty) {
          _codeController.text = devCode;
        }
      });
    }

    return CocoScaffold(
      title: _titleFor(state.step),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _subtitleFor(state),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: CocoSpace.s8),
          Expanded(child: _buildStep(state)),
          if (state.errorMessage != null) ...[
            const SizedBox(height: CocoSpace.s4),
            Text(
              state.errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: CocoColors.danger,
              ),
            ),
          ],
        ],
      ),
      bottom: _buildBottom(state),
    );
  }

  String _titleFor(LoginStep step) {
    switch (step) {
      case LoginStep.role:
        return '欢迎使用可可';
      case LoginStep.phone:
        return '手机号登录';
      case LoginStep.code:
        return '填写验证码';
    }
  }

  String _subtitleFor(AuthState state) {
    switch (state.step) {
      case LoginStep.role:
        return '请先选择您的身份，之后可以用手机号登录。';
      case LoginStep.phone:
        return '以「${state.selectedRole.label}」身份登录。';
      case LoginStep.code:
        return state.challenge?.isRegistered == false
            ? '验证码已发送。如果是第一次使用，请顺便告诉我怎么称呼您。'
            : '验证码已发送到 ${state.phone}。';
    }
  }

  Widget _buildStep(AuthState state) {
    switch (state.step) {
      case LoginStep.role:
        return _RoleStep(
          selected: state.selectedRole,
          onSelected: (role) =>
              ref.read(authControllerProvider.notifier).selectRole(role),
        );
      case LoginStep.phone:
        return CocoTextField(
          controller: _phoneController,
          label: '手机号',
          hint: '请输入 11 位手机号',
          keyboardType: TextInputType.phone,
          maxLength: 11,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitPhone(),
        );
      case LoginStep.code:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CocoTextField(
              controller: _codeController,
              label: '验证码',
              hint: '6 位数字',
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            if (state.challenge?.isRegistered == false) ...[
              const SizedBox(height: CocoSpace.s5),
              CocoTextField(
                controller: _nameController,
                label: '怎么称呼您',
                hint: state.selectedRole == UserRole.parent ? '例如：张阿姨' : '例如：小林',
                maxLength: 20,
              ),
            ],
            if (state.challenge?.devCode != null) ...[
              const SizedBox(height: CocoSpace.s5),
              Container(
                padding: const EdgeInsets.all(CocoSpace.s4),
                decoration: BoxDecoration(
                  // 随当前身份主题变化，不写死父母暖色
                  color: state.selectedRole == UserRole.child
                      ? CocoColors.childPrimarySoft
                      : CocoColors.parentPrimarySoft,
                  borderRadius: BorderRadius.circular(CocoRadius.md),
                ),
                child: Text(
                  '开发验证码：${state.challenge!.devCode}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        );
    }
  }

  Widget? _buildBottom(AuthState state) {
    switch (state.step) {
      case LoginStep.role:
        return null;
      case LoginStep.phone:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CocoPrimaryButton(
              label: '获取验证码',
              loading: state.isBusy,
              loadingLabel: '正在发送…',
              onPressed: _submitPhone,
            ),
            const SizedBox(height: CocoSpace.s3),
            CocoSecondaryButton(
              label: '返回选择身份',
              onPressed: state.isBusy
                  ? null
                  : () => ref.read(authControllerProvider.notifier).backToRole(),
            ),
          ],
        );
      case LoginStep.code:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CocoPrimaryButton(
              label: '登录',
              loading: state.isBusy,
              loadingLabel: '正在登录…',
              onPressed: _submitCode,
            ),
            const SizedBox(height: CocoSpace.s3),
            CocoSecondaryButton(
              label: '返回修改手机号',
              onPressed: state.isBusy
                  ? null
                  : () {
                      _codeController.clear();
                      ref.read(authControllerProvider.notifier).backToPhone();
                    },
            ),
          ],
        );
    }
  }

  Future<void> _submitPhone() async {
    final phone = _phoneController.text.trim();
    await ref.read(authControllerProvider.notifier).requestCode(phone);
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    await ref.read(authControllerProvider.notifier).verifyCode(
          code: code,
          displayName: name.isEmpty ? null : name,
        );
  }
}

class _RoleStep extends StatelessWidget {
  const _RoleStep({
    required this.selected,
    required this.onSelected,
  });

  final UserRole selected;
  final ValueChanged<UserRole> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RoleCard(
          title: '我是父母',
          subtitle: '和大字号、语音优先的可可聊天',
          selected: selected == UserRole.parent,
          color: CocoColors.parentPrimary,
          softColor: CocoColors.parentPrimarySoft,
          onTap: () => onSelected(UserRole.parent),
        ),
        const SizedBox(height: CocoSpace.s5),
        _RoleCard(
          title: '我是子女',
          subtitle: '快速了解父母今天是否安稳',
          selected: selected == UserRole.child,
          color: CocoColors.childPrimary,
          softColor: CocoColors.childPrimarySoft,
          onTap: () => onSelected(UserRole.child),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.softColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final Color color;
  final Color softColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? softColor : CocoColors.white,
      borderRadius: BorderRadius.circular(CocoRadius.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(CocoSpace.s6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CocoRadius.xl),
            border: Border.all(
              color: selected ? color : CocoColors.neutral300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                    ),
              ),
              const SizedBox(height: CocoSpace.s2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
