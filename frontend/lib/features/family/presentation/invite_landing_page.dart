import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/models.dart';
import '../../auth/presentation/widgets/phone_login_form.dart';
import '../application/family_providers.dart';
import '../data/family_api.dart';
import '../domain/models.dart';
import '../../care/application/care_providers.dart';

/// 邀请链接落地：预览 → 按目标角色登录 → 用户确认后加入家庭。
class InviteLandingPage extends ConsumerStatefulWidget {
  const InviteLandingPage({super.key, required this.code});

  final String code;

  @override
  ConsumerState<InviteLandingPage> createState() => _InviteLandingPageState();
}

class _InviteLandingPageState extends ConsumerState<InviteLandingPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  FamilyInvitePreview? _preview;
  bool _loadingPreview = true;
  bool _joining = false;
  bool _joined = false;
  bool _requestingCode = false;
  bool _loggingIn = false;
  String? _error;

  static const _parentBgAsset = 'assets/images/onboarding/login_room_bg.png';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pendingInviteCodeProvider.notifier).state = widget.code;
      _loadPreview();
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  UserRole? get _targetRole {
    final raw = _preview?.targetRole;
    if (raw == 'parent') return UserRole.parent;
    if (raw == 'child') return UserRole.child;
    return null;
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loadingPreview = true;
      _error = null;
    });
    try {
      final preview = await ref
          .read(familyApiProvider)
          .previewInvite(widget.code);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loadingPreview = false;
      });
      final role = _targetRole;
      if (preview.isValid && role != null && !ref.read(authControllerProvider).isAuthenticated) {
        // 预设身份，跳过选角色，并让全局主题切到对应端
        ref.read(authControllerProvider.notifier).selectRole(role);
      }
      // 已登录也须用户点「加入家庭」才绑定，避免误触链接即建立关系
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPreview = false;
        _error = error is ApiException ? error.message : '邀请信息加载失败。您可以再试一次。';
      });
    }
  }

  Future<void> _join() async {
    if (_joining || _joined) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await ref.read(familyApiProvider).joinFamily(widget.code);
      ref.invalidate(familyInfoProvider);
      ref.invalidate(childTodayProvider);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joined = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = error is ApiException
            ? error.message
            : '加入失败。您可以再试一次，没有建立任何家庭关系。';
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

  Future<void> _submitCode() async {
    setState(() => _loggingIn = true);
    try {
      final name = _nameController.text.trim();
      await ref.read(authControllerProvider.notifier).verifyCode(
            code: _codeController.text.trim(),
            displayName: name.isEmpty ? null : name,
          );
      // 登录成功后切到确认页，由用户点「加入家庭」再绑定
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _goHome() {
    final role = ref.read(authControllerProvider).user?.role ?? _targetRole;
    context.go(role == UserRole.child ? '/child' : '/parent');
  }

  /// 当前账号已 active 绑定，且与这份邀请不是同一家庭。
  bool _boundToOtherFamily(FamilyInfo? family, FamilyInvitePreview preview) {
    if (family == null || !family.isActive || preview.familyId == null) {
      return false;
    }
    return family.id != preview.familyId;
  }

  /// 已是这份邀请对应的家庭成员（重复打开链接）。
  bool _alreadyInInviteFamily(FamilyInfo? family, FamilyInvitePreview preview) {
    if (family == null || !family.isActive || preview.familyId == null) {
      return false;
    }
    return family.id == preview.familyId;
  }

  String _currentPartnerName(FamilyInfo family, UserRole? role) {
    if (role == UserRole.child) {
      return family.parentDisplayName ?? '父母';
    }
    return family.childDisplayName ?? '子女';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final familyAsync = auth.isAuthenticated ? ref.watch(familyInfoProvider) : null;
    if (!auth.isBootstrapped || _loadingPreview) {
      return const CocoScaffold(
        title: '加入家庭',
        body: CocoPageLoading(message: '正在打开邀请…'),
      );
    }

    final preview = _preview;
    if (preview == null || !preview.isValid) {
      return CocoScaffold(
        title: '加入家庭',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              preview?.status == 'consumed'
                  ? '这个邀请链接已经用过了。请让家人重新发一条，现在还没有建立任何家庭关系。'
                  : (_error ?? '这个邀请链接无效。请让家人重新发一条。'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(label: '返回', onPressed: () => context.go('/login')),
          ],
        ),
      );
    }

    if (_joined) {
      final name = preview.inviterDisplayName ?? '家人';
      return CocoScaffold(
        title: '加入家庭',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('已经和$name成为家人了', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: CocoSpace.s3),
            Text(
              '若在微信里打开，语音功能可能不可用。请点右上角，选择在浏览器中打开。',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: CocoColors.neutral700,
                  ),
            ),
            const Spacer(),
            CocoPrimaryButton(label: '开始使用', onPressed: _goHome),
          ],
        ),
      );
    }

    if (auth.isAuthenticated && familyAsync != null) {
      return familyAsync.when(
        loading: () => const CocoScaffold(
          title: '加入家庭',
          body: CocoPageLoading(message: '正在检查绑定状态…'),
        ),
        error: (error, _) => CocoScaffold(
          title: '加入家庭',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                error is ApiException
                    ? error.message
                    : '绑定状态加载失败。您可以再试一次。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              CocoPrimaryButton(
                label: '再试一次',
                onPressed: () => ref.invalidate(familyInfoProvider),
              ),
            ],
          ),
        ),
        data: (family) {
          if (_alreadyInInviteFamily(family, preview)) {
            final name = preview.inviterDisplayName ?? '家人';
            return CocoScaffold(
              title: '加入家庭',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '您已经和$name是家人了',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  CocoPrimaryButton(label: '返回首页', onPressed: _goHome),
                ],
              ),
            );
          }

          if (_boundToOtherFamily(family, preview)) {
            final partner = _currentPartnerName(
              family!,
              auth.user?.role ?? _targetRole,
            );
            final inviter = preview.inviterDisplayName ?? '家人';
            return CocoScaffold(
              title: '加入家庭',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '您已经绑定了$partner',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: CocoSpace.s3),
                  Text(
                    '如需接受$inviter的邀请，请先在 App 家庭页解除当前绑定，再打开链接加入。',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: CocoColors.neutral700,
                        ),
                  ),
                  const Spacer(),
                  CocoPrimaryButton(label: '返回首页', onPressed: _goHome),
                ],
              ),
            );
          }

          if (_joining) {
            return const CocoScaffold(
              title: '加入家庭',
              body: CocoPageLoading(message: '正在加入家庭…'),
            );
          }

          return CocoScaffold(
            title: '加入家庭',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${preview.inviterDisplayName ?? '家人'} 邀请您成为家人',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: CocoSpace.s3),
                Text(
                  '绑定后可以分享近况、提醒和报平安。详细权限由长辈决定。',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: CocoColors.neutral700,
                      ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: CocoSpace.s3),
                  Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: CocoColors.danger,
                        ),
                  ),
                ],
                const Spacer(),
                CocoPrimaryButton(label: '加入家庭', onPressed: _join),
              ],
            ),
          );
        },
      );
    }

    if (_joining) {
      return const CocoScaffold(
        title: '加入家庭',
        body: CocoPageLoading(message: '正在加入家庭…'),
      );
    }

    final devCode = auth.challenge?.devCode;
    if (devCode != null && _codeController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_codeController.text.isEmpty) {
          _codeController.text = devCode;
        }
      });
    }

    final handlers = PhoneLoginFormHandlers(
      requestingCode: _requestingCode,
      loggingIn: _loggingIn,
      onRequestCode: _submitPhone,
      onLogin: _submitCode,
      onBackToRole: () {},
      showBackToRole: false,
    );

    final isChild = _targetRole == UserRole.child;
    if (isChild) {
      return ChildLoginScaffold(
        state: auth,
        phoneController: _phoneController,
        codeController: _codeController,
        nameController: _nameController,
        handlers: handlers,
      );
    }
    return ParentLoginScaffold(
      bgAsset: _parentBgAsset,
      state: auth,
      phoneController: _phoneController,
      codeController: _codeController,
      nameController: _nameController,
      handlers: handlers,
    );
  }
}
