import 'package:class_set/domain/models/free_slot.dart';

class SubjectRoomAssignment {
  const SubjectRoomAssignment({
    required this.id,
    required this.subjectId,
    required this.termId,
    required this.stageId,
    required this.scope,
    required this.scopeId,
    required this.roomId,
  });

  final String id;
  final String subjectId;
  final String termId;
  final String stageId;
  final FreeSlotScope scope;
  final String scopeId;
  // A present row with null roomId explicitly suppresses inherited rooms.
  final String? roomId;
}

SubjectRoomAssignment? resolveSubjectRoomAssignment({
  required Iterable<SubjectRoomAssignment> assignments,
  required String subjectId,
  required String termId,
  required String stageId,
  required FreeSlotScope scope,
  required String scopeId,
  String? parentGradeId,
}) {
  if (scope == FreeSlotScope.school) {
    throw ArgumentError('公共教室设置不支持全校范围');
  }
  final candidates = <({FreeSlotScope scope, String id})>[
    (scope: scope, id: scopeId),
    if (scope == FreeSlotScope.schoolClass && parentGradeId != null)
      (scope: FreeSlotScope.grade, id: parentGradeId),
    if (scope != FreeSlotScope.stage) (scope: FreeSlotScope.stage, id: stageId),
  ];
  for (final candidate in candidates) {
    for (final row in assignments) {
      if (row.subjectId == subjectId &&
          row.termId == termId &&
          row.stageId == stageId &&
          row.scope == candidate.scope &&
          row.scopeId == candidate.id) {
        return row;
      }
    }
  }
  return null;
}
