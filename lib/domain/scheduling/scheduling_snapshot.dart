import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/combined_lesson_group.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_lesson_constraint.dart';
import 'package:class_set/domain/models/subject_parallel_limit.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/domain/models/teacher_preset.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot_codec.dart';

/// 仓库一次一致性读取交给纯 Dart 求解器的完整输入。
///
/// [inputFingerprint] 应由仓库对已提交版本计算，并在提交前重新核对。
class SchedulingSnapshot {
  const SchedulingSnapshot({
    required this.term,
    required this.inputFingerprint,
    this.stages = const [],
    this.grades = const [],
    this.classes = const [],
    this.routines = const [],
    this.subjects = const [],
    this.requirements = const [],
    this.teachers = const [],
    this.assignments = const [],
    this.freeSlots = const [],
    this.subjectPresets = const [],
    this.teacherPresets = const [],
    this.teacherGroupPresets = const [],
    this.teacherGroupMembers = const [],
    this.conditions = const [],
    this.preferences = const SchedulePreferences(),
    this.locks = const [],
    this.existingItems = const [],
    this.rooms = const [],
    this.roomAssignments = const [],
    this.parallelLimits = const [],
    this.combinedGroups = const [],
    this.pairings = const [],
    this.lessonConstraints = const [],
    this.allowedPeriodTypeIdsBySubject = const {},
    this.requiredConsecutivePairsByRequirement = const {},
  });

  final AcademicTerm term;
  final String inputFingerprint;
  final List<SchoolStage> stages;
  final List<GradeGroup> grades;
  final List<ClassGroup> classes;
  final List<StageRoutine> routines;
  final List<Subject> subjects;
  final List<SubjectRequirement> requirements;
  final List<Teacher> teachers;
  final List<TeacherAssignment> assignments;
  final List<FreeSlot> freeSlots;
  final List<SubjectPreset> subjectPresets;
  final List<TeacherPreset> teacherPresets;
  final List<TeacherGroupPreset> teacherGroupPresets;
  final List<TeacherGroupMember> teacherGroupMembers;
  final List<ScheduleCondition> conditions;
  final SchedulePreferences preferences;
  final List<ScheduleLock> locks;
  final List<ScheduleItem> existingItems;
  final List<PublicRoom> rooms;
  final List<SubjectRoomAssignment> roomAssignments;
  final List<SubjectParallelLimit> parallelLimits;
  final List<CombinedLessonGroup> combinedGroups;
  final List<SubjectPairing> pairings;
  final List<SubjectLessonConstraint> lessonConstraints;
  final Map<String, Set<String>> allowedPeriodTypeIdsBySubject;
  final Map<String, int> requiredConsecutivePairsByRequirement;

  SchedulingSnapshot copyWith({
    List<ScheduleItem>? existingItems,
    List<ScheduleLock>? locks,
    List<TeacherAssignment>? assignments,
    List<ScheduleCondition>? conditions,
    SchedulePreferences? preferences,
  }) => SchedulingSnapshot(
    term: term,
    inputFingerprint: inputFingerprint,
    stages: stages,
    grades: grades,
    classes: classes,
    routines: routines,
    subjects: subjects,
    requirements: requirements,
    teachers: teachers,
    assignments: assignments ?? this.assignments,
    freeSlots: freeSlots,
    subjectPresets: subjectPresets,
    teacherPresets: teacherPresets,
    teacherGroupPresets: teacherGroupPresets,
    teacherGroupMembers: teacherGroupMembers,
    conditions: conditions ?? this.conditions,
    preferences: preferences ?? this.preferences,
    locks: locks ?? this.locks,
    existingItems: existingItems ?? this.existingItems,
    rooms: rooms,
    roomAssignments: roomAssignments,
    parallelLimits: parallelLimits,
    combinedGroups: combinedGroups,
    pairings: pairings,
    lessonConstraints: lessonConstraints,
    allowedPeriodTypeIdsBySubject: allowedPeriodTypeIdsBySubject,
    requiredConsecutivePairsByRequirement:
        requiredConsecutivePairsByRequirement,
  );

  String? gradeIdForClass(String classId) {
    for (final schoolClass in classes) {
      if (schoolClass.id == classId) return schoolClass.gradeId;
    }
    return null;
  }

  String? stageIdForClass(String classId) {
    final gradeId = gradeIdForClass(classId);
    for (final grade in grades) {
      if (grade.id == gradeId) return grade.stageId;
    }
    return null;
  }

  Map<String, Object?> toJson() => schedulingSnapshotToJson(this);

  factory SchedulingSnapshot.fromJson(Map<String, Object?> json) =>
      schedulingSnapshotFromJson(json);
}
