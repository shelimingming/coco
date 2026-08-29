import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/coco_button.dart';
import '../../../look/domain/screen_share_state.dart';

/// 看手机说明确认卡：大字、一屏一事。
class ParentScreenShareConfirmCard extends StatelessWidget {
  const ParentScreenShareConfirmCard({
    super.key,
    required this.onConfirm,
    required this.onCancel,
    this.onConfirmDontAskAgain,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onConfirmDontAskAgain;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CocoColors.white,
          borderRadius: BorderRadius.circular(CocoRadius.xl),
          boxShadow: const [
            BoxShadow(
              color: CocoColors.onboardingShadow,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(CocoSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '让可可看看你的手机',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: CocoColors.neutral950,
                ),
              ),
              const SizedBox(height: CocoSpace.s4),
              const Text(
                '会暂时看到整部手机屏幕，帮你看短信或教你点哪里。'
                '随时可以停止；验证码、支付页会自动停看。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.4,
                  color: CocoColors.neutral700,
                ),
              ),
              const SizedBox(height: CocoSpace.s5),
              CocoPrimaryButton(label: '开始看手机', onPressed: onConfirm),
              const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(label: '先不用', onPressed: onCancel),
              if (onConfirmDontAskAgain != null) ...[
                const SizedBox(height: CocoSpace.s2),
                TextButton(
                  onPressed: onConfirmDontAskAgain,
                  child: const Text(
                    '开始看手机，下次不再提醒',
                    style: TextStyle(
                      fontSize: 16,
                      color: CocoColors.neutral500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS 三步引导 + 系统广播选择器热区。
class ParentScreenShareIosGuide extends StatelessWidget {
  const ParentScreenShareIosGuide({super.key, this.onCancel});

  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CocoSpace.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CocoColors.white,
          borderRadius: BorderRadius.circular(CocoRadius.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(CocoSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '按提示打开看手机权限',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: CocoColors.neutral950,
                ),
              ),
              const SizedBox(height: CocoSpace.s4),
              const _GuideStep(index: '1', text: '选「可可看手机」'),
              const _GuideStep(index: '2', text: '点「开始直播」'),
              const _GuideStep(index: '3', text: '等 3 秒倒计时'),
              const SizedBox(height: CocoSpace.s4),
              // 系统选择器叠在大按钮热区上
              SizedBox(
                height: 64,
                child: !kIsWeb && Platform.isIOS
                    ? const UiKitView(
                        viewType: 'coco/broadcast_picker',
                        creationParamsCodec: StandardMessageCodec(),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: CocoSpace.s3),
              if (onCancel != null)
                CocoSecondaryButton(label: '先不用', onPressed: onCancel!),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CocoSpace.s3),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: CocoColors.parentPrimarySoft,
            child: Text(
              index,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: CocoColors.parentPrimary,
              ),
            ),
          ),
          const SizedBox(width: CocoSpace.s3),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: CocoColors.neutral950,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 投屏占用中间区时的状态条文案辅助。
String screenShareCloseLabel(ScreenSharePhase phase) {
  if (phase == ScreenSharePhase.blocked) return '知道了';
  if (phase == ScreenSharePhase.error) return '关闭';
  return '停止看手机';
}
