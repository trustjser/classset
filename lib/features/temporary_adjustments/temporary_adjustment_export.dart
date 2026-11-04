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
  for (final record in records.where((record) => !record.needsAttention &&
      (record.cancelledAt == null || (kind == TemporaryExportKind.details && includeCancelled)))) {
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
