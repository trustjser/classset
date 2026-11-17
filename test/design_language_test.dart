import 'dart:math' as math;

import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_appearance.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/theme/subject_colors.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

void main() {
  testWidgets('启动跟随系统，手动选择后不被系统主题覆盖', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    // 空库会进入创建向导（无顶部栏），先种一个学期以便测试主题入口。
    await tester.runAsync(
      () => repository.saveTerm(
        AcademicTerm(
          id: 'design-seed',
          title: '2026 秋季',
          academicYear: '2026-2027',
          semesterLabel: '秋季学期',
          firstTeachingWeekStart: DateTime(2026, 9, 1),
          teachingWeekCount: 20,
          createdAt: DateTime(2026, 8, 1),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
        child: const ClassSetApp(databasePath: 'preview.sqlite'),
      ),
    );
    await tester.pumpAndSettle();
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
    expect(brightness(), Brightness.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIconButton && widget.tooltip == '当前主题：跟随系统，点击切换',
      ),
    );
    await tester.pumpAndSettle();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIconButton && widget.tooltip == '当前主题：浅色模式，点击切换',
      ),
    );
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('减少动态效果时公共切换立即完成', (tester) async {
    late Duration duration;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              duration = AppTheme.motionDuration(
                context,
                AppTheme.transitionDuration,
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(duration, Duration.zero);
  });

  for (final style in AppPalette.values) {
    for (final dark in [false, true]) {
      final mode = '${style.label} · ${dark ? '深色' : '浅色'}';
      final palette = AppTheme.colorsFor(dark, palette: style);
      test('$mode 正文、说明、选中态和语义提示均可读', () {
        for (final foreground in [
          palette.ink,
          palette.inkSecondary,
          palette.muted,
        ]) {
          for (final background in [
            palette.canvas,
            palette.surface,
            palette.tableHeader,
          ]) {
            expect(
              _contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
              reason: '$foreground on $background',
            );
          }
        }
        expect(
          _contrast(palette.controlBorder, palette.surface),
          greaterThanOrEqualTo(3),
        );
        expect(
          _contrast(
            AppTheme.foruiFor(
              dark,
              palette: style,
            ).style.focusedOutlineStyle.color,
            palette.surface,
          ),
          greaterThanOrEqualTo(3),
        );
        for (final pair in [
          (palette.blue, palette.selectedBlue),
          (palette.success, palette.successSurface),
          (palette.warning, palette.warningSurface),
          (palette.destructive, palette.destructiveSurface),
          (
            AppTheme.themeFor(dark, palette: style).colorScheme.onPrimary,
            palette.blue,
          ),
          (
            AppTheme.foruiFor(dark, palette: style).colors.primaryForeground,
            palette.blue,
          ),
        ]) {
          expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
        }
      });

      test('$mode Forui 实际表单边界与焦点清晰可辨', () {
        final theme = AppTheme.foruiFor(dark, palette: style);
        for (final field in [
          theme.textFieldStyles.md,
          theme.selectStyle.fieldStyles.md,
          theme.dateFieldStyle.fieldStyles.md,
        ]) {
          expect(
            _contrast(field.border.base.borderSide.color, field.color.base!),
            greaterThanOrEqualTo(3),
          );
          final focused = field.border.resolve({FTextFieldVariant.focused});
          expect(focused.borderSide.width, greaterThanOrEqualTo(2));
          expect(
            _contrast(focused.borderSide.color, field.color.base!),
            greaterThanOrEqualTo(3),
          );
        }
      });

      testWidgets('$mode 十种科目文字在实际格底可读', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.themeFor(dark, palette: style),
            home: Builder(
              builder: (context) {
                final checked = <int>{};
                for (var i = 0; checked.length < 10 && i < 200; i++) {
                  final id = 'subject-$i';
                  if (!checked.add(SubjectColors.indexOf(id))) continue;
                  expect(
                    _contrast(
                      SubjectColors.of(context, id),
                      SubjectColors.cellBackground(context, id),
                    ),
                    greaterThanOrEqualTo(4.5),
                    reason: '$mode 科目色 ${SubjectColors.indexOf(id)}',
                  );
                }
                expect(checked.length, 10);
                return const SizedBox();
              },
            ),
          ),
        );
      });

      testWidgets('$mode 页面标题在窄窗口和放大文字下保留操作', (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var pressed = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.themeFor(dark, palette: style),
            builder: (context, child) => FTheme(
              data: AppTheme.foruiFor(dark, palette: style),
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppPageHeader(
                    title: '学期与日历',
                    subtitle: '让每一周的安排清楚有序',
                    actions: [
                      AppPrimaryButton(
                        onPressed: () => pressed = true,
                        child: const Text('新增学期'),
                      ),
                      AppSecondaryButton(
                        onPressed: () {},
                        child: const Text('导出日历'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('新增学期'));
        await tester.pumpAndSettle();
        expect(pressed, isTrue);
      });
    }
  }
}
