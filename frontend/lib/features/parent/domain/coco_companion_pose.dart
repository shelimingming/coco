/// Coco 陪伴形象姿态；与 `assets/images/coco` 下 gif 对应。
enum CocoCompanionPose {
  /// 首页刚进入：出场跑动（播完一轮后切待机）
  entrance,

  /// 待机 / 默认呼吸态
  idle,

  /// 倾听用户说话
  listening,

  /// 思考 / 处理中（无专用图时回退倾听）
  thinking,

  /// 说话 / 播报
  speaking,

  /// 正在看（注视）
  looking,

  /// 关怀
  caring,

  /// 不确定 / 需澄清
  uncertain,

  /// 完成一件事
  done,

  /// 主动提醒
  proactiveReminder,
}

extension CocoCompanionPoseAsset on CocoCompanionPose {
  /// 出场 gif 单轮时长（25 帧 × 100ms）；到点后切待机，避免无限循环跑动
  static const Duration entranceDuration = Duration(milliseconds: 2500);

  /// 无障碍与文案用的中文语义名
  String get semanticLabel => switch (this) {
    CocoCompanionPose.entrance => '可可出场',
    CocoCompanionPose.idle => '可可待机',
    CocoCompanionPose.listening => '可可正在倾听',
    CocoCompanionPose.thinking => '可可正在思考',
    CocoCompanionPose.speaking => '可可正在说话',
    CocoCompanionPose.looking => '可可正在看',
    CocoCompanionPose.caring => '可可表示关怀',
    CocoCompanionPose.uncertain => '可不太确定',
    CocoCompanionPose.done => '可可表示完成',
    CocoCompanionPose.proactiveReminder => '可可主动提醒',
  };

  /// 首页/通话主用：出场、待机、倾听、说话；其余回退到最近语义的动图
  String get assetPath => switch (this) {
    CocoCompanionPose.entrance => 'assets/images/coco/coco_出场_loop_v01.gif',
    CocoCompanionPose.idle => 'assets/images/coco/coco_待机_loop_v01.gif',
    CocoCompanionPose.listening => 'assets/images/coco/coco_倾听_loop_v01.gif',
    CocoCompanionPose.thinking => 'assets/images/coco/coco_倾听_loop_v01.gif',
    CocoCompanionPose.speaking => 'assets/images/coco/coco_说话_loop_v01.gif',
    CocoCompanionPose.looking => 'assets/images/coco/coco_待机_loop_v01.gif',
    CocoCompanionPose.caring => 'assets/images/coco/coco_待机_loop_v01.gif',
    CocoCompanionPose.uncertain => 'assets/images/coco/coco_待机_loop_v01.gif',
    CocoCompanionPose.done => 'assets/images/coco/coco_待机_loop_v01.gif',
    CocoCompanionPose.proactiveReminder =>
      'assets/images/coco/coco_待机_loop_v01.gif',
  };
}
