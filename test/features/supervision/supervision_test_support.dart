import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/supervision/supervision_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

/// 抽屉是全高的，会盖住右上角工具栏；操作底层控件前先关闭。
Future<void> closeTeacherDrawer(WidgetTester tester) async {
  final close = find.byKey(const ValueKey('duty-teacher-close'));
  if (close.evaluate().isEmpty) return;
  await tester.tap(close);
  await tester.pumpAndSettle();
}

/// 新设计把「岗位人员设置」收进面板右上角的 ⋯ 菜单。
Future<void> openPostPersonnelSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('duty-teacher-more')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('岗位人员设置'));
  await tester.pumpAndSettle();
}

/// 桌面侧栏候选卡片：选中后需由主按钮确认才落草稿。
Future<void> pickTeacherInPanel(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('duty-teacher-panel')),
      matching: find.text(name),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认指派'));
  await tester.pumpAndSettle();
}

Future<void> clearAssignmentInPanel(WidgetTester tester) async {
  await tester.tap(find.text('清除指派'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认清除'));
  await tester.pumpAndSettle();
}

Future<SupervisionDraft> saveSupervisionFromUi(
  WidgetTester tester,
  TestSupervisionRepository repository,
) async {
  repository.lastSave = null;
  await tester.tap(find.text('保存草稿'));
  await tester.pump();
  expect(repository.lastSave, isNotNull);
  SupervisionDraft? saved;
  Object? failure;
  var completed = false;
  repository.lastSave!.then(
    (value) {
      saved = value;
      completed = true;
    },
    onError: (Object error) {
      failure = error;
      completed = true;
    },
  );
  // A native Drift transaction can need several fake-clock microtask turns.
  // Wait for its actual completion while allowing both queues to progress.
  for (var i = 0; i < 100 && !completed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(completed, isTrue, reason: '保存操作应完成');
  expect(failure, isNull);
  await tester.pumpAndSettle();
  return saved!;
}

Future<void> mouseSelectSupervision(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: from);
  await gesture.down(from);
  await gesture.moveTo(Offset(from.dx + 24, from.dy));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await gesture.removePointer();
  await tester.pumpAndSettle();
}

Future<ProviderContainer> openSupervision(
  WidgetTester tester,
  TestSupervisionRepository repository,
) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
        home: const Scaffold(body: SupervisionPage(termId: 't')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

class TestSupervisionRepository extends DriftSchoolRepository {
  TestSupervisionRepository(super.database, this.fixture);
  final SchedulingSnapshot fixture;
  Future<SupervisionDraft>? lastSave;
  final baselineLoads = <Future<SchedulingSnapshot?>>[];
  @override
  Future<SchedulingSnapshot?> loadPendingSchedulingBaseline(String termId) {
    final operation = super.loadPendingSchedulingBaseline(termId);
    baselineLoads.add(operation);
    return operation;
  }

  @override
  Future<SupervisionDraft> saveSupervisionDraft(
    SupervisionDraft draft, {
    required int expectedRevision,
  }) {
    return lastSave = super.saveSupervisionDraft(
      draft,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<SchedulingSnapshot> loadSchedulingSnapshot(String termId) async =>
      fixture;
}

final supervisionTerm = AcademicTerm(
  id: 't',
  title: '学期',
  academicYear: '2026',
  semesterLabel: '秋',
  firstTeachingWeekStart: DateUtils.dateOnly(DateTime.now())
      .subtract(Duration(days: DateTime.now().weekday - 1)),
  teachingWeekCount: 8,
  createdAt: DateTime(2026),
);

SchedulingSnapshot supervisionSnapshot({int classCount = 2}) =>
    SchedulingSnapshot(
      term: supervisionTerm,
      inputFingerprint: 'selection',
      stages: const [
        SchoolStage(id: 'stage', termId: 't', name: '初中', sortOrder: 0),
      ],
      grades: const [
        GradeGroup(id: 'grade', stageId: 'stage', name: '初一', sortOrder: 0),
      ],
      classes: [
        for (var i = 1; i <= classCount; i++)
          ClassGroup(id: 'c$i', gradeId: 'grade', name: '初一$i班', sortOrder: i),
      ],
      teachers: const [
        Teacher(id: 'teacher', name: '张老师', shortName: '张', sortOrder: 0),
        Teacher(id: 'second', name: '李老师', shortName: '李', sortOrder: 1),
      ],
      subjects: const [
        Subject(id: 'math', name: '数学', shortName: '数', sortOrder: 0),
        Subject(id: 'chinese', name: '语文', shortName: '语', sortOrder: 1),
      ],
      assignments: const [
        TeacherAssignment(
          id: 'ta',
          termId: 't',
          teacherId: 'teacher',
          classId: 'c1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 3,
        ),
        TeacherAssignment(
          id: 'tb',
          termId: 't',
          teacherId: 'second',
          classId: 'c2',
          subjectId: 'chinese',
          weekMode: WeekMode.weekly,
          lessonCount: 3,
        ),
      ],
      routines: const [
        StageRoutine(
          stageId: 'stage',
          teachingWeekdays: {1, 5, 7},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'service',
              name: '课后服务',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '托管',
                  startMinute: 990,
                  endMinute: 1050,
                ),
              ],
            ),
            LessonPeriodType(
              id: 'evening',
              name: '晚上',
              defaultLessonCount: 3,
              sortOrder: 1,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '晚一',
                  startMinute: 1100,
                  endMinute: 1145,
                ),
                LessonTime(
                  lessonIndex: 2,
                  label: '晚二',
                  startMinute: 1155,
                  endMinute: 1200,
                ),
                LessonTime(
                  lessonIndex: 3,
                  label: '晚三',
                  startMinute: 1210,
                  endMinute: 1255,
                ),
              ],
            ),
          ],
        ),
      ],
      freeSlots: [
        for (final day in [1, 5, 7])
          for (final period in ['service', 'evening'])
            for (var i = 1; i <= (period == 'service' ? 1 : 3); i++)
              FreeSlot(
                id: '$day-$period-$i',
                scope: FreeSlotScope.stage,
                scopeId: 'stage',
                stageId: 'stage',
                periodTypeId: period,
                weekday: day,
                lessonIndex: i,
                label: period == 'service' ? '课后服务' : '自习',
              ),
      ],
    );
const supervisionDraft = SupervisionDraft(
  termId: 't',
  teacherIds: {'teacher', 'second'},
  posts: [
    SupervisionPost(
      id: 'a',
      kind: SupervisionKind.afterSchool,
      name: '课后服务',
      stageId: 'stage',
      weekday: 1,
      periodTypeId: 'service',
      lessonIndices: [1],
      classIds: ['c1'],
    ),
    SupervisionPost(
      id: 'b',
      kind: SupervisionKind.afterSchool,
      name: '课后服务',
      stageId: 'stage',
      weekday: 5,
      periodTypeId: 'service',
      lessonIndices: [1],
      classIds: ['c1'],
    ),
    SupervisionPost(
      id: 'c',
      kind: SupervisionKind.afterSchool,
      name: '课后服务',
      stageId: 'stage',
      weekday: 7,
      periodTypeId: 'service',
      lessonIndices: [1],
      classIds: ['c2'],
    ),
    SupervisionPost(
      id: 'merged',
      kind: SupervisionKind.eveningStudy,
      name: '晚自习',
      groupName: '阅读合班',
      location: '阅览室',
      stageId: 'stage',
      weekday: 7,
      periodTypeId: 'evening',
      lessonIndices: [2, 3],
      classIds: ['c1', 'c2'],
    ),
  ],
  assignments: {
    'a': 'teacher',
    'b': 'second',
    'c': 'teacher',
    'merged': 'second',
  },
  manualPostIds: {'a', 'b', 'c', 'merged'},
);
