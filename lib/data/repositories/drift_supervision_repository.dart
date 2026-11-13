import 'dart:convert';

import 'package:class_set/data/database/app_database.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/supervision_allocator.dart';
import 'package:class_set/domain/scheduling/supervision_matching.dart';
import 'package:class_set/domain/scheduling/supervision_validation.dart';
import 'package:drift/drift.dart';

class DriftSupervisionRepository {
  const DriftSupervisionRepository(this._database, {this.clock = DateTime.now});

  final AppDatabase _database;
  final DateTime Function() clock;

  Stream<SupervisionDraft?> watchDraft(String termId) =>
      _draftQuery(termId).watchSingleOrNull().map(_decodeDraft);

  Stream<List<SupervisionVersion>> watchVersions(String termId) =>
      _versionsQuery(termId).watch().map(_decodeVersions);

  Future<List<SupervisionVersion>> loadVersions(String termId) async =>
      _decodeVersions(await _versionsQuery(termId).get());

  Future<SupervisionDraft> saveDraft(
    SupervisionDraft draft, {
    required int expectedRevision,
  }) => _database.transaction(() async {
    final existing = _decodeDraft(
      await _draftQuery(draft.termId).getSingleOrNull(),
    );
    if ((existing?.revision ?? 0) != expectedRevision) {
      throw StateError('带班草稿已更新，请刷新后重试');
    }
    // Keep revisions distinct even after publishing removes the previous draft.
    final revision = clock().microsecondsSinceEpoch;
    final next = draft.copyWith(
      revision: revision > expectedRevision ? revision : expectedRevision + 1,
    );
    await _database
        .into(_database.supervisionDrafts)
        .insertOnConflictUpdate(
          SupervisionDraftsCompanion.insert(
            termId: draft.termId,
            payload: jsonEncode(next.toJson()),
          ),
        );
    return next;
  });

  Future<SupervisionPreview> previewPublish(
    String termId,
    DateTime effectiveDate, {
    required Future<SchedulingSnapshot> Function(String) loadSnapshot,
    bool repair = false,
    List<String> scheduleChanges = const [],
    Future<TemporaryTimetableState> Function(String)? baselineTemporary,
    required Future<TemporaryTimetableState> Function(
      String,
      List<SupervisionVersion>,
    )
    loadTemporary,
    String? extraError,
  }) => _database.transaction(() async {
    final snapshot = await loadSnapshot(termId);
    final draft = _decodeDraft(await _draftQuery(termId).getSingleOrNull());
    if (draft == null) throw StateError('请先保存带班草稿');
    final versions = await loadVersions(termId);
    final date = _day(effectiveDate);
    final today = _day(clock());
    const validation = SupervisionValidation();
    const allocator = SupervisionAllocator();
    final errors = validation.postErrors(snapshot, draft).toSet();
    if (extraError != null) errors.add(extraError);
    final replaced = versions
        .where((version) => version.effectiveDate.isAfter(today))
        .firstOrNull;
    final before = SupervisionVersion.forDate(versions, date);
    final term = snapshot.term;
    if (repair
        ? date != today
        : !date.isAfter(today) ||
              date.weekday != DateTime.monday ||
              term.teachingWeekOf(date) == null) {
      errors.add(repair ? '协调后的带班方案从今天生效' : '请选择学期内尚未开始的教学周周一');
    }
    final matching = SupervisionMatching(snapshot);
    final missing = <String>[];
    for (final post in draft.posts) {
      final teacher = draft.assignments[post.id];
      if (teacher == null) {
        missing.add(post.id);
        continue;
      }
      for (final error in allocator.teacherBlockers(
        snapshot,
        draft,
        post,
        teacher,
        matching: matching,
      )) {
        errors.add('${post.name}：$error');
      }
    }
    final proposed = SupervisionVersion(
      termId: termId,
      effectiveDate: date,
      draft: draft,
      occurrences: validation.occurrences(snapshot, draft),
    );
    final temporary = await loadTemporary(termId, [
      ...versions.where(
        (version) => repair
            ? version.effectiveDate.isBefore(today)
            : !version.effectiveDate.isAfter(today),
      ),
      proposed,
    ]);
    final preexistingIssues = baselineTemporary == null
        ? const <String>{}
        : {
            for (final record in (await baselineTemporary(termId)).records)
              if (record.needsAttention) record.id,
          };
    for (final record in temporary.records) {
      if (record.cancelledAt != null || !record.needsAttention) continue;
      final change = record.supervisionChange;
      if (change != null && !change.before.date.isBefore(today)) {
        errors.add(
          '替班 ${_dateKey(change.before.date)} · ${change.before.post.name} 需要先撤销或修正',
        );
      } else if (!preexistingIssues.contains(record.id) &&
          record.changes.any(
            (change) =>
                !change.before.date.isBefore(date) ||
                !change.after.date.isBefore(date),
          )) {
        errors.add('带班方案影响已有调代课记录，请先在「调代课」撤销或修正');
      }
    }
    final lessonsByDate = <DateTime, List<ActualLesson>>{};
    final supervisionByDate = <DateTime, List<ActualSupervision>>{};
    for (final lesson in temporary.lessons) {
      (lessonsByDate[lesson.date] ??= []).add(lesson);
    }
    for (final supervision in temporary.supervisions) {
      (supervisionByDate[supervision.date] ??= []).add(supervision);
    }
    for (final supervision in temporary.supervisions.where(
      (entry) => !entry.date.isBefore(date),
    )) {
      final conflict = actualSupervisionConflict(
        snapshot,
        lessonsByDate[supervision.date] ?? const [],
        supervisionByDate[supervision.date] ?? const [],
        supervision,
        supervision.teacherId,
      );
      if (conflict != null) {
        errors.add(
          '${_dateKey(supervision.date)} · ${supervision.post.name}：$conflict',
        );
      }
    }
    return SupervisionPreview(
      effectiveDate: date,
      before: before,
      draft: draft,
      errors: errors.toList(),
      missingPostIds: missing,
      scheduleChanges: scheduleChanges,
      replacedFutureDate: replaced?.effectiveDate,
      fingerprint: jsonEncode([
        snapshot.inputFingerprint,
        temporary.revision,
        for (final version in versions) version.toJson(),
        proposed.toJson(),
        scheduleChanges,
      ]),
    );
  });

  Future<void> publish(
    String termId,
    SupervisionPreview expected, {
    required Future<SchedulingSnapshot> Function(String) loadSnapshot,
    bool repair = false,
    List<String> scheduleChanges = const [],
    Future<TemporaryTimetableState> Function(String)? baselineTemporary,
    required Future<TemporaryTimetableState> Function(
      String,
      List<SupervisionVersion>,
    )
    loadTemporary,
  }) => _database.transaction(() async {
    final preview = await previewPublish(
      termId,
      expected.effectiveDate,
      loadSnapshot: loadSnapshot,
      loadTemporary: loadTemporary,
      repair: repair,
      scheduleChanges: scheduleChanges,
      baselineTemporary: baselineTemporary,
    );
    if (preview.fingerprint != expected.fingerprint) {
      throw StateError('带班草稿、课表或日历已变化，请重新预览');
    }
    if (!preview.canPublish) {
      throw StateError('请排齐带班岗位并解决冲突后再确认');
    }
    final snapshot = await loadSnapshot(termId);
    final version = SupervisionVersion(
      termId: termId,
      effectiveDate: preview.effectiveDate,
      draft: preview.draft,
      occurrences: const SupervisionValidation().occurrences(
        snapshot,
        preview.draft,
      ),
    );
    final today = _dateKey(clock());
    await (_database.delete(_database.supervisionPlanVersions)..where(
          (row) =>
              row.termId.equals(termId) &
              (repair
                  ? row.effectiveDate.isBiggerOrEqualValue(today)
                  : row.effectiveDate.isBiggerThanValue(today)),
        ))
        .go();
    await _database
        .into(_database.supervisionPlanVersions)
        .insert(
          SupervisionPlanVersionsCompanion.insert(
            termId: termId,
            effectiveDate: _dateKey(version.effectiveDate),
            payload: jsonEncode(version.toJson()),
          ),
        );
    await (_database.delete(
      _database.supervisionDrafts,
    )..where((row) => row.termId.equals(termId))).go();
  });

  SimpleSelectStatement<SupervisionDrafts, SupervisionDraftRow> _draftQuery(
    String termId,
  ) =>
      _database.select(_database.supervisionDrafts)
        ..where((row) => row.termId.equals(termId));

  SimpleSelectStatement<SupervisionPlanVersions, SupervisionPlanVersionRow>
  _versionsQuery(String termId) =>
      _database.select(_database.supervisionPlanVersions)
        ..where((row) => row.termId.equals(termId))
        ..orderBy([(row) => OrderingTerm.asc(row.effectiveDate)]);

  SupervisionDraft? _decodeDraft(SupervisionDraftRow? row) =>
      row == null ? null : SupervisionDraft.fromJson(_decode(row.payload));

  List<SupervisionVersion> _decodeVersions(
    List<SupervisionPlanVersionRow> rows,
  ) => [
    for (final row in rows) SupervisionVersion.fromJson(_decode(row.payload)),
  ];

  Map<String, Object?> _decode(String payload) =>
      (jsonDecode(payload) as Map).cast<String, Object?>();

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _dateKey(DateTime date) =>
      date.toIso8601String().substring(0, 10);
}
