import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:excel/excel.dart';

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

/// Export options for the three timetable workbooks.
class TimetableExportOptions {
  const TimetableExportOptions({
    this.teacherUnified = true,
    this.showTeacherStage = true,
    this.schoolWeekly = true,
  });
  final bool teacherUnified;
  final bool showTeacherStage;
  final bool schoolWeekly;
}

class TimetableWorkbooks {
  const TimetableWorkbooks({
    required this.classWorkbook,
    required this.teacherWorkbook,
    required this.schoolWorkbook,
  });
  final List<int> classWorkbook;
  final List<int> teacherWorkbook;
  final List<int> schoolWorkbook;
}

class _ExportSlot {
  const _ExportSlot({
    required this.stageId,
    required this.label,
    required this.periodId,
    required this.lessonIndex,
    required this.start,
    required this.end,
    this.common,
  });
  final String stageId;
  final String label;
  final String? periodId;
  final int? lessonIndex;
  final int? start;
  final int? end;
  final CommonPeriod? common;
  String get time =>
      start == null || end == null ? '—' : '${_clock(start)}-${_clock(end)}';
  String get header =>
      common == null ? '$label\n$time' : '${common!.name}\n$time';
}

/// Builds separate class, teacher and stage workbooks from the full timetable.
TimetableWorkbooks buildTimetableWorkbooks(
  SchedulingSnapshot snapshot,
  List<ScheduleItem> items, {
  required String schoolName,
  required Map<String, List<CommonPeriod>> commonPeriods,
  required TimetableExportOptions options,
}) {
  final classes = Excel.createExcel();
  final teachers = Excel.createExcel();
  final school = Excel.createExcel();
  final names = <Excel, Set<String>>{
    classes: {'sheet1'},
    teachers: {'sheet1'},
    school: {'sheet1'},
  };
  final stageById = {for (final stage in snapshot.stages) stage.id: stage};
  final gradeById = {for (final grade in snapshot.grades) grade.id: grade};
  final classById = {for (final item in snapshot.classes) item.id: item};
  final subjectById = {
    for (final item in snapshot.subjects) item.id: item.name,
  };
  final teacherById = {
    for (final item in snapshot.teachers) item.id: item.displayName,
  };
  final routineByStage = {
    for (final routine in snapshot.routines) routine.stageId: routine,
  };
  final placed = items.where((item) => item.position != null).toList();
  final stageNames = {
    for (final stage in snapshot.stages) stage.id: stage.name,
  };
  final heading =
      '$schoolName ${snapshot.term.academicYear}学年${snapshot.term.semesterLabel}';
  final stageSlots = <String, List<_ExportSlot>>{};
  for (final stage in snapshot.stages) {
    final routine = routineByStage[stage.id];
    if (routine == null) continue;
    final commons = [...?commonPeriods[stage.id]]
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.name.compareTo(b.name);
      });
    final slots = <_ExportSlot>[];
    void addCommon(CommonPeriod c) => slots.add(
      _ExportSlot(
        stageId: stage.id,
        label: c.name,
        periodId: null,
        lessonIndex: null,
        start: c.startMinute,
        end: c.endMinute,
        common: c,
      ),
    );
    for (final c in commons.where((c) => c.insertAfterLessonId == null)) {
      addCommon(c);
    }
    var lessonNumber = 0;
    final used = <String>{
      for (final c in commons.where((c) => c.insertAfterLessonId == null)) c.id,
    };
    final periods = [...routine.periodTypes]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final period in periods) {
      var count = period.defaultLessonCount;
      for (final override in routine.overrides.where(
        (o) => o.periodTypeId == period.id,
      )) {
        if (override.lessonCount > count) count = override.lessonCount;
      }
      for (var index = 1; index <= count; index++) {
        lessonNumber++;
        final time = period.lessonTimes
            .where((t) => t.lessonIndex == index)
            .firstOrNull;
        slots.add(
          _ExportSlot(
            stageId: stage.id,
            label: '第$lessonNumber节',
            periodId: period.id,
            lessonIndex: index,
            start: time?.startMinute,
            end: time?.endMinute,
          ),
        );
        for (final c in commons.where(
          (c) => c.insertAfterLessonId == '${period.id}_$index',
        )) {
          addCommon(c);
          used.add(c.id);
        }
      }
    }
    for (final c in commons.where((c) => !used.contains(c.id))) {
      addCommon(c);
    }
    stageSlots[stage.id] = slots;
  }
  List<int> daysFor(String stageId) {
    final days = <int>{...?routineByStage[stageId]?.teachingWeekdays};
    days.addAll(
      placed
          .where((item) => snapshot.stageIdForClass(item.classId) == stageId)
          .map((item) => item.position!.weekday),
    );
    return days.toList()..sort();
  }

  Sheet newSheet(Excel book, String requested) {
    var name = requested
        .replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ')
        .trim()
        .replaceAll(RegExp(r"^'+|'+$"), '');
    if (name.isEmpty) name = '课表';
    if (name.length > 31) name = name.substring(0, 31);
    final base = name;
    var suffix = 2;
    while (names[book]!.contains(name.toLowerCase())) {
      final part = '($suffix)';
      name =
          '${base.substring(0, base.length > 31 - part.length ? 31 - part.length : base.length)}$part';
      suffix++;
    }
    names[book]!.add(name.toLowerCase());
    return book[name];
  }

  String week(ScheduleItem item) => switch (item.weekMode) {
    WeekMode.weekly => '',
    WeekMode.odd => '单周 ',
    WeekMode.even => '双周 ',
  };
  String subject(ScheduleItem item) =>
      '${week(item)}${subjectById[item.subjectId] ?? item.subjectId}';
  String displayClassName(String classId) {
    final schoolClass = classById[classId];
    if (schoolClass == null) return classId;
    final grade = gradeById[schoolClass.gradeId]?.name ?? '';
    return grade.isEmpty || schoolClass.name.contains(grade)
        ? schoolClass.name
        : '$grade ${schoolClass.name}';
  }

  String className(ScheduleItem item) => displayClassName(item.classId);
  String teacherName(ScheduleItem item) =>
      teacherById[item.teacherId] ?? item.teacherId;
  List<ScheduleItem> atSlot(
    List<ScheduleItem> source,
    _ExportSlot slot,
    int day,
  ) => source
      .where(
        (item) =>
            item.position != null &&
            item.position!.stageId == slot.stageId &&
            item.position!.weekday == day &&
            item.position!.periodTypeId == slot.periodId &&
            item.position!.lessonIndex == slot.lessonIndex,
      )
      .toList();
  List<SupervisionOccurrence> dutiesAtSlot(_ExportSlot slot, int day) =>
      snapshot.visibleSupervision.where((duty) {
        final position = duty.position;
        return position.stageId == slot.stageId &&
            position.weekday == day &&
            position.periodTypeId == slot.periodId &&
            position.lessonIndex == slot.lessonIndex;
      }).toList();
  String dutyTeacher(SupervisionOccurrence duty) =>
      teacherById[duty.teacherId] ?? duty.teacherName;
  String dutyClasses(SupervisionOccurrence duty) =>
      duty.classIds.map(displayClassName).join('、');
  String? freeLabel(String classId, _ExportSlot slot, int day) {
    final gradeId = snapshot.gradeIdForClass(classId);
    final matching =
        snapshot.freeSlots
            .where(
              (f) =>
                  f.stageId == slot.stageId &&
                  f.periodTypeId == slot.periodId &&
                  f.lessonIndex == slot.lessonIndex &&
                  f.weekday == day &&
                  switch (f.scope) {
                    FreeSlotScope.school => f.scopeId == snapshot.term.id,
                    FreeSlotScope.stage => f.scopeId == slot.stageId,
                    FreeSlotScope.grade => f.scopeId == gradeId,
                    FreeSlotScope.schoolClass => f.scopeId == classId,
                  },
            )
            .toList()
          ..sort((a, b) => b.scope.index.compareTo(a.scope.index));
    return matching.firstOrNull?.label;
  }

  bool available(_ExportSlot slot, int day) {
    final routine = routineByStage[slot.stageId];
    return routine != null &&
        routine.teachingWeekdays.contains(day) &&
        slot.periodId != null &&
        slot.lessonIndex! <= routine.effectiveLessonCount(slot.periodId!, day);
  }

  CellIndex cell(int row, int col) =>
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);
  final border = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.fromHexString('#D8D8D8'),
  );
  CellStyle style({
    String? color,
    int size = 10,
    bool bold = false,
    Border? edge,
  }) => CellStyle(
    fontFamily: '宋体',
    fontSize: size,
    bold: bold,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    backgroundColorHex: color == null
        ? ExcelColor.none
        : ExcelColor.fromHexString(color),
    leftBorder: edge ?? border,
    rightBorder: edge ?? border,
    topBorder: edge ?? border,
    bottomBorder: edge ?? border,
  );
  final headerStyle = style(color: '#DCEBD2', bold: true);
  final slotStyle = style(color: '#F3F4EF');
  final commonStyle = style(color: '#F3EEDB');
  final bodyStyle = style();
  final titleStyle = style(size: 14, bold: true);
  final blackBorder = Border(
    borderStyle: BorderStyle.Thin,
    borderColorHex: ExcelColor.black,
  );
  final dottedBorder = Border(
    borderStyle: BorderStyle.Dotted,
    borderColorHex: ExcelColor.black,
  );
  final noBorder = Border(borderStyle: BorderStyle.None);
  final gridHeaderStyle = style(
    color: '#DCEBD2',
    bold: true,
    edge: blackBorder,
  );
  final gridSlotStyle = style(color: '#F3F4EF', edge: blackBorder);
  final gridTitleStyle = style(size: 14, bold: true, edge: blackBorder);
  final gridCommonStyle = style(color: '#F3EEDB', edge: blackBorder);
  final classSubjectStyle = style(
    size: 12,
    bold: true,
    edge: blackBorder,
  ).copyWith(bottomBorderVal: dottedBorder);
  final classDetailStyle = style(edge: blackBorder)
      .copyWith(topBorderVal: dottedBorder);
  final teacherSubjectStyle = style(
    size: 12,
    bold: true,
    edge: blackBorder,
  ).copyWith(bottomBorderVal: noBorder);
  final teacherDetailStyle = style(edge: blackBorder)
      .copyWith(topBorderVal: noBorder);
  void put(Sheet sheet, int row, int col, String value, CellStyle style) {
    final target = sheet.cell(cell(row, col));
    target.value = TextCellValue(value);
    target.cellStyle = style;
  }

  void writeCommonRow(Sheet sheet, int row, _ExportSlot slot, List<int> days) {
    put(sheet, row, 0, slot.time, gridSlotStyle);
    var start = 0;
    while (start < days.length) {
      final active =
          routineByStage[slot.stageId]?.teachingWeekdays.contains(
            days[start],
          ) ==
          true;
      var end = start + 1;
      while (end < days.length &&
          (routineByStage[slot.stageId]?.teachingWeekdays.contains(days[end]) ==
                  true) ==
              active) {
        end++;
      }
      for (var i = start; i < end; i++) {
        put(
          sheet,
          row,
          i + 1,
          active ? slot.common!.name : '',
          gridCommonStyle,
        );
      }
      if (active && end - start > 1) {
        sheet.merge(cell(row, start + 1), cell(row, end));
        put(sheet, row, start + 1, slot.common!.name, gridCommonStyle);
        sheet.setMergedCellStyle(cell(row, start + 1), gridCommonStyle);
      }
      start = end;
    }
  }

  void title(Sheet sheet, String value, int columns, {bool framed = false}) {
    if (columns > 1) sheet.merge(cell(0, 0), cell(0, columns - 1));
    final selectedStyle = framed ? gridTitleStyle : titleStyle;
    put(sheet, 0, 0, value, selectedStyle);
    if (framed && columns > 1) {
      sheet.setMergedCellStyle(cell(0, 0), selectedStyle);
    }
    sheet.setRowHeight(0, 28);
    sheet.setColumnWidth(0, 15);
    for (var col = 1; col < columns; col++) {
      sheet.setColumnWidth(col, 18);
    }
  }

  final sortedClasses = [...snapshot.classes]
    ..sort((a, b) {
      final ag = gradeById[a.gradeId], bg = gradeById[b.gradeId];
      final st = (stageById[ag?.stageId]?.sortOrder ?? 0).compareTo(
        stageById[bg?.stageId]?.sortOrder ?? 0,
      );
      if (st != 0) return st;
      final grade = (ag?.sortOrder ?? 0).compareTo(bg?.sortOrder ?? 0);
      return grade != 0 ? grade : a.sortOrder.compareTo(b.sortOrder);
    });
  for (final c in sortedClasses) {
    final stageId = snapshot.stageIdForClass(c.id);
    if (stageId == null) continue;
    final days = daysFor(stageId);
    final slots = stageSlots[stageId] ?? [];
    final sheet = newSheet(classes, displayClassName(c.id));
    title(
      sheet,
      '$heading ${displayClassName(c.id)}课表',
      days.length + 1,
      framed: true,
    );
    put(sheet, 1, 0, '课节', gridHeaderStyle);
    for (var d = 0; d < days.length; d++) {
      put(sheet, 1, d + 1, '星期${_weekday(days[d])}', gridHeaderStyle);
    }
    var row = 2;
    final mine = placed.where((item) => item.classId == c.id).toList();
    for (final slot in slots) {
      if (slot.common != null) {
        writeCommonRow(sheet, row, slot, days);
        sheet.setRowHeight(row, 25);
        row++;
        continue;
      }
      sheet.merge(cell(row, 0), cell(row + 1, 0));
      put(sheet, row, 0, slot.header, gridSlotStyle);
      sheet.setMergedCellStyle(cell(row, 0), gridSlotStyle);
      sheet.setRowHeight(row, 25);
      sheet.setRowHeight(row + 1, 15);
      for (var d = 0; d < days.length; d++) {
        final day = days[d];
        final courses = atSlot(mine, slot, day);
        final duties = dutiesAtSlot(
          slot,
          day,
        ).where((duty) => duty.classIds.contains(c.id));
        final label = freeLabel(c.id, slot, day);
        put(
          sheet,
          row,
          d + 1,
          courses.isNotEmpty || duties.isNotEmpty
              ? [
                  ...courses.map(subject),
                  ...duties.map((duty) => duty.post.name),
                ].join('\n')
              : label ?? (available(slot, day) ? '' : '—'),
          classSubjectStyle,
        );
        put(
          sheet,
          row + 1,
          d + 1,
          {
            ...courses.map((item) => '${week(item)}${teacherName(item)}'),
            ...duties.map(dutyTeacher),
          }.join('\n'),
          classDetailStyle,
        );
      }
      row += 2;
    }
  }
  for (final teacher in snapshot.teachers) {
    final mine = placed.where((item) => item.teacherId == teacher.id).toList();
    final stageIds = <String>{
      for (final item in snapshot.assignments.where(
        (a) => a.teacherId == teacher.id,
      ))
        ?snapshot.stageIdForClass(item.classId),
      for (final item in mine) ?snapshot.stageIdForClass(item.classId),
      for (final duty in snapshot.visibleSupervision)
        if (duty.teacherId == teacher.id) duty.position.stageId,
    };
    final selectedStages = snapshot.stages
        .where((stage) => stageIds.contains(stage.id))
        .toList();
    final sheet = newSheet(teachers, teacher.displayName);
    final days = <int>{
      for (final stage in selectedStages) ...daysFor(stage.id),
    }.toList()..sort();
    title(
      sheet,
      '$heading ${teacher.displayName}课表',
      days.length + 1,
      framed: true,
    );
    put(sheet, 1, 0, '课节', gridHeaderStyle);
    for (var d = 0; d < days.length; d++) {
      put(sheet, 1, d + 1, '星期${_weekday(days[d])}', gridHeaderStyle);
    }
    var row = 2;
    final groups = <List<_ExportSlot>>[];
    if (options.teacherUnified) {
      final slots = <_ExportSlot>[];
      for (final stage in selectedStages) {
        slots.addAll(stageSlots[stage.id] ?? []);
      }
      final byKey = <String, List<_ExportSlot>>{};
      for (final slot in slots) {
        final key = slot.common != null
            ? 'common:${slot.common!.id}'
            : (slot.start != null && slot.end != null
                  ? 'clock:${slot.start}:${slot.end}'
                  : 'stage:${slot.stageId}:${slot.periodId}:${slot.lessonIndex}');
        byKey.putIfAbsent(key, () => []).add(slot);
      }
      groups.addAll(byKey.values);
      double orderOf(_ExportSlot slot) {
        if (slot.start != null) return slot.start!.toDouble();
        final stageRows = stageSlots[slot.stageId] ?? const <_ExportSlot>[];
        final index = stageRows.indexOf(slot);
        for (var i = index - 1; i >= 0; i--) {
          final previous = stageRows[i];
          if (previous.end != null) return previous.end! + (index - i) / 100;
          if (previous.start != null) {
            return previous.start! + (index - i) / 100;
          }
        }
        for (var i = index + 1; i < stageRows.length; i++) {
          if (stageRows[i].start != null) {
            return stageRows[i].start! - (i - index) / 100;
          }
        }
        return 10000 + index.toDouble();
      }

      groups.sort((a, b) => orderOf(a.first).compareTo(orderOf(b.first)));
    } else {
      for (final stage in selectedStages) {
        groups.add([
          _ExportSlot(
            stageId: stage.id,
            label: stage.name,
            periodId: null,
            lessonIndex: null,
            start: null,
            end: null,
          ),
        ]);
        for (final slot in stageSlots[stage.id] ?? <_ExportSlot>[]) {
          groups.add([slot]);
        }
      }
    }
    for (final group in groups) {
      final slot = group.first;
      if (!options.teacherUnified &&
          slot.periodId == null &&
          slot.common == null) {
        if (days.isNotEmpty) sheet.merge(cell(row, 0), cell(row, days.length));
        put(sheet, row, 0, slot.label, gridHeaderStyle);
        row++;
        continue;
      }
      if (slot.common != null) {
        writeCommonRow(sheet, row, slot, days);
        sheet.setRowHeight(row, 25);
        row++;
        continue;
      }
      sheet.merge(cell(row, 0), cell(row + 1, 0));
      put(sheet, row, 0, slot.header, gridSlotStyle);
      sheet.setMergedCellStyle(cell(row, 0), gridSlotStyle);
      sheet.setRowHeight(row, 25);
      sheet.setRowHeight(row + 1, 15);
      for (var d = 0; d < days.length; d++) {
        final found = [
          for (final entry in group) ...atSlot(mine, entry, days[d]),
        ];
        final duties = [
          for (final entry in group)
            ...dutiesAtSlot(
              entry,
              days[d],
            ).where((duty) => duty.teacherId == teacher.id),
        ];
        put(
          sheet,
          row,
          d + 1,
          [
            ...found.map(subject),
            ...duties.map((duty) => duty.post.name),
          ].join('\n'),
          teacherSubjectStyle,
        );
        put(
          sheet,
          row + 1,
          d + 1,
          {
            ...found.map(
              (item) =>
                  '${week(item)}${options.showTeacherStage && selectedStages.length > 1 ? '${stageNames[snapshot.stageIdForClass(item.classId)] ?? ''} · ' : ''}${className(item)}',
            ),
            ...duties.map(dutyClasses),
          }.join('\n'),
          teacherDetailStyle,
        );
      }
      row += 2;
    }
  }
  for (final stage in snapshot.stages) {
    final slots = stageSlots[stage.id] ?? <_ExportSlot>[];
    final days = daysFor(stage.id);
    final stageClasses = sortedClasses
        .where((c) => snapshot.stageIdForClass(c.id) == stage.id)
        .toList();
    if (stageClasses.isEmpty) continue;
    final dayGroups = options.schoolWeekly
        ? [days]
        : [
            for (final day in days) [day],
          ];
    for (final group in dayGroups) {
      final sheet = newSheet(
        school,
        options.schoolWeekly
            ? stage.name
            : '${stage.name} 周${_weekday(group.first)}',
      );
      title(
        sheet,
        '$heading ${stage.name}${options.schoolWeekly ? '整周' : '周${_weekday(group.first)}'}总课表',
        slots.length + 1,
      );
      var row = 1;
      for (final day in group) {
        if (slots.isNotEmpty) {
          sheet.merge(cell(row, 0), cell(row, slots.length));
        }
        put(sheet, row, 0, '星期${_weekday(day)}', headerStyle);
        sheet.setRowHeight(row, 25);
        row++;
        put(sheet, row, 0, '班级', headerStyle);
        for (var col = 0; col < slots.length; col++) {
          put(sheet, row, col + 1, slots[col].header, headerStyle);
        }
        sheet.setRowHeight(row, 34);
        row++;
        for (final c in stageClasses) {
          put(sheet, row, 0, displayClassName(c.id), slotStyle);
          sheet.setRowHeight(row, 42);
          for (var col = 0; col < slots.length; col++) {
            final slot = slots[col];
            if (slot.common != null) {
              put(
                sheet,
                row,
                col + 1,
                routineByStage[stage.id]?.teachingWeekdays.contains(day) == true
                    ? slot.common!.name
                    : '',
                commonStyle,
              );
              continue;
            }
            final found = atSlot(
              placed.where((i) => i.classId == c.id).toList(),
              slot,
              day,
            );
            final label = freeLabel(c.id, slot, day);
            final duties = dutiesAtSlot(
              slot,
              day,
            ).where((duty) => duty.classIds.contains(c.id));
            put(
              sheet,
              row,
              col + 1,
              found.isNotEmpty || duties.isNotEmpty
                  ? [
                      ...found.map(
                        (item) => '${subject(item)}\n${teacherName(item)}',
                      ),
                      ...duties.map(
                        (duty) =>
                            '${duty.post.name}\n${dutyTeacher(duty)}\n${dutyClasses(duty)}',
                      ),
                    ].join('\n')
                  : label ?? (available(slot, day) ? '' : '—'),
              bodyStyle,
            );
          }
          row++;
        }
      }
    }
  }
  List<int> finish(Excel book) {
    if (book.tables.length > 1) book.delete('Sheet1');
    if (book.tables.length == 1 && book.tables.containsKey('Sheet1')) {
      book.rename('Sheet1', '暂无课表');
    }
    return book.encode() ?? (throw StateError('生成课表工作簿失败'));
  }

  return TimetableWorkbooks(
    classWorkbook: finish(classes),
    teacherWorkbook: finish(teachers),
    schoolWorkbook: finish(school),
  );
}

/// 文件名中剔除系统不允许的字符，并保留可辨认的学校和学期名称。
String _timetableFilePrefix(String schoolName, AcademicTerm term) {
  String clean(String value) => value
      .trim()
      .replaceAll(RegExp(r'[\x00-\x1f\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  final school = clean(schoolName);
  final title = clean(term.title);
  final semester = title.isEmpty
      ? clean('${term.academicYear} ${term.semesterLabel}')
      : title;
  return '${school.isEmpty ? '未命名学校' : school}_${semester.isEmpty ? '未命名学期' : semester}';
}

String timetableZipFileName(String schoolName, AcademicTerm term) =>
    '${_timetableFilePrefix(schoolName, term)}_课表.zip';

/// 将三个课表工作簿合并成一个 ZIP，保留 UTF-8 文件名。
List<int> buildTimetableZip(
  SchedulingSnapshot snapshot,
  List<ScheduleItem> items, {
  required String schoolName,
  required Map<String, List<CommonPeriod>> commonPeriods,
  required TimetableExportOptions options,
}) {
  final books = buildTimetableWorkbooks(
    snapshot,
    items,
    schoolName: schoolName,
    commonPeriods: commonPeriods,
    options: options,
  );
  final prefix = _timetableFilePrefix(schoolName, snapshot.term);
  final files = {
    '${prefix}_班级课表.xlsx': books.classWorkbook,
    '${prefix}_教师课表.xlsx': books.teacherWorkbook,
    '${prefix}_学校总课表.xlsx': books.schoolWorkbook,
  };
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encode(archive) ?? (throw StateError('打包课表失败'));
}

/// 在后台生成压缩包，避免捕获页面状态及 UI 对象。
Future<List<int>> buildTimetableZipAsync(
  SchedulingSnapshot snapshot,
  List<ScheduleItem> items, {
  required String schoolName,
  required Map<String, List<CommonPeriod>> commonPeriods,
  required TimetableExportOptions options,
}) => Isolate.run(
  () => buildTimetableZip(
    snapshot,
    items,
    schoolName: schoolName,
    commonPeriods: commonPeriods,
    options: options,
  ),
);
