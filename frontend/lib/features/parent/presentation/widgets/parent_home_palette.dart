import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';

/// 老人端首页白天配色：交付稿对话控制橙，不混用 onboarding 墨绿。
class ParentHomePalette {
  const ParentHomePalette._({
    required this.backgroundAsset,
    required this.text,
    required this.textMuted,
    required this.link,
    required this.chatOrange,
    required this.iconOrange,
    required this.toolbarFill,
    required this.toolbarDivider,
    required this.toolIdleIcon,
    required this.toolActiveFill,
    required this.toolActiveIcon,
    required this.captionBubble,
    required this.captionText,
    required this.captionToggleOn,
    required this.captionToggleOffBorder,
  });

  final String backgroundAsset;
  final Color text;
  final Color textMuted;
  final Color link;

  /// 开始 / 暂停 / 继续 / 看手机选中
  final Color chatOrange;

  /// 未选中工具图标、结束叉号
  final Color iconOrange;
  final Color toolbarFill;
  final Color toolbarDivider;
  final Color toolIdleIcon;
  final Color toolActiveFill;
  final Color toolActiveIcon;
  final Color captionBubble;
  final Color captionText;
  final Color captionToggleOn;
  final Color captionToggleOffBorder;

  static const standard = ParentHomePalette._(
    backgroundAsset: 'assets/images/parent/home/home_bg_day.png',
    text: CocoColors.parentHomeTextPrimary,
    textMuted: CocoColors.parentHomeTextSecondary,
    link: CocoColors.parentHomeChatOrange,
    chatOrange: CocoColors.parentHomeChatOrange,
    iconOrange: CocoColors.parentHomeIconOrange,
    toolbarFill: CocoColors.parentHomeToolbar,
    toolbarDivider: CocoColors.parentHomeDivider,
    toolIdleIcon: CocoColors.parentHomeIconOrange,
    toolActiveFill: CocoColors.parentHomeChatOrange,
    toolActiveIcon: CocoColors.white,
    captionBubble: CocoColors.parentHomeCaptionBubble,
    captionText: CocoColors.parentHomeTextPrimary,
    captionToggleOn: CocoColors.parentHomeChatOrange,
    captionToggleOffBorder: CocoColors.parentHomeChatOrange,
  );
}

/// 按时段问候：上午好 / 下午好 / 晚上好（仅文案，不切换场景）。
String parentHomeGreeting(String name, [DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  final period = hour < 12
      ? '上午好'
      : hour < 18
      ? '下午好'
      : '晚上好';
  return '$period，$name';
}
