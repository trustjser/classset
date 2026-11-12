import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';

class SupervisionValidation {
  const SupervisionValidation();

  List<SchedulePosition> positions(
    SchedulingSnapshot snapshot,
    SupervisionPost post,
  ) {
    return [
      for (final index in post.lessonIndices)
        withRoutineClock(
          snapshot,
          SchedulePosition(
            stageId: post.stageId,
            weekday: post.weekday,
            periodTypeId: post.periodTypeId,
            lessonIndex: index,
          ),
        ),
    ];
  }

  SchedulePosition withRoutineClock(
    SchedulingSnapshot snapshot,
    SchedulePosition position,
  ) {
    if (position.hasClockTime) return position;
    final routine = snapshot.routines
        .where((entry) => entry.stageId == position.stageId)
        .firstOrNull;
    final period = routine?.periodTypes
        .where((entry) => entry.id == position.periodTypeId)
        .firstOrNull;
    final time = period?.lessonTimes
        .where((entry) => entry.lessonIndex == position.lessonIndex)
        .firstOrNull;
    if (time == null) return position;
    return SchedulePosition(
      stageId: position.stageId,
      weekday: position.weekday,
      periodTypeId: position.periodTypeId,
      lessonIndex: position.lessonIndex,
      startMinute: time.startMinute,
      endMinute: time.endMinute,
    );
  }

  List<String> postErrors(SchedulingSnapshot snapshot, SupervisionDraft draft) {
    final errors = <String>{};
    final postIds = <String>{};
    final occupied = <String, List<SchedulePosition>>{};
    final classNames = {
      for (final item in snapshot.classes) item.id: item.name,
    };
    for (final post in draft.posts) {
      final title = post.groupName.isEmpty ? post.name : post.groupName;
      if (!postIds.add(post.id)) errors.add('岗位 $title 重复');
      if (post.name.trim().isEmpty) errors.add('请填写活动名称');
      if (post.classIds.isEmpty ||
          post.classIds.toSet().length != post.classIds.length ||
          post.classIds.any(
            (id) => snapshot.stageIdForClass(id) != post.stageId,
          )) {
        errors.add('$title：请选择同一学段内有效且不重复的班级');
      }
      if (post.classIds.length > 1 &&
          (post.groupName.trim().isEmpty || post.location.trim().isEmpty)) {
        errors.add('$title：实际合班须填写组名和地点');
      }
      final routine = snapshot.routines
          .where((entry) => entry.stageId == post.stageId)
          .firstOrNull;
      if (routine == null ||
          !routine.teachingWeekdays.contains(post.weekday) ||
          !routine.periodTypes.any((entry) => entry.id == post.periodTypeId)) {
        errors.add('$title：星期或时段已不存在');
        continue;
      }
      final count = routine.effectiveLessonCount(
        post.periodTypeId,
        post.weekday,
      );
      final indices = post.lessonIndices;
      if (indices.isEmpty ||
          indices.any((index) => index < 1 || index > count) ||
          indices.indexed.any(
            (entry) => entry.$1 > 0 && entry.$2 != indices[entry.$1 - 1] + 1,
          )) {
        errors.add('$title：节次不存在或连续带班包含不相邻节次');
        continue;
      }
      for (final id in post.classIds) {
        final name = classNames[id] ?? id;
        final prior = occupied.putIfAbsent(id, () => []);
        for (final position in positions(snapshot, post)) {
          final slot = resolveFreeSlotsForView(
            snapshot.freeSlots,
            viewScope: FreeSlotScope.schoolClass,
            viewScopeId: id,
            termId: draft.termId,
            stageId: position.stageId,
            weekday: position.weekday,
            periodTypeId: position.periodTypeId,
            lessonIndex: position.lessonIndex,
            classGradeId: snapshot.gradeIdForClass(id),
          ).full;
          final location =
              '$name · 周${const ['一', '二', '三', '四', '五', '六', '日'][post.weekday - 1]} · 第${position.lessonIndex}节';
          if (slot != null && !slot.allowsSupervision) {
            errors.add('$location：已有免任课「${slot.label}」');
          }
          if (prior.any(position.overlaps)) {
            errors.add('$location：带班岗位重复覆盖');
          }
          prior.add(position);
          final conflict = snapshot.existingItems
              .where(
                (item) =>
                    item.classId == id &&
                    item.position != null &&
                    position.overlaps(
                      withRoutineClock(snapshot, item.position!),
                    ),
              )
              .firstOrNull;
          if (conflict != null) {
            final subject =
                snapshot.subjects
                    .where((item) => item.id == conflict.subjectId)
                    .firstOrNull
                    ?.name ??
                conflict.subjectId;
            errors.add('$location：已有正课「$subject」');
          }
        }
      }
    }
    return errors.toList();
  }

  List<SupervisionOccurrence> occurrences(
    SchedulingSnapshot snapshot,
    SupervisionDraft draft,
  ) {
    final classes = {for (final item in snapshot.classes) item.id: item.name};
    final teachers = {
      for (final item in snapshot.teachers) item.id: item.displayName,
    };
    return [
      for (final post in draft.posts)
        if (draft.assignments[post.id] case final String teacherId)
          for (final position in positions(snapshot, post))
            SupervisionOccurrence(
              post: post,
              teacherId: teacherId,
              position: position,
              teacherName: teachers[teacherId] ?? teacherId,
              classNames: [for (final id in post.classIds) classes[id] ?? id],
            ),
    ];
  }
}
