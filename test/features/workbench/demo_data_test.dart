import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/features/routines/routine_page.dart';
import 'package:class_set/features/subjects/subjects_page.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart' as f;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('科目节数按周模式继承年级值并允许班级覆盖', () {
    const requirements = [
      SubjectRequirement(
        id: 'grade',
        subjectId: 's',
        gradeId: 'g',
        weekMode: WeekMode.weekly,
        lessonCount: 8,
      ),
      SubjectRequirement(
        id: 'odd',
        subjectId: 's',
        gradeId: 'g',
        weekMode: WeekMode.odd,
        lessonCount: 2,
      ),
      SubjectRequirement(
        id: 'class',
        subjectId: 's',
        gradeId: 'g',
        classId: 'c',
        weekMode: WeekMode.weekly,
        lessonCount: 5,
      ),
      SubjectRequirement(
        id: 'other',
        subjectId: 's',
        gradeId: 'other',
        weekMode: WeekMode.even,
        lessonCount: 7,
      ),
    ];
    final values = valuesForClass(
      subjectId: 's',
      classId: 'c',
      gradeId: 'g',
      requirements: requirements,
    );
    expect((values.weekly, values.odd, values.even), (5, 2, 0));
  });
  test('演示数据复用默认学段并完整生成作息、课程和任课', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    final term = AcademicTerm(
      id: 'term',
      title: '秋季',
      academicYear: '2026',
      semesterLabel: '秋',
      firstTeachingWeekStart: null,
      teachingWeekCount: 20,
      createdAt: DateTime(2026),
    );
    await repository.saveTerm(term);
    final original = (await repository.watchStages(term.id).first).single;
    await seedDemoData(repository: repository, term: term);
    final stages = await repository.watchStages(term.id).first;
    expect(stages.map((s) => s.name), ['小学部', '初中部']);
    expect(stages.first.id, original.id);
    final grades = await repository.watchGradesForTerm(term.id).first;
    final classes = await repository.watchClassesForTerm(term.id).first;
    expect(grades.length, 9);
    for (final grade in grades) {
      expect(
        classes.where((c) => c.gradeId == grade.id).length,
        grade.stageId == stages.first.id ? 6 : 8,
      );
    }
    final primary = (await repository.watchRoutine(stages.first.id).first)!;
    final junior = (await repository.watchRoutine(stages.last.id).first)!;
    expect(primary.periodTypes.map((p) => p.defaultLessonCount), [4, 3]);
    expect(junior.periodTypes.map((p) => p.defaultLessonCount), [4, 3, 2]);
    expect(junior.teachingWeekdays, {1, 2, 3, 4, 5, 7});
    expect(junior.overrides, isEmpty);
    for (final stage in stages) {
      final common = await repository.watchCommonPeriods(stage.id).first;
      expect(common.map((p) => p.name).toSet(), {'眼保健操', '午休'});
      final am = stage.id == stages.first.id
          ? primary.periodTypes.first
          : junior.periodTypes.first;
      expect(
        common.firstWhere((p) => p.name == '眼保健操').insertAfterLessonId,
        '${am.id}_2',
      );
      expect(
        common.firstWhere((p) => p.name == '午休').insertAfterLessonId,
        '${am.id}_4',
      );
    }
    final free = await repository.watchFreeSlots(stages.last.id).first;
    expect(free.length, 20);
    expect(free.where((s) => s.label == '自习').length, 10);
    expect(free.where((s) => s.label == '不上课').length, 10);
    expect(
      free.any(
        (s) =>
            s.periodTypeId == junior.periodTypes[1].id &&
            s.weekday == 5 &&
            s.lessonIndex == 3 &&
            s.label == '不上课',
      ),
      isTrue,
    );
    final snapshot = await repository.loadSchedulingSnapshot(term.id);
    expect(snapshot.subjects, isNotEmpty);
    expect(snapshot.teachers, isNotEmpty);
    expect(snapshot.assignments, isNotEmpty);
    for (final grade in grades) {
      final requirements = snapshot.requirements
          .where((r) => r.gradeId == grade.id)
          .toList();
      final total = requirements.fold<int>(0, (n, r) => n + r.lessonCount);
      expect(
        total,
        grade.stageId == stages.last.id ? 34 : (grade.sortOrder < 2 ? 26 : 30),
      );
      for (final schoolClass in classes.where((c) => c.gradeId == grade.id)) {
        for (final requirement in requirements) {
          final assignments = snapshot.assignments.where(
            (a) =>
                a.classId == schoolClass.id &&
                a.subjectId == requirement.subjectId,
          );
          expect(
            assignments.fold<int>(0, (n, a) => n + a.lessonCount),
            requirement.lessonCount,
          );
        }
      }
    }
    final problem = const ProblemBuilder().build(snapshot);
    expect(
      problem.checks.where((c) => !c.ready).map((c) => c.message),
      isEmpty,
    );
    for (final teacher in snapshot.teachers) {
      final load = snapshot.assignments
          .where((a) => a.teacherId == teacher.id)
          .fold<int>(0, (sum, a) => sum + a.lessonCount);
      expect(load, lessThanOrEqualTo(18));
    }
    await expectLater(
      seedDemoData(repository: repository, term: term),
      throwsStateError,
    );
    expect((await repository.watchGradesForTerm(term.id).first).length, 9);
  });

  testWidgets('生成的数据在作息和科目页面可见且保留按天差异', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    final term = AcademicTerm(
      id: 'display',
      title: '学期',
      academicYear: '2026',
      semesterLabel: '秋季',
      firstTeachingWeekStart: null,
      teachingWeekCount: 20,
      createdAt: DateTime(2026),
    );
    final snapshot = (await tester.runAsync(() async {
      await repository.saveTerm(term);
      await seedDemoData(repository: repository, term: term);
      // 模拟旧版本通过按天节数覆盖生成的数据。
      final stage = (await repository.watchStages(term.id).first).last;
      final routine = (await repository.watchRoutine(stage.id).first)!;
      for (final slot in await repository.watchFreeSlots(stage.id).first) {
        if (slot.label == FreeSlotLabels.noClass) {
          await repository.deleteFreeSlot(slot.id);
        }
      }
      await repository.saveRoutine(
        StageRoutine(
          stageId: stage.id,
          teachingWeekdays: routine.teachingWeekdays,
          periodTypes: routine.periodTypes,
          overrides: [
            RoutineOverride(
              periodTypeId: routine.periodTypes[1].id,
              weekday: 5,
              lessonCount: 2,
            ),
            RoutineOverride(
              periodTypeId: routine.periodTypes[2].id,
              weekday: 5,
              lessonCount: 0,
            ),
            RoutineOverride(
              periodTypeId: routine.periodTypes[0].id,
              weekday: 7,
              lessonCount: 0,
            ),
            RoutineOverride(
              periodTypeId: routine.periodTypes[1].id,
              weekday: 7,
              lessonCount: 0,
            ),
          ],
        ),
      );
      return repository.loadSchedulingSnapshot(term.id);
    }))!;
    final primary = snapshot.stages.first;
    final junior = snapshot.stages.last;
    final grade = snapshot.grades.first;
    final chinese = snapshot.subjects.firstWhere((s) => s.name == '语文');
    final primaryRoutine = snapshot.routines.firstWhere(
      (r) => r.stageId == primary.id,
    );
    final juniorRoutine = snapshot.routines.firstWhere(
      (r) => r.stageId == junior.id,
    );
    final container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    Widget wrap(Widget child) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => f.FTheme(
          data: AppTheme.foruiFor(false),
          child: f.FToaster(child: child!),
        ),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpWidget(wrap(RoutinePage(termId: term.id)));
    await tester.pumpAndSettle();
    expect(find.text('小学部 · 7 节'), findsOneWidget);
    expect(find.text('35 格 / 班'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey('routine-cell-${primaryRoutine.periodTypes[1].id}-1-3'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('routine-cell-${primaryRoutine.periodTypes[1].id}-1-4'),
      ),
      findsNothing,
    );
    final first = find.byKey(
      ValueKey('routine-cell-${primaryRoutine.periodTypes[0].id}-1-2'),
    );
    final third = find.byKey(
      ValueKey('routine-cell-${primaryRoutine.periodTypes[0].id}-1-3'),
    );
    expect(
      tester.getTopLeft(find.textContaining('眼保健操 · 10 分钟').first).dy,
      greaterThan(tester.getTopLeft(first).dy),
    );
    expect(
      tester.getTopLeft(find.textContaining('眼保健操 · 10 分钟').first).dy,
      lessThan(tester.getTopLeft(third).dy),
    );
    await tester.tap(find.text('初中部 · 9 节'));
    await tester.pumpAndSettle();
    expect(find.text('34 格 / 班'), findsOneWidget);
    final evening = juniorRoutine.periodTypes.last.id;
    expect(
      find.descendant(
        of: find.byKey(ValueKey('routine-cell-$evening-1-1')),
        matching: find.text('自习'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('routine-cell-$evening-5-1')),
        matching: find.text('不上课'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          ValueKey('routine-cell-${juniorRoutine.periodTypes.first.id}-7-1'),
        ),
        matching: find.text('不上课'),
      ),
      findsOneWidget,
    );
    final friday = find.byKey(ValueKey('routine-cell-$evening-5-1'));
    await tester.tap(friday);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: friday, matching: find.text('不上课')),
      findsNothing,
    );
    expect(find.text('35 格 / 班'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: friday, matching: find.text('不上课')),
      findsOneWidget,
    );
    expect(find.text('34 格 / 班'), findsOneWidget);
    await tester.tap(find.byTooltip('保存作息设置'));
    await tester.pumpAndSettle();
    final savedRoutine = (await tester.runAsync(
      () => repository.watchRoutine(junior.id).first,
    ))!;
    expect(savedRoutine.effectiveLessonCount(evening, 5), 2);
    expect(
      savedRoutine.effectiveLessonCount(juniorRoutine.periodTypes.first.id, 7),
      4,
    );
    expect(
      (await tester.runAsync(() => repository.watchFreeSlots(junior.id).first))!
          .length,
      20,
    );
    final monday = find.byKey(
      ValueKey('routine-cell-${juniorRoutine.periodTypes.first.id}-1-1'),
    );
    await tester.tap(monday, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('自定义名称…'), findsOneWidget);
    final menuItem = find.byWidgetPredicate(
      (widget) => widget is AppMenuTile && widget.item.label == '不上课',
    );
    await tester.tap(menuItem);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: monday, matching: find.text('不上课')),
      findsOneWidget,
    );
    expect(find.text('33 格 / 班'), findsOneWidget);
    await tester.tap(find.byTooltip('保存作息设置'));
    await tester.pumpAndSettle();
    final updated = (await tester.runAsync(
      () => repository.loadSchedulingSnapshot(term.id),
    ))!;
    expect(
      updated.freeSlots.any(
        (s) =>
            s.stageId == junior.id &&
            s.periodTypeId == juniorRoutine.periodTypes.first.id &&
            s.weekday == 1 &&
            s.lessonIndex == 1 &&
            s.label == '不上课',
      ),
      isTrue,
    );
    expect(
      const ProblemBuilder()
          .build(updated)
          .checks
          .any(
            (check) =>
                check.code == 'capacity' && check.message.contains('可用 33'),
          ),
      isTrue,
    );
    await tester.pumpWidget(wrap(SubjectsPage(termId: term.id)));
    await tester.pumpAndSettle();
    final cell = find.byKey(ValueKey('subject-cell-${chinese.id}-${grade.id}'));
    expect(find.descendant(of: cell, matching: find.text('8')), findsOneWidget);
    await tester.pumpWidget(wrap(RoutinePage(termId: term.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('初中部 · 9 节'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: monday, matching: find.text('不上课')),
      findsOneWidget,
    );
    expect(find.text('33 格 / 班'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
