import 'package:flutter/material.dart';

import 'tokens.dart';

/// 父母端 / 子女端两套主题，共享语义但映射不同。
abstract final class CocoTheme {
  static ThemeData parent() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: CocoColors.parentPrimary,
      brightness: Brightness.light,
      primary: CocoColors.parentPrimary,
      onPrimary: CocoColors.white,
      surface: CocoColors.parentSurface,
      onSurface: CocoColors.neutral950,
      error: CocoColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      // 跟随各厂商中文字体，避免锁死 Roboto 导致中文 fallback 杂乱
      fontFamily: 'sans-serif',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CocoColors.parentBackground,
      typography: Typography.material2021(),
      textTheme: _parentTextTheme.apply(fontFamily: 'sans-serif'),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 胶囊主按钮：对齐 DESIGN ElderPrimaryAction
          minimumSize: const Size.fromHeight(56),
          backgroundColor: CocoColors.parentPrimary,
          foregroundColor: CocoColors.white,
          disabledBackgroundColor: CocoColors.parentPrimary,
          disabledForegroundColor: CocoColors.white,
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: CocoColors.parentPrimary,
          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          side: const BorderSide(color: CocoColors.parentPrimary, width: 1.5),
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CocoColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CocoSpace.s5,
          vertical: CocoSpace.s5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoRadius.lg),
          borderSide: const BorderSide(color: CocoColors.neutral300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoRadius.lg),
          borderSide: const BorderSide(color: CocoColors.neutral300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoRadius.lg),
          borderSide: const BorderSide(color: CocoColors.parentFocus, width: 2),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: CocoColors.parentBackground,
        foregroundColor: CocoColors.neutral950,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }

  static ThemeData child() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: CocoColors.childPrimary,
      brightness: Brightness.light,
      primary: CocoColors.childPrimary,
      onPrimary: CocoColors.white,
      surface: CocoColors.childSurface,
      onSurface: CocoColors.neutral950,
      error: CocoColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'sans-serif',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CocoColors.childBackground,
      typography: Typography.material2021(),
      textTheme: _childTextTheme.apply(fontFamily: 'sans-serif'),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: CocoColors.childPrimary,
          foregroundColor: CocoColors.white,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CocoRadius.md),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CocoColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CocoSpace.s4,
          vertical: CocoSpace.s4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoRadius.md),
          borderSide: const BorderSide(color: CocoColors.childBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoRadius.md),
          borderSide: const BorderSide(color: CocoColors.childBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoRadius.md),
          borderSide: const BorderSide(
            color: CocoColors.childPrimary,
            width: 2,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: CocoColors.childBackground,
        foregroundColor: CocoColors.neutral950,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: CocoColors.childSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CocoRadius.md),
          side: const BorderSide(color: CocoColors.childBorder),
        ),
      ),
    );
  }

  static const TextTheme _parentTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: CocoColors.neutral950,
    ),
    titleLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: CocoColors.neutral950,
    ),
    titleMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: CocoColors.neutral950,
    ),
    bodyLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: CocoColors.neutral950,
    ),
    bodyMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      height: 1.4,
      color: CocoColors.neutral700,
    ),
    labelLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: CocoColors.white,
    ),
  );

  static const TextTheme _childTextTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: CocoColors.neutral950,
    ),
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: CocoColors.neutral950,
    ),
    titleMedium: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: CocoColors.neutral950,
    ),
    bodyLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: CocoColors.neutral950,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.35,
      color: CocoColors.neutral700,
    ),
    labelLarge: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.2,
      color: CocoColors.white,
    ),
  );
}
