import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('缺少任课的待处理项包含学段班级科目周别与缺口', () {
    final snapshot = SchedulingSnapshot(
      term: AcademicTerm(
        id: 't',
        title: '学期',
        academicYear: '2027',
        semesterLabel: '第一学期',
        firstTeachingWeekStart: null,
        teachingWeekCount: 20,
        createdAt: DateTime(2027),
      ),
      inputFingerprint: 'test',
      stages: const [
        SchoolStage(id: 'stage-id', termId: 't', name: '小学部', sortOrder: 0),
      ],
      grades: const [
        GradeGroup(
          id: 'grade-id',
          stageId: 'stage-id',
          name: '一年级',
          sortOrder: 0,
        ),
      ],
      classes: const [
        ClassGroup(
          id: 'class-internal',
          gradeId: 'grade-id',
          name: '1 班',
          sortOrder: 0,
        ),
      ],
      subjects: const [
        Subject(
          id: 'subject-internal',
          termId: 't',
          name: '体育与健康',
          shortName: '体育',
          sortOrder: 0,
        ),
      ],
      routines: const [
        StageRoutine(
          stageId: 'stage-id',
          teachingWeekdays: {1},
          periodTypes: [
            LessonPeriodType(
              id: 'p',
              name: '上午',
              defaultLessonCount: 4,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
          overrides: [],
        ),
      ],
      requirements: const [
        SubjectRequirement(
          id: 'r',
          subjectId: 'subject-internal',
          gradeId: 'grade-id',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
      ],
    );
    final problem = const ProblemBuilder().build(snapshot);
    final warning = problem.checks.singleWhere(
      (item) => item.code == 'assignment',
    );
    expect(warning.ready, isFalse);
    expect(warning.message, contains('小学部'));
    expect(warning.message, contains('一年级'));
    expect(warning.message, contains('1 班'));
    expect(warning.message, contains('体育与健康'));
    expect(warning.message, contains('每周'));
    expect(warning.message, contains('0/2'));
    expect(warning.message, isNot(contains('class-internal')));
  });
}
