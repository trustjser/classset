import 'dart:isolate';
import 'dart:convert';

import 'package:archive/archive.dart';

import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/schedule_export.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final snapshot = SchedulingSnapshot(
    term: AcademicTerm(
      id: 't',
      title: '秋季',
      academicYear: '2026-2027',
      semesterLabel: '第一学期',
      firstTeachingWeekStart: null,
      teachingWeekCount: 20,
      createdAt: DateTime(2026),
    ),
    inputFingerprint: 'fixture',
    stages: const [
      SchoolStage(id: 's1', termId: 't', name: '小学部', sortOrder: 0),
      SchoolStage(id: 's2', termId: 't', name: '初中部', sortOrder: 1),
    ],
    grades: const [
      GradeGroup(id: 'g1', stageId: 's1', name: '一年级', sortOrder: 0),
      GradeGroup(id: 'g2', stageId: 's2', name: '七年级', sortOrder: 0),
    ],
    classes: const [
      ClassGroup(id: 'c1', gradeId: 'g1', name: '一班', sortOrder: 0),
      ClassGroup(id: 'c2', gradeId: 'g2', name: '一班', sortOrder: 0),
    ],
    teachers: const [
      Teacher(id: 'teacher', name: '李老师', shortName: '李', sortOrder: 0),
    ],
    subjects: const [
      Subject(id: 'subject', name: '语文', shortName: '语', sortOrder: 0),
    ],
    routines: const [
      StageRoutine(
        stageId: 's1',
        teachingWeekdays: {1, 6},
        periodTypes: [
          LessonPeriodType(
            id: 'p1',
            name: '上午',
            defaultLessonCount: 1,
            sortOrder: 0,
            lessonTimes: [
              LessonTime(
                lessonIndex: 1,
                label: '第一节',
                startMinute: 480,
                endMinute: 520,
              ),
            ],
          ),
        ],
        overrides: [],
      ),
      StageRoutine(
        stageId: 's2',
        teachingWeekdays: {1},
        periodTypes: [
          LessonPeriodType(
            id: 'p2',
            name: '上午',
            defaultLessonCount: 1,
            sortOrder: 0,
            lessonTimes: [
              LessonTime(
                lessonIndex: 1,
                label: '第一节',
                startMinute: 480,
                endMinute: 520,
              ),
            ],
          ),
        ],
        overrides: [],
      ),
    ],
  );
  const items = [
    ScheduleItem(
      id: 'i1',
      termId: 't',
      assignmentId: 'a',
      classId: 'c1',
      teacherId: 'teacher',
      subjectId: 'subject',
      weekMode: WeekMode.odd,
      position: SchedulePosition(
        stageId: 's1',
        weekday: 1,
        periodTypeId: 'p1',
        lessonIndex: 1,
        startMinute: 480,
        endMinute: 520,
      ),
    ),
    ScheduleItem(
      id: 'i2',
      termId: 't',
      assignmentId: 'b',
      classId: 'c2',
      teacherId: 'teacher',
      subjectId: 'subject',
      weekMode: WeekMode.even,
      position: SchedulePosition(
        stageId: 's2',
        weekday: 1,
        periodTypeId: 'p2',
        lessonIndex: 1,
        startMinute: 480,
        endMinute: 520,
      ),
    ),
  ];
  const common = {
    's1': [
      CommonPeriod(
        id: 'break',
        stageId: 's1',
        name: '大课间',
        insertAfterLessonId: 'p1_1',
        durationMinutes: 10,
        startMinute: null,
        endMinute: null,
      ),
    ],
  };
  String text(Sheet sheet) => sheet.rows
      .expand((row) => row)
      .whereType<Data>()
      .map((cell) => cell.value.toString())
      .join('|');

  test('按班、教师、学段分别输出并保留单双周和公共时段', () {
    final output = buildTimetableWorkbooks(
      snapshot,
      items,
      schoolName: '阳光学校',
      commonPeriods: common,
      options: const TimetableExportOptions(),
    );
    final classes = Excel.decodeBytes(output.classWorkbook);
    final teachers = Excel.decodeBytes(output.teacherWorkbook);
    final school = Excel.decodeBytes(output.schoolWorkbook);
    expect(classes.tables.length, 2);
    expect(teachers.tables.length, 1);
    expect(school.tables.length, 2);
    expect(text(classes.tables.values.first), contains('单周'));
    expect(text(classes.tables.values.first), contains('大课间'));
    expect(text(classes.tables.values.first), contains('星期六'));
    expect(text(teachers.tables.values.first), contains('小学部'));
    expect(text(teachers.tables.values.first), contains('初中部'));
    final mergedTeacherRow = teachers.tables.values.single.rows[2][1]!.value
        .toString();
    expect(mergedTeacherRow, contains('单周 语文'));
    expect(mergedTeacherRow, contains('双周 语文'));
    expect(text(school.tables.values.first), contains('星期六'));
    expect(classes.tables.values.first.spannedItems, isNotEmpty);
  });

  test('班级和教师课表使用参考样式并合并公共时段', () {
    final output = buildTimetableWorkbooks(
      snapshot,
      items,
      schoolName: '阳光学校',
      commonPeriods: common,
      options: const TimetableExportOptions(),
    );
    final classSheet = Excel.decodeBytes(output.classWorkbook)
        .tables
        .values
        .first;
    final teacherSheet = Excel.decodeBytes(output.teacherWorkbook)
        .tables
        .values
        .single;
    expect(classSheet.spannedItems, contains('B5:C5'));
    expect(teacherSheet.spannedItems, contains('B5:C5'));
    final classSubject = classSheet
        .cell(CellIndex.indexByString('B3'))
        .cellStyle!;
    final classTeacher = classSheet
        .cell(CellIndex.indexByString('B4'))
        .cellStyle!;
    final teacherSubject = teacherSheet
        .cell(CellIndex.indexByString('B3'))
        .cellStyle!;
    final teacherClass = teacherSheet
        .cell(CellIndex.indexByString('B4'))
        .cellStyle!;
    for (final sheet in [classSheet, teacherSheet]) {
      for (final address in ['A2', 'A3', 'A5']) {
        final edge = sheet
            .cell(CellIndex.indexByString(address))
            .cellStyle!
            .leftBorder;
        expect(edge.borderStyle, BorderStyle.Thin);
        expect(edge.borderColorHex, 'FF000000');
      }
    }
    for (final sheet in [classSheet, teacherSheet]) {
      final border = sheet.cell(CellIndex.indexByString('A1')).cellStyle!;
      for (final edge in [
        border.leftBorder,
        border.topBorder,
        border.bottomBorder,
      ]) {
        expect(edge.borderStyle, BorderStyle.Thin);
        expect(edge.borderColorHex, 'FF000000');
      }
    }
    expect(classSubject.fontSize, 12);
    expect(classSubject.isBold, isTrue);
    expect(classSubject.leftBorder.borderColorHex, 'FF000000');
    expect(classSubject.bottomBorder.borderStyle, BorderStyle.Dotted);
    expect(classTeacher.topBorder.borderStyle, BorderStyle.Dotted);
    expect(teacherSubject.fontSize, 12);
    expect(teacherSubject.isBold, isTrue);
    expect(teacherSubject.leftBorder.borderColorHex, 'FF000000');
    expect(teacherSubject.bottomBorder.borderStyle, isNull);
    expect(teacherClass.topBorder.borderStyle, isNull);
  });

  test('班级和教师课表的合并课节首列在原始文件中逐格写入边框', () {
    final output = buildTimetableWorkbooks(
      snapshot,
      items,
      schoolName: '阳光学校',
      commonPeriods: common,
      options: const TimetableExportOptions(),
    );
    for (final bytes in [output.classWorkbook, output.teacherWorkbook]) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final xml = utf8.decode(
        archive.files
                .firstWhere((entry) => entry.name == 'xl/worksheets/sheet1.xml')
                .content
            as List<int>,
      );
      expect(xml, matches(RegExp(r'<c\s+r="B1"\s+s="\d+"')));
      expect(xml, matches(RegExp(r'<c\s+r="C1"\s+s="\d+"')));
      expect(xml, matches(RegExp(r'<c\s+r="A4"\s+s="\d+"')));
      expect(xml, matches(RegExp(r'<c\s+r="A3"\s+s="\d+"')));
      expect(xml, matches(RegExp(r'<c\s+r="A5"\s+s="\d+"')));
    }
  });

  test('教师跨学段上课日不一致时不跨空白日期合并公共时段', () {
    final extra = ScheduleItem(
      id: 'extra',
      termId: 't',
      assignmentId: 'extra',
      classId: 'c2',
      teacherId: 'teacher',
      subjectId: 'subject',
      weekMode: WeekMode.weekly,
      position: const SchedulePosition(
        stageId: 's2',
        weekday: 2,
        periodTypeId: 'p2',
        lessonIndex: 1,
        startMinute: 480,
        endMinute: 520,
      ),
    );
    final output = buildTimetableWorkbooks(
      snapshot,
      [...items, extra],
      schoolName: '阳光学校',
      commonPeriods: common,
      options: const TimetableExportOptions(),
    );
    final sheet = Excel.decodeBytes(output.teacherWorkbook)
        .tables
        .values
        .single;
    String value(String address) =>
        sheet.cell(CellIndex.indexByString(address)).value?.toString() ?? '';
    expect(value('B5'), '大课间');
    expect(value('C5'), '');
    expect(value('D5'), '大课间');
    expect(sheet.spannedItems, isNot(contains('B5:D5')));
  });

  test('学校按天拆分且教师按学段分时显示', () {
    final output = buildTimetableWorkbooks(
      snapshot,
      items,
      schoolName: '阳光学校',
      commonPeriods: common,
      options: const TimetableExportOptions(
        teacherUnified: false,
        showTeacherStage: false,
        schoolWeekly: false,
      ),
    );
    final school = Excel.decodeBytes(output.schoolWorkbook);
    final teacher = Excel.decodeBytes(output.teacherWorkbook)
        .tables
        .values
        .single;
    expect(school.tables.length, 3);
    expect(text(teacher), contains('小学部'));
    expect(text(teacher), contains('初中部'));
    expect(text(teacher), isNot(contains('单周 小学部 ·')));
    expect(text(teacher), contains('单周 一年级 一班'));
  });
  test('缺少时钟信息的跨学段课节不合并', () {
    final noClock = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: 'fixture',
      stages: snapshot.stages,
      grades: snapshot.grades,
      classes: snapshot.classes,
      teachers: snapshot.teachers,
      subjects: snapshot.subjects,
      routines: [
        snapshot.routines.first,
        const StageRoutine(
          stageId: 's2',
          teachingWeekdays: {1},
          periodTypes: [
            LessonPeriodType(
              id: 'p2',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
          overrides: [],
        ),
      ],
    );
    final output = buildTimetableWorkbooks(
      noClock,
      items,
      schoolName: '阳光学校',
      commonPeriods: common,
      options: const TimetableExportOptions(),
    );
    final sheet = Excel.decodeBytes(output.teacherWorkbook)
        .tables
        .values
        .single;
    final firstColumn = sheet.rows
        .map((row) => row.isEmpty ? '' : row.first?.value.toString() ?? '')
        .where((value) => value.startsWith('第1节'))
        .toList();
    expect(firstColumn, hasLength(2));
  });
  test('免任课按班级范围展示，课表导出不会泄漏到其他班级', () {
    final withFreeSlot = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: 'fixture',
      stages: snapshot.stages,
      grades: snapshot.grades,
      classes: snapshot.classes,
      teachers: snapshot.teachers,
      subjects: snapshot.subjects,
      routines: snapshot.routines,
      freeSlots: const [
        FreeSlot(
          id: 'free',
          scope: FreeSlotScope.schoolClass,
          scopeId: 'c1',
          stageId: 's1',
          periodTypeId: 'p1',
          weekday: 6,
          lessonIndex: 1,
          label: '自习',
        ),
      ],
    );
    final output = buildTimetableWorkbooks(
      withFreeSlot,
      items,
      schoolName: '阳光学校',
      commonPeriods: common,
      options: const TimetableExportOptions(),
    );
    final book = Excel.decodeBytes(output.classWorkbook);
    expect(text(book.tables.values.first), contains('自习'));
    expect(text(book.tables.values.last), isNot(contains('自习')));
    final school = Excel.decodeBytes(output.schoolWorkbook);
    expect(text(school.tables.values.first), contains('自习'));
  });

  test('教师名字冲突及 Excel 保留表名不会丢失工作表', () {
    final duplicates = SchedulingSnapshot(
      term: snapshot.term,
      inputFingerprint: 'fixture',
      stages: snapshot.stages,
      grades: snapshot.grades,
      classes: snapshot.classes,
      routines: snapshot.routines,
      subjects: snapshot.subjects,
      teachers: const [
        Teacher(id: 'a', name: 'Sheet1', shortName: '甲', sortOrder: 0),
        Teacher(id: 'b', name: 'Sheet1', shortName: '乙', sortOrder: 1),
      ],
    );
    final output = buildTimetableWorkbooks(
      duplicates,
      items,
      schoolName: '阳光学校',
      commonPeriods: common,
      options: const TimetableExportOptions(),
    );
    final book = Excel.decodeBytes(output.teacherWorkbook);
    expect(book.tables.length, 2);
    expect(book.tables.keys.toSet(), {'Sheet1(2)', 'Sheet1(3)'});
  });
  test('工作簿可在后台隔离线程生成', () async {
    final output = await Isolate.run(
      () => buildTimetableWorkbooks(
        snapshot,
        items,
        schoolName: '阳光学校',
        commonPeriods: common,
        options: const TimetableExportOptions(),
      ),
    );
    expect(Excel.decodeBytes(output.classWorkbook).tables, hasLength(2));
  });
  test('课表压缩包包含三个完整工作簿，名称包含学校和学期', () {
    final zip = buildTimetableZip(
      snapshot,
      items,
      schoolName: '阳光学校',
      commonPeriods: common,
      options: const TimetableExportOptions(),
    );
    final contents = ZipDecoder().decodeBytes(zip);
    expect(contents.files.map((file) => file.name).toSet(), {
      '阳光学校_秋季_班级课表.xlsx',
      '阳光学校_秋季_教师课表.xlsx',
      '阳光学校_秋季_学校总课表.xlsx',
    });
    for (final file in contents.files) {
      final workbook = Excel.decodeBytes(file.content as List<int>);
      expect(workbook.tables, isNotEmpty);
    }
    expect(timetableZipFileName('阳光学校', snapshot.term), '阳光学校_秋季_课表.zip');
    expect(timetableZipFileName('阳光/学校', snapshot.term), isNot(contains('/')));
  });
}
