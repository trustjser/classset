import 'package:class_set/app.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/features/setup/setup_wizard_page.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

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

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClassSetApp(databasePath: 'school.sqlite'),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 走完向导：跳过校名（或填写 [schoolName]），创建默认学期。
  Future<void> completeWizard(
    WidgetTester tester, {
    String schoolName = '',
    String termTitle = '2026 学年 · 秋季学期',
  }) async {
    if (schoolName.isNotEmpty) {
      await tester.enterText(
        find.byKey(const ValueKey('wizard-school-name')),
        schoolName,
      );
    }
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('wizard-term-title')),
      termTitle,
    );
    await tester.tap(find.byWidgetPredicate((widget) => widget is FDateField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成设置，进入工作台'));
    await tester.pumpAndSettle();
  }

  group('navSectionAvailability 门控规则', () {
    test('无学期时仅保留工作台、学期与日历、公共场室', () {
      const gated = [
        AppSection.classes,
        AppSection.routines,
        AppSection.subjects,
        AppSection.teachers,
        AppSection.scheduling,
        AppSection.supervision,
        AppSection.temporaryAdjustments,
      ];
      for (final section in gated) {
        expect(navSectionAvailability(section, hasTerm: false), (
          false,
          '请先创建学期',
        ), reason: '$section 无学期时应置灰');
      }
      for (final section in [
        AppSection.workbench,
        AppSection.terms,
        AppSection.publicRooms,
      ]) {
        expect(
          navSectionAvailability(section, hasTerm: false).$1,
          isTrue,
          reason: '$section 应始终可用',
        );
      }
    });

    test('汇总尚未加载完成时不拦截导航', () {
      for (final section in AppSection.values) {
        expect(
          navSectionAvailability(section, hasTerm: true, summary: null).$1,
          isTrue,
          reason: '$section 加载期不应置灰',
        );
      }
    });

    test('学段班级未就绪时优先提示更前置的步骤', () {
      const bare = WorkbenchSummary(
        stageCount: 1,
        gradeCount: 0,
        stagesWithRoutine: 1,
      );
      expect(
        navSectionAvailability(
          AppSection.subjects,
          hasTerm: true,
          summary: bare,
        ),
        (false, '请先创建学段、年级与班级'),
      );
      expect(
        navSectionAvailability(
          AppSection.supervision,
          hasTerm: true,
          summary: bare,
        ),
        (false, '请先创建学段、年级与班级'),
      );
    });

    test('按数据就绪情况逐级解锁', () {
      // 已建学段班级但作息未配齐。
      const noRoutine = WorkbenchSummary(
        stageCount: 1,
        gradeCount: 2,
        stagesWithRoutine: 0,
      );
      expect(
        navSectionAvailability(
          AppSection.subjects,
          hasTerm: true,
          summary: noRoutine,
        ),
        (false, '请先完成各学段作息设置'),
      );
      // 作息完成，科目节数未填写。
      const noLessons = WorkbenchSummary(
        stageCount: 1,
        gradeCount: 2,
        stagesWithRoutine: 1,
      );
      expect(
        navSectionAvailability(
          AppSection.subjects,
          hasTerm: true,
          summary: noLessons,
        ).$1,
        isTrue,
      );
      expect(
        navSectionAvailability(
          AppSection.supervision,
          hasTerm: true,
          summary: noLessons,
        ).$1,
        isTrue,
      );
      expect(
        navSectionAvailability(
          AppSection.teachers,
          hasTerm: true,
          summary: noLessons,
        ),
        (false, '请先填写各年级科目节数'),
      );
      // 科目节数完成，教师任课未齐备。
      const noTeachers = WorkbenchSummary(
        stageCount: 1,
        gradeCount: 2,
        stagesWithRoutine: 1,
        subjectLessonsReady: true,
      );
      expect(
        navSectionAvailability(
          AppSection.teachers,
          hasTerm: true,
          summary: noTeachers,
        ).$1,
        isTrue,
      );
      expect(
        navSectionAvailability(
          AppSection.scheduling,
          hasTerm: true,
          summary: noTeachers,
        ),
        (false, '请先补齐各班教师任课'),
      );
      // 教师任课齐备但未生成课表。
      const noSchedule = WorkbenchSummary(
        stageCount: 1,
        gradeCount: 2,
        stagesWithRoutine: 1,
        subjectLessonsReady: true,
        teacherAssignmentsReady: true,
      );
      expect(
        navSectionAvailability(
          AppSection.scheduling,
          hasTerm: true,
          summary: noSchedule,
        ).$1,
        isTrue,
      );
      expect(
        navSectionAvailability(
          AppSection.temporaryAdjustments,
          hasTerm: true,
          summary: noSchedule,
        ),
        (false, '请先在排课与课表中生成课表'),
      );
      // 已生成课表：全部解锁。
      const done = WorkbenchSummary(
        stageCount: 1,
        gradeCount: 2,
        stagesWithRoutine: 1,
        subjectLessonsReady: true,
        teacherAssignmentsReady: true,
        hasSchedule: true,
      );
      for (final section in AppSection.values) {
        expect(
          navSectionAvailability(section, hasTerm: true, summary: done).$1,
          isTrue,
          reason: '$section 数据齐备时应可用',
        );
      }
    });
  });

  testWidgets('空库启动进入创建向导，不显示侧边栏与顶部栏', (tester) async {
    await pumpApp(tester);
    expect(find.byType(SetupWizardPage), findsOneWidget);
    expect(find.text('欢迎使用课集'), findsOneWidget);
    // 侧边栏与顶部栏均不出现。
    expect(find.text('学期与日历'), findsNothing);
    expect(find.text('工作台'), findsNothing);
    expect(find.byTooltip('编辑学校名称'), findsNothing);
    expect(find.byKey(const Key('appearance-settings-button')), findsNothing);
  });

  testWidgets('填写校名并创建学期后进入工作台，数据落库', (tester) async {
    await pumpApp(tester);
    await tester.enterText(
      find.byKey(const ValueKey('wizard-school-name')),
      '青木实验学校',
    );
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('创建第一个学期'), findsOneWidget);

    // 学期名称必填。
    await tester.enterText(
      find.byKey(const ValueKey('wizard-term-title')),
      '  ',
    );
    await tester.tap(find.text('完成设置，进入工作台'));
    await tester.pumpAndSettle();
    expect(find.text('请输入学期名称'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('wizard-term-title')),
      '2026 学年 · 秋季学期',
    );
    await tester.tap(find.byWidgetPredicate((widget) => widget is FDateField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成设置，进入工作台'));
    await tester.pumpAndSettle();

    // 进入工作台：侧边栏与学校卡出现。
    expect(find.text('先把新学期的基础搭起来'), findsOneWidget);
    expect(find.byTooltip('编辑学校名称'), findsOneWidget);
    expect(container.read(selectedSectionProvider), AppSection.workbench);

    final terms = (await tester.runAsync(() => repository.watchTerms().first))!;
    expect(terms, hasLength(1));
    expect(terms.first.title, '2026 学年 · 秋季学期');
    expect(terms.first.firstTeachingWeekStart, isNotNull);
    expect(
      await tester.runAsync(() => repository.watchSchoolName().first),
      '青木实验学校',
    );
    expect(container.read(activeTermIdProvider), terms.first.id);
    expect(await tester.runAsync(repository.loadActiveTermId), terms.first.id);
  });

  testWidgets('向导总周数加减后创建学期，步进值落库', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) => widget is FDateField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();

    // 连续两次「+」：显示值从 20 变为 22（回归保护：早先版本回调缺
    // setState，点击后界面不更新）。
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('22'), findsOneWidget);

    await tester.tap(find.text('完成设置，进入工作台'));
    await tester.pumpAndSettle();

    final terms = (await tester.runAsync(() => repository.watchTerms().first))!;
    expect(terms, hasLength(1));
    expect(terms.first.teachingWeekCount, 22);
  });

  testWidgets('新学期数据未就绪时排课相关菜单置灰且点击不切换', (tester) async {
    await pumpApp(tester);
    await completeWizard(tester);

    // 自动创建的默认学段尚无年级：科目节数与带班安排提示更前置步骤。
    expect(find.byTooltip('请先创建学段、年级与班级'), findsNWidgets(2));
    expect(find.byTooltip('请先填写各年级科目节数'), findsOneWidget);
    expect(find.byTooltip('请先补齐各班教师任课'), findsOneWidget);
    expect(find.byTooltip('请先在排课与课表中生成课表'), findsOneWidget);

    // 基础设置可用：班级与学段可切换。
    await tester.tap(find.text('班级与学段'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.classes);

    // 门控菜单点击不切换。
    await tester.tap(find.text('科目节数'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.classes);
    await tester.tap(find.text('调代课'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.classes);
    await tester.tap(find.text('排课与课表'));
    await tester.pumpAndSettle();
    expect(container.read(selectedSectionProvider), AppSection.classes);
  });

  testWidgets('演示数据就绪后按依赖解锁，调代课在生成课表前仍置灰', (tester) async {
    final term = AcademicTerm(
      id: 'demo',
      title: '2026 秋季',
      academicYear: '2026-2027',
      semesterLabel: '秋季学期',
      firstTeachingWeekStart: DateTime(2026, 9, 1),
      teachingWeekCount: 20,
      createdAt: DateTime(2026, 8, 1),
    );
    await tester.runAsync(() async {
      await repository.saveTerm(term);
      await seedDemoData(repository: repository, term: term);
    });
    await pumpApp(tester);

    // 不真正进入排课页（真实排课控制器在假异步下不完成，与既有排课
    // 测试用桩控制器的做法一致），通过侧栏菜单的可点性验证解锁。
    FTappable navTappable(String label) => tester.widget(
      find.byWidgetPredicate(
        (widget) => widget is FTappable && widget.semanticsLabel == label,
      ),
    );

    // 教师任课齐备：科目节数、教师任课、带班安排与排课与课表均解锁。
    expect(navTappable('科目节数').onPress, isNotNull);
    expect(navTappable('教师任课').onPress, isNotNull);
    expect(navTappable('带班安排').onPress, isNotNull);
    expect(navTappable('排课与课表').onPress, isNotNull);
    // 未生成课表：调代课仍置灰并说明原因。
    expect(navTappable('调代课').onPress, isNull);
    expect(find.byTooltip('请先在排课与课表中生成课表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
