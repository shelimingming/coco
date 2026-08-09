import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/coco_companion_pose.dart';

/// 首页陪伴形象当前姿态；语音/提醒流程后续在此切换，默认待机。
final cocoCompanionPoseProvider = StateProvider<CocoCompanionPose>(
  (ref) => CocoCompanionPose.idle,
);
