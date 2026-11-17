import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
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

  /// 作息改为「保存才生效」后，saveTerm 自动创建的学段不再带默认作息；
  /// 需要作息就绪的场景显式为自动学段落库一份。
  /// 注意：取学段 id 需要 drift 流，必须包在 runAsync 里（假异步下
  /// 直接 await 流会永不完成）。
  Future<void> seedAutoStageRoutine(WidgetTester tester) async {
    await tester.runAsync(() async {
      final stages = await repository.watchStages('t1').first;
      for (final stage in stages.where((item) => item.id != 's1')) {
        await repository.saveRoutine(
          StageRoutine(
            stageId: stage.id,
            teachingWeekdays: const {1, 2, 3, 4, 5},
            periodTypes: [
              LessonPeriodType(
                id: '${stage.id}_am',
                name: '上午时段',
                defaultLessonCount: 4,
                sortOrder: 0,
                lessonTimes: const [],
              ),
            ],
            overrides: const [],
          ),
        );
      }
    });
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
    await seedAutoStageRoutine(tester);
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
    await seedAutoStageRoutine(tester);
    await seedStagesAndClasses();
    await seedRoutine();
    container.read(activeTermIdProvider.notifier).state = 't1';
    await pumpPage(tester);

    expect(find.text('2 / 6 完成'), findsOneWidget);
    expect(find.byKey(const Key('preparation-progress')), findsOneWidget);
    // 进度条渲染校验：高 8px，蓝色填充约占 1/3。
    final bar = tester.getSize(find.byKey(const Key('preparation-progress')));
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

  testWidgets('填写节数和任课后实时推进，任课不足或删除时回退', (tester) async {
    await saveTerm();
    await seedAutoStageRoutine(tester);
    await repository.saveStage(
      const SchoolStage(id: 's1', termId: 't1', name: '小学部', sortOrder: 0),
    );
    await repository.saveGrade(
      const GradeGroup(id: 'g1', stageId: 's1', name: '一年级', sortOrder: 0),
    );
    await repository.saveClass(
      const ClassGroup(id: 'c1', gradeId: 'g1', name: '一班', sortOrder: 0),
    );
    await seedRoutine();
    await repository.saveSubjects([
      const Subject(
        id: 'sub1',
        termId: 't1',
        name: '语文',
        shortName: '语',
        sortOrder: 0,
      ),
    ]);
    container.read(activeTermIdProvider.notifier).state = 't1';
    await pumpPage(tester);
    expect(find.text('2 / 6 完成'), findsOneWidget);

    await repository.replaceGradeRequirements(
      gradeId: 'g1',
      requirements: [
        const SubjectRequirement(
          id: 'r1',
          subjectId: 'sub1',
          gradeId: 'g1',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('3 / 6 完成'), findsOneWidget);
    expect(find.text('分配教师任课'), findsOneWidget);
    await tester.tap(find.text('去分配教师任课'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.teachers);

    await repository.saveTeachers([
      const Teacher(
        id: 'teacher1',
        name: '老师',
        shortName: '师',
        sortOrder: 0,
        subjectIds: {'sub1'},
      ),
    ]);
    Future<void> assign(int count) => repository.replaceTeacherAssignments(
      termId: 't1',
      classId: 'c1',
      subjectId: 'sub1',
      assignments: [
        TeacherAssignment(
          id: 'a1',
          termId: 't1',
          teacherId: 'teacher1',
          classId: 'c1',
          subjectId: 'sub1',
          weekMode: WeekMode.weekly,
          lessonCount: count,
        ),
      ],
    );
    await assign(1);
    await tester.pumpAndSettle();
    expect(find.text('3 / 6 完成'), findsOneWidget);
    await assign(2);
    await tester.pumpAndSettle();
    expect(find.text('4 / 6 完成'), findsOneWidget);
    await tester.tap(find.text('去排课'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.scheduling);
    await repository.replaceTeacherAssignments(
      termId: 't1',
      classId: 'c1',
      subjectId: 'sub1',
      assignments: [],
    );
    await tester.pumpAndSettle();
    expect(find.text('3 / 6 完成'), findsOneWidget);
  });

  testWidgets('上手指南与工作台六个步骤一致', (tester) async {
    await saveTerm();
    container.read(activeTermIdProvider.notifier).state = 't1';
    await pumpPage(tester);
    expect(find.text('查看六步上手指南'), findsOneWidget);
    await tester.ensureVisible(find.text('查看六步上手指南'));
    await tester.tap(find.text('查看六步上手指南'));
    await tester.pumpAndSettle();
    expect(find.text('六步上手指南'), findsOneWidget);
    final dialog = find.byType(AppDialog);
    for (final title in ['学段与班级', '作息设置', '科目节数', '教师任课', '开始排课', '打开课表']) {
      expect(
        find.descendant(of: dialog, matching: find.text(title)),
        findsOneWidget,
      );
    }
    expect(find.textContaining('即将推出'), findsNothing);
    expect(tester.takeException(), isNull);
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
    final end = normalizedStart.add(Duration(days: 20 * 7 - 1));
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
    // 生成包含数百条任课分配，需要等待数据库异步写入完成。
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.textContaining('已生成演示数据').evaluate().isNotEmpty) break;
    }
    expect(find.textContaining('已生成演示数据'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('4 / 6 完成'), findsOneWidget);
    expect(find.byKey(const Key('preparation-progress')), findsOneWidget);
    // 进度条渲染校验：高 8px，蓝色填充约占 1/3。
    final bar = tester.getSize(find.byKey(const Key('preparation-progress')));
    expect(bar.height, 8);
    final blueFill = tester.getSize(
      find.descendant(
        of: find.byKey(const Key('preparation-progress')),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == AppThemeColors.light.blue,
        ),
      ),
    );
    expect(blueFill.width, closeTo(bar.width * 67 / 100, 1));
    // 高度必须撑满：ColoredBox 无子节点时若 Row 不给交叉轴紧约束会得到零高度，
    // 零面积 drawRect 不产生任何可见像素（曾出现「占位不绘制」问题）。
    expect(blueFill.height, 8);
    expect(find.text('开始排课'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
