import type { FreeSlot, StageRoutine } from './models.ts';
import type { ScheduleData } from './scheduling.ts';
import type {
  SchedulePosition,
  SupervisionDraft,
  SupervisionOccurrence,
  SupervisionPost,
} from './supervision.ts';
import { overlaps, poolIdForPost, SUPERVISION_BASE_POOL_ID } from './supervision.ts';

const WEEKDAYS = ['一', '二', '三', '四', '五', '六', '日'];

export function isSupervisionAllowedInSlot(freeSlot?: FreeSlot | null): boolean {
  if (!freeSlot) return true;
  return freeSlot.label !== '无课' && freeSlot.label !== '不上课';
}

export function resolveFreeSlotForClass(
  freeSlots: FreeSlot[],
  termId: string,
  stageId: string,
  gradeId: string | undefined,
  classId: string,
  weekday: number,
  periodTypeId: string,
  lessonIndex: number
): FreeSlot | null {
  let highestRank = -1;
  let bestSlot: FreeSlot | null = null;

  for (const slot of freeSlots) {
    if (
      slot.stageId !== stageId ||
      slot.weekday !== weekday ||
      slot.periodTypeId !== periodTypeId ||
      slot.lessonIndex !== lessonIndex
    ) {
      continue;
    }

    let rank = -1;
    if (slot.scopeType === 'class' && slot.scopeId === classId) {
      rank = 4;
    } else if (slot.scopeType === 'grade' && gradeId && slot.scopeId === gradeId) {
      rank = 3;
    } else if (slot.scopeType === 'stage' && slot.scopeId === stageId) {
      rank = 2;
    } else if (slot.scopeType === 'school' && slot.scopeId === termId) {
      rank = 1;
    }

    if (rank > highestRank) {
      highestRank = rank;
      bestSlot = slot;
    }
  }

  return bestSlot;
}

export function effectiveLessonCount(
  routine: StageRoutine,
  periodTypeId: string,
  weekday: number
): number {
  const override = routine.dailyOverrides.find(
    (row) => row.weekday === weekday && row.periodTypeId === periodTypeId
  );
  if (override != null) return override.lessonCount;
  const period = routine.periodTypes.find((p) => p.id === periodTypeId);
  return period?.defaultLessonCount ?? 0;
}

export function withRoutineClock(
  snapshot: ScheduleData,
  position: SchedulePosition
): SchedulePosition {
  if (position.startMinute != null && position.endMinute != null) {
    return position;
  }
  const routine = snapshot.routines.find((r) => r.stageId === position.stageId);
  if (!routine) return position;
  const time = routine.lessonTimes.find(
    (t) => t.periodTypeId === position.periodTypeId && t.lessonIndex === position.lessonIndex
  );
  if (!time) return position;
  return {
    ...position,
    startMinute: time.startMinute,
    endMinute: time.endMinute,
  };
}

export function positions(
  snapshot: ScheduleData,
  post: SupervisionPost
): SchedulePosition[] {
  return post.lessonIndices.map((index) =>
    withRoutineClock(snapshot, {
      stageId: post.stageId,
      weekday: post.weekday,
      periodTypeId: post.periodTypeId,
      lessonIndex: index,
    })
  );
}

export function postErrors(
  snapshot: ScheduleData,
  draft: SupervisionDraft
): string[] {
  const errors = new Set<string>();
  const postIds = new Set<string>();
  const occupied = new Map<string, SchedulePosition[]>();
  const classNames = new Map<string, string>();
  const classToGrade = new Map<string, string>();
  const classToStage = new Map<string, string>();

  const grades = new Map(snapshot.grades.map((g) => [g.id, g]));
  for (const c of snapshot.classes) {
    classNames.set(c.id, c.name);
    classToGrade.set(c.id, c.gradeId);
    const grade = grades.get(c.gradeId);
    if (grade) {
      classToStage.set(c.id, grade.stageId);
    }
  }

  const subjectMap = new Map(snapshot.subjects.map((s) => [s.id, s.name]));

  for (const post of draft.posts) {
    const title = post.groupName.trim() ? post.groupName : post.name;
    if (postIds.has(post.id)) {
      errors.add(`岗位 ${title} 重复`);
    }
    postIds.add(post.id);

    const poolId = poolIdForPost(draft, post);
    if (
      poolId !== SUPERVISION_BASE_POOL_ID &&
      !draft.teacherPools.some((p) => p.id === poolId)
    ) {
      errors.add(`${title}：候选池已不存在，请重新设置`);
    }

    if (post.targetSubjectIds && post.targetSubjectIds.length > 0) {
      if (post.targetSubjectIds.some((id) => !subjectMap.has(id))) {
        errors.add(`${title}：目标学科已不存在，请重新设置`);
      }
    }

    if (!post.name.trim()) {
      errors.add('请填写活动名称');
    }

    if (
      post.classIds.length === 0 ||
      new Set(post.classIds).size !== post.classIds.length ||
      post.classIds.some((id) => classToStage.get(id) !== post.stageId)
    ) {
      errors.add(`${title}：请选择同一学段内有效且不重复的班级`);
    }

    if (post.classIds.length > 1 && (!post.groupName.trim() || !post.location.trim())) {
      errors.add(`${title}：实际合班须填写组名和地点`);
    }

    const routine = snapshot.routines.find((r) => r.stageId === post.stageId);
    const teachingDays =
      routine?.teachingDays.filter((d) => d.isTeachingDay).map((d) => d.weekday) ?? [];
    if (
      !routine ||
      !teachingDays.includes(post.weekday) ||
      !routine.periodTypes.some((p) => p.id === post.periodTypeId)
    ) {
      errors.add(`${title}：星期或时段已不存在`);
      continue;
    }

    const count = effectiveLessonCount(routine, post.periodTypeId, post.weekday);
    const indices = post.lessonIndices;
    const isConsecutive = indices.every((idx, i) => i === 0 || idx === indices[i - 1] + 1);

    if (
      indices.length === 0 ||
      indices.some((idx) => idx < 1 || idx > count) ||
      !isConsecutive
    ) {
      errors.add(`${title}：节次不存在或连续带班包含不相邻节次`);
      continue;
    }

    const postPositions = positions(snapshot, post);

    for (const classId of post.classIds) {
      const name = classNames.get(classId) ?? classId;
      const prior = occupied.get(classId) ?? [];
      if (!occupied.has(classId)) {
        occupied.set(classId, prior);
      }

      for (const position of postPositions) {
        const slot = resolveFreeSlotForClass(
          snapshot.freeSlots,
          draft.termId,
          position.stageId,
          classToGrade.get(classId),
          classId,
          position.weekday,
          position.periodTypeId,
          position.lessonIndex
        );

        const location = `${name} · 周${WEEKDAYS[post.weekday - 1] ?? post.weekday} · 第${position.lessonIndex}节`;

        if (slot && !isSupervisionAllowedInSlot(slot)) {
          errors.add(`${location}：已有免任课「${slot.label}」`);
        }

        if (prior.some((p) => overlaps(position, p))) {
          errors.add(`${location}：带班岗位重复覆盖`);
        }
        prior.push(position);

        // Check against existing regular curriculum courses (ScheduleItem)
        const conflict = snapshot.items.find((item) => {
          if (item.classId !== classId) return false;
          if (
            item.weekday === null ||
            item.periodTypeId === null ||
            item.lessonIndex === null
          ) {
            return false;
          }
          const itemPos = withRoutineClock(snapshot, {
            stageId: item.stageId ?? post.stageId,
            weekday: item.weekday,
            periodTypeId: item.periodTypeId,
            lessonIndex: item.lessonIndex,
          });
          return overlaps(position, itemPos);
        });

        if (conflict) {
          const subject = subjectMap.get(conflict.subjectId) ?? conflict.subjectId;
          errors.add(`${location}：已有正课「${subject}」`);
        }
      }
    }
  }

  return [...errors];
}

export function occurrences(
  snapshot: ScheduleData,
  draft: SupervisionDraft
): SupervisionOccurrence[] {
  const classes = new Map(snapshot.classes.map((c) => [c.id, c.name]));
  const teachers = new Map(snapshot.teachers.map((t) => [t.id, t.name]));
  const list: SupervisionOccurrence[] = [];

  for (const post of draft.posts) {
    const teacherId = draft.assignments[post.id];
    if (!teacherId) continue;
    const postPositions = positions(snapshot, post);
    for (const position of postPositions) {
      list.push({
        post,
        teacherId,
        teacherName: teachers.get(teacherId) ?? teacherId,
        classNames: post.classIds.map((id) => classes.get(id) ?? id),
        position,
        startMinute: position.startMinute,
        endMinute: position.endMinute,
      });
    }
  }

  return list;
}
