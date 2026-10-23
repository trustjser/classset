import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.ink,
    required this.inkSecondary,
    required this.muted,
    required this.helpIcon,
    required this.canvas,
    required this.surface,
    required this.blue,
    required this.purple,
    required this.border,
    required this.sidebarActive,
    required this.sidebarText,
    required this.sidebarMuted,
    required this.sidebarHint,
    required this.sidebarAccent,
    required this.selectedBlue,
    required this.tableHeader,
    required this.tableDivider,
    required this.success,
    required this.successSurface,
    required this.warning,
    required this.warningSurface,
    required this.destructive,
    required this.destructiveSurface,
    required this.dialogBarrier,
  });

  final Color ink;
  final Color inkSecondary;
  final Color muted;
  final Color helpIcon;
  final Color canvas;
  final Color surface;
  final Color blue;
  final Color purple;
  final Color border;
  final Color sidebarActive;
  final Color sidebarText;
  final Color sidebarMuted;
  final Color sidebarHint;
  final Color sidebarAccent;
  final Color selectedBlue;
  final Color tableHeader;
  final Color tableDivider;
  final Color success;
  final Color successSurface;
  final Color warning;
  final Color warningSurface;
  final Color destructive;
  final Color destructiveSurface;
  final Color dialogBarrier;

  static const light = AppThemeColors(
    ink: Color(0xFF1A1A1A),
    inkSecondary: Color(0xFF615D59),
    muted: Color(0xFFA39E98),
    helpIcon: Color(0xFFB4AEA8),
    canvas: Color(0xFFF6F5F4),
    surface: Colors.white,
    blue: Color(0xFF0075DE),
    purple: Color(0xFF7568B5),
    border: Color(0xFFEAE8E6),
    sidebarActive: Color(0xFFE8F1FC),
    sidebarText: Color(0xFF615D59),
    sidebarMuted: Color(0xFF938D87),
    sidebarHint: Color(0xFF938D87),
    sidebarAccent: Color(0xFF0075DE),
    selectedBlue: Color(0xFFE8F1FC),
    tableHeader: Color(0xFFFAF9F8),
    tableDivider: Color(0xFFF0EEEC),
    success: Color(0xFF2BA471),
    successSurface: Color(0xFFE9F6EF),
    warning: Color(0xFFC98A2B),
    warningSurface: Color(0xFFFAF1E2),
    destructive: Color(0xFFD54941),
    destructiveSurface: Color(0xFFFBECEB),
    dialogBarrier: Color(0x52000000),
  );

  static const dark = AppThemeColors(
    ink: Color(0xFFF1F3F5),
    inkSecondary: Color(0xFFC3C8D0),
    muted: Color(0xFF9299A3),
    helpIcon: Color(0xFF858D98),
    canvas: Color(0xFF17191D),
    surface: Color(0xFF20242A),
    blue: Color(0xFF59A6F6),
    purple: Color(0xFFB3A8F0),
    border: Color(0xFF363B43),
    sidebarActive: Color(0xFF233A50),
    sidebarText: Color(0xFFD5D9DF),
    sidebarMuted: Color(0xFF9EA5AF),
    sidebarHint: Color(0xFF9299A3),
    sidebarAccent: Color(0xFF59A6F6),
    selectedBlue: Color(0xFF20384F),
    tableHeader: Color(0xFF272B32),
    tableDivider: Color(0xFF343941),
    success: Color(0xFF50BE8D),
    successSurface: Color(0xFF1F3B2F),
    warning: Color(0xFFE4B15D),
    warningSurface: Color(0xFF3C321F),
    destructive: Color(0xFFF07870),
    destructiveSurface: Color(0xFF432827),
    dialogBarrier: Color(0x99000000),
  );

  @override
  AppThemeColors copyWith({
    Color? ink,
    Color? inkSecondary,
    Color? muted,
    Color? helpIcon,
    Color? canvas,
    Color? surface,
    Color? blue,
    Color? purple,
    Color? border,
    Color? sidebarActive,
    Color? sidebarText,
    Color? sidebarMuted,
    Color? sidebarHint,
    Color? sidebarAccent,
    Color? selectedBlue,
    Color? tableHeader,
    Color? tableDivider,
    Color? success,
    Color? successSurface,
    Color? warning,
    Color? warningSurface,
    Color? destructive,
    Color? destructiveSurface,
    Color? dialogBarrier,
  }) => AppThemeColors(
    ink: ink ?? this.ink,
    inkSecondary: inkSecondary ?? this.inkSecondary,
    muted: muted ?? this.muted,
    helpIcon: helpIcon ?? this.helpIcon,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    blue: blue ?? this.blue,
    purple: purple ?? this.purple,
    border: border ?? this.border,
    sidebarActive: sidebarActive ?? this.sidebarActive,
    sidebarText: sidebarText ?? this.sidebarText,
    sidebarMuted: sidebarMuted ?? this.sidebarMuted,
    sidebarHint: sidebarHint ?? this.sidebarHint,
    sidebarAccent: sidebarAccent ?? this.sidebarAccent,
    selectedBlue: selectedBlue ?? this.selectedBlue,
    tableHeader: tableHeader ?? this.tableHeader,
    tableDivider: tableDivider ?? this.tableDivider,
    success: success ?? this.success,
    successSurface: successSurface ?? this.successSurface,
    warning: warning ?? this.warning,
    warningSurface: warningSurface ?? this.warningSurface,
    destructive: destructive ?? this.destructive,
    destructiveSurface: destructiveSurface ?? this.destructiveSurface,
    dialogBarrier: dialogBarrier ?? this.dialogBarrier,
  );

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      ink: Color.lerp(ink, other.ink, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      helpIcon: Color.lerp(helpIcon, other.helpIcon, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      border: Color.lerp(border, other.border, t)!,
      sidebarActive: Color.lerp(sidebarActive, other.sidebarActive, t)!,
      sidebarText: Color.lerp(sidebarText, other.sidebarText, t)!,
      sidebarMuted: Color.lerp(sidebarMuted, other.sidebarMuted, t)!,
      sidebarHint: Color.lerp(sidebarHint, other.sidebarHint, t)!,
      sidebarAccent: Color.lerp(sidebarAccent, other.sidebarAccent, t)!,
      selectedBlue: Color.lerp(selectedBlue, other.selectedBlue, t)!,
      tableHeader: Color.lerp(tableHeader, other.tableHeader, t)!,
      tableDivider: Color.lerp(tableDivider, other.tableDivider, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSurface: Color.lerp(successSurface, other.successSurface, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      destructiveSurface: Color.lerp(
        destructiveSurface,
        other.destructiveSurface,
        t,
      )!,
      dialogBarrier: Color.lerp(dialogBarrier, other.dialogBarrier, t)!,
    );
  }
}

extension AppThemeColorsContext on BuildContext {
  AppThemeColors get appColors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemeColors.light;
}

/// Shared layout tokens and factories for the coordinated app themes.
abstract final class AppTheme {
  static const double cardRadius = 14;
  static const double controlRadius = 10;
  static const double pagePadding = 26;
  static const double compactPagePadding = 16;
  static const double compactPageBreakpoint = 880;
  static const double twoColumnLayoutBreakpoint = 1040;
  static const double pageSectionGap = 16;

  static double pagePaddingForWidth(double availableWidth) =>
      availableWidth < compactPageBreakpoint ? compactPagePadding : pagePadding;

  static final ThemeData light = _createMaterialTheme(
    AppThemeColors.light,
    isDark: false,
  );
  static final ThemeData dark = _createMaterialTheme(
    AppThemeColors.dark,
    isDark: true,
  );

  static ThemeData themeFor(bool isDark) => isDark ? dark : light;

  static f.FThemeData foruiFor(bool isDark) => _createForuiTheme(
    isDark ? AppThemeColors.dark : AppThemeColors.light,
    isDark,
  );

  static TextStyle matrixHeaderTextStyle(BuildContext context) => TextStyle(
    color: context.appColors.muted,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: .2,
  );

  /// 学段强调色：与「班级与学段」页一致，按学段序号蓝 / 绿 / 橙轮换。
  static Color stageAccent(BuildContext context, int index) =>
      switch (index % 3) {
        0 => context.appColors.blue,
        1 => context.appColors.success,
        _ => context.appColors.warning,
      };

  static ThemeData _createMaterialTheme(
    AppThemeColors colors, {
    required bool isDark,
  }) {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: colors.blue,
            onPrimary: const Color(0xFF101820),
            secondary: colors.selectedBlue,
            onSecondary: colors.ink,
            error: colors.destructive,
            onError: const Color(0xFF1D1111),
            surface: colors.surface,
            onSurface: colors.ink,
            surfaceContainerLowest: colors.surface,
            surfaceContainerLow: colors.tableHeader,
            surfaceContainer: colors.canvas,
            surfaceContainerHigh: const Color(0xFF2B3037),
            surfaceContainerHighest: const Color(0xFF343A42),
            onSurfaceVariant: colors.inkSecondary,
            outline: colors.border,
            outlineVariant: colors.tableDivider,
            inverseSurface: colors.ink,
            onInverseSurface: colors.surface,
            inversePrimary: const Color(0xFF0075DE),
          )
        : ColorScheme.light(
            primary: colors.blue,
            onPrimary: Colors.white,
            secondary: colors.selectedBlue,
            onSecondary: colors.ink,
            error: colors.destructive,
            onError: Colors.white,
            surface: colors.surface,
            onSurface: colors.ink,
            surfaceContainerLowest: colors.surface,
            surfaceContainerLow: colors.tableHeader,
            surfaceContainer: const Color(0xFFF3F1EF),
            surfaceContainerHigh: const Color(0xFFEEEBE8),
            surfaceContainerHighest: const Color(0xFFE7E3DF),
            onSurfaceVariant: colors.inkSecondary,
            outline: colors.border,
            outlineVariant: const Color(0xFFF0F0F0),
            inverseSurface: colors.ink,
            onInverseSurface: Colors.white,
            inversePrimary: colors.selectedBlue,
          );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: colorScheme,
      extensions: [colors],
      scaffoldBackgroundColor: colors.canvas,
      dividerColor: colors.border,
      visualDensity: VisualDensity.standard,
      hoverColor: isDark ? const Color(0x1AFFFFFF) : const Color(0x0F181818),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      datePickerTheme: DatePickerThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: colors.blue,
        headerForegroundColor: isDark ? const Color(0xFF101820) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF343A42) : const Color(0xE6181818),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(color: colors.ink, fontSize: 12),
      ),
      textTheme:
          (isDark
                  ? Typography.material2021().white
                  : Typography.material2021().black)
              .copyWith(
                headlineSmall: TextStyle(
                  color: colors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
                titleSmall: TextStyle(
                  color: colors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
                bodySmall: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
                labelSmall: TextStyle(
                  color: colors.muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.blue, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: colors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.blue,
          foregroundColor: isDark ? const Color(0xFF101820) : Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.ink,
          side: BorderSide(color: colors.border),
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
      ),
    );
  }

  static f.FThemeData _createForuiTheme(AppThemeColors palette, bool isDark) {
    final base = isDark
        ? f.FTheme.neutral.dark.desktop
        : f.FTheme.neutral.light.desktop;
    final colors = base.colors.copyWith(
      background: palette.canvas,
      foreground: palette.ink,
      primary: palette.blue,
      primaryForeground: isDark ? const Color(0xFF101820) : Colors.white,
      secondary: palette.selectedBlue,
      secondaryForeground: palette.ink,
      muted: palette.tableHeader,
      mutedForeground: palette.muted,
      card: palette.surface,
      border: palette.border,
      destructive: palette.destructive,
      destructiveForeground: isDark ? const Color(0xFF1D1111) : Colors.white,
      error: palette.destructive,
      errorForeground: isDark ? const Color(0xFF1D1111) : Colors.white,
    );
    return f.FThemeData(
      debugLabel: isDark ? 'Keji TDesign Forui Dark' : 'Keji TDesign Forui',
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
