import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/features/teachers/domain/teacher_assignment_matrix_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'class override, assignment totals and unassigned demand are indexed',
    () {
      const classes = [
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-1',
          name: '一班',
        ),
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-2',
          name: '二班',
        ),
      ];
      const subjects = [
        Subject(id: 'math', name: '数学', shortName: '数', sortOrder: 0),
        Subject(id: 'music', name: '音乐', shortName: '音', sortOrder: 1),
      ];
      const requirements = [
        SubjectRequirement(
          id: 'math-grade',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
        SubjectRequirement(
          id: 'math-class',
          subjectId: 'math',
          gradeId: 'grade-1',
          classId: 'class-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ];
      const assignments = [
        TeacherAssignment(
          id: 'assigned',
          termId: 'term-1',
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
        TeacherAssignment(
          id: 'unassigned',
          termId: 'term-1',
          teacherId: '',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 1,
        ),
        TeacherAssignment(
          id: 'unassigned-2',
          termId: 'term-1',
          teacherId: '',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 1,
        ),
      ];

      final data = TeacherAssignmentMatrixData.build(
        classes: classes,
        subjects: subjects,
        requirements: requirements,
        assignments: assignments,
      );

      final overriddenCell = data.cellFor(
        classId: 'class-1',
        subjectId: 'math',
      );
      expect(overriddenCell.requirements.single.lessonCount, 4);
      expect(overriddenCell.assignments.map((row) => row.id), ['assigned']);
      expect(
        data
            .cellFor(classId: 'class-2', subjectId: 'math')
            .requirements
            .single
            .lessonCount,
        4,
      );
      expect(data.cells, hasLength(4));
      expect(data.unassignedCourses, hasLength(2));
      expect(
        data.unassignedCourses.map(
          (course) =>
              (course.classId, course.weekMode, course.remainingLessons),
        ),
        containsAll([
          ('class-1', WeekMode.weekly, 2),
          ('class-2', WeekMode.weekly, 4),
        ]),
      );
    },
  );

  test('large class matrix creates each class-subject cell once', () {
    final classes = [
      for (var index = 0; index < 120; index++)
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-${index % 12}',
          id: 'class-$index',
          name: '班级 $index',
        ),
    ];
    final subjects = [
      for (var index = 0; index < 18; index++)
        Subject(
          id: 'subject-$index',
          name: '科目 $index',
          shortName: '科$index',
          sortOrder: index,
        ),
    ];

    final data = TeacherAssignmentMatrixData.build(
      classes: classes,
      subjects: subjects,
      requirements: const [],
      assignments: const [],
    );

    expect(data.cells, hasLength(2160));
    expect(
      data.cellFor(classId: 'class-119', subjectId: 'subject-17').assignments,
      isEmpty,
    );
  });
}
