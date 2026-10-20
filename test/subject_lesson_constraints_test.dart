import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_lesson_constraint.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repository;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftSchoolRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seed() async {
    await repository.saveTerm(
      AcademicTerm(
        id: 'term',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    await repository.saveSubjects([
      const Subject(id: 'subject', name: '语文', shortName: '语', sortOrder: 0),
    ]);
    await repository.saveStage(
      const SchoolStage(
        id: 'stage_0',
        termId: 'term',
        name: '小学部',
        sortOrder: 0,
      ),
    );
    await repository.saveGrade(
      const GradeGroup(
        id: 'grade',
        stageId: 'stage_0',
        name: '一年级',
        sortOrder: 0,
      ),
    );
    await repository.saveClass(
      const ClassGroup(
        id: 'class',
        gradeId: 'grade',
        name: '一（1）班',
        sortOrder: 0,
      ),
    );
  }

  test('按字段解析范围与星期继承，空值继承而显式零覆盖', () {
    const rows = [
      SubjectLessonConstraint(
        id: 'stage-default',
        subjectId: 'subject',
        scope: FreeSlotScope.stage,
        scopeId: 'stage',
        stageId: 'stage',
        weekday: null,
        maximumDailyLessons: 6,
        maximumDailyConsecutivePairs: 4,
        minimumWeeklyConsecutivePairs: 1,
      ),
      SubjectLessonConstraint(
        id: 'grade-monday',
        subjectId: 'subject',
        scope: FreeSlotScope.grade,
        scopeId: 'grade',
        stageId: 'stage',
        weekday: 1,
        maximumDailyLessons: 5,
      ),
      SubjectLessonConstraint(
        id: 'class-default',
        subjectId: 'subject',
        scope: FreeSlotScope.schoolClass,
        scopeId: 'class',
        stageId: 'stage',
        weekday: null,
        minimumDailyLessons: 2,
        maximumDailyLessons: 0,
        minimumDailyConsecutivePairs: 0,
        minimumWeeklyConsecutivePairs: 0,
      ),
      SubjectLessonConstraint(
        id: 'class-monday',
        subjectId: 'subject',
        scope: FreeSlotScope.schoolClass,
        scopeId: 'class',
        stageId: 'stage',
        weekday: 1,
        minimumDailyLessons: 0,
        minimumDailyConsecutivePairs: 2,
      ),
    ];

    final monday = resolveSubjectLessonConstraints(
      constraints: rows,
      scope: FreeSlotScope.schoolClass,
      scopeId: 'class',
      stageId: 'stage',
      parentGradeId: 'grade',
      weekday: 1,
    );
    expect(monday.minimumDailyLessons, 0);
    expect(monday.maximumDailyLessons, 0);
    expect(monday.minimumDailyConsecutivePairs, 2);
    expect(monday.maximumDailyConsecutivePairs, 4);
    expect(monday.minimumWeeklyConsecutivePairs, 0);

    final tuesday = resolveSubjectLessonConstraints(
      constraints: rows,
      scope: FreeSlotScope.schoolClass,
      scopeId: 'class',
      stageId: 'stage',
      parentGradeId: 'grade',
      weekday: 2,
    );
    expect(tuesday.minimumDailyLessons, 2);
    expect(tuesday.maximumDailyLessons, 0);
    expect(tuesday.minimumDailyConsecutivePairs, 0);
    expect(tuesday.maximumDailyConsecutivePairs, 4);
    expect(tuesday.minimumWeeklyConsecutivePairs, 0);
  });

  test('替换限制只影响指定范围，并保留其他范围记录', () async {
    await seed();
    final rows = [
      SubjectLessonConstraint(
        id: '',
        subjectId: 'subject',
        scope: FreeSlotScope.stage,
        scopeId: 'stage_0',
        stageId: 'stage_0',
        weekday: null,
        maximumDailyLessons: 7,
      ),
    ];
    await repository.replaceSubjectLessonConstraints(
      subjectId: 'subject',
      scope: FreeSlotScope.stage,
      scopeId: 'stage_0',
      stageId: 'stage_0',
      constraints: rows,
    );
    await repository.replaceSubjectLessonConstraints(
      subjectId: 'subject',
      scope: FreeSlotScope.grade,
      scopeId: 'grade',
      stageId: 'stage_0',
      constraints: [
        SubjectLessonConstraint(
          id: '',
          subjectId: 'subject',
          scope: FreeSlotScope.grade,
          scopeId: 'grade',
          stageId: 'stage_0',
          weekday: 1,
          minimumDailyLessons: 2,
          maximumDailyConsecutivePairs: 3,
        ),
      ],
    );

    final saved = await repository
        .watchLessonConstraintsForSubject('subject')
        .first;
    expect(saved, hasLength(2));
    expect(
      saved
          .where((row) => row.scope == FreeSlotScope.stage)
          .single
          .maximumDailyLessons,
      7,
    );
    expect(
      saved
          .where((row) => row.scope == FreeSlotScope.grade)
          .single
          .minimumDailyLessons,
      2,
    );
    expect(
      saved
          .where((row) => row.scope == FreeSlotScope.grade)
          .single
          .maximumDailyConsecutivePairs,
      3,
    );

    await repository.replaceSubjectLessonConstraints(
      subjectId: 'subject',
      scope: FreeSlotScope.grade,
      scopeId: 'grade',
      stageId: 'stage_0',
      constraints: const [],
    );
    final afterClear = await repository
        .watchLessonConstraintsForSubject('subject')
        .first;
    expect(afterClear, hasLength(1));
    expect(afterClear.single.scope, FreeSlotScope.stage);
  });

  test('拒绝全校范围与无效限制数值', () async {
    await seed();
    expect(
      () => SubjectLessonConstraint.validate([
        const SubjectLessonConstraint(
          id: '',
          subjectId: 'subject',
          scope: FreeSlotScope.grade,
          scopeId: 'grade',
          stageId: 'stage_0',
          weekday: null,
          minimumDailyLessons: 4,
          maximumDailyLessons: 3,
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => SubjectLessonConstraint.validate([
        const SubjectLessonConstraint(
          id: '',
          subjectId: 'subject',
          scope: FreeSlotScope.grade,
          scopeId: 'grade',
          stageId: 'stage_0',
          weekday: 1,
          minimumDailyConsecutivePairs: 3,
          maximumDailyConsecutivePairs: 2,
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => SubjectLessonConstraint.validate([
        const SubjectLessonConstraint(
          id: '',
          subjectId: 'subject',
          scope: FreeSlotScope.grade,
          scopeId: 'grade',
          stageId: 'stage_0',
          weekday: null,
          minimumWeeklyConsecutivePairs: 2,
          maximumWeeklyConsecutivePairs: 1,
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => SubjectLessonConstraint.validate([
        const SubjectLessonConstraint(
          id: '',
          subjectId: 'subject',
          scope: FreeSlotScope.grade,
          scopeId: 'grade',
          stageId: 'stage_0',
          weekday: 1,
          maximumDailyLessons: -1,
        ),
      ]),
      throwsArgumentError,
    );
    await expectLater(
      repository.replaceSubjectLessonConstraints(
        subjectId: 'subject',
        scope: FreeSlotScope.school,
        scopeId: 'term',
        stageId: 'stage_0',
        constraints: const [],
      ),
      throwsArgumentError,
    );
    expect(
      () => SubjectLessonConstraint.validate([
        const SubjectLessonConstraint(
          id: '',
          subjectId: 'subject',
          scope: FreeSlotScope.grade,
          scopeId: 'grade',
          stageId: 'stage',
          weekday: 1,
          minimumWeeklyConsecutivePairs: 1,
        ),
      ]),
      throwsArgumentError,
    );
  });

  test('删除班级或年级时清理对应范围的科目限制', () async {
    await seed();

    Future<void> saveRange(FreeSlotScope scope, String scopeId) =>
        repository.replaceSubjectLessonConstraints(
          subjectId: 'subject',
          scope: scope,
          scopeId: scopeId,
          stageId: 'stage_0',
          constraints: [
            SubjectLessonConstraint(
              id: '',
              subjectId: 'subject',
              scope: scope,
              scopeId: scopeId,
              stageId: 'stage_0',
              weekday: null,
              maximumDailyLessons: 4,
            ),
          ],
        );

    await saveRange(FreeSlotScope.stage, 'stage_0');
    await saveRange(FreeSlotScope.grade, 'grade');
    await saveRange(FreeSlotScope.schoolClass, 'class');

    await repository.deleteClass('class');
    var saved = await repository
        .watchLessonConstraintsForSubject('subject')
        .first;
    expect(
      saved.map((row) => row.scope),
      containsAll([FreeSlotScope.stage, FreeSlotScope.grade]),
    );
    expect(
      saved.map((row) => row.scope),
      isNot(contains(FreeSlotScope.schoolClass)),
    );

    await repository.deleteGrade('grade');
    saved = await repository.watchLessonConstraintsForSubject('subject').first;
    expect(saved, hasLength(1));
    expect(saved.single.scope, FreeSlotScope.stage);
  });
}
