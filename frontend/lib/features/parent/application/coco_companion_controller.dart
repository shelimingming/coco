import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/coco_companion_pose.dart';

/// 首页陪伴形象当前姿态；默认待机，进首页时再切入场。
final cocoCompanionPoseProvider = StateProvider<CocoCompanionPose>(
  (ref) => CocoCompanionPose.idle,
);
