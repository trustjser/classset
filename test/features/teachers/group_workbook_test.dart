import 'package:class_set/features/teachers/io/group_workbook.dart';
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
  test('parses group members split by common separators', () {
    final result = parseTeacherGroupsWorkbook(
      _workbook([
        [TextCellValue('分组'), TextCellValue('说明'), TextCellValue('成员')],
        [
          TextCellValue('备课组'),
          TextCellValue('跨学段'),
          TextCellValue('王老师、李老师, 张老师'),
        ],
      ]),
    );
    expect(result.errors, isEmpty);
    expect(result.rows.single.name, '备课组');
    expect(result.rows.single.description, '跨学段');
    expect(result.rows.single.memberNames, ['王老师', '李老师', '张老师']);
  });

  test('rejects blank and duplicate group names but allows empty groups', () {
    final result = parseTeacherGroupsWorkbook(
      _workbook([
        [TextCellValue('分组'), TextCellValue('说明'), TextCellValue('成员')],
        [TextCellValue(''), TextCellValue(''), TextCellValue('')],
        [TextCellValue('语文组'), TextCellValue(''), TextCellValue('')],
        [TextCellValue('语文组'), TextCellValue('重复'), TextCellValue('王老师')],
      ]),
    );
    expect(result.rows, isEmpty);
    expect(result.errors.map((error) => error.rowNumber), contains(4));
  });

  test('exports a group workbook', () {
    final bytes = buildTeacherGroupsWorkbook([
      const TeacherGroupWorkbookRow(
        name: '备课组',
        description: '说明',
        memberNames: ['王老师', '李老师'],
      ),
    ]);
    final rows = Excel.decodeBytes(bytes).tables.values.first.rows;
    expect(rows[1][0]?.value.toString(), '备课组');
    expect(rows[1][2]?.value.toString(), '王老师、李老师');
  });
}
