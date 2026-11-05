import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/combined_lesson_group.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/models/teacher_preset.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

SchedulingSnapshot combinedPairingSnapshot({
  bool sharedEvenTeacher = false,
  bool combineEven = false,
  bool crossStage = false,
  bool fillers = false,
  bool protectOtherMust = false,
}) => SchedulingSnapshot(
  term: AcademicTerm(
    id: 't',
    title: '测试',
    academicYear: '2026',
    semesterLabel: '秋季',
    firstTeachingWeekStart: DateTime(2026, 9, 1),
    teachingWeekCount: 20,
    createdAt: DateTime(2026),
  ),
  inputFingerprint: 'combined-pairing',
  teacherPresets: [
    if (protectOtherMust)
      const TeacherPreset(
        id: 'must-other',
        teacherId: 'other-b',
        scope: TeacherPresetScope.school,
        scopeId: 't',
        stageId: 's',
        weekday: 1,
        periodTypeId: 'am',
        lessonIndex: 1,
        value: PresetValue.must,
      ),
  ],
  stages: [
    const SchoolStage(id: 's', termId: 't', name: '小学部', sortOrder: 0),
    if (crossStage)
      const SchoolStage(id: 's2', termId: 't', name: '初中部', sortOrder: 1),
  ],
  grades: [
    const GradeGroup(id: 'g', stageId: 's', name: '一年级', sortOrder: 0),
    if (crossStage)
      const GradeGroup(id: 'g2', stageId: 's2', name: '七年级', sortOrder: 0),
  ],
  classes: [
    ClassGroup(id: 'a', gradeId: 'g', name: '1 班', sortOrder: 0),
    ClassGroup(
      id: 'b',
      gradeId: crossStage ? 'g2' : 'g',
      name: '2 班',
      sortOrder: 1,
    ),
  ],
  routines: [
    for (final stage in ['s', if (crossStage) 's2'])
      StageRoutine(
        stageId: stage,
        teachingWeekdays: const {1, 2},
        periodTypes: [
          LessonPeriodType(
            id: stage == 's' ? 'am' : 'am2',
            name: '上午',
            defaultLessonCount: 4,
            sortOrder: 0,
            lessonTimes: [
              LessonTime(
                lessonIndex: 1,
                label: '1',
                startMinute: 480,
                endMinute: 520,
              ),
              LessonTime(
                lessonIndex: 2,
                label: '2',
                startMinute: 530,
                endMinute: 570,
              ),
              LessonTime(
                lessonIndex: 3,
                label: '3',
                startMinute: 580,
                endMinute: 620,
              ),
              LessonTime(
                lessonIndex: 4,
                label: '4',
                startMinute: 630,
                endMinute: 670,
              ),
            ],
          ),
        ],
        overrides: [],
      ),
  ],
  subjects: const [
    Subject(id: 'odd', name: '体育与健康', shortName: '体健', sortOrder: 0),
    Subject(id: 'even', name: '体育', shortName: '体育', sortOrder: 1),
    Subject(id: 'other', name: '其他课程', shortName: '其他', sortOrder: 2),
  ],
  teachers: const [
    Teacher(id: 'shared', name: '体育与健康教师 8', shortName: '8', sortOrder: 0),
    Teacher(id: 'even-a', name: '双周教师甲', shortName: '甲', sortOrder: 1),
    Teacher(id: 'even-b', name: '双周教师乙', shortName: '乙', sortOrder: 2),
    Teacher(id: 'other-a', name: '其他甲', shortName: '甲', sortOrder: 3),
    Teacher(id: 'other-b', name: '其他乙', shortName: '乙', sortOrder: 4),
  ],
  requirements: [
    if (fillers)
      const SubjectRequirement(
        id: 'other',
        subjectId: 'other',
        gradeId: 'g',
        weekMode: WeekMode.weekly,
        lessonCount: 4,
      ),
    for (final grade in ['g', if (crossStage) 'g2'])
      for (final week in [WeekMode.odd, WeekMode.even])
        SubjectRequirement(
          id: 'r-$grade-${week.name}',
          subjectId: week.name,
          gradeId: grade,
          weekMode: week,
          lessonCount: 4,
        ),
  ],
  assignments: [
    for (final c in ['a', 'b']) ...[
      if (fillers)
        TeacherAssignment(
          id: '$c-other',
          termId: 't',
          teacherId: 'other-$c',
          classId: c,
          subjectId: 'other',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      TeacherAssignment(
        id: '$c-odd',
        termId: 't',
        teacherId: 'shared',
        classId: c,
        subjectId: 'odd',
        weekMode: WeekMode.odd,
        lessonCount: 4,
        combinedLessonGroupId: 'combined',
      ),
      TeacherAssignment(
        id: '$c-even',
        termId: 't',
        teacherId: sharedEvenTeacher || combineEven ? 'even-a' : 'even-$c',
        classId: c,
        subjectId: 'even',
        weekMode: WeekMode.even,
        lessonCount: 4,
        combinedLessonGroupId: combineEven ? 'combined-even' : null,
      ),
    ],
  ],
  combinedGroups: [
    const CombinedLessonGroup(
      id: 'combined',
      termId: 't',
      teacherId: 'shared',
      subjectId: 'odd',
      weekMode: WeekMode.odd,
      classIds: ['a', 'b'],
    ),
    if (combineEven)
      const CombinedLessonGroup(
        id: 'combined-even',
        termId: 't',
        teacherId: 'even-a',
        subjectId: 'even',
        weekMode: WeekMode.even,
        classIds: ['a', 'b'],
      ),
  ],
  pairings: const [
    SubjectPairing(
      id: 'pair-a',
      classId: 'a',
      oddSubjectId: 'odd',
      evenSubjectId: 'even',
    ),
    SubjectPairing(
      id: 'pair-b',
      classId: 'b',
      oddSubjectId: 'odd',
      evenSubjectId: 'even',
    ),
  ],
);
