import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/web/presentation_slot.dart';
import '../application/auth_controller.dart';
import '../domain/models.dart';
import 'role_selection_page.dart';
import 'widgets/phone_login_form.dart';

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

  /// presentation 双端演示：进入登录表单后填号、发码只跑一次（仍先展示身份选择）。
  bool _presentationAutofillDone = false;

  static const _parentBgAsset = 'assets/images/onboarding/login_room_bg.png';
  static const _presentationParentPhone = '13811111111';
  static const _presentationChildPhone = '13822222222';

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

    // 演示 iframe：身份选完后再预填手机号并自动获取验证码
    _schedulePresentationAutofill(state);

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

    final form = PhoneLoginFormHandlers(
      requestingCode: _requestingCode,
      loggingIn: _loggingIn,
      onRequestCode: _submitPhone,
      onLogin: _submitCode,
      onBackToRole: () =>
          ref.read(authControllerProvider.notifier).backToRole(),
    );

    if (state.selectedRole == UserRole.child) {
      return ChildLoginScaffold(
        state: state,
        phoneController: _phoneController,
        codeController: _codeController,
        nameController: _nameController,
        handlers: form,
      );
    }

    return ParentLoginScaffold(
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

  void _schedulePresentationAutofill(AuthState state) {
    if (readPresentationSlot() == null) return;
    if (state.isAuthenticated) return;
    // 回到身份选择后允许再次自动填号发码
    if (state.step == LoginStep.role) {
      _presentationAutofillDone = false;
      return;
    }
    if (_presentationAutofillDone) return;
    if (state.step != LoginStep.phone) return;

    _presentationAutofillDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runPresentationAutofill(state.selectedRole);
    });
  }

  Future<void> _runPresentationAutofill(UserRole role) async {
    final phone = role == UserRole.child
        ? _presentationChildPhone
        : _presentationParentPhone;

    if (_phoneController.text.trim().isEmpty) {
      _phoneController.text = phone;
    }
    // 尚未发过码时自动点「获取验证码」（开发环境会回填固定码）
    if (ref.read(authControllerProvider).challenge == null &&
        !_requestingCode) {
      await _submitPhone();
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
