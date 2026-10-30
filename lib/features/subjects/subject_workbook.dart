import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:excel/excel.dart';

class SubjectWorkbookPlan {
  const SubjectWorkbookPlan({this.values = const {}, this.errors = const []});
  final Map<(String, String), ClassSubjectValues> values;
  final List<String> errors;
}

const _headers = ['学段', '年级', '科目', '节数'];

List<int> buildSubjectWorkbook({
  required List<SchoolStage> stages,
  required List<GradeGroup> grades,
  required List<ClassBrief> classes,
  required List<Subject> subjects,
  required Map<(String, String), ClassSubjectValues> values,
  required bool includeExisting,
}) {
  final book = Excel.createExcel();
  book.rename(book.getDefaultSheet()!, '导入说明');
  final instructions = book['导入说明'];
  for (final row in [
    ['科目节数导入说明'],
    ['填写位置', '请在“科目节数”工作表填写，名称参照“基础数据”。'],
    ['范围', '每行填写一个年级的一门科目；同一年级同一科目只能填写一次。'],
    ['统一节数', '填写 3 表示年级所有班级每周 3 节；填写 0 可以清零。'],
    ['按班区分', '用英文逗号按“基础数据”的班级顺序填写，例如 3,2；数量须与班级数一致。'],
    ['单双周', '用每周|单周|双周填写，例如 2|1|1；各班不同时可填写 2|1|1,3|0|1。'],
    ['导入方式', '仅更新表中填写的年级和科目；确认导入后请在页面保存。'],
  ]) {
    instructions.appendRow(row.map(TextCellValue.new).toList());
  }
  instructions.setColumnWidth(0, 20);
  instructions.setColumnWidth(1, 90);
  final stageNames = {for (final stage in stages) stage.id: stage.name};
  final gradeNames = {for (final grade in grades) grade.id: grade.name};
  final source = book['基础数据'];
  source.appendRow([
    for (final name in ['学段', '年级', '班级顺序（逗号对应顺序）', '科目（独立列表）'])
      TextCellValue(name),
  ]);
  for (
    var i = 0;
    i < (grades.length > subjects.length ? grades.length : subjects.length);
    i++
  ) {
    final grade = i < grades.length ? grades[i] : null;
    source.appendRow([
      TextCellValue(stageNames[grade?.stageId] ?? ''),
      TextCellValue(grade?.name ?? ''),
      TextCellValue(
        classes
            .where((item) => item.gradeId == grade?.id)
            .map((item) => item.name)
            .join('、'),
      ),
      TextCellValue(i < subjects.length ? subjects[i].name : ''),
    ]);
  }
  for (var i = 0; i < 4; i++) {
    source.setColumnWidth(i, 22);
  }
  final sheet = book['科目节数'];
  sheet.appendRow([for (final header in _headers) TextCellValue(header)]);
  if (includeExisting) {
    for (final grade in grades) {
      final gradeClasses = classes
          .where((item) => item.gradeId == grade.id)
          .toList();
      if (gradeClasses.isEmpty) continue;
      for (final subject in subjects) {
        final entries = [
          for (final schoolClass in gradeClasses)
            values[(schoolClass.id, subject.id)] ?? const ClassSubjectValues(),
        ];
        if (entries.every((value) => value.isAllZero)) continue;
        sheet.appendRow([
          TextCellValue(stageNames[grade.stageId] ?? ''),
          TextCellValue(gradeNames[grade.id] ?? ''),
          TextCellValue(subject.name),
          TextCellValue(formatLessonInput(entries)),
        ]);
      }
    }
  }
  for (var i = 0; i < 4; i++) {
    sheet.setColumnWidth(i, i == 3 ? 36 : 22);
  }
  return book.encode()!;
}

SubjectWorkbookPlan parseSubjectWorkbook(
  List<int> bytes, {
  required List<SchoolStage> stages,
  required List<GradeGroup> grades,
  required List<ClassBrief> classes,
  required List<Subject> subjects,
  required bool alternating,
}) {
  try {
    final book = _decodeSubjectWorkbook(bytes);
    final sheet = book.tables['科目节数'];
    if (sheet == null || sheet.rows.isEmpty) {
      return const SubjectWorkbookPlan(errors: ['缺少“科目节数”工作表，请使用导入模板']);
    }
    String text(CellValue? value) => value?.toString().trim() ?? '';
    final headers = sheet.rows.first.map((cell) => text(cell?.value)).toList();
    if (_headers.any(
      (header) => headers.where((item) => item == header).length != 1,
    )) {
      return const SubjectWorkbookPlan(errors: ['“科目节数”表头需要包含学段、年级、科目、节数']);
    }
    final errors = <String>[];
    final values = <(String, String), ClassSubjectValues>{};
    for (var i = 1; i < sheet.rows.length; i++) {
      final cells = sheet.rows[i];
      String at(String name) {
        final index = headers.indexOf(name);
        return index < cells.length ? text(cells[index]?.value) : '';
      }

      if (cells.every((cell) => text(cell?.value).isEmpty)) continue;
      void error(String message) => errors.add('第 ${i + 1} 行：$message');
      final matchingStages = stages
          .where((item) => item.name.trim() == at('学段'))
          .toList();
      if (matchingStages.length != 1) {
        error('学段不存在或名称不唯一：${at('学段')}');
        continue;
      }
      final matchingGrades = grades
          .where(
            (item) =>
                item.stageId == matchingStages.single.id &&
                item.name.trim() == at('年级'),
          )
          .toList();
      if (matchingGrades.length != 1) {
        error('年级不存在或名称不唯一：${at('年级')}');
        continue;
      }
      final targets = classes
          .where((item) => item.gradeId == matchingGrades.single.id)
          .toList();
      if (targets.isEmpty) {
        error('该年级没有班级');
        continue;
      }
      final matchingSubjects = subjects
          .where((item) => item.name.trim() == at('科目'))
          .toList();
      if (matchingSubjects.length != 1) {
        error('科目不存在或名称不唯一：${at('科目')}');
        continue;
      }
      final counts = parseLessonInput(at('节数'));
      if (counts == null || counts.isEmpty) {
        error('节数格式无效，请填写非负整数，如 3、3,2 或 2|1|1；清零请填写 0');
        continue;
      }
      if (counts.length != 1 && counts.length != targets.length) {
        error('逗号分隔的节数数量须与班级数一致（${targets.length} 个）');
        continue;
      }
      if (!alternating &&
          counts.any((value) => value.odd != 0 || value.even != 0)) {
        error('当前学期未开启单双周交替');
        continue;
      }
      for (var index = 0; index < targets.length; index++) {
        final schoolClass = targets[index];
        final key = (schoolClass.id, matchingSubjects.single.id);
        if (values.containsKey(key)) {
          error('${schoolClass.name}的${matchingSubjects.single.name}重复或范围重叠');
        } else {
          values[key] = counts.length == 1 ? counts.single : counts[index];
        }
      }
    }
    if (errors.isNotEmpty) return SubjectWorkbookPlan(errors: errors);
    if (values.isEmpty) return const SubjectWorkbookPlan(errors: ['没有可导入的数据']);
    return SubjectWorkbookPlan(values: values);
  } catch (_) {
    return const SubjectWorkbookPlan(errors: ['无法读取 Excel，请选择有效的 .xlsx 文件']);
  }
}

Excel _decodeSubjectWorkbook(List<int> bytes) {
  try {
    return Excel.decodeBytes(bytes);
  } catch (error) {
    if (!error.toString().contains('custom numFmtId starts at 164')) rethrow;
    final archive = ZipDecoder().decodeBytes(bytes);
    for (var index = 0; index < archive.length; index++) {
      final file = archive[index];
      if (file.name != 'xl/styles.xml') continue;
      final styles = utf8.decode(file.content as List<int>);
      final normalized = styles.replaceAllMapped(
        RegExp(
          r'<numFmt\b(?=[^>]*\bnumFmtId="(\d+)")[^>]*(?:/>|>\s*</numFmt>)',
        ),
        (match) => int.parse(match.group(1)!) < 164 ? '' : match.group(0)!,
      );
      if (normalized == styles) rethrow;
      final content = utf8.encode(normalized);
      archive[index] = ArchiveFile(file.name, content.length, content)
        ..lastModTime = file.lastModTime
        ..mode = file.mode
        ..ownerId = file.ownerId
        ..groupId = file.groupId
        ..compress = file.compress;
      return Excel.decodeBytes(ZipEncoder().encode(archive)!);
    }
    rethrow;
  }
}
