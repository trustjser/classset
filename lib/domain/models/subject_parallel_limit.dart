import 'package:class_set/domain/models/free_slot.dart';

class SubjectParallelLimit {
  const SubjectParallelLimit({
    required this.id,
    required this.subjectId,
    required this.termId,
    required this.stageId,
    required this.scope,
    required this.scopeId,
    required this.maxParallelLessons,
  });

  final String id;
  final String subjectId;
  final String termId;
  final String stageId;
  final FreeSlotScope scope;
  final String scopeId;
  final int maxParallelLessons;
}

SubjectParallelLimit? resolveSubjectParallelLimit({
  required Iterable<SubjectParallelLimit> limits,
  required String subjectId,
  required String termId,
  required String stageId,
  String? gradeId,
}) {
  SubjectParallelLimit? stage;
  for (final row in limits) {
    if (row.subjectId != subjectId ||
        row.termId != termId ||
        row.stageId != stageId) {
      continue;
    }
    if (row.scope == FreeSlotScope.grade && row.scopeId == gradeId) return row;
    if (row.scope == FreeSlotScope.stage && row.scopeId == stageId) stage = row;
  }
  return stage;
}
