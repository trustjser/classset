import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/supervision_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final label in [
    FreeSlotLabels.selfStudy,
    FreeSlotLabels.labor,
    FreeSlotLabels.teachingResearch,
    FreeSlotLabels.partyLeague,
    '课后服务',
    '早读',
  ]) {
    test('免任课「$label」支持带班且不触发智能排课修复', () {
      final snapshot = _snapshot(label);
      expect(
        const SupervisionValidation().postErrors(snapshot, _draft),
        isEmpty,
      );
      expect(
        const ProblemBuilder()
            .build(snapshot)
            .checks
            .map((check) => check.code),
        isNot(contains('supervisionRepairRequired')),
      );
    });
  }
  for (final label in [FreeSlotLabels.none, FreeSlotLabels.noClass]) {
    test('免任课「$label」不支持带班', () {
      final snapshot = _snapshot(label);
      expect(
        const SupervisionValidation().postErrors(snapshot, _draft),
        contains(contains('已有免任课「$label」')),
      );
      expect(
        const ProblemBuilder()
            .build(snapshot)
            .checks
            .map((check) => check.code),
        contains('supervisionRepairRequired'),
      );
    });
  }
}

const _post = SupervisionPost(
  id: 'post',
  kind: SupervisionKind.custom,
  name: '活动带班',
  stageId: 'stage',
  weekday: 1,
  periodTypeId: 'morning',
  lessonIndices: [1],
  classIds: ['class'],
);
const _draft = SupervisionDraft(
  termId: 'term',
  posts: [_post],
  teacherIds: {'teacher'},
  assignments: {'post': 'teacher'},
);

SchedulingSnapshot _snapshot(String label) => SchedulingSnapshot(
  term: AcademicTerm(
    id: 'term',
    title: '学期',
    academicYear: '2026',
    semesterLabel: '秋',
    firstTeachingWeekStart: DateTime(2026, 9, 7),
    teachingWeekCount: 20,
    createdAt: DateTime(2026),
  ),
  inputFingerprint: 'fixture',
  stages: const [
    SchoolStage(id: 'stage', termId: 'term', name: '小学', sortOrder: 0),
  ],
  grades: const [
    GradeGroup(id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0),
  ],
  classes: const [
    ClassGroup(id: 'class', gradeId: 'grade', name: '一班', sortOrder: 0),
  ],
  teachers: const [
    Teacher(id: 'teacher', name: '张老师', shortName: '张', sortOrder: 0),
  ],
  routines: const [
    StageRoutine(
      stageId: 'stage',
      teachingWeekdays: {1},
      overrides: [],
      periodTypes: [
        LessonPeriodType(
          id: 'morning',
          name: '上午',
          defaultLessonCount: 1,
          sortOrder: 0,
          lessonTimes: [
            LessonTime(
              lessonIndex: 1,
              label: '第1节',
              startMinute: 525,
              endMinute: 570,
            ),
          ],
        ),
      ],
    ),
  ],
  freeSlots: [
    FreeSlot(
      id: 'marker',
      scope: FreeSlotScope.stage,
      scopeId: 'stage',
      stageId: 'stage',
      periodTypeId: 'morning',
      weekday: 1,
      lessonIndex: 1,
      label: label,
    ),
  ],
  supervision: const [
    SupervisionOccurrence(
      post: _post,
      teacherId: 'teacher',
      position: SchedulePosition(
        stageId: 'stage',
        weekday: 1,
        periodTypeId: 'morning',
        lessonIndex: 1,
        startMinute: 525,
        endMinute: 570,
      ),
    ),
  ],
);
