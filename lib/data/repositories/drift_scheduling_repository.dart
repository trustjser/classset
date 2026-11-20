import 'dart:convert';
import 'dart:io';

import 'package:class_set/data/backup/local_backup_service.dart';
import 'package:class_set/data/database/app_database.dart';
import 'package:class_set/data/repositories/drift_supervision_repository.dart';
import 'package:class_set/data/repositories/drift_temporary_adjustment_repository.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/combined_lesson_group.dart' as domain;
import 'package:class_set/domain/models/common_period.dart' as domain;
import 'package:class_set/domain/models/school_structure.dart' as domain;
import 'package:class_set/domain/models/schedule_condition.dart' as domain;
import 'package:class_set/domain/models/schedule_item.dart' as domain;
import 'package:class_set/domain/models/schedule_lock.dart' as domain;
import 'package:class_set/domain/models/schedule_position.dart' as domain;
import 'package:class_set/domain/models/schedule_preferences.dart' as domain;
import 'package:class_set/domain/models/schedule_run.dart' as domain;
import 'package:class_set/domain/models/subject.dart' as domain;
import 'package:class_set/domain/models/teacher_assignment.dart' as domain;
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/constraint_evaluator.dart';
import 'package:class_set/domain/scheduling/manual_schedule_editor.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart' as domain;
import 'package:class_set/domain/scheduling/supervision_validation.dart';
import 'package:class_set/domain/scheduling/schedule_reconciler.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:drift/drift.dart';

/// Persistence boundary for scheduling. Existing school data is converted to
/// domain objects before it reaches the solver.
class DriftSchedulingRepository {
  const DriftSchedulingRepository(
    this._database,
    this._source, {
    this.databasePath,
  });

  final AppDatabase _database;
  final SchoolRepository _source;
  final String? databasePath;

  static const _fingerprintTables = <String>[
    'academic_terms',
    'school_stages',
    'grade_groups',
    'class_groups',
    'stage_teaching_days',
    'lesson_period_types',
    'daily_lesson_overrides',
    'lesson_times',
    'free_slots',
    'subjects',
    'subject_requirements',
    'subject_presets',
    'subject_pairings',
    'subject_lesson_constraints',
    'public_rooms',
    'subject_room_assignments',
    'subject_parallel_limits',
    'teachers',
    'teacher_groups',
    'teacher_group_members',
    'teacher_assignments',
    'teacher_presets',
    'teacher_group_presets',
    'schedule_items',
    'schedule_locks',
    'schedule_conditions',
    'schedule_preferences',
    'supervision_plan_versions',
    'calendar_exceptions',
    'temporary_course_adjustments',
  ];

  Future<domain.SchedulingSnapshot> loadSchedulingSnapshot(
    String termId, {
    List<SupervisionVersion>? supervisionVersions,
  }) => _database.transaction(() async {
    final terms = await _source.watchTerms().first;
    final term = terms.where((item) => item.id == termId).firstOrNull;
    if (term == null) throw ArgumentError.value(termId, 'termId', '学期不存在');

    final stages = await _source.watchStages(termId).first;
    final grades = await _source.watchGradesForTerm(termId).first;
    final gradeIds = grades.map((item) => item.id).toSet();
    final stageIds = stages.map((item) => item.id).toSet();
    final classRows = await _database.select(_database.classGroups).get();
    final classes = classRows
        .where((row) => gradeIds.contains(row.gradeId))
        .map(
          (row) => domain.ClassGroup(
            id: row.id,
            gradeId: row.gradeId,
            name: row.name,
            sortOrder: row.sortOrder,
          ),
        )
        .toList(growable: false);
    final classIds = classes.map((item) => item.id).toSet();

    final routines = (await _source.watchRoutinesForTerm(termId).first).values
        .toList(growable: false);
    final subjects = await _source.watchSubjectsForTerm(termId).first;
    final subjectIds = subjects.map((item) => item.id).toSet();
    final requirements = (await _source.watchAllRequirements().first)
        .where((item) => gradeIds.contains(item.gradeId))
        .toList(growable: false);
    final assignments = await _source.watchTeacherAssignments(termId).first;
    final teachers = await _source.watchTeachers(termId).first;
    final freeSlots = await _source.watchFreeSlotsForTerm(termId).first;
    final subjectPresets = (await _source.watchAllPresets().first)
        .where(
          (item) =>
              subjectIds.contains(item.subjectId) &&
              stageIds.contains(item.stageId),
        )
        .toList(growable: false);
    final teacherPresets = await _source.watchTeacherPresets(termId).first;
    final teacherGroupPresets = await _source
        .watchTeacherGroupPresets(termId)
        .first;
    final teacherGroupMembers = await _source
        .watchTeacherGroupMembers(termId)
        .first;
    final lessonConstraints = (await _source.watchAllLessonConstraints().first)
        .where(
          (item) =>
              subjectIds.contains(item.subjectId) &&
              stageIds.contains(item.stageId),
        )
        .toList(growable: false);
    final pairings = (await _source.watchAllPairings().first)
        .where((item) => classIds.contains(item.classId))
        .toList(growable: false);
    final rooms = await _source.watchPublicRooms().first;
    final roomAssignments = await _source
        .watchSubjectRoomAssignments(termId)
        .first;
    final parallelLimits = await _source
        .watchSubjectParallelLimits(termId)
        .first;

    final grouped = <String, List<domain.TeacherAssignment>>{};
    for (final item in assignments) {
      final groupId = item.combinedLessonGroupId;
      if (groupId != null) grouped.putIfAbsent(groupId, () => []).add(item);
    }
    final combinedGroups = grouped.entries
        .map((entry) {
          final first = entry.value.first;
          return domain.CombinedLessonGroup(
            id: entry.key,
            termId: termId,
            teacherId: first.teacherId,
            subjectId: first.subjectId,
            weekMode: first.weekMode,
            classIds: entry.value
                .map((item) => item.classId)
                .toList(growable: false),
          );
        })
        .toList(growable: false);

    final snapshot = domain.SchedulingSnapshot(
      term: term,
      inputFingerprint: await _inputFingerprint(),
      stages: stages,
      grades: grades,
      classes: classes,
      routines: routines,
      subjects: subjects,
      requirements: requirements,
      teachers: teachers,
      assignments: assignments,
      freeSlots: freeSlots,
      subjectPresets: subjectPresets,
      teacherPresets: teacherPresets,
      teacherGroupPresets: teacherGroupPresets,
      teacherGroupMembers: teacherGroupMembers,
      lessonConstraints: lessonConstraints,
      pairings: pairings,
      rooms: rooms,
      roomAssignments: roomAssignments,
      parallelLimits: parallelLimits,
      combinedGroups: combinedGroups,
      conditions: await _loadConditions(termId),
      preferences: await _loadPreferences(termId),
      locks: await _loadLocks(termId),
      existingItems: await _loadItems(termId),
    );
    final versions =
        supervisionVersions ??
        await DriftSupervisionRepository(_database).loadVersions(termId);
    if (versions.isEmpty) return snapshot;

    final today = _today();
    final visible = SupervisionVersion.forDate(versions, today);
    final exceptions = await _source.watchCalendarExceptions(termId).first;
    final occupied = <String, SupervisionOccurrence>{};
    final weekModes = <String, Set<domain.WeekMode>>{};
    for (final actual in const ActualTimetable().expandSupervision(
      snapshot,
      exceptions,
      versions,
    )) {
      if (actual.date.isBefore(today)) continue;
      final mode = switch (actual.templateWeek?.isOdd) {
        true => domain.WeekMode.odd,
        false => domain.WeekMode.even,
        null => domain.WeekMode.weekly,
      };
      for (final occurrence in actual.occurrences) {
        final key = domain.supervisionReservationKey(occurrence);
        occupied[key] = occurrence;
        weekModes.putIfAbsent(key, () => {}).add(mode);
      }
    }
    return snapshot.copyWith(
      supervision: occupied.values.toList(),
      supervisionWeekModes: weekModes,
      visibleSupervision: visible?.occurrences ?? const [],
      supervisionCalendar: exceptions,
    );
  });

  Future<List<String>> invalidPublishedSupervision(
    domain.SchedulingSnapshot snapshot,
  ) async {
    final today = _today();
    final versions = await DriftSupervisionRepository(_database)
        .loadVersions(snapshot.term.id);
    final active = SupervisionVersion.forDate(versions, today);
    const validation = SupervisionValidation();
    final withoutCourses = snapshot.copyWith(existingItems: const []);
    return [
      for (final version in versions)
        if (version == active || version.effectiveDate.isAfter(today)) ...[
          ...validation.postErrors(withoutCourses, version.draft),
          if (version.occurrences.any(
            (row) => !snapshot.teachers.any(
              (teacher) => teacher.id == row.teacherId,
            ),
          ))
            '有效带班包含已删除的教师',
          if (version.occurrences.any(
            (row) => !validation
                .positions(snapshot, row.post)
                .any(
                  (position) =>
                      position.sameCell(row.position) &&
                      position.startMinute == row.position.startMinute &&
                      position.endMinute == row.position.endMinute,
                ),
          ))
            '有效带班的作息时间已变更',
        ],
    ];
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _validateSupervisionPlacements(
    domain.SchedulingSnapshot snapshot,
    Iterable<domain.ScheduleItem> items,
  ) {
    if (snapshot.supervision.isEmpty) return;
    final problem = const ProblemBuilder().build(snapshot);
    const evaluator = ConstraintEvaluator();
    for (final item in items) {
      final position = item.position;
      if (position == null) continue;
      final currentPosition = (problem.positionsByClass[item.classId] ?? [])
          .where(position.sameCell)
          .firstOrNull;
      final issue = evaluator
          .supervisionBlockers(snapshot, item.at(currentPosition ?? position))
          .firstOrNull;
      if (issue != null) throw StateError(issue.message);
    }
  }

  Future<void> _validateFutureSupervisionSubstitutions(
    domain.SchedulingSnapshot candidate,
  ) async {
    final termId = candidate.term.id;
    final rows =
        await (_database.select(_database.temporaryCourseAdjustments)
              ..where(
                (row) =>
                    row.termId.equals(termId) &
                    row.kind.equals('supervision-substitute') &
                    row.cancelledAt.isNull(),
              )
              ..limit(1))
            .get();
    if (rows.isEmpty) return;
    final temporary = DriftTemporaryAdjustmentRepository(_database, _source);
    final today = _today();
    final previous = await temporary.load(termId);
    final protectedIds = {
      for (final record in previous.records)
        if (record.cancelledAt == null &&
            !record.needsAttention &&
            record.supervisionChange?.before.date.isBefore(today) == false)
          record.id,
    };
    if (protectedIds.isEmpty) return;
    final proposed = await temporary.load(termId, candidateSnapshot: candidate);
    final conflict = proposed.records
        .where(
          (record) => protectedIds.contains(record.id) && record.needsAttention,
        )
        .firstOrNull;
    if (conflict != null) {
      final change = conflict.supervisionChange!;
      final date = change.before.date.toIso8601String().substring(0, 10);
      throw StateError('会使 $date 的「${change.before.post.name}」带班替班失效，请先处理该替班');
    }
  }

  Future<domain.SchedulingSnapshot?> loadPendingSchedulingBaseline(
    String termId,
  ) async {
    var row = await (_database.select(
      _database.scheduleReconciliationBaselines,
    )..where((entry) => entry.termId.equals(termId))).getSingleOrNull();
    if (row == null) {
      final snapshot = await loadSchedulingSnapshot(termId);
      if (!_requiresMeetingReconciliation(snapshot)) return null;
      // 仅记录旧课表供预览；确认前不改动任何课节或用户设置。
      await _database.transaction(() async {
        final current = await loadSchedulingSnapshot(termId);
        if (_requiresMeetingReconciliation(current)) {
          await captureReconciliationBaselineIfNeeded(termId);
        }
      });
      row = await (_database.select(
        _database.scheduleReconciliationBaselines,
      )..where((entry) => entry.termId.equals(termId))).getSingleOrNull();
    }
    if (row == null) return null;
    return domain.SchedulingSnapshot.fromJson(
      (jsonDecode(row.snapshotJson) as Map).cast<String, Object?>(),
    );
  }

  bool _requiresMeetingReconciliation(domain.SchedulingSnapshot snapshot) {
    if (snapshot.existingItems.isEmpty ||
        (snapshot.combinedGroups.isEmpty &&
            !snapshot.existingItems.any((item) => item.meetingId != null))) {
      return false;
    }
    final problem = const ProblemBuilder().build(
      snapshot.copyWith(locks: const []),
    );
    final expectedMeetings = {
      for (final unit in problem.units)
        for (final item in unit.items) item.id: item.meetingId,
    };
    // An old ID may differ from today's canonical ID, but its members
    // must still belong to one meeting under the current rules.
    final expectedByStoredMeeting = <String, String>{};
    for (final item in snapshot.existingItems) {
      final stored = item.meetingId;
      if (stored == null || !expectedMeetings.containsKey(item.id)) continue;
      final expected = expectedMeetings[item.id];
      if (expected == null ||
          expectedByStoredMeeting.putIfAbsent(stored, () => expected) !=
              expected) {
        return true;
      }
    }
    return problem.hasInconsistentCombinedMeetings(snapshot.existingItems);
  }

  // Only discard the baseline when every scheduling input and the timetable
  // still match it. Solver preferences that do not impose hard rules may vary.
  Future<void> _clearReconciliationIfUnchanged(String termId) async {
    final baseline = await loadPendingSchedulingBaseline(termId);
    if (baseline == null) return;
    final current = await loadSchedulingSnapshot(termId);
    String signature(domain.SchedulingSnapshot snapshot) {
      final data = snapshot.toJson();
      data.remove('inputFingerprint');
      final preferences = snapshot.preferences;
      data['preferences'] = {
        'protectLunchBreak': preferences.protectLunchBreak,
        'requireSeparate':
            preferences.consecutiveMode ==
            domain.ConsecutiveMode.requireSeparate,
        'requireProgress':
            preferences.checkProgressConsistency &&
            preferences.progressConsistency ==
                domain.ProgressConsistency.require,
      };
      return jsonEncode(data);
    }

    if (signature(baseline) == signature(current) &&
        !_requiresMeetingReconciliation(current)) {
      await (_database.delete(
        _database.scheduleReconciliationBaselines,
      )..where((row) => row.termId.equals(termId))).go();
    }
  }

  /// Called in the same transaction as a settings edit, before it can cascade
  /// away assignments, periods, or timetable items.
  Future<void> captureReconciliationBaselineIfNeeded(String termId) async {
    final pending = await (_database.select(
      _database.scheduleReconciliationBaselines,
    )..where((entry) => entry.termId.equals(termId))).getSingleOrNull();
    if (pending != null) return;
    final firstItem =
        await (_database.select(_database.scheduleItems)
              ..where((item) => item.termId.equals(termId))
              ..limit(1))
            .getSingleOrNull();
    if (firstItem == null &&
        (await DriftSupervisionRepository(_database).loadVersions(termId))
            .isEmpty) {
      return;
    }
    final snapshot = await loadSchedulingSnapshot(termId);
    if (firstItem == null && snapshot.supervision.isEmpty) return;
    await _database
        .into(_database.scheduleReconciliationBaselines)
        .insert(
          ScheduleReconciliationBaselinesCompanion.insert(
            termId: termId,
            snapshotJson: jsonEncode(snapshot.toJson()),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<ScheduleCommitResult> commitScheduleReconciliation({
    required String termId,
    required String expectedFingerprint,
    domain.SchedulingSnapshot? supervisionRepair,
    Future<void> Function()? commitSupervisionRepair,
  }) async {
    final baseline = await loadPendingSchedulingBaseline(termId);
    if (baseline == null) throw StateError('没有待协调的课表变更');
    final actual = await loadSchedulingSnapshot(termId);
    if (actual.inputFingerprint != expectedFingerprint ||
        (supervisionRepair != null &&
            supervisionRepair.inputFingerprint != expectedFingerprint)) {
      throw StateError('排课设置已再次变化，请重新生成调整预览');
    }
    if (supervisionRepair == null &&
        (await invalidPublishedSupervision(actual)).isNotEmpty) {
      throw StateError('作息或人员变更影响已生效带班，请先到「带班安排」修正并协调');
    }
    final current = supervisionRepair ?? actual;
    final preview = const ScheduleReconciler().preview(baseline, current);
    if (!preview.canApply) {
      throw StateError(
        preview.checks.firstWhere((check) => !check.ready).message,
      );
    }
    final backup = databasePath == null
        ? null
        : LocalBackupService(_database, File(databasePath!));
    if (backup != null) {
      await backup.createSnapshot(label: 'before-incremental-scheduling');
    }
    await _database.transaction(() async {
      if (await _inputFingerprint() != expectedFingerprint) {
        throw StateError('排课设置已再次变化，请重新生成调整预览');
      }
      final pending = await (_database.select(
        _database.scheduleReconciliationBaselines,
      )..where((entry) => entry.termId.equals(termId))).getSingleOrNull();
      if (pending == null) throw StateError('待协调记录已失效，请刷新');
      _validateSupervisionPlacements(current, preview.items);
      if (commitSupervisionRepair == null) {
        await _validateFutureSupervisionSubstitutions(
          current.copyWith(existingItems: preview.items),
        );
      } else {
        await commitSupervisionRepair();
      }
      for (final entry in preview.assignmentLessonCounts.entries) {
        if (entry.value == 0) {
          await (_database.delete(_database.teacherAssignments)..where(
                (row) => row.termId.equals(termId) & row.id.equals(entry.key),
              ))
              .go();
        } else {
          await (_database.update(_database.teacherAssignments)..where(
                (row) => row.termId.equals(termId) & row.id.equals(entry.key),
              ))
              .write(
                TeacherAssignmentsCompanion(lessonCount: Value(entry.value)),
              );
        }
      }
      for (final lock in preview.locksToRelease) {
        final scope = lock.scope == domain.ScheduleLockScope.teacher
            ? 'teacher'
            : 'class';
        await (_database.delete(_database.scheduleLocks)..where(
              (row) =>
                  row.termId.equals(termId) &
                  row.scope.equals(scope) &
                  row.targetId.equals(lock.targetId),
            ))
            .go();
      }
      await (_database.delete(
        _database.scheduleItems,
      )..where((row) => row.termId.equals(termId))).go();
      for (final item in preview.items) {
        final position = item.position;
        await _database
            .into(_database.scheduleItems)
            .insert(
              ScheduleItemsCompanion.insert(
                id: item.id,
                termId: item.termId,
                assignmentId: item.assignmentId,
                classId: item.classId,
                teacherId: Value(item.teacherId),
                subjectId: item.subjectId,
                weekMode: Value(item.weekMode.storageValue),
                combinedGroupId: Value(item.combinedGroupId),
                meetingId: Value(item.meetingId),
                stageId: Value(position?.stageId),
                weekday: Value(position?.weekday),
                periodTypeId: Value(position?.periodTypeId),
                lessonIndex: Value(position?.lessonIndex),
              ),
            );
      }
      await (_database.delete(
        _database.scheduleReconciliationBaselines,
      )..where((entry) => entry.termId.equals(termId))).go();
    });
    if (backup == null) return const ScheduleCommitResult();
    try {
      await backup.createSnapshot(label: 'after-incremental-scheduling');
      return const ScheduleCommitResult();
    } on Object catch (error) {
      return ScheduleCommitResult(backupWarning: '课表已保存，但自动备份失败：$error');
    }
  }

  Future<String> _inputFingerprint() async {
    // Two independent 32-bit rolling hashes give a stable, compact change
    // detector without adding a package dependency. Table names are fixed.
    var first = 0x811c9dc5;
    var second = 0x27d4eb2d;
    for (final table in _fingerprintTables) {
      final rows = await _database
          .customSelect('SELECT * FROM $table ORDER BY rowid')
          .get();
      final bytes = utf8.encode(
        jsonEncode([table, for (final row in rows) row.data]),
      );
      for (final byte in bytes) {
        first = ((first ^ byte) * 0x01000193) & 0xffffffff;
        second = ((second ^ byte) * 0x5bd1e995) & 0xffffffff;
      }
    }
    return '${first.toRadixString(16).padLeft(8, '0')}${second.toRadixString(16).padLeft(8, '0')}';
  }

  Future<List<domain.ScheduleItem>> _loadItems(String termId) async {
    final rows = await (_database.select(
      _database.scheduleItems,
    )..where((row) => row.termId.equals(termId))).get();
    return rows
        .map((row) {
          final position =
              row.stageId == null ||
                  row.weekday == null ||
                  row.periodTypeId == null ||
                  row.lessonIndex == null
              ? null
              : domain.SchedulePosition(
                  stageId: row.stageId!,
                  weekday: row.weekday!,
                  periodTypeId: row.periodTypeId!,
                  lessonIndex: row.lessonIndex!,
                );
          return domain.ScheduleItem(
            id: row.id,
            termId: row.termId,
            assignmentId: row.assignmentId,
            classId: row.classId,
            teacherId: row.teacherId ?? '',
            subjectId: row.subjectId,
            weekMode: domain.WeekMode.fromStorage(row.weekMode),
            combinedGroupId: row.combinedGroupId,
            meetingId: row.meetingId,
            position: position,
          );
        })
        .toList(growable: false);
  }

  Future<List<domain.ScheduleLock>> _loadLocks(String termId) async {
    final rows = await (_database.select(
      _database.scheduleLocks,
    )..where((row) => row.termId.equals(termId))).get();
    return rows
        .map(
          (row) => domain.ScheduleLock(
            termId: row.termId,
            scope: row.scope == 'teacher'
                ? domain.ScheduleLockScope.teacher
                : domain.ScheduleLockScope.schoolClass,
            targetId: row.targetId,
          ),
        )
        .toList(growable: false);
  }

  Future<List<domain.ScheduleCondition>> _loadConditions(String termId) async {
    final rows = await (_database.select(
      _database.scheduleConditions,
    )..where((row) => row.termId.equals(termId))).get();
    return rows
        .map(
          (row) => domain.ScheduleCondition(
            id: row.id,
            termId: row.termId,
            type: domain.ScheduleConditionType.values.byName(row.kind),
            name: row.name,
            targetType: row.targetKind == null
                ? null
                : domain.ScheduleConditionTarget.values.byName(row.targetKind!),
            targetId: row.targetId,
            otherTargetId: row.otherId,
            periodTypeId: row.periodTypeId,
            weekday: row.weekday,
            minimum: row.minCount,
            maximum: row.maxCount,
            exact: row.exactCount,
          ),
        )
        .toList(growable: false);
  }

  Future<domain.SchedulePreferences> _loadPreferences(String termId) async {
    final row = await (_database.select(
      _database.schedulePreferences,
    )..where((item) => item.termId.equals(termId))).getSingleOrNull();
    if (row == null) return const domain.SchedulePreferences();
    return domain.SchedulePreferences(
      strength: domain.ScheduleStrength.values.byName(row.strength),
      progressConsistency: domain.ProgressConsistency.values.byName(
        row.progressConsistency,
      ),
      teacherDistribution: domain.TeacherDistribution.values.byName(
        row.teacherDistribution,
      ),
      protectLunchBreak: row.lunchProtection,
      consecutiveMode: domain.ConsecutiveMode.values.byName(
        row.consecutivePolicy,
      ),
      checkProgressConsistency: row.detectProgressConsistency,
    );
  }

  Future<PublishedTimetable?> loadPublishedSchedule(String termId) async {
    final row = await (_database.select(
      _database.publishedSchedules,
    )..where((row) => row.termId.equals(termId))).getSingleOrNull();
    if (row == null) return null;
    final data = (jsonDecode(row.dataJson) as Map).cast<String, Object?>();
    final commonPeriods = (data['commonPeriods'] as Map).cast<String, List>();
    return PublishedTimetable(
      snapshot: domain.SchedulingSnapshot.fromJson(
        (data['snapshot'] as Map).cast<String, Object?>(),
      ),
      commonPeriods: {
        for (final entry in commonPeriods.entries)
          entry.key: [
            for (final period in entry.value)
              domain.CommonPeriod.fromJson(
                (period as Map).cast<String, Object?>(),
              ),
          ],
      },
    );
  }

  Future<PublishedTimetable> publishSchedule({
    required String termId,
    required String expectedFingerprint,
  }) => _database.transaction(() async {
    if (await loadPendingSchedulingBaseline(termId) != null) {
      throw StateError('请先完成草稿课表协调');
    }
    final draft = await loadSchedulingSnapshot(termId);
    if (draft.inputFingerprint != expectedFingerprint) {
      throw StateError('草稿或排课资料已变更，请刷新后重新确认发布');
    }
    if (!draft.existingItems.any((item) => item.isPlaced)) {
      throw StateError('请先在草稿版安排课程');
    }
    final issues = await invalidPublishedSupervision(draft);
    if (issues.isNotEmpty) throw StateError(issues.first);
    _validateSupervisionPlacements(draft, draft.existingItems);
    await _validateFutureSupervisionSubstitutions(draft);
    return _savePublishedSchedule(draft);
  });

  Future<void> migratePublishedSchedules() async {
    final rows = await _database
        .customSelect(
          'SELECT DISTINCT term_id FROM schedule_items WHERE stage_id IS NOT NULL '
          'UNION SELECT term_id FROM schedule_reconciliation_baselines',
        )
        .get();
    for (final row in rows) {
      final termId = row.read<String>('term_id');
      final baseline = await loadPendingSchedulingBaseline(termId);
      final snapshot = baseline ?? await loadSchedulingSnapshot(termId);
      if (snapshot.existingItems.any((item) => item.isPlaced)) {
        await _savePublishedSchedule(snapshot);
      }
    }
  }

  Future<PublishedTimetable> _savePublishedSchedule(
    domain.SchedulingSnapshot draft,
  ) async {
    final placed = draft.existingItems.where((item) => item.isPlaced);
    final snapshot = draft.copyWith(
      existingItems: placed.toList(),
      locks: const [],
    );
    final commonPeriods = {
      for (final stage in snapshot.stages)
        stage.id: await _source.watchCommonPeriods(stage.id).first,
    };
    await _database
        .into(_database.publishedSchedules)
        .insertOnConflictUpdate(
          PublishedSchedulesCompanion.insert(
            termId: snapshot.term.id,
            dataJson: jsonEncode({
              'snapshot': snapshot.toJson(),
              'commonPeriods': {
                for (final entry in commonPeriods.entries)
                  entry.key: entry.value
                      .map((period) => period.toJson())
                      .toList(),
              },
            }),
          ),
        );
    return PublishedTimetable(snapshot: snapshot, commonPeriods: commonPeriods);
  }

  Stream<ScheduleViewData> watchSchedule(String termId) => _database
      .customSelect(
        'SELECT COUNT(*) AS item_count FROM schedule_items WHERE term_id = ?',
        variables: [Variable<String>(termId)],
        readsFrom: {_database.scheduleItems, _database.scheduleRunReports},
      )
      .watch()
      .asyncMap((_) async {
        final items = await _loadItems(termId);
        final reports =
            await (_database.select(_database.scheduleRunReports)
                  ..where((row) => row.termId.equals(termId))
                  ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
                  ..limit(1))
                .get();
        final latest = reports.isEmpty
            ? null
            : domain.ScheduleRun.fromJson(
                (jsonDecode(reports.first.reportJson) as Map)
                    .cast<String, dynamic>(),
              );
        return ScheduleViewData(items: items, latestRun: latest);
      });

  Future<void> saveScheduleConfiguration({
    required String termId,
    required List<domain.ScheduleCondition> conditions,
    required domain.SchedulePreferences preferences,
  }) => _database.transaction(() async {
    if (conditions.any((item) => item.termId != termId)) {
      throw ArgumentError('排课条件的学期不一致');
    }
    for (final condition in conditions) {
      condition.validate();
    }
    String conditionSignature(List<domain.ScheduleCondition> rows) {
      final sorted = [...rows]..sort((a, b) => a.id.compareTo(b.id));
      return jsonEncode([
        for (final row in sorted)
          [
            row.id,
            row.type.name,
            row.name,
            row.targetType?.name,
            row.targetId,
            row.otherTargetId,
            row.periodTypeId,
            row.weekday,
            row.minimum,
            row.maximum,
            row.exact,
          ],
      ]);
    }

    final previousConditions = await _loadConditions(termId);
    final previousPreferences = await _loadPreferences(termId);
    if (conditionSignature(previousConditions) ==
            conditionSignature(conditions) &&
        jsonEncode(previousPreferences.toJson()) ==
            jsonEncode(preferences.toJson())) {
      await _clearReconciliationIfUnchanged(termId);
      return;
    }
    bool requiresProgressConsistency(domain.SchedulePreferences value) =>
        value.checkProgressConsistency &&
        value.progressConsistency == domain.ProgressConsistency.require;
    final hardRulesChanged =
        conditionSignature(previousConditions) !=
            conditionSignature(conditions) ||
        previousPreferences.protectLunchBreak !=
            preferences.protectLunchBreak ||
        (previousPreferences.consecutiveMode ==
                domain.ConsecutiveMode.requireSeparate) !=
            (preferences.consecutiveMode ==
                domain.ConsecutiveMode.requireSeparate) ||
        requiresProgressConsistency(previousPreferences) !=
            requiresProgressConsistency(preferences);
    if (hardRulesChanged) {
      await captureReconciliationBaselineIfNeeded(termId);
    }
    await (_database.delete(
      _database.scheduleConditions,
    )..where((row) => row.termId.equals(termId))).go();
    for (final item in conditions) {
      await _database
          .into(_database.scheduleConditions)
          .insert(
            ScheduleConditionsCompanion.insert(
              id: item.id,
              termId: termId,
              kind: item.type.name,
              name: Value(item.name),
              targetKind: Value(item.targetType?.name),
              targetId: Value(item.targetId),
              otherId: Value(item.otherTargetId),
              periodTypeId: Value(item.periodTypeId),
              weekday: Value(item.weekday),
              minCount: Value(item.minimum),
              maxCount: Value(item.maximum),
              exactCount: Value(item.exact),
            ),
          );
    }
    await _database
        .into(_database.schedulePreferences)
        .insertOnConflictUpdate(
          SchedulePreferencesCompanion.insert(
            termId: termId,
            strength: preferences.strength.name,
            progressConsistency: preferences.progressConsistency.name,
            teacherDistribution: preferences.teacherDistribution.name,
            lunchProtection: preferences.protectLunchBreak,
            consecutivePolicy: preferences.consecutiveMode.name,
            detectProgressConsistency: preferences.checkProgressConsistency,
          ),
        );
    await _clearReconciliationIfUnchanged(termId);
  });

  Future<void> setScheduleLock(
    domain.ScheduleLock lock, {
    required bool enabled,
  }) => setScheduleLocks(locks: [lock], enabled: enabled);

  Future<void> setScheduleLocks({
    required List<domain.ScheduleLock> locks,
    required bool enabled,
  }) async {
    if (locks.any(
      (lock) => lock.termId.trim().isEmpty || lock.targetId.trim().isEmpty,
    )) {
      throw ArgumentError('排课锁的学期或对象不能为空');
    }
    await _database.transaction(() async {
      for (final lock in locks) {
        final scope = lock.scope == domain.ScheduleLockScope.teacher
            ? 'teacher'
            : 'class';
        final id = '${lock.termId}:$scope:${lock.targetId}';
        if (enabled) {
          await _database
              .into(_database.scheduleLocks)
              .insertOnConflictUpdate(
                ScheduleLocksCompanion.insert(
                  id: id,
                  termId: lock.termId,
                  scope: scope,
                  targetId: lock.targetId,
                ),
              );
        } else {
          await (_database.delete(
            _database.scheduleLocks,
          )..where((row) => row.id.equals(id))).go();
        }
      }
    });
  }

  Future<void> commitManualScheduleEdit({
    required String termId,
    required String expectedFingerprint,
    required List<domain.ScheduleItem> before,
    required List<domain.ScheduleItem> after,
  }) async {
    if (termId.trim().isEmpty ||
        expectedFingerprint.trim().isEmpty ||
        before.isEmpty ||
        before.length != after.length) {
      throw ArgumentError('手动排课的课节范围无效');
    }

    final beforeById = <String, domain.ScheduleItem>{};
    for (final item in before) {
      if (item.id.trim().isEmpty ||
          item.termId != termId ||
          beforeById.containsKey(item.id)) {
        throw ArgumentError('手动排课包含重复课节或错误学期');
      }
      beforeById[item.id] = item;
    }
    final afterById = <String, domain.ScheduleItem>{};
    for (final item in after) {
      final original = beforeById[item.id];
      if (item.id.trim().isEmpty ||
          original == null ||
          item.termId != termId ||
          afterById.containsKey(item.id) ||
          !_sameScheduleIdentity(original, item)) {
        throw ArgumentError('手动排课只能更改原有课节的位置');
      }
      afterById[item.id] = item;
    }
    final changed = before
        .where(
          (item) =>
              _positionKey(item.position) !=
              _positionKey(afterById[item.id]!.position),
        )
        .toList(growable: false);

    if (await _inputFingerprint() != expectedFingerprint) {
      throw StateError('排课资料已改变，请刷新后重试');
    }

    if (changed.isNotEmpty && databasePath != null) {
      await LocalBackupService(
        _database,
        File(databasePath!),
      ).createSnapshot(label: 'before-manual-scheduling');
    }

    await _database.transaction(() async {
      if (await _inputFingerprint() != expectedFingerprint) {
        throw StateError('排课资料已改变，请刷新后重试');
      }
      final currentItems = await _loadItems(termId);
      final currentById = {for (final item in currentItems) item.id: item};
      for (final original in before) {
        final current = currentById[original.id];
        if (current == null ||
            !_sameScheduleIdentity(current, original) ||
            _positionKey(current.position) != _positionKey(original.position)) {
          throw StateError('课表已改变，请刷新后重试');
        }
      }

      if (changed.isEmpty) return;

      final snapshot = await loadSchedulingSnapshot(termId);
      final changedIds = changed.map((item) => item.id).toSet();
      final editedItems = [
        for (final item in currentItems) afterById[item.id] ?? item,
      ];
      final problem = const ProblemBuilder().build(snapshot);
      final blockers = const ManualScheduleEditor().validateEdit(
        problem: problem,
        before: currentItems,
        after: editedItems,
        changedItemIds: changedIds,
      );
      if (blockers.isNotEmpty) throw StateError(blockers.first.message);
      await _validateFutureSupervisionSubstitutions(
        snapshot.copyWith(existingItems: editedItems),
      );

      final locks = await _loadLocks(termId);
      bool isLocked(domain.ScheduleItem item) => locks.any(
        (lock) =>
            (lock.scope == domain.ScheduleLockScope.schoolClass &&
                lock.targetId == item.classId) ||
            (lock.scope == domain.ScheduleLockScope.teacher &&
                lock.targetId == item.teacherId),
      );

      for (final original in changed) {
        if (isLocked(original)) {
          throw StateError('受锁保护的课节不能移动');
        }
        final destination = afterById[original.id]!.position;
        if (destination == null) continue;
        for (final occupant in currentItems) {
          if (occupant.id == original.id ||
              occupant.classId != original.classId ||
              _positionKey(occupant.position) != destination.cellKey ||
              !_weekModesOverlap(occupant.weekMode, original.weekMode)) {
            continue;
          }
          if (isLocked(occupant)) {
            throw StateError('目标位置有受锁保护的课节');
          }
        }
      }

      for (final original in changed) {
        final position = afterById[original.id]!.position;
        final updated =
            await (_database.update(_database.scheduleItems)..where(
                  (row) =>
                      row.id.equals(original.id) & row.termId.equals(termId),
                ))
                .write(
                  ScheduleItemsCompanion(
                    stageId: Value(position?.stageId),
                    weekday: Value(position?.weekday),
                    periodTypeId: Value(position?.periodTypeId),
                    lessonIndex: Value(position?.lessonIndex),
                  ),
                );
        if (updated != 1) throw StateError('课表已改变，请刷新后重试');
      }
    });
  }

  static bool _sameScheduleIdentity(
    domain.ScheduleItem left,
    domain.ScheduleItem right,
  ) =>
      left.id == right.id &&
      left.termId == right.termId &&
      left.assignmentId == right.assignmentId &&
      left.classId == right.classId &&
      left.teacherId == right.teacherId &&
      left.subjectId == right.subjectId &&
      left.weekMode == right.weekMode &&
      left.combinedGroupId == right.combinedGroupId &&
      left.meetingId == right.meetingId;

  static String? _positionKey(domain.SchedulePosition? position) =>
      position?.cellKey;

  static bool _weekModesOverlap(domain.WeekMode left, domain.WeekMode right) =>
      left == domain.WeekMode.weekly ||
      right == domain.WeekMode.weekly ||
      left == right;

  Future<ScheduleCommitResult> commitScheduleRun(
    domain.ScheduleRun run, {
    required Set<String> selectedClassIds,
  }) async {
    if (selectedClassIds.isEmpty ||
        run.config.selectedClassIds.length != selectedClassIds.length ||
        !run.config.selectedClassIds.containsAll(selectedClassIds)) {
      throw ArgumentError('排课范围与结果不一致');
    }
    final ids = <String>{};
    for (final item in run.items) {
      if (item.termId != run.termId || !ids.add(item.id)) {
        throw ArgumentError('排课结果包含重复课节或错误学期');
      }
    }
    final selectedItems = run.items
        .where((item) => selectedClassIds.contains(item.classId))
        .toList(growable: false);
    final selectedIds = selectedItems.map((item) => item.id).toSet();
    final currentSnapshot = await loadSchedulingSnapshot(run.termId);
    final knownClassIds = currentSnapshot.classes
        .map((item) => item.id)
        .toSet();
    if (!knownClassIds.containsAll(selectedClassIds)) {
      throw ArgumentError('排课范围包含不存在的班级');
    }
    if (currentSnapshot.inputFingerprint != run.inputFingerprint) {
      throw StateError('排课资料已改变，请重新检查并排课');
    }
    for (final oldItem in currentSnapshot.existingItems) {
      if (!selectedClassIds.contains(oldItem.classId) || !oldItem.isPlaced) {
        continue;
      }
      final locked = currentSnapshot.locks.any(
        (lock) =>
            (lock.scope == domain.ScheduleLockScope.schoolClass &&
                lock.targetId == oldItem.classId) ||
            (lock.scope == domain.ScheduleLockScope.teacher &&
                lock.targetId == oldItem.teacherId),
      );
      if (!locked) continue;
      final replacement = selectedItems
          .where((item) => item.id == oldItem.id)
          .firstOrNull;
      if (replacement == null ||
          replacement.position?.cellKey != oldItem.position?.cellKey) {
        throw StateError('结果移动了受锁保护的课节');
      }
    }
    if (selectedIds.length != selectedItems.length) {
      throw ArgumentError('同一课节出现多次');
    }

    final backup = databasePath == null
        ? null
        : LocalBackupService(_database, File(databasePath!));
    if (backup != null) {
      // A failed pre-commit image prevents any change to the timetable.
      await backup.createSnapshot(label: 'before-scheduling');
    }

    await _database.transaction(() async {
      if (await _inputFingerprint() != run.inputFingerprint) {
        throw StateError('排课资料已改变，请重新检查并排课');
      }
      final finalItems = [
        for (final item in currentSnapshot.existingItems)
          if (!selectedClassIds.contains(item.classId)) item,
        ...selectedItems,
      ];
      final problem = const ProblemBuilder().build(
        currentSnapshot,
        selectedClassIds: selectedClassIds,
      );
      final unmet = const ConstraintEvaluator().unmetHardRequirements(
        problem,
        finalItems.map(problem.withClock).toList(),
      );
      if (unmet.isNotEmpty) throw StateError(unmet.first.message);
      _validateSupervisionPlacements(currentSnapshot, selectedItems);
      await _validateFutureSupervisionSubstitutions(
        currentSnapshot.copyWith(existingItems: finalItems),
      );
      await (_database.delete(_database.scheduleItems)..where(
            (row) =>
                row.termId.equals(run.termId) &
                row.classId.isIn(selectedClassIds),
          ))
          .go();
      for (final item in selectedItems) {
        final position = item.position;
        await _database
            .into(_database.scheduleItems)
            .insert(
              ScheduleItemsCompanion.insert(
                id: item.id,
                termId: item.termId,
                assignmentId: item.assignmentId,
                classId: item.classId,
                teacherId: Value(item.teacherId),
                subjectId: item.subjectId,
                weekMode: Value(item.weekMode.storageValue),
                combinedGroupId: Value(item.combinedGroupId),
                meetingId: Value(item.meetingId),
                stageId: Value(position?.stageId),
                weekday: Value(position?.weekday),
                periodTypeId: Value(position?.periodTypeId),
                lessonIndex: Value(position?.lessonIndex),
              ),
            );
      }
      await _database
          .into(_database.scheduleRunReports)
          .insert(
            ScheduleRunReportsCompanion.insert(
              id: run.id,
              termId: run.termId,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              solverVersion: run.config.solverVersion,
              seed: run.config.seed,
              strength: run.config.strength.name,
              inputFingerprint: run.inputFingerprint,
              reportJson: jsonEncode(run.toJson()),
            ),
          );
    });

    if (backup == null) return const ScheduleCommitResult();
    try {
      await backup.createSnapshot(label: 'after-scheduling');
      return const ScheduleCommitResult();
    } on Object catch (error) {
      return ScheduleCommitResult(backupWarning: '课表已保存，但自动备份失败：$error');
    }
  }
}
