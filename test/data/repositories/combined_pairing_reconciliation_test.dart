import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/combined_pairing_fixture.dart';

void main() {
  test('双周教师未合班的实际冲突阻止确认，不改旧课表', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final school = await _legacySchool(database, sharedEvenTeacher: true);
    final before = await school.loadSchedulingSnapshot('t');
    final controller = SchedulingController(school, 't');
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.state.pendingBaseline, isNotNull);
    await controller.previewReconciliation();
    final preview = controller.state.reconciliationPreview!;
    expect(preview.canApply, isFalse);
    expect(
      preview.checks.any((c) => c.code == 'meetingTeacherConflict' && !c.ready),
      isTrue,
    );
    await controller.applyReconciliation();
    final after = await school.loadSchedulingSnapshot('t');
    expect(after.inputFingerprint, before.inputFingerprint);
    expect(await school.loadPendingSchedulingBaseline('t'), isNotNull);
  });

  test('旧版保存的拆散合班自动进入协调，预览不改课表，确认后同步且不重复提示', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final school = await _legacySchool(database);
    final original = await school.loadSchedulingSnapshot('t');
    expect(
      await database.select(database.scheduleReconciliationBaselines).get(),
      isEmpty,
    );
    final controller = SchedulingController(school, 't');
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.state.pendingBaseline, isNotNull);
    expect(controller.state.canStart, isFalse);
    await controller.previewReconciliation();
    expect(controller.state.reconciliationPreview?.canApply, isTrue);
    expect(controller.state.reconciliationPreview?.movedCount, greaterThan(0));
    final beforeConfirm = await school.loadSchedulingSnapshot('t');
    expect(beforeConfirm.inputFingerprint, original.inputFingerprint);
    await controller.applyReconciliation();
    expect(controller.state.error, isNull);
    final saved = await school.loadSchedulingSnapshot('t');
    final meetings = saved.existingItems.map((i) => i.meetingId).toSet();
    expect(meetings, hasLength(4));
    for (final key in meetings) {
      final members = saved.existingItems
          .where((i) => i.meetingId == key)
          .toList();
      expect(members, hasLength(4));
      expect(members.map((i) => i.position?.cellKey).toSet(), hasLength(1));
    }
    expect(await school.loadPendingSchedulingBaseline('t'), isNull);
    expect(
      await database.select(database.scheduleReconciliationBaselines).get(),
      isEmpty,
    );
  });
}

Future<DriftSchoolRepository> _legacySchool(
  db.AppDatabase database, {
  bool sharedEvenTeacher = false,
}) async {
  final school = DriftSchoolRepository(database);
  final fixture = combinedPairingSnapshot(sharedEvenTeacher: sharedEvenTeacher);
  await school.saveTerm(fixture.term);
  // 新学期会自动建立默认学段；使用测试学段替换这些空学段。
  for (final stage in await school.watchStages('t').first) {
    await database.customStatement('DELETE FROM school_stages WHERE id = ?', [
      stage.id,
    ]);
  }
  await school.saveStage(fixture.stages.single);
  await school.saveGrade(fixture.grades.single);
  for (final c in fixture.classes) {
    await school.saveClass(c);
  }
  await school.saveRoutine(fixture.routines.single);
  await school.saveSubjects(fixture.subjects);
  await school.saveTeachers(fixture.teachers);
  await school.replaceGradeRequirements(
    gradeId: 'g',
    requirements: fixture.requirements,
  );
  await school.addTeacherAssignments(
    termId: 't',
    assignments: [
      for (final a in fixture.assignments)
        TeacherAssignment(
          id: a.id,
          termId: a.termId,
          teacherId: a.teacherId,
          classId: a.classId,
          subjectId: a.subjectId,
          weekMode: a.weekMode,
          lessonCount: a.lessonCount,
        ),
    ],
  );
  await school.combineTeacherAssignments(
    termId: 't',
    assignmentIds: ['a-odd', 'b-odd'],
    combinedGroupId: 'combined',
  );
  for (final c in fixture.classes) {
    await school.replaceClassPairings(
      classId: c.id,
      pairings: fixture.pairings.where((p) => p.classId == c.id).toList(),
    );
  }
  final snapshot = await school.loadSchedulingSnapshot('t');
  final problem = const ProblemBuilder().build(snapshot);
  final broken = [
    for (final a in fixture.assignments)
      for (var i = 0; i < 4; i++)
        ScheduleItem(
          id: '${a.id}:${i + 1}',
          termId: 't',
          assignmentId: a.id,
          classId: a.classId,
          teacherId: a.teacherId,
          subjectId: a.subjectId,
          weekMode: a.weekMode,
          combinedGroupId: a.combinedLessonGroupId,
          meetingId: 'pair:${a.classId}:$i',
          position: problem
              .positionsByClass[a.classId]![i + (a.classId == 'a' ? 0 : 4)],
        ),
  ];
  // 复现旧求解器输出的已持久化数据，保留两班不同的课节位置。
  await school.commitScheduleRun(
    ScheduleRun(
      id: 'legacy-run',
      termId: 't',
      inputFingerprint: snapshot.inputFingerprint,
      config: const ScheduleRunConfig(selectedClassIds: {'a', 'b'}, seed: 7),
      report: const ScheduleReport(
        totalItems: 16,
        placedItems: 16,
        coverage: 16,
        preferenceScores: {},
        unplaced: [],
        unmetHardRequirements: [],
        candidateChecks: 0,
      ),
      items: broken,
    ),
    selectedClassIds: {'a', 'b'},
  );
  return school;
}
