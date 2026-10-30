import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/subject_workbook.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const stages = [SchoolStage(id: 's', termId: 't', name: '小学部', sortOrder: 0)];
  const grades = [GradeGroup(id: 'g', stageId: 's', name: '一年级', sortOrder: 0)];
  const classes = [
    ClassBrief(stageId: 's', gradeId: 'g', id: 'c1', name: '1班'),
    ClassBrief(stageId: 's', gradeId: 'g', id: 'c2', name: '2班'),
  ];
  const subjects = [Subject(id: 'a', name: '语文', shortName: '语', sortOrder: 0)];
  SubjectWorkbookPlan parse(List<int> bytes, {bool alternating = true}) =>
      parseSubjectWorkbook(
        bytes,
        stages: stages,
        grades: grades,
        classes: classes,
        subjects: subjects,
        alternating: alternating,
      );
  List<int> file(List<CellValue?> counts) {
    final book = Excel.createExcel();
    book.rename(book.getDefaultSheet()!, '科目节数');
    final sheet = book['科目节数'];
    sheet.appendRow([
      for (final title in ['学段', '年级', '科目', '节数']) TextCellValue(title),
    ]);
    for (final value in counts) {
      sheet.appendRow([
        TextCellValue('小学部'),
        TextCellValue('一年级'),
        TextCellValue('语文'),
        value,
      ]);
    }
    return book.encode()!;
  }

  test('现有数据模板按年级汇总，按班顺序和单双周完整往返', () {
    final values = {
      ('c1', 'a'): const ClassSubjectValues(weekly: 2, odd: 1, even: 3),
      ('c2', 'a'): const ClassSubjectValues(),
    };
    final bytes = buildSubjectWorkbook(
      stages: stages,
      grades: grades,
      classes: classes,
      subjects: subjects,
      values: values,
      includeExisting: true,
    );
    final sheet = Excel.decodeBytes(bytes)['科目节数'];
    expect(sheet.rows.length, 2);
    expect(sheet.rows.first.map((cell) => cell?.value.toString()).toList(), [
      '学段',
      '年级',
      '科目',
      '节数',
    ]);
    expect(sheet.rows[1][3]?.value.toString(), '2|1|3,0');
    final result = parse(bytes);
    expect(result.errors, isEmpty);
    expect(result.values, values);
    final blank = buildSubjectWorkbook(
      stages: stages,
      grades: grades,
      classes: classes,
      subjects: subjects,
      values: values,
      includeExisting: false,
    );
    expect(Excel.decodeBytes(blank)['科目节数'].rows.length, 1);
  });
  test('单个数字应用整个年级，逗号和竖线对应各班周别', () {
    expect(parse(file([IntCellValue(2)])).values, {
      ('c1', 'a'): const ClassSubjectValues(weekly: 2),
      ('c2', 'a'): const ClassSubjectValues(weekly: 2),
    });
    expect(parse(file([TextCellValue('0|1|2,3|2|1')])).values, {
      ('c1', 'a'): const ClassSubjectValues(odd: 1, even: 2),
      ('c2', 'a'): const ClassSubjectValues(weekly: 3, odd: 2, even: 1),
    });
  });
  test('拒绝重复、数量不匹配、非法格式和未启用单双周', () {
    expect(parse(file([IntCellValue(1), IntCellValue(1)])).errors, isNotEmpty);
    expect(parse(file([TextCellValue('1,2,3')])).errors, isNotEmpty);
    expect(parse(file([TextCellValue('1|2')])).errors, isNotEmpty);
    expect(parse(file([TextCellValue('-1')])).errors, isNotEmpty);
    expect(
      parse(file([TextCellValue('0|1|0')]), alternating: false).errors,
      isNotEmpty,
    );
    expect(parse([0, 1, 2]).errors, isNotEmpty);
  });
}
