import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

/// Design tokens shared by Forui controls and the few platform-native widgets
/// that remain useful for calendars and desktop menus.
abstract final class AppTheme {
  static const Color ink = Color(0xFF1A1A1A);
  static const Color inkSecondary = Color(0xFF615D59);
  static const Color muted = Color(0xFFA39E98);
  static const Color helpIcon = Color(0xFFB4AEA8);
  static const Color canvas = Color(0xFFF6F5F4);
  static const Color blue = Color(0xFF0075DE);
  static const Color purple = Color(0xFF7568B5);
  static const Color border = Color(0xFFEAE8E6);
  static const Color sidebarActive = Color(0xFFE8F1FC);
  static const Color sidebarText = Color(0xFF615D59);
  static const Color sidebarMuted = Color(0xFF938D87);
  static const Color sidebarHint = Color(0xFF938D87);
  static const Color sidebarAccent = Color(0xFF0075DE);
  static const Color selectedBlue = Color(0xFFE8F1FC);
  static const Color tableHeader = Color(0xFFFAF9F8);
  static const Color tableDivider = Color(0xFFF0EEEC);
  static const Color success = Color(0xFF2BA471);
  static const Color successSurface = Color(0xFFE9F6EF);
  static const Color warning = Color(0xFFC98A2B);
  static const Color warningSurface = Color(0xFFFAF1E2);
  static const Color destructive = Color(0xFFD54941);
  static const Color destructiveSurface = Color(0xFFFBECEB);
  static const Color dialogBarrier = Color(0x52000000);
  static const double cardRadius = 14;
  static const double controlRadius = 10;
  static const double pagePadding = 26;
  static const double pageSectionGap = 16;

  static final f.FThemeData forui = _createForuiTheme();

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    // 显式中性色系：避免 ColorScheme.fromSeed 派生出蓝紫色容器
    // （DatePicker 表头、悬浮遮罩、surfaceContainer 系列都会被 seed 染色）。
    colorScheme: const ColorScheme.light(
      primary: blue,
      onPrimary: Colors.white,
      secondary: selectedBlue,
      onSecondary: ink,
      error: destructive,
      onError: Colors.white,
      surface: Colors.white,
      onSurface: ink,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFFAF9F8),
      surfaceContainer: Color(0xFFF3F1EF),
      surfaceContainerHigh: Color(0xFFEEEBE8),
      surfaceContainerHighest: Color(0xFFE7E3DF),
      onSurfaceVariant: inkSecondary,
      outline: border,
      outlineVariant: Color(0xFFF0F0F0),
      inverseSurface: ink,
      onInverseSurface: Colors.white,
      inversePrimary: selectedBlue,
    ),
    scaffoldBackgroundColor: canvas,
    dividerColor: border,
    visualDensity: VisualDensity.standard,
    // 桌面端交互：中性悬停遮罩，去掉 M3 水波纹（TDesign 无 ripple）。
    hoverColor: const Color(0x0F181818),
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: blue,
      headerForegroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xE6181818),
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    textTheme: Typography.material2021().black.copyWith(
      headlineSmall: const TextStyle(
        color: ink,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleSmall: const TextStyle(
        color: ink,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      bodySmall: const TextStyle(color: muted, fontSize: 12, height: 1.5),
      labelSmall: const TextStyle(color: muted, fontSize: 11, height: 1.4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: const BorderSide(color: blue, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardRadius),
        side: const BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: border),
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      ),
    ),
  );

  static f.FThemeData _createForuiTheme() {
    final base = f.FTheme.neutral.light.desktop;
    final colors = base.colors.copyWith(
      background: canvas,
      foreground: ink,
      primary: blue,
      primaryForeground: Colors.white,
      secondary: selectedBlue,
      secondaryForeground: ink,
      muted: const Color(0xFFF6F6F6),
      mutedForeground: muted,
      card: Colors.white,
      border: border,
      destructive: destructive,
      destructiveForeground: Colors.white,
      error: destructive,
      errorForeground: Colors.white,
    );
    return f.FThemeData(
      debugLabel: 'Keji TDesign Forui',
      colors: colors,
      typography: base.typography,
      touch: false,
      style: base.style.copyWith(
        borderRadius: const f.FBorderRadius(
          xs2: BorderRadius.all(Radius.circular(6)),
          xs: BorderRadius.all(Radius.circular(8)),
          sm: BorderRadius.all(Radius.circular(9)),
          md: BorderRadius.all(Radius.circular(10)),
          lg: BorderRadius.all(Radius.circular(12)),
          xl: BorderRadius.all(Radius.circular(14)),
          xl2: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    );
  }
}
