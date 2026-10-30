import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/features/teachers/io/teacher_workbook.dart';

enum TeacherImportMode { create, update, upsert }

enum TeacherImportStatus { create, update, skip, error }

class TeacherImportEntry {
  const TeacherImportEntry({
    required this.row,
    required this.status,
    required this.message,
    this.teacher,
    this.subjectIds = const {},
  });
  final TeacherWorkbookRow row;
  final TeacherImportStatus status;
  final String message;
  final Teacher? teacher;
  final Set<String> subjectIds;
}

List<TeacherImportEntry> planTeacherImport({
  required List<TeacherWorkbookRow> rows,
  required List<Teacher> teachers,
  required List<Subject> subjects,
  required List<TeacherGroup> groups,
  required TeacherImportMode mode,
}) {
  final names = <String, int>{};
  for (final row in rows) {
    final name = row.name.trim().toLowerCase();
    names[name] = (names[name] ?? 0) + 1;
  }
  return [
    for (final row in rows)
      () {
        final name = row.name.trim().toLowerCase();
        final candidates = teachers
            .where((teacher) => teacher.name.trim().toLowerCase() == name)
            .toList();
        TeacherImportEntry result(
          TeacherImportStatus status,
          String message, {
          Teacher? teacher,
          Set<String> ids = const {},
        }) => TeacherImportEntry(
          row: row,
          status: status,
          message: message,
          teacher: teacher,
          subjectIds: ids,
        );
        if (names[name]! > 1) {
          return result(TeacherImportStatus.error, '文件中教师姓名重复，请分别处理');
        }
        if (mode == TeacherImportMode.create && candidates.isNotEmpty) {
          return result(TeacherImportStatus.skip, '系统中已存在同名教师，新增模式跳过');
        }
        if (mode == TeacherImportMode.update && candidates.isEmpty) {
          return result(TeacherImportStatus.skip, '系统中没有同名教师，更新模式跳过');
        }
        if (candidates.length > 1) {
          return result(TeacherImportStatus.error, '存在多位同名教师，无法确定更新对象');
        }
        final subjectIds = <String>{};
        for (final name in row.subjects) {
          final matches = subjects
              .where((subject) => subject.name.trim() == name)
              .toList();
          if (matches.length != 1) {
            return result(
              TeacherImportStatus.error,
              '科目“$name”${matches.isEmpty ? '不存在' : '名称重复'}',
            );
          }
          subjectIds.add(matches.single.id);
        }
        for (final name in row.groups) {
          if (groups.where((group) => group.name.trim() == name).length > 1) {
            return result(TeacherImportStatus.error, '分组“$name”名称重复');
          }
        }
        return candidates.isEmpty
            ? result(TeacherImportStatus.create, '新增教师', ids: subjectIds)
            : result(
                TeacherImportStatus.update,
                '更新教师',
                teacher: candidates.single,
                ids: subjectIds,
              );
      }(),
  ];
}
