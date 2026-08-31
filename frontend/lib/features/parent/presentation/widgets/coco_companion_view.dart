import 'package:flutter/material.dart';

import '../../domain/coco_companion_pose.dart';

/// 父母端主视觉：按姿态播放 Coco gif（Flutter Image.asset 原生支持循环）。
class CocoCompanionView extends StatelessWidget {
  const CocoCompanionView({super.key, required this.pose, this.size = 280});

  final CocoCompanionPose pose;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: pose.semanticLabel,
      image: true,
      // 固定正方形，避免父级竖向紧约束把 gif 居中后爪底下移
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          pose.assetPath,
          // gif 为透明底全身角色，contain 保证不裁切耳朵/尾巴
          fit: BoxFit.contain,
          // 出场从右走进：贴右对齐，减少画布右侧透明空隙
          alignment: pose == CocoCompanionPose.entrance
              ? Alignment.centerRight
              : Alignment.center,
          excludeFromSemantics: true,
          // 姿态切换时保留上一帧，避免闪一下空位
          gaplessPlayback: true,
          // 按姿态 key 强制重建，确保切换到新 gif 时从首帧重播
          key: ValueKey(pose.assetPath),
        ),
      ),
    );
  }
}
