import 'package:class_set/features/teachers/io/teacher_workbook.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _workbook(List<List<CellValue?>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  for (final row in rows) {
    sheet.appendRow(row);
  }
  return excel.encode()!;
}

void main() {
  test('parses teacher rows and trims cells', () {
    final result = parseTeachersWorkbook(
      _workbook([
        [TextCellValue('教师'), TextCellValue('简称')],
        [TextCellValue(' 王老师 '), TextCellValue(' 王 ')],
      ]),
    );
    expect(result.errors, isEmpty);
    expect(result.rows.single.name, '王老师');
    expect(result.rows.single.shortName, '王');
  });

  test('allows duplicate names when display qualifier differs', () {
    final result = parseTeachersWorkbook(
      _workbook([
        [TextCellValue('教师'), TextCellValue('简称')],
        [TextCellValue('王老师'), TextCellValue('王1')],
        [TextCellValue('王老师'), TextCellValue('王2')],
      ]),
    );
    expect(result.errors, isEmpty);
    expect(result.rows, hasLength(2));
  });

  test('reports row errors and rejects file atomically', () {
    final result = parseTeachersWorkbook(
      _workbook([
        [TextCellValue('教师'), TextCellValue('简称')],
        [TextCellValue(''), TextCellValue('王')],
        [TextCellValue('李老师'), TextCellValue('李')],
      ]),
    );
    expect(result.rows, isEmpty);
    expect(result.errors.map((error) => error.rowNumber), contains(2));
  });

  test('exports a workbook with teacher columns', () {
    final bytes = buildTeachersWorkbook([
      const TeacherWorkbookRow(name: '王老师', shortName: '王'),
    ]);
    final book = Excel.decodeBytes(bytes);
    final rows = book.tables.values.first.rows;
    expect(rows.first.map((cell) => cell?.value.toString()).toList(), [
      '教师',
      '简称',
    ]);
    expect(rows[1][0]?.value.toString(), '王老师');
    expect(rows[1][1]?.value.toString(), '王');
  });
}
