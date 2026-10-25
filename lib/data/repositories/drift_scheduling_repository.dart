import 'dart:convert';
import 'dart:io';

import 'package:class_set/data/backup/local_backup_service.dart';
import 'package:class_set/data/database/app_database.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/combined_lesson_group.dart' as domain;
import 'package:class_set/domain/models/school_structure.dart' as domain;
import 'package:class_set/domain/models/schedule_condition.dart' as domain;
import 'package:class_set/domain/models/schedule_item.dart' as domain;
import 'package:class_set/domain/models/schedule_lock.dart' as domain;
import 'package:class_set/domain/models/schedule_position.dart' as domain;
import 'package:class_set/domain/models/schedule_preferences.dart' as domain;
import 'package:class_set/domain/models/schedule_run.dart' as domain;
import 'package:class_set/domain/models/subject.dart' as domain;
import 'package:class_set/domain/models/teacher_assignment.dart' as domain;
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart' as domain;
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
  ];

  Future<domain.SchedulingSnapshot> loadSchedulingSnapshot(String termId) =>
      _database.transaction(() async {
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

        final routines = (await _source.watchRoutinesForTerm(termId).first)
            .values
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
        final lessonConstraints =
            (await _source.watchAllLessonConstraints().first)
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

        return domain.SchedulingSnapshot(
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
      });

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
  });

  Future<void> setScheduleLock(
    domain.ScheduleLock lock, {
    required bool enabled,
  }) => _database.transaction(() async {
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
  });

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
          jsonEncode(replacement.position?.toJson()) !=
              jsonEncode(oldItem.position?.toJson())) {
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
