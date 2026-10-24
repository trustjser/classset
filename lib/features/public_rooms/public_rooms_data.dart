import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final publicRoomTermDataProvider =
    FutureProvider.family<PublicRoomTermData, String>((ref, termId) async {
      final stages = ref.watch(stagesProvider(termId).future);
      final grades = ref.watch(gradesForTermProvider(termId).future);
      final classes = ref.watch(classesForTermProvider(termId).future);
      final assignments = ref.watch(
        subjectRoomAssignmentsProvider(termId).future,
      );
      final subjects = ref.watch(subjectsForTermProvider(termId).future);
      return PublicRoomTermData(
        termId: termId,
        stages: await stages,
        grades: await grades,
        classes: await classes,
        assignments: await assignments,
        subjects: await subjects,
      );
    });

class PublicRoomTermData {
  PublicRoomTermData({
    required this.termId,
    required this.stages,
    required this.grades,
    required this.classes,
    required this.assignments,
    required this.subjects,
  });
  final String termId;
  final List<SchoolStage> stages;
  final List<GradeGroup> grades;
  final List<ClassBrief> classes;
  final List<SubjectRoomAssignment> assignments;
  final List<Subject> subjects;

  String bindingLabel(SubjectRoomAssignment row) {
    final stage = stages.where((s) => s.id == row.stageId).firstOrNull;
    final subject = subjects.where((s) => s.id == row.subjectId).firstOrNull;
    final parts = <String>[stage?.name ?? '已移除学段'];
    switch (row.scope) {
      case FreeSlotScope.stage:
        parts.add('全学段');
      case FreeSlotScope.grade:
        parts.add(
          grades.where((g) => g.id == row.scopeId).firstOrNull?.name ?? '已移除年级',
        );
      case FreeSlotScope.schoolClass:
        final schoolClass = classes
            .where((c) => c.id == row.scopeId)
            .firstOrNull;
        parts.add(
          grades.where((g) => g.id == schoolClass?.gradeId).firstOrNull?.name ??
              '已移除年级',
        );
        parts.add(schoolClass?.name ?? '已移除班级');
      case FreeSlotScope.school:
        parts.add('未知范围');
    }
    return '${subject?.name ?? '已移除科目'} · ${parts.join(' / ')}';
  }

  late final Set<String> _sharedRoomIds = _resolveSharedRooms();

  bool isSharedAcrossStages(String roomId) => _sharedRoomIds.contains(roomId);

  Set<String> _resolveSharedRooms() {
    final byStageAndSubject =
        <String, Map<String, List<SubjectRoomAssignment>>>{};
    for (final assignment in assignments) {
      byStageAndSubject
          .putIfAbsent(assignment.stageId, () => {})
          .putIfAbsent(assignment.subjectId, () => [])
          .add(assignment);
    }
    final usedStagesByRoom = <String, Set<String>>{};
    for (final schoolClass in classes) {
      final subjectRules = byStageAndSubject[schoolClass.stageId];
      if (subjectRules == null) continue;
      for (final entry in subjectRules.entries) {
        final effective = resolveSubjectRoomAssignment(
          assignments: entry.value,
          subjectId: entry.key,
          termId: termId,
          stageId: schoolClass.stageId,
          scope: FreeSlotScope.schoolClass,
          scopeId: schoolClass.id,
          parentGradeId: schoolClass.gradeId,
        );
        final roomId = effective?.roomId;
        if (roomId != null) {
          usedStagesByRoom
              .putIfAbsent(roomId, () => {})
              .add(schoolClass.stageId);
        }
      }
    }
    return usedStagesByRoom.entries
        .where((entry) => entry.value.length >= 2)
        .map((entry) => entry.key)
        .toSet();
  }
}
