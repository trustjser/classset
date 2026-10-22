import 'package:excel/excel.dart';

class TeacherWorkbookError {
  const TeacherWorkbookError(this.rowNumber, this.message);

  final int rowNumber;
  final String message;

  @override
  String toString() => '第 $rowNumber 行：$message';
}

class TeacherWorkbookRow {
  const TeacherWorkbookRow({required this.name, this.shortName = ''});

  final String name;
  final String shortName;
}

class TeacherWorkbookResult {
  const TeacherWorkbookResult({this.rows = const [], this.errors = const []});

  final List<TeacherWorkbookRow> rows;
  final List<TeacherWorkbookError> errors;
}

TeacherWorkbookResult parseTeachersWorkbook(List<int> bytes) {
  try {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty || book.tables.values.first.rows.isEmpty) {
      return const TeacherWorkbookResult(
        errors: [TeacherWorkbookError(1, '工作表为空，请使用列：教师、简称')],
      );
    }
    final rows = book.tables.values.first.rows;
    final headers = rows.first.map((cell) => _text(cell?.value)).toList();
    const required = ['教师', '简称'];
    if (required.any(
          (header) => headers.where((h) => h == header).length != 1,
        ) ||
        headers.length != required.length) {
      return const TeacherWorkbookResult(
        errors: [TeacherWorkbookError(1, '表格只能包含「教师」「简称」两列')],
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
          column < cells.length ? cells[column]?.value : null;
      final name = _text(at(nameColumn));
      final shortName = _text(at(shortColumn));
      if (name.isEmpty) {
        errors.add(TeacherWorkbookError(index + 1, '教师姓名不能为空'));
      } else {
        parsed.add(TeacherWorkbookRow(name: name, shortName: shortName));
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

List<int> buildTeachersWorkbook(List<TeacherWorkbookRow> rows) {
  final book = Excel.createExcel();
  final sheet = book[book.getDefaultSheet()!];
  sheet.appendRow([TextCellValue('教师'), TextCellValue('简称')]);
  for (final row in rows) {
    sheet.appendRow([
      TextCellValue(row.name.trim()),
      TextCellValue(row.shortName.trim()),
    ]);
  }
  return book.encode()!;
}

String _text(CellValue? value) => value?.toString().trim() ?? '';
