import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:excel/excel.dart';

/// Builds a workbook from the currently visible timetable rows.
List<int> buildScheduleWorkbook(
  SchedulingSnapshot snapshot,
  List<ScheduleItem> items,
) {
  final book = Excel.createExcel();
  final sheet = book['课表'];
  sheet.appendRow(
    const [
      '学段',
      '年级',
      '班级',
      '科目',
      '教师',
      '周别',
      '星期',
      '时段',
      '节次',
      '开始',
      '结束',
    ].map(TextCellValue.new).toList(),
  );
  final grades = {for (final grade in snapshot.grades) grade.id: grade};
  final stages = {for (final stage in snapshot.stages) stage.id: stage.name};
  final classes = {
    for (final schoolClass in snapshot.classes) schoolClass.id: schoolClass,
  };
  final subjects = {
    for (final subject in snapshot.subjects) subject.id: subject.name,
  };
  final teachers = {
    for (final teacher in snapshot.teachers) teacher.id: teacher.displayName,
  };
  final periods = {
    for (final routine in snapshot.routines)
      for (final period in routine.periodTypes) period.id: period.name,
  };
  final placed = items.where((item) => item.position != null).toList()
    ..sort((a, b) {
      final left = a.position!;
      final right = b.position!;
      final day = left.weekday.compareTo(right.weekday);
      if (day != 0) return day;
      final time = (left.startMinute ?? 0).compareTo(right.startMinute ?? 0);
      if (time != 0) return time;
      final lesson = left.lessonIndex.compareTo(right.lessonIndex);
      return lesson != 0 ? lesson : a.classId.compareTo(b.classId);
    });
  for (final item in placed) {
    final position = item.position!;
    final schoolClass = classes[item.classId];
    final grade = grades[schoolClass?.gradeId];
    sheet.appendRow([
      TextCellValue(stages[grade?.stageId] ?? ''),
      TextCellValue(grade?.name ?? ''),
      TextCellValue(schoolClass?.name ?? item.classId),
      TextCellValue(subjects[item.subjectId] ?? item.subjectId),
      TextCellValue(teachers[item.teacherId] ?? item.teacherId),
      TextCellValue(item.weekMode.label),
      TextCellValue('周${_weekday(position.weekday)}'),
      TextCellValue(periods[position.periodTypeId] ?? position.periodTypeId),
      IntCellValue(position.lessonIndex),
      TextCellValue(_clock(position.startMinute)),
      TextCellValue(_clock(position.endMinute)),
    ]);
  }
  book.delete('Sheet1');
  return book.encode() ?? (throw StateError('生成课表工作簿失败'));
}

String _weekday(int value) => switch (value) {
  1 => '一',
  2 => '二',
  3 => '三',
  4 => '四',
  5 => '五',
  6 => '六',
  _ => '日',
};

String _clock(int? minute) => minute == null
    ? ''
    : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
