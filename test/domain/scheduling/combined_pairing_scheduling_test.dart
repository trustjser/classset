import '../../support/combined_pairing_fixture.dart';

import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/scheduling/course_scheduler.dart';
import 'package:class_set/domain/scheduling/constraint_evaluator.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/manual_schedule_editor.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/schedule_reconciler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('普通单双周配对协调不会无故互换原有课次', () {
    final base = combinedPairingSnapshot();
    final snapshot = base.copyWith(
      assignments: [
        for (final a in base.assignments)
          TeacherAssignment(
            id: a.id,
            termId: a.termId,
            teacherId: a.teacherId,
            classId: a.classId,
            subjectId: a.subjectId,
            weekMode: a.weekMode,
            lessonCount: a.lessonCount,
          ),
      ],
    );
    final current = snapshot.copyWith(existingItems: _brokenItems(snapshot));
    final preview = const ScheduleReconciler().preview(current, current);
    expect(preview.canApply, isTrue);
    expect(preview.movedCount, 0);
    expect(preview.keptCount, 16);
  });

  test('合班预览重排不能破坏已满足的教师一定排规则', () {
    final snapshot = combinedPairingSnapshot(
      fillers: true,
      protectOtherMust: true,
    );
    final current = snapshot.copyWith(existingItems: _brokenItems(snapshot));
    final problem = const ProblemBuilder().build(current);
    expect(
      const ConstraintEvaluator().unmetHardRequirements(
        problem,
        current.existingItems,
      ),
      isEmpty,
    );
    final preview = const ScheduleReconciler().preview(current, current);
    expect(
      const ConstraintEvaluator().unmetHardRequirements(problem, preview.items),
      isEmpty,
    );
  });

  test('配对匹配避开非合班教师同周冲突，不因任课标识排序误报无解', () {
    final base = combinedPairingSnapshot(combineEven: true);
    final snapshot = base.copyWith(
      assignments: [
        for (final a in base.assignments)
          if (a.weekMode == WeekMode.even) a,
        for (final c in ['a', 'b']) ...[
          TeacherAssignment(
            id: '$c-shared',
            termId: 't',
            teacherId: 'shared',
            classId: c,
            subjectId: 'odd',
            weekMode: WeekMode.odd,
            lessonCount: 1,
          ),
          TeacherAssignment(
            id: '$c-individual',
            termId: 't',
            teacherId: 'even-$c',
            classId: c,
            subjectId: 'odd',
            weekMode: WeekMode.odd,
            lessonCount: 3,
          ),
        ],
      ],
    );
    final problem = const ProblemBuilder().build(snapshot);
    expect(problem.isReady, isTrue);
    final run = const CourseScheduler().solve(
      problem,
      config: const ScheduleRunConfig(selectedClassIds: {'a', 'b'}, seed: 7),
    );
    expect(run.report.placedItems, 16);
  });

  test('合班同步找不到共同空位时只重排受影响班级形成完整预览', () {
    final snapshot = combinedPairingSnapshot(fillers: true);
    final broken = _brokenItems(snapshot);
    final current = snapshot.copyWith(existingItems: broken);
    final preview = const ScheduleReconciler().preview(current, current);
    expect(preview.canApply, isTrue);
    expect(preview.items, hasLength(24));
    expect(preview.items.every((item) => item.isPlaced), isTrue);
    _expectSynchronized(
      preview.items.where((item) => item.subjectId != 'other').toList(),
    );
  });

  test('拆分任课的标识排序不会把不同次合班课合并成同一课组', () {
    final base = combinedPairingSnapshot(combineEven: true);
    final snapshot = base.copyWith(
      assignments: [
        for (final a in base.assignments)
          if (a.weekMode == WeekMode.even) a,
        for (final c in ['a', 'b']) ...[
          TeacherAssignment(
            id: c == 'a' ? 'a-combined' : 'z-combined',
            termId: 't',
            teacherId: 'shared',
            classId: c,
            subjectId: 'odd',
            weekMode: WeekMode.odd,
            lessonCount: 1,
            combinedLessonGroupId: 'combined',
          ),
          TeacherAssignment(
            id: c == 'a' ? 'z-individual' : 'a-individual',
            termId: 't',
            teacherId: 'even-$c',
            classId: c,
            subjectId: 'odd',
            weekMode: WeekMode.odd,
            lessonCount: 3,
          ),
        ],
      ],
    );
    final problem = const ProblemBuilder().build(snapshot);
    expect(problem.isReady, isTrue);
    expect(problem.units, hasLength(4));
    expect(problem.units.every((unit) => unit.items.length == 4), isTrue);
    final run = const CourseScheduler().solve(
      problem,
      config: const ScheduleRunConfig(selectedClassIds: {'a', 'b'}, seed: 7),
    );
    expect(run.report.placedItems, 16);
  });

  test('配对引出的双周同教师课程未合班时明确阻止排课', () {
    final problem = const ProblemBuilder().build(
      combinedPairingSnapshot(sharedEvenTeacher: true),
    );
    expect(problem.isReady, isFalse);
    final issue = problem.checks.firstWhere(
      (check) => check.code == 'meetingTeacherConflict',
    );
    expect(issue.message, contains('双周教师甲'));
    expect(issue.message, contains('双周'));
    expect(issue.message, contains('合班'));
    expect(issue.message, contains('配对'));
  });

  test('单双周分别合班且跨学段作息同时间时两种绑定共同生效', () {
    final snapshot = combinedPairingSnapshot(
      combineEven: true,
      crossStage: true,
    );
    final problem = const ProblemBuilder().build(snapshot);
    expect(problem.isReady, isTrue);
    final run = const CourseScheduler().solve(
      problem,
      config: const ScheduleRunConfig(selectedClassIds: {'a', 'b'}, seed: 7),
    );
    expect(run.report.placedItems, 16);
    for (final unit in problem.units) {
      final rows = run.items
          .where((item) => item.meetingId == unit.id)
          .toList();
      expect(rows, hasLength(4));
      expect(rows.every((item) => item.isPlaced), isTrue);
      expect(
        rows.every((item) => rows.first.position!.hasSameClock(item.position!)),
        isTrue,
      );
    }
  });

  test('单周合班和各班单双周配对同时约束同一组课节', () {
    final snapshot = combinedPairingSnapshot();
    final problem = const ProblemBuilder().build(snapshot);
    expect(problem.isReady, isTrue);
    expect(problem.units, hasLength(4));
    for (final unit in problem.units) {
      expect(unit.items, hasLength(4));
      expect(unit.items.map((item) => item.classId).toSet(), {'a', 'b'});
      expect(unit.items.map((item) => item.meetingId).toSet(), {unit.id});
    }
    final run = const CourseScheduler().solve(
      problem,
      config: const ScheduleRunConfig(selectedClassIds: {'a', 'b'}, seed: 7),
    );
    expect(run.report.placedItems, 16);
    _expectSynchronized(run.items);
    final placed = snapshot.copyWith(existingItems: run.items);
    final unit = problem.units.first;
    final moved = const ManualScheduleEditor().previewMove(
      snapshot: placed,
      items: run.items,
      itemId: unit.items.first.id,
      target: null,
    );
    expect(moved.allowed, isTrue);
    expect(moved.changedItemIds, unit.items.map((item) => item.id).toSet());
    expect(moved.items.where((item) => !item.isPlaced), hasLength(4));
  });

  test('旧课表中按班拆开的单周合班在协调预览中重新同步', () {
    final snapshot = combinedPairingSnapshot();
    final broken = _brokenItems(snapshot);
    final current = snapshot.copyWith(existingItems: broken);
    final preview = const ScheduleReconciler().preview(current, current);
    expect(preview.canApply, isTrue);
    expect(preview.unplacedCount, 0);
    _expectSynchronized(preview.items);
    expect(
      current.existingItems[0].position?.cellKey,
      isNot(current.existingItems[8].position?.cellKey),
    );
  });
}

void _expectSynchronized(List<ScheduleItem> items) {
  expect(items, hasLength(16));
  expect(items.every((item) => item.isPlaced), isTrue);
  final meetings = items.map((item) => item.meetingId).toSet();
  expect(meetings, hasLength(4));
  for (final key in meetings) {
    final group = items.where((item) => item.meetingId == key).toList();
    expect(group, hasLength(4));
    expect(group.map((item) => item.position!.cellKey).toSet(), hasLength(1));
  }
}

List<ScheduleItem> _brokenItems(SchedulingSnapshot snapshot) {
  final problem = const ProblemBuilder().build(snapshot);
  return [
    for (final a in snapshot.assignments)
      for (var i = 0; i < 4; i++)
        ScheduleItem(
          id: '${a.id}:${i + 1}',
          termId: 't',
          assignmentId: a.id,
          classId: a.classId,
          teacherId: a.teacherId,
          subjectId: a.subjectId,
          weekMode: a.weekMode,
          combinedGroupId: a.combinedLessonGroupId,
          meetingId: a.subjectId == 'other' ? null : 'pair:${a.classId}:$i',
          position:
              problem.positionsByClass[a.classId]![i +
                  ((a.classId == 'a') == (a.subjectId == 'other') ? 4 : 0)],
        ),
  ];
}
