import 'dart:async';
import 'dart:io';

import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_appearance.dart';
import 'package:class_set/data/repositories/appearance_preferences_repository.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/core/widgets/appearance_settings_dialog.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:forui/forui.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 空库会进入创建向导（无顶部栏），先种一个学期以便测试外观入口。
AcademicTerm _seedTerm() => AcademicTerm(
  id: 'appearance-seed',
  title: '2026 秋季',
  academicYear: '2026-2027',
  semesterLabel: '秋季学期',
  firstTeachingWeekStart: DateTime(2026, 9, 1),
  teachingWeekCount: 20,
  createdAt: DateTime(2026, 8, 1),
);

void main() {
  testWidgets('三套配色可直接选择，明暗模式独立，关闭后保留选择', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    await tester.runAsync(() => repository.saveTerm(_seedTerm()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
        child: const ClassSetApp(databasePath: 'preview.sqlite'),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('appearance-settings-button'));
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('主题与外观'), findsOneWidget);
    await tester.tap(find.text('海盐青'));
    await tester.pumpAndSettle();
    ColorScheme colors() =>
        Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;
    expect(colors().primary, const Color(0xFF087D89));
    expect(colors().brightness, Brightness.light);
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(colors().primary, const Color(0xFF78D7D6));
    expect(colors().brightness, Brightness.dark);
    final dialogContext = tester.element(find.byType(AppearanceSettingsDialog));
    expect(Theme.of(dialogContext).brightness, Brightness.dark);
    expect(dialogContext.appColors.accent, const Color(0xFF78D7D6));
    expect(FTheme.of(dialogContext).colors.primary, const Color(0xFF78D7D6));
    await tester.tap(find.text('云白墨灰'));
    await tester.pumpAndSettle();
    expect(colors().primary, const Color(0xFFBDCEE9));
    expect(colors().brightness, Brightness.dark);
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(colors().primary, const Color(0xFF3E4F6D));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(colors().primary, const Color(0xFFBDCEE9));
    await tester.tap(find.widgetWithText(AppPrimaryButton, '完成'));
    await tester.pumpAndSettle();
    expect(find.text('主题与外观'), findsNothing);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(colors().primary, const Color(0xFFBDCEE9));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('实际选择保存到文件，重新打开应用恢复配色和明暗', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('appearance-ui-'),
    );
    addTearDown(() => directory!.delete(recursive: true));
    final file = File.fromUri(directory!.uri.resolve('appearance.json'));
    // Flutter 的手势回调会回到注册时的 FakeAsync zone；真实文件 I/O
    // 和写入队列的初始 Future 必须在 runAsync 的真实 zone 中创建。
    final persistenceZone = (await tester.runAsync(() async => Zone.current))!;
    final preferences = persistenceZone.run(
      () => AppearancePreferencesRepository(file),
    );
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    final container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => repository.saveTerm(_seedTerm()));
    Future<void>? pending;
    Widget app(AppAppearance initial) => UncontrolledProviderScope(
      container: container,
      child: ClassSetApp(
        databasePath: 'preview.sqlite',
        initialAppearance: initial,
        onAppearanceChanged: (value) => pending = persistenceZone
            .run<Future<void>>(() => preferences.save(value)),
      ),
    );
    await tester.pumpWidget(app(const AppAppearance()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('海盐青'));
    await tester.runAsync(() => pending!);
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色模式'));
    await tester.runAsync(() => pending!);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppPrimaryButton, '完成'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final restored = await tester.runAsync(
      () => AppearancePreferencesRepository(file).load(),
    );
    await tester.pumpWidget(app(restored!));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).colorScheme.primary, const Color(0xFF78D7D6));
    await tester.tap(find.byKey(const Key('appearance-settings-button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppearanceSettingsDialog>(
            find.byType(AppearanceSettingsDialog),
          )
          .appearance,
      const AppAppearance(
        palette: AppPalette.teal,
        mode: AppAppearanceMode.dark,
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('主题对话框在窄窗口和大字号下仍可完成选择', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var appearance = const AppAppearance();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => FTheme(
          data: AppTheme.foruiFor(false),
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, update) => AppearanceSettingsDialog(
                appearance: appearance,
                onChanged: (next) => update(() => appearance = next),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('云白墨灰'));
    await tester.tap(find.text('云白墨灰'));
    await tester.pumpAndSettle();
    expect(appearance.palette, AppPalette.cloud);
    expect(find.text('完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('偏好保存失败后可直接重试当前选择', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    var fail = true;
    AppAppearance? saved;
    await tester.runAsync(() => repository.saveTerm(_seedTerm()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
        child: ClassSetApp(
          databasePath: 'preview.sqlite',
          onAppearanceChanged: (value) async {
            if (fail) {
              fail = false;
              throw const FileSystemException('cannot save');
            }
            saved = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('海盐青'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppPrimaryButton, '完成'));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(saved?.palette, AppPalette.teal);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
