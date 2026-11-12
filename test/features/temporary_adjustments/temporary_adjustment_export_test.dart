import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/temporary_adjustments/temporary_adjustment_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('替班导出保留合班范围，日期课表只显示当日实际教师', () {
    final sunday = DateTime(2026, 11, 22);
    final term = AcademicTerm(
      id: 't',
      title: '学期',
      academicYear: '2026',
      semesterLabel: '秋',
      firstTeachingWeekStart: DateTime(2026, 11, 16),
      teachingWeekCount: 2,
      createdAt: DateTime(2026),
    );
    final snapshot = SchedulingSnapshot(term: term, inputFingerprint: 'x');
    const post = SupervisionPost(
      id: 'duty',
      kind: SupervisionKind.eveningStudy,
      name: '晚自习',
      stageId: 'stage',
      weekday: DateTime.sunday,
      periodTypeId: 'evening',
      lessonIndices: [1, 2],
      classIds: ['first', 'second'],
      groupName: '合班',
      location: '报告厅',
    );
    final before = ActualSupervision(
      date: sunday,
      occurrences: [
        for (final index in post.lessonIndices)
          SupervisionOccurrence(
            post: post,
            teacherId: 'original',
            classNames: const ['一班', '二班'],
            position: SchedulePosition(
              stageId: 'stage',
              weekday: DateTime.sunday,
              periodTypeId: 'evening',
              lessonIndex: index,
              startMinute: 1080 + (index - 1) * 40,
              endMinute: 1110 + (index - 1) * 40,
            ),
          ),
      ],
      teacherId: 'original',
      teacherName: '原老师',
    );
    final after = before.withTeacher('replacement', '替班老师');
    final record = TemporaryAdjustmentRecord(
      id: 'change',
      kind: supervisionSubstitutionKind,
      changes: const [],
      reason: '请假',
      createdAt: DateTime(2026, 11, 17),
      supervisionChange: ActualSupervisionChange(before: before, after: after),
    );
    String workbookText(List<int> bytes) =>
        Excel.decodeBytes(bytes).tables.values
            .expand((sheet) => sheet.rows)
            .expand((row) => row)
            .whereType<Data>()
            .map((cell) => cell.value.toString())
            .join(' ');
    final details = workbookText(
      buildTemporaryAdjustmentWorkbook(snapshot, [
        record,
      ], TemporaryExportKind.details),
    );
    expect(details, contains('一班、二班'));
    expect(details, contains('带班替班'));
    expect(details, contains('第1–2节 18:00-19:10'));
    expect(details, contains('原老师'));
    expect(details, contains('替班老师'));

    final state = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: const [],
      records: [record],
      lessons: const [],
      revision: 'test',
      reconciliationPending: false,
      supervisions: [after],
    );
    final start = term.firstTeachingWeekStart!;
    final classWeek = workbookText(
      buildActualWeekWorkbook(state, start, classId: 'second'),
    );
    expect(classWeek, contains('2026-11-22'));
    expect(classWeek, contains('报告厅'));
    expect(classWeek, contains('替班老师'));
    expect(classWeek, isNot(contains('原老师')));
    final teacherWeek = workbookText(
      buildActualWeekWorkbook(state, start, teacherId: 'original'),
    );
    expect(teacherWeek, isNot(contains('晚自习')));
  });

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
