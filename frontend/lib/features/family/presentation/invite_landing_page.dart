import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_safe_area.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/models.dart';
import '../application/family_providers.dart';
import '../data/family_api.dart';
import '../domain/models.dart';

/// 邀请链接落地页：预览 → 登录 → 一键接受 → 成功。
class InviteLandingPage extends ConsumerStatefulWidget {
  const InviteLandingPage({super.key, required this.token});

  final String token;

  @override
  ConsumerState<InviteLandingPage> createState() => _InviteLandingPageState();
}

enum _InvitePhase { loading, invalid, ready, joining, success }

class _InviteLandingPageState extends ConsumerState<InviteLandingPage> {
  FamilyInvitePreview? _preview;
  _InvitePhase _phase = _InvitePhase.loading;
  String? _pageError;

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _requestingCode = false;
  bool _loggingIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _phase = _InvitePhase.loading;
      _pageError = null;
    });
    try {
      final preview = await ref
          .read(familyApiProvider)
          .previewInvite(widget.token);
      if (!mounted) return;
      final role = UserRole.fromJson(preview.targetRole);
      ref.read(authControllerProvider.notifier).beginInviteFlow(role);
      setState(() {
        _preview = preview;
        _phase = _InvitePhase.ready;
      });
      final auth = ref.read(authControllerProvider);
      if (auth.isAuthenticated && auth.user!.role != role) {
        setState(() {
          _pageError = '您当前登录身份与邀请不匹配，请先退出再用「${role.label}」身份登录。';
        });
        return;
      }
      // 已登录且角色匹配时直接尝试接受
      if (auth.isAuthenticated && auth.user!.role == role) {
        await _acceptInvite();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _InvitePhase.invalid;
        _pageError = error is ApiException
            ? error.message
            : '邀请链接无法打开。请向家人重新索取。';
      });
    }
  }

  Future<void> _submitPhone() async {
    setState(() => _requestingCode = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .requestCode(_phoneController.text.trim());
    } finally {
      if (mounted) setState(() => _requestingCode = false);
    }
  }

  Future<void> _submitLogin() async {
    setState(() => _loggingIn = true);
    try {
      final ok = await ref
          .read(authControllerProvider.notifier)
          .verifyCode(
            code: _codeController.text.trim(),
            displayName: _nameController.text.trim().isEmpty
                ? null
                : _nameController.text.trim(),
          );
      if (!mounted || !ok) return;
      await _acceptInvite();
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _acceptInvite() async {
    setState(() {
      _phase = _InvitePhase.joining;
      _pageError = null;
    });
    try {
      await ref.read(familyApiProvider).joinFamily(widget.token);
      if (!mounted) return;
      ref.invalidate(familyInfoProvider);
      ref.read(authControllerProvider.notifier).endInviteFlow();
      setState(() => _phase = _InvitePhase.success);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _InvitePhase.ready;
        _pageError = error is ApiException
            ? error.message
            : '加入家庭没成功。您可以再试一次，数据没有受影响。';
      });
    }
  }

  UserRole? get _targetRole {
    final role = _preview?.targetRole;
    if (role == null) return null;
    return UserRole.fromJson(role);
  }

  bool get _isParent => _targetRole == UserRole.parent;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final preview = _preview;
    final role = _targetRole;

    // 开发环境自动填入验证码
    final devCode = auth.challenge?.devCode;
    if (devCode != null &&
        auth.step == LoginStep.code &&
        _codeController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_codeController.text.isEmpty) {
          _codeController.text = devCode;
        }
      });
    }

    final bg = _isParent
        ? CocoColors.parentBackground
        : CocoColors.childBackground;
    final accent = _isParent
        ? CocoColors.parentPrimary
        : CocoColors.childPrimary;

    return Scaffold(
      backgroundColor: bg,
      body: CocoSafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s6),
          child: switch (_phase) {
            _InvitePhase.loading => const Center(child: CocoPageLoading()),
            _InvitePhase.invalid => _InvalidBody(message: _pageError ?? ''),
            _InvitePhase.joining => const Center(
              child: CocoLoadingLabel(label: '正在加入家庭…'),
            ),
            _InvitePhase.success => _SuccessBody(
              isParent: _isParent,
              onContinue: () {
                final home = _isParent ? '/parent' : '/child';
                context.go(home);
              },
            ),
            _InvitePhase.ready when preview != null && role != null =>
              _ReadyBody(
                preview: preview,
                role: role,
                isParent: _isParent,
                accent: accent,
                auth: auth,
                phoneController: _phoneController,
                codeController: _codeController,
                nameController: _nameController,
                requestingCode: _requestingCode,
                loggingIn: _loggingIn,
                pageError: _pageError ?? auth.errorMessage,
                onRequestCode: _submitPhone,
                onLogin: _submitLogin,
                onAccept: auth.isAuthenticated ? _acceptInvite : null,
              ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

class _InvalidBody extends StatelessWidget {
  const _InvalidBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        Text('邀请链接不可用', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: CocoSpace.s4),
        Text(message, style: Theme.of(context).textTheme.bodyLarge),
        const Spacer(flex: 3),
      ],
    );
  }
}

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({required this.isParent, required this.onContinue});

  final bool isParent;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 2),
        Text('绑定成功', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: CocoSpace.s4),
        Text(
          isParent ? '您已和子女建立家庭连接。' : '您已和父母建立家庭连接。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const Spacer(flex: 3),
        CocoPrimaryButton(label: '进入可可', onPressed: onContinue),
      ],
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({
    required this.preview,
    required this.role,
    required this.isParent,
    required this.accent,
    required this.auth,
    required this.phoneController,
    required this.codeController,
    required this.nameController,
    required this.requestingCode,
    required this.loggingIn,
    required this.pageError,
    required this.onRequestCode,
    required this.onLogin,
    required this.onAccept,
  });

  final FamilyInvitePreview preview;
  final UserRole role;
  final bool isParent;
  final Color accent;
  final AuthState auth;
  final TextEditingController phoneController;
  final TextEditingController codeController;
  final TextEditingController nameController;
  final bool requestingCode;
  final bool loggingIn;
  final String? pageError;
  final VoidCallback onRequestCode;
  final VoidCallback onLogin;
  final Future<void> Function()? onAccept;

  bool get _formBusy => requestingCode || loggingIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleLabel = role.label;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: CocoSpace.s8),
          Text(
            '${preview.inviterDisplayName} 邀请您',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CocoSpace.s3),
          Text(
            '加入后可${isParent ? '与子女互相关怀' : '查看父母近况、报平安'}。\n将以「$roleLabel」身份登录并绑定。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: CocoColors.neutral700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CocoSpace.s6),
          if (auth.isAuthenticated && onAccept != null) ...[
            CocoPrimaryButton(label: '接受邀请', onPressed: onAccept),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(CocoSpace.s5),
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
                children: [
                  Text('手机号登录', style: theme.textTheme.titleMedium),
                  const SizedBox(height: CocoSpace.s4),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '手机号',
                      hintText: '请输入11位手机号',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s4),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: '验证码',
                      hintText: '请输入验证码',
                      counterText: '',
                      suffixIcon: TextButton(
                        onPressed: _formBusy ? null : onRequestCode,
                        child: requestingCode
                            ? CocoLoadingLabel(
                                label: '发送中…',
                                indicatorColor: accent,
                              )
                            : Text('获取验证码', style: TextStyle(color: accent)),
                      ),
                    ),
                  ),
                  if (auth.challenge?.isRegistered == false) ...[
                    const SizedBox(height: CocoSpace.s4),
                    TextField(
                      controller: nameController,
                      maxLength: 20,
                      decoration: InputDecoration(
                        labelText: '怎么称呼您',
                        hintText: isParent ? '例如：张阿姨' : '例如：小林',
                        counterText: '',
                      ),
                    ),
                  ],
                  if (pageError != null) ...[
                    const SizedBox(height: CocoSpace.s3),
                    Text(
                      pageError!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: CocoColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: CocoSpace.s5),
                  CocoPrimaryButton(
                    label: '登录并接受邀请',
                    loading: loggingIn,
                    loadingLabel: '正在登录…',
                    onPressed: _formBusy ? null : onLogin,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: CocoSpace.s8),
        ],
      ),
    );
  }
}
