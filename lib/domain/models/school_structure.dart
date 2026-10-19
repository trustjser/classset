class SchoolStage {
  const SchoolStage({
    required this.id,
    required this.termId,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String termId;
  final String name;
  final int sortOrder;
}

class GradeGroup {
  const GradeGroup({
    required this.id,
    required this.stageId,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String stageId;
  final String name;
  final int sortOrder;
}

class ClassGroup {
  const ClassGroup({
    required this.id,
    required this.gradeId,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String gradeId;
  final String name;
  final int sortOrder;
}

/// 班级简要信息：科目节数矩阵按「学段 → 年级 → 班级」层级展示用。
class ClassBrief {
  const ClassBrief({
    required this.stageId,
    required this.gradeId,
    required this.id,
    required this.name,
  });

  final String stageId;
  final String gradeId;
  final String id;
  final String name;
}

/// 单个学段的结构统计：年级数与作息是否已配置（有上课日且至少一个时段）。
class StageStructureStat {
  const StageStructureStat({
    required this.stageId,
    required this.gradeCount,
    required this.hasTeachingDays,
    required this.hasPeriods,
  });

  final String stageId;
  final int gradeCount;
  final bool hasTeachingDays;
  final bool hasPeriods;

  bool get hasRoutine => hasTeachingDays && hasPeriods;
}
