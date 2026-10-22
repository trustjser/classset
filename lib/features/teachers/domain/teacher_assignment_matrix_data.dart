import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';

typedef TeacherAssignmentMatrixCellKey = ({String classId, String subjectId});

class TeacherAssignmentMatrixCourse {
  const TeacherAssignmentMatrixCourse({
    required this.classId,
    required this.className,
    required this.subjectId,
    required this.subjectName,
    required this.weekMode,
    required this.remainingLessons,
    this.existingAssignmentId,
  });

  final String classId;
  final String className;
  final String subjectId;
  final String subjectName;
  final WeekMode weekMode;
  final int remainingLessons;
  final String? existingAssignmentId;
}

class TeacherAssignmentMatrixCell {
  const TeacherAssignmentMatrixCell({
    required this.assignments,
    required this.requirements,
    required this.remainingCourses,
  });

  static const empty = TeacherAssignmentMatrixCell(
    assignments: [],
    requirements: [],
    remainingCourses: [],
  );

  final List<TeacherAssignment> assignments;
  final List<SubjectRequirement> requirements;
  final List<TeacherAssignmentMatrixCourse> remainingCourses;
}

class TeacherAssignmentMatrixData {
  const TeacherAssignmentMatrixData._({
    required this.cells,
    required this.unassignedCourses,
  });

  factory TeacherAssignmentMatrixData.build({
    required List<ClassBrief> classes,
    required List<Subject> subjects,
    required List<SubjectRequirement> requirements,
    required List<TeacherAssignment> assignments,
  }) {
    final assignmentsByCell =
        <TeacherAssignmentMatrixCellKey, List<TeacherAssignment>>{};
    for (final assignment in assignments) {
      // Unassigned lesson counts are represented by the remaining demand
      // below. Keeping legacy empty-teacher rows here would show the same
      // course both as a stored assignment and as remaining demand.
      if (assignment.teacherId.isEmpty) continue;
      assignmentsByCell
          .putIfAbsent((
            classId: assignment.classId,
            subjectId: assignment.subjectId,
          ), () => [])
          .add(assignment);
    }

    final classRequirements =
        <TeacherAssignmentMatrixCellKey, List<SubjectRequirement>>{};
    final gradeRequirements =
        <(String gradeId, String subjectId), List<SubjectRequirement>>{};
    for (final requirement in requirements) {
      final classId = requirement.classId;
      if (classId != null) {
        classRequirements
            .putIfAbsent((
              classId: classId,
              subjectId: requirement.subjectId,
            ), () => [])
            .add(requirement);
      } else {
        gradeRequirements
            .putIfAbsent((requirement.gradeId, requirement.subjectId), () => [])
            .add(requirement);
      }
    }

    final cells =
        <TeacherAssignmentMatrixCellKey, TeacherAssignmentMatrixCell>{};
    final unassignedCourses = <TeacherAssignmentMatrixCourse>[];
    for (final classBrief in classes) {
      for (final subject in subjects) {
        final key = (classId: classBrief.id, subjectId: subject.id);
        final cellAssignments = assignmentsByCell[key] ?? const [];
        final scopedRequirements = classRequirements[key];
        final cellRequirements = scopedRequirements?.isNotEmpty == true
            ? scopedRequirements!
            : gradeRequirements[(classBrief.gradeId, subject.id)] ?? const [];
        final assignedByMode = <WeekMode, int>{};
        for (final assignment in cellAssignments) {
          assignedByMode.update(
            assignment.weekMode,
            (total) => total + assignment.lessonCount,
            ifAbsent: () => assignment.lessonCount,
          );
        }

        final remainingCourses = <TeacherAssignmentMatrixCourse>[];
        for (final requirement in cellRequirements) {
          final remaining =
              requirement.lessonCount -
              (assignedByMode[requirement.weekMode] ?? 0);
          if (remaining <= 0) continue;
          final course = TeacherAssignmentMatrixCourse(
            classId: classBrief.id,
            className: classBrief.name,
            subjectId: subject.id,
            subjectName: subject.name,
            weekMode: requirement.weekMode,
            remainingLessons: remaining,
          );
          remainingCourses.add(course);
          unassignedCourses.add(course);
        }

        cells[key] = TeacherAssignmentMatrixCell(
          assignments: List.unmodifiable(cellAssignments),
          requirements: List.unmodifiable(cellRequirements),
          remainingCourses: List.unmodifiable(remainingCourses),
        );
      }
    }
    return TeacherAssignmentMatrixData._(
      cells: Map.unmodifiable(cells),
      unassignedCourses: List.unmodifiable(unassignedCourses),
    );
  }

  final Map<TeacherAssignmentMatrixCellKey, TeacherAssignmentMatrixCell> cells;
  final List<TeacherAssignmentMatrixCourse> unassignedCourses;

  TeacherAssignmentMatrixCell cellFor({
    required String classId,
    required String subjectId,
  }) =>
      cells[(classId: classId, subjectId: subjectId)] ??
      TeacherAssignmentMatrixCell.empty;
}
