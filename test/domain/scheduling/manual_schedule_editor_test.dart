import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_lesson_constraint.dart';
import 'package:class_set/domain/scheduling/manual_schedule_editor.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = SchedulePosition(
  stageId: 'stage',
  weekday: 1,
  periodTypeId: 'morning',
  lessonIndex: 1,
  startMinute: 480,
  endMinute: 525,
);
const _second = SchedulePosition(
  stageId: 'stage',
  weekday: 1,
  periodTypeId: 'morning',
  lessonIndex: 2,
  startMinute: 530,
  endMinute: 575,
);
const _afternoon = SchedulePosition(
  stageId: 'stage',
  weekday: 1,
  periodTypeId: 'afternoon',
  lessonIndex: 1,
  startMinute: 810,
  endMinute: 855,
);

void main() {
  const editor = ManualScheduleEditor();

  test('同班占用格可交换两节课', () {
    final items = [
      _item('a', 'class-a', 'teacher-a', _first),
      _item('b', 'class-a', 'teacher-b', _second),
    ];
    final snapshot = _snapshot(items: items);
    final result = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _second,
      problem: _problem(snapshot),
    );

    expect(result.allowed, isTrue);
    expect(result.changedItemIds, {'a', 'b'});
    expect(
      result.items.singleWhere((item) => item.id == 'a').position?.cellKey,
      _second.cellKey,
    );
    expect(
      result.items.singleWhere((item) => item.id == 'b').position?.cellKey,
      _first.cellKey,
    );
  });

  test('教师视图指定另一班课节后可交换', () {
    final items = [
      _item('a', 'class-a', 'teacher-a', _first),
      _item('b', 'class-b', 'teacher-a', _second),
    ];
    final snapshot = _snapshot(items: items);
    final problem = _problem(snapshot);

    final withoutTarget = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _second,
      problem: problem,
    );
    final withTarget = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _second,
      swapWithItemId: 'b',
      problem: problem,
    );

    expect(withoutTarget.allowed, isFalse);
    expect(withTarget.allowed, isTrue);
    expect(withTarget.changedItemIds, {'a', 'b'});
  });

  test('移出最低节数要求所在时段会被阻止', () {
    final items = [_item('a', 'class-a', 'teacher-a', _first)];
    final snapshot = _snapshot(
      items: items,
      conditions: const [
        ScheduleCondition(
          id: 'morning-minimum',
          termId: 'term',
          type: ScheduleConditionType.periodLimit,
          targetType: ScheduleConditionTarget.subject,
          targetId: 'subject',
          periodTypeId: 'morning',
          minimum: 1,
        ),
      ],
    );
    final result = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _afternoon,
      problem: _problem(snapshot),
    );

    expect(result.allowed, isFalse);
    expect(result.blockers.any((blocker) => blocker.code == 'minimum'), isTrue);
  });

  test('拖动到同一天超出科目节数上限时仍会阻止', () {
    const tuesday = SchedulePosition(
      stageId: 'stage',
      weekday: 2,
      periodTypeId: 'morning',
      lessonIndex: 1,
      startMinute: 480,
      endMinute: 525,
    );
    final items = [
      _item('a', 'class-a', 'teacher-a', tuesday),
      _item('b', 'class-a', 'teacher-b', _first),
    ];
    final snapshot = _snapshot(
      items: items,
      lessonConstraints: const [
        SubjectLessonConstraint(
          id: 'limit',
          subjectId: 'subject',
          scope: FreeSlotScope.grade,
          scopeId: 'grade',
          stageId: 'stage',
          weekday: null,
          maximumDailyLessons: 1,
        ),
      ],
    );
    final result = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: _second,
      problem: _problem(snapshot),
    );
    expect(result.allowed, isFalse);
    expect(
      result.blockers.any((blocker) => blocker.code == 'subjectDailyMaximum'),
      isTrue,
    );
  });

  test('班级锁会阻止拖入暂放区', () {
    final items = [_item('a', 'class-a', 'teacher-a', _first)];
    final snapshot = _snapshot(
      items: items,
      locks: const [
        ScheduleLock(
          termId: 'term',
          scope: ScheduleLockScope.schoolClass,
          targetId: 'class-a',
        ),
      ],
    );
    final result = editor.previewMove(
      snapshot: snapshot,
      items: items,
      itemId: 'a',
      target: null,
      problem: _problem(snapshot),
    );

    expect(result.allowed, isFalse);
    expect(result.blockers.single.code, 'locked');
  });

  test('检测会列出跨学段时间缺失等预检阻断', () {
    final snapshot = _snapshot(items: const []);
    final problem = SchedulingProblem(
      snapshot: snapshot,
      selectedClassIds: const {'class-a', 'class-b'},
      positionsByClass: const {},
      fixedItems: const [],
      units: const [],
      checks: const [
        SchedulePreflightCheck(
          code: 'clock',
          message: '跨学段共用教师缺少时间',
          ready: false,
        ),
      ],
    );

    final issues = editor.detectAll(
      snapshot: snapshot,
      items: const [],
      problem: problem,
    );

    expect(issues.any((issue) => issue.code == 'clock'), isTrue);
  });
}

ScheduleItem _item(
  String id,
  String classId,
  String teacherId,
  SchedulePosition position,
) => ScheduleItem(
  id: id,
  termId: 'term',
  assignmentId: 'assignment-$id',
  classId: classId,
  teacherId: teacherId,
  subjectId: 'subject',
  weekMode: WeekMode.weekly,
  position: position,
);

SchedulingSnapshot _snapshot({
  required List<ScheduleItem> items,
  List<ScheduleCondition> conditions = const [],
  List<ScheduleLock> locks = const [],
  List<SubjectLessonConstraint> lessonConstraints = const [],
}) => SchedulingSnapshot(
  term: AcademicTerm(
    id: 'term',
    title: '2026 秋季',
    academicYear: '2026-2027',
    semesterLabel: '秋季学期',
    firstTeachingWeekStart: DateTime(2026, 9, 1),
    teachingWeekCount: 20,
    createdAt: DateTime(2026, 8, 1),
  ),
  inputFingerprint: 'fixture',
  stages: const [
    SchoolStage(id: 'stage', termId: 'term', name: '小学', sortOrder: 0),
  ],
  grades: const [
    GradeGroup(id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0),
  ],
  classes: const [
    ClassGroup(id: 'class-a', gradeId: 'grade', name: '一班', sortOrder: 0),
    ClassGroup(id: 'class-b', gradeId: 'grade', name: '二班', sortOrder: 1),
  ],
  conditions: conditions,
  lessonConstraints: lessonConstraints,
  locks: locks,
  existingItems: items,
);

SchedulingProblem _problem(SchedulingSnapshot snapshot) => SchedulingProblem(
  snapshot: snapshot,
  selectedClassIds: const {'class-a', 'class-b'},
  positionsByClass: const {
    'class-a': [_first, _second, _afternoon],
    'class-b': [_first, _second, _afternoon],
  },
  fixedItems: const [],
  units: const [],
  checks: const [],
);
