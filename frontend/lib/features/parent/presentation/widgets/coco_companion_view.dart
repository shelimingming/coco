import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../domain/coco_companion_pose.dart';

/// 父母端主视觉：按姿态展示 Coco 形象，后续可无感换成同路径动图。
class CocoCompanionView extends StatelessWidget {
  const CocoCompanionView({
    super.key,
    required this.pose,
    this.size = 280,
  });

  final CocoCompanionPose pose;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: pose.semanticLabel,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CocoRadius.xl),
        child: Image.asset(
          pose.assetPath,
          width: size,
          height: size,
          // 角色图带黑底，contain 保证全身可见；动图阶段可保持同一 fit
          fit: BoxFit.contain,
          alignment: Alignment.center,
          excludeFromSemantics: true,
          // 姿态切换时淡入，避免生硬跳切
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
