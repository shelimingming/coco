import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';

/// 老人端首页白天配色：暖橙主操作，不混用 onboarding 墨绿。
class ParentHomePalette {
  const ParentHomePalette._({
    required this.backgroundAsset,
    required this.text,
    required this.textMuted,
    required this.link,
    required this.toolIdleFill,
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
  final Color toolIdleFill;
  final Color toolIdleIcon;
  final Color toolActiveFill;
  final Color toolActiveIcon;
  final Color captionBubble;
  final Color captionText;
  final Color captionToggleOn;
  final Color captionToggleOffBorder;

  static const standard = ParentHomePalette._(
    backgroundAsset: 'assets/images/parent/home/home_bg_day.png',
    text: CocoColors.neutral950,
    textMuted: CocoColors.neutral700,
    link: CocoColors.parentPrimary,
    toolIdleFill: CocoColors.parentHomeToolIdle,
    toolIdleIcon: CocoColors.parentPrimary,
    toolActiveFill: CocoColors.parentPrimary,
    toolActiveIcon: CocoColors.white,
    captionBubble: CocoColors.parentHomeCaptionBubble,
    captionText: CocoColors.neutral950,
    captionToggleOn: CocoColors.parentPrimary,
    captionToggleOffBorder: CocoColors.parentPrimary,
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

/// 每次进入首页的 TTS 开场白：点小狗即可说话。
String parentHomeVoiceGreeting(String name) {
  final parts = parentHomeVoiceGreetingParts(name);
  return '${parts.title}，${parts.subtitle}';
}

/// 开场白拆成两行，气泡主副文案与 TTS 共用。
({String title, String subtitle}) parentHomeVoiceGreetingParts(String name) {
  final who = name.trim().isEmpty ? '家人' : name.trim();
  return (title: '$who，你好呀，我是可可', subtitle: '点我一下，想聊什么就直接说');
}
