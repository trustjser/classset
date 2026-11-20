import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:class_set/features/scheduling/scheduling_timetable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool dark = false,
    void Function(List<ScheduleItem>, String)? onExport,
    Future<void> Function(Set<String>, bool)? onSetClassLocks,
  }) async {
    tester.view.physicalSize = const Size(1440, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final snapshot = SchedulingSnapshot(
      term: AcademicTerm(
        id: 't',
        title: '学期',
        academicYear: '2026',
        semesterLabel: '秋',
        firstTeachingWeekStart: null,
        teachingWeekCount: 20,
        createdAt: DateTime(2026),
      ),
      inputFingerprint: 'test',
      stages: const [
        SchoolStage(id: 's1', termId: 't', name: '小学部', sortOrder: 0),
        SchoolStage(id: 's2', termId: 't', name: '初中部', sortOrder: 1),
      ],
      grades: const [
        GradeGroup(id: 'g1', stageId: 's1', name: '一年级', sortOrder: 0),
        GradeGroup(id: 'g2', stageId: 's2', name: '七年级', sortOrder: 0),
      ],
      classes: const [
        ClassGroup(id: 'c1', gradeId: 'g1', name: '小学一班', sortOrder: 0),
        ClassGroup(id: 'c2', gradeId: 'g2', name: '初中一班', sortOrder: 0),
      ],
      routines: const [
        StageRoutine(
          stageId: 's1',
          teachingWeekdays: {1, 2},
          periodTypes: [
            LessonPeriodType(
              id: 'p1',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '',
                  startMinute: 480,
                  endMinute: 520,
                ),
              ],
            ),
          ],
          overrides: [],
        ),
        StageRoutine(
          stageId: 's2',
          teachingWeekdays: {1, 2},
          periodTypes: [
            LessonPeriodType(
              id: 'p2',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '',
                  startMinute: 490,
                  endMinute: 535,
                ),
              ],
            ),
            LessonPeriodType(
              id: 'p2_pm',
              name: '下午',
              defaultLessonCount: 1,
              sortOrder: 1,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '',
                  startMinute: 840,
                  endMinute: 885,
                ),
              ],
            ),
          ],
          overrides: [],
        ),
      ],
      subjects: const [
        Subject(id: 'sub', name: '数学', shortName: '数', sortOrder: 0),
      ],
      freeSlots: const [
        FreeSlot(
          id: 'free',
          scope: FreeSlotScope.stage,
          scopeId: 's2',
          stageId: 's2',
          periodTypeId: 'p2_pm',
          weekday: 2,
          lessonIndex: 1,
          label: '自习',
        ),
      ],
      teachers: const [
        Teacher(id: 'teacher', name: '张老师', shortName: '张', sortOrder: 0),
      ],
      rooms: const [
        PublicRoom(
          id: 'room',
          name: '实验室',
          roomCount: 1,
          capacityPerRoom: 1,
          sortOrder: 0,
        ),
      ],
      roomAssignments: const [
        SubjectRoomAssignment(
          id: 'r1',
          subjectId: 'sub',
          termId: 't',
          stageId: 's1',
          scope: FreeSlotScope.stage,
          scopeId: 's1',
          roomId: 'room',
        ),
        SubjectRoomAssignment(
          id: 'r2',
          subjectId: 'sub',
          termId: 't',
          stageId: 's2',
          scope: FreeSlotScope.stage,
          scopeId: 's2',
          roomId: 'room',
        ),
      ],
    );
    const items = [
      ScheduleItem(
        id: 'a',
        termId: 't',
        assignmentId: 'a',
        classId: 'c1',
        teacherId: 'teacher',
        subjectId: 'sub',
        weekMode: WeekMode.weekly,
        position: SchedulePosition(
          stageId: 's1',
          weekday: 1,
          periodTypeId: 'p1',
          lessonIndex: 1,
        ),
      ),
      ScheduleItem(
        id: 'b',
        termId: 't',
        assignmentId: 'b',
        classId: 'c2',
        teacherId: 'teacher',
        subjectId: 'sub',
        weekMode: WeekMode.odd,
        position: SchedulePosition(
          stageId: 's2',
          weekday: 1,
          periodTypeId: 'p2',
          lessonIndex: 1,
        ),
      ),
      ScheduleItem(
        id: 'c',
        termId: 't',
        assignmentId: 'c',
        classId: 'c2',
        teacherId: 'teacher',
        subjectId: 'sub',
        weekMode: WeekMode.weekly,
        position: SchedulePosition(
          stageId: 's2',
          weekday: 2,
          periodTypeId: 'p2',
          lessonIndex: 1,
        ),
      ),
    ];
    const common = {
      's1': [
        CommonPeriod(
          id: 'break1',
          stageId: 's1',
          name: '眼保健操',
          insertAfterLessonId: 'p1_1',
          durationMinutes: 10,
          startMinute: null,
          endMinute: null,
        ),
      ],
      's2': [
        CommonPeriod(
          id: 'break2',
          stageId: 's2',
          name: '午休',
          insertAfterLessonId: 'p2_1',
          durationMinutes: 30,
          startMinute: null,
          endMinute: null,
        ),
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => f.FTheme(
          data: AppTheme.foruiFor(dark),
          child: f.FToaster(child: child!),
        ),
        home: Scaffold(
          body: SchedulingTimetable(
            snapshot: snapshot,
            commonPeriods: common,
            state: const SchedulingState(items: items),
            onStart: () {},
            onRefresh: () {},
            onRules: () {},
            onReport: () {},
            onDetectionReport: () {},
            onCancel: () {},
            onDone: () {},
            onExport: onExport ?? (_, _) {},
            onPreviewMove: (_, _, _) => throw UnimplementedError(),
            onMove: (_, _, _) async => throw UnimplementedError(),
            onUndo: () {},
            onRedo: () {},
            onSetLock: (_, _) async {},
            onSetAllLocks: (_) async {},
            onSetClassLocks: onSetClassLocks,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseStage(WidgetTester tester, String stage) async {
    tester
        .widget<AppSelectField<String>>(
          find.byKey(const ValueKey('schedule-stage-selector')),
        )
        .onChanged(stage);
    await tester.pumpAndSettle();
  }

  testWidgets('教师、总课表、场室视角按学段过滤', (tester) async {
    await mount(tester);
    for (final view in ['教师课程表', '总课程表', '场室课程表']) {
      await tester.tap(find.text(view));
      await tester.pumpAndSettle();
      await chooseStage(tester, 's1');
      expect(find.text('眼保健操'), findsOneWidget, reason: view);
      expect(find.text('午休'), findsNothing, reason: view);
      expect(find.text('1 节课'), findsOneWidget, reason: view);
      await chooseStage(tester, 's2');
      expect(find.text('午休'), findsOneWidget, reason: view);
      expect(find.text('眼保健操'), findsNothing, reason: view);
      expect(find.text('2 节课'), findsOneWidget, reason: view);
      await chooseStage(tester, '');
      expect(find.text('眼保健操'), findsOneWidget, reason: view);
      expect(find.text('午休'), findsOneWidget, reason: view);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('总课表按学段分区，班级行按星期和周别展示', (tester) async {
    List<ScheduleItem>? exported;
    String? exportTitle;
    Set<String>? locked;
    await mount(
      tester,
      onExport: (items, title) {
        exported = items;
        exportTitle = title;
      },
      onSetClassLocks: (ids, enabled) async {
        if (enabled) locked = ids;
      },
    );
    await tester.tap(find.text('总课程表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按班级'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-stage-class-s1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('schedule-stage-class-s2')),
      findsOneWidget,
    );
    expect(find.text('小学一班'), findsOneWidget);
    expect(find.text('初中一班'), findsOneWidget);
    expect(find.text('眼保健操'), findsNWidgets(2));
    expect(find.text('午休'), findsNWidgets(2));
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('08:10'), findsOneWidget);
    expect(find.text('第 2 节'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    await chooseStage(tester, 's2');
    expect(find.byKey(const ValueKey('schedule-stage-class-s1')), findsNothing);
    expect(
      find.byKey(const ValueKey('schedule-stage-class-s2')),
      findsOneWidget,
    );
    await tester.tap(find.text('双周'));
    await tester.pumpAndSettle();
    expect(find.text('数学'), findsNothing);
    await tester.tap(find.text('单周'));
    await tester.pumpAndSettle();
    expect(find.textContaining('数学'), findsOneWidget);
    await tester.tap(find.text('锁定'));
    await tester.pumpAndSettle();
    expect(locked, {'c2'});
    tester
        .widget<AppSelectField<int>>(
          find.byKey(const ValueKey('schedule-weekday-selector')),
        )
        .onChanged(2);
    await tester.pumpAndSettle();
    expect(find.text('数学'), findsOneWidget);
    expect(find.text('自习'), findsOneWidget);
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(exported?.map((item) => item.id), ['c']);
    expect(exportTitle, contains('初中部'));
    expect(exportTitle, contains('周二'));
    await tester.tap(find.text('双周'));
    await tester.pumpAndSettle();
    expect(find.text('数学'), findsOneWidget);
    tester.view.physicalSize = const Size(820, 950);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-stage-class-s2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('班级总课表支持暗色主题', (tester) async {
    await mount(tester, dark: true);
    await tester.tap(find.text('总课程表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按班级'));
    await tester.pumpAndSettle();
    final container = tester.widget<Container>(
      find.byKey(const ValueKey('schedule-stage-class-s1')),
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      AppThemeColors.dark.surface,
    );
    expect(tester.takeException(), isNull);
  });
}
