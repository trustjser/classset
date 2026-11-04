import 'dart:convert';
import 'dart:isolate';

import 'package:class_set/data/database/app_database.dart'
    hide CalendarException;
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/temporary_preview_worker.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:drift/drift.dart';

typedef _ProjectionInput = ({
  SchedulingSnapshot snapshot,
  List<CalendarException> exceptions,
  List<TemporaryAdjustmentRecord> records,
});
typedef _ProjectionResult = ({
  List<ActualLesson> lessons,
  List<TemporaryAdjustmentRecord> records,
});

Future<_ProjectionResult> _projectAsync(_ProjectionInput input) =>
    Isolate.run(() => _project(input));

_ProjectionResult _project(_ProjectionInput input) {
  var lessons = const ActualTimetable().expand(
    input.snapshot,
    input.exceptions,
  );
  final records = <TemporaryAdjustmentRecord>[];
  for (final record in input.records) {
    final changes = record.changes;
    var invalid =
        changes.map((change) => change.before.key).toSet().length !=
        changes.length;
    if (record.cancelledAt == null) {
      for (final change in changes) {
        final current = lessons
            .where((lesson) => lesson.key == change.before.key)
            .firstOrNull;
        if (current == null ||
            jsonEncode(current.toJson()) !=
                jsonEncode(change.before.toJson())) {
          invalid = true;
          break;
        }
      }
      if (!invalid && changes.isNotEmpty) {
        final engine = const ActualTimetable();
        ActualChangePreview? preview;
        if (record.kind == 'move' || record.kind == 'substitute') {
          var projected = lessons;
          final verified = <ActualLessonChange>[];
          final errors = <String>[];
          for (var index = 0; index < changes.length;) {
            final change = changes[index];
            final position = change.after.item.position;
            if (position == null) {
              errors.add('目标位置不存在');
              break;
            }
            final one = record.kind == 'move'
                ? engine.previewMove(
                    snapshot: input.snapshot,
                    lessons: projected,
                    exceptions: input.exceptions,
                    sourceKey: change.before.key,
                    targetDate: change.after.date,
                    targetPosition: position,
                  )
                : engine.previewSubstitute(
                    snapshot: input.snapshot,
                    lessons: projected,
                    exceptions: input.exceptions,
                    sourceKey: change.before.key,
                    teacherId: change.after.item.teacherId,
                    subjectId: change.after.item.subjectId,
                  );
            if (one.errors.isNotEmpty) {
              errors.addAll(one.errors);
              break;
            }
            verified.addAll(one.changes);
            projected = engine.apply(projected, one.changes);
            if (one.changes.isEmpty) {
              errors.add('调整课次为空');
              break;
            }
            index += one.changes.length;
          }
          preview = ActualChangePreview(changes: verified, errors: errors);
        } else if (record.kind == 'swap' && changes.length.isEven) {
          var projected = lessons;
          final verified = <ActualLessonChange>[];
          final errors = <String>[];
          for (var i = 0; i < changes.length;) {
            final one = engine.previewSwap(
              snapshot: input.snapshot,
              lessons: projected,
              exceptions: input.exceptions,
              firstKey: changes[i].before.key,
              secondKey: changes[i + 1].before.key,
            );
            if (one.errors.isNotEmpty) {
              errors.addAll(one.errors);
              break;
            }
            verified.addAll(one.changes);
            projected = engine.apply(projected, one.changes);
            if (one.changes.isEmpty) {
              errors.add('调整课次为空');
              break;
            }
            i += one.changes.length;
          }
          preview = ActualChangePreview(changes: verified, errors: errors);
        }
        String canonical(List<ActualLessonChange> values) {
          final sorted = [...values]
            ..sort((a, b) => a.before.key.compareTo(b.before.key));
          return jsonEncode(sorted.map((value) => value.toJson()).toList());
        }

        if (preview == null ||
            preview.errors.isNotEmpty ||
            canonical(preview.changes) != canonical(changes)) {
          invalid = true;
        }
      } else if (changes.isEmpty) {
        invalid = true;
      }
      if (!invalid) lessons = const ActualTimetable().apply(lessons, changes);
    }
    records.add(record.withAttention(invalid));
  }
  return (lessons: lessons, records: records);
}

Future<void> _validateCancellationAsync(
  TemporaryTimetableState state,
  TemporaryAdjustmentRecord record,
  int index,
) => Isolate.run(() => _validateCancellation(state, record, index));

void _validateCancellation(
  TemporaryTimetableState state,
  TemporaryAdjustmentRecord record,
  int index,
) {
  final keys = record.changes.map((change) => change.before.key).toSet();
  if (state.records
      .skip(index + 1)
      .any(
        (later) =>
            later.cancelledAt == null &&
            later.changes.any((change) => keys.contains(change.before.key)),
      )) {
    throw StateError('请先取消引用这些课次的后续调整');
  }
  for (final change
      in record.needsAttention
          ? const <ActualLessonChange>[]
          : record.changes) {
    final target = change.before.item.position;
    if (target == null) throw StateError('原课次位置已失效');
    final preview = record.kind == 'substitute'
        ? const ActualTimetable().previewSubstitute(
            snapshot: state.snapshot,
            lessons: state.lessons,
            exceptions: state.exceptions,
            sourceKey: change.after.key,
            teacherId: change.before.item.teacherId,
            subjectId: change.before.item.subjectId,
          )
        : const ActualTimetable().previewMove(
            snapshot: state.snapshot,
            lessons: state.lessons
                .where(
                  (lesson) =>
                      !keys.contains(lesson.key) ||
                      lesson.key == change.after.key ||
                      (change.after.item.meetingId != null &&
                          lesson.item.meetingId ==
                              change.after.item.meetingId &&
                          lesson.date == change.after.date),
                )
                .toList(),
            exceptions: state.exceptions,
            sourceKey: change.after.key,
            targetDate: change.before.date,
            targetPosition: target,
          );
    if (preview.errors.isNotEmpty) {
      throw StateError('恢复原课次存在冲突：${preview.errors.join('；')}');
    }
  }
  if (!record.needsAttention) {
    const engine = ActualTimetable();
    final reverse = [
      for (final change in record.changes)
        ActualLessonChange(before: change.after, after: change.before),
    ];
    final hardCheck = engine.checkChanges(
      state.snapshot,
      state.lessons,
      reverse,
    );
    if (hardCheck.errors.isNotEmpty) {
      throw StateError('恢复原课次存在冲突：${hardCheck.errors.join('；')}');
    }
    final restored = engine.apply(state.lessons, reverse);
    for (final change in reverse) {
      final position = change.after.item.position;
      if (position == null) throw StateError('原课次位置已失效');
      final check = engine.previewMove(
        snapshot: state.snapshot,
        lessons: restored,
        exceptions: state.exceptions,
        sourceKey: change.after.key,
        targetDate: change.after.date,
        targetPosition: position,
      );
      if (check.errors.isNotEmpty) {
        throw StateError('恢复原课次存在冲突：${check.errors.join('；')}');
      }
    }
  }
}

/// 临时课次与记录的持久化边界，不修改常规课表。
class DriftTemporaryAdjustmentRepository {
  const DriftTemporaryAdjustmentRepository(this._database, this._school);

  final AppDatabase _database;
  final SchoolRepository _school;
  static int _idCounter = 0;

  Future<TemporaryTimetableState> load(String termId) =>
      _database.transaction(() async {
        final current = await _school.loadSchedulingSnapshot(termId);
        final exceptions = await _school.watchCalendarExceptions(termId).first;
        final pending = await _school.loadPendingSchedulingBaseline(termId);
        final snapshot = pending ?? current;
        final rows =
            await (_database.select(_database.temporaryCourseAdjustments)
                  ..where((row) => row.termId.equals(termId))
                  ..orderBy([
                    (row) => OrderingTerm.asc(row.createdAt),
                    (row) => OrderingTerm.asc(row.id),
                  ]))
                .get();
        final revision = jsonEncode([
          current.inputFingerprint,
          pending?.inputFingerprint,
          for (final e in exceptions)
            [
              e.id,
              e.date.toIso8601String(),
              e.kind.storageValue,
              e.makeupWeekday,
              e.makeupForDate?.toIso8601String(),
              e.note,
            ],
          for (final row in rows)
            [
              row.id,
              row.kind,
              row.changesJson,
              row.reason,
              row.createdAt.toIso8601String(),
              row.cancelledAt?.toIso8601String(),
            ],
        ]);
        final parsedRecords = [
          for (final row in rows)
            TemporaryAdjustmentRecord(
              id: row.id,
              kind: row.kind,
              reason: row.reason,
              createdAt: row.createdAt,
              cancelledAt: row.cancelledAt,
              changes: (jsonDecode(row.changesJson) as List)
                  .map(
                    (value) => ActualLessonChange.fromJson(
                      (value as Map).cast<String, Object?>(),
                    ),
                  )
                  .toList(),
            ),
        ];
        final input = (
          snapshot: snapshot,
          exceptions: exceptions,
          records: parsedRecords,
        );
        final projection =
            snapshot.existingItems.length * snapshot.term.teachingWeekCount >
                    2000 ||
                rows.length > 10
            ? await _projectAsync(input)
            : _project(input);
        return TemporaryTimetableState(
          snapshot: snapshot,
          exceptions: exceptions,
          records: projection.records,
          lessons: projection.lessons,
          revision: revision,
          reconciliationPending: pending != null,
        );
      });

  Future<void> commitMove({
    required String termId,
    required TemporaryMoveRequest request,
    required String expectedRevision,
  }) => _database.transaction(() async {
    final state = await load(termId);
    if (state.revision != expectedRevision) {
      throw StateError('课表或调整记录已改变，请刷新预览');
    }
    final preview = state.lessons.length > 2000 || request.rangeStart != null
        ? await computeTemporaryPreview(state: state, move: request)
        : state.previewMove(request);
    if (preview.errors.isNotEmpty || preview.changes.isEmpty) {
      throw StateError(preview.errors.join('；'));
    }
    final now = DateTime.now();
    await _database
        .into(_database.temporaryCourseAdjustments)
        .insert(
          TemporaryCourseAdjustmentsCompanion.insert(
            id: 'temporary_${now.microsecondsSinceEpoch}_${_idCounter++}',
            termId: termId,
            kind: 'move',
            changesJson: jsonEncode(
              preview.changes.map((e) => e.toJson()).toList(),
            ),
            reason: Value(request.reason.trim()),
            createdAt: now,
          ),
        );
  });

  Future<void> commitSubstitute({
    required String termId,
    required TemporarySubstituteRequest request,
    required String expectedRevision,
  }) => _database.transaction(() async {
    final state = await load(termId);
    if (state.revision != expectedRevision) {
      throw StateError('课表或调整记录已改变，请刷新预览');
    }
    final preview = state.lessons.length > 2000 || request.rangeStart != null
        ? await computeTemporaryPreview(state: state, substitute: request)
        : state.previewSubstitute(request);
    if (preview.errors.isNotEmpty || preview.changes.isEmpty) {
      throw StateError(preview.errors.join('；'));
    }
    final now = DateTime.now();
    await _database
        .into(_database.temporaryCourseAdjustments)
        .insert(
          TemporaryCourseAdjustmentsCompanion.insert(
            id: 'temporary_${now.microsecondsSinceEpoch}_${_idCounter++}',
            termId: termId,
            kind: 'substitute',
            changesJson: jsonEncode(
              preview.changes.map((e) => e.toJson()).toList(),
            ),
            reason: Value(request.reason.trim()),
            createdAt: now,
          ),
        );
  });

  Future<void> commitSwap({
    required String termId,
    required TemporarySwapRequest request,
    required String expectedRevision,
  }) => _database.transaction(() async {
    final state = await load(termId);
    if (state.revision != expectedRevision) {
      throw StateError('课表或调整记录已改变，请刷新预览');
    }
    final preview = state.lessons.length > 2000 || request.rangeStart != null
        ? await computeTemporaryPreview(state: state, swap: request)
        : state.previewSwap(request);
    if (preview.errors.isNotEmpty || preview.changes.isEmpty) {
      throw StateError(preview.errors.join('；'));
    }
    final now = DateTime.now();
    await _database
        .into(_database.temporaryCourseAdjustments)
        .insert(
          TemporaryCourseAdjustmentsCompanion.insert(
            id: 'temporary_${now.microsecondsSinceEpoch}_${_idCounter++}',
            termId: termId,
            kind: 'swap',
            changesJson: jsonEncode(
              preview.changes.map((e) => e.toJson()).toList(),
            ),
            reason: Value(request.reason.trim()),
            createdAt: now,
          ),
        );
  });

  Future<void> cancel({
    required String termId,
    required String adjustmentId,
    required String expectedRevision,
  }) => _database.transaction(() async {
    final state = await load(termId);
    if (state.revision != expectedRevision) throw StateError('课表或调整记录已改变，请刷新');
    if (state.reconciliationPending) throw StateError('请先完成课表协调');
    final index = state.records.indexWhere((r) => r.id == adjustmentId);
    if (index < 0 || state.records[index].cancelledAt != null) {
      throw StateError('调整记录不存在或已取消');
    }
    final record = state.records[index];
    if (state.lessons.length > 2000 || record.changes.length > 10) {
      await _validateCancellationAsync(state, record, index);
    } else {
      _validateCancellation(state, record, index);
    }
    await (_database.update(_database.temporaryCourseAdjustments)..where(
          (row) => row.id.equals(adjustmentId) & row.termId.equals(termId),
        ))
        .write(
          TemporaryCourseAdjustmentsCompanion(
            cancelledAt: Value(DateTime.now()),
          ),
        );
  });
}
