import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/tokens.dart';
import '../domain/models.dart';

/// 首次进入 App 的身份选择：门前场景 + 气泡文案 + 两项选择。
/// 文案与布局对齐 `doc/可可_UI完整交付_v1`；场景图不含按钮文字。
class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key, required this.onSelected});

  final ValueChanged<UserRole> onSelected;

  static const _sceneAsset = 'assets/images/onboarding/role_door_scene.png';
  static const _parentIconAsset =
      'assets/icons/onboarding/icon_role_parent.svg';
  static const _childIconAsset = 'assets/icons/onboarding/icon_role_child.svg';

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: CocoColors.onboardingBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 全屏门前场景，按钮叠在场景底部之上
          Image.asset(
            _sceneAsset,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.12),
          ),
          // 中下渐变：场景淡入奶油底，避免硬切
          const Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              child: SizedBox(
                height: 320,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        CocoColors.onboardingFadeStart,
                        CocoColors.onboardingFadeMid,
                        CocoColors.onboardingFadeStrong,
                        CocoColors.onboardingBackground,
                      ],
                      stops: [0.0, 0.35, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  CocoSpace.s5,
                  CocoSpace.s3,
                  CocoSpace.s6,
                  0,
                ),
                child: const _IntroBubble(),
              ),
            ),
          ),
          // 按钮上移：贴近渐变中段，底部留白更大
          Positioned(
            left: CocoSpace.s6,
            right: CocoSpace.s6,
            bottom: CocoSpace.s10 + bottomInset,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RoleOptionButton(
                  label: '我是家长',
                  iconAsset: _parentIconAsset,
                  iconColor: CocoColors.parentPrimary,
                  iconBackground: CocoColors.parentPrimarySoft,
                  onTap: () => onSelected(UserRole.parent),
                ),
                const SizedBox(height: CocoSpace.s4),
                _RoleOptionButton(
                  label: '我是子女',
                  iconAsset: _childIconAsset,
                  iconColor: CocoColors.childPrimary,
                  iconBackground: CocoColors.childPrimarySoft,
                  onTap: () => onSelected(UserRole.child),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 更宽、更透的介绍气泡，轻阴影不压过身份选择。
class _IntroBubble extends StatelessWidget {
  const _IntroBubble();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          // 放宽气泡，减少右侧留白
          constraints: const BoxConstraints(maxWidth: 340),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            CocoSpace.s5,
            CocoSpace.s4,
            CocoSpace.s5,
            CocoSpace.s5,
          ),
          decoration: BoxDecoration(
            color: CocoColors.onboardingBubble,
            borderRadius: BorderRadius.circular(CocoRadius.xl),
            boxShadow: const [
              BoxShadow(
                color: CocoColors.onboardingShadow,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '您好，我是AI陪伴宠物可可',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: CocoColors.neutral950,
                ),
              ),
              SizedBox(height: CocoSpace.s2),
              Text(
                '您是家长，还是子女？',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                  color: CocoColors.neutral700,
                ),
              ),
            ],
          ),
        ),
        // 朝向可可一侧的小三角尾巴
        const Positioned(
          right: 72,
          bottom: -8,
          child: CustomPaint(
            size: Size(18, 10),
            painter: _BubbleTailPainter(color: CocoColors.onboardingBubble),
          ),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.45, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _RoleOptionButton extends StatelessWidget {
  const _RoleOptionButton({
    required this.label,
    required this.iconAsset,
    required this.iconColor,
    required this.iconBackground,
    required this.onTap,
  });

  final String label;
  final String iconAsset;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CocoColors.white,
      elevation: 2,
      shadowColor: CocoColors.onboardingShadow,
      borderRadius: BorderRadius.circular(CocoRadius.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(
            horizontal: CocoSpace.s5,
            vertical: CocoSpace.s4,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBackground,
                  shape: BoxShape.circle,
                ),
                // 单色描边图标按角色主色着色，不改 SVG 源文件
                child: SvgPicture.asset(
                  iconAsset,
                  width: 28,
                  height: 28,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                ),
              ),
              const SizedBox(width: CocoSpace.s4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: CocoColors.neutral950,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: CocoColors.neutral500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
