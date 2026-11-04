import 'dart:io';

import 'package:class_set/data/backup/local_backup_service.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_scheduling_repository.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/models/teacher_preset.dart';
import 'package:class_set/domain/scheduling/course_scheduler.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/schedule_reconciler.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('一键腾挪写入数据库，撤销重做覆盖原课程和暂放课', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final school = DriftSchoolRepository(database);
    await school.saveTerm(
      AcademicTerm(
        id: 'repair',
        title: '腾挪测试',
        academicYear: '2026',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026),
      ),
    );
    final stage = (await school.watchStages('repair').first).first;
    await school.saveGrade(
      GradeGroup(
        id: 'grade-repair',
        stageId: stage.id,
        name: '一年级',
        sortOrder: 0,
      ),
    );
    await school.saveClass(
      const ClassGroup(
        id: 'class-repair',
        gradeId: 'grade-repair',
        name: '一班',
        sortOrder: 0,
      ),
    );
    await school.saveRoutine(
      StageRoutine(
        stageId: stage.id,
        teachingWeekdays: {1},
        overrides: const [],
        periodTypes: const [
          LessonPeriodType(
            id: 'repair-morning',
            name: '上午',
            defaultLessonCount: 2,
            sortOrder: 0,
            lessonTimes: [
              LessonTime(
                lessonIndex: 1,
                label: '第一节',
                startMinute: 480,
                endMinute: 520,
              ),
              LessonTime(
                lessonIndex: 2,
                label: '第二节',
                startMinute: 530,
                endMinute: 570,
              ),
            ],
          ),
        ],
      ),
    );
    await school.saveSubjects(const [
      Subject(
        id: 'subject-repair',
        termId: 'repair',
        name: '数学',
        shortName: '数',
        sortOrder: 0,
      ),
    ]);
    await school.saveTeachers(const [
      Teacher(id: 'flexible', name: '可调整教师', shortName: '甲', sortOrder: 0),
      Teacher(id: 'restricted', name: '受限教师', shortName: '乙', sortOrder: 1),
    ]);
    await database.customStatement(
      'INSERT INTO subject_requirements '
      '(id, subject_id, grade_id, week_mode, lesson_count) VALUES (?, ?, ?, ?, ?)',
      ['requirement-repair', 'subject-repair', 'grade-repair', 'weekly', 2],
    );
    await school.addTeacherAssignments(
      termId: 'repair',
      assignments: [
        for (final teacher in ['flexible', 'restricted'])
          TeacherAssignment(
            id: 'assignment-$teacher',
            termId: 'repair',
            teacherId: teacher,
            classId: 'class-repair',
            subjectId: 'subject-repair',
            weekMode: WeekMode.weekly,
            lessonCount: 1,
          ),
      ],
    );
    await school.replaceTeacherPresets(
      termId: 'repair',
      teacherId: 'restricted',
      presets: [
        TeacherPreset(
          id: 'restricted-second',
          teacherId: 'restricted',
          scope: TeacherPresetScope.school,
          scopeId: 'repair',
          stageId: stage.id,
          weekday: 1,
          periodTypeId: 'repair-morning',
          lessonIndex: 2,
          value: PresetValue.forbid,
        ),
      ],
    );
    for (final teacher in ['flexible', 'restricted']) {
      await database.customStatement(
        'INSERT INTO schedule_items '
        '(id, term_id, assignment_id, class_id, teacher_id, subject_id, week_mode, '
        'stage_id, weekday, period_type_id, lesson_index) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'item-$teacher',
          'repair',
          'assignment-$teacher',
          'class-repair',
          teacher,
          'subject-repair',
          'weekly',
          if (teacher == 'flexible') ...[
            stage.id,
            1,
            'repair-morning',
            1,
          ] else ...[
            null,
            null,
            null,
            null,
          ],
        ],
      );
    }
    final controller = SchedulingController(school, 'repair');
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.state.pendingBaseline, isNull);
    expect(await controller.placeUnplaced({'item-restricted'}), 1);
    expect(controller.state.error, isNull);
    Future<Map<String, int?>> positions() async => {
      for (final item in (await school.loadSchedulingSnapshot(
        'repair',
      )).existingItems)
        item.id: item.position?.lessonIndex,
    };
    expect(await positions(), {'item-flexible': 2, 'item-restricted': 1});
    expect(controller.state.undoCount, 1);
    await controller.undo();
    expect(await positions(), {'item-flexible': 1, 'item-restricted': null});
    await controller.redo();
    expect(await positions(), {'item-flexible': 2, 'item-restricted': 1});
    await controller.undo();
    await controller.setLock(
      const ScheduleLock(
        termId: 'repair',
        scope: ScheduleLockScope.teacher,
        targetId: 'flexible',
      ),
      enabled: true,
    );
    expect(await controller.placeUnplaced({'item-restricted'}), 0);
    expect(await positions(), {'item-flexible': 1, 'item-restricted': null});
    expect(controller.state.placementUnplaced.single.itemId, 'item-restricted');
    expect(controller.state.placementUnplaced.single.blockers, isNotEmpty);
    expect(controller.state.undoCount, 0);
  });

  test('读取排课快照包含已保存学期且指纹稳定', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final school = DriftSchoolRepository(database);
    final scheduling = DriftSchedulingRepository(database, school);
    await school.saveTerm(
      AcademicTerm(
        id: 'term-1',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026, 8, 1),
      ),
    );

    final first = await scheduling.loadSchedulingSnapshot('term-1');
    final second = await scheduling.loadSchedulingSnapshot('term-1');

    expect(first.term.id, 'term-1');
    expect(first.inputFingerprint, isNotEmpty);
    expect(second.inputFingerprint, first.inputFingerprint);
  });

  test('创建的 SQLite 备份可通过完整性校验', () async {
    final directory = await Directory.systemTemp.createTemp(
      'paike-backup-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/school.sqlite');
    final database = db.AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final school = DriftSchoolRepository(database);
    await school.saveTerm(
      AcademicTerm(
        id: 'term-backup',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026, 8, 1),
      ),
    );

    final backups = LocalBackupService(database, file);
    final snapshot = await backups.createSnapshot(label: 'before-scheduling');

    expect(await snapshot.file.exists(), isTrue);
    await backups.verifySnapshot(snapshot);
    expect((await backups.listSnapshots()).single.id, snapshot.id);
  });

  test('提交排课报告并拒绝过期资料的结果', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final school = DriftSchoolRepository(database);
    final scheduling = DriftSchedulingRepository(database, school);
    await school.saveTerm(
      AcademicTerm(
        id: 'term-commit',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    final stage = (await school.watchStages('term-commit').first).first;
    await school.saveGrade(
      GradeGroup(id: 'grade-1', stageId: stage.id, name: '一年级', sortOrder: 0),
    );
    await school.saveClass(
      const ClassGroup(
        id: 'class-1',
        gradeId: 'grade-1',
        name: '一班',
        sortOrder: 0,
      ),
    );
    final snapshot = await scheduling.loadSchedulingSnapshot('term-commit');
    final run = ScheduleRun(
      id: 'run-1',
      termId: 'term-commit',
      inputFingerprint: snapshot.inputFingerprint,
      config: const ScheduleRunConfig(
        selectedClassIds: {'class-1'},
        seed: 1,
        strength: ScheduleStrength.fast,
      ),
      report: const ScheduleReport(
        totalItems: 0,
        placedItems: 0,
        coverage: 0,
        preferenceScores: {},
        unplaced: [],
        unmetHardRequirements: [],
        candidateChecks: 0,
      ),
      items: const [],
    );

    await scheduling.commitScheduleRun(run, selectedClassIds: {'class-1'});
    expect(
      (await scheduling.watchSchedule('term-commit').first).latestRun?.id,
      'run-1',
    );

    await school.saveGrade(
      GradeGroup(id: 'grade-1', stageId: stage.id, name: '一年级甲', sortOrder: 0),
    );
    await expectLater(
      scheduling.commitScheduleRun(run, selectedClassIds: {'class-1'}),
      throwsStateError,
    );
  });

  test('需求与任课经过求解、手工暂放及恢复后可重新读取课表', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final school = DriftSchoolRepository(database);
    final scheduling = DriftSchedulingRepository(database, school);
    await school.saveTerm(
      AcademicTerm(
        id: 'term-flow',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        cycleMode: AcademicTermCycle.everyWeek,
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    final stage = (await school.watchStages('term-flow').first).first;
    await school.saveGrade(
      GradeGroup(
        id: 'grade-flow',
        stageId: stage.id,
        name: '一年级',
        sortOrder: 0,
      ),
    );
    await school.saveClass(
      const ClassGroup(
        id: 'class-flow',
        gradeId: 'grade-flow',
        name: '一班',
        sortOrder: 0,
      ),
    );
    await school.saveSubjects(const [
      Subject(
        id: 'subject-flow',
        termId: 'term-flow',
        name: '数学',
        shortName: '数',
        sortOrder: 0,
      ),
    ]);
    await school.saveTeachers(const [
      Teacher(id: 'teacher-flow', name: '李老师', shortName: '李', sortOrder: 0),
    ]);
    await database.customStatement(
      'INSERT INTO subject_requirements '
      '(id, subject_id, grade_id, week_mode, lesson_count) '
      'VALUES (?, ?, ?, ?, ?)',
      ['requirement-flow', 'subject-flow', 'grade-flow', 'weekly', 1],
    );
    await school.addTeacherAssignments(
      termId: 'term-flow',
      assignments: const [
        TeacherAssignment(
          id: 'assignment-flow',
          termId: 'term-flow',
          teacherId: 'teacher-flow',
          classId: 'class-flow',
          subjectId: 'subject-flow',
          weekMode: WeekMode.weekly,
          lessonCount: 1,
        ),
      ],
    );

    final snapshot = await scheduling.loadSchedulingSnapshot('term-flow');
    final problem = const ProblemBuilder().build(snapshot);
    expect(problem.isReady, isTrue);
    final run = const CourseScheduler().solve(
      problem,
      config: const ScheduleRunConfig(
        selectedClassIds: {'class-flow'},
        seed: 7,
        strength: ScheduleStrength.fast,
      ),
    );
    expect(run.report.placedItems, 1);

    await scheduling.commitScheduleRun(run, selectedClassIds: {'class-flow'});
    final saved = await scheduling.watchSchedule('term-flow').first;
    expect(saved.items, hasLength(1));
    expect(
      saved.items.single.position?.cellKey,
      run.items.single.position?.cellKey,
    );
    expect(saved.latestRun?.id, run.id);

    final beforeManual = await scheduling.loadSchedulingSnapshot('term-flow');
    final placed = beforeManual.existingItems.single;
    final unplaced = placed.at(null);
    await scheduling.commitManualScheduleEdit(
      termId: 'term-flow',
      expectedFingerprint: beforeManual.inputFingerprint,
      before: [placed],
      after: [unplaced],
    );
    expect(
      (await scheduling.loadSchedulingSnapshot('term-flow'))
          .existingItems
          .single
          .position,
      isNull,
    );
    await expectLater(
      scheduling.commitManualScheduleEdit(
        termId: 'term-flow',
        expectedFingerprint: beforeManual.inputFingerprint,
        before: [unplaced],
        after: [placed],
      ),
      throwsStateError,
    );
    final controller = SchedulingController(school, 'term-flow');
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(await controller.placeUnplaced({unplaced.id}), 1);
    expect(
      (await scheduling.loadSchedulingSnapshot('term-flow'))
          .existingItems
          .single
          .isPlaced,
      isTrue,
    );
    await controller.undo();
    expect(
      (await scheduling.loadSchedulingSnapshot('term-flow'))
          .existingItems
          .single
          .isPlaced,
      isFalse,
    );
    await controller.redo();
    expect(
      (await scheduling.loadSchedulingSnapshot('term-flow'))
          .existingItems
          .single
          .isPlaced,
      isTrue,
    );
    await controller.undo();

    final beforeRestore = await scheduling.loadSchedulingSnapshot('term-flow');
    await scheduling.commitManualScheduleEdit(
      termId: 'term-flow',
      expectedFingerprint: beforeRestore.inputFingerprint,
      before: [unplaced],
      after: [placed],
    );
    expect(
      (await scheduling.loadSchedulingSnapshot('term-flow'))
          .existingItems
          .single
          .position
          ?.cellKey,
      placed.position?.cellKey,
    );

    await scheduling.setScheduleLock(
      const ScheduleLock(
        termId: 'term-flow',
        scope: ScheduleLockScope.schoolClass,
        targetId: 'class-flow',
      ),
      enabled: true,
    );
    final routine = (await school.watchRoutine(stage.id).first)!;
    final renamed = StageRoutine(
      stageId: routine.stageId,
      teachingWeekdays: routine.teachingWeekdays,
      overrides: routine.overrides,
      periodTypes: [
        for (final period in routine.periodTypes)
          LessonPeriodType(
            id: period.id,
            name: '${period.name}新',
            defaultLessonCount: period.defaultLessonCount,
            sortOrder: period.sortOrder,
            lessonTimes: period.lessonTimes,
          ),
      ],
    );
    await school.saveRoutine(renamed);
    final baseline = await scheduling.loadPendingSchedulingBaseline(
      'term-flow',
    );
    expect(baseline, isNotNull);
    expect(
      baseline!.existingItems.single.position?.cellKey,
      placed.position?.cellKey,
    );
    expect(
      (await scheduling.loadSchedulingSnapshot('term-flow'))
          .existingItems
          .single
          .position
          ?.cellKey,
      placed.position?.cellKey,
    );

    final removingDay = StageRoutine(
      stageId: renamed.stageId,
      teachingWeekdays: renamed.teachingWeekdays.difference({
        placed.position!.weekday,
      }),
      overrides: renamed.overrides,
      periodTypes: renamed.periodTypes,
    );
    await school.saveRoutine(removingDay);
    final current = await scheduling.loadSchedulingSnapshot('term-flow');
    final preview = const ScheduleReconciler().preview(baseline, current);
    expect(preview.canApply, isTrue);
    expect(preview.movedCount, 1);
    expect(preview.locksToRelease, hasLength(1));
    expect(
      preview.items.single.position?.weekday,
      isNot(placed.position!.weekday),
    );
    await scheduling.commitScheduleReconciliation(
      termId: 'term-flow',
      expectedFingerprint: preview.inputFingerprint,
    );
    final reconciled = await scheduling.loadSchedulingSnapshot('term-flow');
    expect(
      reconciled.existingItems.single.position?.cellKey,
      preview.items.single.position?.cellKey,
    );
    expect(await scheduling.loadPendingSchedulingBaseline('term-flow'), isNull);
    expect(reconciled.locks, isEmpty);
    await school.saveRoutine(removingDay);
    expect(await scheduling.loadPendingSchedulingBaseline('term-flow'), isNull);
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: reconciled.conditions,
      preferences: reconciled.preferences,
    );
    expect(await scheduling.loadPendingSchedulingBaseline('term-flow'), isNull);
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: const [],
      preferences: const SchedulePreferences(strength: ScheduleStrength.high),
    );
    expect(await scheduling.loadPendingSchedulingBaseline('term-flow'), isNull);
    const condition = ScheduleCondition(
      id: 'rule',
      termId: 'term-flow',
      type: ScheduleConditionType.dailyLimit,
      targetType: ScheduleConditionTarget.subject,
      targetId: 'subject-flow',
      maximum: 1,
    );
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: const [condition],
      preferences: const SchedulePreferences(strength: ScheduleStrength.high),
    );
    expect(
      await scheduling.loadPendingSchedulingBaseline('term-flow'),
      isNotNull,
    );
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: const [],
      preferences: const SchedulePreferences(strength: ScheduleStrength.fast),
    );
    expect(await scheduling.loadPendingSchedulingBaseline('term-flow'), isNull);
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: const [condition],
      preferences: const SchedulePreferences(strength: ScheduleStrength.fast),
    );
    await school.saveGrade(
      GradeGroup(
        id: 'grade-flow',
        stageId: stage.id,
        name: '更名年级',
        sortOrder: 0,
      ),
    );
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: const [],
      preferences: const SchedulePreferences(strength: ScheduleStrength.fast),
    );
    expect(
      await scheduling.loadPendingSchedulingBaseline('term-flow'),
      isNotNull,
    );
    await school.saveGrade(
      GradeGroup(
        id: 'grade-flow',
        stageId: stage.id,
        name: '一年级',
        sortOrder: 0,
      ),
    );
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: const [],
      preferences: const SchedulePreferences(strength: ScheduleStrength.high),
    );
    expect(await scheduling.loadPendingSchedulingBaseline('term-flow'), isNull);
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: const [],
      preferences: const SchedulePreferences(
        strength: ScheduleStrength.high,
        protectLunchBreak: true,
      ),
    );
    expect(
      await scheduling.loadPendingSchedulingBaseline('term-flow'),
      isNotNull,
    );
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: const [],
      preferences: const SchedulePreferences(strength: ScheduleStrength.high),
    );
    expect(await scheduling.loadPendingSchedulingBaseline('term-flow'), isNull);
    await scheduling.saveScheduleConfiguration(
      termId: 'term-flow',
      conditions: const [],
      preferences: const SchedulePreferences(
        strength: ScheduleStrength.high,
        protectLunchBreak: true,
      ),
    );
    final ruleBaseline = (await scheduling.loadPendingSchedulingBaseline(
      'term-flow',
    ))!;
    final ruleCurrent = await scheduling.loadSchedulingSnapshot('term-flow');
    final rulePreview = const ScheduleReconciler().preview(
      ruleBaseline,
      ruleCurrent,
    );
    expect(rulePreview.canApply, isTrue);
    expect(rulePreview.keptCount, 1);
    expect(rulePreview.changes.any((change) => change.label == '午间保护'), isTrue);
    await scheduling.commitScheduleReconciliation(
      termId: 'term-flow',
      expectedFingerprint: rulePreview.inputFingerprint,
    );

    await school.saveTeachers(const [
      Teacher(id: 'teacher-flow', name: '李老师', shortName: '李', sortOrder: 0),
      Teacher(id: 'teacher-next', name: '王老师', shortName: '王', sortOrder: 1),
    ]);
    await school.replaceTeacherAssignments(
      termId: 'term-flow',
      classId: 'class-flow',
      subjectId: 'subject-flow',
      assignments: const [
        TeacherAssignment(
          id: 'assignment-next',
          termId: 'term-flow',
          teacherId: 'teacher-next',
          classId: 'class-flow',
          subjectId: 'subject-flow',
          weekMode: WeekMode.weekly,
          lessonCount: 1,
        ),
      ],
    );
    expect(
      (await scheduling.loadPendingSchedulingBaseline('term-flow'))
          ?.existingItems,
      hasLength(1),
    );
    expect(
      (await scheduling.loadSchedulingSnapshot('term-flow')).existingItems,
      isEmpty,
    );
    final replacementPreview = const ScheduleReconciler().preview(
      (await scheduling.loadPendingSchedulingBaseline('term-flow'))!,
      await scheduling.loadSchedulingSnapshot('term-flow'),
    );
    expect(replacementPreview.canApply, isTrue);
    expect(replacementPreview.items.single.assignmentId, 'assignment-next');
    await scheduling.commitScheduleReconciliation(
      termId: 'term-flow',
      expectedFingerprint: replacementPreview.inputFingerprint,
    );

    await school.replaceGradeRequirements(
      gradeId: 'grade-flow',
      requirements: const [
        SubjectRequirement(
          id: 'requirement-flow',
          subjectId: 'subject-flow',
          gradeId: 'grade-flow',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
      ],
    );
    final increasePreview = const ScheduleReconciler().preview(
      (await scheduling.loadPendingSchedulingBaseline('term-flow'))!,
      await scheduling.loadSchedulingSnapshot('term-flow'),
    );
    expect(increasePreview.canApply, isTrue);
    expect(increasePreview.addedCount, 1);
    expect(increasePreview.keptCount, 1);
    await scheduling.commitScheduleReconciliation(
      termId: 'term-flow',
      expectedFingerprint: increasePreview.inputFingerprint,
    );
    final expanded = await scheduling.loadSchedulingSnapshot('term-flow');
    expect(expanded.existingItems, hasLength(2));
    expect(expanded.assignments.single.lessonCount, 2);

    await school.saveTerm(
      expanded.term.copyWith(cycleMode: AcademicTermCycle.alternating),
    );
    await school.replaceGradeRequirements(
      gradeId: 'grade-flow',
      requirements: const [
        SubjectRequirement(
          id: 'per-class',
          subjectId: 'subject-flow',
          gradeId: 'grade-flow',
          classId: 'class-flow',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
      ],
    );
    final cycleBaseline = (await scheduling.loadPendingSchedulingBaseline(
      'term-flow',
    ))!;
    final cycleCurrent = await scheduling.loadSchedulingSnapshot('term-flow');
    final cyclePreview = const ScheduleReconciler().preview(
      cycleBaseline,
      cycleCurrent,
    );
    expect(
      cyclePreview.changes.where((change) => change.group == '科目节数'),
      isEmpty,
    );
    expect(cyclePreview.canApply, isTrue);
    expect(cyclePreview.keptCount, 2);
    expect(
      cycleCurrent.existingItems.map((item) => item.position?.cellKey).toSet(),
      expanded.existingItems.map((item) => item.position?.cellKey).toSet(),
    );
    await scheduling.commitScheduleReconciliation(
      termId: 'term-flow',
      expectedFingerprint: cyclePreview.inputFingerprint,
    );
    final afterCycle = await scheduling.loadSchedulingSnapshot('term-flow');
    expect(
      afterCycle.existingItems.map((item) => item.position?.cellKey).toSet(),
      expanded.existingItems.map((item) => item.position?.cellKey).toSet(),
    );
    expect(await scheduling.loadPendingSchedulingBaseline('term-flow'), isNull);

    final position = expanded.existingItems.first.position!;
    await school.saveFreeSlot(
      FreeSlot(
        id: 'blocked-free-slot',
        scope: FreeSlotScope.schoolClass,
        scopeId: 'class-flow',
        stageId: position.stageId,
        periodTypeId: position.periodTypeId,
        weekday: position.weekday,
        lessonIndex: position.lessonIndex,
        label: '无课',
      ),
    );
    expect(
      await scheduling.loadPendingSchedulingBaseline('term-flow'),
      isNotNull,
    );
    await school.deleteTeacherAssignments(
      termId: 'term-flow',
      assignmentIds: const ['assignment-next'],
    );
    expect(
      (await scheduling.loadSchedulingSnapshot('term-flow')).existingItems,
      isEmpty,
    );
    expect(
      (await scheduling.loadPendingSchedulingBaseline('term-flow'))!
          .existingItems,
      hasLength(2),
    );
  });
}
