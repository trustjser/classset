import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/scheduling_page.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

class _TestSchedulingController extends SchedulingController {
  _TestSchedulingController(
    DriftSchoolRepository repository,
    SchedulingSnapshot snapshot,
  ) : super(repository, snapshot.term.id) {
    state = SchedulingState(status: SchedulingStatus.ready, snapshot: snapshot);
  }

  @override
  Future<void> refresh({bool preserveHistory = false}) async {}
}

void main() {
  testWidgets('课表按作息位置展示公共时段，删除后不会自动补充午休', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    final term = AcademicTerm(
      id: 't',
      title: '学期',
      academicYear: '2026',
      semesterLabel: '秋',
      firstTeachingWeekStart: null,
      teachingWeekCount: 20,
      createdAt: DateTime(2026),
    );
    final fixture = (await tester.runAsync(() async {
      await repository.saveTerm(term);
      final stage = (await repository.watchStages('t').first).single;
      await repository.saveGrade(
        GradeGroup(id: 'g', stageId: stage.id, name: '一年级', sortOrder: 0),
      );
      await repository.saveClass(
        const ClassGroup(id: 'c', gradeId: 'g', name: '一班', sortOrder: 0),
      );
      await repository.saveRoutine(
        StageRoutine(
          stageId: stage.id,
          teachingWeekdays: const {1, 2, 3, 4, 5},
          periodTypes: const [
            LessonPeriodType(
              id: 'am',
              name: '上午',
              defaultLessonCount: 4,
              sortOrder: 0,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '',
                  startMinute: 480,
                  endMinute: 520,
                ),
                LessonTime(
                  lessonIndex: 2,
                  label: '',
                  startMinute: 530,
                  endMinute: 570,
                ),
                LessonTime(
                  lessonIndex: 3,
                  label: '',
                  startMinute: 590,
                  endMinute: 630,
                ),
                LessonTime(
                  lessonIndex: 4,
                  label: '',
                  startMinute: 640,
                  endMinute: 680,
                ),
              ],
            ),
            LessonPeriodType(
              id: 'pm',
              name: '下午',
              defaultLessonCount: 1,
              sortOrder: 1,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '',
                  startMinute: 840,
                  endMinute: 880,
                ),
              ],
            ),
          ],
          overrides: const [],
        ),
      );
      await repository.saveCommonPeriod(
        CommonPeriod(
          id: 'eyes',
          stageId: stage.id,
          name: '眼保健操',
          insertAfterLessonId: 'am_2',
          durationMinutes: 10,
          startMinute: null,
          endMinute: null,
        ),
      );
      await repository.saveCommonPeriod(
        CommonPeriod(
          id: 'rest',
          stageId: stage.id,
          name: '午休',
          insertAfterLessonId: 'am_4',
          durationMinutes: 120,
          startMinute: null,
          endMinute: null,
        ),
      );
      return (stage.id, await repository.loadSchedulingSnapshot(term.id));
    }))!;
    final stageId = fixture.$1;
    final container = ProviderContainer(
      overrides: [
        schoolRepositoryProvider.overrideWithValue(repository),
        schedulingControllerProvider('t').overrideWith(
          (ref) => _TestSchedulingController(repository, fixture.$2),
        ),
      ],
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
          home: const Scaffold(body: SchedulingPage(termId: 't')),
        ),
      ),
    );
    for (var i = 0; i < 100 && find.text('眼保健操').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final state = container.read(schedulingControllerProvider('t'));
    expect(
      state.snapshot,
      isNotNull,
      reason: '状态：${state.status} ${state.error}',
    );
    expect(find.text('眼保健操'), findsOneWidget);
    expect(find.text('午休'), findsOneWidget);
    expect(find.text('午 休'), findsNothing);
    expect(
      tester.getTopLeft(find.text('眼保健操')).dy,
      greaterThan(tester.getTopLeft(find.textContaining('第 2 节 · 08:50')).dy),
    );
    expect(
      tester.getTopLeft(find.text('眼保健操')).dy,
      lessThan(tester.getTopLeft(find.textContaining('第 3 节 · 09:50')).dy),
    );
    expect(
      tester.getTopLeft(find.text('午休')).dy,
      greaterThan(tester.getTopLeft(find.textContaining('第 4 节 · 10:40')).dy),
    );
    await tester.runAsync(() async {
      await repository.deleteCommonPeriod('rest');
    });
    await tester.pumpAndSettle();
    expect(find.text('午休'), findsNothing);
    expect(find.text('午 休'), findsNothing);
    expect(
      (await tester.runAsync(
        () => repository.watchCommonPeriods(stageId).first,
      ))!.length,
      1,
    );
    for (final tab in ['教师课程表', '总课程表', '场室课程表', '班级课程表']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text('眼保健操'), findsOneWidget, reason: tab);
      expect(find.text('午休'), findsNothing, reason: tab);
    }
  });
}
