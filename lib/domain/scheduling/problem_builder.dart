import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

/// 启动前检查清单中的一项。
class SchedulePreflightCheck {
  const SchedulePreflightCheck({
    required this.code,
    required this.message,
    required this.ready,
  });

  final String code;
  final String message;
  final bool ready;
}

/// 必须同时放置的一组课节，包含合班或单双周配对。
class ScheduleUnit {
  const ScheduleUnit(this.id, this.items);

  final String id;
  final List<ScheduleItem> items;

  int get coverage => items.fold(0, (sum, item) => sum + item.occurrenceCount);
}

/// 经过需求展开与结构校验的求解输入。
class SchedulingProblem {
  const SchedulingProblem({
    required this.snapshot,
    required this.selectedClassIds,
    required this.positionsByClass,
    required this.fixedItems,
    required this.units,
    required this.checks,
  });

  final SchedulingSnapshot snapshot;
  final Set<String> selectedClassIds;
  final Map<String, List<SchedulePosition>> positionsByClass;
  final List<ScheduleItem> fixedItems;
  final List<ScheduleUnit> units;
  final List<SchedulePreflightCheck> checks;

  bool get isReady => checks.every((check) => check.ready);
  int get totalItems =>
      fixedItems.length + units.fold(0, (n, u) => n + u.items.length);

  ScheduleItem withClock(ScheduleItem item) {
    final position = item.position;
    if (position == null) return item;
    final cell = positionsByClass[item.classId]
        ?.where((candidate) => candidate.sameCell(position))
        .firstOrNull;
    return cell == null ? item : item.at(cell);
  }

  /// 识别旧版课表中被单双周配对拆散的合班及其关联课组。
  bool hasInconsistentCombinedMeetings(List<ScheduleItem> items) {
    final byId = {for (final item in items) item.id: item};
    for (final unit in units) {
      if (!unit.items.any((item) => item.combinedGroupId != null)) continue;
      final members = unit.items.map((item) => byId[item.id]).toList();
      if (members.every((item) => item == null)) continue;
      if (members.any((item) => item == null)) return true;
      final first = members.first!;
      if (first.meetingId == null) return true;
      SchedulePosition? positionFor(ScheduleItem item) => item.position == null
          ? null
          : (positionsByClass[item.classId] ?? const <SchedulePosition>[])
                .where((position) => position.sameCell(item.position!))
                .firstOrNull;
      final anchor = positionFor(first);
      for (var index = 0; index < members.length; index++) {
        final member = members[index]!;
        if (member.meetingId != first.meetingId ||
            member.combinedGroupId != unit.items[index].combinedGroupId ||
            member.isPlaced != first.isPlaced) {
          return true;
        }
        if (!member.isPlaced) continue;
        final position = positionFor(member);
        if (anchor == null ||
            position == null ||
            !(anchor.stageId == position.stageId
                ? anchor.sameCell(position)
                : anchor.hasSameClock(position))) {
          return true;
        }
      }
    }
    return false;
  }
}

/// 展开年级/班级需求、教师拆分与合班绑定，并检查启动条件。
class ProblemBuilder {
  const ProblemBuilder();

  SchedulingProblem build(
    SchedulingSnapshot snapshot, {
    Set<String>? selectedClassIds,
  }) {
    final allClassIds = snapshot.classes.map((item) => item.id).toSet();
    final selected = selectedClassIds ?? allClassIds;
    final checks = <SchedulePreflightCheck>[];
    void issue(String code, String message) => checks.add(
      SchedulePreflightCheck(code: code, message: message, ready: false),
    );

    if (selected.isEmpty || !allClassIds.containsAll(selected)) {
      issue('classes', '排课范围为空或包含不存在的班级');
    }
    final routines = {for (final item in snapshot.routines) item.stageId: item};
    final positionsByClass = <String, List<SchedulePosition>>{};
    for (final schoolClass in snapshot.classes) {
      final stageId = snapshot.stageIdForClass(schoolClass.id);
      final routine = routines[stageId];
      if (stageId == null || routine == null) {
        if (selected.contains(schoolClass.id)) {
          issue('routine', '班级 ${schoolClass.name} 缺少学段或作息');
        }
        continue;
      }
      final positions = <SchedulePosition>[];
      final periods = [...routine.periodTypes]
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      for (final day in routine.teachingWeekdays.toList()..sort()) {
        for (final period in periods) {
          final count = routine.effectiveLessonCount(period.id, day);
          for (var index = 1; index <= count; index++) {
            final time = period.lessonTimes.where(
              (e) => e.lessonIndex == index,
            );
            final lessonTime = time.isEmpty ? null : time.first;
            positions.add(
              SchedulePosition(
                stageId: stageId,
                weekday: day,
                periodTypeId: period.id,
                lessonIndex: index,
                startMinute: lessonTime?.startMinute,
                endMinute: lessonTime?.endMinute,
              ),
            );
          }
        }
      }
      positionsByClass[schoolClass.id] = positions;
      if (selected.contains(schoolClass.id) && positions.isEmpty) {
        issue('routine', '班级 ${schoolClass.name} 没有可排节次');
      }
    }

    final knownTeachers = snapshot.teachers
        .map((teacher) => teacher.id)
        .toSet();
    final invalidDuties = <String>{};
    for (final duty in snapshot.supervision) {
      final position = duty.position;
      final valid =
          knownTeachers.contains(duty.teacherId) &&
          duty.classIds.every((classId) {
            final current = (positionsByClass[classId] ?? const [])
                .where(position.sameCell)
                .firstOrNull;
            if (current == null ||
                current.startMinute != duty.startMinute ||
                current.endMinute != duty.endMinute) {
              return false;
            }
            final marker = resolveFreeSlotsForView(
              snapshot.freeSlots,
              viewScope: FreeSlotScope.schoolClass,
              viewScopeId: classId,
              termId: snapshot.term.id,
              stageId: position.stageId,
              weekday: position.weekday,
              periodTypeId: position.periodTypeId,
              lessonIndex: position.lessonIndex,
              classGradeId: snapshot.gradeIdForClass(classId),
            ).full;
            return marker == null || marker.allowsSupervision;
          });
      if (!valid && invalidDuties.add(duty.post.id)) {
        issue(
          'supervisionRepairRequired',
          '带班「${duty.post.name}」的班级、老师或作息已变化，请先修正带班方案',
        );
      }
    }

    final effectiveDemand = <(String, String, WeekMode), int>{};
    for (final schoolClass in snapshot.classes) {
      final rows = snapshot.requirements.where(
        (row) => row.gradeId == schoolClass.gradeId,
      );
      final bySubjectWeek = <(String, WeekMode), SubjectRequirement>{};
      for (final row in rows.where((row) => row.classId == null)) {
        bySubjectWeek[(row.subjectId, row.weekMode)] = row;
      }
      for (final row in rows.where((row) => row.classId == schoolClass.id)) {
        bySubjectWeek[(row.subjectId, row.weekMode)] = row;
      }
      var oddDemand = 0;
      var evenDemand = 0;
      for (final row in bySubjectWeek.values) {
        if (row.lessonCount <= 0) continue;
        final key = (schoolClass.id, row.subjectId, row.weekMode);
        effectiveDemand[key] = row.lessonCount;
        if (row.weekMode != WeekMode.even) oddDemand += row.lessonCount;
        if (row.weekMode != WeekMode.odd) evenDemand += row.lessonCount;
      }
      if (selected.contains(schoolClass.id)) {
        final available = (positionsByClass[schoolClass.id] ?? const [])
            .where((position) => !_isFree(snapshot, schoolClass.id, position))
            .length;
        if (oddDemand > available || evenDemand > available) {
          checks.add(
            SchedulePreflightCheck(
              code: 'capacity',
              message:
                  '班级 ${schoolClass.name} 容量不足：单周 $oddDemand、双周 $evenDemand、可用 $available；剩余课程将进入暂放区',
              ready: true,
            ),
          );
        }
      }
    }

    final assignedCount = <(String, String, WeekMode), int>{};
    String demandLabel((String, String, WeekMode) key) {
      final schoolClass = snapshot.classes
          .where((item) => item.id == key.$1)
          .firstOrNull;
      final grade = snapshot.grades
          .where((item) => item.id == schoolClass?.gradeId)
          .firstOrNull;
      final stage = snapshot.stages
          .where((item) => item.id == grade?.stageId)
          .firstOrNull;
      final subject = snapshot.subjects
          .where((item) => item.id == key.$2)
          .firstOrNull;
      return '${[stage?.name, grade?.name, schoolClass?.name ?? key.$1].whereType<String>().join(' · ')} · ${subject?.name ?? key.$2}（${key.$3.label}）';
    }

    final teacherIds = snapshot.teachers.map((item) => item.id).toSet();
    final subjectIds = snapshot.subjects.map((item) => item.id).toSet();
    for (final assignment in snapshot.assignments) {
      if (assignment.termId != snapshot.term.id) continue;
      assignedCount.update(
        (assignment.classId, assignment.subjectId, assignment.weekMode),
        (count) => count + assignment.lessonCount,
        ifAbsent: () => assignment.lessonCount,
      );
      if (selected.contains(assignment.classId) &&
          (!allClassIds.contains(assignment.classId) ||
              !teacherIds.contains(assignment.teacherId) ||
              !subjectIds.contains(assignment.subjectId) ||
              assignment.lessonCount < 0)) {
        issue('assignment', '任课 ${assignment.id} 的班级、教师、科目或节数无效');
      }
    }
    for (final entry in effectiveDemand.entries) {
      final classId = entry.key.$1;
      if (selected.contains(classId) &&
          assignedCount[entry.key] != entry.value) {
        issue(
          'assignment',
          '${demandLabel(entry.key)}的任课节数与需求不符：${assignedCount[entry.key] ?? 0}/${entry.value}。请前往教师任课调整分配',
        );
      }
    }
    for (final entry in assignedCount.entries) {
      final classId = entry.key.$1;
      if (selected.contains(classId) &&
          !effectiveDemand.containsKey(entry.key) &&
          entry.value != 0) {
        issue(
          'assignment',
          '${demandLabel(entry.key)}存在无对应节数需求的任课，请前往教师任课调整分配',
        );
      }
    }

    final existingByAssignment = <String, List<ScheduleItem>>{};
    for (final item in snapshot.existingItems) {
      existingByAssignment.putIfAbsent(item.assignmentId, () => []).add(item);
    }
    final allItems = <ScheduleItem>[];
    for (final assignment in snapshot.assignments) {
      if (assignment.termId != snapshot.term.id ||
          assignment.lessonCount <= 0) {
        continue;
      }
      final existing = [...?existingByAssignment[assignment.id]]
        ..sort((a, b) => a.id.compareTo(b.id));
      for (var index = 0; index < assignment.lessonCount; index++) {
        final old = index < existing.length ? existing[index] : null;
        final oldPosition = old?.position;
        final normalizedPosition = oldPosition == null
            ? null
            : (positionsByClass[assignment.classId] ??
                          const <SchedulePosition>[])
                      .where((position) => position.sameCell(oldPosition))
                      .firstOrNull ??
                  oldPosition;
        allItems.add(
          ScheduleItem(
            id: old?.id ?? '${assignment.id}:${index + 1}',
            termId: snapshot.term.id,
            assignmentId: assignment.id,
            classId: assignment.classId,
            teacherId: assignment.teacherId,
            subjectId: assignment.subjectId,
            weekMode: assignment.weekMode,
            combinedGroupId: assignment.combinedLessonGroupId,
            meetingId: old?.meetingId,
            position: normalizedPosition,
          ),
        );
      }
    }

    final teacherNames = {
      for (final teacher in snapshot.teachers) teacher.id: teacher.name,
    };
    final classNames = {for (final c in snapshot.classes) c.id: c.name};
    final subjectNames = {
      for (final subject in snapshot.subjects) subject.id: subject.name,
    };
    final lockedClasses = snapshot.locks
        .where((lock) => lock.scope == ScheduleLockScope.schoolClass)
        .map((lock) => lock.targetId)
        .toSet();
    final lockedTeachers = snapshot.locks
        .where((lock) => lock.scope == ScheduleLockScope.teacher)
        .map((lock) => lock.targetId)
        .toSet();
    final fixedCombinedGroupIds = <String>{};
    for (final group in snapshot.combinedGroups) {
      if (lockedTeachers.contains(group.teacherId) ||
          group.classIds.any(
            (classId) =>
                !selected.contains(classId) || lockedClasses.contains(classId),
          )) {
        fixedCombinedGroupIds.add(group.id);
      }
    }
    for (final item in allItems) {
      final groupId = item.combinedGroupId;
      if (groupId != null &&
          (!selected.contains(item.classId) ||
              lockedClasses.contains(item.classId) ||
              lockedTeachers.contains(item.teacherId))) {
        fixedCombinedGroupIds.add(groupId);
      }
    }
    final fixed = <ScheduleItem>[];
    final movable = <ScheduleItem>[];
    for (final item in allItems) {
      if (!selected.contains(item.classId) ||
          lockedClasses.contains(item.classId) ||
          lockedTeachers.contains(item.teacherId) ||
          (item.combinedGroupId != null &&
              fixedCombinedGroupIds.contains(item.combinedGroupId))) {
        fixed.add(item);
      } else {
        movable.add(item.at(null));
      }
    }
    final reportedMeetingConflicts = <String>{};
    void reportTeacherConflict(ScheduleItem left, ScheduleItem right) {
      final key =
          '${left.teacherId}:${left.classId}:${right.classId}:${left.weekMode.storageValue}:${right.weekMode.storageValue}';
      if (!reportedMeetingConflicts.add(key)) return;
      final week = left.weekMode == WeekMode.weekly
          ? right.weekMode
          : left.weekMode;
      issue(
        'meetingTeacherConflict',
        '${teacherNames[left.teacherId] ?? left.teacherId}的${week.label}课程被合班与单双周配对要求同时在'
            '${classNames[left.classId] ?? left.classId}、${classNames[right.classId] ?? right.classId}上课，'
            '但这些课程尚未合班。请为该周次设置合班，或解除相关单双周配对。',
      );
    }

    final pairingTeacherConflicts = <(ScheduleItem, ScheduleItem)>[];
    final meetingKeys = <String, String>{};
    final meetingParents = <String, String>{};
    final meetingMembers = <String, Set<String>>{};
    final movableById = {for (final item in movable) item.id: item};
    String meetingRoot(String key) {
      final parent = meetingParents[key];
      if (parent == null) return key;
      return meetingParents[key] = meetingRoot(parent);
    }

    void bindMeeting(String itemId, String key) {
      final previous = meetingKeys[itemId];
      String? mergedRoot;
      if (previous != null) {
        final left = meetingRoot(previous);
        final right = meetingRoot(key);
        if (left != right) {
          // 采用稳定根标识，同时保留合班和单双周配对的传递约束。
          if (left.compareTo(right) < 0) {
            meetingParents[right] = left;
            mergedRoot = right;
          } else {
            meetingParents[left] = right;
            mergedRoot = left;
          }
        }
      }
      meetingKeys[itemId] = key;
      final root = meetingRoot(key);
      final members = meetingMembers.putIfAbsent(root, () => {});
      members.add(itemId);
      if (mergedRoot != null) {
        members.addAll(meetingMembers.remove(mergedRoot) ?? const {});
      }
    }

    String rootFor(ScheduleItem item) => meetingKeys[item.id] == null
        ? 'item:${item.id}'
        : meetingRoot(meetingKeys[item.id]!);
    bool canPair(ScheduleItem odd, ScheduleItem even) {
      final left = rootFor(odd);
      final right = rootFor(even);
      if (left == right) return true;
      for (final leftId in meetingMembers[left] ?? {odd.id}) {
        for (final rightId in meetingMembers[right] ?? {even.id}) {
          final a = movableById[leftId]!;
          final b = movableById[rightId]!;
          if (!weekModesOverlap(a.weekMode, b.weekMode)) continue;
          if (a.classId == b.classId) return false;
          if (a.teacherId == b.teacherId &&
              !(a.combinedGroupId != null &&
                  a.combinedGroupId == b.combinedGroupId)) {
            pairingTeacherConflicts.add((a, b));
            return false;
          }
        }
      }
      return true;
    }

    for (final group in snapshot.combinedGroups) {
      final members = allItems.where(
        (item) => item.combinedGroupId == group.id,
      );
      final groupedByClass = <String, List<ScheduleItem>>{};
      for (final item in members) {
        groupedByClass.putIfAbsent(item.classId, () => []).add(item);
      }
      if (groupedByClass.isEmpty) continue;
      final groupClassNames = group.classIds
          .map((classId) => classNames[classId] ?? '未知班级')
          .join('、');
      final groupLabel =
          '$groupClassNames · ${subjectNames[group.subjectId] ?? '未知科目'}'
          ' · ${teacherNames[group.teacherId] ?? '未知教师'} · ${group.weekMode.label}';
      if (!selected.containsAll(group.classIds)) {
        issue('combinedScope', '合班组（$groupLabel）跨越已选与未选班级');
      }
      final counts = groupedByClass.values.map((rows) => rows.length).toSet();
      if (counts.length != 1 ||
          groupedByClass.length != group.classIds.length) {
        issue('combined', '合班组（$groupLabel）的各班任课节数不一致');
        continue;
      }
      for (final rows in groupedByClass.values) {
        rows.sort((a, b) => a.id.compareTo(b.id));
        for (var index = 0; index < rows.length; index++) {
          bindMeeting(rows[index].id, 'combined:${group.id}:$index');
        }
      }
    }
    for (final pairing in snapshot.pairings) {
      pairingTeacherConflicts.clear();
      final odd =
          movable
              .where(
                (item) =>
                    item.classId == pairing.classId &&
                    item.subjectId == pairing.oddSubjectId &&
                    item.weekMode == WeekMode.odd,
              )
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      final even =
          movable
              .where(
                (item) =>
                    item.classId == pairing.classId &&
                    item.subjectId == pairing.evenSubjectId &&
                    item.weekMode == WeekMode.even,
              )
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      if (odd.length != even.length) {
        issue('pairing', '单双周配对 ${pairing.id} 的需求节数不一致');
        continue;
      }
      // 已经通过其他班的合班关系配对的课次必须保留，剩余课次做兼容匹配。
      final matched = <String, ScheduleItem>{};
      final pinnedEven = <String>{};
      final pinnedOdd = <String>{};
      for (final item in odd) {
        final partner = even
            .where((other) => rootFor(item) == rootFor(other))
            .firstOrNull;
        if (partner == null) continue;
        matched[partner.id] = item;
        pinnedEven.add(partner.id);
        pinnedOdd.add(item.id);
      }
      bool match(ScheduleItem item, Set<String> visited) {
        // 先用空闲课次，只有必要时才调整已有匹配，避免无变更课表产生互换差异。
        final candidates = [
          ...even.where((partner) => !matched.containsKey(partner.id)),
          ...even.where((partner) => matched.containsKey(partner.id)),
        ];
        for (final partner in candidates) {
          if (pinnedEven.contains(partner.id) ||
              !canPair(item, partner) ||
              !visited.add(partner.id)) {
            continue;
          }
          final previous = matched[partner.id];
          if (previous == null || match(previous, visited)) {
            matched[partner.id] = item;
            return true;
          }
        }
        return false;
      }

      if (odd.any((item) => !pinnedOdd.contains(item.id) && !match(item, {}))) {
        if (pairingTeacherConflicts.isNotEmpty) {
          final (left, right) = pairingTeacherConflicts.first;
          reportTeacherConflict(left, right);
        } else {
          issue(
            'pairingCombinedConflict',
            '合班与单双周配对 ${pairing.id} 无法形成完整课组，请检查合班范围和配对设置。',
          );
        }
        continue;
      }
      for (var index = 0; index < odd.length; index++) {
        final partner = even.firstWhere(
          (item) => matched[item.id]?.id == odd[index].id,
        );
        bindMeeting(odd[index].id, 'pair:${pairing.id}:$index');
        bindMeeting(partner.id, 'pair:${pairing.id}:$index');
      }
    }
    final unitsById = <String, List<ScheduleItem>>{};
    for (final item in movable) {
      final meetingKey = meetingKeys[item.id];
      final meetingId = meetingKey == null ? null : meetingRoot(meetingKey);
      final unitId = meetingId ?? item.id;
      unitsById
          .putIfAbsent(unitId, () => [])
          .add(
            ScheduleItem(
              id: item.id,
              termId: item.termId,
              assignmentId: item.assignmentId,
              classId: item.classId,
              teacherId: item.teacherId,
              subjectId: item.subjectId,
              weekMode: item.weekMode,
              combinedGroupId: item.combinedGroupId,
              meetingId: meetingId,
            ),
          );
    }
    final units = [
      for (final entry in unitsById.entries)
        ScheduleUnit(entry.key, entry.value),
    ];
    units.sort((a, b) => a.id.compareTo(b.id));
    for (final unit in units) {
      for (var i = 0; i < unit.items.length; i++) {
        final left = unit.items[i];
        for (final right in unit.items.skip(i + 1)) {
          if (left.teacherId != right.teacherId ||
              !weekModesOverlap(left.weekMode, right.weekMode) ||
              (left.combinedGroupId != null &&
                  left.combinedGroupId == right.combinedGroupId)) {
            continue;
          }
          reportTeacherConflict(left, right);
        }
      }
    }

    // A shared resource can only be checked across stages when every relevant
    // teaching cell has a clock interval.
    final teacherStages = <String, Set<String>>{};
    for (final assignment in snapshot.assignments) {
      final stage = snapshot.stageIdForClass(assignment.classId);
      if (stage != null) {
        teacherStages.putIfAbsent(assignment.teacherId, () => {}).add(stage);
      }
    }
    final clockStages = <String>{};
    for (final stages in teacherStages.values) {
      if (stages.length > 1) clockStages.addAll(stages);
    }
    for (final group in snapshot.combinedGroups) {
      final stages = group.classIds
          .map(snapshot.stageIdForClass)
          .whereType<String>()
          .toSet();
      if (stages.length > 1) clockStages.addAll(stages);
    }
    final roomStages = <String, Set<String>>{};
    for (final row in snapshot.roomAssignments) {
      final roomId = row.roomId;
      if (roomId != null) {
        roomStages.putIfAbsent(roomId, () => {}).add(row.stageId);
      }
    }
    for (final stages in roomStages.values) {
      if (stages.length > 1) clockStages.addAll(stages);
    }
    for (final stageId in clockStages) {
      final relevant = positionsByClass.entries
          .where((entry) => snapshot.stageIdForClass(entry.key) == stageId)
          .expand((entry) => entry.value);
      if (relevant.any((position) => !position.hasClockTime)) {
        issue('clock', '跨学段共享资源涉及的学段 $stageId 缺少完整节次起止时间');
      }
    }
    if (checks.isEmpty) {
      checks.add(
        const SchedulePreflightCheck(
          code: 'ready',
          message: '班级、作息、容量、任课与跨学段时间已就绪',
          ready: true,
        ),
      );
    }
    return SchedulingProblem(
      snapshot: snapshot,
      selectedClassIds: selected,
      positionsByClass: positionsByClass,
      fixedItems: fixed,
      units: units,
      checks: checks,
    );
  }
}

bool _isFree(
  SchedulingSnapshot snapshot,
  String classId,
  SchedulePosition position,
) {
  final gradeId = snapshot.gradeIdForClass(classId);
  for (final slot in snapshot.freeSlots) {
    if (slot.stageId != position.stageId ||
        slot.weekday != position.weekday ||
        slot.periodTypeId != position.periodTypeId ||
        slot.lessonIndex != position.lessonIndex) {
      continue;
    }
    if (slot.scope == FreeSlotScope.school ||
        (slot.scope == FreeSlotScope.stage &&
            slot.scopeId == position.stageId) ||
        (slot.scope == FreeSlotScope.grade && slot.scopeId == gradeId) ||
        (slot.scope == FreeSlotScope.schoolClass && slot.scopeId == classId)) {
      return true;
    }
  }
  return false;
}
