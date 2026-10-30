import 'dart:convert';

import 'package:archive/archive.dart';
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

List<int> _withBuiltinNumberFormatDeclaration(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  for (var index = 0; index < archive.length; index++) {
    final file = archive[index];
    if (file.name != 'xl/styles.xml') continue;
    final styles = utf8.decode(file.content as List<int>);
    const declaration = '<numFmt numFmtId="42" formatCode="#,##0"/>';
    final normalized = styles.contains('<numFmts')
        ? styles.replaceFirstMapped(RegExp(r'<numFmts[^>]*>'), (match) {
            final openingTag = match.group(0)!;
            return '$openingTag$declaration';
          })
        : styles.replaceFirst(
            '<fonts',
            '<numFmts count="1">$declaration</numFmts><fonts',
          );
    final content = utf8.encode(normalized);
    archive[index] = ArchiveFile(file.name, content.length, content);
  }
  return ZipEncoder().encode(archive)!;
}

void main() {
  test('教师模板支持分组和科目并提供说明与科目数据源', () {
    final bytes = buildTeachersWorkbook(
      [
        const TeacherWorkbookRow(
          name: '王老师',
          shortName: '王',
          groups: ['语文组', '年级组'],
          subjects: ['语文', '数学'],
        ),
      ],
      subjectNames: ['语文', '数学'],
    );
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, containsAll(['教师', '填写说明', '科目数据源']));
    final row = parseTeachersWorkbook(bytes).rows.single;
    expect(row.groups, ['语文组', '年级组']);
    expect(row.subjects, ['语文', '数学']);
    expect(
      book['科目数据源'].rows.map((row) => row.first?.value.toString()),
      containsAll(['语文', '数学']),
    );
  });

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

  test('parses files that redeclare a built-in number format', () {
    final result = parseTeachersWorkbook(
      _withBuiltinNumberFormatDeclaration(
        _workbook([
          [TextCellValue('教师'), TextCellValue('简称')],
          [TextCellValue('王老师'), TextCellValue('王')],
        ]),
      ),
    );

    expect(result.errors, isEmpty);
    expect(result.rows.single.name, '王老师');
    expect(result.rows.single.shortName, '王');
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
      '分组',
      '任课科目',
    ]);
    expect(rows[1][0]?.value.toString(), '王老师');
    expect(rows[1][1]?.value.toString(), '王');
  });
}
