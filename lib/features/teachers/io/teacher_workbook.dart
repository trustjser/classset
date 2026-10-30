import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

class TeacherWorkbookError {
  const TeacherWorkbookError(this.rowNumber, this.message);

  final int rowNumber;
  final String message;

  @override
  String toString() => '第 $rowNumber 行：$message';
}

class TeacherWorkbookRow {
  const TeacherWorkbookRow({
    required this.name,
    this.shortName = '',
    this.groups = const [],
    this.subjects = const [],
    this.rowNumber = 0,
    this.hasGroups = true,
    this.hasSubjects = true,
  });

  final String name;
  final String shortName;
  final List<String> groups;
  final List<String> subjects;
  final int rowNumber;
  final bool hasGroups;
  final bool hasSubjects;
}

class TeacherWorkbookResult {
  const TeacherWorkbookResult({this.rows = const [], this.errors = const []});

  final List<TeacherWorkbookRow> rows;
  final List<TeacherWorkbookError> errors;
}

TeacherWorkbookResult parseTeachersWorkbook(List<int> bytes) {
  try {
    final book = _decodeTeachersWorkbook(bytes);
    if (book.tables.isEmpty || book.tables.values.first.rows.isEmpty) {
      return const TeacherWorkbookResult(
        errors: [TeacherWorkbookError(1, '工作表为空，请使用列：教师、简称')],
      );
    }
    final rows = (book.tables['教师'] ?? book.tables.values.first).rows;
    final headers = rows.first.map((cell) => _text(cell?.value)).toList();
    const required = ['教师', '简称'];
    if (required.any(
          (header) => headers.where((h) => h == header).length != 1,
        ) ||
        headers.where((header) => header == '分组').length > 1 ||
        headers.where((header) => header == '任课科目').length > 1 ||
        headers.any(
          (header) =>
              header.isNotEmpty && !['教师', '简称', '分组', '任课科目'].contains(header),
        )) {
      return const TeacherWorkbookResult(
        errors: [TeacherWorkbookError(1, '表头须包含「教师」「简称」，可包含「分组」「任课科目」')],
      );
    }
    final nameColumn = headers.indexOf('教师');
    final shortColumn = headers.indexOf('简称');
    final errors = <TeacherWorkbookError>[];
    final parsed = <TeacherWorkbookRow>[];
    for (var index = 1; index < rows.length; index++) {
      final cells = rows[index];
      if (cells.every((cell) => _text(cell?.value).isEmpty)) continue;
      CellValue? at(int column) =>
          column >= 0 && column < cells.length ? cells[column]?.value : null;
      final name = _text(at(nameColumn));
      final shortName = _text(at(shortColumn));
      if (name.isEmpty) {
        errors.add(TeacherWorkbookError(index + 1, '教师姓名不能为空'));
      } else {
        List<String> split(String header) =>
            _text(at(headers.indexOf(header)))
                .split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList();
        parsed.add(
          TeacherWorkbookRow(
            name: name,
            shortName: shortName,
            groups: split('分组'),
            subjects: split('任课科目'),
            rowNumber: index + 1,
            hasGroups: headers.contains('分组'),
            hasSubjects: headers.contains('任课科目'),
          ),
        );
      }
    }
    if (errors.isNotEmpty) return TeacherWorkbookResult(errors: errors);
    if (parsed.isEmpty) {
      return const TeacherWorkbookResult(
        errors: [TeacherWorkbookError(2, '没有可导入的教师数据')],
      );
    }
    return TeacherWorkbookResult(rows: parsed);
  } catch (_) {
    return const TeacherWorkbookResult(
      errors: [TeacherWorkbookError(1, '无法读取 Excel 文件，请选择有效的 .xlsx 文件')],
    );
  }
}

Excel _decodeTeachersWorkbook(List<int> bytes) {
  try {
    return Excel.decodeBytes(bytes);
  } catch (error) {
    if (!error.toString().contains('custom numFmtId starts at 164')) rethrow;
    return Excel.decodeBytes(_removeBuiltinNumberFormatDeclarations(bytes));
  }
}

List<int> _removeBuiltinNumberFormatDeclarations(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  for (var index = 0; index < archive.length; index++) {
    final file = archive[index];
    if (file.name != 'xl/styles.xml') continue;
    final styles = utf8.decode(file.content as List<int>);
    final normalized = styles.replaceAllMapped(
      RegExp(r'<numFmt\b(?=[^>]*\bnumFmtId="(\d+)")[^>]*(?:/>|>\s*</numFmt>)'),
      (match) => int.parse(match.group(1)!) < 164 ? '' : match.group(0)!,
    );
    if (normalized == styles) return bytes;
    final content = utf8.encode(normalized);
    archive[index] = ArchiveFile(file.name, content.length, content)
      ..lastModTime = file.lastModTime
      ..mode = file.mode
      ..ownerId = file.ownerId
      ..groupId = file.groupId
      ..compress = file.compress;
    return ZipEncoder().encode(archive)!;
  }
  return bytes;
}

List<int> buildTeachersWorkbook(
  List<TeacherWorkbookRow> rows, {
  List<String> subjectNames = const [],
}) {
  final book = Excel.createExcel();
  book.rename(book.getDefaultSheet()!, '教师');
  final sheet = book['教师'];
  sheet.appendRow([
    for (final title in ['教师', '简称', '分组', '任课科目']) TextCellValue(title),
  ]);
  for (final row in rows) {
    sheet.appendRow([
      TextCellValue(row.name.trim()),
      TextCellValue(row.shortName.trim()),
      TextCellValue(row.groups.join(',')),
      TextCellValue(row.subjects.join(',')),
    ]);
  }
  for (var index = 0; index < 4; index++) {
    sheet.setColumnWidth(index, index < 2 ? 20 : 36);
  }
  final instructions = book['填写说明'];
  for (final line in [
    ['教师导入填写说明'],
    ['教师', '填写教师姓名，简称可留空；同名教师导入时需要确认身份。'],
    ['分组', '多个分组用英文逗号分隔；已有分组添加成员，未存在的分组会新建。'],
    ['任课科目', '填写科目全称，多个科目用英文逗号分隔，名称参照“科目数据源”。'],
    ['导入规则', '可选择新增、更新或新增及更新，并设置空白是否清除；不会自动分配班级或课时。'],
  ]) {
    instructions.appendRow(line.map(TextCellValue.new).toList());
  }
  instructions.setColumnWidth(0, 18);
  instructions.setColumnWidth(1, 95);
  final source = book['科目数据源'];
  source.appendRow([TextCellValue('科目')]);
  for (final name in subjectNames) {
    source.appendRow([TextCellValue(name)]);
  }
  source.setColumnWidth(0, 30);
  return book.encode()!;
}

String _text(CellValue? value) => value?.toString().trim() ?? '';
