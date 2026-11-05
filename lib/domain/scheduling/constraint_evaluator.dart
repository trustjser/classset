import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_lesson_constraint.dart';
import 'package:class_set/domain/models/subject_parallel_limit.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/teacher_preset.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

/// 一个求解单元在各参与班级的候选位置。
class SchedulePlacementCandidate {
  const SchedulePlacementCandidate({
    required this.unit,
    required this.positions,
  });

  final ScheduleUnit unit;
  final Map<String, SchedulePosition> positions;

  List<ScheduleItem> get placedItems => [
    for (final item in unit.items) item.at(positions[item.id]),
  ];
}

/// 检查候选课节是否遵守已排课程和全部可即时判定的硬性规则。
class ConstraintEvaluator {
  const ConstraintEvaluator();

  /// 返回调整后新增或进一步恶化的硬性下限缺口。
  List<ScheduleBlocker> newHardRequirementBlockers(
    SchedulingProblem problem,
    List<ScheduleItem> before,
    List<ScheduleItem> after,
  ) {
    final existing = {
      for (final blocker in unmetHardRequirements(problem, before))
        _blockerIdentity(blocker): blocker,
    };
    return unmetHardRequirements(problem, after).where((blocker) {
      final previous = existing[_blockerIdentity(blocker)];
      if (previous == null) return true;
      final beforeCount = _placedCount(previous);
      final afterCount = _placedCount(blocker);
      return beforeCount != null &&
          afterCount != null &&
          afterCount < beforeCount;
    }).toList();
  }

  List<ScheduleBlocker> evaluatePlacement(
    SchedulingProblem problem,
    List<ScheduleItem> placed,
    SchedulePlacementCandidate candidate,
  ) {
    final snapshot = problem.snapshot;
    final blockers = <ScheduleBlocker>[];
    final candidateItems = candidate.placedItems;
    final all = [...placed, ...candidateItems];
    final placedIds = candidateItems.map((item) => item.id).toSet();
    final otherItems = placed
        .where((item) => !placedIds.contains(item.id))
        .toList();
    void block(
      String code,
      String message,
      ScheduleItem item, {
      String? conditionId,
      List<String> relatedIds = const [],
    }) {
      blockers.add(
        ScheduleBlocker(
          code: code,
          message: message,
          conditionId: conditionId,
          position: item.position,
          relatedIds: relatedIds,
        ),
      );
    }

    for (final item in candidateItems) {
      final position = item.position;
      if (position == null ||
          !(problem.positionsByClass[item.classId] ?? const []).any(
            (allowed) => allowed.sameCell(position),
          )) {
        block('position', '班级 ${item.classId} 的候选节次不存在', item);
        continue;
      }
      if (_isFree(snapshot, item.classId, position)) {
        block('freeSlot', '免任课位置不能排正课', item);
      }
      final allowedTypes =
          snapshot.allowedPeriodTypeIdsBySubject[item.subjectId];
      if (allowedTypes != null &&
          allowedTypes.isNotEmpty &&
          !allowedTypes.contains(position.periodTypeId)) {
        block('periodType', '科目 ${item.subjectId} 不允许此时段类型', item);
      }
      final subjectPreset = _subjectPreset(snapshot, item, position);
      if (subjectPreset == PresetValue.forbid) {
        block('subjectPreset', '科目预设禁止此位置', item);
      }
      final teacherPreset = _teacherPreset(snapshot, item, position);
      if (teacherPreset == PresetValue.forbid) {
        block('teacherPreset', '教师预设禁止此位置', item);
      }
      if (subjectPreset == PresetValue.must &&
          teacherPreset == PresetValue.forbid) {
        block('presetConflict', '科目一定排与教师不排相冲突', item);
      }
      for (final other in [...otherItems, ...candidateItems]) {
        if (other.id == item.id ||
            other.position == null ||
            !weekModesOverlap(item.weekMode, other.weekMode)) {
          continue;
        }
        if (item.classId == other.classId &&
            position.sameCell(other.position!)) {
          block('classOccupied', '班级该周次已有课', item, relatedIds: [other.id]);
        }
        if (item.teacherId == other.teacherId &&
            !_sameMeeting(item, other) &&
            position.overlaps(other.position!)) {
          block('teacherOccupied', '教师该周次时间已有课', item, relatedIds: [other.id]);
        }
      }
      _checkConditions(snapshot, item, all, block);
      _checkLessonLimits(snapshot, item, all, block);
      _checkParallelAndRooms(snapshot, item, all, block);
      _checkHardGlobals(snapshot, item, all, block);
    }

    if (candidateItems.length > 1) {
      for (var index = 0; index < candidateItems.length; index++) {
        final first = candidateItems[index];
        for (final item in candidateItems.skip(index + 1)) {
          if (first.position == null || item.position == null) continue;
          final same = first.position!.stageId == item.position!.stageId
              ? first.position!.sameCell(item.position!)
              : first.position!.hasSameClock(item.position!);
          if (first.combinedGroupId != null &&
              first.combinedGroupId == item.combinedGroupId) {
            if (!same || first.weekMode != item.weekMode) {
              block('combined', '合班课必须同周次且节次时间完全一致', item);
            }
          } else if (first.meetingId != null &&
              first.meetingId == item.meetingId &&
              !same) {
            block('pairing', '单双周配对必须共用同一节次', item);
          }
        }
      }
    }
    final unique = <String, ScheduleBlocker>{};
    for (final blocker in blockers) {
      final key =
          '${blocker.code}:${blocker.conditionId}:${blocker.position?.cellKey}:${blocker.relatedIds.join(',')}';
      unique.putIfAbsent(key, () => blocker);
    }
    return unique.values.toList();
  }

  List<ScheduleBlocker> unmetHardRequirements(
    SchedulingProblem problem,
    List<ScheduleItem> items,
  ) {
    final snapshot = problem.snapshot;
    final hasConditionMinimum = snapshot.conditions.any(
      (condition) =>
          (condition.type == ScheduleConditionType.periodLimit ||
              condition.type == ScheduleConditionType.dailyLimit) &&
          (condition.exact != null || condition.minimum != null),
    );
    final hasLessonMinimum = snapshot.lessonConstraints.any(
      (rule) =>
          rule.minimumDailyLessons != null ||
          rule.minimumDailyConsecutivePairs != null ||
          rule.minimumWeeklyConsecutivePairs != null,
    );
    final hasMustPreset =
        snapshot.subjectPresets.any(
          (preset) => preset.value == PresetValue.must,
        ) ||
        snapshot.teacherPresets.any(
          (preset) => preset.value == PresetValue.must,
        ) ||
        snapshot.teacherGroupPresets.any(
          (preset) => preset.value == PresetValue.must,
        );
    final hasRequiredProgress =
        snapshot.preferences.checkProgressConsistency &&
        snapshot.preferences.progressConsistency == ProgressConsistency.require;
    if (!hasConditionMinimum &&
        !hasLessonMinimum &&
        !hasMustPreset &&
        !hasRequiredProgress) {
      return const [];
    }
    final unmet = <ScheduleBlocker>[];
    final byClassSubject = <String, List<ScheduleItem>>{};
    for (final item in items) {
      byClassSubject
          .putIfAbsent('${item.classId}:${item.subjectId}', () => [])
          .add(item);
    }
    for (final condition in snapshot.conditions) {
      if (condition.type != ScheduleConditionType.periodLimit &&
          condition.type != ScheduleConditionType.dailyLimit) {
        continue;
      }
      final minimum = condition.exact ?? condition.minimum;
      if (minimum == null) continue;
      final targets = items.where(
        (item) => _conditionTargetMatches(condition, item),
      );
      final classScopes =
          condition.targetType == ScheduleConditionTarget.subject
          ? targets.map((item) => item.classId).toSet()
          : <String>{''};
      final weekdays =
          condition.weekday == null &&
              condition.type == ScheduleConditionType.dailyLimit
          ? snapshot.routines
                .expand((routine) => routine.teachingWeekdays)
                .toSet()
                .cast<int?>()
          : <int?>{condition.weekday};
      for (final classId in classScopes) {
        for (final weekday in weekdays) {
          for (final oddWeek in [true, false]) {
            if (!targets.any(
              (item) =>
                  (classId.isEmpty || item.classId == classId) &&
                  occursInWeek(item.weekMode, oddWeek: oddWeek),
            )) {
              continue;
            }
            final count = targets.where((item) {
              final position = item.position;
              return position != null &&
                  (classId.isEmpty || item.classId == classId) &&
                  (condition.type != ScheduleConditionType.periodLimit ||
                      position.periodTypeId == condition.periodTypeId) &&
                  (weekday == null || position.weekday == weekday) &&
                  occursInWeek(item.weekMode, oddWeek: oddWeek);
            }).length;
            if (count < minimum) {
              final scope = classId.isEmpty ? '' : '班级 $classId ';
              final day = weekday == null ? '' : '星期$weekday ';
              unmet.add(
                ScheduleBlocker(
                  code: 'minimum',
                  message:
                      '${condition.name ?? condition.id} $scope$day${oddWeek ? '单' : '双'}周至少 $minimum 节，已排 $count 节',
                  conditionId: condition.id,
                ),
              );
            }
          }
        }
      }
    }
    for (final preset in snapshot.subjectPresets.where(
      (preset) => preset.value == PresetValue.must,
    )) {
      final relevantClasses = snapshot.classes.where((schoolClass) {
        final stageId = snapshot.stageIdForClass(schoolClass.id);
        final gradeId = schoolClass.gradeId;
        return stageId == preset.stageId &&
            (preset.scope == FreeSlotScope.school ||
                (preset.scope == FreeSlotScope.stage &&
                    preset.scopeId == stageId) ||
                (preset.scope == FreeSlotScope.grade &&
                    preset.scopeId == gradeId) ||
                (preset.scope == FreeSlotScope.schoolClass &&
                    preset.scopeId == schoolClass.id));
      });
      for (final schoolClass in relevantClasses) {
        final subjectItems =
            byClassSubject['${schoolClass.id}:${preset.subjectId}'];
        if (subjectItems == null) continue;
        final requiredPosition = SchedulePosition(
          stageId: preset.stageId,
          weekday: preset.weekday,
          periodTypeId: preset.periodTypeId,
          lessonIndex: preset.lessonIndex,
        );
        final effectiveItems = subjectItems.where(
          (item) =>
              _subjectPreset(snapshot, item, requiredPosition) ==
              PresetValue.must,
        );
        if (effectiveItems.isEmpty) continue;
        for (final oddWeek in [true, false]) {
          if (!effectiveItems.any(
            (item) => occursInWeek(item.weekMode, oddWeek: oddWeek),
          )) {
            continue;
          }
          final exists = effectiveItems.any(
            (item) =>
                item.position?.sameCell(requiredPosition) == true &&
                occursInWeek(item.weekMode, oddWeek: oddWeek),
          );
          if (!exists) {
            unmet.add(
              ScheduleBlocker(
                code: 'mustPreset',
                message:
                    '班级 ${schoolClass.id} 科目 ${preset.subjectId} 的一定排位置未满足（${oddWeek ? '单' : '双'}周）',
                relatedIds: [schoolClass.id, preset.id],
              ),
            );
          }
        }
      }
    }
    final byTeacher = <String, List<ScheduleItem>>{};
    for (final item in items) {
      byTeacher.putIfAbsent(item.teacherId, () => []).add(item);
    }
    final teacherMusts =
        <
          ({
            String teacherId,
            String presetId,
            TeacherPresetScope scope,
            String scopeId,
            SchedulePosition position,
          })
        >[];
    for (final preset in snapshot.teacherPresets.where(
      (row) => row.value == PresetValue.must,
    )) {
      teacherMusts.add((
        teacherId: preset.teacherId,
        presetId: preset.id,
        scope: preset.scope,
        scopeId: preset.scopeId,
        position: SchedulePosition(
          stageId: preset.stageId,
          weekday: preset.weekday,
          periodTypeId: preset.periodTypeId,
          lessonIndex: preset.lessonIndex,
        ),
      ));
    }
    for (final preset in snapshot.teacherGroupPresets.where(
      (row) => row.value == PresetValue.must,
    )) {
      for (final member in snapshot.teacherGroupMembers.where(
        (row) => row.groupId == preset.groupId,
      )) {
        teacherMusts.add((
          teacherId: member.teacherId,
          presetId: preset.id,
          scope: preset.scope,
          scopeId: preset.scopeId,
          position: SchedulePosition(
            stageId: preset.stageId,
            weekday: preset.weekday,
            periodTypeId: preset.periodTypeId,
            lessonIndex: preset.lessonIndex,
          ),
        ));
      }
    }
    for (final must in teacherMusts) {
      final relevant = (byTeacher[must.teacherId] ?? const <ScheduleItem>[])
          .where(
            (item) =>
                snapshot.stageIdForClass(item.classId) ==
                    must.position.stageId &&
                _teacherPresetScopeMatches(
                  snapshot,
                  must.scope,
                  must.scopeId,
                  item.classId,
                ) &&
                _teacherPreset(snapshot, item, must.position) ==
                    PresetValue.must,
          )
          .toList();
      if (relevant.isEmpty) continue;
      for (final oddWeek in [true, false]) {
        if (!relevant.any(
          (item) => occursInWeek(item.weekMode, oddWeek: oddWeek),
        )) {
          continue;
        }
        final exists = relevant.any(
          (item) =>
              occursInWeek(item.weekMode, oddWeek: oddWeek) &&
              item.position?.sameCell(must.position) == true,
        );
        if (!exists) {
          unmet.add(
            ScheduleBlocker(
              code: 'teacherMustPreset',
              message:
                  '教师 ${must.teacherId} 的一定排位置未满足（${oddWeek ? '单' : '双'}周）',
              relatedIds: [must.teacherId, must.presetId],
              position: must.position,
            ),
          );
        }
      }
    }
    for (final subjectItems in byClassSubject.values) {
      final sample = subjectItems.first;
      final stageId = snapshot.stageIdForClass(sample.classId);
      final gradeId = snapshot.gradeIdForClass(sample.classId);
      if (stageId == null) continue;
      final routine = snapshot.routines.where((row) => row.stageId == stageId);
      if (routine.isEmpty) continue;
      for (final oddWeek in [true, false]) {
        final weeklyRows = subjectItems.where(
          (row) =>
              row.position != null &&
              occursInWeek(row.weekMode, oddWeek: oddWeek),
        );
        var weeklyPairs = 0;
        for (final day in routine.first.teachingWeekdays) {
          final limits = resolveSubjectLessonConstraints(
            constraints: snapshot.lessonConstraints.where(
              (row) => row.subjectId == sample.subjectId,
            ),
            scope: FreeSlotScope.schoolClass,
            scopeId: sample.classId,
            stageId: stageId,
            weekday: day,
            parentGradeId: gradeId,
          );
          final dayRows = weeklyRows
              .where((row) => row.position!.weekday == day)
              .toList();
          final pairs = _consecutivePairCount(snapshot, dayRows);
          weeklyPairs += pairs;
          if (limits.minimumDailyLessons != null &&
              dayRows.length < limits.minimumDailyLessons!) {
            unmet.add(
              ScheduleBlocker(
                code: 'dailyMinimum',
                message:
                    '班级 ${sample.classId} 科目 ${sample.subjectId} ${oddWeek ? '单' : '双'}周星期$day 的日课节下限未满足',
              ),
            );
          }
          if (limits.minimumDailyConsecutivePairs != null &&
              pairs < limits.minimumDailyConsecutivePairs!) {
            unmet.add(
              ScheduleBlocker(
                code: 'dailyConsecutiveMinimum',
                message:
                    '班级 ${sample.classId} 科目 ${sample.subjectId} ${oddWeek ? '单' : '双'}周星期$day 的连堂下限未满足',
              ),
            );
          }
        }
        final weeklyLimits = resolveSubjectLessonConstraints(
          constraints: snapshot.lessonConstraints.where(
            (row) => row.subjectId == sample.subjectId,
          ),
          scope: FreeSlotScope.schoolClass,
          scopeId: sample.classId,
          stageId: stageId,
          weekday: null,
          parentGradeId: gradeId,
        );
        if (weeklyLimits.minimumWeeklyConsecutivePairs != null &&
            weeklyPairs < weeklyLimits.minimumWeeklyConsecutivePairs!) {
          unmet.add(
            ScheduleBlocker(
              code: 'weeklyConsecutiveMinimum',
              message:
                  '班级 ${sample.classId} 科目 ${sample.subjectId} ${oddWeek ? '单' : '双'}周的每周连堂下限未满足',
            ),
          );
        }
      }
    }
    if (snapshot.preferences.checkProgressConsistency &&
        snapshot.preferences.progressConsistency ==
            ProgressConsistency.require) {
      final groups = <String, List<ScheduleItem>>{};
      for (final item in items) {
        final gradeId = snapshot.gradeIdForClass(item.classId);
        if (gradeId != null) {
          groups.putIfAbsent('$gradeId:${item.subjectId}', () => []).add(item);
        }
      }
      for (final entry in groups.entries) {
        for (final oddWeek in [true, false]) {
          final byClass = <String, List<ScheduleItem>>{};
          for (final item in entry.value.where(
            (row) => occursInWeek(row.weekMode, oddWeek: oddWeek),
          )) {
            byClass.putIfAbsent(item.classId, () => []).add(item);
          }
          final sameDemand = <int, List<List<ScheduleItem>>>{};
          for (final rows in byClass.values) {
            sameDemand.putIfAbsent(rows.length, () => []).add(rows);
          }
          for (final peerClasses in sameDemand.values.where(
            (rows) => rows.length > 1,
          )) {
            final days = peerClasses
                .expand((rows) => rows)
                .map((row) => row.position?.weekday)
                .whereType<int>()
                .toSet();
            for (final day in days) {
              final totals = [
                for (final rows in peerClasses)
                  rows
                      .where(
                        (row) =>
                            row.position != null &&
                            row.position!.weekday <= day,
                      )
                      .length,
              ];
              final low = totals.reduce((a, b) => a < b ? a : b);
              final high = totals.reduce((a, b) => a > b ? a : b);
              if (high - low > 1) {
                unmet.add(
                  ScheduleBlocker(
                    code: 'progressConsistency',
                    message:
                        '${entry.key} ${oddWeek ? '单' : '双'}周星期$day 的同级同科进度不同步',
                  ),
                );
              }
            }
          }
        }
      }
    }
    return unmet;
  }
}

bool _teacherPresetScopeMatches(
  SchedulingSnapshot snapshot,
  TeacherPresetScope scope,
  String scopeId,
  String classId,
) => switch (scope) {
  TeacherPresetScope.school => scopeId == snapshot.term.id,
  TeacherPresetScope.stage => snapshot.stageIdForClass(classId) == scopeId,
  TeacherPresetScope.grade => snapshot.gradeIdForClass(classId) == scopeId,
  TeacherPresetScope.schoolClass => classId == scopeId,
};

bool _sameMeeting(ScheduleItem left, ScheduleItem right) =>
    left.meetingId != null &&
    left.meetingId == right.meetingId &&
    left.combinedGroupId != null &&
    left.combinedGroupId == right.combinedGroupId;

bool _isFree(SchedulingSnapshot snapshot, String classId, SchedulePosition p) {
  final gradeId = snapshot.gradeIdForClass(classId);
  return snapshot.freeSlots.any(
    (slot) =>
        slot.stageId == p.stageId &&
        slot.weekday == p.weekday &&
        slot.periodTypeId == p.periodTypeId &&
        slot.lessonIndex == p.lessonIndex &&
        (slot.scope == FreeSlotScope.school ||
            (slot.scope == FreeSlotScope.stage && slot.scopeId == p.stageId) ||
            (slot.scope == FreeSlotScope.grade && slot.scopeId == gradeId) ||
            (slot.scope == FreeSlotScope.schoolClass &&
                slot.scopeId == classId)),
  );
}

PresetValue _subjectPreset(
  SchedulingSnapshot snapshot,
  ScheduleItem item,
  SchedulePosition p,
) {
  final gradeId = snapshot.gradeIdForClass(item.classId);
  final rows = snapshot.subjectPresets.where(
    (row) =>
        row.subjectId == item.subjectId &&
        row.stageId == p.stageId &&
        row.weekday == p.weekday &&
        row.periodTypeId == p.periodTypeId &&
        row.lessonIndex == p.lessonIndex,
  );
  for (final scope in [
    (FreeSlotScope.schoolClass, item.classId),
    (FreeSlotScope.grade, gradeId),
    (FreeSlotScope.stage, p.stageId),
    (FreeSlotScope.school, snapshot.term.id),
  ]) {
    for (final row in rows) {
      if (row.scope == scope.$1 && row.scopeId == scope.$2) return row.value;
    }
  }
  return PresetValue.auto;
}

PresetValue _teacherPreset(
  SchedulingSnapshot snapshot,
  ScheduleItem item,
  SchedulePosition p,
) {
  final gradeId = snapshot.gradeIdForClass(item.classId);
  final groupIds = snapshot.teacherGroupMembers
      .where((member) => member.teacherId == item.teacherId)
      .map((member) => member.groupId)
      .toSet();
  for (final scope in [
    (TeacherPresetScope.schoolClass, item.classId),
    (TeacherPresetScope.grade, gradeId),
    (TeacherPresetScope.stage, p.stageId),
    (TeacherPresetScope.school, snapshot.term.id),
  ]) {
    final personal = snapshot.teacherPresets.where(
      (row) =>
          row.teacherId == item.teacherId &&
          row.scope == scope.$1 &&
          row.scopeId == scope.$2 &&
          row.stageId == p.stageId &&
          row.weekday == p.weekday &&
          row.periodTypeId == p.periodTypeId &&
          row.lessonIndex == p.lessonIndex,
    );
    final groups = snapshot.teacherGroupPresets.where(
      (row) =>
          groupIds.contains(row.groupId) &&
          row.scope == scope.$1 &&
          row.scopeId == scope.$2 &&
          row.stageId == p.stageId &&
          row.weekday == p.weekday &&
          row.periodTypeId == p.periodTypeId &&
          row.lessonIndex == p.lessonIndex,
    );
    if (personal.isNotEmpty || groups.isNotEmpty) {
      try {
        return resolveTeacherPreset(
          personal: personal.isEmpty ? null : personal.first,
          groups: groups,
        );
      } on TeacherPresetConflictException {
        return PresetValue.forbid;
      }
    }
  }
  return PresetValue.auto;
}

typedef _Block = void Function(
  String code,
  String message,
  ScheduleItem item, {
  String? conditionId,
  List<String> relatedIds,
});

bool _conditionTargetMatches(ScheduleCondition condition, ScheduleItem item) =>
    condition.targetType == ScheduleConditionTarget.subject
    ? condition.targetId == item.subjectId
    : condition.targetId == item.teacherId;

void _checkConditions(
  SchedulingSnapshot snapshot,
  ScheduleItem item,
  List<ScheduleItem> all,
  _Block block,
) {
  final p = item.position!;
  for (final condition in snapshot.conditions) {
    if (condition.termId != snapshot.term.id) continue;
    if (condition.type == ScheduleConditionType.periodLimit ||
        condition.type == ScheduleConditionType.dailyLimit) {
      if (!_conditionTargetMatches(condition, item) ||
          (condition.type == ScheduleConditionType.periodLimit &&
              condition.periodTypeId != p.periodTypeId) ||
          (condition.weekday != null && condition.weekday != p.weekday)) {
        continue;
      }
      final maximum = condition.exact ?? condition.maximum;
      if (maximum == null) continue;
      for (final oddWeek in [true, false]) {
        if (!occursInWeek(item.weekMode, oddWeek: oddWeek)) continue;
        final count = all
            .where(
              (row) =>
                  row.position != null &&
                  occursInWeek(row.weekMode, oddWeek: oddWeek) &&
                  _conditionTargetMatches(condition, row) &&
                  (condition.targetType != ScheduleConditionTarget.subject ||
                      row.classId == item.classId) &&
                  (condition.type != ScheduleConditionType.periodLimit ||
                      row.position!.periodTypeId == condition.periodTypeId) &&
                  (condition.type != ScheduleConditionType.dailyLimit ||
                      row.position!.weekday == p.weekday) &&
                  (condition.weekday == null ||
                      row.position!.weekday == condition.weekday),
            )
            .length;
        if (count > maximum) {
          block(
            'conditionMaximum',
            '${condition.name ?? condition.id} 超过最多 $maximum 节',
            item,
            conditionId: condition.id,
          );
        }
      }
    } else if (condition.type == ScheduleConditionType.teacherMutualExclusion) {
      if (item.teacherId != condition.targetId &&
          item.teacherId != condition.otherTargetId) {
        continue;
      }
      final otherId = item.teacherId == condition.targetId
          ? condition.otherTargetId
          : condition.targetId;
      for (final other in all) {
        if (other.id != item.id &&
            other.teacherId == otherId &&
            other.position != null &&
            weekModesOverlap(item.weekMode, other.weekMode) &&
            p.overlaps(other.position!)) {
          block(
            'teacherMutualExclusion',
            '${condition.name ?? condition.id}：教师不能同时上课',
            item,
            conditionId: condition.id,
            relatedIds: [other.id],
          );
        }
      }
    } else if (condition.type == ScheduleConditionType.subjectMutualExclusion) {
      if (item.subjectId != condition.targetId &&
          item.subjectId != condition.otherTargetId) {
        continue;
      }
      final otherId = item.subjectId == condition.targetId
          ? condition.otherTargetId
          : condition.targetId;
      for (final other in all) {
        if (other.id != item.id &&
            other.classId == item.classId &&
            other.subjectId == otherId &&
            other.position?.weekday == p.weekday &&
            weekModesOverlap(item.weekMode, other.weekMode)) {
          block(
            'subjectMutualExclusion',
            '${condition.name ?? condition.id}：两科不能同一天',
            item,
            conditionId: condition.id,
            relatedIds: [other.id],
          );
        }
      }
    } else if (condition.type == ScheduleConditionType.forbiddenAdjacency) {
      for (final other in all) {
        if (other.id == item.id ||
            other.classId != item.classId ||
            other.position?.weekday != p.weekday ||
            !weekModesOverlap(item.weekMode, other.weekMode)) {
          continue;
        }
        if ((item.subjectId == condition.targetId &&
                other.subjectId == condition.otherTargetId &&
                _nextLesson(snapshot, p)?.sameCell(other.position!) == true) ||
            (other.subjectId == condition.targetId &&
                item.subjectId == condition.otherTargetId &&
                _nextLesson(snapshot, other.position!)?.sameCell(p) == true)) {
          block(
            'forbiddenAdjacency',
            '${condition.name ?? condition.id}：禁止科目相邻',
            item,
            conditionId: condition.id,
            relatedIds: [other.id],
          );
        }
      }
    }
  }
}

SchedulePosition? _nextLesson(SchedulingSnapshot snapshot, SchedulePosition p) {
  final routine = snapshot.routines.where((row) => row.stageId == p.stageId);
  if (routine.isEmpty) return null;
  final periods = [...routine.first.periodTypes]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final cells = <SchedulePosition>[];
  for (final period in periods) {
    for (
      var index = 1;
      index <= routine.first.effectiveLessonCount(period.id, p.weekday);
      index++
    ) {
      cells.add(
        SchedulePosition(
          stageId: p.stageId,
          weekday: p.weekday,
          periodTypeId: period.id,
          lessonIndex: index,
        ),
      );
    }
  }
  final index = cells.indexWhere((cell) => cell.sameCell(p));
  return index >= 0 && index + 1 < cells.length ? cells[index + 1] : null;
}

void _checkLessonLimits(
  SchedulingSnapshot snapshot,
  ScheduleItem item,
  List<ScheduleItem> all,
  _Block block,
) {
  final subjectConstraints = snapshot.lessonConstraints
      .where((rule) => rule.subjectId == item.subjectId)
      .toList();
  if (!subjectConstraints.any(
    (rule) =>
        rule.maximumDailyLessons != null ||
        rule.maximumDailyConsecutivePairs != null ||
        rule.maximumWeeklyConsecutivePairs != null,
  )) {
    return;
  }
  final p = item.position!;
  final gradeId = snapshot.gradeIdForClass(item.classId);
  for (final oddWeek in [true, false]) {
    if (!occursInWeek(item.weekMode, oddWeek: oddWeek)) continue;
    final limits = resolveSubjectLessonConstraints(
      constraints: subjectConstraints,
      scope: FreeSlotScope.schoolClass,
      scopeId: item.classId,
      stageId: p.stageId,
      weekday: p.weekday,
      parentGradeId: gradeId,
    );
    final count = limits.maximumDailyLessons == null
        ? 0
        : all
              .where(
                (row) =>
                    row.position != null &&
                    row.classId == item.classId &&
                    row.subjectId == item.subjectId &&
                    row.position!.weekday == p.weekday &&
                    occursInWeek(row.weekMode, oddWeek: oddWeek),
              )
              .length;
    if (limits.maximumDailyLessons != null &&
        count > limits.maximumDailyLessons!) {
      block('subjectDailyMaximum', '科目单日节数超过上限', item);
    }
    final weeklyRows = all.where(
      (row) =>
          row.position != null &&
          row.classId == item.classId &&
          row.subjectId == item.subjectId &&
          occursInWeek(row.weekMode, oddWeek: oddWeek),
    );
    final dayPairs = limits.maximumDailyConsecutivePairs == null
        ? 0
        : _consecutivePairCount(
            snapshot,
            weeklyRows
                .where((row) => row.position!.weekday == p.weekday)
                .toList(),
          );
    if (limits.maximumDailyConsecutivePairs != null &&
        dayPairs > limits.maximumDailyConsecutivePairs!) {
      block('dailyConsecutiveMaximum', '科目单日连堂次数超过上限', item);
    }
    final weeklyPairs = limits.maximumWeeklyConsecutivePairs == null
        ? 0
        : snapshot.routines
              .where((row) => row.stageId == p.stageId)
              .expand((row) => row.teachingWeekdays)
              .fold<int>(
                0,
                (sum, day) =>
                    sum +
                    _consecutivePairCount(
                      snapshot,
                      weeklyRows
                          .where((row) => row.position!.weekday == day)
                          .toList(),
                    ),
              );
    if (limits.maximumWeeklyConsecutivePairs != null &&
        weeklyPairs > limits.maximumWeeklyConsecutivePairs!) {
      block('weeklyConsecutiveMaximum', '科目每周连堂次数超过上限', item);
    }
  }
}

void _checkParallelAndRooms(
  SchedulingSnapshot snapshot,
  ScheduleItem item,
  List<ScheduleItem> all,
  _Block block,
) {
  final p = item.position!;
  final gradeId = snapshot.gradeIdForClass(item.classId);
  final limit = resolveSubjectParallelLimit(
    limits: snapshot.parallelLimits,
    subjectId: item.subjectId,
    termId: snapshot.term.id,
    stageId: p.stageId,
    gradeId: gradeId,
  );
  if (limit != null) {
    final lessons = all
        .where(
          (row) =>
              row.position != null &&
              row.subjectId == item.subjectId &&
              weekModesOverlap(row.weekMode, item.weekMode) &&
              row.position!.overlaps(p),
        )
        .map(
          (row) => row.combinedGroupId == null
              ? row.id
              : '${row.combinedGroupId}:${row.meetingId ?? row.position!.cellKey}',
        )
        .toSet();
    if (lessons.length > limit.maxParallelLessons) {
      block('parallelLimit', '同科同时上课超过 ${limit.maxParallelLessons} 节', item);
    }
  }
  String? roomFor(ScheduleItem row) => resolveSubjectRoomAssignment(
    assignments: snapshot.roomAssignments,
    subjectId: row.subjectId,
    termId: snapshot.term.id,
    stageId: row.position!.stageId,
    scope: FreeSlotScope.schoolClass,
    scopeId: row.classId,
    parentGradeId: snapshot.gradeIdForClass(row.classId),
  )?.roomId;

  final roomId = roomFor(item);
  if (roomId == null) return;
  final room = snapshot.rooms.where((row) => row.id == roomId);
  if (room.isEmpty) {
    block('room', '公共场室 $roomId 不存在', item);
    return;
  }
  for (final oddWeek in [true, false]) {
    if (!occursInWeek(item.weekMode, oddWeek: oddWeek)) continue;
    final classes = all
        .where(
          (row) =>
              row.position != null &&
              occursInWeek(row.weekMode, oddWeek: oddWeek) &&
              row.position!.overlaps(p) &&
              roomFor(row) == roomId,
        )
        .map((row) => row.classId)
        .toSet();
    if (classes.length > room.first.roomCount * room.first.capacityPerRoom) {
      block('roomCapacity', '公共场室 ${room.first.name} 容量已满', item);
    }
  }
}

void _checkHardGlobals(
  SchedulingSnapshot snapshot,
  ScheduleItem item,
  List<ScheduleItem> all,
  _Block block,
) {
  final p = item.position!;
  if (snapshot.preferences.consecutiveMode == ConsecutiveMode.requireSeparate &&
      !_hasForcedConsecutive(snapshot, item)) {
    for (final other in all) {
      if (other.id != item.id &&
          other.classId == item.classId &&
          other.subjectId == item.subjectId &&
          other.position?.weekday == p.weekday &&
          weekModesOverlap(item.weekMode, other.weekMode) &&
          (_nextLesson(snapshot, p)?.sameCell(other.position!) == true ||
              _nextLesson(snapshot, other.position!)?.sameCell(p) == true)) {
        block('consecutive', '该科目设置了硬性不连堂', item);
      }
    }
  }
  if (snapshot.preferences.protectLunchBreak) {
    final routine = snapshot.routines.where((row) => row.stageId == p.stageId);
    if (routine.isNotEmpty) {
      final periods = [...routine.first.periodTypes]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final morning = periods.where((row) => row.name.contains('上午'));
      final afternoon = periods.where((row) => row.name.contains('下午'));
      if (morning.isNotEmpty && afternoon.isNotEmpty) {
        for (final other in all) {
          if (other.id == item.id ||
              other.teacherId != item.teacherId ||
              other.position?.weekday != p.weekday ||
              !weekModesOverlap(item.weekMode, other.weekMode)) {
            continue;
          }
          final pair = [p, other.position!];
          final atMorningEnd = pair.any(
            (cell) =>
                cell.periodTypeId == morning.first.id &&
                cell.lessonIndex ==
                    routine.first.effectiveLessonCount(
                      morning.first.id,
                      p.weekday,
                    ),
          );
          final atAfternoonStart = pair.any(
            (cell) =>
                cell.periodTypeId == afternoon.first.id &&
                cell.lessonIndex == 1,
          );
          if (atMorningEnd && atAfternoonStart) {
            block('lunchProtection', '教师上午末节与下午首节连续有课', item);
          }
        }
      }
    }
  }
}

bool _hasForcedConsecutive(SchedulingSnapshot snapshot, ScheduleItem item) {
  final gradeId = snapshot.gradeIdForClass(item.classId);
  if (snapshot.requirements.any(
    (row) =>
        row.subjectId == item.subjectId &&
        row.gradeId == gradeId &&
        row.weekMode == item.weekMode &&
        (row.classId == null || row.classId == item.classId) &&
        (snapshot.requiredConsecutivePairsByRequirement[row.id] ?? 0) > 0,
  )) {
    return true;
  }
  final stageId = snapshot.stageIdForClass(item.classId);
  if (stageId == null) return false;
  final limits = resolveSubjectLessonConstraints(
    constraints: snapshot.lessonConstraints.where(
      (row) => row.subjectId == item.subjectId,
    ),
    scope: FreeSlotScope.schoolClass,
    scopeId: item.classId,
    stageId: stageId,
    weekday: item.position?.weekday,
    parentGradeId: gradeId,
  );
  return (limits.minimumDailyConsecutivePairs ?? 0) > 0 ||
      (limits.minimumWeeklyConsecutivePairs ?? 0) > 0;
}

int _consecutivePairCount(
  SchedulingSnapshot snapshot,
  List<ScheduleItem> rows,
) {
  var count = 0;
  for (final row in rows) {
    final next = _nextLesson(snapshot, row.position!);
    if (next != null &&
        rows.any(
          (other) =>
              other.id != row.id && other.position?.sameCell(next) == true,
        )) {
      count++;
    }
  }
  return count;
}

String _blockerIdentity(ScheduleBlocker blocker) =>
    '${blocker.code}:${blocker.conditionId}:${blocker.position?.cellKey}:${blocker.message.replaceAll(RegExp(r'已排 \d+ 节'), '已排 * 节')}';

int? _placedCount(ScheduleBlocker blocker) => int.tryParse(
  RegExp(r'已排 (\d+) 节').firstMatch(blocker.message)?.group(1) ?? '',
);
