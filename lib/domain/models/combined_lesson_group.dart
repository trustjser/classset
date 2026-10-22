import 'package:class_set/domain/models/subject.dart';

/// 同一教师、科目和周模式下跨班合并排课的组。
class CombinedLessonGroup {
  const CombinedLessonGroup({
    required this.id,
    required this.termId,
    required this.teacherId,
    required this.subjectId,
    required this.weekMode,
    required this.classIds,
  });

  final String id;
  final String termId;
  final String teacherId;
  final String subjectId;
  final WeekMode weekMode;
  final List<String> classIds;

  bool containsClass(String classId) => classIds.contains(classId);
}

/// 合并课候选项的时段完全相同才允许合并；部分重叠也必须拒绝。
bool canCombineLessons({
  required String teacherId,
  required String subjectId,
  required WeekMode weekMode,
  required String otherTeacherId,
  required String otherSubjectId,
  required WeekMode otherWeekMode,
  required int startLesson,
  required int endLesson,
  required int otherStartLesson,
  required int otherEndLesson,
}) {
  return teacherId == otherTeacherId &&
      subjectId == otherSubjectId &&
      weekMode == otherWeekMode &&
      startLesson == otherStartLesson &&
      endLesson == otherEndLesson;
}
