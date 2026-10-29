import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_lesson_constraint.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/scheduling/constraint_evaluator.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

class ScheduleSettingChange {
  const ScheduleSettingChange(this.group, this.label, this.before, this.after);

  final String group;
  final String label;
  final String before;
  final String after;
}

class ScheduleAdjustment {
  const ScheduleAdjustment(this.label, this.before, this.after);

  final String label;
  final String before;
  final String after;
}

class ScheduleReconciliationPreview {
  const ScheduleReconciliationPreview({
    required this.inputFingerprint,
    required this.items,
    required this.changes,
    required this.adjustments,
    required this.checks,
    required this.keptCount,
    required this.movedCount,
    required this.unplacedCount,
    required this.addedCount,
    required this.removedCount,
    required this.locksToRelease,
    required this.assignmentLessonCounts,
  });

  final String inputFingerprint;
  final List<ScheduleItem> items;
  final List<ScheduleSettingChange> changes;
  final List<ScheduleAdjustment> adjustments;
  final List<SchedulePreflightCheck> checks;
  final int keptCount;
  final int movedCount;
  final int unplacedCount;
  final int addedCount;
  final int removedCount;
  final List<ScheduleLock> locksToRelease;
  final Map<String, int> assignmentLessonCounts;

  bool get canApply => checks.every((check) => check.ready);
}

/// Retains valid existing cells before searching for positions for affected
/// lessons. A result may contain unplaced lessons when no legal cell remains.
class ScheduleReconciler {
  const ScheduleReconciler({this.evaluator = const ConstraintEvaluator()});

  final ConstraintEvaluator evaluator;

  List<ScheduleSettingChange> describeChanges(
    SchedulingSnapshot baseline,
    SchedulingSnapshot current,
  ) => _changes(baseline, current);

  ScheduleReconciliationPreview preview(
    SchedulingSnapshot baseline,
    SchedulingSnapshot current,
  ) {
    final (plannedAssignments, assignmentLessonCounts) =
        _normalizeAssignmentCounts(baseline, current);
    final effective = current.copyWith(assignments: plannedAssignments);
    final oldAssignments = {
      for (final row in baseline.assignments) row.id: row,
    };
    final oldItemsByAssignment = <String, List<ScheduleItem>>{};
    for (final item in baseline.existingItems) {
      oldItemsByAssignment.putIfAbsent(item.assignmentId, () => []).add(item);
    }
    for (final items in oldItemsByAssignment.values) {
      items.sort((left, right) {
        if (left.isPlaced != right.isPlaced) return left.isPlaced ? -1 : 1;
        return left.id.compareTo(right.id);
      });
    }
    final usedAssignments = <String>{};
    final usedOldItems = <String>{};
    final originByNewId = <String, ScheduleItem>{};
    final usedNewIds = <String>{};
    final aligned = <ScheduleItem>[];
    for (final assignment in effective.assignments) {
      if (assignment.lessonCount <= 0) continue;
      var oldAssignment = oldAssignments[assignment.id];
      if (oldAssignment == null) {
        for (final candidate in baseline.assignments) {
          if (usedAssignments.contains(candidate.id) ||
              candidate.classId != assignment.classId ||
              candidate.subjectId != assignment.subjectId ||
              candidate.weekMode != assignment.weekMode) {
            continue;
          }
          if (candidate.teacherId == assignment.teacherId) {
            oldAssignment = candidate;
            break;
          }
          oldAssignment ??= candidate;
        }
      }
      if (oldAssignment != null) usedAssignments.add(oldAssignment.id);
      final previous = oldItemsByAssignment[oldAssignment?.id] ?? const [];
      for (var index = 0; index < assignment.lessonCount; index++) {
        final old = index < previous.length ? previous[index] : null;
        if (old != null) usedOldItems.add(old.id);
        var id = old != null && old.assignmentId == assignment.id
            ? old.id
            : '${assignment.id}:${index + 1}';
        var suffix = 2;
        while (!usedNewIds.add(id)) {
          id = '${assignment.id}:${index + 1}:$suffix';
          suffix++;
        }
        aligned.add(
          ScheduleItem(
            id: id,
            termId: current.term.id,
            assignmentId: assignment.id,
            classId: assignment.classId,
            teacherId: assignment.teacherId,
            subjectId: assignment.subjectId,
            weekMode: assignment.weekMode,
            combinedGroupId: assignment.combinedLessonGroupId,
            meetingId:
                oldAssignment?.combinedLessonGroupId ==
                    assignment.combinedLessonGroupId
                ? old?.meetingId
                : null,
            position: old?.position,
          ),
        );
        if (old != null) originByNewId[id] = old;
      }
    }

    final problem = const ProblemBuilder().build(
      effective.copyWith(existingItems: aligned, locks: const []),
    );
    final oldById = {for (final item in aligned) item.id: item};
    final units = [...problem.units]
      ..sort((left, right) {
        int priority(ScheduleUnit unit) {
          final old = originByNewId[unit.items.first.id];
          if (old == null || !old.isPlaced) return 2;
          final locked = baseline.locks.any((lock) => _protects(lock, old));
          return locked ? 0 : 1;
        }

        final order = priority(left).compareTo(priority(right));
        return order != 0 ? order : left.id.compareTo(right.id);
      });
    final candidatesByUnit = {
      for (final unit in units) unit.id: _candidates(problem, unit),
    };
    final placed = <ScheduleItem>[];
    final waiting = <ScheduleUnit>[];
    for (final unit in units) {
      final old = unit.items.map((item) => oldById[item.id]).toList();
      if (old.any((item) => item?.position == null)) {
        waiting.add(unit);
        continue;
      }
      final candidate = candidatesByUnit[unit.id]!
          .where(
            (candidate) => unit.items.every((item) {
              final position = oldById[item.id]?.position;
              return position != null &&
                  candidate.positions[item.id]?.sameCell(position) == true;
            }),
          )
          .firstOrNull;
      if (candidate == null ||
          evaluator.evaluatePlacement(problem, placed, candidate).isNotEmpty) {
        waiting.add(unit);
      } else {
        placed.addAll(candidate.placedItems);
      }
    }
    final unplaced = <ScheduleItem>[];
    for (final unit in waiting) {
      final oldPosition = oldById[unit.items.first.id]?.position;
      final candidates = [...candidatesByUnit[unit.id]!]
        ..sort(
          (left, right) =>
              _distance(
                left.positions[unit.items.first.id]!,
                oldPosition,
              ).compareTo(
                _distance(right.positions[unit.items.first.id]!, oldPosition),
              ),
        );
      final chosen = candidates
          .where(
            (candidate) =>
                evaluator.evaluatePlacement(problem, placed, candidate).isEmpty,
          )
          .firstOrNull;
      if (chosen == null) {
        unplaced.addAll(unit.items.map((item) => item.at(null)));
      } else {
        placed.addAll(chosen.placedItems);
      }
    }
    final result = [...placed, ...unplaced]
      ..sort((left, right) => left.id.compareTo(right.id));
    final locksToRelease = <ScheduleLock>{};
    var kept = 0;
    var moved = 0;
    var temporarilyUnplaced = 0;
    var added = 0;
    for (final item in result) {
      final old = originByNewId[item.id];
      if (old == null) {
        added++;
        continue;
      }
      if (!old.isPlaced) continue;
      if (item.position == null) {
        temporarilyUnplaced++;
      } else if (item.position!.sameCell(old.position!)) {
        kept++;
        continue;
      } else {
        moved++;
      }
      locksToRelease.addAll(
        baseline.locks.where((lock) => _protects(lock, old)),
      );
    }
    for (final old in baseline.existingItems) {
      if (usedOldItems.contains(old.id)) continue;
      locksToRelease.addAll(
        baseline.locks.where((lock) => _protects(lock, old)),
      );
    }
    final classNames = {
      for (final row in [...baseline.classes, ...current.classes])
        row.id: row.name,
    };
    final subjectNames = {
      for (final row in [...baseline.subjects, ...current.subjects])
        row.id: row.name,
    };
    String label(ScheduleItem item) =>
        '${classNames[item.classId] ?? item.classId} · ${subjectNames[item.subjectId] ?? item.subjectId}';
    final adjustments = <ScheduleAdjustment>[];
    for (final item in result) {
      final old = originByNewId[item.id];
      if (old != null &&
          ((old.position == null && item.position == null) ||
              (old.position != null &&
                  item.position != null &&
                  old.position!.sameCell(item.position!)))) {
        continue;
      }
      adjustments.add(
        ScheduleAdjustment(
          label(item),
          _positionLabel(
            old?.position,
            baseline,
            empty: old == null ? '新增' : '暂放区',
          ),
          _positionLabel(item.position, current, empty: '暂放区'),
        ),
      );
    }
    for (final old in baseline.existingItems) {
      if (!usedOldItems.contains(old.id)) {
        adjustments.add(
          ScheduleAdjustment(
            label(old),
            _positionLabel(old.position, baseline, empty: '暂放区'),
            '已减少',
          ),
        );
      }
    }
    return ScheduleReconciliationPreview(
      inputFingerprint: current.inputFingerprint,
      items: result,
      changes: _changes(baseline, effective),
      adjustments: adjustments,
      checks: problem.checks,
      keptCount: kept,
      movedCount: moved,
      unplacedCount: temporarilyUnplaced,
      addedCount: added,
      removedCount: baseline.existingItems.length - usedOldItems.length,
      locksToRelease: locksToRelease.toList(),
      assignmentLessonCounts: assignmentLessonCounts,
    );
  }

  static (List<TeacherAssignment>, Map<String, int>) _normalizeAssignmentCounts(
    SchedulingSnapshot baseline,
    SchedulingSnapshot current,
  ) {
    final targets = <String, int>{};
    for (final schoolClass in current.classes) {
      final bySubjectMode = <String, int>{};
      for (final requirement in current.requirements.where(
        (row) => row.gradeId == schoolClass.gradeId && row.classId == null,
      )) {
        bySubjectMode['${requirement.subjectId}:${requirement.weekMode.storageValue}'] =
            requirement.lessonCount;
      }
      for (final requirement in current.requirements.where(
        (row) => row.classId == schoolClass.id,
      )) {
        bySubjectMode['${requirement.subjectId}:${requirement.weekMode.storageValue}'] =
            requirement.lessonCount;
      }
      for (final entry in bySubjectMode.entries) {
        targets['${schoolClass.id}:${entry.key}'] = entry.value;
      }
    }
    final byDemand = <String, List<TeacherAssignment>>{};
    for (final assignment in current.assignments) {
      byDemand.putIfAbsent(assignment.demandKey, () => []).add(assignment);
    }
    final updates = <String, int>{};
    final normalized = <TeacherAssignment>[];
    for (final entry in byDemand.entries) {
      final rows = [...entry.value];
      final target = targets[entry.key] ?? 0;
      var total = rows.fold<int>(0, (sum, row) => sum + row.lessonCount);
      if (total < target && rows.isNotEmpty) {
        rows.sort((a, b) {
          final byCount = b.lessonCount.compareTo(a.lessonCount);
          return byCount != 0 ? byCount : a.id.compareTo(b.id);
        });
        final chosen = rows.first;
        updates[chosen.id] = chosen.lessonCount + target - total;
      } else if (total > target) {
        rows.sort((a, b) {
          int placed(String id) => baseline.existingItems
              .where((item) => item.assignmentId == id && item.isPlaced)
              .length;
          final byPlaced = placed(a.id).compareTo(placed(b.id));
          return byPlaced != 0 ? byPlaced : b.sortOrder.compareTo(a.sortOrder);
        });
        for (final row in rows) {
          if (total <= target) break;
          final reduced = (total - target).clamp(0, row.lessonCount);
          updates[row.id] = row.lessonCount - reduced;
          total -= reduced;
        }
      }
      for (final row in entry.value) {
        final count = updates[row.id] ?? row.lessonCount;
        if (count > 0) normalized.add(row.copyWith(lessonCount: count));
      }
    }
    return (normalized, updates);
  }

  static bool _protects(ScheduleLock lock, ScheduleItem item) =>
      lock.termId == item.termId &&
      ((lock.scope == ScheduleLockScope.schoolClass &&
              lock.targetId == item.classId) ||
          (lock.scope == ScheduleLockScope.teacher &&
              lock.targetId == item.teacherId));

  static int _distance(SchedulePosition position, SchedulePosition? old) {
    if (old == null) return position.weekday * 100 + position.lessonIndex;
    return (position.weekday - old.weekday).abs() * 100 +
        (position.periodTypeId == old.periodTypeId ? 0 : 30) +
        (position.lessonIndex - old.lessonIndex).abs();
  }

  static List<SchedulePlacementCandidate> _candidates(
    SchedulingProblem problem,
    ScheduleUnit unit,
  ) {
    if (unit.items.isEmpty) return const [];
    final first = unit.items.first;
    final result = <SchedulePlacementCandidate>[];
    for (final position
        in problem.positionsByClass[first.classId] ??
            const <SchedulePosition>[]) {
      final mapped = <String, SchedulePosition>{first.id: position};
      for (final item in unit.items.skip(1)) {
        final matching = (problem.positionsByClass[item.classId] ?? const [])
            .where(
              (candidate) => position.stageId == candidate.stageId
                  ? position.sameCell(candidate)
                  : position.hasSameClock(candidate),
            )
            .firstOrNull;
        if (matching == null) break;
        mapped[item.id] = matching;
      }
      if (mapped.length == unit.items.length) {
        result.add(SchedulePlacementCandidate(unit: unit, positions: mapped));
      }
    }
    return result;
  }

  static List<ScheduleSettingChange> _changes(
    SchedulingSnapshot before,
    SchedulingSnapshot after,
  ) {
    final changes = <ScheduleSettingChange>[];
    void add(String group, String label, String old, String next) {
      if (old != next) {
        changes.add(ScheduleSettingChange(group, label, old, next));
      }
    }

    final stageNames = {
      for (final stage in [...before.stages, ...after.stages])
        stage.id: stage.name,
    };
    final routinesBefore = {
      for (final row in before.routines) row.stageId: row,
    };
    final routinesAfter = {for (final row in after.routines) row.stageId: row};
    for (final stageId in {...routinesBefore.keys, ...routinesAfter.keys}) {
      final old = routinesBefore[stageId];
      final next = routinesAfter[stageId];
      final label = stageNames[stageId] ?? stageId;
      add(
        '作息时间',
        '$label · 上课日',
        old?.teachingWeekdays.join('、') ?? '无',
        next?.teachingWeekdays.join('、') ?? '无',
      );
      final oldPeriods = {
        for (final row in old?.periodTypes ?? const []) row.id: row,
      };
      final newPeriods = {
        for (final row in next?.periodTypes ?? const []) row.id: row,
      };
      for (final id in {...oldPeriods.keys, ...newPeriods.keys}) {
        final oldPeriod = oldPeriods[id];
        final newPeriod = newPeriods[id];
        String describe(LessonPeriodType? period, StageRoutine? routine) =>
            period == null
            ? '无'
            : '${period.name}，默认 ${period.defaultLessonCount} 节，'
                  '${period.lessonTimes.map((time) => '${time.lessonIndex}节 ${_clock(time.startMinute)}–${_clock(time.endMinute)}').join('；')}'
                  '${routine == null ? '' : routine.overrides.where((row) => row.periodTypeId == period.id).map((row) => '，周${row.weekday}改为${row.lessonCount}节').join()}';
        add(
          '作息时间',
          '$label · ${newPeriod?.name ?? oldPeriod?.name ?? id}',
          describe(oldPeriod, old),
          describe(newPeriod, next),
        );
      }
    }
    final classNames = {
      for (final row in [...before.classes, ...after.classes]) row.id: row.name,
    };
    final gradeNames = {
      for (final row in [...before.grades, ...after.grades]) row.id: row.name,
    };
    final teacherNames = {
      for (final row in [...before.teachers, ...after.teachers])
        row.id: row.displayName,
    };
    final subjectNames = {
      for (final row in [...before.subjects, ...after.subjects])
        row.id: row.name,
    };
    final oldGrades = {for (final row in before.grades) row.id: row};
    final newGrades = {for (final row in after.grades) row.id: row};
    for (final id in {...oldGrades.keys, ...newGrades.keys}) {
      final old = oldGrades[id];
      final next = newGrades[id];
      add(
        '年级结构',
        gradeNames[id] ?? id,
        old == null ? '无' : stageNames[old.stageId] ?? old.stageId,
        next == null ? '已删除' : stageNames[next.stageId] ?? next.stageId,
      );
    }
    final oldClasses = {for (final row in before.classes) row.id: row};
    final newClasses = {for (final row in after.classes) row.id: row};
    for (final id in {...oldClasses.keys, ...newClasses.keys}) {
      final old = oldClasses[id];
      final next = newClasses[id];
      add(
        '班级结构',
        classNames[id] ?? id,
        old == null ? '无' : gradeNames[old.gradeId] ?? old.gradeId,
        next == null ? '已删除' : gradeNames[next.gradeId] ?? next.gradeId,
      );
    }
    final oldSubjects = {for (final row in before.subjects) row.id: row};
    final newSubjects = {for (final row in after.subjects) row.id: row};
    for (final id in {...oldSubjects.keys, ...newSubjects.keys}) {
      if (oldSubjects[id] != null && newSubjects[id] == null) {
        add('科目', subjectNames[id] ?? id, '使用中', '已删除');
      }
    }
    final oldAssignments = {for (final row in before.assignments) row.id: row};
    final newAssignments = {for (final row in after.assignments) row.id: row};
    for (final id in {...oldAssignments.keys, ...newAssignments.keys}) {
      final old = oldAssignments[id];
      final next = newAssignments[id];
      final row = next ?? old!;
      String describe(TeacherAssignment? assignment) => assignment == null
          ? '无'
          : '${teacherNames[assignment.teacherId] ?? assignment.teacherId} · ${assignment.weekMode.label} ${assignment.lessonCount} 节';
      add(
        '教师任课',
        '${classNames[row.classId] ?? row.classId} · ${subjectNames[row.subjectId] ?? row.subjectId}',
        describe(old),
        describe(next),
      );
    }
    final oldRequirements = {
      for (final row in before.requirements)
        (row.gradeId, row.classId, row.subjectId, row.weekMode):
            row.lessonCount,
    };
    final newRequirements = {
      for (final row in after.requirements)
        (row.gradeId, row.classId, row.subjectId, row.weekMode):
            row.lessonCount,
    };
    final groups = {
      for (final row in [...before.requirements, ...after.requirements])
        (row.gradeId, row.subjectId, row.weekMode),
    };
    String countLabel(int count) => count == 0 ? '无' : '$count 节';
    for (final group in groups) {
      final (gradeId, subjectId, mode) = group;
      final classIds = {
        for (final row in [...before.classes, ...after.classes])
          if (row.gradeId == gradeId) row.id,
        for (final row in [...before.requirements, ...after.requirements])
          if (row.gradeId == gradeId && row.classId != null) row.classId!,
      };
      int count(
        Map<(String, String?, String, WeekMode), int> rows,
        String? classId,
      ) =>
          rows[(gradeId, classId, subjectId, mode)] ??
          rows[(gradeId, null, subjectId, mode)] ??
          0;
      final ids = classIds.isEmpty ? <String?>[null] : classIds.toList();
      final differences = [
        for (final id in ids)
          (id, count(oldRequirements, id), count(newRequirements, id)),
      ];
      final first = differences.first;
      final sameForGrade = differences.every(
        (row) => row.$2 == first.$2 && row.$3 == first.$3,
      );
      final label = '${subjectNames[subjectId] ?? subjectId} · ${mode.label}';
      if (sameForGrade) {
        add(
          '科目节数',
          '${gradeNames[gradeId] ?? gradeId} · $label',
          countLabel(first.$2),
          countLabel(first.$3),
        );
      } else {
        for (final row in differences) {
          add(
            '科目节数',
            '${classNames[row.$1] ?? gradeNames[gradeId] ?? gradeId} · $label',
            countLabel(row.$2),
            countLabel(row.$3),
          );
        }
      }
    }
    final oldFreeSlots = {for (final row in before.freeSlots) row.id: row};
    final newFreeSlots = {for (final row in after.freeSlots) row.id: row};
    final periodNames = {
      for (final routine in [...before.routines, ...after.routines])
        for (final period in routine.periodTypes) period.id: period.name,
    };
    final scopeNames = {...stageNames, ...gradeNames, ...classNames};
    for (final id in {...oldFreeSlots.keys, ...newFreeSlots.keys}) {
      final old = oldFreeSlots[id];
      final next = newFreeSlots[id];
      final row = next ?? old!;
      String describeFreeSlot(FreeSlot? slot) => slot == null
          ? '可排课'
          : '周${slot.weekday} ${periodNames[slot.periodTypeId] ?? slot.periodTypeId}'
                '第${slot.lessonIndex}节 · ${slot.label}';
      add(
        '免任课',
        '${stageNames[row.stageId] ?? row.stageId} · ${scopeNames[row.scopeId] ?? '全校'}',
        describeFreeSlot(old),
        describeFreeSlot(next),
      );
    }
    final oldSubjectPresets = {
      for (final row in before.subjectPresets)
        '${row.subjectId}:${row.cellKey}': row,
    };
    final newSubjectPresets = {
      for (final row in after.subjectPresets)
        '${row.subjectId}:${row.cellKey}': row,
    };
    for (final key in {...oldSubjectPresets.keys, ...newSubjectPresets.keys}) {
      final old = oldSubjectPresets[key];
      final next = newSubjectPresets[key];
      final row = next ?? old!;
      add(
        '科目预设',
        '${subjectNames[row.subjectId] ?? row.subjectId} · ${scopeNames[row.scopeId] ?? '全校'} · 周${row.weekday} ${periodNames[row.periodTypeId] ?? row.periodTypeId}第${row.lessonIndex}节',
        old?.value.label ?? '自动',
        next?.value.label ?? '自动',
      );
    }
    final oldTeacherPresets = {
      for (final row in before.teacherPresets)
        '${row.teacherId}:${row.cellKey}': row,
    };
    final newTeacherPresets = {
      for (final row in after.teacherPresets)
        '${row.teacherId}:${row.cellKey}': row,
    };
    for (final key in {...oldTeacherPresets.keys, ...newTeacherPresets.keys}) {
      final old = oldTeacherPresets[key];
      final next = newTeacherPresets[key];
      final row = next ?? old!;
      add(
        '教师预排',
        '${teacherNames[row.teacherId] ?? row.teacherId} · ${scopeNames[row.scopeId] ?? '全校'} · 周${row.weekday} ${periodNames[row.periodTypeId] ?? row.periodTypeId}第${row.lessonIndex}节',
        old?.value.label ?? '自动',
        next?.value.label ?? '自动',
      );
    }
    final oldGroupMembers = <String, Set<String>>{};
    final newGroupMembers = <String, Set<String>>{};
    for (final row in before.teacherGroupMembers) {
      oldGroupMembers.putIfAbsent(row.groupId, () => {}).add(row.teacherId);
    }
    for (final row in after.teacherGroupMembers) {
      newGroupMembers.putIfAbsent(row.groupId, () => {}).add(row.teacherId);
    }
    String describeMembers(Set<String>? ids) => ids == null || ids.isEmpty
        ? '无成员'
        : (ids.map((id) => teacherNames[id] ?? id).toList()..sort()).join('、');
    for (final id in {...oldGroupMembers.keys, ...newGroupMembers.keys}) {
      add(
        '教师分组',
        '分组 $id · 成员',
        describeMembers(oldGroupMembers[id]),
        describeMembers(newGroupMembers[id]),
      );
    }
    final oldGroupPresets = {
      for (final row in before.teacherGroupPresets)
        '${row.groupId}:${row.cellKey}': row,
    };
    final newGroupPresets = {
      for (final row in after.teacherGroupPresets)
        '${row.groupId}:${row.cellKey}': row,
    };
    for (final key in {...oldGroupPresets.keys, ...newGroupPresets.keys}) {
      final old = oldGroupPresets[key];
      final next = newGroupPresets[key];
      final row = next ?? old!;
      add(
        '分组预排',
        '分组 ${row.groupId} · ${scopeNames[row.scopeId] ?? '全校'} · '
            '周${row.weekday} ${periodNames[row.periodTypeId] ?? row.periodTypeId}第${row.lessonIndex}节',
        old?.value.label ?? '自动',
        next?.value.label ?? '自动',
      );
    }
    final oldPairings = {for (final row in before.pairings) row.id: row};
    final newPairings = {for (final row in after.pairings) row.id: row};
    String describePairing(SubjectPairing? row) => row == null
        ? '无'
        : '单周 ${subjectNames[row.oddSubjectId] ?? row.oddSubjectId} · '
              '双周 ${subjectNames[row.evenSubjectId] ?? row.evenSubjectId}';
    for (final id in {...oldPairings.keys, ...newPairings.keys}) {
      final old = oldPairings[id];
      final next = newPairings[id];
      add(
        '单双周配对',
        classNames[next?.classId ?? old!.classId] ??
            next?.classId ??
            old!.classId,
        describePairing(old),
        describePairing(next),
      );
    }
    final oldLimits = {for (final row in before.lessonConstraints) row.id: row};
    final newLimits = {for (final row in after.lessonConstraints) row.id: row};
    String describeLimit(SubjectLessonConstraint? row) {
      if (row == null) return '无限制';
      String range(int? min, int? max) =>
          min == null && max == null ? '不限' : '${min ?? 0}–${max ?? '不限'}';
      return '单日节数 ${range(row.minimumDailyLessons, row.maximumDailyLessons)}，'
          '单日连堂 ${range(row.minimumDailyConsecutivePairs, row.maximumDailyConsecutivePairs)}，'
          '每周连堂 ${range(row.minimumWeeklyConsecutivePairs, row.maximumWeeklyConsecutivePairs)}';
    }

    for (final id in {...oldLimits.keys, ...newLimits.keys}) {
      final old = oldLimits[id];
      final next = newLimits[id];
      final row = next ?? old!;
      add(
        '课节限制',
        '${subjectNames[row.subjectId] ?? row.subjectId} · '
            '${scopeNames[row.scopeId] ?? row.scopeId} · '
            '${row.weekday == null ? '每天' : '周${row.weekday}'}',
        describeLimit(old),
        describeLimit(next),
      );
    }
    final roomNames = {
      for (final row in [...before.rooms, ...after.rooms]) row.id: row.name,
    };
    String roomKey(
      String subjectId,
      String stageId,
      String scope,
      String scopeId,
    ) => '$subjectId:$stageId:$scope:$scopeId';
    final oldRooms = {
      for (final row in before.roomAssignments)
        roomKey(
          row.subjectId,
          row.stageId,
          row.scope.storageValue,
          row.scopeId,
        ): roomNames[row.roomId] ?? row.roomId ?? '不指定',
    };
    final newRooms = {
      for (final row in after.roomAssignments)
        roomKey(
          row.subjectId,
          row.stageId,
          row.scope.storageValue,
          row.scopeId,
        ): roomNames[row.roomId] ?? row.roomId ?? '不指定',
    };
    for (final key in {...oldRooms.keys, ...newRooms.keys}) {
      final parts = key.split(':');
      add(
        '场室要求',
        '${subjectNames[parts[0]] ?? parts[0]} · ${scopeNames[parts[3]] ?? stageNames[parts[1]] ?? parts[3]}',
        oldRooms[key] ?? '不指定',
        newRooms[key] ?? '不指定',
      );
    }
    final oldParallel = {
      for (final row in before.parallelLimits)
        roomKey(
          row.subjectId,
          row.stageId,
          row.scope.storageValue,
          row.scopeId,
        ): '${row.maxParallelLessons} 节',
    };
    final newParallel = {
      for (final row in after.parallelLimits)
        roomKey(
          row.subjectId,
          row.stageId,
          row.scope.storageValue,
          row.scopeId,
        ): '${row.maxParallelLessons} 节',
    };
    for (final key in {...oldParallel.keys, ...newParallel.keys}) {
      final parts = key.split(':');
      add(
        '并行限制',
        '${subjectNames[parts[0]] ?? parts[0]} · ${scopeNames[parts[3]] ?? stageNames[parts[1]] ?? parts[3]}',
        oldParallel[key] ?? '无限制',
        newParallel[key] ?? '无限制',
      );
    }
    String condition(ScheduleCondition? row) => row == null
        ? '无'
        : '${row.type.name} ${row.targetId ?? ''} ${row.weekday == null ? '' : '周${row.weekday}'} ${row.exact ?? row.minimum ?? ''}';
    final oldConditions = {for (final row in before.conditions) row.id: row};
    final newConditions = {for (final row in after.conditions) row.id: row};
    for (final id in {...oldConditions.keys, ...newConditions.keys}) {
      add(
        '排课规则',
        newConditions[id]?.name ?? oldConditions[id]?.name ?? id,
        condition(oldConditions[id]),
        condition(newConditions[id]),
      );
    }
    String preferenceName(Enum value) => switch (value) {
      ScheduleStrength.fast => '快速',
      ScheduleStrength.normal => '标准',
      ScheduleStrength.high => '高强度',
      ProgressConsistency.prefer => '尽量一致',
      ProgressConsistency.require => '必须一致',
      TeacherDistribution.indifferent => '不限制',
      TeacherDistribution.spread => '尽量分散',
      TeacherDistribution.concentrate => '尽量集中',
      ConsecutiveMode.preferSeparate => '尽量不连堂',
      ConsecutiveMode.requireSeparate => '禁止连堂',
      ConsecutiveMode.preferTogether => '尽量连堂',
      _ => value.name,
    };
    add(
      '排课偏好',
      '排课强度',
      preferenceName(before.preferences.strength),
      preferenceName(after.preferences.strength),
    );
    add(
      '排课偏好',
      '同级同科进度',
      preferenceName(before.preferences.progressConsistency),
      preferenceName(after.preferences.progressConsistency),
    );
    add(
      '排课偏好',
      '教师课程分布',
      preferenceName(before.preferences.teacherDistribution),
      preferenceName(after.preferences.teacherDistribution),
    );
    add(
      '排课偏好',
      '午间保护',
      before.preferences.protectLunchBreak ? '开启' : '关闭',
      after.preferences.protectLunchBreak ? '开启' : '关闭',
    );
    add(
      '排课偏好',
      '连堂策略',
      preferenceName(before.preferences.consecutiveMode),
      preferenceName(after.preferences.consecutiveMode),
    );
    add(
      '排课偏好',
      '进度一致性检测',
      before.preferences.checkProgressConsistency ? '开启' : '关闭',
      after.preferences.checkProgressConsistency ? '开启' : '关闭',
    );
    return changes;
  }

  static String _clock(int? minute) => minute == null
      ? '未设时间'
      : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  static String _positionLabel(
    SchedulePosition? position,
    SchedulingSnapshot snapshot, {
    required String empty,
  }) {
    if (position == null) return empty;
    final stage = snapshot.stages
        .where((row) => row.id == position.stageId)
        .firstOrNull;
    final routine = snapshot.routines
        .where((row) => row.stageId == position.stageId)
        .firstOrNull;
    final period = routine?.periodTypes
        .where((row) => row.id == position.periodTypeId)
        .firstOrNull;
    return '${stage?.name ?? ''} · 周${position.weekday} ${period?.name ?? position.periodTypeId}第${position.lessonIndex}节';
  }
}
