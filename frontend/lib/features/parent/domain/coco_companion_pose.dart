/// Coco 陪伴形象姿态；与 `assets/images/coco` 一一对应，后续可同路径换动图。
enum CocoCompanionPose {
  /// 待机 / 默认呼吸态
  idle,

  /// 倾听用户说话
  listening,

  /// 思考 / 处理中
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
  /// 无障碍与文案用的中文语义名
  String get semanticLabel => switch (this) {
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

  /// 当前静态帧资源；换成 gif/webp 时只改扩展名或此映射即可
  String get assetPath => switch (this) {
        CocoCompanionPose.idle =>
          'assets/images/coco/coco_待机_loop_v01.png',
        CocoCompanionPose.listening =>
          'assets/images/coco/coco_倾听_loop_v01.png',
        CocoCompanionPose.thinking =>
          'assets/images/coco/coco_思考_loop_v01.png',
        CocoCompanionPose.speaking =>
          'assets/images/coco/coco_说话_loop_v01.png',
        CocoCompanionPose.looking =>
          'assets/images/coco/coco_正在看_loop_v01.png',
        CocoCompanionPose.caring =>
          'assets/images/coco/coco_关怀_loop_v01.png',
        CocoCompanionPose.uncertain =>
          'assets/images/coco/coco_不确定_loop_v01.png',
        CocoCompanionPose.done =>
          'assets/images/coco/coco_完成_loop_v01.png',
        CocoCompanionPose.proactiveReminder =>
          'assets/images/coco/coco_主动提醒_loop_v01.png',
      };
}
