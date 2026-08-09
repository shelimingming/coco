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

  static const Color childBackground = Color(0xFFF6F8F7);
  static const Color childSurface = Color(0xFFFFFFFF);
  static const Color childPrimary = Color(0xFF28786B);
  static const Color childPrimaryPressed = Color(0xFF1F6258);
  static const Color childPrimarySoft = Color(0xFFDDEFEA);
  static const Color childAccent = Color(0xFFD97745);
  static const Color childBorder = Color(0xFFDEE5E2);
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
