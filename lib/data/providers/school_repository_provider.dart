import 'package:class_set/data/providers/database_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_lesson_constraint.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/subject_parallel_limit.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/domain/models/teacher_preset.dart';

final schoolRepositoryProvider = Provider<SchoolRepository>(
  (ref) => DriftSchoolRepository(
    ref.watch(appDatabaseProvider),
    databasePath: ref.watch(databasePathProvider),
  ),
);

final termsProvider = StreamProvider<List<AcademicTerm>>(
  (ref) => ref.watch(schoolRepositoryProvider).watchTerms(),
);

final schoolNameProvider = StreamProvider<String>(
  (ref) => ref.watch(schoolRepositoryProvider).watchSchoolName(),
);

final schoolDisplayNameProvider = Provider<String>((ref) {
  final name = ref.watch(schoolNameProvider).valueOrNull?.trim() ?? '';
  return name.isEmpty ? '未命名学校' : name;
});

final stagesProvider = StreamProvider.family<List<SchoolStage>, String>(
  (ref, termId) => ref.watch(schoolRepositoryProvider).watchStages(termId),
);

final gradesProvider = StreamProvider.family<List<GradeGroup>, String>(
  (ref, stageId) => ref.watch(schoolRepositoryProvider).watchGrades(stageId),
);

final classesProvider = StreamProvider.family<List<ClassGroup>, String>(
  (ref, gradeId) => ref.watch(schoolRepositoryProvider).watchClasses(gradeId),
);

final routineProvider = StreamProvider.family<StageRoutine?, String>(
  (ref, stageId) => ref.watch(schoolRepositoryProvider).watchRoutine(stageId),
);

final calendarExceptionsProvider =
    StreamProvider.family<List<CalendarException>, String>(
      (ref, termId) =>
          ref.watch(schoolRepositoryProvider).watchCalendarExceptions(termId),
    );

final freeSlotsProvider = StreamProvider.family<List<FreeSlot>, String>(
  (ref, stageId) => ref.watch(schoolRepositoryProvider).watchFreeSlots(stageId),
);

final commonPeriodsProvider = StreamProvider.family<List<CommonPeriod>, String>(
  (ref, stageId) =>
      ref.watch(schoolRepositoryProvider).watchCommonPeriods(stageId),
);

final subjectsProvider = StreamProvider<List<Subject>>(
  (ref) => ref.watch(schoolRepositoryProvider).watchSubjects(),
);

final subjectsForTermProvider = StreamProvider.family<List<Subject>, String>(
  (ref, termId) =>
      ref.watch(schoolRepositoryProvider).watchSubjectsForTerm(termId),
);

/// 某年级的科目节数需求流（年级默认 + 按班覆盖）。
final gradeRequirementsProvider =
    StreamProvider.family<List<SubjectRequirement>, String>(
      (ref, gradeId) => ref
          .watch(schoolRepositoryProvider)
          .watchRequirementsForGrade(gradeId),
    );

/// 全校科目节数需求流（客户端按学段/年级过滤）。
final allRequirementsProvider = StreamProvider<List<SubjectRequirement>>(
  (ref) => ref.watch(schoolRepositoryProvider).watchAllRequirements(),
);

/// 某学段下班级简要信息流（按年级/班级顺序）。
final stageClassesProvider = StreamProvider.family<List<ClassBrief>, String>(
  (ref, stageId) =>
      ref.watch(schoolRepositoryProvider).watchClassesForStage(stageId),
);

/// 某科目的预设行流（按范围 / 学段客户端过滤）。
final subjectPresetsProvider =
    StreamProvider.family<List<SubjectPreset>, String>(
      (ref, subjectId) =>
          ref.watch(schoolRepositoryProvider).watchPresetsForSubject(subjectId),
    );

/// 全校预设行流（客户端按范围 / 学段过滤）。
final allPresetsProvider = StreamProvider<List<SubjectPreset>>(
  (ref) => ref.watch(schoolRepositoryProvider).watchAllPresets(),
);

/// 某科目的单日课节与每周连堂限制。
final subjectLessonConstraintsProvider =
    StreamProvider.family<List<SubjectLessonConstraint>, String>(
      (ref, subjectId) => ref
          .watch(schoolRepositoryProvider)
          .watchLessonConstraintsForSubject(subjectId),
    );

/// 全部科目的单日课节与每周连堂限制。
final allSubjectLessonConstraintsProvider =
    StreamProvider<List<SubjectLessonConstraint>>(
      (ref) => ref.watch(schoolRepositoryProvider).watchAllLessonConstraints(),
    );

/// 全校课程配对流（按班级客户端过滤）。
final allPairingsProvider = StreamProvider<List<SubjectPairing>>(
  (ref) => ref.watch(schoolRepositoryProvider).watchAllPairings(),
);

/// 某学期全部年级流（按学段顺序）。
final gradesForTermProvider = StreamProvider.family<List<GradeGroup>, String>(
  (ref, termId) =>
      ref.watch(schoolRepositoryProvider).watchGradesForTerm(termId),
);

/// 某学期全部班级简要信息流。
final classesForTermProvider = StreamProvider.family<List<ClassBrief>, String>(
  (ref, termId) =>
      ref.watch(schoolRepositoryProvider).watchClassesForTerm(termId),
);

/// 某学期各学段作息流（stageId → 作息）。
final routinesForTermProvider =
    StreamProvider.family<Map<String, StageRoutine>, String>(
      (ref, termId) =>
          ref.watch(schoolRepositoryProvider).watchRoutinesForTerm(termId),
    );

/// 某学期全部免任课格流。
final freeSlotsForTermProvider = StreamProvider.family<List<FreeSlot>, String>(
  (ref, termId) =>
      ref.watch(schoolRepositoryProvider).watchFreeSlotsForTerm(termId),
);

final publicRoomsProvider = StreamProvider<List<PublicRoom>>(
  (ref) => ref.watch(schoolRepositoryProvider).watchPublicRooms(),
);
final subjectRoomAssignmentsProvider =
    StreamProvider.family<List<SubjectRoomAssignment>, String>(
      (ref, termId) => ref
          .watch(schoolRepositoryProvider)
          .watchSubjectRoomAssignments(termId),
    );
final subjectParallelLimitsProvider =
    StreamProvider.family<List<SubjectParallelLimit>, String>(
      (ref, termId) => ref
          .watch(schoolRepositoryProvider)
          .watchSubjectParallelLimits(termId),
    );
final roomReferencesProvider =
    StreamProvider.family<List<SubjectRoomAssignment>, String>(
      (ref, roomId) =>
          ref.watch(schoolRepositoryProvider).watchRoomReferences(roomId),
    );

final teachersProvider = StreamProvider.family<List<Teacher>, String>(
  (ref, termId) => ref.watch(schoolRepositoryProvider).watchTeachers(termId),
);

final teacherAssignmentsProvider =
    StreamProvider.family<List<TeacherAssignment>, String>(
      (ref, termId) =>
          ref.watch(schoolRepositoryProvider).watchTeacherAssignments(termId),
    );

final teacherGroupsProvider = StreamProvider.family<List<TeacherGroup>, String>(
  (ref, termId) =>
      ref.watch(schoolRepositoryProvider).watchTeacherGroups(termId),
);

final teacherGroupMembersProvider =
    StreamProvider.family<List<TeacherGroupMember>, String>(
      (ref, termId) =>
          ref.watch(schoolRepositoryProvider).watchTeacherGroupMembers(termId),
    );

final teacherPresetsProvider =
    StreamProvider.family<List<TeacherPreset>, String>(
      (ref, termId) =>
          ref.watch(schoolRepositoryProvider).watchTeacherPresets(termId),
    );

final teacherGroupPresetsProvider =
    StreamProvider.family<List<TeacherGroupPreset>, String>(
      (ref, termId) =>
          ref.watch(schoolRepositoryProvider).watchTeacherGroupPresets(termId),
    );
