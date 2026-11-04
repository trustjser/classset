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
    this.unplaced = const [],
  });

  final List<ScheduleItem> items;
  final List<ScheduleBlocker> blockers;
  final Set<String> changedItemIds;
  final List<ScheduleUnplacedCourse> unplaced;

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

  /// 优先填入空位，必要时有限腾挪未锁定的课组，不减少已排课程。
  ManualMoveResult placeUnplaced({
    required SchedulingSnapshot snapshot,
    required List<ScheduleItem> items,
    required Set<String> itemIds,
    SchedulingProblem? problem,
  }) {
    final schedulingProblem = problem ?? const ProblemBuilder().build(snapshot);
    final pending = <String, ScheduleItem>{};
    final groupSizes = <String, int>{};
    for (final item in items.where(
      (item) => itemIds.contains(item.id) && !item.isPlaced,
    )) {
      final group = _groupFor(items, item);
      if (group.every((member) => !member.isPlaced)) {
        final key = _groupKey(item);
        pending.putIfAbsent(key, () => item);
        groupSizes[key] = group.length;
      }
    }
    const maxChecks = 20000;
    const maxDepth = 512;
    final clock = Stopwatch()..start();
    // 为后续腾挪保留预算，避免直接放入的回溯耗尽全部时间。
    const maxTime = Duration(seconds: 2);
    var checks = 0;
    var bestItems = items;
    var bestChanged = <String>{};
    final targetCount = groupSizes.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    bool getBudgetAvailable() => checks < maxChecks && clock.elapsed < maxTime;

    void search(
      List<ScheduleItem> current,
      Map<String, ScheduleItem> remaining,
      Set<String> changed,
      int depth,
    ) {
      if (changed.length > bestChanged.length) {
        bestItems = current;
        bestChanged = {...changed};
      }
      if (bestChanged.length == targetCount ||
          remaining.isEmpty ||
          depth >= maxDepth ||
          !getBudgetAvailable()) {
        return;
      }
      final possible =
          changed.length +
          remaining.keys.fold<int>(0, (sum, key) => sum + groupSizes[key]!);
      if (possible <= bestChanged.length) return;

      String? chosenKey;
      List<ManualMoveResult> chosenMoves = [];
      for (final entry in remaining.entries) {
        final moves = <ManualMoveResult>[];
        for (final position
            in schedulingProblem.positionsByClass[entry.value.classId] ??
                const <SchedulePosition>[]) {
          if (!getBudgetAvailable()) break;
          checks++;
          final result = previewMove(
            snapshot: snapshot,
            items: current,
            itemId: entry.value.id,
            target: position,
            problem: schedulingProblem,
          );
          if (result.allowed && result.changedItemIds.isNotEmpty) {
            moves.add(result);
          }
        }
        if (moves.isNotEmpty) {
          if (chosenKey == null || moves.length < chosenMoves.length) {
            chosenKey = entry.key;
            chosenMoves = moves;
          }
        }
        if (!getBudgetAvailable()) break;
      }
      if (chosenKey == null) return;
      final next = Map<String, ScheduleItem>.of(remaining)..remove(chosenKey);
      for (final move in chosenMoves) {
        final nextChanged = {...changed, ...move.changedItemIds};
        if (nextChanged.length > bestChanged.length) {
          bestItems = move.items;
          bestChanged = nextChanged;
        }
        if (!getBudgetAvailable() || bestChanged.length == targetCount) break;
        search(move.items, next, nextChanged, depth + 1);
        if (!getBudgetAvailable() || bestChanged.length == targetCount) break;
      }
      // 留下该课组，继续搜索其余课程，以便保留覆盖最多的部分解。
      if (getBudgetAvailable() && bestChanged.length < targetCount) {
        search(current, next, changed, depth + 1);
      }
    }

    final ordered = pending.entries.toList()
      ..sort((a, b) {
        final left =
            schedulingProblem.positionsByClass[a.value.classId]?.length ?? 0;
        final right =
            schedulingProblem.positionsByClass[b.value.classId]?.length ?? 0;
        final comparison = left.compareTo(right);
        return comparison != 0 ? comparison : a.key.compareTo(b.key);
      });
    // 先保留快速顺排的结果，避免大批量课程耗尽候选计数预算却没有进展。
    for (final entry in ordered) {
      for (final position
          in schedulingProblem.positionsByClass[entry.value.classId] ??
              const <SchedulePosition>[]) {
        if (!getBudgetAvailable()) break;
        checks++;
        final result = previewMove(
          snapshot: snapshot,
          items: bestItems,
          itemId: entry.value.id,
          target: position,
          problem: schedulingProblem,
        );
        if (!result.allowed || result.changedItemIds.isEmpty) continue;
        bestItems = result.items;
        bestChanged.addAll(result.changedItemIds);
        break;
      }
      if (!getBudgetAvailable()) break;
    }
    search(items, Map.fromEntries(ordered), <String>{}, 0);
    final repair = _UnplacedRepairSearch(
      snapshot,
      schedulingProblem,
      () => checks++ < 40000 && clock.elapsed < const Duration(seconds: 3),
      items,
    );
    // 逐步加深，优先尝试较短的腾挪链。
    for (var depth = 1; depth <= 3; depth++) {
      for (final entry in ordered) {
        final selected = bestItems.firstWhere(
          (item) => item.id == entry.value.id,
        );
        if (selected.isPlaced) continue;
        for (final proposal in repair.place(bestItems, selected, depth, {})) {
          final result = _result(bestItems, {
            for (final item in proposal) item.id: item,
          });
          if (_proposalBlockers(
            schedulingProblem,
            bestItems,
            result,
          ).isNotEmpty) {
            continue;
          }
          bestItems = result.items;
          break;
        }
      }
    }
    bestChanged = _result(items, {
      for (final item in bestItems) item.id: item,
    }).changedItemIds;
    final unplaced = <ScheduleUnplacedCourse>[];
    final bestById = {for (final item in bestItems) item.id: item};
    final diagnosticsClock = Stopwatch()..start();
    var diagnosticChecks = 0;
    bool canDiagnose() =>
        diagnosticChecks++ < 2000 &&
        diagnosticsClock.elapsed < const Duration(milliseconds: 250);
    for (final entry in ordered) {
      final selected = bestById[entry.value.id]!;
      if (selected.isPlaced) continue;
      final reasons = repair.diagnose(bestItems, selected, canDiagnose);
      for (final member in _groupFor(bestItems, selected)) {
        unplaced.add(
          ScheduleUnplacedCourse(itemId: member.id, blockers: reasons),
        );
      }
    }
    return ManualMoveResult(
      items: bestItems,
      blockers: const [],
      changedItemIds: bestChanged,
      unplaced: unplaced,
    );
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

    final blockers = _proposalBlockers(schedulingProblem, items, proposal);
    if (blockers.isNotEmpty) {
      return ManualMoveResult(
        items: items,
        blockers: blockers,
        changedItemIds: const {},
      );
    }
    return proposal;
  }
}

/// 只验证最终结果，腾挪中间暂时移出的课组不参与最低节数检查。
List<ScheduleBlocker> _proposalBlockers(
  SchedulingProblem schedulingProblem,
  List<ScheduleItem> items,
  ManualMoveResult proposal,
) {
  const evaluator = ConstraintEvaluator();
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
  return _uniqueBlockers(blockers);
}

/// 带预算的局部腾挪；每个分支必须把被挤出的完整课组全部放回。
class _UnplacedRepairSearch {
  _UnplacedRepairSearch(
    this.snapshot,
    this.problem,
    this.hasBudget,
    List<ScheduleItem> items,
  ) : lockedItemIds = _lockedMembers(
        snapshot,
        items,
      ).map((item) => item.id).toSet();

  final SchedulingSnapshot snapshot;
  final SchedulingProblem problem;
  final bool Function() hasBudget;
  final Set<String> lockedItemIds;

  SchedulePlacementCandidate? _candidate(
    List<ScheduleItem> moving,
    SchedulePosition anchor,
  ) {
    final destinations = <String, SchedulePosition>{};
    for (final member in moving) {
      final position = _resolvePosition(
        snapshot: snapshot,
        problem: problem,
        classId: member.classId,
        anchor: anchor,
      );
      if (position == null) return null;
      destinations[member.id] = position;
    }
    return SchedulePlacementCandidate(
      unit: ScheduleUnit(_groupKey(moving.first), moving),
      positions: destinations,
    );
  }

  List<ScheduleBlocker> diagnose(
    List<ScheduleItem> items,
    ScheduleItem selected,
    bool Function() canDiagnose,
  ) {
    const fallback = ScheduleBlocker(
      code: 'searchLimit',
      message: '本次有限搜索未找到可行方案，请检查作息、锁定及排课规则。',
    );
    if (!canDiagnose()) return const [fallback];
    final moving = _groupFor(items, selected);
    if (moving.any((item) => lockedItemIds.contains(item.id))) {
      return const [
        ScheduleBlocker(code: 'locked', message: '待放入课组的班级或教师已锁定，请先解锁。'),
      ];
    }
    final movingIds = moving.map((item) => item.id).toSet();
    final others = items.where((item) => !movingIds.contains(item.id)).toList();
    final reasons = <String, ScheduleBlocker>{};
    for (final anchor
        in problem.positionsByClass[selected.classId] ??
            const <SchedulePosition>[]) {
      if (!canDiagnose()) {
        reasons['searchLimit'] = fallback;
        break;
      }
      final candidate = _candidate(moving, anchor);
      if (candidate == null) continue;
      final blockers = const ConstraintEvaluator().evaluatePlacement(
        problem,
        others,
        candidate,
      );
      for (final blocker in blockers) {
        if (blocker.relatedIds.any(lockedItemIds.contains)) {
          reasons['locked'] = const ScheduleBlocker(
            code: 'locked',
            message: '可用位置涉及已锁定的班级或教师课程，无法自动腾挪，请先解锁。',
          );
        }
        reasons.putIfAbsent(
          '${blocker.code}:${blocker.conditionId}:${blocker.message}',
          () => blocker,
        );
      }
    }
    return reasons.isEmpty ? const [fallback] : reasons.values.toList();
  }

  Iterable<List<ScheduleItem>> place(
    List<ScheduleItem> items,
    ScheduleItem selected,
    int depth,
    Set<String> protected,
  ) sync* {
    if (!hasBudget()) return;
    final moving = _groupFor(items, selected);
    if (moving.any((item) => lockedItemIds.contains(item.id))) return;
    final movingIds = moving.map((item) => item.id).toSet();
    final byId = {for (final item in items) item.id: item};
    final candidates =
        <
          ({
            Map<String, ScheduleItem> replacements,
            List<ScheduleItem> displaced,
          })
        >[];
    const evaluator = ConstraintEvaluator();
    for (final anchor
        in problem.positionsByClass[selected.classId] ??
            const <SchedulePosition>[]) {
      if (!hasBudget()) break;
      final candidate = _candidate(moving, anchor);
      if (candidate == null) continue;
      final others = items
          .where((item) => !movingIds.contains(item.id))
          .toList();
      final blockers = evaluator.evaluatePlacement(problem, others, candidate);
      // 只有明确关联到其他课节的冲突才可通过腾挪解决。
      if (blockers.any(
        (blocker) =>
            blocker.relatedIds.isEmpty ||
            blocker.relatedIds.any((id) => !byId.containsKey(id)),
      )) {
        continue;
      }
      final displaced = <String, ScheduleItem>{};
      for (final blocker in blockers) {
        for (final id in blocker.relatedIds) {
          final other = byId[id]!;
          displaced[_groupKey(other)] = other;
        }
      }
      if (displaced.isNotEmpty && depth == 0) continue;
      if (displaced.keys.any(
        (key) => protected.contains(key) || key == _groupKey(selected),
      )) {
        continue;
      }
      final displacedMembers = [
        for (final other in displaced.values) ..._groupFor(items, other),
      ];
      if (displacedMembers.any((item) => lockedItemIds.contains(item.id))) {
        continue;
      }
      final displacedIds = displacedMembers.map((item) => item.id).toSet();
      final cleared = others
          .where((item) => !displacedIds.contains(item.id))
          .toList();
      if (evaluator.evaluatePlacement(problem, cleared, candidate).isNotEmpty) {
        continue;
      }
      candidates.add((
        replacements: {
          for (final member in displacedMembers) member.id: member.at(null),
          for (final member in candidate.placedItems) member.id: member,
        },
        displaced: displaced.values.toList(),
      ));
    }
    candidates.sort((a, b) => a.displaced.length.compareTo(b.displaced.length));
    for (final candidate in candidates) {
      if (!hasBudget()) return;
      final proposal = [
        for (final item in items) candidate.replacements[item.id] ?? item,
      ];
      yield* _restore(proposal, candidate.displaced, depth - 1, {
        ...protected,
        _groupKey(selected),
      });
    }
  }

  Iterable<List<ScheduleItem>> _restore(
    List<ScheduleItem> items,
    List<ScheduleItem> displaced,
    int depth,
    Set<String> protected,
  ) sync* {
    if (displaced.isEmpty) {
      yield items;
      return;
    }
    if (!hasBudget()) return;
    final selected = items.firstWhere((item) => item.id == displaced.first.id);
    for (final proposal in place(items, selected, depth, protected)) {
      yield* _restore(proposal, displaced.sublist(1), depth, {
        ...protected,
        _groupKey(selected),
      });
    }
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
