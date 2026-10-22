import 'package:excel/excel.dart';

class TeacherGroupWorkbookError {
  const TeacherGroupWorkbookError(this.rowNumber, this.message);

  final int rowNumber;
  final String message;

  @override
  String toString() => '第 $rowNumber 行：$message';
}

class TeacherGroupWorkbookRow {
  const TeacherGroupWorkbookRow({
    required this.name,
    this.description = '',
    this.memberNames = const [],
  });

  final String name;
  final String description;
  final List<String> memberNames;
}

class TeacherGroupWorkbookResult {
  const TeacherGroupWorkbookResult({
    this.rows = const [],
    this.errors = const [],
  });

  final List<TeacherGroupWorkbookRow> rows;
  final List<TeacherGroupWorkbookError> errors;
}

TeacherGroupWorkbookResult parseTeacherGroupsWorkbook(List<int> bytes) {
  try {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty || book.tables.values.first.rows.isEmpty) {
      return const TeacherGroupWorkbookResult(
        errors: [TeacherGroupWorkbookError(1, '工作表为空，请使用列：分组、说明、成员')],
      );
    }
    final rows = book.tables.values.first.rows;
    final headers = rows.first.map((cell) => _text(cell?.value)).toList();
    const required = ['分组', '说明', '成员'];
    if (required.any(
      (header) => headers.where((h) => h == header).length != 1,
    )) {
      return const TeacherGroupWorkbookResult(
        errors: [TeacherGroupWorkbookError(1, '表头必须各包含一列：分组、说明、成员')],
      );
    }
    final nameColumn = headers.indexOf('分组');
    final descriptionColumn = headers.indexOf('说明');
    final membersColumn = headers.indexOf('成员');
    final errors = <TeacherGroupWorkbookError>[];
    final parsed = <TeacherGroupWorkbookRow>[];
    final names = <String>{};
    for (var index = 1; index < rows.length; index++) {
      final cells = rows[index];
      if (cells.every((cell) => _text(cell?.value).isEmpty)) continue;
      CellValue? at(int column) =>
          column < cells.length ? cells[column]?.value : null;
      final name = _text(at(nameColumn));
      final description = _text(at(descriptionColumn));
      final memberNames = _splitList(_text(at(membersColumn)));
      if (name.isEmpty) {
        errors.add(TeacherGroupWorkbookError(index + 1, '分组名称不能为空'));
      } else if (!names.add(name.toLowerCase())) {
        errors.add(TeacherGroupWorkbookError(index + 1, '分组名称“$name”重复'));
      } else {
        parsed.add(
          TeacherGroupWorkbookRow(
            name: name,
            description: description,
            memberNames: memberNames,
          ),
        );
      }
    }
    if (errors.isNotEmpty) return TeacherGroupWorkbookResult(errors: errors);
    if (parsed.isEmpty) {
      return const TeacherGroupWorkbookResult(
        errors: [TeacherGroupWorkbookError(2, '没有可导入的分组数据')],
      );
    }
    return TeacherGroupWorkbookResult(rows: parsed);
  } catch (_) {
    return const TeacherGroupWorkbookResult(
      errors: [TeacherGroupWorkbookError(1, '无法读取 Excel 文件，请选择有效的 .xlsx 文件')],
    );
  }
}

List<int> buildTeacherGroupsWorkbook(List<TeacherGroupWorkbookRow> rows) {
  final book = Excel.createExcel();
  final sheet = book[book.getDefaultSheet()!];
  sheet.appendRow([
    TextCellValue('分组'),
    TextCellValue('说明'),
    TextCellValue('成员'),
  ]);
  for (final row in rows) {
    sheet.appendRow([
      TextCellValue(row.name.trim()),
      TextCellValue(row.description.trim()),
      TextCellValue(
        row.memberNames
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .join('、'),
      ),
    ]);
  }
  return book.encode()!;
}

String _text(CellValue? value) => value?.toString().trim() ?? '';

List<String> _splitList(String value) => value
    .split(RegExp(r'[、,，;；\n]+'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toSet()
    .toList(growable: false);
