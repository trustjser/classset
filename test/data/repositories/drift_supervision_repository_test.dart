import 'dart:io';

import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:class_set/data/repositories/drift_supervision_repository.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v17 升级后缺岗草稿可重开且不生成生效版本', () async {
    final directory = Directory.systemTemp.createTempSync('supervision_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/school.sqlite');
    final oldDatabase = AppDatabase(
      NativeDatabase(
        file,
        setup: (connection) {
          connection.execute(
            'CREATE TABLE academic_terms (id TEXT NOT NULL PRIMARY KEY)',
          );
          connection.execute("INSERT INTO academic_terms (id) VALUES ('term')");
          connection.execute(
            'CREATE TABLE temporary_course_adjustments '
            '(id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL)',
          );
          connection.execute(
            "INSERT INTO temporary_course_adjustments VALUES ('original', 'move')",
          );
          connection.execute('PRAGMA user_version = 17');
        },
      ),
    );
    const post = SupervisionPost(
      id: 'sunday',
      kind: SupervisionKind.eveningStudy,
      name: '晚自习',
      stageId: 'stage',
      weekday: DateTime.sunday,
      periodTypeId: 'evening',
      lessonIndices: [1, 2],
      classIds: ['class'],
    );
    try {
      final repository = DriftSupervisionRepository(
        oldDatabase,
        clock: () => DateTime.fromMicrosecondsSinceEpoch(1),
      );
      final draft = await repository.saveDraft(
        const SupervisionDraft(termId: 'term', posts: [post]),
        expectedRevision: 0,
      );
      expect(draft.revision, 1);
      expect(await repository.loadVersions('term'), isEmpty);
      await expectLater(
        repository.saveDraft(draft, expectedRevision: 0),
        throwsStateError,
      );
    } finally {
      await oldDatabase.close();
    }
    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    final repository = DriftSupervisionRepository(reopened);
    final draft = (await repository.watchDraft('term').first)!;
    expect(draft.posts.single.lessonIndices, [1, 2]);
    expect(draft.assignments, isEmpty);
    expect(await repository.loadVersions('term'), isEmpty);
    final row = await reopened
        .customSelect(
          "SELECT kind FROM temporary_course_adjustments WHERE id = 'original'",
        )
        .getSingle();
    expect(row.read<String>('kind'), 'move');
  });
  test('发布需排齐并重验版本，未来带班保留到协调确认', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final school = DriftSchoolRepository(database);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final effective = monday.add(const Duration(days: 7));
    await school.saveTerm(
      AcademicTerm(
        id: 'school-term',
        title: '测试学期',
        academicYear: '2026',
        semesterLabel: '秋',
        firstTeachingWeekStart: monday,
        teachingWeekCount: 5,
        createdAt: today,
      ),
    );
    final stage = (await school.watchStages('school-term').first).first;
    await school.saveGrade(
      GradeGroup(id: 'grade', stageId: stage.id, name: '一年级', sortOrder: 0),
    );
    await school.saveClass(
      const ClassGroup(id: 'class', gradeId: 'grade', name: '一班', sortOrder: 0),
    );
    await school.saveTeachers(const [
      Teacher(id: 'teacher', name: '张老师', shortName: '张', sortOrder: 0),
    ]);
    await school.saveRoutine(
      StageRoutine(
        stageId: stage.id,
        teachingWeekdays: const {7},
        overrides: const [],
        periodTypes: const [
          LessonPeriodType(
            id: 'evening',
            name: '晚间',
            defaultLessonCount: 2,
            sortOrder: 0,
            lessonTimes: [
              LessonTime(
                lessonIndex: 1,
                label: '晚一',
                startMinute: 1100,
                endMinute: 1140,
              ),
              LessonTime(
                lessonIndex: 2,
                label: '晚二',
                startMinute: 1150,
                endMinute: 1190,
              ),
            ],
          ),
        ],
      ),
    );
    for (final (index, label) in [(1, '课后服务'), (2, FreeSlotLabels.labor)]) {
      await school.saveFreeSlot(
        FreeSlot(
          id: 'activity-$index',
          scope: FreeSlotScope.stage,
          scopeId: stage.id,
          stageId: stage.id,
          periodTypeId: 'evening',
          weekday: 7,
          lessonIndex: index,
          label: label,
        ),
      );
    }
    final draft = await school.saveSupervisionDraft(
      SupervisionDraft(
        termId: 'school-term',
        teacherIds: const {'teacher'},
        posts: [
          SupervisionPost(
            id: 'evening-post',
            kind: SupervisionKind.eveningStudy,
            name: '晚自习',
            stageId: stage.id,
            weekday: 7,
            periodTypeId: 'evening',
            lessonIndices: const [1, 2],
            classIds: const ['class'],
          ),
        ],
      ),
      expectedRevision: 0,
    );
    final missing = await school.previewSupervisionPublish(
      'school-term',
      effective,
    );
    expect(missing.missingPostIds, ['evening-post']);
    await expectLater(
      school.publishSupervision('school-term', missing),
      throwsStateError,
    );
    expect(await school.watchSupervisionVersions('school-term').first, isEmpty);

    await school.saveSupervisionDraft(
      draft.copyWith(assignments: const {'evening-post': 'teacher'}),
      expectedRevision: draft.revision,
    );
    final stale = await school.previewSupervisionPublish(
      'school-term',
      effective,
    );
    expect(stale.errors, isEmpty);
    await school.saveCalendarException(
      CalendarException(
        id: 'holiday',
        termId: 'school-term',
        date: effective,
        kind: CalendarExceptionKind.holiday,
        makeupWeekday: null,
        note: '',
      ),
    );
    await expectLater(
      school.publishSupervision('school-term', stale),
      throwsStateError,
    );
    final preview = await school.previewSupervisionPublish(
      'school-term',
      effective,
    );
    expect(preview.canPublish, isTrue, reason: preview.errors.join('、'));
    await school.publishSupervision('school-term', preview);
    final published =
        (await school.watchSupervisionVersions('school-term').first).single;
    expect(published.occurrences.map((row) => row.teacherName), ['张老师', '张老师']);
    expect(await school.watchSupervisionDraft('school-term').first, isNull);
    expect(
      (await school.loadSchedulingSnapshot('school-term')).visibleSupervision,
      isEmpty,
    );
    expect(
      (await school.loadTemporaryTimetable('school-term'))
          .supervisions
          .first
          .teacherId,
      'teacher',
    );

    final sunday = effective.add(const Duration(days: 6));
    await school.saveCalendarException(
      CalendarException(
        id: 'sunday-holiday',
        termId: 'school-term',
        date: sunday,
        kind: CalendarExceptionKind.holiday,
        makeupWeekday: null,
        note: '停课',
      ),
    );
    final protected = await school.loadTemporaryTimetable('school-term');
    expect(protected.reconciliationPending, isTrue);
    expect(protected.supervisions.first.date, sunday);
    await school.commitScheduleReconciliation(
      termId: 'school-term',
      expectedFingerprint: (await school.loadSchedulingSnapshot('school-term'))
          .inputFingerprint,
    );
    final confirmed = await school.loadTemporaryTimetable('school-term');
    expect(confirmed.reconciliationPending, isFalse);
    expect(
      confirmed.supervisions.any((entry) => entry.date == sunday),
      isFalse,
    );

    await school.saveRoutine(
      StageRoutine(
        stageId: stage.id,
        teachingWeekdays: const {7},
        overrides: const [],
        periodTypes: const [
          LessonPeriodType(
            id: 'evening',
            name: '晚间',
            defaultLessonCount: 1,
            sortOrder: 0,
            lessonTimes: [
              LessonTime(
                lessonIndex: 1,
                label: '晚一',
                startMinute: 1100,
                endMinute: 1140,
              ),
            ],
          ),
        ],
      ),
    );
    final baseline = await school.loadPendingSchedulingBaseline('school-term');
    expect(baseline?.supervision, hasLength(2));
    final updated = await school.loadSchedulingSnapshot('school-term');
    await expectLater(
      school.commitScheduleReconciliation(
        termId: 'school-term',
        expectedFingerprint: updated.inputFingerprint,
      ),
      throwsStateError,
    );
    final oldPost = published.draft.posts.single;
    await school.saveSupervisionDraft(
      published.draft.copyWith(
        revision: 0,
        posts: [
          SupervisionPost(
            id: oldPost.id,
            kind: oldPost.kind,
            name: oldPost.name,
            stageId: stage.id,
            weekday: 7,
            periodTypeId: 'evening',
            lessonIndices: const [1],
            classIds: oldPost.classIds,
          ),
        ],
      ),
      expectedRevision: 0,
    );
    final repair = await school.previewSupervisionPublish('school-term', today);
    expect(repair.canPublish, isTrue, reason: repair.errors.join('、'));
    await school.publishSupervision('school-term', repair);
    expect(await school.loadPendingSchedulingBaseline('school-term'), isNull);
    final current =
        (await school.watchSupervisionVersions('school-term').first).single;
    expect(current.occurrences.single.position.lessonIndex, 1);
  });
}
