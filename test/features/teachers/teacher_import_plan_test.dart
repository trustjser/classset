import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/teachers/io/teacher_import_plan.dart';
import 'package:class_set/features/teachers/io/teacher_workbook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const teachers = [
    Teacher(id: 'a', name: '张老师', shortName: '张', sortOrder: 0),
  ];
  const subjects = [Subject(id: 's', name: '语文', shortName: '语', sortOrder: 0)];
  const rows = [
    TeacherWorkbookRow(name: '张老师', subjects: ['语文'], rowNumber: 2),
    TeacherWorkbookRow(name: '李老师', rowNumber: 3),
  ];
  test('三种导入方式分别计算新增、更新和跳过', () {
    List<TeacherImportStatus> statuses(TeacherImportMode mode) =>
        planTeacherImport(
          rows: rows,
          teachers: teachers,
          subjects: subjects,
          groups: [],
          mode: mode,
        ).map((entry) => entry.status).toList();
    expect(statuses(TeacherImportMode.create), [
      TeacherImportStatus.skip,
      TeacherImportStatus.create,
    ]);
    expect(statuses(TeacherImportMode.update), [
      TeacherImportStatus.update,
      TeacherImportStatus.skip,
    ]);
    expect(statuses(TeacherImportMode.upsert), [
      TeacherImportStatus.update,
      TeacherImportStatus.create,
    ]);
  });
  test('同名和未知科目不得被当作可导入', () {
    const duplicate = [
      Teacher(id: 'a', name: '张老师', shortName: '', sortOrder: 0),
      Teacher(id: 'b', name: '张老师', shortName: '', sortOrder: 1),
    ];
    expect(
      planTeacherImport(
        rows: rows,
        teachers: duplicate,
        subjects: subjects,
        groups: [],
        mode: TeacherImportMode.update,
      ).first.status,
      TeacherImportStatus.error,
    );
    expect(
      planTeacherImport(
        rows: [
          const TeacherWorkbookRow(name: '甲', subjects: ['不存在']),
        ],
        teachers: teachers,
        subjects: subjects,
        groups: [],
        mode: TeacherImportMode.create,
      ).single.status,
      TeacherImportStatus.error,
    );
  });
}
