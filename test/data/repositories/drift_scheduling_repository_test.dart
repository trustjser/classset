import 'dart:io';

import 'package:class_set/data/backup/local_backup_service.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_scheduling_repository.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/scheduling/course_scheduler.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('需求与任课经过求解、提交后可重新读取课表', () async {
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
  });
}
