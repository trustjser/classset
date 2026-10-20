import 'package:class_set/data/database/app_database.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart' as domain;
import 'package:class_set/domain/models/calendar_exception.dart' as domain;
import 'package:class_set/domain/models/common_period.dart' as domain;
import 'package:class_set/domain/models/free_slot.dart' as domain;
import 'package:class_set/domain/models/school_structure.dart' as domain;
import 'package:class_set/domain/models/stage_routine.dart' as domain;
import 'package:class_set/domain/models/subject.dart' as domain;
import 'package:class_set/domain/models/subject_lesson_constraint.dart'
    as domain;
import 'package:class_set/domain/models/public_room.dart' as domain;
import 'package:class_set/domain/models/subject_room_assignment.dart' as domain;
import 'package:class_set/domain/models/subject_parallel_limit.dart' as domain;
import 'package:drift/drift.dart';

class DriftSchoolRepository implements SchoolRepository {
  const DriftSchoolRepository(this._database);

  final AppDatabase _database;

  @override
  Stream<List<domain.AcademicTerm>> watchTerms() =>
      (_database.select(_database.academicTerms)..orderBy([
            (term) => OrderingTerm.desc(term.firstTeachingWeekStart),
            (term) => OrderingTerm.desc(term.createdAt),
          ]))
          .watch()
          .map((rows) => rows.map(_toDomainTerm).toList(growable: false));

  @override
  Future<void> saveTerm(domain.AcademicTerm term) =>
      _database.transaction(() async {
        final existing = await (_database.select(
          _database.academicTerms,
        )..where((row) => row.id.equals(term.id))).getSingleOrNull();
        await _database
            .into(_database.academicTerms)
            .insertOnConflictUpdate(
              AcademicTermsCompanion.insert(
                id: term.id,
                title: term.title.trim(),
                academicYear: term.academicYear.trim(),
                semesterLabel: term.semesterLabel.trim(),
                firstTeachingWeekStart: Value(
                  term.firstTeachingWeekStart?.toIso8601String(),
                ),
                teachingWeekCount: Value(term.teachingWeekCount),
                cycleMode: Value(term.cycleMode.storageValue),
                createdAt: term.createdAt.millisecondsSinceEpoch,
              ),
            );
        if (existing == null) await _createDefaultStage(term.id);
      });

  @override
  Future<void> cloneTerm({
    required String sourceTermId,
    required domain.AcademicTerm targetTerm,
  }) => _database.transaction(() async {
    if (sourceTermId == targetTerm.id) {
      throw ArgumentError('复制后的学期 ID 不能与来源学期相同');
    }
    final source = await (_database.select(
      _database.academicTerms,
    )..where((row) => row.id.equals(sourceTermId))).getSingleOrNull();
    if (source == null) throw StateError('来源学期不存在');
    final targetExists = await (_database.select(
      _database.academicTerms,
    )..where((row) => row.id.equals(targetTerm.id))).getSingleOrNull();
    if (targetExists != null) throw StateError('目标学期已存在');

    await _database
        .into(_database.academicTerms)
        .insert(
          AcademicTermsCompanion.insert(
            id: targetTerm.id,
            title: targetTerm.title.trim(),
            academicYear: targetTerm.academicYear.trim(),
            semesterLabel: targetTerm.semesterLabel.trim(),
            firstTeachingWeekStart: Value(
              targetTerm.firstTeachingWeekStart?.toIso8601String(),
            ),
            teachingWeekCount: Value(targetTerm.teachingWeekCount),
            cycleMode: Value(targetTerm.cycleMode.storageValue),
            createdAt: targetTerm.createdAt.millisecondsSinceEpoch,
          ),
        );

    final sourceStart = source.firstTeachingWeekStart == null
        ? null
        : DateTime.tryParse(source.firstTeachingWeekStart!);
    final targetStart = targetTerm.firstTeachingWeekStart;
    final dateShift = sourceStart == null || targetStart == null
        ? 0
        : _dateOnly(targetStart).difference(_dateOnly(sourceStart)).inDays;
    final stageIds = <String, String>{};
    final gradeIds = <String, String>{};
    final classIds = <String, String>{};
    final periodIds = <String, String>{};
    final lessonIds = <String, String>{};

    final sourceStages = await (_database.select(
      _database.schoolStages,
    )..where((row) => row.termId.equals(sourceTermId))).get();
    for (final stage in sourceStages) {
      final newId = _newId();
      stageIds[stage.id] = newId;
      await _database
          .into(_database.schoolStages)
          .insert(
            SchoolStagesCompanion.insert(
              id: newId,
              termId: targetTerm.id,
              name: stage.name,
              sortOrder: stage.sortOrder,
            ),
          );
    }

    for (final stage in sourceStages) {
      final targetStageId = stageIds[stage.id]!;
      final teachingDays = await (_database.select(
        _database.stageTeachingDays,
      )..where((row) => row.stageId.equals(stage.id))).get();
      for (final day in teachingDays) {
        await _database
            .into(_database.stageTeachingDays)
            .insert(
              StageTeachingDaysCompanion.insert(
                id: _newId(),
                stageId: targetStageId,
                weekday: day.weekday,
                isTeachingDay: day.isTeachingDay,
              ),
            );
      }

      final sourceGrades = await (_database.select(
        _database.gradeGroups,
      )..where((row) => row.stageId.equals(stage.id))).get();
      for (final grade in sourceGrades) {
        final newId = _newId();
        gradeIds[grade.id] = newId;
        await _database
            .into(_database.gradeGroups)
            .insert(
              GradeGroupsCompanion.insert(
                id: newId,
                stageId: targetStageId,
                name: grade.name,
                sortOrder: grade.sortOrder,
              ),
            );
        final sourceClasses = await (_database.select(
          _database.classGroups,
        )..where((row) => row.gradeId.equals(grade.id))).get();
        for (final schoolClass in sourceClasses) {
          final newClassId = _newId();
          classIds[schoolClass.id] = newClassId;
          await _database
              .into(_database.classGroups)
              .insert(
                ClassGroupsCompanion.insert(
                  id: newClassId,
                  gradeId: newId,
                  name: schoolClass.name,
                  sortOrder: schoolClass.sortOrder,
                ),
              );
        }
      }

      final sourcePeriods = await (_database.select(
        _database.lessonPeriodTypes,
      )..where((row) => row.stageId.equals(stage.id))).get();
      for (final period in sourcePeriods) {
        final newPeriodId = _newId();
        periodIds[period.id] = newPeriodId;
        await _database
            .into(_database.lessonPeriodTypes)
            .insert(
              LessonPeriodTypesCompanion.insert(
                id: newPeriodId,
                stageId: targetStageId,
                name: period.name,
                defaultLessonCount: period.defaultLessonCount,
                sortOrder: period.sortOrder,
              ),
            );
        final times = await (_database.select(
          _database.lessonTimes,
        )..where((row) => row.periodTypeId.equals(period.id))).get();
        for (final time in times) {
          final newLessonId = '${newPeriodId}_${time.lessonIndex}';
          lessonIds[time.id] = newLessonId;
          await _database
              .into(_database.lessonTimes)
              .insert(
                LessonTimesCompanion.insert(
                  id: newLessonId,
                  periodTypeId: newPeriodId,
                  lessonIndex: time.lessonIndex,
                  label: time.label,
                  startMinute: Value(time.startMinute),
                  endMinute: Value(time.endMinute),
                ),
              );
        }
      }

      final overrides = await (_database.select(
        _database.dailyLessonOverrides,
      )..where((row) => row.stageId.equals(stage.id))).get();
      for (final override in overrides) {
        final newPeriodId = periodIds[override.periodTypeId];
        if (newPeriodId == null) continue;
        await _database
            .into(_database.dailyLessonOverrides)
            .insert(
              DailyLessonOverridesCompanion.insert(
                id: _newId(),
                stageId: targetStageId,
                periodTypeId: newPeriodId,
                weekday: override.weekday,
                lessonCount: override.lessonCount,
              ),
            );
      }

      final slots = await (_database.select(
        _database.freeSlots,
      )..where((row) => row.stageId.equals(stage.id))).get();
      for (final slot in slots) {
        final newPeriodId = periodIds[slot.periodTypeId];
        if (newPeriodId == null) continue;
        final newScopeId = switch (slot.scopeType) {
          'school' => targetTerm.id,
          'stage' => stageIds[slot.scopeId],
          'grade' => gradeIds[slot.scopeId],
          'class' => classIds[slot.scopeId],
          _ => null,
        };
        if (newScopeId == null) continue;
        await _database
            .into(_database.freeSlots)
            .insert(
              FreeSlotsCompanion.insert(
                id: _newId(),
                scopeType: slot.scopeType,
                scopeId: newScopeId,
                stageId: targetStageId,
                periodTypeId: newPeriodId,
                weekday: slot.weekday,
                lessonIndex: slot.lessonIndex,
                label: slot.label,
              ),
            );
      }

      final commonPeriods = await (_database.select(
        _database.commonPeriods,
      )..where((row) => row.stageId.equals(stage.id))).get();
      for (final period in commonPeriods) {
        await _database
            .into(_database.commonPeriods)
            .insert(
              CommonPeriodsCompanion.insert(
                id: _newId(),
                stageId: targetStageId,
                name: period.name,
                insertAfterLessonId: Value(
                  period.insertAfterLessonId == null
                      ? null
                      : lessonIds[period.insertAfterLessonId],
                ),
                durationMinutes: Value(period.durationMinutes),
                startMinute: Value(period.startMinute),
                endMinute: Value(period.endMinute),
              ),
            );
      }
    }

    final exceptions = await (_database.select(
      _database.calendarExceptions,
    )..where((row) => row.termId.equals(sourceTermId))).get();
    for (final exception in exceptions) {
      final date = _dateFromStorage(exception.date)
          .add(Duration(days: dateShift));
      final makeupForDate = exception.makeupForDate == null
          ? null
          : _dateFromStorage(exception.makeupForDate!)
                .add(Duration(days: dateShift));
      await _database
          .into(_database.calendarExceptions)
          .insert(
            CalendarExceptionsCompanion.insert(
              id: _newId(),
              termId: targetTerm.id,
              date: _dateStorage(date),
              kind: exception.kind,
              makeupWeekday: Value(exception.makeupWeekday),
              makeupForDate: Value(
                makeupForDate == null ? null : _dateStorage(makeupForDate),
              ),
              note: Value(exception.note),
            ),
          );
    }
  });

  @override
  Future<void> deleteTerm(String termId) => (_database.delete(
    _database.academicTerms,
  )..where((term) => term.id.equals(termId))).go();

  @override
  Stream<List<domain.SchoolStage>> watchStages(String termId) =>
      (_database.select(_database.schoolStages)
            ..where((stage) => stage.termId.equals(termId))
            ..orderBy([(stage) => OrderingTerm.asc(stage.sortOrder)]))
          .watch()
          .map((rows) => rows.map(_toDomainStage).toList(growable: false));

  @override
  Stream<List<domain.StageStructureStat>> watchStageStructureStats(
    String termId,
  ) => _database
      .customSelect(
        '''
        SELECT s.id AS stage_id,
          (SELECT COUNT(*) FROM grade_groups g WHERE g.stage_id = s.id)
            AS grade_count,
          (SELECT COUNT(*) FROM stage_teaching_days d
             WHERE d.stage_id = s.id AND d.is_teaching_day = 1)
            AS teaching_day_count,
          (SELECT COUNT(*) FROM lesson_period_types p
             WHERE p.stage_id = s.id)
            AS period_count
        FROM school_stages s
        WHERE s.term_id = ?
        ORDER BY s.sort_order ASC
        ''',
        variables: [Variable<String>(termId)],
        readsFrom: {
          _database.schoolStages,
          _database.gradeGroups,
          _database.stageTeachingDays,
          _database.lessonPeriodTypes,
        },
      )
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            domain.StageStructureStat(
              stageId: row.read<String>('stage_id'),
              gradeCount: row.read<int>('grade_count'),
              hasTeachingDays: row.read<int>('teaching_day_count') > 0,
              hasPeriods: row.read<int>('period_count') > 0,
            ),
        ],
      );

  @override
  Future<void> saveStage(domain.SchoolStage stage) =>
      _database.transaction(() async {
        final existing = await (_database.select(
          _database.schoolStages,
        )..where((row) => row.id.equals(stage.id))).getSingleOrNull();
        await _database
            .into(_database.schoolStages)
            .insertOnConflictUpdate(
              SchoolStagesCompanion.insert(
                id: stage.id,
                termId: stage.termId,
                name: stage.name.trim(),
                sortOrder: stage.sortOrder,
              ),
            );
        if (existing == null) {
          await _createDefaultRoutine(stage.id);
          await _inheritSchoolFreeSlots(stage.id, stage.termId);
        }
      });

  /// 新建学段时，按「同时段名称 + 同节次」继承同学期的全校范围免任课，
  /// 使全校范围的标记对新学段同样生效。
  Future<void> _inheritSchoolFreeSlots(String newStageId, String termId) async {
    final siblings =
        await (_database.select(_database.schoolStages)..where(
              (stage) =>
                  stage.termId.equals(termId) &
                  stage.id.equals(newStageId).not(),
            ))
            .get();
    if (siblings.isEmpty) return;
    final schoolSlots =
        await (_database.select(_database.freeSlots)..where(
              (slot) =>
                  slot.scopeType.equals('school') & slot.scopeId.equals(termId),
            ))
            .get();
    if (schoolSlots.isEmpty) return;

    // 去重：同一（时段名称, 星期, 节次, 标签）只继承一条。
    final unique = <String, FreeSlot>{};
    for (final slot in schoolSlots) {
      final period = await (_database.select(
        _database.lessonPeriodTypes,
      )..where((item) => item.id.equals(slot.periodTypeId))).getSingleOrNull();
      if (period == null) continue;
      final key =
          '${period.name}_${slot.weekday}_${slot.lessonIndex}_${slot.label}';
      unique.putIfAbsent(key, () => slot);
    }
    if (unique.isEmpty) return;

    final newPeriods = await (_database.select(
      _database.lessonPeriodTypes,
    )..where((period) => period.stageId.equals(newStageId))).get();
    final byName = {for (final period in newPeriods) period.name: period.id};
    for (final entry in unique.entries) {
      final source = entry.value;
      final sourcePeriod =
          await (_database.select(_database.lessonPeriodTypes)
                ..where((item) => item.id.equals(source.periodTypeId)))
              .getSingleOrNull();
      if (sourcePeriod == null) continue;
      final targetPeriodId = byName[sourcePeriod.name];
      if (targetPeriodId == null) continue;
      final hasLesson =
          await (_database.select(_database.lessonTimes)..where(
                (time) =>
                    time.periodTypeId.equals(targetPeriodId) &
                    time.lessonIndex.equals(source.lessonIndex),
              ))
              .get()
              .then((rows) => rows.isNotEmpty);
      if (!hasLesson) continue;
      await _database
          .into(_database.freeSlots)
          .insert(
            FreeSlotsCompanion.insert(
              id: '${newStageId}_inh_${source.id}',
              scopeType: 'school',
              scopeId: termId,
              stageId: newStageId,
              periodTypeId: targetPeriodId,
              weekday: source.weekday,
              lessonIndex: source.lessonIndex,
              label: source.label,
            ),
          );
    }
  }

  @override
  Future<void> deleteStage(String stageId) => _database.transaction(() async {
    final stage = await (_database.select(
      _database.schoolStages,
    )..where((row) => row.id.equals(stageId))).getSingleOrNull();
    if (stage == null) return;
    final stageCount =
        await (_database.selectOnly(_database.schoolStages)
              ..addColumns([_database.schoolStages.id.count()])
              ..where(_database.schoolStages.termId.equals(stage.termId)))
            .map((row) => row.read(_database.schoolStages.id.count()) ?? 0)
            .getSingle();
    if (stageCount <= 1) throw StateError('每个学期至少保留一个学段');
    final childGrade =
        await (_database.select(_database.gradeGroups)
              ..where((grade) => grade.stageId.equals(stageId))
              ..limit(1))
            .getSingleOrNull();
    if (childGrade != null) throw StateError('请先迁移或删除该学段下的年级');
    await (_database.delete(
      _database.schoolStages,
    )..where((row) => row.id.equals(stageId))).go();
  });

  @override
  Stream<List<domain.GradeGroup>> watchGrades(String stageId) =>
      (_database.select(_database.gradeGroups)
            ..where((grade) => grade.stageId.equals(stageId))
            ..orderBy([(grade) => OrderingTerm.asc(grade.sortOrder)]))
          .watch()
          .map((rows) => rows.map(_toDomainGrade).toList(growable: false));

  @override
  Future<void> saveGrade(domain.GradeGroup grade) =>
      _database.transaction(() async {
        final existing = await (_database.select(
          _database.gradeGroups,
        )..where((row) => row.id.equals(grade.id))).getSingleOrNull();
        if (existing != null && existing.stageId != grade.stageId) {
          await _remapGradeFreeSlots(grade.id, existing.stageId, grade.stageId);
        }
        await _database
            .into(_database.gradeGroups)
            .insertOnConflictUpdate(
              GradeGroupsCompanion.insert(
                id: grade.id,
                stageId: grade.stageId,
                name: grade.name.trim(),
                sortOrder: grade.sortOrder,
              ),
            );
        if (existing != null && existing.stageId != grade.stageId) {
          final classes = await (_database.select(
            _database.classGroups,
          )..where((row) => row.gradeId.equals(grade.id))).get();
          await _remapRoomScope('grade', [grade.id], grade.stageId);
          await _remapRoomScope(
            'class',
            classes.map((row) => row.id).toList(),
            grade.stageId,
          );
        }
      });

  @override
  Future<void> saveGrades(List<domain.GradeGroup> grades) =>
      _database.transaction(() async {
        for (final grade in grades) {
          await saveGrade(grade);
        }
      });

  Future<void> _remapGradeFreeSlots(
    String gradeId,
    String sourceStageId,
    String targetStageId,
  ) async {
    final childClasses = await (_database.select(
      _database.classGroups,
    )..where((row) => row.gradeId.equals(gradeId))).get();
    final classIds = childClasses.map((row) => row.id).toList();
    final slots =
        await (_database.select(_database.freeSlots)..where(
              (slot) =>
                  (slot.scopeType.equals('grade') &
                      slot.scopeId.equals(gradeId)) |
                  (slot.scopeType.equals('class') &
                      slot.scopeId.isIn(classIds)),
            ))
            .get();
    if (slots.isEmpty) return;

    final sourcePeriods = await (_database.select(
      _database.lessonPeriodTypes,
    )..where((period) => period.stageId.equals(sourceStageId))).get();
    final targetPeriods = await (_database.select(
      _database.lessonPeriodTypes,
    )..where((period) => period.stageId.equals(targetStageId))).get();
    final sourceNames = {
      for (final period in sourcePeriods) period.id: period.name,
    };
    final targetIds = {
      for (final period in targetPeriods) period.name: period.id,
    };
    final targetLessons = await (_database.select(
      _database.lessonTimes,
    )..where((lesson) => lesson.periodTypeId.isIn(targetIds.values))).get();
    final validLessons = {
      for (final lesson in targetLessons)
        '${lesson.periodTypeId}:${lesson.lessonIndex}',
    };
    final replacements = <String, String>{};
    for (final slot in slots) {
      final sourceName = sourceNames[slot.periodTypeId];
      final targetPeriodId = targetIds[sourceName];
      if (targetPeriodId == null ||
          !validLessons.contains('$targetPeriodId:${slot.lessonIndex}')) {
        throw StateError('目标学段缺少免任课对应的时段或节次，请先调整作息');
      }
      replacements[slot.id] = targetPeriodId;
    }
    for (final slot in slots) {
      await (_database.update(
        _database.freeSlots,
      )..where((row) => row.id.equals(slot.id))).write(
        FreeSlotsCompanion(
          stageId: Value(targetStageId),
          periodTypeId: Value(replacements[slot.id]!),
        ),
      );
    }
  }

  @override
  Future<void> deleteGrade(String gradeId) => _database.transaction(() async {
    final childClasses = await (_database.select(
      _database.classGroups,
    )..where((schoolClass) => schoolClass.gradeId.equals(gradeId))).get();
    final classIds = childClasses.map((schoolClass) => schoolClass.id).toList();
    await _deleteRoomScope('grade', [gradeId]);
    await _deleteRoomScope('class', classIds);
    if (classIds.isNotEmpty) {
      await (_database.delete(_database.freeSlots)..where(
            (slot) =>
                slot.scopeType.equals('class') & slot.scopeId.isIn(classIds),
          ))
          .go();
      await (_database.delete(_database.subjectLessonConstraints)..where(
            (constraint) =>
                constraint.scopeType.equals('class') &
                constraint.scopeId.isIn(classIds),
          ))
          .go();
    }
    await (_database.delete(_database.freeSlots)..where(
          (slot) =>
              slot.scopeType.equals('grade') & slot.scopeId.equals(gradeId),
        ))
        .go();
    await (_database.delete(_database.subjectLessonConstraints)..where(
          (constraint) =>
              constraint.scopeType.equals('grade') &
              constraint.scopeId.equals(gradeId),
        ))
        .go();
    await (_database.delete(
      _database.gradeGroups,
    )..where((grade) => grade.id.equals(gradeId))).go();
  });

  @override
  Stream<List<domain.ClassGroup>> watchClasses(String gradeId) =>
      (_database.select(_database.classGroups)
            ..where((schoolClass) => schoolClass.gradeId.equals(gradeId))
            ..orderBy([
              (schoolClass) => OrderingTerm.asc(schoolClass.sortOrder),
            ]))
          .watch()
          .map((rows) => rows.map(_toDomainClass).toList(growable: false));

  @override
  Future<void> saveClass(domain.ClassGroup classGroup) =>
      _database.transaction(() async {
        await _database
            .into(_database.classGroups)
            .insertOnConflictUpdate(
              ClassGroupsCompanion.insert(
                id: classGroup.id,
                gradeId: classGroup.gradeId,
                name: classGroup.name.trim(),
                sortOrder: classGroup.sortOrder,
              ),
            );
        final grade = await (_database.select(
          _database.gradeGroups,
        )..where((row) => row.id.equals(classGroup.gradeId))).getSingle();
        await _remapRoomScope('class', [classGroup.id], grade.stageId);
      });

  @override
  Future<void> saveClasses(List<domain.ClassGroup> classes) =>
      _database.transaction(() async {
        for (final schoolClass in classes) {
          await saveClass(schoolClass);
        }
      });

  @override
  Future<void> deleteClass(String classId) => _database.transaction(() async {
    await _deleteRoomScope('class', [classId]);
    await (_database.delete(_database.freeSlots)..where(
          (slot) =>
              slot.scopeType.equals('class') & slot.scopeId.equals(classId),
        ))
        .go();
    await (_database.delete(_database.subjectLessonConstraints)..where(
          (constraint) =>
              constraint.scopeType.equals('class') &
              constraint.scopeId.equals(classId),
        ))
        .go();
    await (_database.delete(
      _database.classGroups,
    )..where((schoolClass) => schoolClass.id.equals(classId))).go();
  });

  @override
  Stream<domain.StageRoutine?> watchRoutine(String stageId) => _database
      .customSelect(
        'SELECT id FROM school_stages WHERE id = ?',
        variables: [Variable<String>(stageId)],
        readsFrom: {
          _database.schoolStages,
          _database.stageTeachingDays,
          _database.lessonPeriodTypes,
          _database.dailyLessonOverrides,
          _database.lessonTimes,
          _database.freeSlots,
          _database.commonPeriods,
        },
      )
      .watch()
      .asyncMap((rows) => rows.isEmpty ? null : _loadRoutine(stageId));

  @override
  Future<void> saveRoutine(domain.StageRoutine routine) async {
    _validateRoutine(routine);
    await _database.transaction(() async {
      // 免任课与公共时段不随时段类型重建而丢失：先保留，重建后按有效性恢复。
      final preservedFreeSlots = await (_database.select(
        _database.freeSlots,
      )..where((slot) => slot.stageId.equals(routine.stageId))).get();
      final preservedCommonPeriods = await (_database.select(
        _database.commonPeriods,
      )..where((period) => period.stageId.equals(routine.stageId))).get();

      await (_database.delete(
        _database.stageTeachingDays,
      )..where((day) => day.stageId.equals(routine.stageId))).go();
      await (_database.delete(
        _database.lessonPeriodTypes,
      )..where((period) => period.stageId.equals(routine.stageId))).go();

      for (
        var weekday = DateTime.monday;
        weekday <= DateTime.sunday;
        weekday++
      ) {
        await _database
            .into(_database.stageTeachingDays)
            .insert(
              StageTeachingDaysCompanion.insert(
                id: '${routine.stageId}_day_$weekday',
                stageId: routine.stageId,
                weekday: weekday,
                isTeachingDay: routine.teachingWeekdays.contains(weekday),
              ),
            );
      }

      for (final period in routine.periodTypes) {
        await _database
            .into(_database.lessonPeriodTypes)
            .insert(
              LessonPeriodTypesCompanion.insert(
                id: period.id,
                stageId: routine.stageId,
                name: period.name.trim(),
                defaultLessonCount: period.defaultLessonCount,
                sortOrder: period.sortOrder,
              ),
            );
        for (final override in routine.overrides.where(
          (item) => item.periodTypeId == period.id,
        )) {
          await _database
              .into(_database.dailyLessonOverrides)
              .insert(
                DailyLessonOverridesCompanion.insert(
                  id: '${routine.stageId}_${period.id}_${override.weekday}',
                  stageId: routine.stageId,
                  periodTypeId: period.id,
                  weekday: override.weekday,
                  lessonCount: override.lessonCount,
                ),
              );
        }
        for (final lessonTime in period.lessonTimes) {
          await _database
              .into(_database.lessonTimes)
              .insert(
                LessonTimesCompanion.insert(
                  id: '${period.id}_${lessonTime.lessonIndex}',
                  periodTypeId: period.id,
                  lessonIndex: lessonTime.lessonIndex,
                  label: lessonTime.label,
                  startMinute: Value(lessonTime.startMinute),
                  endMinute: Value(lessonTime.endMinute),
                ),
              );
        }
      }

      // 恢复仍有效的免任课（时段与节次均存在）。
      final validLessonIds = <String>{
        for (final period in routine.periodTypes)
          for (final time in period.lessonTimes)
            '${period.id}_${time.lessonIndex}',
      };
      for (final slot in preservedFreeSlots) {
        if (!validLessonIds.contains(
          '${slot.periodTypeId}_${slot.lessonIndex}',
        )) {
          continue;
        }
        await _database
            .into(_database.freeSlots)
            .insertOnConflictUpdate(
              FreeSlotsCompanion.insert(
                id: slot.id,
                scopeType: slot.scopeType,
                scopeId: slot.scopeId,
                stageId: slot.stageId,
                periodTypeId: slot.periodTypeId,
                weekday: slot.weekday,
                lessonIndex: slot.lessonIndex,
                label: slot.label,
              ),
            );
      }

      // 公共时段挂载点漂移时修复：优先挂到原时段最后一节，时段已删除则移到最前。
      for (final row in preservedCommonPeriods) {
        final anchor = row.insertAfterLessonId;
        if (anchor == null || validLessonIds.contains(anchor)) continue;
        final periodId = anchor.substring(0, anchor.lastIndexOf('_'));
        final period = routine.periodTypes
            .where((item) => item.id == periodId)
            .firstOrNull;
        String? newAnchor;
        if (period != null && period.lessonTimes.isNotEmpty) {
          final last = period.lessonTimes.reduce(
            (a, b) => a.lessonIndex >= b.lessonIndex ? a : b,
          );
          newAnchor = '${period.id}_${last.lessonIndex}';
        }
        await (_database.update(
          _database.commonPeriods,
        )..where((item) => item.id.equals(row.id))).write(
          CommonPeriodsCompanion(insertAfterLessonId: Value(newAnchor)),
        );
      }
    });
  }

  // —— 教学日历例外 ——

  @override
  Stream<List<domain.CalendarException>> watchCalendarExceptions(
    String termId,
  ) =>
      (_database.select(_database.calendarExceptions)
            ..where((row) => row.termId.equals(termId))
            ..orderBy([(row) => OrderingTerm.asc(row.date)]))
          .watch()
          .map((rows) => rows.map(_toDomainException).toList(growable: false));

  @override
  Future<void> saveCalendarException(domain.CalendarException exception) =>
      saveCalendarExceptions(
        termId: exception.termId,
        upserts: [exception],
        deleteIds: const {},
      );

  @override
  Future<void> saveCalendarExceptions({
    required String termId,
    required List<domain.CalendarException> upserts,
    required Set<String> deleteIds,
  }) => _database.transaction(() async {
    if (upserts.any((item) => item.termId != termId)) {
      throw ArgumentError('批量例外必须属于同一学期');
    }
    final existing = await (_database.select(
      _database.calendarExceptions,
    )..where((row) => row.termId.equals(termId))).get();
    final replacingIds = {...deleteIds, ...upserts.map((item) => item.id)};
    final usedDates = <String>{
      for (final item in existing)
        if (!replacingIds.contains(item.id)) item.date,
    };
    for (final item in upserts) {
      final date = _dateStorage(item.date);
      if (!usedDates.add(date)) {
        throw ArgumentError('同一天只能设置一条日历例外：$date');
      }
      final rowWithSameId = await (_database.select(
        _database.calendarExceptions,
      )..where((row) => row.id.equals(item.id))).getSingleOrNull();
      if (rowWithSameId != null && rowWithSameId.termId != termId) {
        throw ArgumentError('例外 ID 已被其他学期使用');
      }
    }

    if (deleteIds.isNotEmpty) {
      await (_database.delete(
            _database.calendarExceptions,
          )..where((row) => row.termId.equals(termId) & row.id.isIn(deleteIds)))
          .go();
    }
    for (final exception in upserts) {
      await _database
          .into(_database.calendarExceptions)
          .insertOnConflictUpdate(
            CalendarExceptionsCompanion.insert(
              id: exception.id,
              termId: termId,
              date: _dateStorage(exception.date),
              kind: exception.kind.storageValue,
              makeupWeekday: Value(exception.makeupWeekday),
              makeupForDate: Value(
                exception.makeupForDate == null
                    ? null
                    : _dateStorage(exception.makeupForDate!),
              ),
              note: Value(exception.note),
            ),
          );
    }
  });

  @override
  Future<void> deleteCalendarException(String exceptionId) => (_database.delete(
    _database.calendarExceptions,
  )..where((row) => row.id.equals(exceptionId))).go();

  // —— 免任课 ——

  @override
  Stream<List<domain.FreeSlot>> watchFreeSlots(String stageId) =>
      (_database.select(_database.freeSlots)
            ..where((slot) => slot.stageId.equals(stageId))
            ..orderBy([
              (slot) => OrderingTerm.asc(slot.weekday),
              (slot) => OrderingTerm.asc(slot.lessonIndex),
            ]))
          .watch()
          .map((rows) => rows.map(_toDomainFreeSlot).toList(growable: false));

  @override
  Future<void> saveFreeSlot(domain.FreeSlot slot) => _database
      .into(_database.freeSlots)
      .insertOnConflictUpdate(
        FreeSlotsCompanion.insert(
          id: slot.id,
          scopeType: slot.scope.storageValue,
          scopeId: slot.scopeId,
          stageId: slot.stageId,
          periodTypeId: slot.periodTypeId,
          weekday: slot.weekday,
          lessonIndex: slot.lessonIndex,
          label: slot.label,
        ),
      );

  @override
  Future<void> deleteFreeSlot(String slotId) => (_database.delete(
    _database.freeSlots,
  )..where((slot) => slot.id.equals(slotId))).go();

  // —— 公共时段 ——

  @override
  Stream<List<domain.CommonPeriod>> watchCommonPeriods(String stageId) =>
      (_database.select(_database.commonPeriods)
            ..where((period) => period.stageId.equals(stageId))
            ..orderBy([
              (period) => OrderingTerm.asc(period.insertAfterLessonId),
              (period) => OrderingTerm.asc(period.name),
            ]))
          .watch()
          .map(
            (rows) => rows.map(_toDomainCommonPeriod).toList(growable: false),
          );

  @override
  Future<void> saveCommonPeriod(domain.CommonPeriod period) => _database
      .into(_database.commonPeriods)
      .insertOnConflictUpdate(
        CommonPeriodsCompanion.insert(
          id: period.id,
          stageId: period.stageId,
          name: period.name.trim(),
          insertAfterLessonId: Value(period.insertAfterLessonId),
          durationMinutes: Value(period.durationMinutes),
          startMinute: Value(period.startMinute),
          endMinute: Value(period.endMinute),
        ),
      );

  @override
  Future<void> deleteCommonPeriod(String periodId) => (_database.delete(
    _database.commonPeriods,
  )..where((period) => period.id.equals(periodId))).go();

  Future<domain.StageRoutine> _loadRoutine(String stageId) async {
    final days = await (_database.select(
      _database.stageTeachingDays,
    )..where((day) => day.stageId.equals(stageId))).get();
    final periodRows =
        await (_database.select(_database.lessonPeriodTypes)
              ..where((period) => period.stageId.equals(stageId))
              ..orderBy([(period) => OrderingTerm.asc(period.sortOrder)]))
            .get();
    final overrideRows = await (_database.select(
      _database.dailyLessonOverrides,
    )..where((override) => override.stageId.equals(stageId))).get();
    final periods = <domain.LessonPeriodType>[];
    for (final period in periodRows) {
      final times =
          await (_database.select(_database.lessonTimes)
                ..where((time) => time.periodTypeId.equals(period.id))
                ..orderBy([(time) => OrderingTerm.asc(time.lessonIndex)]))
              .get();
      periods.add(
        domain.LessonPeriodType(
          id: period.id,
          name: period.name,
          defaultLessonCount: period.defaultLessonCount,
          sortOrder: period.sortOrder,
          lessonTimes: times
              .map(
                (time) => domain.LessonTime(
                  lessonIndex: time.lessonIndex,
                  label: time.label,
                  startMinute: time.startMinute,
                  endMinute: time.endMinute,
                ),
              )
              .toList(growable: false),
        ),
      );
    }
    return domain.StageRoutine(
      stageId: stageId,
      teachingWeekdays: days
          .where((day) => day.isTeachingDay)
          .map((day) => day.weekday)
          .toSet(),
      periodTypes: periods,
      overrides: overrideRows
          .map(
            (row) => domain.RoutineOverride(
              periodTypeId: row.periodTypeId,
              weekday: row.weekday,
              lessonCount: row.lessonCount,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _createDefaultStage(String termId) async {
    final stageId = _newId();
    await _database
        .into(_database.schoolStages)
        .insert(
          SchoolStagesCompanion.insert(
            id: stageId,
            termId: termId,
            name: '小学部',
            sortOrder: 0,
          ),
        );
    await _createDefaultRoutine(stageId);
  }

  Future<void> _createDefaultRoutine(String stageId) async {
    const defaultPeriods = [
      ('早上', 0, 'early'),
      ('上午', 4, '0'),
      ('下午', 4, '1'),
      ('晚上', 2, '2'),
    ];
    for (var index = 0; index < defaultPeriods.length; index++) {
      final (name, count, key) = defaultPeriods[index];
      final periodId = '${stageId}_period_$key';
      await _database
          .into(_database.lessonPeriodTypes)
          .insert(
            LessonPeriodTypesCompanion.insert(
              id: periodId,
              stageId: stageId,
              name: name,
              defaultLessonCount: count,
              sortOrder: index,
            ),
          );
      for (var lessonIndex = 1; lessonIndex <= count; lessonIndex++) {
        await _database
            .into(_database.lessonTimes)
            .insert(
              LessonTimesCompanion.insert(
                id: '${periodId}_$lessonIndex',
                periodTypeId: periodId,
                lessonIndex: lessonIndex,
                label: '第 $lessonIndex 节',
                startMinute: const Value(null),
                endMinute: const Value(null),
              ),
            );
      }
    }
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      await _database
          .into(_database.stageTeachingDays)
          .insert(
            StageTeachingDaysCompanion.insert(
              id: '${stageId}_day_$weekday',
              stageId: stageId,
              weekday: weekday,
              isTeachingDay: weekday <= DateTime.friday,
            ),
          );
    }
  }

  void _validateRoutine(domain.StageRoutine routine) {
    if (routine.teachingWeekdays.any((day) => day < 1 || day > 7)) {
      throw ArgumentError('上课日必须在星期一至星期日之间');
    }
    final periodIds = routine.periodTypes.map((period) => period.id).toSet();
    if (periodIds.length != routine.periodTypes.length) {
      throw ArgumentError('时段类型 ID 不能重复');
    }
    for (final period in routine.periodTypes) {
      if (period.name.trim().isEmpty) {
        throw ArgumentError('时段类型名称不能为空');
      }
      if (period.defaultLessonCount < 0 || period.defaultLessonCount > 9) {
        throw ArgumentError('每个时段类型每天最多 9 节');
      }
      final indices = period.lessonTimes
          .map((time) => time.lessonIndex)
          .toSet();
      if (indices.length != period.lessonTimes.length) {
        throw ArgumentError('同一时段的节次序号不能重复');
      }
      for (final time in period.lessonTimes) {
        if ((time.startMinute == null) != (time.endMinute == null)) {
          throw ArgumentError('节次开始和结束时间需要同时填写');
        }
        if (time.startMinute != null && time.startMinute! >= time.endMinute!) {
          throw ArgumentError('节次开始时间必须早于结束时间');
        }
      }
    }
    final keys = <String>{};
    for (final override in routine.overrides) {
      final key = '${override.periodTypeId}_${override.weekday}';
      if (!periodIds.contains(override.periodTypeId)) {
        throw ArgumentError('按天覆盖引用了不存在的时段');
      }
      if (override.weekday < 1 || override.weekday > 7) {
        throw ArgumentError('按天覆盖的星期不正确');
      }
      if (override.lessonCount < 0 || override.lessonCount > 9) {
        throw ArgumentError('按天节数必须在 0 到 9 之间');
      }
      if (!keys.add(key)) throw ArgumentError('同一时段的同一天只能有一条覆盖设置');
    }
  }

  domain.AcademicTerm _toDomainTerm(AcademicTerm row) => domain.AcademicTerm(
    id: row.id,
    title: row.title,
    academicYear: row.academicYear,
    semesterLabel: row.semesterLabel,
    firstTeachingWeekStart: row.firstTeachingWeekStart == null
        ? null
        : DateTime.tryParse(row.firstTeachingWeekStart!),
    teachingWeekCount: row.teachingWeekCount,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    cycleMode: domain.AcademicTermCycle.fromStorage(row.cycleMode),
  );

  domain.SchoolStage _toDomainStage(SchoolStage row) => domain.SchoolStage(
    id: row.id,
    termId: row.termId,
    name: row.name,
    sortOrder: row.sortOrder,
  );

  domain.GradeGroup _toDomainGrade(GradeGroup row) => domain.GradeGroup(
    id: row.id,
    stageId: row.stageId,
    name: row.name,
    sortOrder: row.sortOrder,
  );

  domain.ClassGroup _toDomainClass(ClassGroup row) => domain.ClassGroup(
    id: row.id,
    gradeId: row.gradeId,
    name: row.name,
    sortOrder: row.sortOrder,
  );

  domain.CalendarException _toDomainException(CalendarException row) =>
      domain.CalendarException(
        id: row.id,
        termId: row.termId,
        date: _dateFromStorage(row.date),
        kind: domain.CalendarExceptionKind.fromStorage(row.kind),
        makeupWeekday: row.makeupWeekday,
        makeupForDate: row.makeupForDate == null
            ? null
            : _dateFromStorage(row.makeupForDate!),
        note: row.note,
      );

  domain.FreeSlot _toDomainFreeSlot(FreeSlot row) => domain.FreeSlot(
    id: row.id,
    scope: domain.FreeSlotScope.fromStorage(row.scopeType),
    scopeId: row.scopeId,
    stageId: row.stageId,
    periodTypeId: row.periodTypeId,
    weekday: row.weekday,
    lessonIndex: row.lessonIndex,
    label: row.label,
  );

  domain.CommonPeriod _toDomainCommonPeriod(CommonPeriod row) =>
      domain.CommonPeriod(
        id: row.id,
        stageId: row.stageId,
        name: row.name,
        insertAfterLessonId: row.insertAfterLessonId,
        durationMinutes: row.durationMinutes,
        startMinute: row.startMinute,
        endMinute: row.endMinute,
      );

  static String _dateStorage(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime _dateFromStorage(String value) {
    final parts = value.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static int _idCounter = 0;

  static String _newId() =>
      'id_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  // —— 科目与科目节数 ——

  @override
  Stream<List<domain.Subject>> watchSubjects() =>
      (_database.select(_database.subjects)
            ..orderBy([(subject) => OrderingTerm.asc(subject.sortOrder)]))
          .watch()
          .map((rows) => rows.map(_toDomainSubject).toList(growable: false));

  @override
  Future<void> saveSubjects(List<domain.Subject> subjects) async {
    if (subjects.isEmpty) return;
    await _database.batch((batch) {
      batch.insertAll(_database.subjects, [
        for (final subject in subjects)
          SubjectsCompanion.insert(
            id: subject.id,
            name: subject.name.trim(),
            shortName: subject.shortName.trim(),
            sortOrder: subject.sortOrder,
          ),
      ], mode: InsertMode.insertOrReplace);
    });
  }

  @override
  Future<void> deleteSubject(String subjectId) => (_database.delete(
    _database.subjects,
  )..where((subject) => subject.id.equals(subjectId))).go();

  @override
  Stream<List<domain.SubjectRequirement>> watchRequirementsForGrade(
    String gradeId,
  ) =>
      (_database.select(
        _database.subjectRequirements,
      )..where((row) => row.gradeId.equals(gradeId))).watch().map(
        (rows) => rows.map(_toDomainRequirement).toList(growable: false),
      );

  @override
  Stream<List<domain.SubjectRequirement>> watchAllRequirements() =>
      (_database.select(_database.subjectRequirements)).watch().map(
        (rows) => rows.map(_toDomainRequirement).toList(growable: false),
      );

  @override
  Stream<List<domain.ClassBrief>> watchClassesForStage(String stageId) =>
      _database
          .customSelect(
            '''
            SELECT s.id AS stage_id, g.id AS grade_id, c.id AS class_id,
                   c.name AS class_name
            FROM class_groups c
            JOIN grade_groups g ON c.grade_id = g.id
            JOIN school_stages s ON g.stage_id = s.id
            WHERE s.id = ?
            ORDER BY g.sort_order ASC, c.sort_order ASC
            ''',
            variables: [Variable<String>(stageId)],
            readsFrom: {
              _database.classGroups,
              _database.gradeGroups,
              _database.schoolStages,
            },
          )
          .watch()
          .map(
            (rows) => [
              for (final row in rows)
                domain.ClassBrief(
                  stageId: row.read<String>('stage_id'),
                  gradeId: row.read<String>('grade_id'),
                  id: row.read<String>('class_id'),
                  name: row.read<String>('class_name'),
                ),
            ],
          );

  @override
  Stream<List<domain.GradeGroup>> watchGradesForTerm(String termId) => _database
      .customSelect(
        '''
            SELECT g.id AS g_id, g.stage_id AS g_stage_id,
                   g.name AS g_name, g.sort_order AS g_sort
            FROM grade_groups g
            JOIN school_stages s ON g.stage_id = s.id
            WHERE s.term_id = ?
            ORDER BY s.sort_order ASC, g.sort_order ASC
            ''',
        variables: [Variable<String>(termId)],
        readsFrom: {_database.gradeGroups, _database.schoolStages},
      )
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            domain.GradeGroup(
              id: row.read<String>('g_id'),
              stageId: row.read<String>('g_stage_id'),
              name: row.read<String>('g_name'),
              sortOrder: row.read<int>('g_sort'),
            ),
        ],
      );

  @override
  Stream<List<domain.ClassBrief>> watchClassesForTerm(String termId) =>
      _database
          .customSelect(
            '''
            SELECT s.id AS stage_id, g.id AS grade_id, c.id AS class_id,
                   c.name AS class_name
            FROM class_groups c
            JOIN grade_groups g ON c.grade_id = g.id
            JOIN school_stages s ON g.stage_id = s.id
            WHERE s.term_id = ?
            ORDER BY s.sort_order ASC, g.sort_order ASC, c.sort_order ASC
            ''',
            variables: [Variable<String>(termId)],
            readsFrom: {
              _database.classGroups,
              _database.gradeGroups,
              _database.schoolStages,
            },
          )
          .watch()
          .map(
            (rows) => [
              for (final row in rows)
                domain.ClassBrief(
                  stageId: row.read<String>('stage_id'),
                  gradeId: row.read<String>('grade_id'),
                  id: row.read<String>('class_id'),
                  name: row.read<String>('class_name'),
                ),
            ],
          );

  @override
  Stream<Map<String, domain.StageRoutine>> watchRoutinesForTerm(
    String termId,
  ) => _database
      .customSelect(
        'SELECT id FROM school_stages WHERE term_id = ?',
        variables: [Variable<String>(termId)],
        readsFrom: {
          _database.schoolStages,
          _database.stageTeachingDays,
          _database.lessonPeriodTypes,
          _database.dailyLessonOverrides,
          _database.lessonTimes,
        },
      )
      .watch()
      .asyncMap(
        (rows) async => {
          for (final row in rows)
            row.read<String>('id'): await _loadRoutine(row.read<String>('id')),
        },
      );

  @override
  Stream<List<domain.FreeSlot>> watchFreeSlotsForTerm(String termId) =>
      (_database.select(_database.freeSlots).join([
        innerJoin(
          _database.schoolStages,
          _database.schoolStages.id.equalsExp(_database.freeSlots.stageId),
        ),
      ])..where(_database.schoolStages.termId.equals(termId))).watch().map(
        (rows) => [
          for (final row in rows)
            _toDomainFreeSlot(row.readTable(_database.freeSlots)),
        ],
      );

  @override
  Future<void> replaceGradeRequirements({
    required String gradeId,
    required List<domain.SubjectRequirement> requirements,
  }) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.subjectRequirements,
      )..where((row) => row.gradeId.equals(gradeId))).go();
      if (requirements.isEmpty) return;
      await _database.batch((batch) {
        batch.insertAll(_database.subjectRequirements, [
          for (final requirement in requirements)
            SubjectRequirementsCompanion.insert(
              id: requirement.id,
              subjectId: requirement.subjectId,
              gradeId: requirement.gradeId,
              classId: Value(requirement.classId),
              weekMode: Value(requirement.weekMode.storageValue),
              lessonCount: Value(requirement.lessonCount),
            ),
        ]);
      });
    });
  }

  domain.Subject _toDomainSubject(Subject row) => domain.Subject(
    id: row.id,
    name: row.name,
    shortName: row.shortName,
    sortOrder: row.sortOrder,
  );

  // —— 科目预设与课程配对 ——

  @override
  Stream<List<domain.SubjectPreset>> watchPresetsForSubject(String subjectId) =>
      (_database.select(_database.subjectPresets)
            ..where((row) => row.subjectId.equals(subjectId)))
          .watch()
          .map((rows) => rows.map(_toDomainPreset).toList(growable: false));

  @override
  Stream<List<domain.SubjectPreset>> watchAllPresets() =>
      (_database.select(_database.subjectPresets))
          .watch()
          .map((rows) => rows.map(_toDomainPreset).toList(growable: false));

  @override
  Future<void> replaceSubjectPresets({
    required String subjectId,
    required String termId,
    required domain.FreeSlotScope scope,
    required String scopeId,
    required String stageId,
    required List<domain.SubjectPreset> presets,
  }) async {
    await _database.transaction(() async {
      // 范围网格总是对应单个学段的作息；即使 scope 为 school，也只替换
      // 当前学段的数据，避免把某一套作息的星期与时段映射到其他学段。
      await _deleteSubjectPresets(subjectId, scope, scopeId, stageId);
      if (presets.isEmpty) return;
      await _insertSubjectPresets(presets);
    });
  }

  @override
  Stream<List<domain.SubjectLessonConstraint>> watchLessonConstraintsForSubject(
    String subjectId,
  ) =>
      (_database.select(_database.subjectLessonConstraints)
            ..where((row) => row.subjectId.equals(subjectId)))
          .watch()
          .map((rows) => rows.map(_toDomainLessonConstraint).toList());

  @override
  Stream<List<domain.SubjectLessonConstraint>> watchAllLessonConstraints() =>
      _database
          .select(_database.subjectLessonConstraints)
          .watch()
          .map((rows) => rows.map(_toDomainLessonConstraint).toList());

  @override
  Future<void> replaceSubjectLessonConstraints({
    required String subjectId,
    required domain.FreeSlotScope scope,
    required String scopeId,
    required String stageId,
    required List<domain.SubjectLessonConstraint> constraints,
  }) async {
    if (scope == domain.FreeSlotScope.school) {
      throw ArgumentError.value(scope, 'scope', '科目限制不支持全校范围');
    }
    domain.SubjectLessonConstraint.validate(constraints);
    final weekdays = <int?>{};
    for (final constraint in constraints) {
      if (constraint.subjectId != subjectId ||
          constraint.scope != scope ||
          constraint.scopeId != scopeId ||
          constraint.stageId != stageId) {
        throw ArgumentError('限制记录必须全部属于传入的科目和范围');
      }
      if (!weekdays.add(constraint.weekday)) {
        throw ArgumentError('同一范围的同一天只能设置一条限制');
      }
    }
    await _database.transaction(() async {
      await (_database.delete(_database.subjectLessonConstraints)..where(
            (row) =>
                row.subjectId.equals(subjectId) &
                row.scopeType.equals(scope.storageValue) &
                row.scopeId.equals(scopeId) &
                row.stageId.equals(stageId),
          ))
          .go();
      if (constraints.isEmpty) return;
      await _database.batch((batch) {
        batch.insertAll(_database.subjectLessonConstraints, [
          for (final constraint in constraints)
            SubjectLessonConstraintsCompanion.insert(
              id: _newId(),
              subjectId: subjectId,
              scopeType: scope.storageValue,
              scopeId: scopeId,
              stageId: stageId,
              weekday: Value(constraint.weekday),
              minimumDailyLessons: Value(constraint.minimumDailyLessons),
              maximumDailyLessons: Value(constraint.maximumDailyLessons),
              minimumDailyConsecutivePairs: Value(
                constraint.minimumDailyConsecutivePairs,
              ),
              maximumDailyConsecutivePairs: Value(
                constraint.maximumDailyConsecutivePairs,
              ),
              minimumWeeklyConsecutivePairs: Value(
                constraint.minimumWeeklyConsecutivePairs,
              ),
              maximumWeeklyConsecutivePairs: Value(
                constraint.maximumWeeklyConsecutivePairs,
              ),
            ),
        ]);
      });
    });
  }

  Future<void> _deleteSubjectPresets(
    String subjectId,
    domain.FreeSlotScope scope,
    String scopeId,
    String stageId,
  ) =>
      (_database.delete(_database.subjectPresets)..where(
            (row) =>
                row.subjectId.equals(subjectId) &
                row.scopeType.equals(scope.storageValue) &
                row.scopeId.equals(scopeId) &
                row.stageId.equals(stageId),
          ))
          .go();

  Future<void> _insertSubjectPresets(List<domain.SubjectPreset> presets) async {
    if (presets.isEmpty) return;
    await _database.batch((batch) {
      batch.insertAll(_database.subjectPresets, [
        for (final preset in presets)
          SubjectPresetsCompanion.insert(
            id: _newId(),
            subjectId: preset.subjectId,
            scopeType: preset.scope.storageValue,
            scopeId: preset.scopeId,
            stageId: preset.stageId,
            weekday: preset.weekday,
            periodTypeId: preset.periodTypeId,
            lessonIndex: preset.lessonIndex,
            value: Value(preset.value.storageValue),
          ),
      ]);
    });
  }

  @override
  Stream<List<domain.SubjectPairing>> watchAllPairings() =>
      (_database.select(_database.subjectPairings))
          .watch()
          .map((rows) => rows.map(_toDomainPairing).toList(growable: false));

  @override
  Future<void> replaceClassPairings({
    required String classId,
    required List<domain.SubjectPairing> pairings,
  }) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.subjectPairings,
      )..where((row) => row.classId.equals(classId))).go();
      if (pairings.isEmpty) return;
      await _database.batch((batch) {
        batch.insertAll(_database.subjectPairings, [
          for (final pairing in pairings)
            SubjectPairingsCompanion.insert(
              id: _newId(),
              classId: pairing.classId,
              oddSubjectId: pairing.oddSubjectId,
              evenSubjectId: pairing.evenSubjectId,
            ),
        ]);
      });
    });
  }

  domain.SubjectPreset _toDomainPreset(SubjectPreset row) =>
      domain.SubjectPreset(
        id: row.id,
        subjectId: row.subjectId,
        scope: domain.FreeSlotScope.fromStorage(row.scopeType),
        scopeId: row.scopeId,
        stageId: row.stageId,
        weekday: row.weekday,
        periodTypeId: row.periodTypeId,
        lessonIndex: row.lessonIndex,
        value: domain.PresetValue.fromStorage(row.value),
      );

  domain.SubjectLessonConstraint _toDomainLessonConstraint(
    SubjectLessonConstraint row,
  ) => domain.SubjectLessonConstraint(
    id: row.id,
    subjectId: row.subjectId,
    scope: domain.FreeSlotScope.fromStorage(row.scopeType),
    scopeId: row.scopeId,
    stageId: row.stageId,
    weekday: row.weekday,
    minimumDailyLessons: row.minimumDailyLessons,
    maximumDailyLessons: row.maximumDailyLessons,
    minimumDailyConsecutivePairs: row.minimumDailyConsecutivePairs,
    maximumDailyConsecutivePairs: row.maximumDailyConsecutivePairs,
    minimumWeeklyConsecutivePairs: row.minimumWeeklyConsecutivePairs,
    maximumWeeklyConsecutivePairs: row.maximumWeeklyConsecutivePairs,
  );

  domain.SubjectPairing _toDomainPairing(SubjectPairing row) =>
      domain.SubjectPairing(
        id: row.id,
        classId: row.classId,
        oddSubjectId: row.oddSubjectId,
        evenSubjectId: row.evenSubjectId,
      );

  domain.SubjectRequirement _toDomainRequirement(SubjectRequirement row) =>
      domain.SubjectRequirement(
        id: row.id,
        subjectId: row.subjectId,
        gradeId: row.gradeId,
        weekMode: domain.WeekMode.fromStorage(row.weekMode),
        lessonCount: row.lessonCount,
        classId: row.classId,
      );
  @override
  Stream<List<domain.PublicRoom>> watchPublicRooms() =>
      (_database.select(_database.publicRooms)..orderBy([
            (row) => OrderingTerm.asc(row.sortOrder),
            (row) => OrderingTerm.asc(row.id),
          ]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (row) => domain.PublicRoom(
                    id: row.id,
                    name: row.name,
                    roomCount: row.roomCount,
                    capacityPerRoom: row.capacityPerRoom,
                    sortOrder: row.sortOrder,
                  ),
                )
                .toList(),
          );

  @override
  Future<void> savePublicRooms(List<domain.PublicRoom> rooms) async {
    final ids = <String>{};
    for (final room in rooms) {
      room.validate();
      if (!ids.add(room.id)) throw ArgumentError('公共教室 ID 重复');
    }
    await _database.transaction(() async {
      for (final room in rooms) {
        await _database
            .into(_database.publicRooms)
            .insertOnConflictUpdate(
              PublicRoomsCompanion.insert(
                id: room.id,
                name: room.name.trim(),
                roomCount: room.roomCount,
                capacityPerRoom: room.capacityPerRoom,
                sortOrder: room.sortOrder,
              ),
            );
      }
    });
  }

  @override
  Future<void> deletePublicRoom(String roomId) =>
      _database.transaction(() async {
        await (_database.delete(
          _database.subjectRoomAssignments,
        )..where((row) => row.roomId.equals(roomId))).go();
        await (_database.delete(
          _database.publicRooms,
        )..where((row) => row.id.equals(roomId))).go();
      });

  domain.SubjectRoomAssignment _toDomainRoomAssignment(
    SubjectRoomAssignment row,
  ) => domain.SubjectRoomAssignment(
    id: row.id,
    subjectId: row.subjectId,
    termId: row.termId,
    stageId: row.stageId,
    scope: domain.FreeSlotScope.fromStorage(row.scopeType),
    scopeId: row.scopeId,
    roomId: row.roomId,
  );

  domain.SubjectParallelLimit _toDomainParallelLimit(
    SubjectParallelLimit row,
  ) => domain.SubjectParallelLimit(
    id: row.id,
    subjectId: row.subjectId,
    termId: row.termId,
    stageId: row.stageId,
    scope: domain.FreeSlotScope.fromStorage(row.scopeType),
    scopeId: row.scopeId,
    maxParallelLessons: row.maxParallelLessons,
  );

  @override
  Stream<List<domain.SubjectRoomAssignment>> watchRoomReferences(
    String roomId,
  ) =>
      (_database.select(_database.subjectRoomAssignments)
            ..where((row) => row.roomId.equals(roomId)))
          .watch()
          .map((rows) => rows.map(_toDomainRoomAssignment).toList());

  @override
  Stream<List<domain.SubjectRoomAssignment>> watchSubjectRoomAssignments(
    String termId,
  ) =>
      (_database.select(_database.subjectRoomAssignments)
            ..where((row) => row.termId.equals(termId)))
          .watch()
          .map((rows) => rows.map(_toDomainRoomAssignment).toList());

  @override
  Stream<List<domain.SubjectParallelLimit>> watchSubjectParallelLimits(
    String termId,
  ) =>
      (_database.select(_database.subjectParallelLimits)
            ..where((row) => row.termId.equals(termId)))
          .watch()
          .map((rows) => rows.map(_toDomainParallelLimit).toList());

  Future<void> _validateRoomScope({
    required String termId,
    required String stageId,
    required domain.FreeSlotScope scope,
    required String scopeId,
    bool allowClass = true,
  }) async {
    if (scope == domain.FreeSlotScope.school ||
        (!allowClass && scope == domain.FreeSlotScope.schoolClass)) {
      throw ArgumentError('不支持此设置范围');
    }
    final stage = await (_database.select(
      _database.schoolStages,
    )..where((row) => row.id.equals(stageId))).getSingleOrNull();
    if (stage == null || stage.termId != termId) {
      throw ArgumentError('学段不属于指定学期');
    }
    if (scope == domain.FreeSlotScope.stage) {
      if (scopeId != stageId) throw ArgumentError('范围必须属于指定学段');
    } else {
      String? gradeId;
      if (scope == domain.FreeSlotScope.schoolClass) {
        final schoolClass = await (_database.select(
          _database.classGroups,
        )..where((row) => row.id.equals(scopeId))).getSingleOrNull();
        if (schoolClass == null) throw ArgumentError('班级不存在');
        gradeId = schoolClass.gradeId;
      } else {
        gradeId = scopeId;
      }
      final grade = await (_database.select(
        _database.gradeGroups,
      )..where((row) => row.id.equals(gradeId!))).getSingleOrNull();
      if (grade == null || grade.stageId != stageId) {
        throw ArgumentError('范围必须属于指定学段');
      }
    }
  }

  Future<void> _validateSubjectTerm(String subjectId, String termId) async {
    final subject = await (_database.select(
      _database.subjects,
    )..where((row) => row.id.equals(subjectId))).getSingleOrNull();
    final term = await (_database.select(
      _database.academicTerms,
    )..where((row) => row.id.equals(termId))).getSingleOrNull();
    if (subject == null || term == null) throw ArgumentError('科目或学期不存在');
  }

  Future<void> _insertRoomAssignments(
    List<domain.SubjectRoomAssignment> assignments,
  ) async {
    for (final row in assignments) {
      await _database
          .into(_database.subjectRoomAssignments)
          .insert(
            SubjectRoomAssignmentsCompanion.insert(
              id: _newId(),
              subjectId: row.subjectId,
              termId: row.termId,
              stageId: row.stageId,
              scopeType: row.scope.storageValue,
              scopeId: row.scopeId,
              roomId: Value(row.roomId),
            ),
          );
    }
  }

  Future<void> _insertParallelLimits(
    List<domain.SubjectParallelLimit> limits,
  ) async {
    for (final row in limits) {
      await _database
          .into(_database.subjectParallelLimits)
          .insert(
            SubjectParallelLimitsCompanion.insert(
              id: _newId(),
              subjectId: row.subjectId,
              termId: row.termId,
              stageId: row.stageId,
              scopeType: row.scope.storageValue,
              scopeId: row.scopeId,
              maxParallelLessons: row.maxParallelLessons,
            ),
          );
    }
  }

  @override
  Future<void> replaceSubjectRoomSettings({
    required String termId,
    required String subjectId,
    required List<domain.SubjectRoomAssignment> assignments,
    required List<domain.SubjectParallelLimit> limits,
  }) => _database.transaction(() async {
    await _validateSubjectTerm(subjectId, termId);
    final assignmentScopes = <(domain.FreeSlotScope, String)>{};
    for (final row in assignments) {
      if (row.subjectId != subjectId ||
          row.termId != termId ||
          !assignmentScopes.add((row.scope, row.scopeId))) {
        throw ArgumentError('公共教室记录必须属于指定科目和学期，且范围不能重复');
      }
      await _validateRoomScope(
        termId: termId,
        stageId: row.stageId,
        scope: row.scope,
        scopeId: row.scopeId,
      );
    }
    final limitScopes = <(domain.FreeSlotScope, String)>{};
    for (final row in limits) {
      if (row.subjectId != subjectId ||
          row.termId != termId ||
          row.maxParallelLessons <= 0 ||
          !limitScopes.add((row.scope, row.scopeId))) {
        throw ArgumentError('并行课节限制必须为正数并属于指定科目和学期，且范围不能重复');
      }
      await _validateRoomScope(
        termId: termId,
        stageId: row.stageId,
        scope: row.scope,
        scopeId: row.scopeId,
        allowClass: false,
      );
    }
    await (_database.delete(_database.subjectRoomAssignments)..where(
          (row) => row.termId.equals(termId) & row.subjectId.equals(subjectId),
        ))
        .go();
    await (_database.delete(_database.subjectParallelLimits)..where(
          (row) => row.termId.equals(termId) & row.subjectId.equals(subjectId),
        ))
        .go();
    await _insertRoomAssignments(assignments);
    await _insertParallelLimits(limits);
  });

  @override
  Future<void> replaceSubjectRoomAssignments({
    required String subjectId,
    required String termId,
    required String stageId,
    required domain.FreeSlotScope scope,
    required String scopeId,
    required List<domain.SubjectRoomAssignment> assignments,
  }) => _database.transaction(() async {
    await _validateSubjectTerm(subjectId, termId);
    await _validateRoomScope(
      termId: termId,
      stageId: stageId,
      scope: scope,
      scopeId: scopeId,
    );
    if (assignments.length > 1 ||
        assignments.any(
          (row) =>
              row.subjectId != subjectId ||
              row.termId != termId ||
              row.stageId != stageId ||
              row.scope != scope ||
              row.scopeId != scopeId,
        )) {
      throw ArgumentError('同一范围只能保存一条公共教室设置');
    }
    await (_database.delete(_database.subjectRoomAssignments)..where(
          (row) =>
              row.subjectId.equals(subjectId) &
              row.termId.equals(termId) &
              row.scopeType.equals(scope.storageValue) &
              row.scopeId.equals(scopeId),
        ))
        .go();
    await _insertRoomAssignments(assignments);
  });

  @override
  Future<void> replaceSubjectParallelLimits({
    required String subjectId,
    required String termId,
    required String stageId,
    required domain.FreeSlotScope scope,
    required String scopeId,
    required List<domain.SubjectParallelLimit> limits,
  }) => _database.transaction(() async {
    await _validateSubjectTerm(subjectId, termId);
    await _validateRoomScope(
      termId: termId,
      stageId: stageId,
      scope: scope,
      scopeId: scopeId,
      allowClass: false,
    );
    if (limits.length > 1 ||
        limits.any(
          (row) =>
              row.subjectId != subjectId ||
              row.termId != termId ||
              row.stageId != stageId ||
              row.scope != scope ||
              row.scopeId != scopeId ||
              row.maxParallelLessons <= 0,
        )) {
      throw ArgumentError('同一范围只能保存一条正数并行课节限制');
    }
    await (_database.delete(_database.subjectParallelLimits)..where(
          (row) =>
              row.subjectId.equals(subjectId) &
              row.termId.equals(termId) &
              row.scopeType.equals(scope.storageValue) &
              row.scopeId.equals(scopeId),
        ))
        .go();
    await _insertParallelLimits(limits);
  });

  Future<void> _deleteRoomScope(String scopeType, List<String> scopeIds) async {
    await (_database.delete(_database.subjectRoomAssignments)..where(
          (row) => row.scopeType.equals(scopeType) & row.scopeId.isIn(scopeIds),
        ))
        .go();
    await (_database.delete(_database.subjectParallelLimits)..where(
          (row) => row.scopeType.equals(scopeType) & row.scopeId.isIn(scopeIds),
        ))
        .go();
  }

  Future<void> _remapRoomScope(
    String scopeType,
    List<String> scopeIds,
    String stageId,
  ) async {
    if (scopeIds.isEmpty) return;
    final stage = await (_database.select(
      _database.schoolStages,
    )..where((row) => row.id.equals(stageId))).getSingle();
    await (_database.update(_database.subjectRoomAssignments)..where(
          (row) => row.scopeType.equals(scopeType) & row.scopeId.isIn(scopeIds),
        ))
        .write(
          SubjectRoomAssignmentsCompanion(
            stageId: Value(stageId),
            termId: Value(stage.termId),
          ),
        );
    await (_database.update(_database.subjectParallelLimits)..where(
          (row) => row.scopeType.equals(scopeType) & row.scopeId.isIn(scopeIds),
        ))
        .write(
          SubjectParallelLimitsCompanion(
            stageId: Value(stageId),
            termId: Value(stage.termId),
          ),
        );
  }
}
