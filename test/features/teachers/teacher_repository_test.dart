import 'dart:async';

import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/domain/models/teacher_preset.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repository;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftSchoolRepository(database);
  });

  tearDown(() => database.close());

  Future<void> seed() async {
    await repository.saveTerm(
      AcademicTerm(
        id: 'term-1',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026),
      ),
    );
    final stage = (await repository.watchStages('term-1').first).first;
    await repository.saveGrade(
      GradeGroup(id: 'grade-1', stageId: stage.id, name: '初一', sortOrder: 0),
    );
    await repository.saveClass(
      const ClassGroup(
        id: 'class-1',
        gradeId: 'grade-1',
        name: '初一（1）班',
        sortOrder: 0,
      ),
    );
    await repository.saveSubjects([
      const Subject(id: 'subject-1', name: '数学', shortName: '数', sortOrder: 0),
    ]);
    expect(stage.termId, 'term-1');
  }

  test('教师、标签、分组和拆分任课可持久化', () async {
    await seed();
    await repository.saveTeachers([
      const Teacher(
        id: 'teacher-1',
        name: '张伟',
        shortName: '张',
        sortOrder: 0,
        subjectIds: {'subject-1'},
      ),
      const Teacher(id: 'teacher-2', name: '李芳', shortName: '李', sortOrder: 1),
    ]);
    expect((await repository.watchTeachers('term-1').first).first.subjectIds, {
      'subject-1',
    });

    await repository.saveTeacherGroup(
      const TeacherGroup(
        id: 'group-1',
        termId: 'term-1',
        name: '数学组',
        sortOrder: 0,
      ),
    );
    await repository.replaceTeacherGroupMembers(
      groupId: 'group-1',
      members: const [
        TeacherGroupMember(
          id: 'm1',
          groupId: 'group-1',
          teacherId: 'teacher-1',
        ),
      ],
    );
    expect(
      (await repository.watchTeacherGroupMembers('term-1').first)
          .single
          .teacherId,
      'teacher-1',
    );

    await repository.replaceGradeRequirements(
      gradeId: 'grade-1',
      requirements: const [
        SubjectRequirement(
          id: 'requirement-1',
          subjectId: 'subject-1',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
    );

    await repository.replaceTeacherAssignments(
      termId: 'term-1',
      classId: 'class-1',
      subjectId: 'subject-1',
      assignments: const [
        TeacherAssignment(
          id: 'a1',
          termId: 'term-1',
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'subject-1',
          weekMode: WeekMode.weekly,
          lessonCount: 3,
        ),
        TeacherAssignment(
          id: 'a2',
          termId: 'term-1',
          teacherId: 'teacher-2',
          classId: 'class-1',
          subjectId: 'subject-1',
          weekMode: WeekMode.weekly,
          lessonCount: 1,
        ),
      ],
    );
    expect(
      (await repository.watchTeacherAssignments('term-1').first),
      hasLength(2),
    );
    expect(await repository.countTeacherAssignments('teacher-1'), 1);

    await expectLater(
      repository.replaceTeacherAssignments(
        termId: 'term-1',
        classId: 'class-1',
        subjectId: 'subject-1',
        assignments: const [
          TeacherAssignment(
            id: 'too-many',
            termId: 'term-1',
            teacherId: 'teacher-1',
            classId: 'class-1',
            subjectId: 'subject-1',
            weekMode: WeekMode.weekly,
            lessonCount: 5,
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    await repository.deleteTeacher('teacher-1');
    final afterDelete = await repository
        .watchTeacherAssignments('term-1')
        .first;
    expect(afterDelete.firstWhere((row) => row.id == 'a1').teacherId, isEmpty);
    expect(await repository.countTeacherAssignments('teacher-1'), 0);
  });

  test('替换分组成员后成员监听流会发出最新数据', () async {
    await seed();
    await repository.saveTeachers([
      const Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
    ]);
    await repository.saveTeacherGroup(
      const TeacherGroup(
        id: 'group-1',
        termId: 'term-1',
        name: '数学组',
        sortOrder: 0,
      ),
    );

    final membershipUpdates = StreamIterator(
      repository.watchTeacherGroupMembers('term-1'),
    );
    addTearDown(membershipUpdates.cancel);
    expect(await membershipUpdates.moveNext(), isTrue);
    expect(membershipUpdates.current, isEmpty);

    await repository.replaceTeacherGroupMembers(
      groupId: 'group-1',
      members: const [
        TeacherGroupMember(
          id: 'member-1',
          groupId: 'group-1',
          teacherId: 'teacher-1',
        ),
      ],
    );

    expect(
      await membershipUpdates.moveNext().timeout(
        const Duration(milliseconds: 300),
      ),
      isTrue,
    );
    expect(membershipUpdates.current.map((member) => member.teacherId), [
      'teacher-1',
    ]);
  });

  test('批量添加任课按单元格校验容量并在失败时整体回滚', () async {
    await seed();
    await repository.saveTeachers([
      const Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
    ]);
    await repository.saveClass(
      const ClassGroup(
        id: 'class-2',
        gradeId: 'grade-1',
        name: '初一（2）班',
        sortOrder: 1,
      ),
    );
    await repository.replaceGradeRequirements(
      gradeId: 'grade-1',
      requirements: const [
        SubjectRequirement(
          id: 'requirement-1',
          subjectId: 'subject-1',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
    );

    await repository.addTeacherAssignments(
      termId: 'term-1',
      assignments: const [
        TeacherAssignment(
          id: 'batch-1',
          termId: 'term-1',
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'subject-1',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
        TeacherAssignment(
          id: 'batch-2',
          termId: 'term-1',
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'subject-1',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
      ],
    );
    expect(
      (await repository.watchTeacherAssignments('term-1').first),
      hasLength(2),
    );

    await expectLater(
      repository.addTeacherAssignments(
        termId: 'term-1',
        assignments: const [
          TeacherAssignment(
            id: 'batch-3',
            termId: 'term-1',
            teacherId: 'teacher-1',
            classId: 'class-2',
            subjectId: 'subject-1',
            weekMode: WeekMode.weekly,
            lessonCount: 3,
          ),
          TeacherAssignment(
            id: 'batch-4',
            termId: 'term-1',
            teacherId: 'teacher-1',
            classId: 'class-1',
            subjectId: 'subject-1',
            weekMode: WeekMode.weekly,
            lessonCount: 1,
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await repository.watchTeacherAssignments('term-1').first).map(
        (row) => row.id,
      ),
      ['batch-1', 'batch-2'],
    );
  });

  test('删除任课会整体解除相关合班关系', () async {
    await seed();
    await repository.saveTeachers([
      const Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
    ]);
    await repository.saveClass(
      const ClassGroup(
        id: 'class-2',
        gradeId: 'grade-1',
        name: '初一（2）班',
        sortOrder: 1,
      ),
    );
    await repository.replaceGradeRequirements(
      gradeId: 'grade-1',
      requirements: const [
        SubjectRequirement(
          id: 'requirement-1',
          subjectId: 'subject-1',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 3,
        ),
      ],
    );
    await repository.addTeacherAssignments(
      termId: 'term-1',
      assignments: const [
        TeacherAssignment(
          id: 'class-1-assignment',
          termId: 'term-1',
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'subject-1',
          weekMode: WeekMode.weekly,
          lessonCount: 3,
        ),
        TeacherAssignment(
          id: 'class-2-assignment',
          termId: 'term-1',
          teacherId: 'teacher-1',
          classId: 'class-2',
          subjectId: 'subject-1',
          weekMode: WeekMode.weekly,
          lessonCount: 3,
        ),
      ],
    );
    await repository.combineTeacherAssignments(
      termId: 'term-1',
      assignmentIds: const ['class-1-assignment', 'class-2-assignment'],
      combinedGroupId: 'combined-1',
    );

    await repository.deleteTeacherAssignments(
      termId: 'term-1',
      assignmentIds: const ['class-1-assignment'],
    );

    final remaining =
        (await repository.watchTeacherAssignments('term-1').first).single;
    expect(remaining.id, 'class-2-assignment');
    expect(remaining.combinedLessonGroupId, isNull);
  });

  test('替换为空集合后会删除已保存的个人与分组预排规则', () async {
    await seed();
    final stage = (await repository.watchStages('term-1').first).single;
    await repository.saveRoutine(
      StageRoutine(
        stageId: stage.id,
        teachingWeekdays: const {1},
        periodTypes: const [
          LessonPeriodType(
            id: 'period-1',
            name: '上午',
            defaultLessonCount: 1,
            sortOrder: 0,
            lessonTimes: [],
          ),
        ],
        overrides: const [],
      ),
    );
    await repository.saveTeachers([
      const Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
    ]);
    await repository.saveTeacherGroup(
      const TeacherGroup(
        id: 'group-1',
        termId: 'term-1',
        name: '数学组',
        sortOrder: 0,
      ),
    );
    await repository.replaceTeacherPresets(
      termId: 'term-1',
      teacherId: 'teacher-1',
      presets: [
        TeacherPreset(
          id: 'teacher-preset',
          teacherId: 'teacher-1',
          scope: TeacherPresetScope.grade,
          scopeId: 'grade-1',
          stageId: stage.id,
          weekday: 1,
          periodTypeId: 'period-1',
          lessonIndex: 1,
          value: PresetValue.forbid,
        ),
      ],
    );
    await repository.replaceTeacherGroupPresets(
      groupId: 'group-1',
      presets: [
        TeacherGroupPreset(
          id: 'group-preset',
          groupId: 'group-1',
          scope: TeacherPresetScope.grade,
          scopeId: 'grade-1',
          stageId: stage.id,
          weekday: 1,
          periodTypeId: 'period-1',
          lessonIndex: 1,
          value: PresetValue.must,
        ),
      ],
    );

    expect(await repository.watchTeacherPresets('term-1').first, hasLength(1));
    expect(
      await repository.watchTeacherGroupPresets('term-1').first,
      hasLength(1),
    );

    await repository.replaceTeacherPresets(
      termId: 'term-1',
      teacherId: 'teacher-1',
      presets: const [],
    );
    await repository.replaceTeacherGroupPresets(
      groupId: 'group-1',
      presets: const [],
    );

    expect(await repository.watchTeacherPresets('term-1').first, isEmpty);
    expect(await repository.watchTeacherGroupPresets('term-1').first, isEmpty);
  });

  test('学期克隆复用教师身份并重映射个人与分组预排范围', () async {
    await seed();
    final sourceStage = (await repository.watchStages('term-1').first).single;
    await repository.saveRoutine(
      StageRoutine(
        stageId: sourceStage.id,
        teachingWeekdays: const {1},
        periodTypes: const [
          LessonPeriodType(
            id: 'period-1',
            name: '上午',
            defaultLessonCount: 4,
            sortOrder: 0,
            lessonTimes: [
              LessonTime(
                lessonIndex: 1,
                label: '第一节',
                startMinute: 480,
                endMinute: 525,
              ),
            ],
          ),
        ],
        overrides: const [],
      ),
    );
    await repository.saveTeachers([
      const Teacher(
        id: 'teacher-1',
        name: '张伟',
        shortName: '张',
        sortOrder: 0,
        subjectIds: {'subject-1'},
      ),
    ]);
    await repository.saveTeacherGroup(
      const TeacherGroup(
        id: 'group-1',
        termId: 'term-1',
        name: '数学组',
        sortOrder: 0,
      ),
    );
    await repository.replaceTeacherPresets(
      termId: 'term-1',
      teacherId: 'teacher-1',
      presets: [
        TeacherPreset(
          id: 'teacher-grade-preset',
          teacherId: 'teacher-1',
          scope: TeacherPresetScope.grade,
          scopeId: 'grade-1',
          stageId: sourceStage.id,
          weekday: 1,
          periodTypeId: 'period-1',
          lessonIndex: 1,
          value: PresetValue.forbid,
        ),
      ],
    );
    await repository.replaceTeacherGroupPresets(
      groupId: 'group-1',
      presets: [
        TeacherGroupPreset(
          id: 'group-class-preset',
          groupId: 'group-1',
          scope: TeacherPresetScope.schoolClass,
          scopeId: 'class-1',
          stageId: sourceStage.id,
          weekday: 1,
          periodTypeId: 'period-1',
          lessonIndex: 1,
          value: PresetValue.must,
        ),
      ],
    );

    await repository.cloneTerm(
      sourceTermId: 'term-1',
      targetTerm: AcademicTerm(
        id: 'term-2',
        title: '2027 春季',
        academicYear: '2026-2027',
        semesterLabel: '春季学期',
        firstTeachingWeekStart: DateTime(2027, 2, 15),
        teachingWeekCount: 20,
        createdAt: DateTime(2026),
      ),
    );

    expect(
      (await repository.watchTeachers('term-2').first).map(
        (teacher) => teacher.id,
      ),
      ['teacher-1'],
    );
    final targetStage = (await repository.watchStages('term-2').first).single;
    final targetGrade =
        (await repository.watchGrades(targetStage.id).first).single;
    final targetClass =
        (await repository.watchClasses(targetGrade.id).first).single;
    final teacherPreset =
        (await repository.watchTeacherPresets('term-2').first).single;
    final groupPreset =
        (await repository.watchTeacherGroupPresets('term-2').first).single;

    expect(teacherPreset.scopeId, targetGrade.id);
    expect(teacherPreset.stageId, targetStage.id);
    expect(teacherPreset.periodTypeId, isNot('period-1'));
    expect(groupPreset.scopeId, targetClass.id);
    expect(groupPreset.stageId, targetStage.id);
    expect(groupPreset.periodTypeId, teacherPreset.periodTypeId);
  });

  test('分组和成员批量保存失败时不会留下部分数据', () async {
    await seed();
    await repository.saveTeachers([
      const Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
    ]);
    await expectLater(
      repository.saveTeacherGroupsWithMembers(
        groups: const [
          TeacherGroup(
            id: 'group-1',
            termId: 'term-1',
            name: '数学组',
            sortOrder: 0,
          ),
        ],
        members: const [
          TeacherGroupMember(
            id: 'member-1',
            groupId: 'group-1',
            teacherId: 'missing-teacher',
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(await repository.watchTeacherGroups('term-1').first, isEmpty);
  });

  test('符合条件的同一教师任课可合班并整体拆班', () async {
    await seed();
    await repository.saveClass(
      const ClassGroup(
        id: 'class-2',
        gradeId: 'grade-1',
        name: '初一（2）班',
        sortOrder: 1,
      ),
    );
    await repository.saveTeachers([
      const Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
    ]);
    await repository.replaceGradeRequirements(
      gradeId: 'grade-1',
      requirements: const [
        SubjectRequirement(
          id: 'requirement-1',
          subjectId: 'subject-1',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
    );
    for (final classId in ['class-1', 'class-2']) {
      await repository.replaceTeacherAssignments(
        termId: 'term-1',
        classId: classId,
        subjectId: 'subject-1',
        assignments: [
          TeacherAssignment(
            id: 'assignment-$classId',
            termId: 'term-1',
            teacherId: 'teacher-1',
            classId: classId,
            subjectId: 'subject-1',
            weekMode: WeekMode.weekly,
            lessonCount: 4,
          ),
        ],
      );
    }

    await repository.combineTeacherAssignments(
      termId: 'term-1',
      assignmentIds: const ['assignment-class-1', 'assignment-class-2'],
      combinedGroupId: 'combined-1',
    );
    expect(
      (await repository.watchTeacherAssignments('term-1').first).map(
        (row) => row.combinedLessonGroupId,
      ),
      ['combined-1', 'combined-1'],
    );

    await repository.separateTeacherAssignments(
      termId: 'term-1',
      combinedGroupId: 'combined-1',
    );
    expect(
      (await repository.watchTeacherAssignments('term-1').first).map(
        (row) => row.combinedLessonGroupId,
      ),
      [null, null],
    );
  });

  test('属性不一致的任课不能合班且不会部分更新', () async {
    await seed();
    await repository.saveClass(
      const ClassGroup(
        id: 'class-2',
        gradeId: 'grade-1',
        name: '初一（2）班',
        sortOrder: 1,
      ),
    );
    await repository.saveTeachers([
      const Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
      const Teacher(id: 'teacher-2', name: '李芳', shortName: '李', sortOrder: 1),
    ]);
    await repository.replaceGradeRequirements(
      gradeId: 'grade-1',
      requirements: const [
        SubjectRequirement(
          id: 'requirement-1',
          subjectId: 'subject-1',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
    );
    await repository.replaceTeacherAssignments(
      termId: 'term-1',
      classId: 'class-1',
      subjectId: 'subject-1',
      assignments: const [
        TeacherAssignment(
          id: 'assignment-1',
          termId: 'term-1',
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'subject-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
    );
    await repository.replaceTeacherAssignments(
      termId: 'term-1',
      classId: 'class-2',
      subjectId: 'subject-1',
      assignments: const [
        TeacherAssignment(
          id: 'assignment-2',
          termId: 'term-1',
          teacherId: 'teacher-2',
          classId: 'class-2',
          subjectId: 'subject-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
    );

    await expectLater(
      repository.combineTeacherAssignments(
        termId: 'term-1',
        assignmentIds: const ['assignment-1', 'assignment-2'],
        combinedGroupId: 'combined-1',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      (await repository.watchTeacherAssignments('term-1').first).map(
        (row) => row.combinedLessonGroupId,
      ),
      [null, null],
    );
  });

  test('没有科目需求或未选择教师时不能保存任课分配', () async {
    await seed();
    await repository.saveTeachers([
      const Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
    ]);
    const assignment = TeacherAssignment(
      id: 'assignment-1',
      termId: 'term-1',
      teacherId: 'teacher-1',
      classId: 'class-1',
      subjectId: 'subject-1',
      weekMode: WeekMode.weekly,
      lessonCount: 1,
    );

    await expectLater(
      repository.replaceTeacherAssignments(
        termId: 'term-1',
        classId: 'class-1',
        subjectId: 'subject-1',
        assignments: const [assignment],
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.addTeacherAssignments(
        termId: 'term-1',
        assignments: const [assignment],
      ),
      throwsA(isA<StateError>()),
    );

    await repository.replaceGradeRequirements(
      gradeId: 'grade-1',
      requirements: const [
        SubjectRequirement(
          id: 'requirement-1',
          subjectId: 'subject-1',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
    );
    await expectLater(
      repository.replaceTeacherAssignments(
        termId: 'term-1',
        classId: 'class-1',
        subjectId: 'subject-1',
        assignments: const [
          TeacherAssignment(
            id: 'unassigned',
            termId: 'term-1',
            teacherId: '',
            classId: 'class-1',
            subjectId: 'subject-1',
            weekMode: WeekMode.weekly,
            lessonCount: 1,
          ),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
