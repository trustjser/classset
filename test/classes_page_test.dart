import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/features/classes/classes_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => FTheme(
      data: AppTheme.forui,
      child: FToaster(child: child!),
    ),
    home: const Scaffold(body: ClassesPage(termId: 't1')),
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
    await repository.saveTerm(
      AcademicTerm(
        id: 't1',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    final stage = (await repository.watchStages('t1').first).single;
    await repository.saveStage(
      const SchoolStage(id: 'stage2', termId: 't1', name: '初中部', sortOrder: 1),
    );
    await repository.saveGrade(
      GradeGroup(id: 'g1', stageId: stage.id, name: '一年级', sortOrder: 0),
    );
    await repository.saveClass(
      const ClassGroup(id: 'c1', gradeId: 'g1', name: '一班', sortOrder: 0),
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  testWidgets('新增班级可一次指定数量并保留年级归属', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加班级'));
    await tester.pumpAndSettle();
    expect(find.text('新增班级'), findsOneWidget);
    expect(find.text('数量'), findsOneWidget);
    await tester.enterText(find.widgetWithText(AppTextFormField, '数量'), '3');
    await tester.tap(find.text('添加').last);
    await tester.pumpAndSettle();
    expect(find.text('一（1）班'), findsOneWidget);
    expect(find.text('一（2）班'), findsOneWidget);
    expect(find.text('一（3）班'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量新增年级会跳过已有名称并展示预览', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('add-grade-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-grade-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('二年级、三年级、四年级'), findsOneWidget);
    await tester.tap(find.text('添加').last);
    await tester.pumpAndSettle();
    expect(find.text('二年级'), findsOneWidget);
    expect(find.text('三年级'), findsOneWidget);
    expect(find.text('四年级'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑年级可以迁移到另一学段并保留班级', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑').first);
    await tester.pumpAndSettle();
    final stageField = find.descendant(
      of: find.byType(AppDialog),
      matching: find.byType(AppSelectField<String>),
    );
    expect(stageField, findsOneWidget);
    tester.widget<AppSelectField<String>>(stageField).onChanged('stage2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppBadge && widget.label == '初中部',
      ),
      findsOneWidget,
    );
    expect(find.text('一班'), findsOneWidget);
  });

  testWidgets('班级名称可在表格行内编辑', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('一班'));
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text('回车保存 · Esc 取消'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '新一班');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('新一班'), findsOneWidget);
    expect(find.text('回车保存 · Esc 取消'), findsNothing);
  });

  testWidgets('批量填充后可以撤销且不改变班级顺序', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('批量填充名称').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 1 个学段'), findsOneWidget);
    await tester.tap(find.text('应用填充'));
    await tester.pumpAndSettle();
    expect(find.text('一（1）班'), findsOneWidget);

    await tester.tap(find.text('批量填充名称').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销上次填充'));
    await tester.pumpAndSettle();
    expect(find.text('一班'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('学段新增卡保持窄卡宽度，表格随内容收起', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    final addCard = tester.getRect(find.byKey(const Key('add-stage-card')));
    final stageCard = tester.getRect(
      find
          .ancestor(
            of: find.text('小学部').first,
            matching: find.byType(AppSurface),
          )
          .first,
    );
    expect(addCard.width, lessThan(stageCard.width));
    expect(addCard.height, stageCard.height);
    final dots = tester
        .widgetList<AppStageDot>(find.byType(AppStageDot))
        .toList();
    expect(dots.first.color, AppTheme.blue);
    expect(dots.last.color, const Color(0xFF2BA471));
    expect(tester.getRect(find.textContaining('共 2 个学段')).top, lessThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄而矮的窗口可滚动且不出现布局溢出', (tester) async {
    tester.view.physicalSize = const Size(620, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有年级的学段不可直接删除，年级删除需确认旗下班级', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    final stageCard = find
        .ancestor(of: find.text('小学部').first, matching: find.byType(AppSurface))
        .first;
    final stageDelete = find.descendant(
      of: stageCard,
      matching: find.text('删除'),
    );
    final stageDeleteInk = find
        .ancestor(of: stageDelete, matching: find.byType(InkWell))
        .first;
    expect(tester.widget<InkWell>(stageDeleteInk).onTap, isNull);

    await tester.tap(find.text('编辑').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').at(2));
    await tester.pumpAndSettle();
    expect(find.textContaining('将删除「一年级」及其 1 个班级'), findsOneWidget);
    expect(find.textContaining('科目节数'), findsOneWidget);
    await tester.tap(find.text('同时删除旗下班级'));
    await tester.pumpAndSettle();
    final confirm = tester.widget<AppDestructiveButton>(
      find.widgetWithText(AppDestructiveButton, '确认删除'),
    );
    expect(confirm.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重复的学段名称显示校验错误', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-stage-card')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppTextFormField).last, '小学部');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('学段名称已存在'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('顺序调整', () {
    setUp(() async {
      final stage = (await repository.watchStages('t1').first).first;
      await repository.saveGrade(
        GradeGroup(id: 'g2', stageId: stage.id, name: '二年级', sortOrder: 7),
      );
      await repository.saveClass(
        const ClassGroup(id: 'c2', gradeId: 'g1', name: '二班', sortOrder: 8),
      );
    });

    testWidgets('非连续排序值的年级仍可拖拽调整顺序', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('一年级').first),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('二年级')).dy,
        lessThan(tester.getTopLeft(find.text('一年级').first).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('非连续排序值的班级仍能下移', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(container));
      await tester.pumpAndSettle();

      final chip = tester.widget<AppClassChip>(
        find.byWidgetPredicate(
          (widget) => widget is AppClassChip && widget.name == '一班',
        ),
      );
      chip.onMoveDown!();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('二班')).dx,
        lessThan(tester.getTopLeft(find.text('一班')).dx),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
