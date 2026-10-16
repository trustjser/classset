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
