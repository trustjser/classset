import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/course_scheduler.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('相同输入与种子生成相同课表，班级课节不冲突', () {
    final problem = _problem(slotCount: 2);
    const scheduler = CourseScheduler();
    const config = ScheduleRunConfig(
      selectedClassIds: {'class-1'},
      seed: 42,
      strength: ScheduleStrength.fast,
    );

    final first = scheduler.solve(problem, config: config);
    final second = scheduler.solve(problem, config: config);

    expect(first.report.placedItems, 2);
    expect(first.report.unplaced, isEmpty);
    expect(first.items.map((item) => item.position?.cellKey).toSet().length, 2);
    expect(
      second.items.map((item) => item.position?.cellKey).toList(),
      first.items.map((item) => item.position?.cellKey).toList(),
    );
  });

  test('容量不足时课程留在暂放区并报告阻断', () {
    final problem = _problem(slotCount: 1);
    final run = const CourseScheduler().solve(
      problem,
      config: ScheduleRunConfig(
        selectedClassIds: {'class-1'},
        seed: 42,
        strength: ScheduleStrength.fast,
      ),
    );

    expect(run.report.placedItems, 1);
    expect(run.report.unplaced, hasLength(1));
    expect(run.report.unplaced.single.blockers, isNotEmpty);
  });
}

SchedulingProblem _problem({required int slotCount}) {
  final term = AcademicTerm(
    id: 'term-1',
    title: '2026 秋季',
    academicYear: '2026-2027',
    semesterLabel: '秋季学期',
    firstTeachingWeekStart: DateTime(2026, 9, 1),
    teachingWeekCount: 20,
    createdAt: DateTime(2026, 8, 1),
  );
  final snapshot = SchedulingSnapshot(
    term: term,
    inputFingerprint: 'fixture',
    stages: const [
      SchoolStage(id: 'stage-1', termId: 'term-1', name: '小学', sortOrder: 0),
    ],
    grades: const [
      GradeGroup(id: 'grade-1', stageId: 'stage-1', name: '一年级', sortOrder: 0),
    ],
    classes: const [
      ClassGroup(id: 'class-1', gradeId: 'grade-1', name: '一班', sortOrder: 0),
    ],
  );
  final items = [
    for (var index = 1; index <= 2; index++)
      ScheduleItem(
        id: 'item-$index',
        termId: 'term-1',
        assignmentId: 'assignment-$index',
        classId: 'class-1',
        teacherId: 'teacher-1',
        subjectId: 'subject-1',
        weekMode: WeekMode.weekly,
      ),
  ];
  return SchedulingProblem(
    snapshot: snapshot,
    selectedClassIds: const {'class-1'},
    positionsByClass: {
      'class-1': [
        for (var index = 1; index <= slotCount; index++)
          SchedulePosition(
            stageId: 'stage-1',
            weekday: 1,
            periodTypeId: 'morning',
            lessonIndex: index,
            startMinute: 480 + index * 45,
            endMinute: 525 + index * 45,
          ),
      ],
    },
    fixedItems: const [],
    units: [
      for (final item in items) ScheduleUnit(item.id, [item]),
    ],
    checks: const [
      SchedulePreflightCheck(code: 'ready', message: '就绪', ready: true),
    ],
  );
}
