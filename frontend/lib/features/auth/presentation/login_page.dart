import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../application/auth_controller.dart';
import '../domain/models.dart';
import 'role_selection_page.dart';

/// 登录页：角色选择后，家长端暖色场景卡 / 子女端青绿简洁表单分版。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  /// 区分「发码」与「登录」加载，避免两处同时显示发送中。
  bool _requestingCode = false;
  bool _loggingIn = false;

  static const _parentBgAsset = 'assets/images/onboarding/login_room_bg.png';

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

    if (state.step == LoginStep.role) {
      return RoleSelectionPage(
        onSelected: (role) =>
            ref.read(authControllerProvider.notifier).selectRole(role),
      );
    }

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

    final form = _LoginFormHandlers(
      requestingCode: _requestingCode,
      loggingIn: _loggingIn,
      onRequestCode: _submitPhone,
      onLogin: _submitCode,
      onBackToRole: () =>
          ref.read(authControllerProvider.notifier).backToRole(),
    );

    if (state.selectedRole == UserRole.child) {
      return _ChildLoginScaffold(
        state: state,
        phoneController: _phoneController,
        codeController: _codeController,
        nameController: _nameController,
        handlers: form,
      );
    }

    return _ParentLoginScaffold(
      bgAsset: _parentBgAsset,
      state: state,
      phoneController: _phoneController,
      codeController: _codeController,
      nameController: _nameController,
      handlers: form,
    );
  }

  Future<void> _submitPhone() async {
    setState(() => _requestingCode = true);
    try {
      final phone = _phoneController.text.trim();
      await ref.read(authControllerProvider.notifier).requestCode(phone);
    } finally {
      if (mounted) setState(() => _requestingCode = false);
    }
  }

  Future<void> _submitCode() async {
    setState(() => _loggingIn = true);
    try {
      final code = _codeController.text.trim();
      final name = _nameController.text.trim();
      await ref
          .read(authControllerProvider.notifier)
          .verifyCode(code: code, displayName: name.isEmpty ? null : name);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }
}

class _LoginFormHandlers {
  const _LoginFormHandlers({
    required this.requestingCode,
    required this.loggingIn,
    required this.onRequestCode,
    required this.onLogin,
    required this.onBackToRole,
  });

  final bool requestingCode;
  final bool loggingIn;
  final VoidCallback onRequestCode;
  final VoidCallback onLogin;
  final VoidCallback onBackToRole;

  bool get formBusy => requestingCode || loggingIn;
}

/// 家长端：客厅模糊底 + 白卡内含主次按钮。
class _ParentLoginScaffold extends StatelessWidget {
  const _ParentLoginScaffold({
    required this.bgAsset,
    required this.state,
    required this.phoneController,
    required this.codeController,
    required this.nameController,
    required this.handlers,
  });

  final String bgAsset;
  final AuthState state;
  final TextEditingController phoneController;
  final TextEditingController codeController;
  final TextEditingController nameController;
  final _LoginFormHandlers handlers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: CocoColors.onboardingBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Image.asset(
              bgAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          const ColoredBox(color: CocoColors.loginScrim),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s6),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const Spacer(flex: 2),
                          Text(
                            '手机号登录',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: CocoSpace.s2),
                          Text(
                            '以「${state.selectedRole.label}」身份登录',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: CocoSpace.s6),
                          _ParentLoginCard(
                            state: state,
                            phoneController: phoneController,
                            codeController: codeController,
                            nameController: nameController,
                            handlers: handlers,
                          ),
                          const Spacer(flex: 3),
                          Padding(
                            padding: const EdgeInsets.only(
                              top: CocoSpace.s6,
                              bottom: CocoSpace.s5,
                            ),
                            child: Text(
                              '手机号仅用于登录和保障账号安全',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                color: CocoColors.neutral500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 子女端：浅灰底、左对齐标题、按钮在卡外、返回为文字链。
class _ChildLoginScaffold extends StatelessWidget {
  const _ChildLoginScaffold({
    required this.state,
    required this.phoneController,
    required this.codeController,
    required this.nameController,
    required this.handlers,
  });

  final AuthState state;
  final TextEditingController phoneController;
  final TextEditingController codeController;
  final TextEditingController nameController;
  final _LoginFormHandlers handlers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: CocoColors.childBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s6),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: CocoSpace.s8),
                      Text('手机号登录', style: theme.textTheme.titleLarge),
                      const SizedBox(height: CocoSpace.s2),
                      Text(
                        '以「子女」身份登录',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: CocoColors.neutral500,
                        ),
                      ),
                      const SizedBox(height: CocoSpace.s6),
                      _ChildFieldsCard(
                        state: state,
                        phoneController: phoneController,
                        codeController: codeController,
                        nameController: nameController,
                        handlers: handlers,
                      ),
                      const SizedBox(height: CocoSpace.s6),
                      CocoPrimaryButton(
                        label: '登录',
                        loading: handlers.loggingIn,
                        loadingLabel: '正在登录…',
                        onPressed: handlers.formBusy ? null : handlers.onLogin,
                      ),
                      const SizedBox(height: CocoSpace.s4),
                      Center(
                        child: TextButton(
                          onPressed: handlers.formBusy
                              ? null
                              : handlers.onBackToRole,
                          style: TextButton.styleFrom(
                            foregroundColor: CocoColors.childPrimary,
                            disabledForegroundColor: CocoColors.childPrimary
                                .withValues(alpha: 0.38),
                            textStyle: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: CocoColors.childPrimary,
                            ),
                          ),
                          child: const Text('返回选择身份'),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(bottom: CocoSpace.s5),
                        child: Text(
                          '手机号仅用于登录和保障账号安全',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            color: CocoColors.neutral500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ParentLoginCard extends StatelessWidget {
  const _ParentLoginCard({
    required this.state,
    required this.phoneController,
    required this.codeController,
    required this.nameController,
    required this.handlers,
  });

  final AuthState state;
  final TextEditingController phoneController;
  final TextEditingController codeController;
  final TextEditingController nameController;
  final _LoginFormHandlers handlers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const buttonHeight = 56.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        CocoSpace.s5,
        CocoSpace.s6,
        CocoSpace.s5,
        CocoSpace.s5,
      ),
      decoration: BoxDecoration(
        color: CocoColors.white,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        boxShadow: const [
          BoxShadow(
            color: CocoColors.onboardingShadow,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('手机号'),
          const SizedBox(height: CocoSpace.s2),
          _LoginTextField(
            controller: phoneController,
            hint: '请输入11位手机号',
            borderColor: CocoColors.loginFieldBorder,
            fillColor: CocoColors.white,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: CocoSpace.s5),
          const _FieldLabel('验证码'),
          const SizedBox(height: CocoSpace.s2),
          _CodeField(
            controller: codeController,
            borderColor: CocoColors.loginFieldBorder,
            fillColor: CocoColors.white,
            accentColor: scheme.primary,
            style: _CodeActionStyle.parentInline,
            requesting: handlers.requestingCode,
            enabled: !handlers.formBusy,
            onRequestCode: handlers.onRequestCode,
          ),
          ..._extraFields(
            context: context,
            state: state,
            nameController: nameController,
            isParent: true,
            borderColor: CocoColors.loginFieldBorder,
            fillColor: CocoColors.white,
          ),
          const SizedBox(height: CocoSpace.s6),
          Theme(
            data: theme.copyWith(
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(buttonHeight),
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  textStyle: theme.textTheme.labelLarge,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(CocoRadius.md),
                  ),
                ),
              ),
            ),
            child: CocoPrimaryButton(
              label: '登录',
              loading: handlers.loggingIn,
              loadingLabel: '正在登录…',
              onPressed: handlers.formBusy ? null : handlers.onLogin,
            ),
          ),
          const SizedBox(height: CocoSpace.s3),
          OutlinedButton(
            onPressed: handlers.formBusy ? null : handlers.onBackToRole,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(buttonHeight),
              foregroundColor: scheme.primary,
              disabledForegroundColor: scheme.primary.withValues(alpha: 0.38),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
              ),
              side: BorderSide(color: scheme.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CocoRadius.md),
              ),
            ),
            child: const Text('返回选择身份'),
          ),
        ],
      ),
    );
  }
}

/// 子女端白卡：仅表单字段，主按钮在卡外。
class _ChildFieldsCard extends StatelessWidget {
  const _ChildFieldsCard({
    required this.state,
    required this.phoneController,
    required this.codeController,
    required this.nameController,
    required this.handlers,
  });

  final AuthState state;
  final TextEditingController phoneController;
  final TextEditingController codeController;
  final TextEditingController nameController;
  final _LoginFormHandlers handlers;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        CocoSpace.s5,
        CocoSpace.s5,
        CocoSpace.s5,
        CocoSpace.s5,
      ),
      decoration: BoxDecoration(
        color: CocoColors.white,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        boxShadow: const [
          BoxShadow(
            color: CocoColors.onboardingShadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FieldLabel('手机号', muted: true),
          const SizedBox(height: CocoSpace.s2),
          _LoginTextField(
            controller: phoneController,
            hint: '请输入11位手机号',
            borderColor: CocoColors.childBorder,
            fillColor: CocoColors.childBackground,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: CocoSpace.s5),
          const _FieldLabel('验证码', muted: true),
          const SizedBox(height: CocoSpace.s2),
          _CodeField(
            controller: codeController,
            borderColor: CocoColors.childBorder,
            fillColor: CocoColors.childBackground,
            accentColor: CocoColors.childPrimary,
            style: _CodeActionStyle.childChip,
            requesting: handlers.requestingCode,
            enabled: !handlers.formBusy,
            onRequestCode: handlers.onRequestCode,
          ),
          ..._extraFields(
            context: context,
            state: state,
            nameController: nameController,
            isParent: false,
            borderColor: CocoColors.childBorder,
            fillColor: CocoColors.childBackground,
          ),
        ],
      ),
    );
  }
}

List<Widget> _extraFields({
  required BuildContext context,
  required AuthState state,
  required TextEditingController nameController,
  required bool isParent,
  required Color borderColor,
  required Color fillColor,
}) {
  final theme = Theme.of(context);
  final widgets = <Widget>[];

  if (state.challenge?.isRegistered == false) {
    widgets.addAll([
      const SizedBox(height: CocoSpace.s5),
      _FieldLabel('怎么称呼您', muted: !isParent),
      const SizedBox(height: CocoSpace.s2),
      _LoginTextField(
        controller: nameController,
        hint: isParent ? '例如：张阿姨' : '例如：小林',
        borderColor: borderColor,
        fillColor: fillColor,
        maxLength: 20,
      ),
    ]);
  }

  if (state.challenge?.devCode != null) {
    widgets.addAll([
      const SizedBox(height: CocoSpace.s4),
      Container(
        padding: const EdgeInsets.all(CocoSpace.s3),
        decoration: BoxDecoration(
          color: isParent
              ? CocoColors.parentPrimarySoft
              : CocoColors.childPrimarySoft,
          borderRadius: BorderRadius.circular(CocoRadius.md),
        ),
        child: Text(
          '开发验证码：${state.challenge!.devCode}',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    ]);
  }

  if (state.errorMessage != null) {
    widgets.addAll([
      const SizedBox(height: CocoSpace.s3),
      Text(
        state.errorMessage!,
        style: theme.textTheme.bodyMedium?.copyWith(color: CocoColors.danger),
      ),
    ]);
  }

  return widgets;
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: muted ? CocoColors.neutral700 : CocoColors.neutral950,
      ),
    );
  }
}

/// 标签在框外的输入框；子女端用浅底，家长端白底描边。
class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.hint,
    required this.borderColor,
    required this.fillColor,
    this.keyboardType,
    this.maxLength,
    this.autofocus = false,
    this.inputFormatters,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hint;
  final Color borderColor;
  final Color fillColor;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      autofocus: autofocus,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: CocoColors.neutral500,
        ),
        counterText: '',
        filled: true,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CocoSpace.s4,
          vertical: CocoSpace.s4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoRadius.md),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoRadius.md),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoRadius.md),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}

enum _CodeActionStyle { parentInline, childChip }

/// 验证码输入 + 「获取验证码」；子女端为青绿软底小按钮。
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.borderColor,
    required this.fillColor,
    required this.accentColor,
    required this.style,
    required this.requesting,
    required this.enabled,
    required this.onRequestCode,
  });

  final TextEditingController controller;
  final Color borderColor;
  final Color fillColor;
  final Color accentColor;
  final _CodeActionStyle style;
  final bool requesting;
  final bool enabled;
  final VoidCallback onRequestCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isChildChip = style == _CodeActionStyle.childChip;

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: '请输入验证码',
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: CocoColors.neutral500,
                ),
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: CocoSpace.s4,
                  vertical: CocoSpace.s4,
                ),
              ),
            ),
          ),
          if (!isChildChip) Container(width: 1, height: 28, color: borderColor),
          Padding(
            padding: EdgeInsets.only(right: isChildChip ? CocoSpace.s2 : 0),
            child: isChildChip
                ? _ChildGetCodeChip(
                    requesting: requesting,
                    enabled: enabled,
                    onPressed: onRequestCode,
                  )
                : TextButton(
                    onPressed: enabled ? onRequestCode : null,
                    style: TextButton.styleFrom(
                      foregroundColor: accentColor,
                      disabledForegroundColor: accentColor.withValues(
                        alpha: 0.4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CocoSpace.s4,
                      ),
                      minimumSize: const Size(0, 52),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: requesting
                        ? CocoLoadingLabel(
                            label: '发送中…',
                            indicatorColor: accentColor,
                          )
                        : Text(
                            '获取验证码',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 子女端「获取验证码」：浅绿底 + 青绿字，对齐交付稿。
class _ChildGetCodeChip extends StatelessWidget {
  const _ChildGetCodeChip({
    required this.requesting,
    required this.enabled,
    required this.onPressed,
  });

  final bool requesting;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CocoColors.childPrimarySoft,
      borderRadius: BorderRadius.circular(CocoRadius.md),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CocoSpace.s3,
            vertical: CocoSpace.s2,
          ),
          child: requesting
              ? const CocoLoadingLabel(
                  label: '发送中…',
                  indicatorColor: CocoColors.childPrimary,
                )
              : Text(
                  '获取验证码',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: enabled
                        ? CocoColors.childPrimary
                        : CocoColors.childPrimary.withValues(alpha: 0.4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}
