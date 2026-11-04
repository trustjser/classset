import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/temporary_adjustments/temporary_adjustment_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('教师通知包含原教师和代课教师，排除取消和失效调整', () {
    final term = AcademicTerm(
      id: 't',
      title: '学期',
      academicYear: '2026',
      semesterLabel: '秋',
      firstTeachingWeekStart: DateTime(2026, 9, 7),
      teachingWeekCount: 1,
      createdAt: DateTime(2026),
    );
    final snapshot = SchedulingSnapshot(
      term: term,
      inputFingerprint: 'x',
      classes: const [
        ClassGroup(id: 'c', gradeId: 'g', name: '一班', sortOrder: 0),
      ],
      subjects: const [
        Subject(id: 's', name: '数学', shortName: '数', sortOrder: 0),
      ],
      teachers: const [
        Teacher(id: 'a', name: '李老师', shortName: '李', sortOrder: 0),
        Teacher(id: 'b', name: '王老师', shortName: '王', sortOrder: 1),
      ],
    );
    ScheduleItem item(String teacher) => ScheduleItem(
      id: 'lesson',
      termId: 't',
      assignmentId: 'a',
      classId: 'c',
      teacherId: teacher,
      subjectId: 's',
      weekMode: WeekMode.weekly,
      position: const SchedulePosition(
        stageId: 'stage',
        weekday: 1,
        periodTypeId: 'p',
        lessonIndex: 1,
        startMinute: 480,
        endMinute: 520,
      ),
    );
    final change = ActualLessonChange(
      before: ActualLesson(date: DateTime(2026, 9, 7), item: item('a')),
      after: ActualLesson(date: DateTime(2026, 9, 7), item: item('b')),
    );
    TemporaryAdjustmentRecord record(
      String id, {
      bool invalid = false,
      bool cancelled = false,
    }) => TemporaryAdjustmentRecord(
      id: id,
      kind: 'substitute',
      changes: [change],
      reason: id,
      createdAt: DateTime(2026, 9, 1),
      needsAttention: invalid,
      cancelledAt: cancelled ? DateTime(2026, 9, 2) : null,
    );
    final bytes = buildTemporaryAdjustmentWorkbook(snapshot, [
      record('有效'),
      record('失效', invalid: true),
      record('取消', cancelled: true),
    ], TemporaryExportKind.teacher);
    final sheets = Excel.decodeBytes(bytes).tables.values;
    final text = sheets
        .expand((sheet) => sheet.rows)
        .expand((row) => row)
        .whereType<Data>()
        .map((cell) => cell.value.toString())
        .join(' ');
    expect(text, contains('李老师'));
    expect(text, contains('王老师'));
    expect(text, contains('2026-09-07'));
    expect(text, contains('08:00'));
    expect(text, isNot(contains('失效')));
    expect(text, isNot(contains('取消')));
    final filteredBytes = buildTemporaryAdjustmentWorkbook(
      snapshot,
      [record('有效')],
      TemporaryExportKind.teacher,
      teacherId: 'a',
    );
    final filtered = Excel.decodeBytes(filteredBytes).tables.values
        .expand((sheet) => sheet.rows)
        .skip(1)
        .expand((row) => row.take(1))
        .whereType<Data>()
        .map((cell) => cell.value.toString())
        .toList();
    expect(filtered, ['李老师']);
    final detailBytes = buildTemporaryAdjustmentWorkbook(snapshot, [record('取消', cancelled: true)],
      TemporaryExportKind.details, includeCancelled: true);
    final detail = Excel.decodeBytes(detailBytes).tables.values.expand((sheet) => sheet.rows)
      .expand((row) => row).whereType<Data>().map((cell) => cell.value.toString()).join(' ');
    expect(detail, contains('取消'));
    expect(detail, contains('已取消'));
  });
}
