import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
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

  Future<AcademicTerm> createTerm() async {
    final term = AcademicTerm(
      id: 'term1',
      title: '2026 学年 · 秋季学期',
      academicYear: '2026-2027',
      semesterLabel: '秋季学期',
      firstTeachingWeekStart: DateTime(2026, 9, 1),
      teachingWeekCount: 20,
      createdAt: DateTime(2026, 8, 1),
    );
    await repository.saveTerm(term);
    return term;
  }

  test('全校科目预设只替换对应学段并保留其他学段', () async {
    await createTerm();
    await repository.saveSubjects([
      const Subject(id: 'subject1', name: '语文', shortName: '语', sortOrder: 0),
    ]);
    final firstStage = (await repository.watchStages('term1').first).single;
    await repository.saveStage(
      const SchoolStage(
        id: 'stage2',
        termId: 'term1',
        name: '高中部',
        sortOrder: 1,
      ),
    );
    final firstRoutine = (await repository.watchRoutine(firstStage.id).first)!;
    final secondRoutine = (await repository.watchRoutine('stage2').first)!;
    final firstMorning = firstRoutine.periodTypes.firstWhere(
      (period) => period.name == '上午',
    );
    final secondMorning = secondRoutine.periodTypes.firstWhere(
      (period) => period.name == '上午',
    );

    await repository.replaceSubjectPresets(
      subjectId: 'subject1',
      termId: 'term1',
      scope: FreeSlotScope.school,
      scopeId: 'term1',
      stageId: firstStage.id,
      presets: [
        SubjectPreset(
          id: '',
          subjectId: 'subject1',
          scope: FreeSlotScope.school,
          scopeId: 'term1',
          stageId: firstStage.id,
          weekday: 1,
          periodTypeId: firstMorning.id,
          lessonIndex: 1,
          value: PresetValue.prefer,
        ),
      ],
    );
    await repository.replaceSubjectPresets(
      subjectId: 'subject1',
      termId: 'term1',
      scope: FreeSlotScope.school,
      scopeId: 'term1',
      stageId: 'stage2',
      presets: [
        SubjectPreset(
          id: '',
          subjectId: 'subject1',
          scope: FreeSlotScope.school,
          scopeId: 'term1',
          stageId: 'stage2',
          weekday: 2,
          periodTypeId: secondMorning.id,
          lessonIndex: 2,
          value: PresetValue.forbid,
        ),
      ],
    );

    var presets = await repository.watchAllPresets().first;
    expect(presets, hasLength(2));
    expect(
      presets.singleWhere((preset) => preset.stageId == firstStage.id),
      isA<SubjectPreset>()
          .having((preset) => preset.weekday, 'weekday', 1)
          .having((preset) => preset.value, 'value', PresetValue.prefer),
    );
    expect(
      presets.singleWhere((preset) => preset.stageId == 'stage2'),
      isA<SubjectPreset>()
          .having((preset) => preset.weekday, 'weekday', 2)
          .having((preset) => preset.periodTypeId, 'period', secondMorning.id)
          .having((preset) => preset.value, 'value', PresetValue.forbid),
    );

    await repository.replaceSubjectPresets(
      subjectId: 'subject1',
      termId: 'term1',
      scope: FreeSlotScope.school,
      scopeId: 'term1',
      stageId: firstStage.id,
      presets: const [],
    );
    presets = await repository.watchAllPresets().first;
    expect(presets, hasLength(1));
    expect(presets.single.stageId, 'stage2');
  });

  test('新建学期自动建立默认学段与作息', () async {
    await createTerm();
    final stages = await repository.watchStages('term1').first;
    expect(stages, hasLength(1));
    final routine = await repository.watchRoutine(stages.first.id).first;
    expect(routine, isNotNull);
    expect(routine!.teachingWeekdays, {1, 2, 3, 4, 5});
    expect(
      routine.periodTypes.map(
        (period) => '${period.name}:${period.defaultLessonCount}',
      ),
      ['上午:4', '下午:4', '晚上:2'],
    );
  });

  test('学期周期模式默认单双周并可持久化每周相同', () async {
    await createTerm();
    var loaded = (await repository.watchTerms().first).single;
    expect(loaded.cycleMode, AcademicTermCycle.alternating);

    await repository.saveTerm(
      loaded.copyWith(cycleMode: AcademicTermCycle.everyWeek),
    );
    loaded = (await repository.watchTerms().first).single;
    expect(loaded.cycleMode, AcademicTermCycle.everyWeek);
  });

  test('复制学期会重映射结构关联并平移日历日期', () async {
    final source = await createTerm();
    final stage = (await repository.watchStages(source.id).first).single;
    final grade = GradeGroup(
      id: 'source_grade',
      stageId: stage.id,
      name: '三年级',
      sortOrder: 0,
    );
    final schoolClass = ClassGroup(
      id: 'source_class',
      gradeId: grade.id,
      name: '一班',
      sortOrder: 0,
    );
    await repository.saveGrade(grade);
    await repository.saveClass(schoolClass);
    final initialRoutine = (await repository.watchRoutine(stage.id).first)!;
    final period = initialRoutine.periodTypes.first;
    await repository.saveRoutine(
      StageRoutine(
        stageId: stage.id,
        teachingWeekdays: initialRoutine.teachingWeekdays,
        periodTypes: initialRoutine.periodTypes,
        overrides: [
          RoutineOverride(periodTypeId: period.id, weekday: 1, lessonCount: 3),
        ],
      ),
    );
    await repository.saveFreeSlot(
      FreeSlot(
        id: 'source_free_slot',
        scope: FreeSlotScope.schoolClass,
        scopeId: schoolClass.id,
        stageId: stage.id,
        periodTypeId: period.id,
        weekday: 2,
        lessonIndex: 1,
        label: '自习',
      ),
    );
    await repository.saveCommonPeriod(
      CommonPeriod(
        id: 'source_common_period',
        stageId: stage.id,
        name: '大课间',
        insertAfterLessonId: '${period.id}_1',
        durationMinutes: 10,
        startMinute: null,
        endMinute: null,
      ),
    );
    await repository.saveCalendarException(
      CalendarException(
        id: 'source_exception',
        termId: source.id,
        date: DateTime(2026, 10, 1),
        kind: CalendarExceptionKind.holiday,
        makeupWeekday: null,
        makeupForDate: null,
        note: '假期',
      ),
    );
    await repository.saveCalendarException(
      CalendarException(
        id: 'source_makeup',
        termId: source.id,
        date: DateTime(2026, 10, 3),
        kind: CalendarExceptionKind.makeup,
        makeupWeekday: 3,
        makeupForDate: DateTime(2026, 10, 7),
        note: '',
      ),
    );

    final target = AcademicTerm(
      id: 'term2',
      title: '2027 学年 · 春季学期',
      academicYear: '2027-2028',
      semesterLabel: '春季学期',
      firstTeachingWeekStart: DateTime(2027, 1, 1),
      teachingWeekCount: 20,
      createdAt: DateTime(2026, 12, 1),
      cycleMode: AcademicTermCycle.everyWeek,
    );
    await repository.cloneTerm(sourceTermId: source.id, targetTerm: target);

    final clonedStage = (await repository.watchStages(target.id).first).single;
    expect(clonedStage.id, isNot(stage.id));
    final clonedGrade =
        (await repository.watchGrades(clonedStage.id).first).single;
    expect(clonedGrade.id, isNot(grade.id));
    final clonedClass =
        (await repository.watchClasses(clonedGrade.id).first).single;
    expect(clonedClass.id, isNot(schoolClass.id));
    final clonedRoutine = (await repository
        .watchRoutine(clonedStage.id)
        .first)!;
    expect(clonedRoutine.periodTypes.first.id, isNot(period.id));
    expect(
      clonedRoutine.overrides.single.periodTypeId,
      clonedRoutine.periodTypes.first.id,
    );
    expect(clonedRoutine.overrides.single.lessonCount, 3);
    final clonedSlots = await repository.watchFreeSlots(clonedStage.id).first;
    expect(clonedSlots.single.scopeId, clonedClass.id);
    expect(clonedSlots.single.periodTypeId, clonedRoutine.periodTypes.first.id);
    final clonedPeriods = await repository
        .watchCommonPeriods(clonedStage.id)
        .first;
    expect(clonedPeriods.single.id, isNot('source_common_period'));
    expect(
      clonedPeriods.single.insertAfterLessonId,
      '${clonedRoutine.periodTypes.first.id}_1',
    );
    final clonedExceptions = await repository
        .watchCalendarExceptions(target.id)
        .first;
    expect(clonedExceptions.map((item) => item.date), [
      DateTime(2027, 1, 31),
      DateTime(2027, 2, 2),
    ]);
    expect(clonedExceptions.last.makeupForDate, DateTime(2027, 2, 6));
    expect(
      clonedExceptions.every((item) => item.id != 'source_exception'),
      isTrue,
    );
  });

  test('保存作息后免任课不丢失，越界免任课被清理', () async {
    await createTerm();
    final stage = (await repository.watchStages('term1').first).first;
    final routine = (await repository.watchRoutine(stage.id).first)!;
    final morning = routine.periodTypes.first;

    await repository.saveFreeSlot(
      FreeSlot(
        id: 'free1',
        scope: FreeSlotScope.school,
        scopeId: 'term1',
        stageId: stage.id,
        periodTypeId: morning.id,
        weekday: 3,
        lessonIndex: 2,
        label: FreeSlotLabels.teachingResearch,
      ),
    );

    // 原样保存：免任课保留。
    await repository.saveRoutine(routine);
    var slots = await repository.watchFreeSlots(stage.id).first;
    expect(slots, hasLength(1));

    // 上午节数从 4 降到 1：第 2 节的免任课越界，应被清理。
    final shrunk = StageRoutine(
      stageId: routine.stageId,
      teachingWeekdays: routine.teachingWeekdays,
      periodTypes: [
        for (final period in routine.periodTypes)
          LessonPeriodType(
            id: period.id,
            name: period.name,
            defaultLessonCount: period.id == morning.id
                ? 1
                : period.defaultLessonCount,
            sortOrder: period.sortOrder,
            lessonTimes: period.id == morning.id
                ? period.lessonTimes.take(1).toList()
                : period.lessonTimes,
          ),
      ],
      overrides: routine.overrides,
    );
    await repository.saveRoutine(shrunk);
    slots = await repository.watchFreeSlots(stage.id).first;
    expect(slots, isEmpty);
  });

  test('删除年级清理年级范围免任课', () async {
    await createTerm();
    final stage = (await repository.watchStages('term1').first).first;
    final grade = GradeGroup(
      id: 'g1',
      stageId: stage.id,
      name: '一年级',
      sortOrder: 0,
    );
    await repository.saveGrade(grade);
    final routine = (await repository.watchRoutine(stage.id).first)!;
    final period = routine.periodTypes.first;

    await repository.saveFreeSlot(
      FreeSlot(
        id: 'freeGrade',
        scope: FreeSlotScope.grade,
        scopeId: 'g1',
        stageId: stage.id,
        periodTypeId: period.id,
        weekday: 1,
        lessonIndex: 1,
        label: FreeSlotLabels.none,
      ),
    );
    expect(await repository.watchFreeSlots(stage.id).first, hasLength(1));

    await repository.deleteGrade('g1');
    expect(await repository.watchFreeSlots(stage.id).first, isEmpty);
  });

  test('新建学段继承全校范围免任课', () async {
    await createTerm();
    final first = (await repository.watchStages('term1').first).first;
    final routine = (await repository.watchRoutine(first.id).first)!;
    final morning = routine.periodTypes.first;

    await repository.saveFreeSlot(
      FreeSlot(
        id: 'freeSchool',
        scope: FreeSlotScope.school,
        scopeId: 'term1',
        stageId: first.id,
        periodTypeId: morning.id,
        weekday: 3,
        lessonIndex: 2,
        label: FreeSlotLabels.teachingResearch,
      ),
    );

    final second = SchoolStage(
      id: 'stage2',
      termId: 'term1',
      name: '初中部',
      sortOrder: 1,
    );
    await repository.saveStage(second);

    final inherited = await repository.watchFreeSlots('stage2').first;
    expect(inherited, hasLength(1));
    expect(inherited.single.scope, FreeSlotScope.school);
    expect(inherited.single.label, FreeSlotLabels.teachingResearch);
    expect(inherited.single.lessonIndex, 2);
    expect(inherited.single.weekday, 3);
  });

  test('有年级的学段不能直接删除，需先迁移年级', () async {
    await createTerm();
    final first = (await repository.watchStages('term1').first).single;
    await repository.saveStage(
      const SchoolStage(
        id: 'stage2',
        termId: 'term1',
        name: '初中部',
        sortOrder: 1,
      ),
    );
    await repository.saveGrade(
      GradeGroup(id: 'g1', stageId: first.id, name: '一年级', sortOrder: 0),
    );

    await expectLater(repository.deleteStage(first.id), throwsStateError);
    expect(await repository.watchStages('term1').first, hasLength(2));
    expect(await repository.watchGrades(first.id).first, hasLength(1));
  });

  test('删除年级时同时清理所属班级范围的免任课', () async {
    await createTerm();
    final stage = (await repository.watchStages('term1').first).single;
    await repository.saveGrade(
      GradeGroup(id: 'g1', stageId: stage.id, name: '一年级', sortOrder: 0),
    );
    await repository.saveClass(
      const ClassGroup(id: 'c1', gradeId: 'g1', name: '一班', sortOrder: 0),
    );
    final period =
        (await repository.watchRoutine(stage.id).first)!.periodTypes.first;
    await repository.saveFreeSlot(
      FreeSlot(
        id: 'classSlot',
        scope: FreeSlotScope.schoolClass,
        scopeId: 'c1',
        stageId: stage.id,
        periodTypeId: period.id,
        weekday: 1,
        lessonIndex: 1,
        label: FreeSlotLabels.none,
      ),
    );

    await repository.deleteGrade('g1');
    expect(await repository.watchFreeSlots(stage.id).first, isEmpty);
  });

  test('年级切换学段时保留班级并重映射年级与班级免任课', () async {
    await createTerm();
    final source = (await repository.watchStages('term1').first).single;
    const target = SchoolStage(
      id: 'stage2',
      termId: 'term1',
      name: '初中部',
      sortOrder: 1,
    );
    await repository.saveStage(target);
    await repository.saveGrade(
      GradeGroup(id: 'g1', stageId: source.id, name: '一年级', sortOrder: 0),
    );
    await repository.saveClass(
      const ClassGroup(id: 'c1', gradeId: 'g1', name: '一班', sortOrder: 0),
    );
    final sourcePeriod =
        (await repository.watchRoutine(source.id).first)!.periodTypes.first;
    final targetPeriod =
        (await repository.watchRoutine(target.id).first)!.periodTypes.first;
    for (final (id, scope, scopeId) in [
      ('gradeSlot', FreeSlotScope.grade, 'g1'),
      ('classSlot', FreeSlotScope.schoolClass, 'c1'),
    ]) {
      await repository.saveFreeSlot(
        FreeSlot(
          id: id,
          scope: scope,
          scopeId: scopeId,
          stageId: source.id,
          periodTypeId: sourcePeriod.id,
          weekday: 1,
          lessonIndex: 1,
          label: FreeSlotLabels.none,
        ),
      );
    }

    await repository.saveGrade(
      const GradeGroup(id: 'g1', stageId: 'stage2', name: '一年级', sortOrder: 0),
    );

    expect(await repository.watchGrades(source.id).first, isEmpty);
    expect(await repository.watchGrades(target.id).first, hasLength(1));
    expect(await repository.watchClasses('g1').first, hasLength(1));
    expect(await repository.watchFreeSlots(source.id).first, isEmpty);
    final movedSlots = await repository.watchFreeSlots(target.id).first;
    expect(movedSlots, hasLength(2));
    expect(
      movedSlots.map((slot) => slot.periodTypeId),
      everyElement(targetPeriod.id),
    );
  });

  test('目标学段缺少对应节次时年级迁移完整回滚', () async {
    await createTerm();
    final source = (await repository.watchStages('term1').first).single;
    const target = SchoolStage(
      id: 'stage2',
      termId: 'term1',
      name: '初中部',
      sortOrder: 1,
    );
    await repository.saveStage(target);
    await repository.saveGrade(
      GradeGroup(id: 'g1', stageId: source.id, name: '一年级', sortOrder: 0),
    );
    final sourcePeriod =
        (await repository.watchRoutine(source.id).first)!.periodTypes.first;
    await repository.saveFreeSlot(
      FreeSlot(
        id: 'slot',
        scope: FreeSlotScope.grade,
        scopeId: 'g1',
        stageId: source.id,
        periodTypeId: sourcePeriod.id,
        weekday: 1,
        lessonIndex: 4,
        label: FreeSlotLabels.none,
      ),
    );
    final targetRoutine = (await repository.watchRoutine(target.id).first)!;
    await repository.saveRoutine(
      StageRoutine(
        stageId: target.id,
        teachingWeekdays: targetRoutine.teachingWeekdays,
        periodTypes: [
          for (final period in targetRoutine.periodTypes)
            if (period.id == targetRoutine.periodTypes.first.id)
              LessonPeriodType(
                id: period.id,
                name: period.name,
                defaultLessonCount: 3,
                sortOrder: period.sortOrder,
                lessonTimes: period.lessonTimes.take(3).toList(),
              )
            else
              period,
        ],
        overrides: targetRoutine.overrides,
      ),
    );

    await expectLater(
      repository.saveGrade(
        const GradeGroup(
          id: 'g1',
          stageId: 'stage2',
          name: '一年级',
          sortOrder: 0,
        ),
      ),
      throwsStateError,
    );
    expect(await repository.watchGrades(source.id).first, hasLength(1));
    expect(await repository.watchGrades(target.id).first, isEmpty);
    expect(await repository.watchFreeSlots(source.id).first, hasLength(1));
  });

  test('批量保存班级遇到无效所属年级时不会部分提交', () async {
    await createTerm();
    final stage = (await repository.watchStages('term1').first).single;
    await repository.saveGrade(
      GradeGroup(id: 'g1', stageId: stage.id, name: '一年级', sortOrder: 0),
    );

    await expectLater(
      repository.saveClasses(const <ClassGroup>[
        ClassGroup(id: 'c1', gradeId: 'g1', name: '一班', sortOrder: 0),
        ClassGroup(id: 'c2', gradeId: 'missing', name: '二班', sortOrder: 1),
      ]),
      throwsA(anything),
    );
    expect(await repository.watchClasses('g1').first, isEmpty);
  });

  test('教学日历例外读写与删除', () async {
    await createTerm();
    final exception = CalendarException(
      id: 'ex1',
      termId: 'term1',
      date: DateTime(2026, 10, 1),
      kind: CalendarExceptionKind.holiday,
      makeupWeekday: null,
      makeupForDate: null,
      note: '国庆假期',
    );
    await repository.saveCalendarException(exception);
    var loaded = await repository.watchCalendarExceptions('term1').first;
    expect(loaded, hasLength(1));
    expect(loaded.single.date, DateTime(2026, 10, 1));
    expect(loaded.single.note, '国庆假期');
    expect(loaded.single.isMakeup, isFalse);

    final makeup = CalendarException(
      id: 'ex2',
      termId: 'term1',
      date: DateTime(2026, 9, 26),
      kind: CalendarExceptionKind.makeup,
      makeupWeekday: 3,
      makeupForDate: DateTime(2026, 9, 30),
      note: '',
    );
    await repository.saveCalendarException(makeup);
    loaded = await repository.watchCalendarExceptions('term1').first;
    expect(loaded, hasLength(2));
    // 按日期升序：09/26 补课在前，10/01 停课在后。
    expect(loaded.first.isMakeup, isTrue);
    expect(loaded.first.makeupForDate, DateTime(2026, 9, 30));
    expect(loaded.last.isMakeup, isFalse);

    await repository.deleteCalendarException('ex1');
    expect(
      await repository.watchCalendarExceptions('term1').first,
      hasLength(1),
    );
  });

  test('例外批量保存遇到写入错误时完整回滚', () async {
    await createTerm();
    await repository.saveCalendarException(
      CalendarException(
        id: 'ex_keep',
        termId: 'term1',
        date: DateTime(2026, 10, 1),
        kind: CalendarExceptionKind.holiday,
        makeupWeekday: null,
        makeupForDate: null,
        note: '',
      ),
    );
    await database.customStatement(
      "CREATE TRIGGER reject_calendar_exception BEFORE INSERT ON calendar_exceptions "
      "WHEN NEW.date = '2026-10-03' BEGIN SELECT RAISE(ABORT, 'rejected'); END",
    );

    await expectLater(
      repository.saveCalendarExceptions(
        termId: 'term1',
        deleteIds: {'ex_keep'},
        upserts: [
          CalendarException(
            id: 'ex_new',
            termId: 'term1',
            date: DateTime(2026, 10, 2),
            kind: CalendarExceptionKind.holiday,
            makeupWeekday: null,
            makeupForDate: null,
            note: '',
          ),
          CalendarException(
            id: 'ex_rejected',
            termId: 'term1',
            date: DateTime(2026, 10, 3),
            kind: CalendarExceptionKind.holiday,
            makeupWeekday: null,
            makeupForDate: null,
            note: '',
          ),
        ],
      ),
      throwsA(anything),
    );

    final loaded = await repository.watchCalendarExceptions('term1').first;
    expect(loaded.map((item) => item.id), ['ex_keep']);
  });

  test('删除学期级联清理学段与例外', () async {
    await createTerm();
    await repository.saveTerm(
      AcademicTerm(
        id: 'term2',
        title: '2027 学年 · 春季学期',
        academicYear: '2027-2028',
        semesterLabel: '春季学期',
        firstTeachingWeekStart: DateTime(2027, 2, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2027, 1, 1),
      ),
    );
    await repository.saveCalendarException(
      CalendarException(
        id: 'ex1',
        termId: 'term1',
        date: DateTime(2026, 10, 1),
        kind: CalendarExceptionKind.holiday,
        makeupWeekday: null,
        makeupForDate: null,
        note: '',
      ),
    );
    await repository.deleteTerm('term1');
    expect(await repository.watchStages('term1').first, isEmpty);
    expect(await repository.watchCalendarExceptions('term1').first, isEmpty);
    expect((await repository.watchTerms().first).map((term) => term.id), [
      'term2',
    ]);
    expect(await repository.watchStages('term2').first, hasLength(1));
  });

  test('公共时段读写与删除', () async {
    await createTerm();
    final stage = (await repository.watchStages('term1').first).first;
    final routine = (await repository.watchRoutine(stage.id).first)!;
    final firstLessonId = '${routine.periodTypes.first.id}_1';

    await repository.saveCommonPeriod(
      CommonPeriod(
        id: 'cp1',
        stageId: stage.id,
        name: '眼保健操',
        insertAfterLessonId: firstLessonId,
        durationMinutes: 10,
        startMinute: 9 * 60 + 5,
        endMinute: 9 * 60 + 15,
      ),
    );
    var periods = await repository.watchCommonPeriods(stage.id).first;
    expect(periods, hasLength(1));
    expect(periods.single.startLabel, '09:05');
    expect(periods.single.endLabel, '09:15');

    await repository.deleteCommonPeriod('cp1');
    expect(await repository.watchCommonPeriods(stage.id).first, isEmpty);
  });

  test('公共时段挂载点在节次缩减后自动修复', () async {
    await createTerm();
    final stage = (await repository.watchStages('term1').first).first;
    final routine = (await repository.watchRoutine(stage.id).first)!;
    final morning = routine.periodTypes.first;

    await repository.saveCommonPeriod(
      CommonPeriod(
        id: 'cp1',
        stageId: stage.id,
        name: '课间',
        insertAfterLessonId: '${morning.id}_3',
        durationMinutes: 10,
        startMinute: null,
        endMinute: null,
      ),
    );

    // 上午节数降到 2：挂载点「第 3 节」消失，应回落到该时段最后一节。
    final shrunk = StageRoutine(
      stageId: routine.stageId,
      teachingWeekdays: routine.teachingWeekdays,
      periodTypes: [
        for (final period in routine.periodTypes)
          LessonPeriodType(
            id: period.id,
            name: period.name,
            defaultLessonCount: period.id == morning.id
                ? 2
                : period.defaultLessonCount,
            sortOrder: period.sortOrder,
            lessonTimes: period.id == morning.id
                ? period.lessonTimes.take(2).toList()
                : period.lessonTimes,
          ),
      ],
      overrides: routine.overrides,
    );
    await repository.saveRoutine(shrunk);

    final periods = await repository.watchCommonPeriods(stage.id).first;
    expect(periods.single.insertAfterLessonId, '${morning.id}_2');
  });
}
