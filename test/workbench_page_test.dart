import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/features/workbench/workbench_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => f.FTheme(
      data: AppTheme.foruiFor(false),
      child: f.FToaster(child: child!),
    ),
    home: const Scaffold(body: WorkbenchPage()),
  ),
);

void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repository;
  late ProviderContainer container;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftSchoolRepository(database);
    container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();
  }

  Future<void> saveTerm({DateTime? firstTeachingWeekStart}) =>
      repository.saveTerm(
        AcademicTerm(
          id: 't1',
          title: '2026 秋季',
          academicYear: '2026-2027',
          semesterLabel: '第一学期',
          firstTeachingWeekStart: firstTeachingWeekStart,
          teachingWeekCount: 20,
          createdAt: DateTime(2026, 8, 1),
        ),
      );

  Future<void> seedStagesAndClasses() async {
    await repository.saveStage(
      const SchoolStage(id: 's1', termId: 't1', name: '小学部', sortOrder: 0),
    );
    for (var g = 0; g < 3; g++) {
      await repository.saveGrade(
        GradeGroup(id: 'g$g', stageId: 's1', name: '${g + 1} 年级', sortOrder: g),
      );
    }
  }

  Future<void> seedRoutine() async {
    await repository.saveRoutine(
      StageRoutine(
        stageId: 's1',
        teachingWeekdays: const {1, 2, 3, 4, 5},
        periodTypes: const [
          LessonPeriodType(
            id: 'p1',
            name: '上午时段',
            defaultLessonCount: 4,
            sortOrder: 0,
            lessonTimes: [],
          ),
        ],
        overrides: const [],
      ),
    );
  }

  /// 清空指定学段的作息（无上课日、无时段），用于构造「作息未配置」状态。
  /// 注意：新建学段会自动带上默认作息，需显式清空。
  Future<void> clearRoutine(String stageId) async {
    await repository.saveRoutine(
      StageRoutine(
        stageId: stageId,
        teachingWeekdays: const {},
        periodTypes: const [],
        overrides: const [],
      ),
    );
  }

  testWidgets('没有学期时展示创建学期引导', (tester) async {
    await pumpPage(tester);
    expect(find.text('先创建一个学期'), findsOneWidget);
    expect(find.text('前往学期与日历'), findsOneWidget);
  });

  testWidgets('未建学段时第 1 步为当前步骤并可跳转班级与学段', (tester) async {
    await saveTerm();
    container.read(activeTermIdProvider.notifier).state = 't1';
    await pumpPage(tester);

    expect(find.text('0 / 6 完成'), findsOneWidget);
    expect(find.byKey(const Key('preparation-progress')), findsOneWidget);
    expect(find.text('创建学段与班级'), findsOneWidget);
    expect(find.text('去创建学段与班级'), findsOneWidget);
    expect(find.text('当前步骤'), findsOneWidget);
    expect(find.text('完成前一步后解锁'), findsNWidgets(5));

    await tester.tap(find.text('去创建学段与班级'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.classes);
  });

  testWidgets('学段就绪未配作息时第 2 步为当前步骤', (tester) async {
    await saveTerm();
    await seedStagesAndClasses();
    await clearRoutine('s1');
    container.read(activeTermIdProvider.notifier).state = 't1';
    await pumpPage(tester);

    expect(find.text('1 / 6 完成'), findsOneWidget);
    expect(find.text('设置各学段作息'), findsOneWidget);
    expect(find.text('1 / 2 个学段已配置作息'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('当前步骤'), findsOneWidget);

    await tester.tap(find.text('去设置作息'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.routines);
  });

  testWidgets('两步完成后第 3 步为当前步骤且可跳转科目节数', (tester) async {
    await saveTerm();
    await seedStagesAndClasses();
    await seedRoutine();
    container.read(activeTermIdProvider.notifier).state = 't1';
    await pumpPage(tester);

    expect(find.text('2 / 6 完成'), findsOneWidget);
    expect(find.byKey(const Key('preparation-progress')), findsOneWidget);
    // 进度条渲染校验：高 8px，蓝色填充约占 1/3。
    final bar = tester.getSize(
      find.byKey(const Key('preparation-progress')),
    );
    expect(bar.height, 8);
    final blueFill = tester.getSize(
      find.descendant(
        of: find.byKey(const Key('preparation-progress')),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == AppThemeColors.light.blue,
        ),
      ),
    );
    expect(blueFill.width, closeTo(bar.width * 33 / 100, 1));
    // 高度必须撑满：ColoredBox 无子节点时若 Row 不给交叉轴紧约束会得到零高度，
    // 零面积 drawRect 不产生任何可见像素（曾出现「占位不绘制」问题）。
    expect(blueFill.height, 8);
    expect(find.text('填写各年级的科目节数'), findsOneWidget);
    expect(find.text('已准备 3 个年级'), findsOneWidget);
    expect(find.text('学段与班级 · 已完成'), findsOneWidget);
    expect(find.text('作息设置 · 已完成'), findsOneWidget);
    expect(find.text('已完成'), findsNWidgets(2));
    expect(find.text('完成前一步后解锁'), findsNWidgets(3));

    await tester.tap(find.text('去填写科目节数'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.subjects);
  });

  testWidgets('当前学期卡展示教学周与单双周', (tester) async {
    final start = DateTime.now().subtract(const Duration(days: 3));
    await saveTerm(firstTeachingWeekStart: start);
    container.read(activeTermIdProvider.notifier).state = 't1';
    await pumpPage(tester);

    expect(find.text('2026-2027 学年 · 第一学期'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('第 1 教学周 · 单周'), findsOneWidget);
    final normalizedStart = DateTime(start.year, start.month, start.day);
    // 学期范围 = 第 1 教学周起始日 — 最后教学周结束日（共 teachingWeekCount 周）。
    final end = normalizedStart.add(
      Duration(days: 20 * 7 - 1),
    );
    expect(
      find.text(
        '${normalizedStart.year}年${normalizedStart.month}月${normalizedStart.day}日'
        ' — '
        '${end.year}年${end.month}月${end.day}日',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('查看学期与日历'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.terms);
  });

  testWidgets('未设置教学日历时展示提示', (tester) async {
    await saveTerm();
    container.read(activeTermIdProvider.notifier).state = 't1';
    await pumpPage(tester);

    expect(find.text('尚未设置教学日历'), findsOneWidget);
    expect(find.text('未开始'), findsOneWidget);
  });

  testWidgets('演示数据按钮播种后进度刷新', (tester) async {
    await saveTerm();
    container.read(activeTermIdProvider.notifier).state = 't1';
    await pumpPage(tester);

    expect(find.text('0 / 6 完成'), findsOneWidget);
    await tester.tap(find.text('演示数据'));
    await tester.pumpAndSettle();

    expect(find.text('2 / 6 完成'), findsOneWidget);
    expect(find.byKey(const Key('preparation-progress')), findsOneWidget);
    // 进度条渲染校验：高 8px，蓝色填充约占 1/3。
    final bar = tester.getSize(
      find.byKey(const Key('preparation-progress')),
    );
    expect(bar.height, 8);
    final blueFill = tester.getSize(
      find.descendant(
        of: find.byKey(const Key('preparation-progress')),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == AppThemeColors.light.blue,
        ),
      ),
    );
    expect(blueFill.width, closeTo(bar.width * 33 / 100, 1));
    // 高度必须撑满：ColoredBox 无子节点时若 Row 不给交叉轴紧约束会得到零高度，
    // 零面积 drawRect 不产生任何可见像素（曾出现「占位不绘制」问题）。
    expect(blueFill.height, 8);
    expect(find.text('填写各年级的科目节数'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
