import 'package:class_set/domain/models/subject.dart';

/// 教师在一个班级的一门科目上的任课份额。
///
/// [lessonCount] 表示对应周模式中一个实际出现周的节数。拆分任课时，
/// 同一个班级、科目和周模式可以存多条记录，合计不得超过科目需求。
class TeacherAssignment {
  const TeacherAssignment({
    required this.id,
    required this.termId,
    required this.teacherId,
    required this.classId,
    required this.subjectId,
    required this.weekMode,
    required this.lessonCount,
    this.sortOrder = 0,
    this.combinedLessonGroupId,
  });

  final String id;
  final String termId;
  final String teacherId;
  final String classId;
  final String subjectId;
  final WeekMode weekMode;
  final int lessonCount;
  final int sortOrder;
  final String? combinedLessonGroupId;

  String get demandKey => '$classId:$subjectId:${weekMode.storageValue}';

  TeacherAssignment copyWith({
    String? teacherId,
    String? classId,
    String? subjectId,
    WeekMode? weekMode,
    int? lessonCount,
    int? sortOrder,
    String? combinedLessonGroupId,
    bool clearCombinedLessonGroupId = false,
  }) => TeacherAssignment(
    id: id,
    termId: termId,
    teacherId: teacherId ?? this.teacherId,
    classId: classId ?? this.classId,
    subjectId: subjectId ?? this.subjectId,
    weekMode: weekMode ?? this.weekMode,
    lessonCount: lessonCount ?? this.lessonCount,
    sortOrder: sortOrder ?? this.sortOrder,
    combinedLessonGroupId: clearCombinedLessonGroupId
        ? null
        : combinedLessonGroupId ?? this.combinedLessonGroupId,
  );
}

class TeacherAssignmentSummary {
  const TeacherAssignmentSummary({
    required this.weekly,
    required this.odd,
    required this.even,
  });

  final int weekly;
  final int odd;
  final int even;

  /// 双周总课时折算成每周平均课时。
  ///
  /// [odd] 与 [even] 已包含每周课，因此直接取两者平均值。
  double get biweeklyAverage => (odd + even) / 2;

  factory TeacherAssignmentSummary.from(
    Iterable<TeacherAssignment> assignments,
  ) {
    var weekly = 0;
    var odd = 0;
    var even = 0;
    final countedCombinedGroups = <String>{};
    for (final assignment in assignments) {
      final combinedGroupId = assignment.combinedLessonGroupId;
      if (combinedGroupId != null &&
          !countedCombinedGroups.add(combinedGroupId)) {
        continue;
      }
      switch (assignment.weekMode) {
        case WeekMode.weekly:
          weekly += assignment.lessonCount;
        case WeekMode.odd:
          odd += assignment.lessonCount;
        case WeekMode.even:
          even += assignment.lessonCount;
      }
    }
    return TeacherAssignmentSummary(
      weekly: weekly,
      odd: weekly + odd,
      even: weekly + even,
    );
  }
}
