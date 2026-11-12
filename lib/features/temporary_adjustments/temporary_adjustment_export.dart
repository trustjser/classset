import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:excel/excel.dart';

enum TemporaryExportKind { teacher, schoolClass, details }

/// 导出有效调整的实际日期与调整前后信息。
List<int> buildTemporaryAdjustmentWorkbook(
  SchedulingSnapshot snapshot,
  List<TemporaryAdjustmentRecord> records,
  TemporaryExportKind kind, {
  String? teacherId,
  String? classId,
  bool Function(ActualLessonChange)? includeChange,
  bool includeCancelled = false,
}) {
  final excel = Excel.createExcel();
  final title = switch (kind) {
    TemporaryExportKind.teacher => '教师通知',
    TemporaryExportKind.schoolClass => '班级通知',
    TemporaryExportKind.details => '调整明细',
  };
  excel.rename(excel.getDefaultSheet()!, title);
  final sheet = excel[title];
  String className(String id) =>
      snapshot.classes.where((c) => c.id == id).firstOrNull?.name ?? id;
  String subjectName(String id) =>
      snapshot.subjects.where((s) => s.id == id).firstOrNull?.name ?? id;
  String teacherName(String id) =>
      snapshot.teachers.where((t) => t.id == id).firstOrNull?.displayName ?? id;
  String clock(int? value) => value == null
      ? ''
      : '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
  String describe(ActualLesson lesson) {
    final position = lesson.item.position;
    final date = lesson.date.toIso8601String().substring(0, 10);
    final routine = snapshot.routines
        .where((routine) => routine.stageId == position?.stageId)
        .firstOrNull;
    final period = routine?.periodTypes
        .where((period) => period.id == position?.periodTypeId)
        .firstOrNull;
    return '$date ${period?.name ?? ''}第${position?.lessonIndex ?? '-'}节 ${clock(position?.startMinute)}-${clock(position?.endMinute)} '
        '${subjectName(lesson.item.subjectId)} ${teacherName(lesson.item.teacherId)}';
  }

  void row(List<String> values) =>
      sheet.appendRow(values.map((value) => TextCellValue(value)).toList());
  row([
    kind == TemporaryExportKind.teacher ? '通知教师' : '班级',
    '班级',
    '类型',
    '状态',
    '调整前',
    '调整后',
    '原因',
  ]);
  for (final record in records.where(
    (record) =>
        !record.needsAttention &&
        (record.cancelledAt == null ||
            (kind == TemporaryExportKind.details && includeCancelled)),
  )) {
    final supervision = record.supervisionChange;
    if (supervision != null) {
      final before = supervision.before;
      final after = supervision.after;
      final classes = <String, String>{
        for (var i = 0; i < before.classIds.length; i++)
          before.classIds[i]: i < before.classNames.length
              ? before.classNames[i]
              : className(before.classIds[i]),
      };
      final recipients = switch (kind) {
        TemporaryExportKind.teacher => [
          if (teacherId == null || before.teacherId == teacherId)
            before.teacherName,
          if (teacherId == null || after.teacherId == teacherId)
            after.teacherName,
        ],
        TemporaryExportKind.schoolClass => [
          for (final entry in classes.entries)
            if (classId == null || entry.key == classId) entry.value,
        ],
        TemporaryExportKind.details => [classes.values.join('、')],
      };
      String describeSupervision(ActualSupervision duty) {
        final first = duty.occurrences.first;
        final last = duty.occurrences.last;
        final section = first.position.lessonIndex == last.position.lessonIndex
            ? '第${first.position.lessonIndex}节'
            : '第${first.position.lessonIndex}–${last.position.lessonIndex}节';
        final times = first.startMinute == null || last.endMinute == null
            ? ''
            : ' ${clock(first.startMinute)}-${clock(last.endMinute)}';
        return '${duty.date.toIso8601String().substring(0, 10)} '
            '$section$times ${duty.post.name} ${duty.teacherName}';
      }

      for (final recipient in recipients) {
        row([
          recipient,
          classes.values.join('、'),
          '带班替班',
          record.cancelledAt == null ? '有效' : '已取消',
          describeSupervision(before),
          describeSupervision(after),
          record.reason,
        ]);
      }
      continue;
    }
    final label = switch (record.kind) {
      'move' => '移课',
      'swap' => '换课',
      _ => '代课',
    };
    for (final change in record.changes) {
      if (includeChange != null && !includeChange(change)) continue;
      final recipients = kind == TemporaryExportKind.teacher
          ? {change.before.item.teacherId, change.after.item.teacherId}
                .where((id) => teacherId == null || id == teacherId)
                .map(teacherName)
          : [className(change.before.item.classId)];
      for (final recipient in recipients) {
        row([
          recipient,
          className(change.before.item.classId),
          label,
          record.cancelledAt == null ? '有效' : '已取消',
          describe(change.before),
          describe(change.after),
          record.reason,
        ]);
      }
    }
  }
  for (var column = 0; column < 7; column++) {
    sheet.setColumnWidth(column, column == 4 || column == 5 ? 50 : 18);
  }
  return excel.encode()!;
}

/// 导出所选教学周的实际课程和带班，教师视图按岗位保留一行。
List<int> buildActualWeekWorkbook(
  TemporaryTimetableState state,
  DateTime weekStart, {
  String? teacherId,
  String? classId,
}) {
  final first = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final end = DateTime(first.year, first.month, first.day + 7);
  bool inWeek(DateTime date) => !date.isBefore(first) && date.isBefore(end);
  final snapshot = state.snapshot;
  final classNames = {for (final item in snapshot.classes) item.id: item.name};
  final subjects = {for (final item in snapshot.subjects) item.id: item.name};
  final teachers = {
    for (final item in snapshot.teachers) item.id: item.displayName,
  };
  final periods = {
    for (final routine in snapshot.routines)
      for (final period in routine.periodTypes)
        (routine.stageId, period.id): period,
  };
  String clock(int? minute) => minute == null
      ? ''
      : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  String range(int? start, int? end) =>
      start == null || end == null ? '' : '${clock(start)}-${clock(end)}';
  String day(DateTime date) => date.toIso8601String().substring(0, 10);
  final rows =
      <
        ({
          DateTime date,
          int? minute,
          int period,
          int slot,
          List<String> values,
        })
      >[];
  for (final lesson in state.lessons) {
    final item = lesson.item;
    final position = item.position;
    if (position == null ||
        !inWeek(lesson.date) ||
        (classId != null && item.classId != classId) ||
        (teacherId != null && item.teacherId != teacherId)) {
      continue;
    }
    final period = periods[(position.stageId, position.periodTypeId)];
    rows.add((
      date: lesson.date,
      minute: position.startMinute,
      period: period?.sortOrder ?? 0,
      slot: position.lessonIndex,
      values: [
        day(lesson.date),
        '${period?.name ?? ''}第${position.lessonIndex}节',
        range(position.startMinute, position.endMinute),
        '正课',
        subjects[item.subjectId] ?? item.subjectId,
        classNames[item.classId] ?? item.classId,
        teachers[item.teacherId] ?? item.teacherId,
        '',
      ],
    ));
  }
  for (final duty in state.supervisions) {
    if (!inWeek(duty.date) ||
        (classId != null && !duty.classIds.contains(classId)) ||
        (teacherId != null && duty.teacherId != teacherId)) {
      continue;
    }
    final start = duty.occurrences.first;
    final last = duty.occurrences.last;
    final index = start.position.lessonIndex;
    final lastIndex = last.position.lessonIndex;
    final period =
        periods[(start.position.stageId, start.position.periodTypeId)];
    rows.add((
      date: duty.date,
      minute: start.startMinute,
      period: period?.sortOrder ?? 0,
      slot: index,
      values: [
        day(duty.date),
        '${period?.name ?? ''}第${index == lastIndex ? index : '$index–$lastIndex'}节',
        range(start.startMinute, last.endMinute),
        duty.post.kind.label,
        duty.post.name,
        duty.classNames.join('、'),
        duty.teacherName,
        duty.post.location,
      ],
    ));
  }
  rows.sort((left, right) {
    final byDate = left.date.compareTo(right.date);
    if (byDate != 0) return byDate;
    final byClock = (left.minute ?? 1440).compareTo(right.minute ?? 1440);
    if (byClock != 0) return byClock;
    final byPeriod = left.period.compareTo(right.period);
    return byPeriod == 0 ? left.slot.compareTo(right.slot) : byPeriod;
  });
  final excel = Excel.createExcel();
  const title = '本周实际课表';
  excel.rename(excel.getDefaultSheet()!, title);
  final sheet = excel[title];
  void append(List<String> row) =>
      sheet.appendRow(row.map(TextCellValue.new).toList());
  append(['日期', '节次', '时间', '类型', '课程或活动', '班级', '教师', '地点']);
  for (final row in rows) {
    append(row.values);
  }
  for (var column = 0; column < 8; column++) {
    sheet.setColumnWidth(column, 20);
  }
  return excel.encode()!;
}
