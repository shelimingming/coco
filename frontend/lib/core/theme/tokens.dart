import 'package:flutter/material.dart';

/// 设计 token，色值来自 doc/DESIGN.md，页面内禁止写裸色值。
abstract final class CocoColors {
  static const Color neutral950 = Color(0xFF26231F);
  static const Color neutral700 = Color(0xFF5D574F);
  static const Color neutral500 = Color(0xFF817A71);
  static const Color neutral300 = Color(0xFFCFC8BE);
  static const Color neutral100 = Color(0xFFF3EFE9);
  static const Color white = Color(0xFFFFFFFF);
  static const Color success = Color(0xFF397A58);
  static const Color warning = Color(0xFFA86113);
  static const Color danger = Color(0xFFB33A34);
  static const Color info = Color(0xFF326B8C);

  static const Color parentBackground = Color(0xFFFFF8ED);
  static const Color parentSurface = Color(0xFFFFFFFF);
  static const Color parentPrimary = Color(0xFFC85F36);
  static const Color parentPrimaryPressed = Color(0xFFA94829);
  static const Color parentPrimarySoft = Color(0xFFF9DED0);
  static const Color parentSecondary = Color(0xFF7C6848);
  static const Color parentFocus = Color(0xFF784128);

  /// 老人端首页：闲置工具圆底、字幕气泡；底栏用纯色 parentBackground，不再透底图。
  static const Color parentHomeToolIdle = Color(0xFFFFFFFF);

  /// 对话气泡约 72% 白，半透明贴合场景，与身份选择介绍气泡一致。
  static const Color parentHomeCaptionBubble = Color(0xB8FFFFFF);

  static const Color childBackground = Color(0xFFF6F8F7);
  static const Color childSurface = Color(0xFFFFFFFF);
  static const Color childPrimary = Color(0xFF28786B);
  static const Color childPrimaryPressed = Color(0xFF1F6258);
  static const Color childPrimarySoft = Color(0xFFDDEFEA);
  static const Color childAccent = Color(0xFFD97745);
  static const Color childBorder = Color(0xFFDEE5E2);

  /// 首次身份选择等老人端白天操作色（可可_UI完整交付_v1，#276D62）。
  /// 与 DESIGN 暖橙主色并存：本页按交付稿走墨绿，不混用父母暖色按钮。
  static const Color onboardingBackground = Color(0xFFF9F8F3);
  static const Color onboardingAccent = Color(0xFF276D62);
  static const Color onboardingAccentSoft = Color(0xFFE6F2F0);

  /// 介绍气泡约 72% 白，更透、不抢场景。
  static const Color onboardingBubble = Color(0xB8FFFFFF);
  static const Color onboardingShadow = Color(0x14000000);

  /// 场景到底部奶油底的渐变停靠色。
  static const Color onboardingFadeStart = Color(0x00F9F8F3);
  static const Color onboardingFadeMid = Color(0x66F9F8F3);
  static const Color onboardingFadeStrong = Color(0xCCF9F8F3);

  /// 登录页：背景图上的浅罩，保证标题与白卡可读。
  static const Color loginScrim = Color(0x66F9F8F3);

  /// 登录卡输入框描边（交付稿暖米色边）。
  static const Color loginFieldBorder = Color(0xFFE8D5C8);
}

abstract final class CocoSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
}

abstract final class CocoRadius {
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;
}
