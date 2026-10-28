import 'package:class_set/core/navigation/draft_navigation_guard.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/features/routines/routine_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

void main() {
  testWidgets('加载旧作息和按天差异不产生未保存修改，实际编辑仍可保存', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    late String stageId;
    await tester.runAsync(() async {
      await repository.saveTerm(
        AcademicTerm(
          id: 't',
          title: '学期',
          academicYear: '2026',
          semesterLabel: '秋',
          firstTeachingWeekStart: null,
          teachingWeekCount: 20,
          createdAt: DateTime(2026),
        ),
      );
      final stage = (await repository.watchStages('t').first).single;
      stageId = stage.id;
      await repository.saveRoutine(
        StageRoutine(
          stageId: stage.id,
          teachingWeekdays: const {1, 2, 3, 4, 5},
          periodTypes: const [
            LessonPeriodType(
              id: 'am',
              name: '上午时段',
              defaultLessonCount: 2,
              sortOrder: 0,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '',
                  startMinute: 480,
                  endMinute: 525,
                ),
                LessonTime(
                  lessonIndex: 2,
                  label: '',
                  startMinute: 535,
                  endMinute: 580,
                ),
              ],
            ),
          ],
          overrides: const [
            RoutineOverride(periodTypeId: 'am', weekday: 5, lessonCount: 1),
          ],
        ),
      );
    });
    final container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => f.FTheme(
            data: AppTheme.foruiFor(false),
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: RoutinePage(termId: 't')),
        ),
      ),
    );
    for (
      var i = 0;
      i < 100 && find.byTooltip('保存作息设置').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    final save = find.descendant(
      of: find.byTooltip('保存作息设置'),
      matching: find.byType(AppPrimaryButton),
    );
    expect(tester.widget<AppPrimaryButton>(save).onPressed, isNull);
    expect(
      container.read(draftNavigationGuardProvider).hasChangesFor('routines:t'),
      isFalse,
    );
    final legacyCell = find.byKey(const ValueKey('routine-cell-am-5-2'));
    await tester.tap(legacyCell);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(draftNavigationGuardProvider).hasChangesFor('routines:t'),
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(draftNavigationGuardProvider).hasChangesFor('routines:t'),
      isFalse,
    );
    final cell = find.byKey(const ValueKey('routine-cell-am-1-1'));
    await tester.tap(cell);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AppPrimaryButton>(save).onPressed, isNotNull);
    expect(
      container.read(draftNavigationGuardProvider).hasChangesFor('routines:t'),
      isTrue,
    );
    await tester.tap(save);
    for (
      var i = 0;
      i < 100 &&
          container
              .read(draftNavigationGuardProvider)
              .hasChangesFor('routines:t');
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      container.read(draftNavigationGuardProvider).hasChangesFor('routines:t'),
      isFalse,
    );
    final saved = (await tester.runAsync(
      () => repository.watchRoutine(stageId).first,
    ))!;
    final slots = (await tester.runAsync(
      () => repository.watchFreeSlots(stageId).first,
    ))!;
    expect(saved.overrides, isEmpty);
    expect(
      slots.any((slot) => slot.weekday == 5 && slot.lessonIndex == 2),
      isTrue,
    );
    expect(
      slots.any((slot) => slot.weekday == 1 && slot.lessonIndex == 1),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => f.FTheme(
            data: AppTheme.foruiFor(false),
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: RoutinePage(termId: 't')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(draftNavigationGuardProvider).hasChangesFor('routines:t'),
      isFalse,
    );
    expect(tester.widget<AppPrimaryButton>(save).onPressed, isNull);
  });
}
