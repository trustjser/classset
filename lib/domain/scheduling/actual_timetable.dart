import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/scheduling/constraint_evaluator.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

/// 一条周期课表在某个自然日实际出现的课次。
class ActualLesson {
  const ActualLesson({required this.date, required this.item, this.originDate});

  final DateTime date;
  final ScheduleItem item;
  final DateTime? originDate;

  String get key =>
      '${item.id}:${(originDate ?? date).toIso8601String().substring(0, 10)}';

  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'originDate': (originDate ?? date).toIso8601String(),
    'item': item.toJson(),
  };

  factory ActualLesson.fromJson(Map<String, Object?> json) => ActualLesson(
    date: DateTime.parse(json['date'] as String),
    originDate: DateTime.parse(json['originDate'] as String),
    item: ScheduleItem.fromJson((json['item'] as Map).cast<String, Object?>()),
  );
}

class ActualLessonChange {
  const ActualLessonChange({required this.before, required this.after});
  final ActualLesson before;
  final ActualLesson after;

  Map<String, Object?> toJson() => {
    'before': before.toJson(),
    'after': after.toJson(),
  };

  factory ActualLessonChange.fromJson(Map<String, Object?> json) =>
      ActualLessonChange(
        before: ActualLesson.fromJson(
          (json['before'] as Map).cast<String, Object?>(),
        ),
        after: ActualLesson.fromJson(
          (json['after'] as Map).cast<String, Object?>(),
        ),
      );
}

class TemporaryMoveRequest {
  const TemporaryMoveRequest({
    required this.sourceKey,
    required this.targetDate,
    required this.targetPosition,
    this.reason = '',
    this.rangeStart,
    this.rangeEnd,
    this.excludedDates = const {},
  });
  final String sourceKey;
  final DateTime targetDate;
  final SchedulePosition targetPosition;
  final String reason;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final Set<DateTime> excludedDates;
}

class TemporarySubstituteRequest {
  const TemporarySubstituteRequest({
    required this.sourceKey,
    required this.teacherId,
    this.subjectId,
    this.reason = '',
    this.rangeStart,
    this.rangeEnd,
    this.excludedDates = const {},
  });
  final String sourceKey;
  final String teacherId;
  final String? subjectId;
  final String reason;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final Set<DateTime> excludedDates;
}

class TemporarySwapRequest {
  const TemporarySwapRequest({
    required this.firstKey,
    required this.secondKey,
    this.reason = '',
    this.rangeStart,
    this.rangeEnd,
    this.excludedDates = const {},
  });
  final String firstKey;
  final String secondKey;
  final String reason;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final Set<DateTime> excludedDates;
}

const supervisionSubstitutionKind = 'supervision-substitute';

class ActualSupervision {
  const ActualSupervision({
    required this.date,
    required this.occurrences,
    required this.teacherId,
    required this.teacherName,
    this.templateWeek,
    this.eligibleTeacherIds = const {},
  });

  final DateTime date;
  final List<SupervisionOccurrence> occurrences;
  final String teacherId;
  final String teacherName;
  final int? templateWeek;
  final Set<String> eligibleTeacherIds;

  String get postId => occurrences.first.post.id;
  SupervisionPost get post => occurrences.first.post;
  List<String> get classIds => post.classIds;
  List<String> get classNames => occurrences.first.classNames;
  String get key => '${date.toIso8601String().substring(0, 10)}:$postId';

  ActualSupervision withTeacher(String id, String name) => ActualSupervision(
    date: date,
    occurrences: occurrences,
    teacherId: id,
    teacherName: name,
    templateWeek: templateWeek,
    eligibleTeacherIds: eligibleTeacherIds,
  );

  Map<String, Object?> toJson() => {
    'date': date.toIso8601String().substring(0, 10),
    'occurrences': [for (final row in occurrences) row.toJson()],
    'teacherId': teacherId,
    'teacherName': teacherName,
  };

  factory ActualSupervision.fromJson(Map<String, Object?> json) =>
      ActualSupervision(
        date: DateTime.parse(json['date'] as String),
        occurrences: [
          for (final row in json['occurrences'] as List)
            SupervisionOccurrence.fromJson(
              (row as Map).cast<String, Object?>(),
            ),
        ],
        teacherId: json['teacherId'] as String,
        teacherName: json['teacherName'] as String,
      );

  bool sameAssignment(ActualSupervision other) =>
      key == other.key &&
      teacherId == other.teacherId &&
      classIds.toSet().length == other.classIds.toSet().length &&
      classIds.toSet().containsAll(other.classIds) &&
      occurrences.length == other.occurrences.length &&
      occurrences.every(
        (row) => other.occurrences.any(
          (next) =>
              next.position.sameCell(row.position) &&
              next.startMinute == row.startMinute &&
              next.endMinute == row.endMinute,
        ),
      );
}

class TemporarySupervisionSubstituteRequest {
  const TemporarySupervisionSubstituteRequest({
    required this.date,
    required this.postId,
    required this.teacherId,
    this.reason = '',
  });

  final DateTime date;
  final String postId;
  final String teacherId;
  final String reason;

  String get key => '${date.toIso8601String().substring(0, 10)}:$postId';
}

class ActualSupervisionChange {
  const ActualSupervisionChange({required this.before, required this.after});

  final ActualSupervision before;
  final ActualSupervision after;

  Map<String, Object?> toJson() => {
    'before': before.toJson(),
    'after': after.toJson(),
  };

  factory ActualSupervisionChange.fromJson(Map<String, Object?> json) =>
      ActualSupervisionChange(
        before: ActualSupervision.fromJson(
          (json['before'] as Map).cast<String, Object?>(),
        ),
        after: ActualSupervision.fromJson(
          (json['after'] as Map).cast<String, Object?>(),
        ),
      );
}

typedef SupervisionSubstitutePreview = ({
  ActualSupervisionChange? change,
  List<String> errors,
});

bool _positionsConflictOnDate(SchedulePosition a, SchedulePosition b) {
  if (a.hasClockTime && b.hasClockTime) {
    return a.startMinute! < b.endMinute! && b.startMinute! < a.endMinute!;
  }
  return a.stageId != b.stageId ||
      (a.periodTypeId == b.periodTypeId && a.lessonIndex == b.lessonIndex);
}

/// Detect shared resources on an actual day, regardless of source weekdays.
String? actualSupervisionConflict(
  SchedulingSnapshot snapshot,
  Iterable<ActualLesson> lessons,
  Iterable<ActualSupervision> supervisions,
  ActualSupervision supervision,
  String teacherId,
) {
  for (final lesson in lessons.where((row) => row.date == supervision.date)) {
    final position = lesson.item.position;
    final teacherConflict = lesson.item.teacherId == teacherId;
    final classConflict = supervision.classIds.contains(lesson.item.classId);
    if (position == null || (!teacherConflict && !classConflict)) continue;
    if (supervision.occurrences.any(
      (row) => _positionsConflictOnDate(row.position, position),
    )) {
      final subject = snapshot.subjects
          .where((subject) => subject.id == lesson.item.subjectId)
          .firstOrNull;
      return '与${teacherConflict ? '教师' : '班级'}的${subject?.name ?? '正课'}时间冲突';
    }
  }
  for (final other in supervisions.where(
    (row) => row.date == supervision.date && row.key != supervision.key,
  )) {
    if (other.teacherId != teacherId &&
        !other.classIds.any(supervision.classIds.contains)) {
      continue;
    }
    if (supervision.occurrences.any(
      (row) => other.occurrences.any(
        (next) => _positionsConflictOnDate(row.position, next.position),
      ),
    )) {
      return '与「${other.post.name}」带班时间冲突';
    }
  }
  return null;
}

class TemporaryAdjustmentRecord {
  const TemporaryAdjustmentRecord({
    required this.id,
    required this.kind,
    required this.changes,
    required this.reason,
    required this.createdAt,
    this.cancelledAt,
    this.needsAttention = false,
    this.supervisionChange,
  });
  final String id;
  final String kind;
  final List<ActualLessonChange> changes;
  final String reason;
  final DateTime createdAt;
  final DateTime? cancelledAt;
  final bool needsAttention;
  final ActualSupervisionChange? supervisionChange;

  TemporaryAdjustmentRecord withAttention(bool value) =>
      TemporaryAdjustmentRecord(
        id: id,
        kind: kind,
        changes: changes,
        reason: reason,
        createdAt: createdAt,
        cancelledAt: cancelledAt,
        needsAttention: value,
        supervisionChange: supervisionChange,
      );
}

class TemporaryTimetableState {
  const TemporaryTimetableState({
    required this.snapshot,
    required this.exceptions,
    required this.records,
    required this.lessons,
    required this.revision,
    required this.reconciliationPending,
    this.supervisions = const [],
    this.supervisionVersions = const [],
  });
  final SchedulingSnapshot snapshot;
  final List<CalendarException> exceptions;
  final List<TemporaryAdjustmentRecord> records;
  final List<ActualLesson> lessons;
  final String revision;
  final bool reconciliationPending;
  final List<ActualSupervision> supervisions;
  final List<SupervisionVersion> supervisionVersions;

  SupervisionSubstitutePreview previewSupervisionSubstitute(
    TemporarySupervisionSubstituteRequest request,
  ) {
    if (reconciliationPending) {
      return (change: null, errors: ['请先完成课表协调']);
    }
    if (records.any(
      (record) =>
          record.cancelledAt == null &&
          record.supervisionChange?.before.key == request.key,
    )) {
      return (change: null, errors: ['该岗位已有替班记录，请先撤销']);
    }
    return const ActualTimetable().previewSupervisionSubstitute(
      snapshot: snapshot,
      lessons: lessons,
      supervisions: supervisions,
      versions: supervisionVersions,
      request: request,
    );
  }

  ActualLesson? _originalOccurrence(ActualLesson anchor, DateTime date) {
    final offset = date.difference(anchor.date).inDays;
    final origin = (anchor.originDate ?? anchor.date).add(
      Duration(days: offset),
    );
    return lessons
        .where(
          (item) =>
              item.item.id == anchor.item.id &&
              (item.originDate ?? item.date) == origin &&
              item.date == date,
        )
        .firstOrNull;
  }

  ActualChangePreview previewMove(
    TemporaryMoveRequest request, {
    SchedulingProblem? problem,
  }) {
    if (reconciliationPending) {
      return const ActualChangePreview(changes: [], errors: ['请先完成课表协调']);
    }
    if (request.rangeStart != null || request.rangeEnd != null) {
      final start = request.rangeStart;
      final end = request.rangeEnd;
      final source = lessons
          .where((lesson) => lesson.key == request.sourceKey)
          .firstOrNull;
      if (start == null ||
          end == null ||
          end.isBefore(start) ||
          source == null) {
        return const ActualChangePreview(changes: [], errors: ['日期范围或原课次无效']);
      }
      final engine = const ActualTimetable();
      var projected = lessons;
      final changes = <ActualLessonChange>[];
      final errors = <String>[];
      final skipped = <DateTime>[];
      final usedKeys = <String>{};
      final first = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      for (
        var date = first;
        !date.isAfter(last);
        date = date.add(const Duration(days: 1))
      ) {
        if (date.weekday != source.date.weekday ||
            request.excludedDates.contains(date)) {
          continue;
        }
        final original = _originalOccurrence(source, date);
        final lesson = original == null
            ? null
            : projected.where((item) => item.key == original.key).firstOrNull;
        if (lesson == null) {
          skipped.add(date);
          continue;
        }
        final delta = date.difference(source.date).inDays;
        final targetDate = request.targetDate.add(Duration(days: delta));
        if (targetDate.isBefore(first) || targetDate.isAfter(last)) {
          errors.add('${date.toIso8601String().substring(0, 10)}：目标日期超出范围');
          continue;
        }
        final preview = engine.previewMove(
          snapshot: snapshot,
          lessons: projected,
          exceptions: exceptions,
          sourceKey: lesson.key,
          targetDate: targetDate,
          targetPosition: request.targetPosition,
          problem: problem,
        );
        if (preview.errors.isNotEmpty) {
          errors.addAll(
            preview.errors.map(
              (error) => '${date.toIso8601String().substring(0, 10)}：$error',
            ),
          );
        } else if (preview.changes.any(
          (change) => usedKeys.contains(change.before.key),
        )) {
          errors.add('${date.toIso8601String().substring(0, 10)}：课次已被本次其他调整使用');
        } else {
          usedKeys.addAll(preview.changes.map((change) => change.before.key));
          changes.addAll(preview.changes);
          projected = engine.apply(projected, preview.changes);
        }
      }
      return _guardInvalid(
        ActualChangePreview(
          changes: changes,
          errors: errors,
          skippedDates: skipped,
        ),
      );
    }
    return _guardInvalid(
      const ActualTimetable().previewMove(
        snapshot: snapshot,
        lessons: lessons,
        exceptions: exceptions,
        sourceKey: request.sourceKey,
        targetDate: request.targetDate,
        targetPosition: request.targetPosition,
        problem: problem,
      ),
    );
  }

  ActualChangePreview previewSubstitute(TemporarySubstituteRequest request) {
    if (reconciliationPending) {
      return const ActualChangePreview(changes: [], errors: ['请先完成课表协调']);
    }
    if (request.rangeStart != null || request.rangeEnd != null) {
      final start = request.rangeStart;
      final end = request.rangeEnd;
      final source = lessons
          .where((lesson) => lesson.key == request.sourceKey)
          .firstOrNull;
      if (start == null ||
          end == null ||
          end.isBefore(start) ||
          source == null) {
        return const ActualChangePreview(changes: [], errors: ['日期范围或原课次无效']);
      }
      final first = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      final engine = const ActualTimetable();
      var projected = lessons;
      final changes = <ActualLessonChange>[];
      final errors = <String>[];
      final skipped = <DateTime>[];
      final usedKeys = <String>{};
      for (
        var date = first;
        !date.isAfter(last);
        date = date.add(const Duration(days: 1))
      ) {
        if (date.weekday != source.date.weekday ||
            request.excludedDates.contains(date)) {
          continue;
        }
        final original = _originalOccurrence(source, date);
        final lesson = original == null
            ? null
            : projected.where((item) => item.key == original.key).firstOrNull;
        if (lesson == null) {
          skipped.add(date);
          continue;
        }
        final preview = engine.previewSubstitute(
          snapshot: snapshot,
          lessons: projected,
          exceptions: exceptions,
          sourceKey: lesson.key,
          teacherId: request.teacherId,
          subjectId: request.subjectId,
        );
        if (preview.errors.isNotEmpty) {
          errors.addAll(
            preview.errors.map(
              (error) => '${date.toIso8601String().substring(0, 10)}：$error',
            ),
          );
        } else if (preview.changes.any(
          (change) => usedKeys.contains(change.before.key),
        )) {
          errors.add('${date.toIso8601String().substring(0, 10)}：课次已被本次其他调整使用');
        } else {
          usedKeys.addAll(preview.changes.map((change) => change.before.key));
          changes.addAll(preview.changes);
          projected = engine.apply(projected, preview.changes);
        }
      }
      return _guardInvalid(
        ActualChangePreview(
          changes: changes,
          errors: errors,
          skippedDates: skipped,
        ),
      );
    }
    return _guardInvalid(
      const ActualTimetable().previewSubstitute(
        snapshot: snapshot,
        lessons: lessons,
        exceptions: exceptions,
        sourceKey: request.sourceKey,
        teacherId: request.teacherId,
        subjectId: request.subjectId,
      ),
    );
  }

  ActualChangePreview previewSwap(
    TemporarySwapRequest request, {
    SchedulingProblem? problem,
  }) {
    if (reconciliationPending) {
      return const ActualChangePreview(changes: [], errors: ['请先完成课表协调']);
    }
    if (request.rangeStart != null || request.rangeEnd != null) {
      final start = request.rangeStart;
      final end = request.rangeEnd;
      final firstLesson = lessons
          .where((lesson) => lesson.key == request.firstKey)
          .firstOrNull;
      final secondLesson = lessons
          .where((lesson) => lesson.key == request.secondKey)
          .firstOrNull;
      if (start == null ||
          end == null ||
          end.isBefore(start) ||
          firstLesson == null ||
          secondLesson == null) {
        return const ActualChangePreview(changes: [], errors: ['日期范围或原课次无效']);
      }
      final first = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      final engine = const ActualTimetable();
      var projected = lessons;
      final changes = <ActualLessonChange>[];
      final errors = <String>[];
      final skipped = <DateTime>[];
      final usedKeys = <String>{};
      for (
        var date = first;
        !date.isAfter(last);
        date = date.add(const Duration(days: 1))
      ) {
        if (date.weekday != firstLesson.date.weekday ||
            request.excludedDates.contains(date)) {
          continue;
        }
        final originalSource = _originalOccurrence(firstLesson, date);
        if (originalSource != null && usedKeys.contains(originalSource.key)) {
          errors.add('${date.toIso8601String().substring(0, 10)}：课次已被本次其他换课使用');
          continue;
        }
        final source = originalSource == null
            ? null
            : projected
                  .where((lesson) => lesson.key == originalSource.key)
                  .firstOrNull;
        if (source == null) {
          skipped.add(date);
          continue;
        }
        final targetDate = secondLesson.date.add(
          Duration(days: date.difference(firstLesson.date).inDays),
        );
        if (targetDate.isBefore(first) || targetDate.isAfter(last)) {
          errors.add('${date.toIso8601String().substring(0, 10)}：目标日期超出范围');
          continue;
        }
        final originalTarget = _originalOccurrence(secondLesson, targetDate);
        if (originalTarget != null && usedKeys.contains(originalTarget.key)) {
          errors.add(
            '${date.toIso8601String().substring(0, 10)}：目标课次已被本次其他换课使用',
          );
          continue;
        }
        final target = originalTarget == null
            ? null
            : projected
                  .where((lesson) => lesson.key == originalTarget.key)
                  .firstOrNull;
        if (target == null) {
          errors.add('${date.toIso8601String().substring(0, 10)}：目标课次不存在');
          continue;
        }
        final preview = engine.previewSwap(
          snapshot: snapshot,
          lessons: projected,
          exceptions: exceptions,
          firstKey: source.key,
          secondKey: target.key,
          problem: problem,
        );
        if (preview.errors.isNotEmpty) {
          errors.addAll(
            preview.errors.map(
              (error) => '${date.toIso8601String().substring(0, 10)}：$error',
            ),
          );
        } else if (preview.changes.any(
          (change) => usedKeys.contains(change.before.key),
        )) {
          errors.add('${date.toIso8601String().substring(0, 10)}：课组已被本次其他换课使用');
        } else {
          usedKeys.addAll(preview.changes.map((change) => change.before.key));
          changes.addAll(preview.changes);
          projected = engine.apply(projected, preview.changes);
        }
      }
      return _guardInvalid(
        ActualChangePreview(
          changes: changes,
          errors: errors,
          skippedDates: skipped,
        ),
      );
    }
    return _guardInvalid(
      const ActualTimetable().previewSwap(
        snapshot: snapshot,
        lessons: lessons,
        exceptions: exceptions,
        firstKey: request.firstKey,
        secondKey: request.secondKey,
        problem: problem,
      ),
    );
  }

  ActualChangePreview _guardInvalid(ActualChangePreview preview) {
    final supervisionErrors = const ActualTimetable().checkSupervisionChanges(
      supervisions,
      preview.changes,
    );
    if (supervisionErrors.isNotEmpty) {
      return ActualChangePreview(changes: const [], errors: supervisionErrors);
    }
    for (final invalid in records.where(
      (record) => record.needsAttention && record.cancelledAt == null,
    )) {
      for (final stale in invalid.changes) {
        for (final proposed in preview.changes) {
          if (stale.before.key == proposed.before.key) {
            return const ActualChangePreview(
              changes: [],
              errors: ['所选课次存在需要处理的调整记录'],
            );
          }
          for (final old in [stale.before, stale.after]) {
            for (final next in [proposed.before, proposed.after]) {
              final sameDate = old.date == next.date;
              final sharedResource =
                  old.item.classId == next.item.classId ||
                  old.item.teacherId == next.item.teacherId ||
                  (snapshot.roomAssignments.isNotEmpty) ||
                  (snapshot.parallelLimits.isNotEmpty &&
                      old.item.subjectId == next.item.subjectId);
              final sameWeekWithRules =
                  snapshot.term.teachingWeekOf(old.date) ==
                      snapshot.term.teachingWeekOf(next.date) &&
                  (snapshot.conditions.isNotEmpty ||
                      snapshot.lessonConstraints.isNotEmpty);
              if ((sameDate && sharedResource) || sameWeekWithRules) {
                return const ActualChangePreview(
                  changes: [],
                  errors: ['相关课次存在需要处理的调整记录'],
                );
              }
            }
          }
        }
      }
    }
    return preview;
  }
}

class ActualChangePreview {
  const ActualChangePreview({
    required this.changes,
    required this.errors,
    this.skippedDates = const [],
  });
  final List<ActualLessonChange> changes;
  final List<String> errors;
  final List<DateTime> skippedDates;
}

/// 根据教学周和日历例外将常规课表展开为实际课次。
class ActualTimetable {
  const ActualTimetable();

  SupervisionSubstitutePreview previewSupervisionSubstitute({
    required SchedulingSnapshot snapshot,
    required List<ActualLesson> lessons,
    required List<ActualSupervision> supervisions,
    required List<SupervisionVersion> versions,
    required TemporarySupervisionSubstituteRequest request,
  }) {
    final source = supervisions
        .where((row) => row.key == request.key)
        .firstOrNull;
    final teacher = snapshot.teachers
        .where((row) => row.id == request.teacherId)
        .firstOrNull;
    if (source == null || teacher == null) {
      return (change: null, errors: ['带班岗位或替班教师不存在']);
    }
    if (source.teacherId == teacher.id) {
      return (change: null, errors: ['请选择不同的教师']);
    }
    final version = SupervisionVersion.forDate(versions, source.date);
    if (version == null || !version.draft.teacherIds.contains(teacher.id)) {
      return (change: null, errors: ['教师不在该方案的候选范围']);
    }
    final unavailable =
        version.draft.rules[teacher.id]?.unavailable ?? const [];
    if (source.occurrences.any(
      (row) => unavailable.any((slot) => slot.sameCell(row.position)),
    )) {
      return (change: null, errors: ['教师在该节次禁排带班']);
    }
    final conflict = actualSupervisionConflict(
      snapshot,
      lessons,
      supervisions,
      source,
      teacher.id,
    );
    if (conflict != null) return (change: null, errors: [conflict]);
    return (
      change: ActualSupervisionChange(
        before: source,
        after: source.withTeacher(teacher.id, teacher.displayName),
      ),
      errors: const [],
    );
  }

  List<String> checkSupervisionChanges(
    List<ActualSupervision> supervisions,
    List<ActualLessonChange> changes,
  ) {
    final errors = <String>{};
    for (final change in changes) {
      final target = change.after;
      final position = target.item.position;
      if (position == null) continue;
      for (final supervision in supervisions) {
        if (supervision.date != target.date ||
            (supervision.teacherId != target.item.teacherId &&
                !supervision.classIds.contains(target.item.classId))) {
          continue;
        }
        if (supervision.occurrences.any(
          (row) => _positionsConflictOnDate(row.position, position),
        )) {
          errors.add(
            '${_dateConflictLabel(target.date)}与「${supervision.post.name}」带班冲突',
          );
        }
      }
    }
    return errors.toList();
  }

  List<ActualSupervision> expandSupervision(
    SchedulingSnapshot snapshot,
    List<CalendarException> exceptions,
    List<SupervisionVersion> versions,
  ) {
    if (versions.isEmpty) return const [];
    final result = <ActualSupervision>[];
    for (final day in _actualDays(snapshot, exceptions)) {
      final version = SupervisionVersion.forDate(versions, day.date);
      if (version == null) continue;
      final byPost = <String, List<SupervisionOccurrence>>{};
      for (final row in version.occurrences) {
        if (row.position.weekday == day.weekday) {
          byPost.putIfAbsent(row.post.id, () => []).add(row);
        }
      }
      for (final rows in byPost.values) {
        rows.sort(
          (a, b) => a.position.lessonIndex.compareTo(b.position.lessonIndex),
        );
        result.add(
          ActualSupervision(
            date: day.date,
            occurrences: rows,
            teacherId: rows.first.teacherId,
            teacherName: rows.first.teacherName,
            eligibleTeacherIds: version.draft.teacherIds,
            templateWeek: day.templateWeek,
          ),
        );
      }
    }
    return result;
  }

  ActualChangePreview previewSubstitute({
    required SchedulingSnapshot snapshot,
    required List<ActualLesson> lessons,
    required List<CalendarException> exceptions,
    required String sourceKey,
    required String teacherId,
    String? subjectId,
    SchedulingProblem? problem,
  }) {
    final source = lessons
        .where((lesson) => lesson.key == sourceKey)
        .firstOrNull;
    if (source == null ||
        source.item.position == null ||
        !snapshot.teachers.any((teacher) => teacher.id == teacherId) ||
        (subjectId != null &&
            !snapshot.subjects.any((subject) => subject.id == subjectId))) {
      return const ActualChangePreview(changes: [], errors: ['课次、代课教师或科目不存在']);
    }
    if (snapshot.locks.any(
      (lock) =>
          lock.scope == ScheduleLockScope.teacher &&
          (lock.targetId == source.item.teacherId ||
              lock.targetId == teacherId),
    )) {
      return const ActualChangePreview(changes: [], errors: ['教师课表已锁定']);
    }
    if (teacherId == source.item.teacherId &&
        (subjectId == null || subjectId == source.item.subjectId)) {
      return const ActualChangePreview(changes: [], errors: ['请选择不同的教师或科目']);
    }
    final group = source.item.meetingId == null
        ? [source]
        : lessons
              .where(
                (lesson) =>
                    lesson.item.meetingId == source.item.meetingId &&
                    lesson.date == source.date,
              )
              .toList();
    if (group.any(
      (member) => snapshot.locks.any(
        (lock) =>
            lock.scope == ScheduleLockScope.teacher &&
            lock.targetId == member.item.teacherId,
      ),
    )) {
      return const ActualChangePreview(changes: [], errors: ['教师课表已锁定']);
    }
    final replacements = <String, ActualLesson>{};
    for (final member in group) {
      final original = member.item;
      replacements[member.key] = ActualLesson(
        date: member.date,
        originDate: member.originDate,
        item: ScheduleItem(
          id: original.id,
          termId: original.termId,
          assignmentId: original.assignmentId,
          classId: original.classId,
          teacherId: teacherId,
          subjectId: subjectId ?? original.subjectId,
          weekMode: original.weekMode,
          combinedGroupId: original.combinedGroupId,
          meetingId: original.meetingId,
          position: original.position,
        ),
      );
    }
    final resolvedProblem = problem ?? const ProblemBuilder().build(snapshot);
    final proposal = _previewMove(
      snapshot: snapshot,
      lessons: [
        for (final lesson in lessons) replacements[lesson.key] ?? lesson,
      ],
      exceptions: exceptions,
      sourceKey: sourceKey,
      targetDate: source.date,
      targetPosition: source.item.position!,
      problem: resolvedProblem,
    );
    final result = ActualChangePreview(
      changes: proposal.errors.isEmpty
          ? [
              for (final member in group)
                ActualLessonChange(
                  before: member,
                  after: replacements[member.key]!,
                ),
            ]
          : const [],
      errors: proposal.errors,
    );
    return _checkHardChanges(
      snapshot,
      lessons,
      result,
      problem: resolvedProblem,
    );
  }

  ActualChangePreview previewSwap({
    required SchedulingSnapshot snapshot,
    required List<ActualLesson> lessons,
    required List<CalendarException> exceptions,
    required String firstKey,
    required String secondKey,
    SchedulingProblem? problem,
  }) {
    final first = lessons.where((lesson) => lesson.key == firstKey).firstOrNull;
    final second = lessons
        .where((lesson) => lesson.key == secondKey)
        .firstOrNull;
    if (first == null ||
        second == null ||
        firstKey == secondKey ||
        first.item.classId != second.item.classId ||
        first.item.position == null ||
        second.item.position == null) {
      return const ActualChangePreview(changes: [], errors: ['请选择同一班级的另一课次']);
    }
    List<ActualLesson> groupFor(ActualLesson item) =>
        item.item.meetingId == null
        ? [item]
        : lessons
              .where(
                (other) =>
                    other.item.meetingId == item.item.meetingId &&
                    other.date == item.date,
              )
              .toList();
    final firstGroup = groupFor(first);
    final secondGroup = groupFor(second);
    final firstClasses = firstGroup.map((item) => item.item.classId).toSet();
    final secondClasses = secondGroup.map((item) => item.item.classId).toSet();
    if (firstClasses.length != secondClasses.length ||
        !firstClasses.containsAll(secondClasses) ||
        firstClasses.length != firstGroup.length ||
        secondClasses.length != secondGroup.length) {
      return const ActualChangePreview(
        changes: [],
        errors: ['两个课组的参与班级不一致，无法整体换课'],
      );
    }
    final resolvedProblem = problem ?? const ProblemBuilder().build(snapshot);
    final firstKeys = firstGroup.map((item) => item.key).toSet();
    final secondKeys = secondGroup.map((item) => item.key).toSet();
    final firstMove = _previewMove(
      snapshot: snapshot,
      lessons: lessons
          .where((lesson) => !secondKeys.contains(lesson.key))
          .toList(),
      exceptions: exceptions,
      sourceKey: firstKey,
      targetDate: second.date,
      targetPosition: second.item.position!,
      problem: resolvedProblem,
    );
    final secondMove = _previewMove(
      snapshot: snapshot,
      lessons: lessons
          .where((lesson) => !firstKeys.contains(lesson.key))
          .toList(),
      exceptions: exceptions,
      sourceKey: secondKey,
      targetDate: first.date,
      targetPosition: first.item.position!,
      problem: resolvedProblem,
    );
    final errors = [...firstMove.errors, ...secondMove.errors];
    final changes = <ActualLessonChange>[];
    if (errors.isEmpty) {
      for (final change in firstMove.changes) {
        final counterpart = secondMove.changes
            .where(
              (other) =>
                  other.before.item.classId == change.before.item.classId,
            )
            .firstOrNull;
        if (counterpart == null) {
          errors.add('课组班级不一致');
          break;
        }
        changes.addAll([change, counterpart]);
      }
    }
    if (errors.isEmpty) {
      final proposed = apply(lessons, changes);
      for (final change in changes) {
        final after = change.after;
        final checked = _previewMove(
          snapshot: snapshot,
          lessons: proposed,
          exceptions: exceptions,
          sourceKey: after.key,
          targetDate: after.date,
          targetPosition: after.item.position!,
          problem: resolvedProblem,
        );
        errors.addAll(checked.errors);
      }
    }
    return _checkHardChanges(
      snapshot,
      lessons,
      ActualChangePreview(
        changes: errors.isEmpty ? changes : const [],
        errors: errors.toSet().toList(),
      ),
      problem: resolvedProblem,
    );
  }

  List<ActualLesson> apply(
    List<ActualLesson> lessons,
    List<ActualLessonChange> changes,
  ) {
    final replacements = {
      for (final change in changes) change.before.key: change.after,
    };
    return [for (final lesson in lessons) replacements[lesson.key] ?? lesson];
  }

  /// 复核一组原子变更对已有硬性下限的影响。
  ActualChangePreview checkChanges(
    SchedulingSnapshot snapshot,
    List<ActualLesson> lessons,
    List<ActualLessonChange> changes,
  ) => _checkHardChanges(
    snapshot,
    lessons,
    ActualChangePreview(changes: changes, errors: const []),
  );

  ActualChangePreview previewMove({
    required SchedulingSnapshot snapshot,
    required List<ActualLesson> lessons,
    required List<CalendarException> exceptions,
    required String sourceKey,
    required DateTime targetDate,
    required SchedulePosition targetPosition,
    SchedulingProblem? problem,
  }) {
    final resolvedProblem = problem ?? const ProblemBuilder().build(snapshot);
    final preview = _previewMove(
      snapshot: snapshot,
      lessons: lessons,
      exceptions: exceptions,
      sourceKey: sourceKey,
      targetDate: targetDate,
      targetPosition: targetPosition,
      problem: resolvedProblem,
    );
    return _checkHardChanges(
      snapshot,
      lessons,
      preview,
      problem: resolvedProblem,
    );
  }

  ActualChangePreview _checkHardChanges(
    SchedulingSnapshot snapshot,
    List<ActualLesson> lessons,
    ActualChangePreview preview, {
    SchedulingProblem? problem,
  }) {
    if (preview.errors.isNotEmpty || preview.changes.isEmpty) return preview;
    final resolvedProblem = problem ?? const ProblemBuilder().build(snapshot);
    final evaluator = const ConstraintEvaluator();
    final after = apply(lessons, preview.changes);
    final weeks = <int>{};
    for (final change in preview.changes) {
      final beforeWeek = snapshot.term.teachingWeekOf(change.before.date);
      final afterWeek = snapshot.term.teachingWeekOf(change.after.date);
      if (beforeWeek != null) weeks.add(beforeWeek);
      if (afterWeek != null) weeks.add(afterWeek);
    }
    ScheduleItem normalize(ActualLesson lesson, {bool unplaced = false}) =>
        ScheduleItem(
          id: lesson.key,
          termId: lesson.item.termId,
          assignmentId: lesson.item.assignmentId,
          classId: lesson.item.classId,
          teacherId: lesson.item.teacherId,
          subjectId: lesson.item.subjectId,
          weekMode: WeekMode.weekly,
          combinedGroupId: lesson.item.combinedGroupId,
          meetingId: lesson.item.meetingId,
          position: unplaced ? null : lesson.item.position,
        );
    String identity(ScheduleBlocker blocker) =>
        '${blocker.code}:${blocker.conditionId}:${blocker.position?.cellKey}:${blocker.message.replaceAll(RegExp(r'已排 \d+ 节'), '已排 * 节')}';
    int? count(ScheduleBlocker blocker) => int.tryParse(
      RegExp(r'已排 (\d+) 节').firstMatch(blocker.message)?.group(1) ?? '',
    );
    final errors = <String>[];
    for (final week in weeks) {
      final oldLessons = lessons
          .where((lesson) => snapshot.term.teachingWeekOf(lesson.date) == week)
          .toList();
      final newLessons = after
          .where((lesson) => snapshot.term.teachingWeekOf(lesson.date) == week)
          .toList();
      final oldKeys = oldLessons.map((lesson) => lesson.key).toSet();
      final newKeys = newLessons.map((lesson) => lesson.key).toSet();
      final oldItems = [
        for (final lesson in oldLessons) normalize(lesson),
        for (final lesson in newLessons)
          if (!oldKeys.contains(lesson.key)) normalize(lesson, unplaced: true),
      ];
      final newItems = [
        for (final lesson in newLessons) normalize(lesson),
        for (final lesson in oldLessons)
          if (!newKeys.contains(lesson.key)) normalize(lesson, unplaced: true),
      ];
      final oldBlockers = {
        for (final blocker in evaluator.unmetHardRequirements(
          resolvedProblem,
          oldItems,
        ))
          identity(blocker): blocker,
      };
      for (final blocker in evaluator.unmetHardRequirements(
        resolvedProblem,
        newItems,
      )) {
        final previous = oldBlockers[identity(blocker)];
        if (previous == null ||
            (count(previous) != null &&
                count(blocker) != null &&
                count(blocker)! < count(previous)!)) {
          errors.add('第 $week 周：${blocker.message}');
        }
      }
    }
    return errors.isEmpty
        ? preview
        : ActualChangePreview(changes: const [], errors: errors);
  }

  String _lessonConflictLabel(
    SchedulingSnapshot snapshot,
    ActualLesson lesson,
  ) {
    final subject = snapshot.subjects
        .where((subject) => subject.id == lesson.item.subjectId)
        .firstOrNull;
    final teacher = snapshot.teachers
        .where((teacher) => teacher.id == lesson.item.teacherId)
        .firstOrNull;
    final subjectName = subject?.name ?? lesson.item.subjectId;
    final teacherName = teacher?.displayName ?? lesson.item.teacherId;
    return '$subjectName（$teacherName）';
  }

  String _classConflictLabel(SchedulingSnapshot snapshot, String classId) {
    final schoolClass = snapshot.classes
        .where((entry) => entry.id == classId)
        .firstOrNull;
    if (schoolClass == null) return classId;
    final grade = snapshot.grades
        .where((entry) => entry.id == schoolClass.gradeId)
        .firstOrNull;
    final label = [
      grade?.name,
      schoolClass.name,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' ');
    return label.isEmpty ? classId : label;
  }

  String _positionConflictLabel(
    SchedulingSnapshot snapshot,
    SchedulePosition position,
  ) {
    final period = snapshot.routines
        .where((routine) => routine.stageId == position.stageId)
        .expand((routine) => routine.periodTypes)
        .where((period) => period.id == position.periodTypeId)
        .firstOrNull;
    final periodName = period?.name;
    final periodPrefix = periodName == null || periodName.isEmpty
        ? ''
        : periodName;
    return '$periodPrefix第${position.lessonIndex}节';
  }

  String _dateConflictLabel(DateTime date) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${date.month}月${date.day}日（周${weekdays[date.weekday - 1]}）';
  }

  ActualChangePreview _previewMove({
    required SchedulingSnapshot snapshot,
    required List<ActualLesson> lessons,
    required List<CalendarException> exceptions,
    required String sourceKey,
    required DateTime targetDate,
    required SchedulePosition targetPosition,
    bool groupPart = false,
    SchedulingProblem? problem,
  }) {
    final source = lessons
        .where((lesson) => lesson.key == sourceKey)
        .firstOrNull;
    final errors = <String>[];
    if (source == null) {
      return const ActualChangePreview(changes: [], errors: ['原课次不存在']);
    }
    final resolvedProblem = problem ?? const ProblemBuilder().build(snapshot);
    final canonicalTarget =
        (resolvedProblem.positionsByClass[source.item.classId] ??
                const <SchedulePosition>[])
            .where((position) => position.sameCell(targetPosition))
            .firstOrNull;
    if (canonicalTarget != null) targetPosition = canonicalTarget;
    if (!groupPart && source.item.meetingId != null) {
      final group = lessons
          .where(
            (lesson) =>
                lesson.item.meetingId == source.item.meetingId &&
                lesson.date == source.date,
          )
          .toList();
      if (group.length > 1) {
        final keys = group.map((lesson) => lesson.key).toSet();
        final changes = <ActualLessonChange>[];
        final groupErrors = <String>[];
        for (final member in group) {
          final allowed =
              resolvedProblem.positionsByClass[member.item.classId] ??
              const <SchedulePosition>[];
          final destination = allowed
              .where(
                (position) => position.stageId == targetPosition.stageId
                    ? position.sameCell(targetPosition)
                    : position.hasSameClock(targetPosition),
              )
              .firstOrNull;
          if (destination == null) {
            groupErrors.add('合班成员的目标节次不存在或时间不一致');
            continue;
          }
          final preview = _previewMove(
            snapshot: snapshot,
            lessons: lessons
                .where(
                  (lesson) =>
                      !keys.contains(lesson.key) || lesson.key == member.key,
                )
                .toList(),
            exceptions: exceptions,
            sourceKey: member.key,
            targetDate: targetDate,
            targetPosition: destination,
            groupPart: true,
            problem: resolvedProblem,
          );
          groupErrors.addAll(preview.errors);
          changes.addAll(preview.changes);
        }
        if (groupErrors.isEmpty && changes.length == group.length) {
          ScheduleItem normalized(ActualLesson lesson) => ScheduleItem(
            id: lesson.key,
            termId: lesson.item.termId,
            assignmentId: lesson.item.assignmentId,
            classId: lesson.item.classId,
            teacherId: lesson.item.teacherId,
            subjectId: lesson.item.subjectId,
            weekMode: WeekMode.weekly,
            combinedGroupId: lesson.item.combinedGroupId,
            meetingId: lesson.item.meetingId,
            position: lesson.item.position,
          );
          final candidate = changes
              .map((change) => normalized(change.after))
              .toList();
          final week = snapshot.term.teachingWeekOf(targetDate);
          final others = [
            for (final lesson in lessons)
              if (!keys.contains(lesson.key) &&
                  lesson.item.position != null &&
                  snapshot.term.teachingWeekOf(lesson.date) == week)
                normalized(lesson),
          ];
          final blockers = _evaluatePlacementByDate(
            resolvedProblem,
            others,
            SchedulePlacementCandidate(
              unit: ScheduleUnit(source.item.meetingId!, candidate),
              positions: {
                for (final item in candidate) item.id: item.position!,
              },
            ),
            {
              for (final lesson in lessons)
                if (lesson.date == targetDate) lesson.key,
            },
          );
          groupErrors.addAll(blockers.map((blocker) => blocker.message));
        }
        return ActualChangePreview(
          changes: groupErrors.isEmpty ? changes : const [],
          errors: groupErrors,
        );
      }
      if (source.item.combinedGroupId != null) {
        return const ActualChangePreview(
          changes: [],
          errors: ['合班课组不完整，请先处理课表'],
        );
      }
    }
    if (snapshot.locks.any(
      (lock) =>
          (lock.scope == ScheduleLockScope.schoolClass &&
              lock.targetId == source.item.classId) ||
          (lock.scope == ScheduleLockScope.teacher &&
              lock.targetId == source.item.teacherId),
    )) {
      errors.add('班级或教师课表已锁定');
    }
    final stage = snapshot.stageIdForClass(source.item.classId);
    void checkCrossStageClock(Set<String> stages, String resource) {
      if (stages.length < 2) return;
      for (final stageId in stages) {
        final positions = resolvedProblem.positionsByClass.entries
            .where((entry) => snapshot.stageIdForClass(entry.key) == stageId)
            .expand((entry) => entry.value)
            .toList();
        if (positions.isEmpty ||
            positions.any((position) => !position.hasClockTime)) {
          errors.add('$resource涉及跨学段，学段 $stageId 缺少完整节次时间');
        }
      }
    }

    final teacherStages = <String>{
      ?stage,
      for (final assignment in snapshot.assignments)
        if (assignment.teacherId == source.item.teacherId)
          ?snapshot.stageIdForClass(assignment.classId),
      for (final lesson in lessons)
        if (lesson.item.teacherId == source.item.teacherId)
          ?snapshot.stageIdForClass(lesson.item.classId),
    };
    checkCrossStageClock(teacherStages, '教师');
    if (source.item.combinedGroupId != null) {
      final groupStages = <String>{
        ?stage,
        for (final item in snapshot.existingItems)
          if (item.combinedGroupId == source.item.combinedGroupId)
            ?snapshot.stageIdForClass(item.classId),
      };
      checkCrossStageClock(groupStages, '合班课');
    }
    if (stage != null) {
      final room = resolveSubjectRoomAssignment(
        assignments: snapshot.roomAssignments,
        subjectId: source.item.subjectId,
        termId: snapshot.term.id,
        stageId: stage,
        scope: FreeSlotScope.schoolClass,
        scopeId: source.item.classId,
        parentGradeId: snapshot.gradeIdForClass(source.item.classId),
      )?.roomId;
      if (room != null) {
        checkCrossStageClock({
          stage,
          for (final assignment in snapshot.roomAssignments)
            if (assignment.roomId == room) assignment.stageId,
        }, '公共场室');
      }
    }
    final exception = exceptions
        .where(
          (entry) =>
              entry.date.year == targetDate.year &&
              entry.date.month == targetDate.month &&
              entry.date.day == targetDate.day,
        )
        .firstOrNull;
    if (exception?.kind == CalendarExceptionKind.holiday) errors.add('目标日期停课');
    final templateWeekday = exception?.makeupWeekday ?? targetDate.weekday;
    final routine = snapshot.routines
        .where((r) => r.stageId == stage)
        .firstOrNull;
    final period = routine?.periodTypes
        .where((p) => p.id == targetPosition.periodTypeId)
        .firstOrNull;
    if (stage != targetPosition.stageId ||
        routine == null ||
        period == null ||
        targetPosition.weekday != templateWeekday ||
        !routine.teachingWeekdays.contains(targetPosition.weekday) ||
        targetPosition.lessonIndex < 1 ||
        targetPosition.lessonIndex >
            routine.effectiveLessonCount(period.id, targetPosition.weekday) ||
        snapshot.term.teachingWeekOf(targetDate) == null) {
      errors.add('目标课位不存在');
    }
    for (final other in lessons) {
      if (other.key == source.key ||
          other.date.year != targetDate.year ||
          other.date.month != targetDate.month ||
          other.date.day != targetDate.day ||
          other.item.position == null) {
        continue;
      }
      final rawPosition = other.item.position!;
      final position =
          (resolvedProblem.positionsByClass[other.item.classId] ??
                  const <SchedulePosition>[])
              .where((position) => position.sameCell(rawPosition))
              .firstOrNull ??
          rawPosition;
      final overlap = targetPosition.stageId == position.stageId
          ? targetPosition.periodTypeId == position.periodTypeId &&
                    targetPosition.lessonIndex == position.lessonIndex ||
                (targetPosition.hasClockTime &&
                    position.hasClockTime &&
                    targetPosition.startMinute! < position.endMinute! &&
                    position.startMinute! < targetPosition.endMinute!)
          : targetPosition.hasClockTime &&
                position.hasClockTime &&
                targetPosition.startMinute! < position.endMinute! &&
                position.startMinute! < targetPosition.endMinute!;
      if (overlap && source.item.classId == other.item.classId) {
        errors.add(
          '换入「${_lessonConflictLabel(snapshot, source)}」时，'
          '班级「${_classConflictLabel(snapshot, other.item.classId)}」在'
          '${_dateConflictLabel(targetDate)}${_positionConflictLabel(snapshot, position)}'
          '已有「${_lessonConflictLabel(snapshot, other)}」',
        );
      }
      if (overlap && source.item.teacherId == other.item.teacherId) {
        final teacher = snapshot.teachers
            .where((entry) => entry.id == source.item.teacherId)
            .firstOrNull;
        final teacherName = teacher?.displayName ?? source.item.teacherId;
        errors.add(
          '换入「${_lessonConflictLabel(snapshot, source)}」时，教师「$teacherName」'
          '在${_dateConflictLabel(targetDate)}${_positionConflictLabel(snapshot, position)}'
          '已为「${_classConflictLabel(snapshot, other.item.classId)}」上'
          '「${_lessonConflictLabel(snapshot, other)}」',
        );
      }
      if (!overlap &&
          targetPosition.stageId != position.stageId &&
          source.item.teacherId == other.item.teacherId &&
          (!targetPosition.hasClockTime || !position.hasClockTime)) {
        errors.add('跨学段教师缺少节次时间');
      }
    }
    if (errors.isEmpty) {
      ScheduleItem actualItem(ActualLesson lesson, SchedulePosition position) =>
          ScheduleItem(
            id: lesson.key,
            termId: lesson.item.termId,
            assignmentId: lesson.item.assignmentId,
            classId: lesson.item.classId,
            teacherId: lesson.item.teacherId,
            subjectId: lesson.item.subjectId,
            weekMode: WeekMode.weekly,
            combinedGroupId: lesson.item.combinedGroupId,
            meetingId: lesson.item.meetingId,
            position: position,
          );
      final week = snapshot.term.teachingWeekOf(targetDate);
      final placed = [
        for (final lesson in lessons)
          if (lesson.key != source.key &&
              lesson.item.position != null &&
              snapshot.term.teachingWeekOf(lesson.date) == week)
            actualItem(lesson, lesson.item.position!),
      ];
      final candidate = actualItem(source, targetPosition);
      final blockers = _evaluatePlacementByDate(
        resolvedProblem,
        placed,
        SchedulePlacementCandidate(
          unit: ScheduleUnit(candidate.id, [candidate]),
          positions: {candidate.id: targetPosition},
        ),
        {
          for (final lesson in lessons)
            if (lesson.date == targetDate) lesson.key,
        },
      );
      errors.addAll(blockers.map((blocker) => blocker.message));
    }
    if (errors.isNotEmpty) {
      return ActualChangePreview(changes: const [], errors: errors);
    }
    return ActualChangePreview(
      changes: [
        ActualLessonChange(
          before: source,
          after: ActualLesson(
            date: DateTime(targetDate.year, targetDate.month, targetDate.day),
            originDate: source.originDate ?? source.date,
            item: source.item.at(targetPosition),
          ),
        ),
      ],
      errors: const [],
    );
  }

  List<ScheduleBlocker> _evaluatePlacementByDate(
    SchedulingProblem problem,
    List<ScheduleItem> placed,
    SchedulePlacementCandidate candidate,
    Set<String> sameDayKeys,
  ) {
    const evaluator = ConstraintEvaluator();
    final weekly = evaluator.evaluatePlacement(problem, placed, candidate);
    final daily = evaluator.evaluatePlacement(
      problem,
      placed.where((item) => sameDayKeys.contains(item.id)).toList(),
      candidate,
    );
    bool dailyRule(ScheduleBlocker blocker) {
      if (const {
        'classOccupied',
        'teacherOccupied',
        'teacherMutualExclusion',
        'subjectMutualExclusion',
        'forbiddenAdjacency',
        'subjectDailyMaximum',
        'dailyConsecutiveMaximum',
        'parallelLimit',
        'roomCapacity',
        'consecutive',
        'lunchProtection',
      }.contains(blocker.code)) {
        return true;
      }
      if (blocker.code == 'conditionMaximum') {
        final condition = problem.snapshot.conditions
            .where((item) => item.id == blocker.conditionId)
            .firstOrNull;
        return condition != null &&
            (condition.type == ScheduleConditionType.dailyLimit ||
                condition.weekday != null);
      }
      return false;
    }

    return [
      for (final blocker in weekly)
        if (!dailyRule(blocker)) blocker,
      for (final blocker in daily)
        if (dailyRule(blocker)) blocker,
    ];
  }

  List<ActualLesson> expand(
    SchedulingSnapshot snapshot,
    List<CalendarException> exceptions,
  ) {
    final problem = const ProblemBuilder().build(snapshot);
    final result = <ActualLesson>[];
    for (final day in _actualDays(snapshot, exceptions)) {
      for (final item in snapshot.existingItems) {
        if (item.position?.weekday != day.weekday ||
            !occursInWeek(item.weekMode, oddWeek: day.templateWeek.isOdd)) {
          continue;
        }
        final raw = item.position!;
        final position =
            (problem.positionsByClass[item.classId] ??
                    const <SchedulePosition>[])
                .where((candidate) => candidate.sameCell(raw))
                .firstOrNull ??
            raw;
        result.add(ActualLesson(date: day.date, item: item.at(position)));
      }
    }
    return result;
  }

  Iterable<({DateTime date, int weekday, int templateWeek})> _actualDays(
    SchedulingSnapshot snapshot,
    List<CalendarException> exceptions,
  ) sync* {
    final start = snapshot.term.firstTeachingWeekStart;
    if (start == null) return;
    final exceptionsByDay = {
      for (final exception in exceptions)
        DateTime(exception.date.year, exception.date.month, exception.date.day):
            exception,
    };
    for (
      var offset = 0;
      offset < snapshot.term.teachingWeekCount * 7;
      offset++
    ) {
      final date = DateTime(start.year, start.month, start.day + offset);
      final exception = exceptionsByDay[date];
      if (exception?.kind == CalendarExceptionKind.holiday) continue;
      final templateWeek = snapshot.term.teachingWeekOf(
        exception?.makeupForDate ?? date,
      );
      if (templateWeek == null) continue;
      yield (
        date: date,
        weekday: exception?.makeupWeekday ?? date.weekday,
        templateWeek: templateWeek,
      );
    }
  }
}
