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

    final effectiveDemand = <String, int>{};
    for (final schoolClass in snapshot.classes) {
      final rows = snapshot.requirements.where(
        (row) => row.gradeId == schoolClass.gradeId,
      );
      final bySubjectWeek = <String, SubjectRequirement>{};
      for (final row in rows.where((row) => row.classId == null)) {
        bySubjectWeek['${row.subjectId}:${row.weekMode.name}'] = row;
      }
      for (final row in rows.where((row) => row.classId == schoolClass.id)) {
        bySubjectWeek['${row.subjectId}:${row.weekMode.name}'] = row;
      }
      var oddDemand = 0;
      var evenDemand = 0;
      for (final row in bySubjectWeek.values) {
        if (row.lessonCount <= 0) continue;
        final key = '${schoolClass.id}:${row.subjectId}:${row.weekMode.name}';
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

    final assignedCount = <String, int>{};
    final teacherIds = snapshot.teachers.map((item) => item.id).toSet();
    final subjectIds = snapshot.subjects.map((item) => item.id).toSet();
    for (final assignment in snapshot.assignments) {
      if (assignment.termId != snapshot.term.id) continue;
      assignedCount.update(
        assignment.demandKey,
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
      final classId = entry.key.split(':').first;
      if (selected.contains(classId) &&
          assignedCount[entry.key] != entry.value) {
        issue(
          'assignment',
          '班级 $classId 的任课节数与需求不符：${assignedCount[entry.key] ?? 0}/${entry.value}',
        );
      }
    }
    for (final entry in assignedCount.entries) {
      final classId = entry.key.split(':').first;
      if (selected.contains(classId) &&
          !effectiveDemand.containsKey(entry.key) &&
          entry.value != 0) {
        issue('assignment', '班级 $classId 存在无对应节数需求的任课 ${entry.key}');
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

    final lockedClasses = snapshot.locks
        .where((lock) => lock.scope == ScheduleLockScope.schoolClass)
        .map((lock) => lock.targetId)
        .toSet();
    final lockedTeachers = snapshot.locks
        .where((lock) => lock.scope == ScheduleLockScope.teacher)
        .map((lock) => lock.targetId)
        .toSet();
    final fixed = <ScheduleItem>[];
    final movable = <ScheduleItem>[];
    for (final item in allItems) {
      if (!selected.contains(item.classId) ||
          lockedClasses.contains(item.classId) ||
          lockedTeachers.contains(item.teacherId)) {
        fixed.add(item);
      } else {
        movable.add(item.at(null));
      }
    }
    final meetingKeys = <String, String>{};
    for (final group in snapshot.combinedGroups) {
      final members = movable.where((item) => item.combinedGroupId == group.id);
      final groupedByClass = <String, List<ScheduleItem>>{};
      for (final item in members) {
        groupedByClass.putIfAbsent(item.classId, () => []).add(item);
      }
      if (groupedByClass.isEmpty) continue;
      if (!selected.containsAll(group.classIds)) {
        issue('combinedScope', '合班组 ${group.id} 跨越已选与未选班级');
      }
      final counts = groupedByClass.values.map((rows) => rows.length).toSet();
      if (counts.length != 1 ||
          groupedByClass.length != group.classIds.length) {
        issue('combined', '合班组 ${group.id} 的各班任课节数不一致');
        continue;
      }
      for (final rows in groupedByClass.values) {
        rows.sort((a, b) => a.id.compareTo(b.id));
        for (var index = 0; index < rows.length; index++) {
          meetingKeys[rows[index].id] = 'combined:${group.id}:$index';
        }
      }
    }
    for (final pairing in snapshot.pairings) {
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
      }
      for (var index = 0; index < odd.length && index < even.length; index++) {
        meetingKeys[odd[index].id] = 'pair:${pairing.id}:$index';
        meetingKeys[even[index].id] = 'pair:${pairing.id}:$index';
      }
    }
    final unitsById = <String, List<ScheduleItem>>{};
    for (final item in movable) {
      final unitId = meetingKeys[item.id] ?? item.id;
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
              meetingId: meetingKeys[item.id] ?? item.meetingId,
            ),
          );
    }
    final units = [
      for (final entry in unitsById.entries)
        ScheduleUnit(entry.key, entry.value),
    ];
    units.sort((a, b) => a.id.compareTo(b.id));

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
