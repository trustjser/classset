import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/scheduling/course_scheduler.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('确认临时移课后重新读取生效，常规课表不变，取消后恢复', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final school = DriftSchoolRepository(database);
    await school.saveTerm(
      AcademicTerm(
        id: 'term',
        title: '学期',
        academicYear: '2026',
        semesterLabel: '秋季',
        firstTeachingWeekStart: DateTime(2026, 9, 7),
        teachingWeekCount: 8,
        cycleMode: AcademicTermCycle.everyWeek,
        createdAt: DateTime(2026, 9, 1),
      ),
    );
    final stage = (await school.watchStages('term').first).first;
    await school.saveGrade(
      GradeGroup(id: 'grade', stageId: stage.id, name: '一年级', sortOrder: 0),
    );
    await school.saveClass(
      const ClassGroup(id: 'class', gradeId: 'grade', name: '一班', sortOrder: 0),
    );
    await school.saveSubjects(const [
      Subject(
        id: 'subject',
        termId: 'term',
        name: '数学',
        shortName: '数',
        sortOrder: 0,
      ),
    ]);
    await school.saveTeachers(const [
      Teacher(id: 'teacher', name: '李老师', shortName: '李', sortOrder: 0),
      Teacher(id: 'substitute', name: '王老师', shortName: '王', sortOrder: 1),
    ]);
    await database.customStatement(
      'INSERT INTO subject_requirements (id, subject_id, grade_id, week_mode, lesson_count) VALUES (?, ?, ?, ?, ?)',
      ['requirement', 'subject', 'grade', 'weekly', 1],
    );
    await school.addTeacherAssignments(
      termId: 'term',
      assignments: const [
        TeacherAssignment(
          id: 'assignment',
          termId: 'term',
          teacherId: 'teacher',
          classId: 'class',
          subjectId: 'subject',
          weekMode: WeekMode.weekly,
          lessonCount: 1,
        ),
      ],
    );
    final base = await school.loadSchedulingSnapshot('term');
    final problem = const ProblemBuilder().build(base);
    final run = const CourseScheduler().solve(
      problem,
      config: const ScheduleRunConfig(
        selectedClassIds: {'class'},
        seed: 7,
        strength: ScheduleStrength.fast,
      ),
    );
    await school.commitScheduleRun(run, selectedClassIds: {'class'});
    final before = await school.loadSchedulingSnapshot('term');
    final actual = await school.loadTemporaryTimetable('term');
    final source = actual.lessons.first;
    final target = problem.positionsByClass['class']!.firstWhere(
      (p) => !p.sameCell(source.item.position!),
    );
    final date = DateTime(2026, 9, 7).add(Duration(days: target.weekday - 1));
    final request = TemporaryMoveRequest(
      sourceKey: source.key,
      targetDate: date,
      targetPosition: target,
      reason: '测试',
    );
    final preview = actual.previewMove(request);
    expect(preview.errors, isEmpty);
    await school.commitTemporaryMove(
      termId: 'term',
      request: request,
      expectedRevision: actual.revision,
    );
    final saved = await school.loadTemporaryTimetable('term');
    expect(
      saved.lessons.firstWhere((lesson) => lesson.key == source.key).date,
      date,
    );
    expect(
      (await school.loadSchedulingSnapshot('term'))
          .existingItems
          .single
          .position!
          .cellKey,
      before.existingItems.single.position!.cellKey,
    );
    await expectLater(
      school.commitTemporaryMove(
        termId: 'term',
        request: request,
        expectedRevision: actual.revision,
      ),
      throwsStateError,
    );
    final third = problem.positionsByClass['class']!.firstWhere(
      (p) => !p.sameCell(target) && !p.sameCell(source.item.position!),
    );
    final secondRequest = TemporaryMoveRequest(
      sourceKey: source.key,
      targetDate: DateTime(2026, 9, 7).add(Duration(days: third.weekday - 1)),
      targetPosition: third,
    );
    await school.commitTemporaryMove(
      termId: 'term',
      request: secondRequest,
      expectedRevision: saved.revision,
    );
    final twice = await school.loadTemporaryTimetable('term');
    await expectLater(
      school.cancelTemporaryAdjustment(
        termId: 'term',
        adjustmentId: saved.records.single.id,
        expectedRevision: twice.revision,
      ),
      throwsStateError,
    );
    await school.cancelTemporaryAdjustment(
      termId: 'term',
      adjustmentId: twice.records.last.id,
      expectedRevision: twice.revision,
    );
    final once = await school.loadTemporaryTimetable('term');
    await school.cancelTemporaryAdjustment(
      termId: 'term',
      adjustmentId: saved.records.single.id,
      expectedRevision: once.revision,
    );
    var restored = await school.loadTemporaryTimetable('term');
    expect(
      restored.lessons.firstWhere((lesson) => lesson.key == source.key).date,
      source.date,
    );
    final rangeRequest = TemporaryMoveRequest(
      sourceKey: source.key,
      targetDate: date,
      targetPosition: target,
      rangeStart: DateTime(2026, 9, 7),
      rangeEnd: DateTime(2026, 9, 27),
    );
    final invalidRange = TemporaryMoveRequest(
      sourceKey: source.key,
      targetDate: date.add(const Duration(days: 28)),
      targetPosition: target,
      rangeStart: DateTime(2026, 9, 7),
      rangeEnd: DateTime(2026, 9, 20),
    );
    expect(restored.previewMove(invalidRange).errors, isNotEmpty);
    await expectLater(
      school.commitTemporaryMove(
        termId: 'term',
        request: invalidRange,
        expectedRevision: restored.revision,
      ),
      throwsStateError,
    );
    expect(
      (await school.loadTemporaryTimetable('term')).records.length,
      restored.records.length,
    );
    expect(restored.previewMove(rangeRequest).changes, hasLength(3));
    await school.commitTemporaryMove(
      termId: 'term',
      request: rangeRequest,
      expectedRevision: restored.revision,
    );
    final rangeSaved = await school.loadTemporaryTimetable('term');
    expect(rangeSaved.records.last.needsAttention, isFalse);
    expect(rangeSaved.records.last.changes, hasLength(3));
    await school.cancelTemporaryAdjustment(
      termId: 'term',
      adjustmentId: rangeSaved.records.last.id,
      expectedRevision: rangeSaved.revision,
    );
    restored = await school.loadTemporaryTimetable('term');
    final crossPosition = problem.positionsByClass['class']!.firstWhere((p) =>
      p.weekday == source.item.position!.weekday && !p.sameCell(source.item.position!));
    final crossWeek = TemporaryMoveRequest(sourceKey: source.key,
      targetDate: source.date.add(const Duration(days: 7)), targetPosition: crossPosition,
      rangeStart: DateTime(2026, 9, 7), rangeEnd: DateTime(2026, 9, 27),
      excludedDates: {source.date.add(const Duration(days: 14))});
    expect(restored.previewMove(crossWeek).changes, hasLength(2));
    await school.commitTemporaryMove(termId: 'term', request: crossWeek, expectedRevision: restored.revision);
    final crossSaved = await school.loadTemporaryTimetable('term');
    expect(crossSaved.records.last.needsAttention, isFalse);
    expect(crossSaved.records.last.changes.map((change) => change.before.key).toSet(), hasLength(2));
    await school.cancelTemporaryAdjustment(termId: 'term', adjustmentId: crossSaved.records.last.id,
      expectedRevision: crossSaved.revision);
    restored = await school.loadTemporaryTimetable('term');
    final substitution = TemporarySubstituteRequest(
      sourceKey: source.key,
      teacherId: 'substitute',
      reason: '请假',
      rangeStart: DateTime(2026, 9, 7),
      rangeEnd: DateTime(2026, 9, 27),
    );
    expect(restored.previewSubstitute(substitution).errors, isEmpty);
    await school.commitTemporarySubstitute(
      termId: 'term',
      request: substitution,
      expectedRevision: restored.revision,
    );
    final withSubstitute = await school.loadTemporaryTimetable('term');
    expect(withSubstitute.records.last.needsAttention, isFalse);
    expect(withSubstitute.records.last.changes, hasLength(3));
    expect(
      withSubstitute.lessons
          .firstWhere((lesson) => lesson.key == source.key)
          .item
          .teacherId,
      'substitute',
    );
    expect(
      (await school.loadSchedulingSnapshot('term'))
          .existingItems
          .single
          .teacherId,
      'teacher',
    );
    await school.cancelTemporaryAdjustment(
      termId: 'term',
      adjustmentId: withSubstitute.records.last.id,
      expectedRevision: withSubstitute.revision,
    );
    expect(
      (await school.loadTemporaryTimetable('term')).lessons
          .firstWhere((lesson) => lesson.key == source.key)
          .item
          .teacherId,
      'teacher',
    );

    await database.customStatement(
      'INSERT INTO schedule_items (id, term_id, assignment_id, class_id, teacher_id, subject_id, week_mode, stage_id, weekday, period_type_id, lesson_index) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'second',
        'term',
        'assignment',
        'class',
        'teacher',
        'subject',
        'weekly',
        third.stageId,
        third.weekday,
        third.periodTypeId,
        third.lessonIndex,
      ],
    );
    final swapState = await school.loadTemporaryTimetable('term');
    final other = swapState.lessons.firstWhere(
      (lesson) => lesson.item.id == 'second',
    );
    final swap = TemporarySwapRequest(
      firstKey: source.key,
      secondKey: other.key,
      rangeStart: DateTime(2026, 9, 7),
      rangeEnd: DateTime(2026, 9, 27),
    );
    expect(swapState.previewSwap(swap).errors, isEmpty);
    await school.commitTemporarySwap(
      termId: 'term',
      request: swap,
      expectedRevision: swapState.revision,
    );
    final swapped = await school.loadTemporaryTimetable('term');
    expect(swapped.records.last.needsAttention, isFalse);
    expect(swapped.records.last.changes, hasLength(6));
    expect(
      swapped.lessons.firstWhere((lesson) => lesson.key == source.key).date,
      other.date,
    );
    expect(
      swapped.lessons.firstWhere((lesson) => lesson.key == other.key).date,
      source.date,
    );
    await school.cancelTemporaryAdjustment(
      termId: 'term',
      adjustmentId: swapped.records.last.id,
      expectedRevision: swapped.revision,
    );
    final afterSwapCancel = await school.loadTemporaryTimetable('term');
    expect(
      afterSwapCancel.lessons
          .firstWhere((lesson) => lesson.key == source.key)
          .date,
      source.date,
    );
    expect(
      afterSwapCancel.lessons
          .firstWhere((lesson) => lesson.key == other.key)
          .date,
      other.date,
    );

    await school.commitTemporaryMove(
      termId: 'term',
      request: request,
      expectedRevision: afterSwapCancel.revision,
    );
    await database.customStatement(
      'UPDATE schedule_items SET weekday = ?, period_type_id = ?, lesson_index = ? WHERE id = ?',
      [target.weekday, target.periodTypeId, target.lessonIndex, 'second'],
    );
    final conflictingBase = await school.loadTemporaryTimetable('term');
    expect(conflictingBase.records.last.needsAttention, isTrue);
    expect(
      conflictingBase.lessons
          .firstWhere((lesson) => lesson.key == source.key)
          .date,
      source.date,
    );
    await school.cancelTemporaryAdjustment(
      termId: 'term',
      adjustmentId: conflictingBase.records.last.id,
      expectedRevision: conflictingBase.revision,
    );
    final afterDiscard = await school.loadTemporaryTimetable('term');
    expect(afterDiscard.records.last.cancelledAt, isNotNull);
    await database.customStatement('DELETE FROM schedule_items WHERE id = ?', [
      'second',
    ]);
    await database.customStatement(
      'INSERT INTO class_groups (id, grade_id, name, sort_order) VALUES (?, ?, ?, ?)',
      ['class2', 'grade', '二班', 1],
    );
    await database.customStatement(
      'UPDATE schedule_items SET meeting_id = ?, combined_group_id = ? WHERE id = ?',
      ['meeting', 'group', source.item.id],
    );
    final originalPosition = source.item.position!;
    await database.customStatement(
      'INSERT INTO schedule_items (id, term_id, assignment_id, class_id, teacher_id, subject_id, week_mode, meeting_id, combined_group_id, stage_id, weekday, period_type_id, lesson_index) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'group-second',
        'term',
        'assignment',
        'class2',
        'teacher',
        'subject',
        'weekly',
        'meeting',
        'group',
        originalPosition.stageId,
        originalPosition.weekday,
        originalPosition.periodTypeId,
        originalPosition.lessonIndex,
      ],
    );
    final groupState = await school.loadTemporaryTimetable('term');
    expect(groupState.previewMove(request).changes, hasLength(2));
    await school.commitTemporaryMove(
      termId: 'term',
      request: request,
      expectedRevision: groupState.revision,
    );
    final groupSaved = await school.loadTemporaryTimetable('term');
    expect(groupSaved.records.last.needsAttention, isFalse);
    expect(groupSaved.records.last.changes, hasLength(2));
    await school.cancelTemporaryAdjustment(
      termId: 'term',
      adjustmentId: groupSaved.records.last.id,
      expectedRevision: groupSaved.revision,
    );
    final groupRestored = await school.loadTemporaryTimetable('term');
    expect(
      groupRestored.lessons
          .where(
            (lesson) =>
                lesson.item.meetingId == 'meeting' &&
                lesson.date == source.date,
          )
          .length,
      2,
    );
    final groupSub = TemporarySubstituteRequest(
      sourceKey: source.key,
      teacherId: 'substitute',
    );
    expect(groupRestored.previewSubstitute(groupSub).changes, hasLength(2));
    await school.commitTemporarySubstitute(
      termId: 'term',
      request: groupSub,
      expectedRevision: groupRestored.revision,
    );
    final groupSubSaved = await school.loadTemporaryTimetable('term');
    expect(groupSubSaved.records.last.needsAttention, isFalse);
    expect(groupSubSaved.records.last.changes, hasLength(2));
    await school.cancelTemporaryAdjustment(
      termId: 'term',
      adjustmentId: groupSubSaved.records.last.id,
      expectedRevision: groupSubSaved.revision,
    );
    final groupSubRestored = await school.loadTemporaryTimetable('term');
    expect(
      groupSubRestored.lessons
          .where(
            (lesson) =>
                lesson.item.meetingId == 'meeting' &&
                lesson.date == source.date,
          )
          .map((lesson) => lesson.item.teacherId)
          .toSet(),
      {'teacher'},
    );
    for (final entry in [
      ('group-other-one', 'class'),
      ('group-other-two', 'class2'),
    ]) {
      await database.customStatement(
        'INSERT INTO schedule_items (id, term_id, assignment_id, class_id, teacher_id, subject_id, week_mode, meeting_id, combined_group_id, stage_id, weekday, period_type_id, lesson_index) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          entry.$1,
          'term',
          'assignment',
          entry.$2,
          'teacher',
          'subject',
          'weekly',
          'other-meeting',
          'other-group',
          third.stageId,
          third.weekday,
          third.periodTypeId,
          third.lessonIndex,
        ],
      );
    }
    final groupSwapState = await school.loadTemporaryTimetable('term');
    final groupTarget = groupSwapState.lessons.firstWhere(
      (lesson) => lesson.item.id == 'group-other-one',
    );
    final groupSwap = TemporarySwapRequest(
      firstKey: source.key,
      secondKey: groupTarget.key,
    );
    expect(groupSwapState.previewSwap(groupSwap).changes, hasLength(4));
    await school.commitTemporarySwap(
      termId: 'term',
      request: groupSwap,
      expectedRevision: groupSwapState.revision,
    );
    final groupSwapSaved = await school.loadTemporaryTimetable('term');
    expect(groupSwapSaved.records.last.needsAttention, isFalse);
    expect(groupSwapSaved.records.last.changes, hasLength(4));
    await database.transaction(() async {
      await database.customStatement('CREATE TEMP TABLE reorder_items AS SELECT * FROM schedule_items');
      await database.customStatement('DELETE FROM schedule_items');
      await database.customStatement('INSERT INTO schedule_items SELECT * FROM reorder_items ORDER BY id DESC');
      await database.customStatement('DROP TABLE reorder_items');
    });
    final reordered = await school.loadTemporaryTimetable('term');
    expect(reordered.records.last.needsAttention, isFalse);
    await school.cancelTemporaryAdjustment(
      termId: 'term',
      adjustmentId: groupSwapSaved.records.last.id,
      expectedRevision: reordered.revision,
    );
    final groupSwapRestored = await school.loadTemporaryTimetable('term');
    expect(
      groupSwapRestored.lessons
          .where(
            (lesson) =>
                lesson.item.meetingId == 'meeting' &&
                lesson.date == source.date,
          )
          .length,
      2,
    );
    final oldRoutine = groupSwapRestored.snapshot.routines.first;
    await school.saveRoutine(StageRoutine(stageId: oldRoutine.stageId,
      teachingWeekdays: oldRoutine.teachingWeekdays.where((day) => day != originalPosition.weekday).toSet(),
      periodTypes: oldRoutine.periodTypes, overrides: oldRoutine.overrides));
    final pendingState = await school.loadTemporaryTimetable('term');
    expect(pendingState.reconciliationPending, isTrue);
    expect(pendingState.snapshot.routines.first.teachingWeekdays, oldRoutine.teachingWeekdays);
    expect(pendingState.lessons.any((lesson) => lesson.key == source.key), isTrue);
    expect(pendingState.previewMove(request).errors, isNotEmpty);
  });
}
