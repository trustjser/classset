import 'package:class_set/core/theme/app_appearance.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;
import 'package:material_ui/material_ui.dart' as material;

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
    required this.onAccent,
    required this.controlBorder,
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
    required this.cardShadow,
  });

  final Color ink;
  final Color inkSecondary;
  final Color muted;
  final Color helpIcon;
  final Color canvas;
  final Color surface;

  /// Legacy storage name; new components use [accent].
  final Color blue;
  Color get accent => blue;
  Color get selection => selectedBlue;
  final Color onAccent;
  final Color controlBorder;
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

  /// 静态面板依靠底色层次区分，保留此入口兼容已有面板。
  final List<BoxShadow> cardShadow;

  // 晴空蓝 / 夜空蓝：正文、交互与状态色均成对设计。
  static const light = AppThemeColors(
    ink: Color(0xFF202A3D),
    inkSecondary: Color(0xFF5E6B80),
    muted: Color(0xFF606F86),
    helpIcon: Color(0xFF606F86),
    canvas: Color(0xFFF4F7FC),
    surface: Color(0xFFFFFFFF),
    blue: Color(0xFF2864DC),
    onAccent: Color(0xFFFFFFFF),
    controlBorder: Color(0xFF7E8BA3),
    purple: Color(0xFF6E5AAC),
    border: Color(0xFFDCE3EF),
    sidebarActive: Color(0xFFEAF1FF),
    sidebarText: Color(0xFF5E6B80),
    sidebarMuted: Color(0xFF606F86),
    sidebarHint: Color(0xFF606F86),
    sidebarAccent: Color(0xFF2864DC),
    selectedBlue: Color(0xFFEAF1FF),
    tableHeader: Color(0xFFF3F5F9),
    tableDivider: Color(0xFFE6EBF4),
    success: Color(0xFF1F765E),
    successSurface: Color(0xFFE5F4ED),
    warning: Color(0xFF875D18),
    warningSurface: Color(0xFFFFF4DD),
    destructive: Color(0xFFB74752),
    destructiveSurface: Color(0xFFFCECEF),
    dialogBarrier: Color(0x66111B2D),
    cardShadow: [],
  );

  static const dark = AppThemeColors(
    ink: Color(0xFFEDF2FC),
    inkSecondary: Color(0xFFA6B4CC),
    muted: Color(0xFF9EAEC8),
    helpIcon: Color(0xFF9EAEC8),
    canvas: Color(0xFF111722),
    surface: Color(0xFF1B2433),
    blue: Color(0xFF97BAFF),
    onAccent: Color(0xFF162B50),
    controlBorder: Color(0xFF7186A6),
    purple: Color(0xFFC3B3F5),
    border: Color(0xFF34425A),
    sidebarActive: Color(0xFF253957),
    sidebarText: Color(0xFFA6B4CC),
    sidebarMuted: Color(0xFF9EAEC8),
    sidebarHint: Color(0xFF9EAEC8),
    sidebarAccent: Color(0xFF97BAFF),
    selectedBlue: Color(0xFF253957),
    tableHeader: Color(0xFF242E3F),
    tableDivider: Color(0xFF303C52),
    success: Color(0xFF78D8B4),
    successSurface: Color(0xFF193D35),
    warning: Color(0xFFF0CC83),
    warningSurface: Color(0xFF423824),
    destructive: Color(0xFFFFA4AE),
    destructiveSurface: Color(0xFF472A36),
    dialogBarrier: Color(0xB308101E),
    cardShadow: [],
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
    Color? onAccent,
    Color? controlBorder,
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
    List<BoxShadow>? cardShadow,
  }) => AppThemeColors(
    ink: ink ?? this.ink,
    inkSecondary: inkSecondary ?? this.inkSecondary,
    muted: muted ?? this.muted,
    helpIcon: helpIcon ?? this.helpIcon,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    blue: blue ?? this.blue,
    onAccent: onAccent ?? this.onAccent,
    controlBorder: controlBorder ?? this.controlBorder,
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
    cardShadow: cardShadow ?? this.cardShadow,
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
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      controlBorder: Color.lerp(controlBorder, other.controlBorder, t)!,
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
      // 阴影不参与插值，主题切换时直接取目标值。
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
    );
  }
}

extension AppThemeColorsContext on BuildContext {
  AppThemeColors get appColors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemeColors.light;

  Color get routineMatrixDivider =>
      Theme.of(this).brightness == Brightness.light
      ? Colors.white
      : Color.lerp(appColors.tableDivider, appColors.inkSecondary, 0.22)!;
}

/// Shared layout tokens and factories for the coordinated app themes.
abstract final class AppTheme {
  static const double cardRadius = 20;
  static const double controlRadius = 12;
  static const double pagePadding = 32;
  static const double compactPagePadding = 16;
  static const double pageTopPadding = 16;
  static const double compactPageBreakpoint = 880;
  static const double twoColumnLayoutBreakpoint = 1040;
  static const double pageSectionGap = 24;
  static const Duration feedbackDuration = Duration(milliseconds: 120);
  static const Duration transitionDuration = Duration(milliseconds: 180);
  static const Duration exitDuration = Duration(milliseconds: 120);
  static const Curve entranceCurve = Curves.easeOutCubic;
  static const Curve transitionCurve = Curves.easeInOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const double pressedScale = 0.98;

  static Duration motionDuration(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  static double pagePaddingForWidth(double availableWidth) =>
      availableWidth < compactPageBreakpoint ? compactPagePadding : pagePadding;

  static EdgeInsets pageInsetsForWidth(double availableWidth) {
    final gutter = pagePaddingForWidth(availableWidth);
    return EdgeInsets.fromLTRB(gutter, pageTopPadding, gutter, gutter);
  }

  static double sidebarPaddingForWidth(double availableWidth) =>
      availableWidth < compactPageBreakpoint ? 12 : 16;

  static final ThemeData light = _createMaterialTheme(
    AppThemeColors.light,
    isDark: false,
  );
  static final ThemeData dark = _createMaterialTheme(
    AppThemeColors.dark,
    isDark: true,
  );

  static final _materialThemes = <(AppPalette, bool), ThemeData>{};
  static final _foruiThemes = <(AppPalette, bool), f.FThemeData>{};

  static ThemeData themeFor(
    bool isDark, {
    AppPalette palette = AppPalette.sky,
  }) {
    if (palette == AppPalette.sky) return isDark ? dark : light;
    return _materialThemes.putIfAbsent(
      (palette, isDark),
      () => _createMaterialTheme(
        colorsFor(isDark, palette: palette),
        isDark: isDark,
      ),
    );
  }

  static f.FThemeData foruiFor(
    bool isDark, {
    AppPalette palette = AppPalette.sky,
  }) => _foruiThemes.putIfAbsent((
    palette,
    isDark,
  ), () => _createForuiTheme(colorsFor(isDark, palette: palette), isDark));

  static AppThemeColors colorsFor(
    bool isDark, {
    AppPalette palette = AppPalette.sky,
  }) {
    final base = isDark ? AppThemeColors.dark : AppThemeColors.light;
    return switch (palette) {
      AppPalette.sky => base,
      AppPalette.teal =>
        isDark
            ? base.copyWith(
                canvas: const Color(0xFF101C20),
                surface: const Color(0xFF1B2A30),
                ink: const Color(0xFFE6F4F5),
                inkSecondary: const Color(0xFFA0BEC4),
                muted: const Color(0xFFA0BEC4),
                helpIcon: const Color(0xFFA0BEC4),
                blue: const Color(0xFF78D7D6),
                onAccent: const Color(0xFF103A3D),
                selectedBlue: const Color(0xFF244347),
                sidebarActive: const Color(0xFF244347),
                sidebarAccent: const Color(0xFF78D7D6),
                sidebarText: const Color(0xFFA0BEC4),
                sidebarMuted: const Color(0xFFA0BEC4),
                sidebarHint: const Color(0xFFA0BEC4),
                tableHeader: const Color(0xFF26373D),
                border: const Color(0xFF31464E),
                tableDivider: const Color(0xFF2B4149),
                controlBorder: const Color(0xFF718E99),
              )
            : base.copyWith(
                canvas: const Color(0xFFF2F9F9),
                surface: Colors.white,
                ink: const Color(0xFF20373B),
                inkSecondary: const Color(0xFF526F74),
                muted: const Color(0xFF526F74),
                helpIcon: const Color(0xFF526F74),
                blue: const Color(0xFF087D89),
                onAccent: Colors.white,
                selectedBlue: const Color(0xFFEEF9F9),
                sidebarActive: const Color(0xFFEEF9F9),
                sidebarAccent: const Color(0xFF087D89),
                sidebarText: const Color(0xFF526F74),
                sidebarMuted: const Color(0xFF526F74),
                sidebarHint: const Color(0xFF526F74),
                tableHeader: const Color(0xFFF0F6F6),
                border: const Color(0xFFD6E6E8),
                tableDivider: const Color(0xFFE2ECEE),
                controlBorder: const Color(0xFF748E94),
              ),
      AppPalette.cloud =>
        isDark
            ? base.copyWith(
                canvas: const Color(0xFF15181E),
                surface: const Color(0xFF21262F),
                ink: const Color(0xFFEEF0F5),
                inkSecondary: const Color(0xFFACB5C4),
                muted: const Color(0xFFACB5C4),
                helpIcon: const Color(0xFFACB5C4),
                blue: const Color(0xFFBDCEE9),
                onAccent: const Color(0xFF263447),
                selectedBlue: const Color(0xFF303D51),
                sidebarActive: const Color(0xFF303D51),
                sidebarAccent: const Color(0xFFBDCEE9),
                sidebarText: const Color(0xFFACB5C4),
                sidebarMuted: const Color(0xFFACB5C4),
                sidebarHint: const Color(0xFFACB5C4),
                tableHeader: const Color(0xFF2A303A),
                border: const Color(0xFF3B424F),
                tableDivider: const Color(0xFF333B48),
                controlBorder: const Color(0xFF7D899C),
              )
            : base.copyWith(
                canvas: const Color(0xFFF6F7F9),
                surface: Colors.white,
                ink: const Color(0xFF242B38),
                inkSecondary: const Color(0xFF626D7E),
                muted: const Color(0xFF626D7E),
                helpIcon: const Color(0xFF626D7E),
                blue: const Color(0xFF3E4F6D),
                onAccent: Colors.white,
                selectedBlue: const Color(0xFFEAF0F8),
                sidebarActive: const Color(0xFFEAF0F8),
                sidebarAccent: const Color(0xFF3E4F6D),
                sidebarText: const Color(0xFF626D7E),
                sidebarMuted: const Color(0xFF626D7E),
                sidebarHint: const Color(0xFF626D7E),
                tableHeader: const Color(0xFFF1F3F6),
                border: const Color(0xFFDEE3EA),
                tableDivider: const Color(0xFFE6EAF0),
                controlBorder: const Color(0xFF7B8596),
              ),
    };
  }

  static TextStyle matrixHeaderTextStyle(BuildContext context) => TextStyle(
    color: context.appColors.muted,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  /// 学段强调色：与「班级与学段」页一致，按学段序号晴空蓝 / 鸢尾紫 / 琥珀轮换。
  static Color stageAccent(BuildContext context, int index) =>
      switch (index % 3) {
        0 => context.appColors.blue,
        1 => context.appColors.purple,
        _ => context.appColors.warning,
      };

  static ThemeData _createMaterialTheme(
    AppThemeColors colors, {
    required bool isDark,
  }) {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: colors.accent,
            onPrimary: colors.onAccent,
            secondary: colors.selection,
            onSecondary: colors.ink,
            error: colors.destructive,
            onError: const Color(0xFF1D1111),
            surface: colors.surface,
            onSurface: colors.ink,
            surfaceContainerLowest: colors.surface,
            surfaceContainerLow: colors.tableHeader,
            surfaceContainer: colors.canvas,
            surfaceContainerHigh: Color.alphaBlend(
              colors.ink.withValues(alpha: .07),
              colors.surface,
            ),
            surfaceContainerHighest: Color.alphaBlend(
              colors.ink.withValues(alpha: .12),
              colors.surface,
            ),
            onSurfaceVariant: colors.inkSecondary,
            outline: colors.controlBorder,
            outlineVariant: colors.tableDivider,
            inverseSurface: colors.ink,
            onInverseSurface: colors.surface,
            inversePrimary: colors.accent,
          )
        : ColorScheme.light(
            primary: colors.accent,
            onPrimary: colors.onAccent,
            secondary: colors.selection,
            onSecondary: colors.ink,
            error: colors.destructive,
            onError: Colors.white,
            surface: colors.surface,
            onSurface: colors.ink,
            surfaceContainerLowest: colors.surface,
            surfaceContainerLow: colors.tableHeader,
            surfaceContainer: colors.canvas,
            surfaceContainerHigh: Color.alphaBlend(
              colors.ink.withValues(alpha: .04),
              colors.surface,
            ),
            surfaceContainerHighest: Color.alphaBlend(
              colors.ink.withValues(alpha: .08),
              colors.surface,
            ),
            onSurfaceVariant: colors.inkSecondary,
            outline: colors.controlBorder,
            outlineVariant: colors.border,
            inverseSurface: colors.ink,
            onInverseSurface: Colors.white,
            inversePrimary: colors.selection,
          );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        primaryContainer: colors.selection,
        onPrimaryContainer: colors.accent,
        secondaryContainer: colors.tableHeader,
        onSecondaryContainer: colors.ink,
        tertiary: colors.purple,
        errorContainer: colors.destructiveSurface,
        onErrorContainer: colors.destructive,
        surfaceTint: Colors.transparent,
      ),
      extensions: [colors],
      scaffoldBackgroundColor: colors.canvas,
      dividerColor: colors.border,
      visualDensity: VisualDensity.standard,
      hoverColor: isDark ? const Color(0x1AFFFFFF) : const Color(0x0F181818),
      focusColor: colors.accent.withValues(alpha: .18),
      splashFactory: InkSparkle.splashFactory,
      datePickerTheme: DatePickerThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: colors.accent,
        headerForegroundColor: colors.onAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? colors.border : const Color(0xE6181818),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(
          color: isDark ? colors.ink : Colors.white,
          fontSize: 12,
        ),
      ),
      textTheme:
          (isDark
                  ? Typography.material2021().white
                  : Typography.material2021().black)
              .copyWith(
                headlineSmall: TextStyle(
                  color: colors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
                titleMedium: TextStyle(
                  color: colors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
                bodyLarge: TextStyle(
                  color: colors.ink,
                  fontSize: 16,
                  height: 1.5,
                ),
                bodyMedium: TextStyle(
                  color: colors.ink,
                  fontSize: 14,
                  height: 1.5,
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
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.tableHeader,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.controlBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.controlBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.accent, width: 2),
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
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
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
          side: BorderSide(color: colors.controlBorder),
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
      primary: palette.accent,
      primaryForeground: palette.onAccent,
      secondary: palette.selection,
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
    final typography = f.FTypography.inherit(colors: colors, touch: false);
    final theme = f.FThemeData(
      debugLabel: isDark ? 'ClassSet Dark' : 'ClassSet Light',
      colors: colors,
      typography: typography,
      touch: false,
      style:
          f.FStyle.inherit(
            colors: colors,
            typography: typography,
            touch: false,
          ).copyWith(
            borderRadius: const f.FBorderRadius(
              xs2: BorderRadius.all(Radius.circular(6)),
              xs: BorderRadius.all(Radius.circular(8)),
              sm: BorderRadius.all(Radius.circular(9)),
              md: BorderRadius.all(Radius.circular(controlRadius)),
              lg: BorderRadius.all(Radius.circular(12)),
              xl: BorderRadius.all(Radius.circular(18)),
              xl2: BorderRadius.all(Radius.circular(cardRadius)),
            ),
          ),
    );
    // 字段单独加强边界，避免把面板和所有分隔线一起加重。
    final fields =
        f.FVariantsDelta<
          f.FTextFieldSizeVariantConstraint,
          f.FTextFieldSizeVariant,
          f.FTextFieldStyle,
          f.FTextFieldStyleDelta
        >.delta([
          f.FVariantOperation.all(
            f.FTextFieldStyleDelta.delta(
              color: f.FVariantsValueDelta.delta([
                f.FVariantValueDeltaOperation.base(palette.tableHeader),
              ]),
              border: f.FVariantsValueDelta.delta([
                f.FVariantValueDeltaOperation.base(
                  material.OutlineInputBorder(
                    borderRadius: BorderRadius.circular(controlRadius),
                    borderSide: BorderSide(color: palette.controlBorder),
                  ),
                ),
                f.FVariantValueDeltaOperation.exact(
                  {f.FTextFieldVariant.focused},
                  material.OutlineInputBorder(
                    borderRadius: BorderRadius.circular(controlRadius),
                    borderSide: BorderSide(color: palette.accent, width: 2),
                  ),
                ),
              ]),
            ),
          ),
        ]);
    return theme.copyWith(
      textFieldStyles: fields,
      selectStyle: f.FSelectStyleDelta.delta(fieldStyles: fields),
      dateFieldStyle: f.FDateFieldStyleDelta.delta(fieldStyles: fields),
      timeFieldStyle: f.FTimeFieldStyleDelta.delta(fieldStyles: fields),
    );
  }
}
