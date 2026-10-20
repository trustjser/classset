import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/subject_parallel_limit.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repository;
  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftSchoolRepository(database);
    for (final term in ['a', 'b']) {
      await repository.saveTerm(
        AcademicTerm(
          id: term,
          title: term,
          academicYear: '2026',
          semesterLabel: '秋季',
          firstTeachingWeekStart: null,
          teachingWeekCount: 20,
          createdAt: DateTime(2026),
        ),
      );
      await repository.saveStage(
        SchoolStage(
          id: '${term}_stage',
          termId: term,
          name: '初中',
          sortOrder: 1,
        ),
      );
      await repository.saveGrade(
        GradeGroup(
          id: '${term}_grade',
          stageId: '${term}_stage',
          name: '一年级',
          sortOrder: 0,
        ),
      );
      await repository.saveClass(
        ClassGroup(
          id: '${term}_class',
          gradeId: '${term}_grade',
          name: '一班',
          sortOrder: 0,
        ),
      );
    }
    await repository.saveSubjects([
      const Subject(id: 'music', name: '音乐', shortName: '音', sortOrder: 0),
      const Subject(id: 'art', name: '美术', shortName: '美', sortOrder: 1),
    ]);
    await repository.savePublicRooms([
      const PublicRoom(
        id: 'room',
        name: '音乐室',
        roomCount: 2,
        capacityPerRoom: 1,
        sortOrder: 0,
      ),
    ]);
  });
  tearDown(() => database.close());

  SubjectRoomAssignment assignment(
    FreeSlotScope scope, {
    String term = 'a',
    String subject = 'music',
    String? roomId = 'room',
  }) => SubjectRoomAssignment(
    id: '',
    subjectId: subject,
    termId: term,
    stageId: '${term}_stage',
    scope: scope,
    scopeId:
        '${term}_${scope == FreeSlotScope.schoolClass ? 'class' : scope.name}',
    roomId: roomId,
  );
  Future<void> saveAssignment(SubjectRoomAssignment row) =>
      repository.replaceSubjectRoomAssignments(
        subjectId: row.subjectId,
        termId: row.termId,
        stageId: row.stageId,
        scope: row.scope,
        scopeId: row.scopeId,
        assignments: [row],
      );
  SubjectParallelLimit limit(
    FreeSlotScope scope,
    int max, {
    String term = 'a',
  }) => SubjectParallelLimit(
    id: '',
    subjectId: 'music',
    termId: term,
    stageId: '${term}_stage',
    scope: scope,
    scopeId: '${term}_${scope.name}',
    maxParallelLessons: max,
  );
  Future<void> saveLimit(SubjectParallelLimit row) =>
      repository.replaceSubjectParallelLimits(
        subjectId: row.subjectId,
        termId: row.termId,
        stageId: row.stageId,
        scope: row.scope,
        scopeId: row.scopeId,
        limits: [row],
      );

  test('room CRUD keeps stable IDs, ordering and positive values', () async {
    await repository.savePublicRooms([
      const PublicRoom(
        id: 'second',
        name: ' 实验室 ',
        roomCount: 3,
        capacityPerRoom: 2,
        sortOrder: -1,
      ),
      const PublicRoom(
        id: 'room',
        name: '新音乐室',
        roomCount: 4,
        capacityPerRoom: 2,
        sortOrder: 0,
      ),
    ]);
    var rooms = await repository.watchPublicRooms().first;
    expect(rooms.map((row) => row.id), ['second', 'room']);
    expect(rooms.first.name, '实验室');
    expect(rooms.last.roomCount, 4);
    expect(rooms.last.capacityPerRoom, 2);
    for (final room in [
      const PublicRoom(
        id: 'bad',
        name: 'x',
        roomCount: 0,
        capacityPerRoom: 1,
        sortOrder: 0,
      ),
      const PublicRoom(
        id: 'bad',
        name: 'x',
        roomCount: 1,
        capacityPerRoom: -1,
        sortOrder: 0,
      ),
      const PublicRoom(
        id: '',
        name: 'x',
        roomCount: 1,
        capacityPerRoom: 1,
        sortOrder: 0,
      ),
      const PublicRoom(
        id: 'bad',
        name: ' ',
        roomCount: 1,
        capacityPerRoom: 1,
        sortOrder: 0,
      ),
    ]) {
      await expectLater(
        repository.savePublicRooms([room]),
        throwsArgumentError,
      );
    }
    await repository.deletePublicRoom('second');
    rooms = await repository.watchPublicRooms().first;
    expect(rooms.single.id, 'room');
  });

  test('missing assignment inherits, explicit null blocks inheritance and clearing restores it', () async {
    await saveAssignment(assignment(FreeSlotScope.stage));
    await saveAssignment(assignment(FreeSlotScope.grade, roomId: null));
    String? resolved(List<SubjectRoomAssignment> rows) =>
        resolveSubjectRoomAssignment(
          assignments: rows,
          subjectId: 'music',
          termId: 'a',
          stageId: 'a_stage',
          scope: FreeSlotScope.schoolClass,
          scopeId: 'a_class',
          parentGradeId: 'a_grade',
        )?.roomId;
    var rows = await repository.watchSubjectRoomAssignments('a').first;
    expect(rows, hasLength(2));
    expect(resolved(rows), isNull);
    await repository.replaceSubjectRoomAssignments(
      subjectId: 'music',
      termId: 'a',
      stageId: 'a_stage',
      scope: FreeSlotScope.grade,
      scopeId: 'a_grade',
      assignments: [],
    );
    rows = await repository.watchSubjectRoomAssignments('a').first;
    expect(resolved(rows), 'room');
    await saveAssignment(assignment(FreeSlotScope.schoolClass, roomId: null));
    rows = await repository.watchSubjectRoomAssignments('a').first;
    expect(resolved(rows), isNull);
  });

  test(
    'replacement isolates subjects, terms and scopes and enforces context',
    () async {
      await saveAssignment(assignment(FreeSlotScope.stage));
      await saveAssignment(assignment(FreeSlotScope.stage, term: 'b'));
      await saveAssignment(assignment(FreeSlotScope.stage, subject: 'art'));
      await saveAssignment(assignment(FreeSlotScope.stage, roomId: null));
      expect(
        await repository.watchSubjectRoomAssignments('b').first,
        hasLength(1),
      );
      final rows = await repository.watchSubjectRoomAssignments('a').first;
      expect(rows, hasLength(2));
      expect(rows.singleWhere((r) => r.subjectId == 'music').roomId, isNull);
      expect(rows.singleWhere((r) => r.subjectId == 'art').roomId, 'room');
      await expectLater(
        repository.replaceSubjectRoomAssignments(
          subjectId: 'music',
          termId: 'b',
          stageId: 'a_stage',
          scope: FreeSlotScope.grade,
          scopeId: 'a_grade',
          assignments: [],
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.replaceSubjectRoomAssignments(
          subjectId: 'music',
          termId: 'a',
          stageId: 'a_stage',
          scope: FreeSlotScope.grade,
          scopeId: 'b_grade',
          assignments: [],
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.replaceSubjectRoomAssignments(
          subjectId: 'music',
          termId: 'a',
          stageId: 'a_stage',
          scope: FreeSlotScope.school,
          scopeId: 'a',
          assignments: [],
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.replaceSubjectRoomAssignments(
          subjectId: 'music',
          termId: 'a',
          stageId: 'a_stage',
          scope: FreeSlotScope.stage,
          scopeId: 'a_stage',
          assignments: [
            assignment(FreeSlotScope.stage),
            assignment(FreeSlotScope.stage),
          ],
        ),
        throwsArgumentError,
      );
      await expectLater(
        saveAssignment(assignment(FreeSlotScope.stage, roomId: 'missing')),
        throwsA(anything),
      );
      expect(
        (await repository.watchSubjectRoomAssignments('a').first)
            .singleWhere((r) => r.subjectId == 'music')
            .roomId,
        isNull,
      );
    },
  );

  test(
    'grade parallel cap replaces stage fallback and term streams stay isolated',
    () async {
      await saveLimit(limit(FreeSlotScope.stage, 2));
      await saveLimit(limit(FreeSlotScope.grade, 4));
      await saveLimit(limit(FreeSlotScope.stage, 7, term: 'b'));
      final rows = await repository.watchSubjectParallelLimits('a').first;
      int? resolve(String grade) => resolveSubjectParallelLimit(
        limits: rows,
        subjectId: 'music',
        termId: 'a',
        stageId: 'a_stage',
        gradeId: grade,
      )?.maxParallelLessons;
      expect(resolve('a_grade'), 4);
      expect(resolve('other'), 2);
      expect(
        (await repository.watchSubjectParallelLimits('b').first)
            .single
            .maxParallelLessons,
        7,
      );
      await saveLimit(limit(FreeSlotScope.grade, 3));
      expect(
        (await repository.watchSubjectParallelLimits('a').first)
            .singleWhere((r) => r.scope == FreeSlotScope.grade)
            .maxParallelLessons,
        3,
      );
      await expectLater(
        saveLimit(limit(FreeSlotScope.grade, 0)),
        throwsArgumentError,
      );
      await expectLater(
        repository.replaceSubjectParallelLimits(
          subjectId: 'music',
          termId: 'a',
          stageId: 'a_stage',
          scope: FreeSlotScope.schoolClass,
          scopeId: 'a_class',
          limits: [],
        ),
        throwsArgumentError,
      );
      await repository.replaceSubjectParallelLimits(
        subjectId: 'music',
        termId: 'a',
        stageId: 'a_stage',
        scope: FreeSlotScope.grade,
        scopeId: 'a_grade',
        limits: [],
      );
      expect(
        (await repository.watchSubjectParallelLimits('a').first)
            .single
            .maxParallelLessons,
        2,
      );
    },
  );

  test('room deletion cleans referencing assignments across terms but keeps explicit no-room and limits', () async {
    await saveAssignment(assignment(FreeSlotScope.stage));
    await saveAssignment(assignment(FreeSlotScope.grade, roomId: null));
    await saveAssignment(assignment(FreeSlotScope.stage, term: 'b'));
    await saveLimit(limit(FreeSlotScope.stage, 2));
    await repository.deletePublicRoom('room');
    expect(
      (await repository.watchSubjectRoomAssignments('a').first).single.scope,
      FreeSlotScope.grade,
    );
    expect(await repository.watchSubjectRoomAssignments('b').first, isEmpty);
    expect(
      await repository.watchSubjectParallelLimits('a').first,
      hasLength(1),
    );
  });

  test('combined settings replace a subject atomically and references include other terms', () async {
    await saveAssignment(assignment(FreeSlotScope.stage, term: 'b'));
    await saveAssignment(assignment(FreeSlotScope.stage, subject: 'art'));
    await repository.replaceSubjectRoomSettings(
      termId: 'a',
      subjectId: 'music',
      assignments: [assignment(FreeSlotScope.grade)],
      limits: [limit(FreeSlotScope.stage, 3)],
    );
    expect(await repository.watchRoomReferences('room').first, hasLength(3));
    await expectLater(
      repository.replaceSubjectRoomSettings(
        termId: 'a',
        subjectId: 'music',
        assignments: [assignment(FreeSlotScope.stage, roomId: 'missing')],
        limits: [limit(FreeSlotScope.stage, 5)],
      ),
      throwsA(anything),
    );
    expect(
      (await repository.watchSubjectParallelLimits('a').first)
          .single
          .maxParallelLessons,
      3,
    );
    expect(
      (await repository.watchSubjectRoomAssignments('a').first)
          .singleWhere((r) => r.subjectId == 'music')
          .scope,
      FreeSlotScope.grade,
    );
    await repository.replaceSubjectRoomSettings(
      termId: 'a',
      subjectId: 'music',
      assignments: [],
      limits: [],
    );
    expect(await repository.watchSubjectParallelLimits('a').first, isEmpty);
    expect(
      (await repository.watchSubjectRoomAssignments('a').first)
          .single
          .subjectId,
      'art',
    );
    expect(
      (await repository.watchRoomReferences('room').first).map((r) => r.termId),
      containsAll(['a', 'b']),
    );
  });

  test(
    'class, grade, subject and term deletions remove scoped rules',
    () async {
      for (final scope in [
        FreeSlotScope.stage,
        FreeSlotScope.grade,
        FreeSlotScope.schoolClass,
      ]) {
        await saveAssignment(assignment(scope));
      }
      await saveLimit(limit(FreeSlotScope.stage, 2));
      await saveLimit(limit(FreeSlotScope.grade, 3));
      await repository.deleteClass('a_class');
      expect(
        await repository.watchSubjectRoomAssignments('a').first,
        hasLength(2),
      );
      await repository.deleteGrade('a_grade');
      expect(
        (await repository.watchSubjectRoomAssignments('a').first).single.scope,
        FreeSlotScope.stage,
      );
      expect(
        (await repository.watchSubjectParallelLimits('a').first).single.scope,
        FreeSlotScope.stage,
      );
      await repository.deleteSubject('music');
      expect(await repository.watchSubjectRoomAssignments('a').first, isEmpty);
      expect(await repository.watchSubjectParallelLimits('a').first, isEmpty);
      await repository.saveSubjects([
        const Subject(id: 'music', name: '音乐', shortName: '音', sortOrder: 0),
      ]);
      await saveAssignment(assignment(FreeSlotScope.stage, term: 'b'));
      await saveLimit(limit(FreeSlotScope.stage, 2, term: 'b'));
      await repository.deleteTerm('b');
      expect(await repository.watchSubjectRoomAssignments('b').first, isEmpty);
      expect(await repository.watchSubjectParallelLimits('b').first, isEmpty);
      expect(await repository.watchPublicRooms().first, hasLength(1));
    },
  );
  test(
    'moving a grade or class updates binding term and stage context',
    () async {
      await saveAssignment(assignment(FreeSlotScope.grade));
      await saveAssignment(assignment(FreeSlotScope.schoolClass));
      await saveLimit(limit(FreeSlotScope.grade, 3));
      await repository.saveGrade(
        const GradeGroup(
          id: 'a_grade',
          stageId: 'b_stage',
          name: '一年级',
          sortOrder: 0,
        ),
      );
      expect(await repository.watchSubjectRoomAssignments('a').first, isEmpty);
      final moved = await repository.watchSubjectRoomAssignments('b').first;
      expect(moved, hasLength(2));
      expect(moved.map((r) => r.stageId).toSet(), {'b_stage'});
      expect(
        (await repository.watchSubjectParallelLimits('b').first).single.stageId,
        'b_stage',
      );
      await repository.saveGrade(
        const GradeGroup(
          id: 'new_grade',
          stageId: 'a_stage',
          name: '二年级',
          sortOrder: 1,
        ),
      );
      await repository.saveClass(
        const ClassGroup(
          id: 'a_class',
          gradeId: 'new_grade',
          name: '一班',
          sortOrder: 0,
        ),
      );
      expect(
        (await repository.watchSubjectRoomAssignments('a').first)
            .single
            .scopeId,
        'a_class',
      );
      expect(
        (await repository.watchSubjectRoomAssignments('b').first)
            .single
            .scopeId,
        'a_grade',
      );
    },
  );
}
