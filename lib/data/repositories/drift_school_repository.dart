import 'package:class_set/data/database/app_database.dart';
import 'package:class_set/data/repositories/drift_temporary_adjustment_repository.dart';
import 'package:class_set/data/repositories/drift_scheduling_repository.dart';
import 'package:class_set/data/repositories/drift_supervision_repository.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart' as domain;
import 'package:class_set/domain/models/calendar_exception.dart' as domain;
import 'package:class_set/domain/models/common_period.dart' as domain;
import 'package:class_set/domain/models/free_slot.dart' as domain;
import 'package:class_set/domain/models/school_structure.dart' as domain;
import 'package:class_set/domain/models/stage_routine.dart' as domain;
import 'package:class_set/domain/models/subject.dart' as domain;
import 'package:class_set/domain/models/supervision.dart' as domain;
import 'package:class_set/domain/models/subject_lesson_constraint.dart'
    as domain;
import 'package:class_set/domain/models/public_room.dart' as domain;
import 'package:class_set/domain/models/subject_room_assignment.dart' as domain;
import 'package:class_set/domain/models/subject_parallel_limit.dart' as domain;
import 'package:class_set/domain/models/teacher.dart' as domain;
import 'package:class_set/domain/models/teacher_assignment.dart' as domain;
import 'package:class_set/domain/models/teacher_group.dart' as domain;
import 'package:class_set/domain/models/teacher_preset.dart' as domain;
import 'package:class_set/domain/models/schedule_condition.dart' as domain;
import 'package:class_set/domain/models/schedule_item.dart' as domain;
import 'package:class_set/domain/models/schedule_lock.dart' as domain;
import 'package:class_set/domain/models/schedule_preferences.dart' as domain;
import 'package:class_set/domain/models/schedule_run.dart' as domain;
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart' as domain;
import 'package:class_set/domain/scheduling/schedule_reconciler.dart';
import 'package:class_set/domain/scheduling/supervision_validation.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart' as domain;
import 'package:drift/drift.dart';

class DriftSchoolRepository implements SchoolRepository {
  const DriftSchoolRepository(this._database, {this.databasePath});

  final AppDatabase _database;
  final String? databasePath;

  DriftTemporaryAdjustmentRepository get _temporary =>
      DriftTemporaryAdjustmentRepository(_database, this);

  DriftSupervisionRepository get _supervision =>
      DriftSupervisionRepository(_database);

  @override
  Stream<domain.SupervisionDraft?> watchSupervisionDraft(String termId) =>
      _supervision.watchDraft(termId);

  @override
  Stream<List<domain.SupervisionVersion>> watchSupervisionVersions(
    String termId,
  ) => _supervision.watchVersions(termId);

  @override
  Future<domain.SupervisionDraft> saveSupervisionDraft(
    domain.SupervisionDraft draft, {
    required int expectedRevision,
  }) => _supervision.saveDraft(draft, expectedRevision: expectedRevision);

  Future<domain.TemporaryTimetableState> _projectSupervision(
    String termId,
    List<domain.SupervisionVersion> versions,
  ) => _temporary.load(termId, supervisionVersions: versions);

  Future<
    ({
      domain.SchedulingSnapshot? repair,
      domain.SchedulingSnapshot snapshot,
      String? repairError,
      List<String> scheduleChanges,
    })
  >
  _supervisionPublishInputs(String termId, DateTime date) async {
    final current = await loadSchedulingSnapshot(termId);
    final baseline = await loadPendingSchedulingBaseline(termId);
    if (baseline == null) {
      return (
        snapshot: current,
        repair: null,
        repairError: null,
        scheduleChanges: const <String>[],
      );
    }
    final issues = await _scheduling.invalidPublishedSupervision(current);
    if (issues.isEmpty) {
      return (
        snapshot: current,
        repair: null,
        repairError: '请先在「排课与课表」确认待协调变更',
        scheduleChanges: const <String>[],
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date != today) {
      return (
        snapshot: current,
        repair: null,
        repairError: '作息或人员变更影响现有带班，请选择「修正带班并协调」',
        scheduleChanges: const <String>[],
      );
    }
    final draft = await _supervision.watchDraft(termId).first;
    if (draft == null) throw StateError('请先保存带班草稿');
    final versions = await _supervision.loadVersions(termId);
    final repaired = await _scheduling.loadSchedulingSnapshot(
      termId,
      supervisionVersions: [
        ...versions.where((version) => version.effectiveDate.isBefore(today)),
        domain.SupervisionVersion(
          termId: termId,
          effectiveDate: today,
          draft: draft,
          occurrences: const SupervisionValidation().occurrences(
            current,
            draft,
          ),
        ),
      ],
    );
    final result = const ScheduleReconciler().preview(baseline, repaired);
    return (
      snapshot: repaired.copyWith(existingItems: result.items),
      repair: repaired,
      repairError: result.canApply ? null : '请先补齐待协调的任课或作息资料',
      scheduleChanges: [
        if (result.adjustments.isNotEmpty)
          '正课保留 ${result.keptCount} 节、移动 ${result.movedCount} 节、'
              '新增 ${result.addedCount} 节、移除 ${result.removedCount} 节、暂放 ${result.unplacedCount} 节',
        for (final change in result.adjustments)
          '${change.label}：${change.before} → ${change.after}',
      ],
    );
  }

  @override
  Future<domain.SupervisionPreview> previewSupervisionPublish(
    String termId,
    DateTime effectiveDate,
  ) => _database.transaction(() async {
    final inputs = await _supervisionPublishInputs(termId, effectiveDate);
    return _supervision.previewPublish(
      termId,
      effectiveDate,
      loadSnapshot: (_) async => inputs.snapshot,
      loadTemporary: (id, versions) => inputs.repair == null
          ? _projectSupervision(id, versions)
          : _temporary.load(
              id,
              supervisionVersions: versions,
              candidateSnapshot: inputs.snapshot,
            ),
      repair: inputs.repair != null,
      scheduleChanges: inputs.scheduleChanges,
      baselineTemporary: _temporary.load,
      extraError: inputs.repairError,
    );
  });

  @override
  Future<void> publishSupervision(
    String termId,
    domain.SupervisionPreview preview,
  ) async {
    final inputs = await _supervisionPublishInputs(
      termId,
      preview.effectiveDate,
    );
    if (inputs.repairError case final String error) throw StateError(error);
    if (inputs.repair case final repair?) {
      await _scheduling.commitScheduleReconciliation(
        termId: termId,
        expectedFingerprint: repair.inputFingerprint,
        supervisionRepair: repair,
        commitSupervisionRepair: () => _supervision.publish(
          termId,
          preview,
          loadSnapshot: (_) async => inputs.snapshot,
          loadTemporary: (id, versions) => _temporary.load(
            id,
            supervisionVersions: versions,
            candidateSnapshot: inputs.snapshot,
          ),
          repair: true,
          scheduleChanges: inputs.scheduleChanges,
          baselineTemporary: _temporary.load,
        ),
      );
      return;
    }
    await _database.transaction(() async {
      if (await loadPendingSchedulingBaseline(termId) != null) {
        throw StateError('课表正在等待协调，请刷新后重试');
      }
      await _supervision.publish(
        termId,
        preview,
        loadSnapshot: loadSchedulingSnapshot,
        loadTemporary: _projectSupervision,
        baselineTemporary: _temporary.load,
      );
    });
  }

  @override
  Future<void> commitTemporarySupervisionSubstitute({
    required String termId,
    required domain.TemporarySupervisionSubstituteRequest request,
    required String expectedRevision,
  }) => _temporary.commitSupervisionSubstitute(
    termId: termId,
    request: request,
    expectedRevision: expectedRevision,
  );

  @override
  Future<domain.TemporaryTimetableState> loadTemporaryTimetable(
    String termId,
  ) => _temporary.load(termId);

  @override
  Future<void> commitTemporaryMove({
    required String termId,
    required domain.TemporaryMoveRequest request,
    required String expectedRevision,
  }) => _temporary.commitMove(
    termId: termId,
    request: request,
    expectedRevision: expectedRevision,
  );

  @override
  Future<void> commitTemporarySubstitute({
    required String termId,
    required domain.TemporarySubstituteRequest request,
    required String expectedRevision,
  }) => _temporary.commitSubstitute(
    termId: termId,
    request: request,
    expectedRevision: expectedRevision,
  );

  @override
  Future<void> commitTemporarySwap({
    required String termId,
    required domain.TemporarySwapRequest request,
    required String expectedRevision,
  }) => _temporary.commitSwap(
    termId: termId,
    request: request,
    expectedRevision: expectedRevision,
  );

  @override
  Future<void> cancelTemporaryAdjustment({
    required String termId,
    required String adjustmentId,
    required String expectedRevision,
  }) => _temporary.cancel(
    termId: termId,
    adjustmentId: adjustmentId,
    expectedRevision: expectedRevision,
  );

  DriftSchedulingRepository get _scheduling =>
      DriftSchedulingRepository(_database, this, databasePath: databasePath);

  Future<void> _captureForStage(String stageId) async {
    final stage = await (_database.select(
      _database.schoolStages,
    )..where((row) => row.id.equals(stageId))).getSingleOrNull();
    if (stage != null) {
      await _scheduling.captureReconciliationBaselineIfNeeded(stage.termId);
    }
  }

  Future<void> _captureForClass(String classId) async {
    final schoolClass = await (_database.select(
      _database.classGroups,
    )..where((row) => row.id.equals(classId))).getSingleOrNull();
    if (schoolClass == null) return;
    final grade = await (_database.select(
      _database.gradeGroups,
    )..where((row) => row.id.equals(schoolClass.gradeId))).getSingleOrNull();
    if (grade != null) await _captureForStage(grade.stageId);
  }

  @override
  Future<domain.SchedulingSnapshot> loadSchedulingSnapshot(String termId) =>
      _scheduling.loadSchedulingSnapshot(termId);

  @override
  Future<domain.SchedulingSnapshot?> loadPendingSchedulingBaseline(
    String termId,
  ) => _scheduling.loadPendingSchedulingBaseline(termId);

  @override
  Future<ScheduleCommitResult> commitScheduleReconciliation({
    required String termId,
    required String expectedFingerprint,
  }) => _scheduling.commitScheduleReconciliation(
    termId: termId,
    expectedFingerprint: expectedFingerprint,
  );

  @override
  Stream<ScheduleViewData> watchSchedule(String termId) =>
      _scheduling.watchSchedule(termId);

  @override
  Future<void> saveScheduleConfiguration({
    required String termId,
    required List<domain.ScheduleCondition> conditions,
    required domain.SchedulePreferences preferences,
  }) => _scheduling.saveScheduleConfiguration(
    termId: termId,
    conditions: conditions,
    preferences: preferences,
  );

  @override
  Future<void> setScheduleLock(
    domain.ScheduleLock lock, {
    required bool enabled,
  }) => _scheduling.setScheduleLock(lock, enabled: enabled);

  @override
  Future<void> setScheduleLocks({
    required List<domain.ScheduleLock> locks,
    required bool enabled,
  }) => _scheduling.setScheduleLocks(locks: locks, enabled: enabled);

  @override
  Future<ScheduleCommitResult> commitScheduleRun(
    domain.ScheduleRun run, {
    required Set<String> selectedClassIds,
  }) => _scheduling.commitScheduleRun(run, selectedClassIds: selectedClassIds);

  @override
  Future<void> commitManualScheduleEdit({
    required String termId,
    required String expectedFingerprint,
    required List<domain.ScheduleItem> before,
    required List<domain.ScheduleItem> after,
  }) => _scheduling.commitManualScheduleEdit(
    termId: termId,
    expectedFingerprint: expectedFingerprint,
    before: before,
    after: after,
  );

  @override
  Future<String?> loadActiveTermId() async {
    final settings = await (_database.select(
      _database.appSettings,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    return settings?.activeTermId;
  }

  @override
  Future<void> saveActiveTermId(String? termId) =>
      _database.transaction(() async {
        await _ensureAppSettings();
        await (_database.update(_database.appSettings)
              ..where((row) => row.id.equals(1)))
            .write(AppSettingsCompanion(activeTermId: Value(termId)));
      });

  @override
  Stream<String> watchSchoolName() =>
      (_database.select(_database.appSettings)
            ..where((row) => row.id.equals(1)))
          .watchSingleOrNull()
          .map((settings) => settings?.schoolName ?? '');

  @override
  Future<void> saveSchoolName(String name) => _database.transaction(() async {
    await _ensureAppSettings();
    await (_database.update(_database.appSettings)
          ..where((row) => row.id.equals(1)))
        .write(AppSettingsCompanion(schoolName: Value(name.trim())));
  });

  Future<void> _ensureAppSettings() async {
    await _database
        .into(_database.appSettings)
        .insert(
          const AppSettingsCompanion(id: Value(1)),
          mode: InsertMode.insertOrIgnore,
        );
  }

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
        if (existing == null) {
          // 学段自动创建，但不写入默认作息：作息数据由用户在「作息设置」
          // 保存后才落库（watchRoutine 返回 null 时由页面提供默认草稿）。
          await _createDefaultStage(term.id);
          await (_database.update(_database.subjects)
                ..where((row) => row.termId.isNull()))
              .write(SubjectsCompanion(termId: Value(term.id)));
        }
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
    final subjectIds = <String, String>{};

    final sourceSubjects = await (_database.select(
      _database.subjects,
    )..where((row) => row.termId.equals(sourceTermId))).get();
    for (final subject in sourceSubjects) {
      final newId = _newId();
      subjectIds[subject.id] = newId;
      await _database
          .into(_database.subjects)
          .insert(
            SubjectsCompanion.insert(
              id: newId,
              termId: Value(targetTerm.id),
              name: subject.name,
              shortName: subject.shortName,
              sortOrder: subject.sortOrder,
            ),
          );
      final tags = await (_database.select(
        _database.teacherSubjectTags,
      )..where((row) => row.subjectId.equals(subject.id))).get();
      for (final tag in tags) {
        await _database
            .into(_database.teacherSubjectTags)
            .insert(
              TeacherSubjectTagsCompanion.insert(
                teacherId: tag.teacherId,
                subjectId: newId,
              ),
            );
      }
    }

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
                sortOrder: Value(period.sortOrder),
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

    // 教师身份为全校范围的稳定实体，克隆学期时只克隆任课、分组与预设。
    final teacherIds = {
      for (final teacher in await _database.select(_database.teachers).get())
        teacher.id: teacher.id,
    };

    final groupIds = <String, String>{};
    final sourceGroups = await (_database.select(
      _database.teacherGroups,
    )..where((row) => row.termId.equals(sourceTermId))).get();
    for (final group in sourceGroups) {
      final newId = _newId();
      groupIds[group.id] = newId;
      await _database
          .into(_database.teacherGroups)
          .insert(
            TeacherGroupsCompanion.insert(
              id: newId,
              termId: targetTerm.id,
              name: group.name,
              description: Value(group.description),
              sortOrder: Value(group.sortOrder),
            ),
          );
      final members = await (_database.select(
        _database.teacherGroupMembers,
      )..where((row) => row.groupId.equals(group.id))).get();
      for (final member in members) {
        if (!teacherIds.containsKey(member.teacherId)) continue;
        await _database
            .into(_database.teacherGroupMembers)
            .insert(
              TeacherGroupMembersCompanion.insert(
                groupId: newId,
                teacherId: member.teacherId,
              ),
            );
      }
    }

    final sourceAssignments = await (_database.select(
      _database.teacherAssignments,
    )..where((row) => row.termId.equals(sourceTermId))).get();
    for (final assignment in sourceAssignments) {
      final targetTeacherId = assignment.teacherId == null
          ? null
          : teacherIds[assignment.teacherId!];
      final targetClassId = classIds[assignment.classId];
      final targetSubjectId = subjectIds[assignment.subjectId];
      if (targetClassId == null || targetSubjectId == null) continue;
      await _database
          .into(_database.teacherAssignments)
          .insert(
            TeacherAssignmentsCompanion.insert(
              id: _newId(),
              termId: targetTerm.id,
              teacherId: Value(targetTeacherId),
              subjectId: targetSubjectId,
              classId: targetClassId,
              weekMode: Value(assignment.weekMode),
              lessonCount: Value(assignment.lessonCount),
              sortOrder: Value(assignment.sortOrder),
              combinedLessonGroupId: Value(assignment.combinedLessonGroupId),
            ),
          );
    }

    final sourcePresets = await (_database.select(
      _database.teacherPresets,
    )..where((row) => row.termId.equals(sourceTermId))).get();
    for (final preset in sourcePresets) {
      final targetTeacherId = teacherIds[preset.teacherId];
      final targetStageId = stageIds[preset.stageId];
      final targetPeriodId = periodIds[preset.periodTypeId];
      final targetScopeId = switch (preset.scopeType) {
        'school' => targetTerm.id,
        'stage' => targetStageId,
        'grade' => gradeIds[preset.scopeId],
        'class' => classIds[preset.scopeId],
        _ => null,
      };
      if (targetTeacherId == null ||
          targetStageId == null ||
          targetPeriodId == null ||
          targetScopeId == null) {
        continue;
      }
      await _database
          .into(_database.teacherPresets)
          .insert(
            TeacherPresetsCompanion.insert(
              id: _newId(),
              termId: targetTerm.id,
              teacherId: targetTeacherId,
              scopeType: preset.scopeType,
              scopeId: targetScopeId,
              stageId: targetStageId,
              weekday: preset.weekday,
              periodTypeId: targetPeriodId,
              lessonIndex: preset.lessonIndex,
              weekMode: Value(preset.weekMode),
              value: Value(preset.value),
            ),
          );
    }

    final sourceGroupPresets =
        await (_database.select(_database.teacherGroupPresets).join([
          innerJoin(
            _database.teacherGroups,
            _database.teacherGroups.id.equalsExp(
              _database.teacherGroupPresets.groupId,
            ),
          ),
        ])..where(_database.teacherGroups.termId.equals(sourceTermId))).get();
    for (final joined in sourceGroupPresets) {
      final preset = joined.readTable(_database.teacherGroupPresets);
      final targetGroupId = groupIds[preset.groupId];
      final targetStageId = stageIds[preset.stageId];
      final targetPeriodId = periodIds[preset.periodTypeId];
      final targetScopeId = switch (preset.scopeType) {
        'school' => targetTerm.id,
        'stage' => targetStageId,
        'grade' => gradeIds[preset.scopeId],
        'class' => classIds[preset.scopeId],
        _ => null,
      };
      if (targetGroupId == null ||
          targetStageId == null ||
          targetPeriodId == null ||
          targetScopeId == null) {
        continue;
      }
      await _database
          .into(_database.teacherGroupPresets)
          .insert(
            TeacherGroupPresetsCompanion.insert(
              id: _newId(),
              groupId: targetGroupId,
              scopeType: preset.scopeType,
              scopeId: targetScopeId,
              stageId: targetStageId,
              weekday: preset.weekday,
              periodTypeId: targetPeriodId,
              lessonIndex: preset.lessonIndex,
              weekMode: Value(preset.weekMode),
              value: Value(preset.value),
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
  Future<void> saveStage(
    domain.SchoolStage stage,
  ) => _database.transaction(() async {
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
    // 不写入默认作息：作息数据由用户在「作息设置」保存后才落库。
    // 新学段的全校免任课继承保留：新学段暂无作息时按名称匹配自然为空；
    // 首次保存作息后由 saveRoutine 补做继承。
    if (existing == null) {
      await _inheritSchoolFreeSlots(stage.id, stage.termId);
    }
    if (existing != null && existing.termId != stage.termId) {
      await (_database.update(_database.subjectRoomAssignments)
            ..where((row) => row.stageId.equals(stage.id)))
          .write(SubjectRoomAssignmentsCompanion(termId: Value(stage.termId)));
      await (_database.update(_database.subjectParallelLimits)
            ..where((row) => row.stageId.equals(stage.id)))
          .write(SubjectParallelLimitsCompanion(termId: Value(stage.termId)));
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
          await _captureForStage(existing.stageId);
          await _captureForStage(grade.stageId);
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
    final grade = await (_database.select(
      _database.gradeGroups,
    )..where((row) => row.id.equals(gradeId))).getSingleOrNull();
    if (grade != null) await _captureForStage(grade.stageId);
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
  Future<void> saveClass(domain.ClassGroup classGroup) => _database.transaction(
    () async {
      final existing = await (_database.select(
        _database.classGroups,
      )..where((row) => row.id.equals(classGroup.id))).getSingleOrNull();
      if (existing != null && existing.gradeId != classGroup.gradeId) {
        await _captureForClass(classGroup.id);
        final targetGrade = await (_database.select(
          _database.gradeGroups,
        )..where((row) => row.id.equals(classGroup.gradeId))).getSingleOrNull();
        if (targetGrade != null) await _captureForStage(targetGrade.stageId);
      }
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
    },
  );

  @override
  Future<void> saveClasses(List<domain.ClassGroup> classes) =>
      _database.transaction(() async {
        for (final schoolClass in classes) {
          await saveClass(schoolClass);
        }
      });

  @override
  Future<void> deleteClass(String classId) => _database.transaction(() async {
    await _captureForClass(classId);
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
      final previous = await _loadRoutine(routine.stageId);
      if (_sameRoutine(previous, routine)) return;
      final stage = await (_database.select(
        _database.schoolStages,
      )..where((row) => row.id.equals(routine.stageId))).getSingleOrNull();
      if (stage != null) {
        await _scheduling.captureReconciliationBaselineIfNeeded(stage.termId);
      }
      // 保留现有时段类型的主键，避免更新作息时级联删除课表与免任课。
      // 删除无效节次前保留免任课和公共时段挂载点，用于后续清理与修复。
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
        _database.dailyLessonOverrides,
      )..where((item) => item.stageId.equals(routine.stageId))).go();
      final nextPeriodIds = routine.periodTypes
          .map((period) => period.id)
          .toSet();
      final previousPeriodIds = previous.periodTypes
          .map((period) => period.id)
          .toSet();
      for (final oldPeriod in previous.periodTypes) {
        if (nextPeriodIds.contains(oldPeriod.id)) continue;
        await (_database.delete(
          _database.lessonPeriodTypes,
        )..where((period) => period.id.equals(oldPeriod.id))).go();
      }

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
        if (previousPeriodIds.contains(period.id)) {
          await (_database.update(
            _database.lessonPeriodTypes,
          )..where((row) => row.id.equals(period.id))).write(
            LessonPeriodTypesCompanion(
              name: Value(period.name.trim()),
              defaultLessonCount: Value(period.defaultLessonCount),
              sortOrder: Value(period.sortOrder),
            ),
          );
        } else {
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
        }
        await (_database.delete(
          _database.lessonTimes,
        )..where((time) => time.periodTypeId.equals(period.id))).go();
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

      // 清理已删除节次的免任课；保留的时段不会重建外键记录。
      final validLessonIds = <String>{
        for (final period in routine.periodTypes)
          for (final time in period.lessonTimes)
            '${period.id}_${time.lessonIndex}',
      };
      for (final slot in preservedFreeSlots) {
        if (validLessonIds.contains(
          '${slot.periodTypeId}_${slot.lessonIndex}',
        )) {
          continue;
        }
        await (_database.delete(
          _database.freeSlots,
        )..where((row) => row.id.equals(slot.id))).go();
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

      // 学段此前从未保存过作息（如新建学段后直接进入作息设置保存）：
      // 补做全校免任课继承，覆盖创建学段时因无作息而跳过的部分。
      if (stage != null && previous.periodTypes.isEmpty) {
        await _inheritSchoolFreeSlots(routine.stageId, stage.termId);
      }
    });
  }

  bool _sameRoutine(domain.StageRoutine left, domain.StageRoutine right) {
    if (left.stageId != right.stageId ||
        left.teachingWeekdays.length != right.teachingWeekdays.length ||
        !left.teachingWeekdays.containsAll(right.teachingWeekdays) ||
        left.periodTypes.length != right.periodTypes.length ||
        left.overrides.length != right.overrides.length) {
      return false;
    }
    final periods = {for (final row in left.periodTypes) row.id: row};
    for (final row in right.periodTypes) {
      final old = periods[row.id];
      if (old == null ||
          old.name != row.name ||
          old.defaultLessonCount != row.defaultLessonCount ||
          old.sortOrder != row.sortOrder ||
          old.lessonTimes.length != row.lessonTimes.length) {
        return false;
      }
      final times = {
        for (final time in old.lessonTimes) time.lessonIndex: time,
      };
      for (final time in row.lessonTimes) {
        final before = times[time.lessonIndex];
        if (before == null ||
            before.label != time.label ||
            before.startMinute != time.startMinute ||
            before.endMinute != time.endMinute) {
          return false;
        }
      }
    }
    final overrides = {
      for (final row in left.overrides)
        '${row.periodTypeId}:${row.weekday}': row.lessonCount,
    };
    for (final row in right.overrides) {
      if (overrides['${row.periodTypeId}:${row.weekday}'] != row.lessonCount) {
        return false;
      }
    }
    return true;
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

    final versions = await _supervision.loadVersions(termId);
    if (versions.isNotEmpty) {
      final before = existing.map(_toDomainException).toList();
      final after = [
        ...before.where((item) => !replacingIds.contains(item.id)),
        ...upserts,
      ];
      final snapshot = await loadSchedulingSnapshot(termId);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      Set<String> duties(List<domain.CalendarException> exceptions) => {
        for (final row in const domain.ActualTimetable().expandSupervision(
          snapshot,
          exceptions,
          versions,
        ))
          if (!row.date.isBefore(today)) '${row.key}:${row.templateWeek}',
      };
      final previous = duties(before);
      final next = duties(after);
      if (previous.length != next.length || !previous.containsAll(next)) {
        await _scheduling.captureReconciliationBaselineIfNeeded(termId);
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
  Future<void> deleteCalendarException(String exceptionId) =>
      _database.transaction(() async {
        final row = await (_database.select(
          _database.calendarExceptions,
        )..where((item) => item.id.equals(exceptionId))).getSingleOrNull();
        if (row != null) {
          await saveCalendarExceptions(
            termId: row.termId,
            upserts: const [],
            deleteIds: {exceptionId},
          );
        }
      });

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
  Future<void> saveFreeSlot(domain.FreeSlot slot) =>
      _database.transaction(() async {
        final stage = await (_database.select(
          _database.schoolStages,
        )..where((row) => row.id.equals(slot.stageId))).getSingleOrNull();
        if (stage != null) {
          await _scheduling.captureReconciliationBaselineIfNeeded(stage.termId);
        }
        await _database
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
      });

  @override
  Future<void> deleteFreeSlot(String slotId) => _database.transaction(() async {
    final slot = await (_database.select(
      _database.freeSlots,
    )..where((row) => row.id.equals(slotId))).getSingleOrNull();
    if (slot != null) {
      final stage = await (_database.select(
        _database.schoolStages,
      )..where((row) => row.id.equals(slot.stageId))).getSingleOrNull();
      if (stage != null) {
        await _scheduling.captureReconciliationBaselineIfNeeded(stage.termId);
      }
    }
    await (_database.delete(
      _database.freeSlots,
    )..where((row) => row.id.equals(slotId))).go();
  });

  // —— 公共时段 ——

  @override
  Stream<List<domain.CommonPeriod>> watchCommonPeriods(String stageId) =>
      (_database.select(_database.commonPeriods)
            ..where((period) => period.stageId.equals(stageId))
            ..orderBy([
              (period) => OrderingTerm.asc(period.insertAfterLessonId),
              (period) => OrderingTerm.asc(period.sortOrder),
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
          sortOrder: Value(period.sortOrder),
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
    // 不写入默认作息：作息数据由用户在「作息设置」保存后才落库。
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
        sortOrder: row.sortOrder,
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
  Stream<List<domain.Subject>> watchSubjectsForTerm(String termId) =>
      (_database.select(_database.subjects)
            ..where((subject) => subject.termId.equals(termId))
            ..orderBy([(subject) => OrderingTerm.asc(subject.sortOrder)]))
          .watch()
          .map((rows) => rows.map(_toDomainSubject).toList(growable: false));

  @override
  Future<void> saveSubjects(List<domain.Subject> subjects) async {
    if (subjects.isEmpty) return;
    await _database.transaction(() async {
      final fallbackTerm = subjects.any((subject) => subject.termId == null)
          ? (await (_database.select(
                  _database.academicTerms,
                )..orderBy([(term) => OrderingTerm.asc(term.createdAt)])).get())
                .firstOrNull
          : null;
      final existingTerms = {
        for (final row in await _database.select(_database.subjects).get())
          row.id: row.termId,
      };
      for (final subject in subjects) {
        final termId = subject.termId ?? fallbackTerm?.id;
        final existingTermId = existingTerms[subject.id];
        if (existingTermId != null && existingTermId != termId) {
          throw StateError('不能将已有科目移动到其他学期');
        }
        await _database
            .into(_database.subjects)
            .insertOnConflictUpdate(
              SubjectsCompanion.insert(
                id: subject.id,
                termId: Value(termId),
                name: subject.name.trim(),
                shortName: subject.shortName.trim(),
                sortOrder: subject.sortOrder,
              ),
            );
      }
    });
  }

  @override
  Future<void> deleteSubject(String subjectId) =>
      _database.transaction(() async {
        final subject = await (_database.select(
          _database.subjects,
        )..where((row) => row.id.equals(subjectId))).getSingleOrNull();
        if (subject?.termId case final termId?) {
          await _scheduling.captureReconciliationBaselineIfNeeded(termId);
        }
        await (_database.delete(
          _database.subjects,
        )..where((row) => row.id.equals(subjectId))).go();
      });

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
      final previous = await (_database.select(
        _database.subjectRequirements,
      )..where((row) => row.gradeId.equals(gradeId))).get();
      final oldValues = {
        for (final row in previous)
          '${row.classId}:${row.subjectId}:${row.weekMode}:${row.lessonCount}',
      };
      final newValues = {
        for (final row in requirements)
          '${row.classId}:${row.subjectId}:${row.weekMode.storageValue}:${row.lessonCount}',
      };
      if (oldValues.length != newValues.length ||
          !oldValues.containsAll(newValues)) {
        final grade = await (_database.select(
          _database.gradeGroups,
        )..where((row) => row.id.equals(gradeId))).getSingleOrNull();
        if (grade != null) {
          final stage = await (_database.select(
            _database.schoolStages,
          )..where((row) => row.id.equals(grade.stageId))).getSingleOrNull();
          if (stage != null) {
            await _scheduling.captureReconciliationBaselineIfNeeded(
              stage.termId,
            );
          }
        }
      }
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
    termId: row.termId,
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
      await _captureForStage(stageId);
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
      await _captureForStage(stageId);
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
      await _captureForClass(classId);
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
      for (final term
          in await _database.select(_database.academicTerms).get()) {
        await _scheduling.captureReconciliationBaselineIfNeeded(term.id);
      }
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
        for (final term
            in await _database.select(_database.academicTerms).get()) {
          await _scheduling.captureReconciliationBaselineIfNeeded(term.id);
        }
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
    await _scheduling.captureReconciliationBaselineIfNeeded(termId);
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
    await _scheduling.captureReconciliationBaselineIfNeeded(termId);
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
    await _scheduling.captureReconciliationBaselineIfNeeded(termId);
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

  @override
  Stream<List<domain.Teacher>> watchTeachers(String termId) =>
      (_database.select(_database.teachers)..orderBy([
            (row) => OrderingTerm.asc(row.sortOrder),
            (row) => OrderingTerm.asc(row.name),
            (row) => OrderingTerm.asc(row.id),
          ]))
          .watch()
          .asyncMap((rows) async {
            if (rows.isEmpty) return <domain.Teacher>[];
            final tags = await (_database.select(
              _database.teacherSubjectTags,
            )..where((row) => row.teacherId.isIn(rows.map((e) => e.id)))).get();
            final tagsByTeacher = <String, Set<String>>{};
            for (final tag in tags) {
              tagsByTeacher
                  .putIfAbsent(tag.teacherId, () => <String>{})
                  .add(tag.subjectId);
            }
            return rows
                .map(
                  (row) => domain.Teacher(
                    id: row.id,
                    name: row.name,
                    shortName: row.shortName,
                    displayQualifier: row.displayQualifier.isEmpty
                        ? null
                        : row.displayQualifier,
                    sortOrder: row.sortOrder,
                    subjectIds: tagsByTeacher[row.id] ?? const <String>{},
                  ),
                )
                .toList(growable: false);
          });

  @override
  Future<void> saveTeachers(List<domain.Teacher> teachers) =>
      _database.transaction(() async {
        final ids = <String>{};
        for (final teacher in teachers) {
          if (!ids.add(teacher.id) || teacher.name.trim().isEmpty) {
            throw ArgumentError('教师 ID 不能重复且姓名不能为空');
          }
        }
        for (final teacher in teachers) {
          await _database
              .into(_database.teachers)
              .insertOnConflictUpdate(
                TeachersCompanion.insert(
                  id: teacher.id,
                  name: teacher.name.trim(),
                  shortName: Value(teacher.shortName.trim()),
                  displayQualifier: Value(
                    teacher.displayQualifier?.trim() ?? '',
                  ),
                  sortOrder: Value(teacher.sortOrder),
                ),
              );
          await (_database.delete(
            _database.teacherSubjectTags,
          )..where((row) => row.teacherId.equals(teacher.id))).go();
          for (final subjectId in teacher.subjectIds) {
            await _database
                .into(_database.teacherSubjectTags)
                .insertOnConflictUpdate(
                  TeacherSubjectTagsCompanion.insert(
                    teacherId: teacher.id,
                    subjectId: subjectId,
                  ),
                );
          }
        }
      });

  @override
  Future<void> importTeachersWithGroups({
    required String termId,
    required List<domain.Teacher> teachers,
    required Map<String, List<String>> groupsByTeacher,
    Set<String> replaceGroupsForTeachers = const {},
    Set<String> replaceSubjectsForTeachers = const {},
  }) => _database.transaction(() async {
    final term = await (_database.select(
      _database.academicTerms,
    )..where((row) => row.id.equals(termId))).getSingleOrNull();
    if (term == null) throw ArgumentError('学期不存在');
    final ids = teachers.map((teacher) => teacher.id).toSet();
    if (ids.length != teachers.length ||
        !ids.containsAll(groupsByTeacher.keys) ||
        !ids.containsAll(replaceGroupsForTeachers) ||
        !ids.containsAll(replaceSubjectsForTeachers)) {
      throw ArgumentError('教师数据无效或重复');
    }
    final existingGroups = await (_database.select(
      _database.teacherGroups,
    )..where((row) => row.termId.equals(termId))).get();
    final groups = <String, List<TeacherGroup>>{};
    var nextGroupOrder = existingGroups.fold<int>(
      0,
      (next, group) => group.sortOrder >= next ? group.sortOrder + 1 : next,
    );
    for (final group in existingGroups) {
      groups.putIfAbsent(group.name.trim(), () => []).add(group);
    }
    for (final group in existingGroups) {
      if (replaceGroupsForTeachers.isEmpty) break;
      final oldMembers =
          await (_database.select(_database.teacherGroupMembers)..where(
                (row) =>
                    row.groupId.equals(group.id) &
                    row.teacherId.isIn(replaceGroupsForTeachers),
              ))
              .get();
      if (oldMembers.isEmpty) continue;
      final preset =
          await (_database.select(_database.teacherGroupPresets)
                ..where((row) => row.groupId.equals(group.id))
                ..limit(1))
              .getSingleOrNull();
      if (preset != null &&
          oldMembers.any(
            (member) => !(groupsByTeacher[member.teacherId] ?? []).contains(
              group.name.trim(),
            ),
          )) {
        await _scheduling.captureReconciliationBaselineIfNeeded(termId);
      }
    }
    for (final entry in groupsByTeacher.entries) {
      for (final name in entry.value.map((item) => item.trim()).toSet()) {
        final matches = groups[name] ?? [];
        if (name.isEmpty || matches.length > 1) {
          throw ArgumentError('分组名称为空或不唯一：$name');
        }
        if (matches.isEmpty) continue;
        final groupId = matches.single.id;
        final oldMember =
            await (_database.select(_database.teacherGroupMembers)..where(
                  (row) =>
                      row.groupId.equals(groupId) &
                      row.teacherId.equals(entry.key),
                ))
                .getSingleOrNull();
        final preset =
            await (_database.select(_database.teacherGroupPresets)
                  ..where((row) => row.groupId.equals(groupId))
                  ..limit(1))
                .getSingleOrNull();
        if (oldMember == null && preset != null) {
          await _scheduling.captureReconciliationBaselineIfNeeded(termId);
        }
      }
    }
    final currentTags = await (_database.select(
      _database.teacherSubjectTags,
    )..where((row) => row.teacherId.isIn(ids))).get();
    final tagsByTeacher = <String, Set<String>>{};
    for (final tag in currentTags) {
      tagsByTeacher.putIfAbsent(tag.teacherId, () => {}).add(tag.subjectId);
    }
    final termSubjects = await (_database.select(
      _database.subjects,
    )..where((row) => row.termId.equals(termId))).get();
    final termSubjectIds = termSubjects.map((subject) => subject.id).toSet();
    await saveTeachers([
      for (final teacher in teachers)
        teacher.copyWith(
          subjectIds: replaceSubjectsForTeachers.contains(teacher.id)
              ? {
                  ...?tagsByTeacher[teacher.id]?.difference(termSubjectIds),
                  ...teacher.subjectIds,
                }
              : {...?tagsByTeacher[teacher.id], ...teacher.subjectIds},
        ),
    ]);
    final additions = <String, Set<String>>{};
    for (final entry in groupsByTeacher.entries) {
      for (final rawName in entry.value) {
        final name = rawName.trim();
        if (name.isEmpty) throw ArgumentError('分组名称不能为空');
        var matches = groups[name] ?? [];
        if (matches.length > 1) throw ArgumentError('分组名称“$name”不唯一');
        if (matches.isEmpty) {
          final group = domain.TeacherGroup(
            id: _newId(),
            termId: termId,
            name: name,
            sortOrder: nextGroupOrder++,
          );
          await saveTeacherGroup(group);
          final created = await (_database.select(
            _database.teacherGroups,
          )..where((row) => row.id.equals(group.id))).getSingle();
          matches = [created];
          groups[name] = matches;
        }
        additions.putIfAbsent(matches.single.id, () => {}).add(entry.key);
      }
    }
    for (final group in existingGroups) {
      if (replaceGroupsForTeachers.isNotEmpty) {
        additions.putIfAbsent(group.id, () => {});
      }
    }
    for (final entry in additions.entries) {
      final current = await (_database.select(
        _database.teacherGroupMembers,
      )..where((row) => row.groupId.equals(entry.key))).get();
      final oldIds = current.map((row) => row.teacherId).toSet();
      final members = {
        ...oldIds.difference(replaceGroupsForTeachers),
        ...entry.value,
      };
      if (members.length == oldIds.length && members.containsAll(oldIds)) {
        continue;
      }
      await replaceTeacherGroupMembers(
        groupId: entry.key,
        members: [
          for (final id in members)
            domain.TeacherGroupMember(
              id: '${entry.key}:$id',
              groupId: entry.key,
              teacherId: id,
            ),
        ],
      );
    }
  });

  @override
  Future<void> deleteTeacher(String teacherId) => _database.transaction(
    () async {
      final terms =
          (await (_database.select(
                _database.teacherAssignments,
              )..where((row) => row.teacherId.equals(teacherId))).get())
              .map((row) => row.termId)
              .toSet();
      final publishedTerms =
          await (_database.selectOnly(
                _database.supervisionPlanVersions,
                distinct: true,
              )..addColumns([_database.supervisionPlanVersions.termId]))
              .map((row) => row.read(_database.supervisionPlanVersions.termId)!)
              .get();
      for (final termId in publishedTerms.where((id) => !terms.contains(id))) {
        final snapshot = await loadSchedulingSnapshot(termId);
        if ([
          ...snapshot.visibleSupervision,
          ...snapshot.supervision,
        ].any((entry) => entry.teacherId == teacherId)) {
          terms.add(termId);
        }
      }
      for (final termId in terms) {
        await _scheduling.captureReconciliationBaselineIfNeeded(termId);
      }
      await (_database.update(_database.teacherAssignments)
            ..where((row) => row.teacherId.equals(teacherId)))
          .write(const TeacherAssignmentsCompanion(teacherId: Value(null)));
      await (_database.delete(
        _database.teachers,
      )..where((row) => row.id.equals(teacherId))).go();
    },
  );

  @override
  Future<int> countTeacherAssignments(String teacherId) async =>
      (await _database
              .customSelect(
                'SELECT COUNT(*) AS assignment_count '
                'FROM teacher_assignments WHERE teacher_id = ?',
                variables: [Variable<String>(teacherId)],
              )
              .getSingle())
          .read<int>('assignment_count');

  @override
  Stream<List<domain.TeacherAssignment>> watchTeacherAssignments(
    String termId,
  ) =>
      (_database.select(_database.teacherAssignments)
            ..where((row) => row.termId.equals(termId))
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (row) => domain.TeacherAssignment(
                    id: row.id,
                    termId: row.termId,
                    teacherId: row.teacherId ?? '',
                    classId: row.classId,
                    subjectId: row.subjectId,
                    weekMode: domain.WeekMode.fromStorage(row.weekMode),
                    lessonCount: row.lessonCount,
                    sortOrder: row.sortOrder,
                    combinedLessonGroupId: row.combinedLessonGroupId,
                  ),
                )
                .toList(growable: false),
          );

  @override
  Future<void> replaceTeacherAssignments({
    required String termId,
    required String classId,
    required String subjectId,
    required List<domain.TeacherAssignment> assignments,
  }) => _database.transaction(() async {
    final classRow = await (_database.select(
      _database.classGroups,
    )..where((row) => row.id.equals(classId))).getSingleOrNull();
    if (classRow == null) throw ArgumentError('班级不存在');
    final subject = await (_database.select(
      _database.subjects,
    )..where((row) => row.id.equals(subjectId))).getSingleOrNull();
    if (subject == null) throw ArgumentError('科目不存在');
    final teachers = await _database.select(_database.teachers).get();
    final teacherIds = teachers.map((row) => row.id).toSet();
    final seen = <String>{};
    for (final assignment in assignments) {
      if (assignment.termId != termId ||
          assignment.classId != classId ||
          assignment.subjectId != subjectId ||
          assignment.lessonCount <= 0 ||
          assignment.teacherId.isEmpty ||
          !teacherIds.contains(assignment.teacherId) ||
          !seen.add(assignment.id)) {
        throw ArgumentError('任课分配记录不属于当前班级/科目，或教师/课时无效');
      }
    }
    final requirements =
        await (_database.select(_database.subjectRequirements)..where(
              (row) =>
                  row.subjectId.equals(subjectId) &
                  row.gradeId.equals(classRow.gradeId),
            ))
            .get();
    final scopedRequirements = requirements
        .where((row) => row.classId == classId)
        .toList();
    final effectiveRequirements = scopedRequirements.isNotEmpty
        ? scopedRequirements
        : requirements.where((row) => row.classId == null).toList();
    final capacity = <String, int>{
      for (final requirement in effectiveRequirements)
        if (requirement.lessonCount > 0)
          requirement.weekMode: requirement.lessonCount,
    };
    if (assignments.isNotEmpty && capacity.isEmpty) {
      throw StateError('该科目尚未设置节数需求，不能分配任课');
    }
    for (final assignment in assignments) {
      if (!capacity.containsKey(assignment.weekMode.storageValue)) {
        throw StateError('该周模式尚未设置科目需求，不能分配任课');
      }
    }
    final totals = <String, int>{};
    for (final assignment in assignments) {
      totals.update(
        assignment.weekMode.storageValue,
        (value) => value + assignment.lessonCount,
        ifAbsent: () => assignment.lessonCount,
      );
    }
    for (final entry in totals.entries) {
      final limit = capacity[entry.key];
      if (limit != null && entry.value > limit) {
        throw StateError('任课总节数超过${entry.key}需求（${entry.value}/$limit），请先调整分配');
      }
    }
    final currentRows =
        await (_database.select(_database.teacherAssignments)..where(
              (row) =>
                  row.termId.equals(termId) &
                  row.classId.equals(classId) &
                  row.subjectId.equals(subjectId),
            ))
            .get();
    final replacementById = {
      for (final assignment in assignments) assignment.id: assignment,
    };
    final unchanged =
        currentRows.length == assignments.length &&
        currentRows.every((current) {
          final replacement = replacementById[current.id];
          return replacement != null &&
              current.teacherId == replacement.teacherId &&
              current.weekMode == replacement.weekMode.storageValue &&
              current.lessonCount == replacement.lessonCount &&
              current.sortOrder == replacement.sortOrder &&
              current.combinedLessonGroupId == null;
        });
    if (unchanged) return;
    await _scheduling.captureReconciliationBaselineIfNeeded(termId);
    final combinedGroupIds = currentRows
        .map((row) => row.combinedLessonGroupId)
        .whereType<String>()
        .toSet();
    for (final groupId in combinedGroupIds) {
      await (_database.update(_database.teacherAssignments)..where(
            (row) =>
                row.termId.equals(termId) &
                row.combinedLessonGroupId.equals(groupId),
          ))
          .write(
            const TeacherAssignmentsCompanion(
              combinedLessonGroupId: Value(null),
            ),
          );
    }
    await (_database.delete(_database.teacherAssignments)..where(
          (row) =>
              row.termId.equals(termId) &
              row.classId.equals(classId) &
              row.subjectId.equals(subjectId),
        ))
        .go();
    for (final assignment in assignments) {
      await _database
          .into(_database.teacherAssignments)
          .insert(
            TeacherAssignmentsCompanion.insert(
              id: assignment.id,
              termId: termId,
              teacherId: Value(assignment.teacherId),
              subjectId: subjectId,
              classId: classId,
              weekMode: Value(assignment.weekMode.storageValue),
              lessonCount: Value(assignment.lessonCount),
              sortOrder: Value(assignment.sortOrder),
              combinedLessonGroupId: const Value(null),
            ),
          );
    }
  });

  @override
  Future<void> addTeacherAssignments({
    required String termId,
    required List<domain.TeacherAssignment> assignments,
  }) => _database.transaction(() async {
    if (assignments.isEmpty) return;

    final classes = await _database.select(_database.classGroups).get();
    final classById = {for (final row in classes) row.id: row};
    final subjects = await _database.select(_database.subjects).get();
    final subjectIds = subjects.map((row) => row.id).toSet();
    final teachers = await _database.select(_database.teachers).get();
    final teacherIds = teachers.map((row) => row.id).toSet();
    final existingRows = await (_database.select(
      _database.teacherAssignments,
    )..where((row) => row.termId.equals(termId))).get();
    final existingIds = existingRows.map((row) => row.id).toSet();
    final incomingIds = <String>{};
    for (final assignment in assignments) {
      if (assignment.termId != termId ||
          classById[assignment.classId] == null ||
          !subjectIds.contains(assignment.subjectId) ||
          assignment.teacherId.isEmpty ||
          !teacherIds.contains(assignment.teacherId) ||
          assignment.lessonCount <= 0 ||
          existingIds.contains(assignment.id) ||
          !incomingIds.add(assignment.id)) {
        throw ArgumentError('任课分配记录、教师、科目或节数无效');
      }
    }

    final requirements = await _database
        .select(_database.subjectRequirements)
        .get();
    final requirementsByClass =
        <
          ({String classId, String subjectId}),
          List<domain.SubjectRequirement>
        >{};
    final requirementsByGrade =
        <
          ({String gradeId, String subjectId}),
          List<domain.SubjectRequirement>
        >{};
    for (final row in requirements) {
      final requirement = domain.SubjectRequirement(
        id: row.id,
        subjectId: row.subjectId,
        gradeId: row.gradeId,
        classId: row.classId,
        weekMode: domain.WeekMode.fromStorage(row.weekMode),
        lessonCount: row.lessonCount,
      );
      final classId = row.classId;
      if (classId == null) {
        requirementsByGrade
            .putIfAbsent((
              gradeId: row.gradeId,
              subjectId: row.subjectId,
            ), () => [])
            .add(requirement);
      } else {
        requirementsByClass
            .putIfAbsent((classId: classId, subjectId: row.subjectId), () => [])
            .add(requirement);
      }
    }

    final currentTotals =
        <({String classId, String subjectId, String weekMode}), int>{};
    for (final row in existingRows) {
      if (row.teacherId == null || row.teacherId!.isEmpty) continue;
      final key = (
        classId: row.classId,
        subjectId: row.subjectId,
        weekMode: row.weekMode,
      );
      currentTotals.update(
        key,
        (total) => total + row.lessonCount,
        ifAbsent: () => row.lessonCount,
      );
    }
    final additions =
        <({String classId, String subjectId, String weekMode}), int>{};
    final assignmentsByCell =
        <
          ({String classId, String subjectId}),
          List<domain.TeacherAssignment>
        >{};
    for (final assignment in assignments) {
      final key = (
        classId: assignment.classId,
        subjectId: assignment.subjectId,
        weekMode: assignment.weekMode.storageValue,
      );
      additions.update(
        key,
        (total) => total + assignment.lessonCount,
        ifAbsent: () => assignment.lessonCount,
      );
      assignmentsByCell
          .putIfAbsent((
            classId: assignment.classId,
            subjectId: assignment.subjectId,
          ), () => [])
          .add(assignment);
    }

    for (final cell in assignmentsByCell.keys) {
      final classRow = classById[cell.classId]!;
      final classRequirements =
          requirementsByClass[cell] ?? const <domain.SubjectRequirement>[];
      final effectiveRequirements = classRequirements.isNotEmpty
          ? classRequirements
          : requirementsByGrade[(
                  gradeId: classRow.gradeId,
                  subjectId: cell.subjectId,
                )] ??
                const <domain.SubjectRequirement>[];
      if (!effectiveRequirements.any(
        (requirement) => requirement.lessonCount > 0,
      )) {
        throw StateError('该科目尚未设置节数需求，不能分配任课');
      }
      final demandedModes = effectiveRequirements
          .where((requirement) => requirement.lessonCount > 0)
          .map((requirement) => requirement.weekMode)
          .toSet();
      if (assignmentsByCell[cell]!.any(
        (assignment) => !demandedModes.contains(assignment.weekMode),
      )) {
        throw StateError('该周模式尚未设置科目需求，不能分配任课');
      }
      for (final requirement in effectiveRequirements) {
        final key = (
          classId: cell.classId,
          subjectId: cell.subjectId,
          weekMode: requirement.weekMode.storageValue,
        );
        final total = (currentTotals[key] ?? 0) + (additions[key] ?? 0);
        if (total > requirement.lessonCount) {
          throw StateError(
            '任课总节数超过${requirement.weekMode.storageValue}需求（$total/${requirement.lessonCount}），请先调整分配',
          );
        }
      }
    }

    await _scheduling.captureReconciliationBaselineIfNeeded(termId);
    for (final assignment in assignments) {
      await _database
          .into(_database.teacherAssignments)
          .insert(
            TeacherAssignmentsCompanion.insert(
              id: assignment.id,
              termId: termId,
              teacherId: Value(assignment.teacherId),
              subjectId: assignment.subjectId,
              classId: assignment.classId,
              weekMode: Value(assignment.weekMode.storageValue),
              lessonCount: Value(assignment.lessonCount),
              sortOrder: Value(assignment.sortOrder),
            ),
          );
    }
  });

  @override
  Future<void> deleteTeacherAssignments({
    required String termId,
    required List<String> assignmentIds,
  }) => _database.transaction(() async {
    final ids = assignmentIds.toSet();
    if (ids.isEmpty) return;
    final rows = await (_database.select(
      _database.teacherAssignments,
    )..where((row) => row.termId.equals(termId) & row.id.isIn(ids))).get();
    await _scheduling.captureReconciliationBaselineIfNeeded(termId);
    final combinedGroupIds = rows
        .map((row) => row.combinedLessonGroupId)
        .whereType<String>()
        .toSet();
    for (final groupId in combinedGroupIds) {
      await (_database.update(_database.teacherAssignments)..where(
            (row) =>
                row.termId.equals(termId) &
                row.combinedLessonGroupId.equals(groupId),
          ))
          .write(
            const TeacherAssignmentsCompanion(
              combinedLessonGroupId: Value(null),
            ),
          );
    }
    await (_database.delete(
      _database.teacherAssignments,
    )..where((row) => row.termId.equals(termId) & row.id.isIn(ids))).go();
  });

  @override
  Future<void> combineTeacherAssignments({
    required String termId,
    required List<String> assignmentIds,
    required String combinedGroupId,
  }) => _database.transaction(() async {
    final ids = assignmentIds.toSet();
    if (ids.length < 2 ||
        ids.length != assignmentIds.length ||
        combinedGroupId.trim().isEmpty) {
      throw ArgumentError('合班至少需要两条不同的任课记录');
    }
    final rows = await (_database.select(
      _database.teacherAssignments,
    )..where((row) => row.termId.equals(termId) & row.id.isIn(ids))).get();
    if (rows.length != ids.length) {
      throw StateError('部分任课记录已不存在，请刷新后重试');
    }
    final first = rows.first;
    final classIds = <String>{};
    for (final row in rows) {
      if (row.teacherId == null ||
          row.teacherId != first.teacherId ||
          row.subjectId != first.subjectId ||
          row.weekMode != first.weekMode ||
          row.lessonCount != first.lessonCount ||
          row.combinedLessonGroupId != null ||
          !classIds.add(row.classId)) {
        throw StateError('合班要求教师、科目、单双周和节数一致，且每班仅选一条任课');
      }
    }
    final groupInUse =
        await (_database.select(_database.teacherAssignments)..where(
              (row) =>
                  row.termId.equals(termId) &
                  row.combinedLessonGroupId.equals(combinedGroupId),
            ))
            .getSingleOrNull();
    if (groupInUse != null) throw StateError('合班标识已存在，请重试');
    await _scheduling.captureReconciliationBaselineIfNeeded(termId);
    await (_database.update(
      _database.teacherAssignments,
    )..where((row) => row.termId.equals(termId) & row.id.isIn(ids))).write(
      TeacherAssignmentsCompanion(
        combinedLessonGroupId: Value(combinedGroupId),
      ),
    );
  });

  @override
  Future<void> separateTeacherAssignments({
    required String termId,
    required String combinedGroupId,
  }) => _database.transaction(() async {
    await _scheduling.captureReconciliationBaselineIfNeeded(termId);
    final affected =
        await (_database.update(_database.teacherAssignments)..where(
              (row) =>
                  row.termId.equals(termId) &
                  row.combinedLessonGroupId.equals(combinedGroupId),
            ))
            .write(
              const TeacherAssignmentsCompanion(
                combinedLessonGroupId: Value(null),
              ),
            );
    if (affected == 0) throw StateError('合班记录不存在，请刷新后重试');
  });

  @override
  Stream<List<domain.TeacherGroup>> watchTeacherGroups(String termId) =>
      (_database.select(_database.teacherGroups)
            ..where((row) => row.termId.equals(termId))
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .watch()
          .map(
            (rows) => rows
                .map(
                  (row) => domain.TeacherGroup(
                    id: row.id,
                    termId: row.termId,
                    name: row.name,
                    description: row.description.isEmpty
                        ? null
                        : row.description,
                    sortOrder: row.sortOrder,
                  ),
                )
                .toList(growable: false),
          );

  @override
  Stream<List<domain.TeacherGroupMember>> watchTeacherGroupMembers(
    String termId,
  ) =>
      (_database.select(_database.teacherGroupMembers).join([
        innerJoin(
          _database.teacherGroups,
          _database.teacherGroups.id.equalsExp(
            _database.teacherGroupMembers.groupId,
          ),
        ),
      ])..where(_database.teacherGroups.termId.equals(termId))).watch().map(
        (rows) => rows
            .map((joined) {
              final row = joined.readTable(_database.teacherGroupMembers);
              return domain.TeacherGroupMember(
                id: '${row.groupId}:${row.teacherId}',
                groupId: row.groupId,
                teacherId: row.teacherId,
              );
            })
            .toList(growable: false),
      );

  @override
  Future<void> saveTeacherGroup(domain.TeacherGroup group) async {
    final term = await (_database.select(
      _database.academicTerms,
    )..where((row) => row.id.equals(group.termId))).getSingleOrNull();
    if (term == null || group.name.trim().isEmpty) {
      throw ArgumentError('分组名称或学期无效');
    }
    await _database
        .into(_database.teacherGroups)
        .insertOnConflictUpdate(
          TeacherGroupsCompanion.insert(
            id: group.id,
            termId: group.termId,
            name: group.name.trim(),
            description: Value(group.description?.trim() ?? ''),
            sortOrder: Value(group.sortOrder),
          ),
        );
  }

  @override
  Future<void> saveTeacherGroupsWithMembers({
    required List<domain.TeacherGroup> groups,
    required List<domain.TeacherGroupMember> members,
  }) => _database.transaction(() async {
    if (groups.isEmpty) return;
    final groupIds = <String>{};
    final termId = groups.first.termId;
    for (final group in groups) {
      if (group.termId != termId ||
          group.name.trim().isEmpty ||
          !groupIds.add(group.id)) {
        throw ArgumentError('分组数据无效或重复');
      }
    }
    final teachers = await _database.select(_database.teachers).get();
    final teacherIds = teachers.map((teacher) => teacher.id).toSet();
    final seenMembers = <String>{};
    for (final member in members) {
      final key = '${member.groupId}:${member.teacherId}';
      if (!groupIds.contains(member.groupId) ||
          !teacherIds.contains(member.teacherId) ||
          !seenMembers.add(key)) {
        throw ArgumentError('分组成员不存在或重复');
      }
    }
    for (final group in groups) {
      await _database
          .into(_database.teacherGroups)
          .insert(
            TeacherGroupsCompanion.insert(
              id: group.id,
              termId: termId,
              name: group.name.trim(),
              description: Value(group.description?.trim() ?? ''),
              sortOrder: Value(group.sortOrder),
            ),
          );
    }
    for (final member in members) {
      await _database
          .into(_database.teacherGroupMembers)
          .insert(
            TeacherGroupMembersCompanion.insert(
              groupId: member.groupId,
              teacherId: member.teacherId,
            ),
          );
    }
  });

  @override
  Future<void> deleteTeacherGroup(String groupId) =>
      _database.transaction(() async {
        final group = await (_database.select(
          _database.teacherGroups,
        )..where((row) => row.id.equals(groupId))).getSingleOrNull();
        if (group == null) return;
        final preset =
            await (_database.select(_database.teacherGroupPresets)
                  ..where((row) => row.groupId.equals(groupId))
                  ..limit(1))
                .getSingleOrNull();
        if (preset != null) {
          await _scheduling.captureReconciliationBaselineIfNeeded(group.termId);
        }
        await (_database.delete(
          _database.teacherGroups,
        )..where((row) => row.id.equals(groupId))).go();
      });

  @override
  Future<void> replaceTeacherGroupMembers({
    required String groupId,
    required List<domain.TeacherGroupMember> members,
  }) => _database.transaction(() async {
    final group = await (_database.select(
      _database.teacherGroups,
    )..where((row) => row.id.equals(groupId))).getSingleOrNull();
    if (group == null) throw ArgumentError('教师分组不存在');
    final teachers = await _database.select(_database.teachers).get();
    final teacherIds = teachers.map((row) => row.id).toSet();
    final ids = <String>{};
    for (final member in members) {
      if (member.groupId != groupId ||
          !teacherIds.contains(member.teacherId) ||
          !ids.add(member.teacherId)) {
        throw ArgumentError('分组成员无效或重复');
      }
    }
    final existing = await (_database.select(
      _database.teacherGroupMembers,
    )..where((row) => row.groupId.equals(groupId))).get();
    final oldIds = existing.map((row) => row.teacherId).toSet();
    if (oldIds.length != ids.length || !oldIds.containsAll(ids)) {
      final preset =
          await (_database.select(_database.teacherGroupPresets)
                ..where((row) => row.groupId.equals(groupId))
                ..limit(1))
              .getSingleOrNull();
      if (preset != null) {
        await _scheduling.captureReconciliationBaselineIfNeeded(group.termId);
      }
    }
    await (_database.delete(
      _database.teacherGroupMembers,
    )..where((row) => row.groupId.equals(groupId))).go();
    for (final member in members) {
      await _database
          .into(_database.teacherGroupMembers)
          .insert(
            TeacherGroupMembersCompanion.insert(
              groupId: groupId,
              teacherId: member.teacherId,
            ),
          );
    }
  });

  @override
  Stream<List<domain.TeacherPreset>> watchTeacherPresets(String termId) =>
      (_database.select(
        _database.teacherPresets,
      )..where((row) => row.termId.equals(termId))).watch().map(
        (rows) => rows.map(_toDomainTeacherPreset).toList(growable: false),
      );

  @override
  Stream<List<domain.TeacherGroupPreset>> watchTeacherGroupPresets(
    String termId,
  ) =>
      (_database.select(_database.teacherGroupPresets).join([
        innerJoin(
          _database.teacherGroups,
          _database.teacherGroups.id.equalsExp(
            _database.teacherGroupPresets.groupId,
          ),
        ),
      ])..where(_database.teacherGroups.termId.equals(termId))).watch().map(
        (rows) => rows
            .map(
              (row) => _toDomainTeacherGroupPreset(
                row.readTable(_database.teacherGroupPresets),
              ),
            )
            .toList(growable: false),
      );

  domain.TeacherPreset _toDomainTeacherPreset(TeacherPreset row) =>
      domain.TeacherPreset(
        id: row.id,
        teacherId: row.teacherId,
        scope: domain.TeacherPresetScope.fromStorage(row.scopeType),
        scopeId: row.scopeId,
        stageId: row.stageId,
        weekday: row.weekday,
        periodTypeId: row.periodTypeId,
        lessonIndex: row.lessonIndex,
        value: domain.PresetValue.fromStorage(row.value),
      );

  domain.TeacherGroupPreset _toDomainTeacherGroupPreset(
    TeacherGroupPreset row,
  ) => domain.TeacherGroupPreset(
    id: row.id,
    groupId: row.groupId,
    scope: domain.TeacherPresetScope.fromStorage(row.scopeType),
    scopeId: row.scopeId,
    stageId: row.stageId,
    weekday: row.weekday,
    periodTypeId: row.periodTypeId,
    lessonIndex: row.lessonIndex,
    value: domain.PresetValue.fromStorage(row.value),
  );

  @override
  Future<void> replaceTeacherPresets({
    required String termId,
    required String teacherId,
    required List<domain.TeacherPreset> presets,
  }) => _database.transaction(() async {
    await _scheduling.captureReconciliationBaselineIfNeeded(termId);
    await (_database.delete(_database.teacherPresets)..where(
          (row) => row.termId.equals(termId) & row.teacherId.equals(teacherId),
        ))
        .go();
    for (final preset in presets) {
      if (preset.teacherId != teacherId) throw ArgumentError('教师预设归属不一致');
      await _database
          .into(_database.teacherPresets)
          .insert(
            TeacherPresetsCompanion.insert(
              id: preset.id,
              termId: termId,
              teacherId: teacherId,
              scopeType: preset.scope.storageValue,
              scopeId: preset.scopeId,
              stageId: preset.stageId,
              weekday: preset.weekday,
              periodTypeId: preset.periodTypeId,
              lessonIndex: preset.lessonIndex,
              value: Value(preset.value.storageValue),
            ),
          );
    }
  });

  @override
  Future<void> replaceTeacherGroupPresets({
    required String groupId,
    required List<domain.TeacherGroupPreset> presets,
  }) => _database.transaction(() async {
    final group = await (_database.select(
      _database.teacherGroups,
    )..where((row) => row.id.equals(groupId))).getSingleOrNull();
    if (group != null) {
      await _scheduling.captureReconciliationBaselineIfNeeded(group.termId);
    }
    await (_database.delete(
      _database.teacherGroupPresets,
    )..where((row) => row.groupId.equals(groupId))).go();
    for (final preset in presets) {
      if (preset.groupId != groupId) throw ArgumentError('分组预设归属不一致');
      await _database
          .into(_database.teacherGroupPresets)
          .insert(
            TeacherGroupPresetsCompanion.insert(
              id: preset.id,
              groupId: groupId,
              scopeType: preset.scope.storageValue,
              scopeId: preset.scopeId,
              stageId: preset.stageId,
              weekday: preset.weekday,
              periodTypeId: preset.periodTypeId,
              lessonIndex: preset.lessonIndex,
              value: Value(preset.value.storageValue),
            ),
          );
    }
  });
}
