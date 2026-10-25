import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/constraint_evaluator.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

/// 一次确定性搜索的进度快照。
class ScheduleProgress {
  const ScheduleProgress({
    required this.candidateChecks,
    required this.budget,
    required this.bestCoverage,
    required this.completedUnits,
    required this.totalUnits,
  });

  final int candidateChecks;
  final int budget;
  final int bestCoverage;
  final int completedUnits;
  final int totalUnits;

  double get fraction => budget == 0 ? 1 : candidateChecks / budget;
}

/// 取消后不携带任何可提交课表的求解异常。
class ScheduleCancelled implements Exception {
  const ScheduleCancelled();
}

/// 前置检查未通过时的求解异常。
class SchedulePreflightException implements Exception {
  const SchedulePreflightException(this.checks);

  final List<SchedulePreflightCheck> checks;
}

/// 按固定候选预算搜索，并以覆盖量和四类等权满足率选出结果。
class CourseScheduler {
  const CourseScheduler({this.evaluator = const ConstraintEvaluator()});

  final ConstraintEvaluator evaluator;

  ScheduleRun solve(
    SchedulingProblem problem, {
    required ScheduleRunConfig config,
    void Function(ScheduleProgress)? onProgress,
    bool Function()? isCancelled,
  }) {
    if (!problem.isReady) throw SchedulePreflightException(problem.checks);
    if (!problem.selectedClassIds.containsAll(config.selectedClassIds) ||
        !config.selectedClassIds.containsAll(problem.selectedClassIds)) {
      throw ArgumentError('求解范围与前置检查范围不一致');
    }
    final budget = switch (config.strength) {
      ScheduleStrength.fast => 100000,
      ScheduleStrength.normal => 300000,
      ScheduleStrength.high => 1000000,
    };
    const checksPerAttempt = 100000;
    final attemptLimit = switch (config.strength) {
      ScheduleStrength.fast => 1,
      ScheduleStrength.normal => 3,
      ScheduleStrength.high => 10,
    };
    final units = [...problem.units];
    final candidates = <String, List<SchedulePlacementCandidate>>{};
    final unitByItemId = <String, ScheduleUnit>{};
    for (final unit in units) {
      candidates[unit.id] = _candidates(problem, unit);
      for (final item in unit.items) {
        unitByItemId[item.id] = unit;
      }
    }
    units.sort((a, b) {
      final count = (candidates[a.id]?.length ?? 0).compareTo(
        candidates[b.id]?.length ?? 0,
      );
      if (count != 0) return count;
      final weight = b.coverage.compareTo(a.coverage);
      return weight != 0 ? weight : a.id.compareTo(b.id);
    });
    final fixed = problem.fixedItems
        .where((item) => item.position != null)
        .toList();
    final fixedUnplaced = problem.fixedItems
        .where((item) => item.position == null)
        .toList();
    final seed = config.seed & 0x7fffffff;
    var checks = 0;
    _Attempt? best;
    var attempt = 0;
    while (checks < budget && attempt < attemptLimit) {
      if (isCancelled?.call() == true) throw const ScheduleCancelled();
      final placed = <ScheduleItem>[...fixed];
      final unplaced = <ScheduleItem>[...fixedUnplaced];
      var completed = 0;
      var checksAtStart = checks;
      for (final unit in units) {
        if (isCancelled?.call() == true) throw const ScheduleCancelled();
        final positions = candidates[unit.id] ?? const [];
        if (positions.isEmpty) {
          unplaced.addAll(unit.items);
          completed++;
          continue;
        }
        final offset = attempt == 0
            ? 0
            : _mix(seed, _stableHash(unit.id), attempt) % positions.length;
        SchedulePlacementCandidate? chosen;
        for (
          var n = 0;
          n < positions.length &&
              checks < budget &&
              checks - checksAtStart < checksPerAttempt;
          n++
        ) {
          final candidate = positions[(offset + n) % positions.length];
          checks++;
          if (evaluator.evaluatePlacement(problem, placed, candidate).isEmpty) {
            chosen = candidate;
            break;
          }
        }
        if (chosen == null) {
          unplaced.addAll(unit.items);
        } else {
          placed.addAll(chosen.placedItems);
        }
        completed++;
        if (checks % 512 == 0) {
          onProgress?.call(
            ScheduleProgress(
              candidateChecks: checks,
              budget: budget,
              bestCoverage: best?.coverage ?? 0,
              completedUnits: completed,
              totalUnits: units.length,
            ),
          );
        }
      }
      final waitingIds = unplaced.map((item) => item.id).toSet();
      for (final unit in units) {
        if (checks >= budget || checks - checksAtStart >= checksPerAttempt) {
          break;
        }
        final unitIds = unit.items.map((item) => item.id).toSet();
        if (!unitIds.every(waitingIds.contains)) {
          continue;
        }
        for (final candidate in candidates[unit.id] ?? const []) {
          if (checks >= budget || checks - checksAtStart >= checksPerAttempt) {
            break;
          }
          checks++;
          final blockers = evaluator.evaluatePlacement(
            problem,
            placed,
            candidate,
          );
          if (blockers.isEmpty) {
            placed.addAll(candidate.placedItems);
            unplaced.removeWhere((item) => unitIds.contains(item.id));
            waitingIds.removeAll(unitIds);
            break;
          }
          if (blockers.any(
            (blocker) =>
                blocker.code != 'classOccupied' &&
                blocker.code != 'teacherOccupied',
          )) {
            continue;
          }
          final displacedUnits = blockers
              .expand((blocker) => blocker.relatedIds)
              .map((id) => unitByItemId[id])
              .toSet();
          if (displacedUnits.length != 1 || displacedUnits.single == null) {
            continue;
          }
          final displaced = displacedUnits.single!;
          final displacedIds = displaced.items.map((item) => item.id).toSet();
          final reduced = placed
              .where((item) => !displacedIds.contains(item.id))
              .toList();
          if (checks >= budget || checks - checksAtStart >= checksPerAttempt) {
            break;
          }
          checks++;
          if (evaluator
              .evaluatePlacement(problem, reduced, candidate)
              .isNotEmpty) {
            continue;
          }
          SchedulePlacementCandidate? replacement;
          for (final option in candidates[displaced.id] ?? const []) {
            if (checks >= budget ||
                checks - checksAtStart >= checksPerAttempt) {
              break;
            }
            checks++;
            if (evaluator.evaluatePlacement(problem, [
              ...reduced,
              ...candidate.placedItems,
            ], option).isEmpty) {
              replacement = option;
              break;
            }
          }
          if (replacement == null) continue;
          placed
            ..removeWhere((item) => displacedIds.contains(item.id))
            ..addAll(candidate.placedItems)
            ..addAll(replacement.placedItems);
          unplaced.removeWhere((item) => unitIds.contains(item.id));
          waitingIds.removeAll(unitIds);
          break;
        }
      }
      final score = _score(problem.snapshot, placed);
      final result = _Attempt(
        placed,
        unplaced,
        score,
        evaluator
            .unmetHardRequirements(
              problem,
              [...placed, ...unplaced]
                  .where(
                    (item) => problem.selectedClassIds.contains(item.classId),
                  )
                  .toList(),
            )
            .where(_isPlacedScheduleViolation)
            .length,
      );
      if (best == null || result.compareTo(best) > 0) best = result;
      onProgress?.call(
        ScheduleProgress(
          candidateChecks: checks,
          budget: budget,
          bestCoverage: best.coverage,
          completedUnits: completed,
          totalUnits: units.length,
        ),
      );
      attempt++;
      if (checks == checksAtStart ||
          (best.unplaced
                  .where(
                    (item) => problem.selectedClassIds.contains(item.classId),
                  )
                  .isEmpty &&
              attempt >= 2) ||
          (attempt > 1 && checks < budget && units.isEmpty)) {
        break;
      }
    }
    final result =
        best ??
        _Attempt(
          fixed,
          fixedUnplaced,
          _score(problem.snapshot, fixed),
          evaluator
              .unmetHardRequirements(
                problem,
                [...fixed, ...fixedUnplaced]
                    .where(
                      (item) => problem.selectedClassIds.contains(item.classId),
                    )
                    .toList(),
              )
              .where(_isPlacedScheduleViolation)
              .length,
        );
    final all = [...result.placed, ...result.unplaced]
      ..sort((a, b) => a.id.compareTo(b.id));
    final unplacedReport = <ScheduleUnplacedCourse>[];
    for (final item in result.unplaced.where(
      (item) => problem.selectedClassIds.contains(item.classId),
    )) {
      final unit = units.where((row) => row.items.any((e) => e.id == item.id));
      final blockers = <ScheduleBlocker>[];
      if (unit.isNotEmpty) {
        for (final candidate in candidates[unit.first.id] ?? const []) {
          blockers.addAll(
            evaluator.evaluatePlacement(problem, result.placed, candidate),
          );
          if (blockers.length >= 12) break;
        }
      }
      final unique = <String, ScheduleBlocker>{};
      for (final blocker in blockers) {
        unique.putIfAbsent(
          '${blocker.code}:${blocker.conditionId}:${blocker.position?.cellKey}',
          () => blocker,
        );
      }
      if (unique.isEmpty) {
        unique['budget'] = const ScheduleBlocker(
          code: 'budget',
          message: '在本次搜索预算内未找到可行位置',
        );
      }
      unplacedReport.add(
        ScheduleUnplacedCourse(
          itemId: item.id,
          blockers: unique.values.toList(),
        ),
      );
    }
    unplacedReport.sort((a, b) => a.itemId.compareTo(b.itemId));
    final selectedItems = all
        .where((item) => problem.selectedClassIds.contains(item.classId))
        .toList();
    final selectedPlaced = selectedItems
        .where((item) => item.position != null)
        .toList();
    final report = ScheduleReport(
      totalItems: selectedItems.length,
      placedItems: selectedPlaced.length,
      coverage: selectedPlaced.fold(
        0,
        (sum, item) => sum + item.occurrenceCount,
      ),
      preferenceScores: result.scores,
      unplaced: unplacedReport,
      unmetHardRequirements: evaluator.unmetHardRequirements(
        problem,
        selectedItems,
      ),
      candidateChecks: checks,
    );
    return ScheduleRun(
      id: '${problem.snapshot.term.id}:${config.seed}:${config.strength.name}:${problem.snapshot.inputFingerprint}',
      termId: problem.snapshot.term.id,
      inputFingerprint: problem.snapshot.inputFingerprint,
      config: config,
      report: report,
      items: all,
    );
  }
}

bool _isPlacedScheduleViolation(ScheduleBlocker blocker) =>
    blocker.code == 'mustPreset' ||
    blocker.code == 'teacherMustPreset' ||
    blocker.code == 'progressConsistency';

List<SchedulePlacementCandidate> _candidates(
  SchedulingProblem problem,
  ScheduleUnit unit,
) {
  if (unit.items.isEmpty) return const [];
  final first = unit.items.first;
  final firstPositions = problem.positionsByClass[first.classId] ?? const [];
  final result = <SchedulePlacementCandidate>[];
  for (final position in firstPositions) {
    final mapped = <String, SchedulePosition>{first.id: position};
    var fits = true;
    for (final item in unit.items.skip(1)) {
      final choices = problem.positionsByClass[item.classId] ?? const [];
      final matches = choices.where(
        (candidate) => position.stageId == candidate.stageId
            ? position.sameCell(candidate)
            : position.hasSameClock(candidate),
      );
      if (matches.isEmpty) {
        fits = false;
        break;
      }
      mapped[item.id] = matches.first;
    }
    if (fits) {
      result.add(SchedulePlacementCandidate(unit: unit, positions: mapped));
    }
  }
  return result;
}

int _mix(int seed, int id, int attempt) {
  var x = seed ^ id ^ (attempt * 0x9e3779b9);
  x ^= x >> 16;
  x = (x * 0x7feb352d) & 0x7fffffff;
  x ^= x >> 15;
  return x & 0x7fffffff;
}

int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

class _Attempt {
  const _Attempt(this.placed, this.unplaced, this.scores, this.hardFailures);

  final List<ScheduleItem> placed;
  final List<ScheduleItem> unplaced;
  final Map<String, SchedulePreferenceScore> scores;
  final int hardFailures;

  int get coverage => placed.fold(0, (sum, item) => sum + item.occurrenceCount);

  int compareTo(_Attempt other) {
    final valid = other.hardFailures.compareTo(hardFailures);
    if (valid != 0) return valid;
    final covered = coverage.compareTo(other.coverage);
    if (covered != 0) return covered;
    final preferred = _compareRateSums(scores, other.scores);
    if (preferred != 0) return preferred;
    final left = _canonical(placed);
    final right = _canonical(other.placed);
    return -left.compareTo(right);
  }
}

int _compareRateSums(
  Map<String, SchedulePreferenceScore> left,
  Map<String, SchedulePreferenceScore> right,
) {
  (BigInt, BigInt) fraction(Map<String, SchedulePreferenceScore> scores) {
    var numerator = BigInt.zero;
    var denominator = BigInt.one;
    for (final score in scores.values) {
      if (score.applicable <= 0) continue;
      final nextDenominator = BigInt.from(score.applicable);
      numerator =
          numerator * nextDenominator +
          BigInt.from(score.satisfied) * denominator;
      denominator *= nextDenominator;
    }
    return (numerator, denominator);
  }

  final a = fraction(left);
  final b = fraction(right);
  return (a.$1 * b.$2).compareTo(b.$1 * a.$2);
}

String _canonical(List<ScheduleItem> items) {
  final rows = [...items]..sort((a, b) => a.id.compareTo(b.id));
  return rows
      .map((item) {
        final p = item.position;
        return '${item.id}:${item.weekMode.name}:${p?.stageId ?? ''}:${p?.weekday ?? 0}:${p?.periodTypeId ?? ''}:${p?.lessonIndex ?? 0}';
      })
      .join('|');
}

Map<String, SchedulePreferenceScore> _score(
  SchedulingSnapshot snapshot,
  List<ScheduleItem> placed,
) {
  var preferApplicable = 0;
  var preferSatisfied = 0;
  final presetsBySubjectStage = <String, List<SubjectPreset>>{};
  for (final preset in snapshot.subjectPresets) {
    presetsBySubjectStage
        .putIfAbsent('${preset.subjectId}:${preset.stageId}', () => [])
        .add(preset);
  }
  for (final item in placed) {
    final p = item.position;
    if (p == null) continue;
    final relevant =
        presetsBySubjectStage['${item.subjectId}:${p.stageId}'] ?? const [];
    final cells = relevant
        .map(
          (preset) => (preset.weekday, preset.periodTypeId, preset.lessonIndex),
        )
        .toSet();
    final hasEffectivePrefer = cells.any((cell) {
      return _effectiveSubjectPreset(
            snapshot,
            item,
            relevant,
            weekday: cell.$1,
            periodTypeId: cell.$2,
            lessonIndex: cell.$3,
          ) ==
          PresetValue.prefer;
    });
    if (!hasEffectivePrefer) continue;
    preferApplicable += item.occurrenceCount;
    if (_effectiveSubjectPreset(
          snapshot,
          item,
          relevant,
          weekday: p.weekday,
          periodTypeId: p.periodTypeId,
          lessonIndex: p.lessonIndex,
        ) ==
        PresetValue.prefer) {
      preferSatisfied += item.occurrenceCount;
    }
  }

  var progressApplicable = 0;
  var progressSatisfied = 0;
  final gradeSubject = <String, List<ScheduleItem>>{};
  for (final item in placed) {
    final grade = snapshot.gradeIdForClass(item.classId);
    if (grade != null) {
      gradeSubject.putIfAbsent('$grade:${item.subjectId}', () => []).add(item);
    }
  }
  for (final group
      in snapshot.preferences.checkProgressConsistency
          ? gradeSubject.values
          : const <List<ScheduleItem>>[]) {
    final sample = group.first;
    final gradeId = snapshot.gradeIdForClass(sample.classId);
    final stageId = snapshot.stageIdForClass(sample.classId);
    if (gradeId == null || stageId == null) continue;
    final routine = snapshot.routines.where((row) => row.stageId == stageId);
    if (routine.isEmpty) continue;
    final days = routine.first.teachingWeekdays.toList()..sort();
    for (final oddWeek in [true, false]) {
      final byClass = <String, List<ScheduleItem>>{};
      for (final item in group.where(
        (row) => occursInWeek(row.weekMode, oddWeek: oddWeek),
      )) {
        byClass.putIfAbsent(item.classId, () => []).add(item);
      }
      final expected = <String, int>{};
      for (final assignment in snapshot.assignments) {
        if (assignment.subjectId != sample.subjectId ||
            snapshot.gradeIdForClass(assignment.classId) != gradeId ||
            !occursInWeek(assignment.weekMode, oddWeek: oddWeek)) {
          continue;
        }
        expected.update(
          assignment.classId,
          (count) => count + assignment.lessonCount,
          ifAbsent: () => assignment.lessonCount,
        );
      }
      final byDemand = <int, List<List<ScheduleItem>>>{};
      for (final entry in expected.entries.where((entry) => entry.value > 0)) {
        byDemand
            .putIfAbsent(entry.value, () => [])
            .add(byClass[entry.key] ?? const []);
      }
      for (final sameDemand in byDemand.values.where(
        (rows) => rows.length > 1,
      )) {
        for (final day in days) {
          final totals = [
            for (final rows in sameDemand)
              rows.where((item) => item.position!.weekday <= day).length,
          ];
          progressApplicable++;
          final low = totals.reduce((a, b) => a < b ? a : b);
          final high = totals.reduce((a, b) => a > b ? a : b);
          if (high - low <= 1) progressSatisfied++;
        }
      }
    }
  }

  var distributionApplicable = 0;
  var distributionSatisfied = 0;
  if (snapshot.preferences.teacherDistribution !=
      TeacherDistribution.indifferent) {
    final groups = <String, List<ScheduleItem>>{};
    for (final item in placed) {
      for (final oddWeek in [true, false]) {
        if (occursInWeek(item.weekMode, oddWeek: oddWeek)) {
          groups
              .putIfAbsent(
                '${item.teacherId}:${item.position!.weekday}:$oddWeek',
                () => [],
              )
              .add(item);
        }
      }
    }
    for (final rows in groups.values.where((rows) => rows.length >= 2)) {
      final periods = rows.map((item) => item.position!.periodTypeId).toSet();
      final morningIds = <String>{};
      final afternoonIds = <String>{};
      for (final routine in snapshot.routines) {
        for (final period in routine.periodTypes) {
          if (period.name.contains('上午')) morningIds.add(period.id);
          if (period.name.contains('下午')) afternoonIds.add(period.id);
        }
      }
      if (morningIds.isEmpty || afternoonIds.isEmpty) continue;
      distributionApplicable++;
      final hasMorning = periods.any(morningIds.contains);
      final hasAfternoon = periods.any(afternoonIds.contains);
      if (snapshot.preferences.teacherDistribution == TeacherDistribution.spread
          ? hasMorning && hasAfternoon
          : hasMorning != hasAfternoon) {
        distributionSatisfied++;
      }
    }
  }

  var consecutiveApplicable = 0;
  var consecutiveSatisfied = 0;
  if (snapshot.preferences.consecutiveMode != ConsecutiveMode.requireSeparate) {
    final groups = <String, List<ScheduleItem>>{};
    for (final item in placed) {
      for (final oddWeek in [true, false]) {
        if (occursInWeek(item.weekMode, oddWeek: oddWeek)) {
          groups
              .putIfAbsent(
                '${item.classId}:${item.subjectId}:${item.position!.weekday}:$oddWeek',
                () => [],
              )
              .add(item);
        }
      }
    }
    for (final rows in groups.values.where((rows) => rows.length >= 2)) {
      final item = rows.first;
      final hasForced = snapshot.requirements.any(
        (requirement) =>
            requirement.subjectId == item.subjectId &&
            requirement.gradeId == snapshot.gradeIdForClass(item.classId) &&
            (requirement.classId == null ||
                requirement.classId == item.classId) &&
            (snapshot.requiredConsecutivePairsByRequirement[requirement.id] ??
                    0) >
                0,
      );
      if (hasForced) continue;
      final indices = <int>[];
      final routine = snapshot.routines.where(
        (row) => row.stageId == item.position!.stageId,
      );
      if (routine.isEmpty) continue;
      final periods = [...routine.first.periodTypes]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (final row in rows) {
        var index = row.position!.lessonIndex;
        for (final period in periods) {
          if (period.id == row.position!.periodTypeId) break;
          index += routine.first.effectiveLessonCount(
            period.id,
            row.position!.weekday,
          );
        }
        indices.add(index);
      }
      indices.sort();
      consecutiveApplicable++;
      final noGap = indices.last - indices.first + 1 == indices.length;
      final noAdjacent = !List.generate(
        indices.length - 1,
        (i) => i,
      ).any((i) => indices[i + 1] == indices[i] + 1);
      if (snapshot.preferences.consecutiveMode == ConsecutiveMode.preferTogether
          ? noGap
          : noAdjacent) {
        consecutiveSatisfied++;
      }
    }
  }
  return {
    'prefer': SchedulePreferenceScore(
      satisfied: preferSatisfied,
      applicable: preferApplicable,
    ),
    'progress': SchedulePreferenceScore(
      satisfied: progressSatisfied,
      applicable: progressApplicable,
    ),
    'teacherDistribution': SchedulePreferenceScore(
      satisfied: distributionSatisfied,
      applicable: distributionApplicable,
    ),
    'consecutive': SchedulePreferenceScore(
      satisfied: consecutiveSatisfied,
      applicable: consecutiveApplicable,
    ),
  };
}

PresetValue _effectiveSubjectPreset(
  SchedulingSnapshot snapshot,
  ScheduleItem item,
  Iterable<SubjectPreset> relevant, {
  required int weekday,
  required String periodTypeId,
  required int lessonIndex,
}) {
  final stageId = snapshot.stageIdForClass(item.classId);
  if (stageId == null) return PresetValue.auto;
  final gradeId = snapshot.gradeIdForClass(item.classId);
  final rows = relevant.where(
    (row) =>
        row.weekday == weekday &&
        row.periodTypeId == periodTypeId &&
        row.lessonIndex == lessonIndex,
  );
  for (final scope in [
    (FreeSlotScope.schoolClass, item.classId),
    (FreeSlotScope.grade, gradeId),
    (FreeSlotScope.stage, stageId),
    (FreeSlotScope.school, snapshot.term.id),
  ]) {
    for (final row in rows) {
      if (row.scope == scope.$1 && row.scopeId == scope.$2) return row.value;
    }
  }
  return PresetValue.auto;
}
