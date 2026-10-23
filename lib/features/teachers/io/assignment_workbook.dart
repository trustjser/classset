import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:excel/excel.dart';

class AssignmentWorkbookError {
  const AssignmentWorkbookError(this.rowNumber, this.message);
  final int rowNumber;
  final String message;

  @override
  String toString() => '第 $rowNumber 行：$message';
}

class AssignmentWorkbookRow {
  const AssignmentWorkbookRow({
    required this.stage,
    required this.grade,
    required this.schoolClass,
    required this.subject,
    required this.teacher,
    required this.weekMode,
    required this.lessonCount,
    required this.rowNumber,
  });

  final String stage;
  final String grade;
  final String schoolClass;
  final String subject;
  final String teacher;
  final WeekMode weekMode;
  final int lessonCount;
  final int rowNumber;
}

class AssignmentWorkbookResult {
  const AssignmentWorkbookResult({
    this.rows = const [],
    this.errors = const [],
  });
  final List<AssignmentWorkbookRow> rows;
  final List<AssignmentWorkbookError> errors;
}

class ResolvedAssignmentRow {
  const ResolvedAssignmentRow({
    required this.source,
    required this.teacherId,
    required this.classId,
    required this.subjectId,
  });
  final AssignmentWorkbookRow source;
  final String teacherId;
  final String classId;
  final String subjectId;
}

class AssignmentImportPlan {
  const AssignmentImportPlan({this.rows = const [], this.errors = const []});
  final List<ResolvedAssignmentRow> rows;
  final List<AssignmentWorkbookError> errors;
}

const _headers = ['学段', '年级', '班级', '科目', '教师', '周模式', '节数'];

List<int> buildAssignmentWorkbook(
  List<AssignmentWorkbookRow> rows, {
  List<SchoolStage> stages = const [],
  List<GradeGroup> grades = const [],
  List<ClassBrief> classes = const [],
  List<Subject> subjects = const [],
  List<Teacher> teachers = const [],
  List<SubjectRequirement> requirements = const [],
  List<TeacherAssignment> existingAssignments = const [],
}) {
  final book = Excel.createExcel();
  book.rename(book.getDefaultSheet()!, '导入说明');
  final instructions = book['导入说明'];
  for (final line in [
    ['任课分配 Excel 导入说明'],
    ['填写位置', '请只在「任课分配」工作表中填写数据；每行代表一条任课分配。'],
    ['学段、年级、班级', '按「数据源」中的组合填写完整名称，不能只填班级。'],
    ['科目', '使用「数据源」中的科目全称。'],
    ['教师', '使用「数据源」中的教师显示名称；同名教师须包含括号中的限定词。'],
    ['周模式', '只能填写「每周」「单周」「双周」，并须与该班级科目需求一致。'],
    ['节数', '填写大于 0 的整数；同一班级、科目、周模式的总分配不能超过需求。'],
    ['导入方式', '上传后先预览，确认后追加任课；已有任课不会被覆盖。'],
    ['数据源', '前七列是可分配的班级科目与剩余节数；最后一列是独立的可选教师名单。'],
  ]) {
    instructions.appendRow(line.map(TextCellValue.new).toList());
  }
  instructions.setColumnWidth(0, 20);
  instructions.setColumnWidth(1, 85);

  final source = book['数据源'];
  source.appendRow([
    for (final header in [
      '学段',
      '年级',
      '班级',
      '科目',
      '周模式',
      '需求节数',
      '剩余可分配节数',
      '可选教师（独立列表）',
    ])
      TextCellValue(header),
  ]);
  final stageNames = {for (final stage in stages) stage.id: stage.name};
  final gradeById = {for (final grade in grades) grade.id: grade};
  final used = <(String, String, WeekMode), int>{};
  for (final assignment in existingAssignments.where(
    (item) => item.teacherId.isNotEmpty,
  )) {
    final key = (assignment.classId, assignment.subjectId, assignment.weekMode);
    used.update(
      key,
      (count) => count + assignment.lessonCount,
      ifAbsent: () => assignment.lessonCount,
    );
  }
  final choices = <List<CellValue>>[];
  for (final schoolClass in classes) {
    final grade = gradeById[schoolClass.gradeId];
    if (grade == null) continue;
    for (final subject in subjects) {
      final scoped = requirements
          .where(
            (item) =>
                item.gradeId == grade.id &&
                item.subjectId == subject.id &&
                item.classId == schoolClass.id,
          )
          .toList();
      final effective = scoped.isNotEmpty
          ? scoped
          : requirements.where(
              (item) =>
                  item.gradeId == grade.id &&
                  item.subjectId == subject.id &&
                  item.classId == null,
            );
      for (final demand in effective.where((item) => item.lessonCount > 0)) {
        final remaining =
            demand.lessonCount -
            (used[(schoolClass.id, subject.id, demand.weekMode)] ?? 0);
        choices.add([
          TextCellValue(stageNames[schoolClass.stageId] ?? ''),
          TextCellValue(grade.name),
          TextCellValue(schoolClass.name),
          TextCellValue(subject.name),
          TextCellValue(demand.weekMode.label),
          IntCellValue(demand.lessonCount),
          IntCellValue(remaining < 0 ? 0 : remaining),
        ]);
      }
    }
  }
  final teacherNames = teachers.map((teacher) => teacher.displayName).toList();
  for (
    var index = 0;
    index <
        (choices.length > teacherNames.length
            ? choices.length
            : teacherNames.length);
    index++
  ) {
    source.appendRow([
      if (index < choices.length)
        ...choices[index]
      else
        ...List<CellValue>.generate(7, (_) => TextCellValue('')),
      TextCellValue(index < teacherNames.length ? teacherNames[index] : ''),
    ]);
  }
  for (var index = 0; index < 8; index++) {
    source.setColumnWidth(index, index == 7 ? 28 : 18);
  }

  final sheet = book['任课分配'];
  sheet.appendRow(_headers.map(TextCellValue.new).toList());
  for (var index = 0; index < _headers.length; index++) {
    sheet.setColumnWidth(index, 18);
  }
  for (final row in rows) {
    sheet.appendRow([
      TextCellValue(row.stage),
      TextCellValue(row.grade),
      TextCellValue(row.schoolClass),
      TextCellValue(row.subject),
      TextCellValue(row.teacher),
      TextCellValue(row.weekMode.label),
      IntCellValue(row.lessonCount),
    ]);
  }
  return book.encode()!;
}

AssignmentWorkbookResult parseAssignmentWorkbook(List<int> bytes) {
  try {
    final book = Excel.decodeBytes(bytes);
    final sheet = book.tables['任课分配'] ?? book.tables.values.firstOrNull;
    if (sheet == null || sheet.rows.isEmpty) {
      return const AssignmentWorkbookResult(
        errors: [AssignmentWorkbookError(1, '工作表为空')],
      );
    }
    final rows = sheet.rows;
    final headers = rows.first
        .map((cell) => cell?.value?.toString().trim() ?? '')
        .toList();
    if (headers.length != _headers.length ||
        !_headers.every(
          (header) => headers.where((item) => item == header).length == 1,
        )) {
      return const AssignmentWorkbookResult(
        errors: [AssignmentWorkbookError(1, '表头必须包含学段、年级、班级、科目、教师、周模式、节数各一列')],
      );
    }
    final parsed = <AssignmentWorkbookRow>[];
    final errors = <AssignmentWorkbookError>[];
    for (var index = 1; index < rows.length; index++) {
      final cells = rows[index];
      String value(String header) {
        final column = headers.indexOf(header);
        return column < cells.length
            ? cells[column]?.value?.toString().trim() ?? ''
            : '';
      }

      if (_headers.every((header) => value(header).isEmpty)) continue;
      final fields = _headers.take(5).map(value).toList();
      if (fields.any((item) => item.isEmpty)) {
        errors.add(AssignmentWorkbookError(index + 1, '学段、年级、班级、科目、教师不能为空'));
        continue;
      }
      final mode = WeekMode.values
          .where((item) => item.label == value('周模式'))
          .firstOrNull;
      if (mode == null) {
        errors.add(AssignmentWorkbookError(index + 1, '周模式只能是每周、单周或双周'));
        continue;
      }
      final count = int.tryParse(value('节数'));
      if (count == null || count <= 0) {
        errors.add(AssignmentWorkbookError(index + 1, '节数必须是正整数'));
        continue;
      }
      parsed.add(
        AssignmentWorkbookRow(
          stage: fields[0],
          grade: fields[1],
          schoolClass: fields[2],
          subject: fields[3],
          teacher: fields[4],
          weekMode: mode,
          lessonCount: count,
          rowNumber: index + 1,
        ),
      );
    }
    if (errors.isNotEmpty) return AssignmentWorkbookResult(errors: errors);
    if (parsed.isEmpty) {
      return const AssignmentWorkbookResult(
        errors: [AssignmentWorkbookError(2, '没有可导入的任课数据')],
      );
    }
    return AssignmentWorkbookResult(rows: parsed);
  } catch (_) {
    return const AssignmentWorkbookResult(
      errors: [AssignmentWorkbookError(1, '无法读取 Excel 文件，请选择有效的 .xlsx 文件')],
    );
  }
}

AssignmentImportPlan resolveAssignmentWorkbook({
  required List<AssignmentWorkbookRow> rows,
  required List<SchoolStage> stages,
  required List<GradeGroup> grades,
  required List<ClassBrief> classes,
  required List<Subject> subjects,
  required List<Teacher> teachers,
  required List<SubjectRequirement> requirements,
  required List<TeacherAssignment> existingAssignments,
}) {
  final resolved = <ResolvedAssignmentRow>[];
  final errors = <AssignmentWorkbookError>[];
  final totals = <(String, String, WeekMode), int>{};
  for (final assignment in existingAssignments.where(
    (item) => item.teacherId.isNotEmpty,
  )) {
    final key = (assignment.classId, assignment.subjectId, assignment.weekMode);
    totals.update(
      key,
      (count) => count + assignment.lessonCount,
      ifAbsent: () => assignment.lessonCount,
    );
  }
  for (final row in rows) {
    final stageMatches = stages
        .where((item) => item.name == row.stage)
        .toList();
    final gradeMatches = grades
        .where(
          (item) =>
              stageMatches.any((stage) => stage.id == item.stageId) &&
              item.name == row.grade,
        )
        .toList();
    final classMatches = classes
        .where(
          (item) =>
              gradeMatches.any((grade) => grade.id == item.gradeId) &&
              item.name == row.schoolClass,
        )
        .toList();
    final subjectMatches = subjects
        .where((item) => item.name == row.subject)
        .toList();
    final teacherMatches = teachers
        .where((item) => item.displayName == row.teacher)
        .toList();
    if (stageMatches.length != 1 ||
        gradeMatches.length != 1 ||
        classMatches.length != 1 ||
        subjectMatches.length != 1 ||
        teacherMatches.length != 1) {
      final ambiguous = [
        stageMatches,
        gradeMatches,
        classMatches,
        subjectMatches,
        teacherMatches,
      ].any((items) => items.length > 1);
      errors.add(
        AssignmentWorkbookError(
          row.rowNumber,
          ambiguous ? '学段、年级、班级、科目或教师名称重复，请使用可唯一识别的名称' : '学段、年级、班级、科目或教师不存在',
        ),
      );
      continue;
    }
    final schoolClass = classMatches.single;
    final subject = subjectMatches.single;
    final scoped = requirements
        .where(
          (item) =>
              item.gradeId == schoolClass.gradeId &&
              item.subjectId == subject.id &&
              item.classId == schoolClass.id,
        )
        .toList();
    final effective = scoped.isNotEmpty
        ? scoped
        : requirements
              .where(
                (item) =>
                    item.gradeId == schoolClass.gradeId &&
                    item.subjectId == subject.id &&
                    item.classId == null,
              )
              .toList();
    final demand = effective
        .where((item) => item.weekMode == row.weekMode)
        .firstOrNull;
    if (demand == null || demand.lessonCount <= 0) {
      errors.add(
        AssignmentWorkbookError(
          row.rowNumber,
          '该班级科目未设置${row.weekMode.label}节数需求',
        ),
      );
      continue;
    }
    final key = (schoolClass.id, subject.id, row.weekMode);
    final next = (totals[key] ?? 0) + row.lessonCount;
    if (next > demand.lessonCount) {
      errors.add(
        AssignmentWorkbookError(
          row.rowNumber,
          '任课总节数 $next 超过需求 ${demand.lessonCount}',
        ),
      );
      continue;
    }
    totals[key] = next;
    resolved.add(
      ResolvedAssignmentRow(
        source: row,
        teacherId: teacherMatches.single.id,
        classId: schoolClass.id,
        subjectId: subject.id,
      ),
    );
  }
  if (errors.isNotEmpty) return AssignmentImportPlan(errors: errors);
  return AssignmentImportPlan(rows: resolved);
}
