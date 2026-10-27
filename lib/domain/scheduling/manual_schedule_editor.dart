import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/constraint_evaluator.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

/// 一次手动调整的完整预览结果，不修改持久化数据。
class ManualMoveResult {
  const ManualMoveResult({
    required this.items,
    required this.blockers,
    required this.changedItemIds,
  });

  final List<ScheduleItem> items;
  final List<ScheduleBlocker> blockers;
  final Set<String> changedItemIds;

  bool get allowed => blockers.isEmpty;
}

/// 计算拖拽、暂放和课表检测结果，不修改持久化数据。
class ManualScheduleEditor {
  const ManualScheduleEditor();

  /// 检查当前课表中所有已排课组及全局硬性下限。
  ///
  /// 拖拽期间可传入同一 [snapshot] 预先构建的 [problem]，避免重复解析作息。
  List<ScheduleBlocker> detectAll({
    required SchedulingSnapshot snapshot,
    required List<ScheduleItem> items,
    SchedulingProblem? problem,
  }) {
    final schedulingProblem = problem ?? const ProblemBuilder().build(snapshot);
    final evaluator = const ConstraintEvaluator();
    final blockers = <ScheduleBlocker>[
      for (final check in schedulingProblem.checks)
        if (!check.ready)
          ScheduleBlocker(code: check.code, message: check.message),
    ];
    final groups = <String, List<ScheduleItem>>{};
    for (final item in items) {
      groups.putIfAbsent(_groupKey(item), () => []).add(item);
    }
    for (final entry in groups.entries) {
      final placed = entry.value
          .where((item) => item.position != null)
          .toList();
      if (placed.isEmpty) continue;
      if (placed.length != entry.value.length) {
        blockers.add(
          ScheduleBlocker(
            code: 'meetingPartial',
            message: '同一课组中部分课程仍在暂放区，无法形成完整排课。',
            relatedIds: entry.value.map((item) => item.id).toList(),
          ),
        );
      }
      final groupIds = entry.value.map((item) => item.id).toSet();
      final others = items
          .where((item) => item.position != null && !groupIds.contains(item.id))
          .toList();
      blockers.addAll(
        evaluator.evaluatePlacement(
          schedulingProblem,
          others,
          SchedulePlacementCandidate(
            unit: ScheduleUnit(entry.key, placed),
            positions: {for (final item in placed) item.id: item.position!},
          ),
        ),
      );
    }
    blockers.addAll(evaluator.unmetHardRequirements(schedulingProblem, items));
    return _uniqueBlockers(blockers);
  }

  /// 预览一个课组移到目标节次，或移入暂放区。
  ///
  /// 高频预览时应传入同一 [snapshot] 预先构建的 [problem]。
  ManualMoveResult previewMove({
    required SchedulingSnapshot snapshot,
    required List<ScheduleItem> items,
    required String itemId,
    required SchedulePosition? target,
    String? swapWithItemId,
    SchedulingProblem? problem,
  }) {
    final selected = items.where((item) => item.id == itemId).firstOrNull;
    if (selected == null) {
      return _blocked(items, 'itemMissing', '这节课已不存在，请刷新课表后重试。');
    }

    final moving = _groupFor(items, selected);
    final locked = _lockedMembers(snapshot, moving);
    if (locked.isNotEmpty) {
      return _blocked(
        items,
        'locked',
        '课组中有班级或教师已锁定，无法移动。',
        relatedIds: locked.map((item) => item.id).toList(),
      );
    }

    final schedulingProblem = problem ?? const ProblemBuilder().build(snapshot);
    final evaluator = const ConstraintEvaluator();

    if (target == null) {
      final proposal = _result(items, {
        for (final item in moving) item.id: item.at(null),
      });
      final blockers = _newHardRequirementBlockers(
        evaluator,
        schedulingProblem,
        items,
        proposal.items,
      );
      return blockers.isEmpty
          ? proposal
          : ManualMoveResult(
              items: items,
              blockers: blockers,
              changedItemIds: const {},
            );
    }

    final destination = <String, ScheduleItem>{};
    for (final item in moving) {
      final position = _resolvePosition(
        snapshot: snapshot,
        problem: schedulingProblem,
        classId: item.classId,
        anchor: target,
      );
      if (position == null) {
        return _blocked(
          items,
          'position',
          '目标节次不在班级 ${item.classId} 的作息中，或跨学段节次时间不一致。',
          position: target,
          relatedIds: [item.id],
        );
      }
      destination[item.id] = item.at(position);
    }

    final movingIds = moving.map((item) => item.id).toSet();
    final occupants = <String, ScheduleItem>{};
    for (final placed in destination.values) {
      for (final other in items) {
        if (movingIds.contains(other.id) ||
            other.classId != placed.classId ||
            other.position == null ||
            !weekModesOverlap(other.weekMode, placed.weekMode) ||
            !other.position!.sameCell(placed.position!)) {
          continue;
        }
        occupants[_groupKey(other)] = other;
      }
    }
    if (swapWithItemId != null && !movingIds.contains(swapWithItemId)) {
      final explicit = items
          .where((item) => item.id == swapWithItemId)
          .firstOrNull;
      if (explicit != null &&
          explicit.position != null &&
          moving.any(
            (item) => weekModesOverlap(item.weekMode, explicit.weekMode),
          ) &&
          _sameMeetingPosition(explicit.position!, target)) {
        occupants[_groupKey(explicit)] = explicit;
      }
    }

    if (occupants.length > 1) {
      final singleWeekSplit =
          moving.any((item) => item.weekMode == WeekMode.weekly) &&
          occupants.values.every((item) => item.weekMode != WeekMode.weekly) &&
          occupants.values.map((item) => item.weekMode).toSet().length > 1;
      return _blocked(
        items,
        'multipleOccupants',
        singleWeekSplit
            ? '目标节次的单周和双周由不同课组占用，整周课程无法换入；请先腾出完整节次。'
            : '目标节次涉及多个课组，无法确定唯一交换对象；请先腾出目标节次。',
        position: target,
        relatedIds: occupants.values.map((item) => item.id).toList(),
      );
    }

    if (occupants.isNotEmpty) {
      final source = selected.position;
      if (source == null) {
        final singleWeekSpace =
            moving.any((item) => item.weekMode == WeekMode.weekly) &&
            occupants.values.any((item) => item.weekMode != WeekMode.weekly);
        return _blocked(
          items,
          singleWeekSpace ? 'singleWeekSpace' : 'swapSource',
          singleWeekSpace
              ? '目标节次只空出单周，整周课程无法放入；请先腾出完整节次。'
              : '暂放课程没有来源节次，无法与目标课程交换；请先选择空节次。',
          position: target,
        );
      }
      if (moving.any(
        (item) =>
            item.position == null ||
            !_sameMeetingPosition(item.position!, source),
      )) {
        return _blocked(
          items,
          'swapSource',
          '原课组没有一致的来源节次，无法与目标课程交换；请先选择空节次。',
          position: target,
        );
      }

      final displaced = _groupFor(items, occupants.values.single);
      final lockedDisplaced = _lockedMembers(snapshot, displaced);
      if (lockedDisplaced.isNotEmpty) {
        return _blocked(
          items,
          'locked',
          '目标课组中有班级或教师已锁定，无法交换。',
          position: target,
          relatedIds: lockedDisplaced.map((item) => item.id).toList(),
        );
      }
      if (displaced.any(
        (item) =>
            item.position == null ||
            !_sameMeetingPosition(item.position!, target),
      )) {
        return _blocked(
          items,
          'swapTarget',
          '目标课组的成员没有排在同一节次，无法完整交换。',
          position: target,
        );
      }
      for (final item in displaced) {
        final position = _resolvePosition(
          snapshot: snapshot,
          problem: schedulingProblem,
          classId: item.classId,
          anchor: source,
        );
        if (position == null) {
          return _blocked(
            items,
            'swapPosition',
            '原节次不在目标课组班级 ${item.classId} 的作息中，无法完整交换。',
            position: source,
            relatedIds: [item.id],
          );
        }
        destination[item.id] = item.at(position);
      }
      final displacedIds = displaced.map((item) => item.id).toSet();
      for (final item in displaced.where(
        (item) => item.weekMode == WeekMode.weekly,
      )) {
        final swapped = destination[item.id]!;
        final remainingSingleWeekLesson = items.any(
          (other) =>
              !movingIds.contains(other.id) &&
              !displacedIds.contains(other.id) &&
              other.classId == item.classId &&
              other.weekMode != WeekMode.weekly &&
              other.position?.sameCell(swapped.position!) == true,
        );
        if (remainingSingleWeekLesson) {
          return _blocked(
            items,
            'singleWeekSpace',
            '原节次只空出单周，整周课程无法交换到此处；请先腾出完整节次。',
            position: swapped.position,
            relatedIds: [item.id],
          );
        }
      }
    }

    final proposal = _result(items, destination);
    if (proposal.changedItemIds.isEmpty) return proposal;

    final changedGroupKeys = proposal.items
        .where((item) => proposal.changedItemIds.contains(item.id))
        .map(_groupKey)
        .toSet();
    final changedGroups = <String, List<ScheduleItem>>{};
    for (final item in proposal.items) {
      if (changedGroupKeys.contains(_groupKey(item))) {
        changedGroups.putIfAbsent(_groupKey(item), () => []).add(item);
      }
    }
    final blockers = <ScheduleBlocker>[];
    for (final entry in changedGroups.entries) {
      final group = entry.value;
      if (group.every((item) => item.position == null)) continue;
      final groupIds = group.map((item) => item.id).toSet();
      final others = proposal.items
          .where((item) => !groupIds.contains(item.id))
          .toList();
      blockers.addAll(
        evaluator.evaluatePlacement(
          schedulingProblem,
          others,
          SchedulePlacementCandidate(
            unit: ScheduleUnit(entry.key, group),
            positions: {for (final item in group) item.id: item.position!},
          ),
        ),
      );
    }
    blockers.addAll(
      _newHardRequirementBlockers(
        evaluator,
        schedulingProblem,
        items,
        proposal.items,
      ),
    );
    if (blockers.isNotEmpty) {
      return ManualMoveResult(
        items: items,
        blockers: _uniqueBlockers(blockers),
        changedItemIds: const {},
      );
    }
    return proposal;
  }
}

List<ScheduleBlocker> _uniqueBlockers(List<ScheduleBlocker> blockers) {
  final unique = <String, ScheduleBlocker>{};
  for (final blocker in blockers) {
    final key =
        '${blocker.code}:${blocker.conditionId}:${blocker.position?.cellKey}:${blocker.relatedIds.join(',')}:${blocker.message}';
    unique.putIfAbsent(key, () => blocker);
  }
  return unique.values.toList();
}

List<ScheduleBlocker> _newHardRequirementBlockers(
  ConstraintEvaluator evaluator,
  SchedulingProblem problem,
  List<ScheduleItem> before,
  List<ScheduleItem> after,
) {
  final existing = {
    for (final blocker in evaluator.unmetHardRequirements(problem, before))
      _blockerIdentity(blocker): blocker,
  };
  return evaluator.unmetHardRequirements(problem, after).where((blocker) {
    final previous = existing[_blockerIdentity(blocker)];
    if (previous == null) return true;
    final beforeCount = _placedCount(previous);
    final afterCount = _placedCount(blocker);
    return beforeCount != null &&
        afterCount != null &&
        afterCount < beforeCount;
  }).toList();
}

String _blockerIdentity(ScheduleBlocker blocker) =>
    '${blocker.code}:${blocker.conditionId}:${blocker.position?.cellKey}:${blocker.message.replaceAll(RegExp(r'已排 \d+ 节'), '已排 * 节')}';

int? _placedCount(ScheduleBlocker blocker) => int.tryParse(
  RegExp(r'已排 (\d+) 节').firstMatch(blocker.message)?.group(1) ?? '',
);

String _groupKey(ScheduleItem item) =>
    item.meetingId == null ? 'item:${item.id}' : 'meeting:${item.meetingId}';

List<ScheduleItem> _groupFor(List<ScheduleItem> items, ScheduleItem item) =>
    item.meetingId == null
    ? [item]
    : items.where((other) => other.meetingId == item.meetingId).toList();

List<ScheduleItem> _lockedMembers(
  SchedulingSnapshot snapshot,
  List<ScheduleItem> members,
) {
  final lockedClasses = <String>{};
  final lockedTeachers = <String>{};
  for (final lock in snapshot.locks) {
    if (lock.termId != snapshot.term.id) continue;
    switch (lock.scope) {
      case ScheduleLockScope.schoolClass:
        lockedClasses.add(lock.targetId);
      case ScheduleLockScope.teacher:
        lockedTeachers.add(lock.targetId);
    }
  }
  return members
      .where(
        (item) =>
            lockedClasses.contains(item.classId) ||
            lockedTeachers.contains(item.teacherId),
      )
      .toList();
}

SchedulePosition? _resolvePosition({
  required SchedulingSnapshot snapshot,
  required SchedulingProblem problem,
  required String classId,
  required SchedulePosition anchor,
}) {
  final stageId = snapshot.stageIdForClass(classId);
  if (stageId == null) return null;
  for (final position in problem.positionsByClass[classId] ?? const []) {
    if (stageId == anchor.stageId
        ? position.sameCell(anchor)
        : position.hasSameClock(anchor)) {
      return position;
    }
  }
  return null;
}

bool _sameMeetingPosition(SchedulePosition position, SchedulePosition anchor) =>
    position.stageId == anchor.stageId
    ? position.sameCell(anchor)
    : position.hasSameClock(anchor);

ManualMoveResult _blocked(
  List<ScheduleItem> items,
  String code,
  String message, {
  SchedulePosition? position,
  List<String> relatedIds = const [],
}) => ManualMoveResult(
  items: items,
  blockers: [
    ScheduleBlocker(
      code: code,
      message: message,
      position: position,
      relatedIds: relatedIds,
    ),
  ],
  changedItemIds: const {},
);

ManualMoveResult _result(
  List<ScheduleItem> items,
  Map<String, ScheduleItem> replacements,
) {
  final changedIds = <String>{};
  final updated = [
    for (final item in items)
      if (replacements[item.id] case final replacement?) replacement else item,
  ];
  for (final item in items) {
    final replacement = replacements[item.id];
    if (replacement != null &&
        replacement.position?.cellKey != item.position?.cellKey) {
      changedIds.add(item.id);
    }
  }
  return ManualMoveResult(
    items: updated,
    blockers: const [],
    changedItemIds: changedIds,
  );
}
