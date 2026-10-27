import 'dart:collection';

import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/constraint_evaluator.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingItems extends ListBase<ScheduleItem> {
  _CountingItems(this.items);
  final List<ScheduleItem> items;
  int reads = 0;
  @override
  int get length => items.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  ScheduleItem operator [](int index) {
    reads++;
    return items[index];
  }

  @override
  void operator []=(int index, ScheduleItem value) =>
      throw UnsupportedError('read only');
}

void main() {
  test('没有硬性下限或必须排课规则时，无需遍历全部课表', () {
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
    );
    final problem = SchedulingProblem(
      snapshot: snapshot,
      selectedClassIds: const {},
      positionsByClass: const {},
      fixedItems: const [],
      units: const [],
      checks: const [],
    );
    final items = _CountingItems(
      List.generate(
        2000,
        (i) => ScheduleItem(
          id: '$i',
          termId: 't',
          assignmentId: '$i',
          classId: 'c',
          teacherId: 't',
          subjectId: 's',
          weekMode: WeekMode.weekly,
        ),
      ),
    );
    expect(
      const ConstraintEvaluator().unmetHardRequirements(problem, items),
      isEmpty,
    );
    expect(items.reads, 0);
  });
}
