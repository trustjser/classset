import type {
  AcademicTerm, ClassGroup, FreeSlot, GradeGroup, PublicRoom, ScheduleCondition, ScheduleItem,
  ScheduleLock, SchedulePreferences, SchoolStage, StageRoutine, Subject, SubjectLessonConstraint,
  SubjectPairing, SubjectParallelLimit, SubjectPreset, SubjectRequirement, SubjectRoomAssignment,
  Teacher, TeacherAssignment, TeacherGroupMember, TeacherGroupPreset, TeacherPreset, WeekMode,
} from './models';

export interface ScheduleSlot {
  stageId: string;
  weekday: number;
  periodTypeId: string;
  lessonIndex: number;
  startMinute: number | null;
  endMinute: number | null;
  order: number;
  label: string;
  periodName: string;
}

export interface DutyOccurrence {
  teacherId: string;
  teacherName: string;
  weekModes?: WeekMode[];
  classNames: string[];
  post: { id: string; name: string; classIds: string[] };
  position: Omit<ScheduleSlot, 'order' | 'label' | 'periodName'>;
}

export interface ScheduleData {
  term: AcademicTerm;
  stages: SchoolStage[];
  grades: GradeGroup[];
  classes: ClassGroup[];
  routines: StageRoutine[];
  subjects: Subject[];
  teachers: Teacher[];
  assignments: TeacherAssignment[];
  requirements: SubjectRequirement[];
  items: ScheduleItem[];
  locks: ScheduleLock[];
  freeSlots: FreeSlot[];
  subjectPresets: SubjectPreset[];
  teacherPresets: TeacherPreset[];
  teacherGroupPresets: TeacherGroupPreset[];
  teacherGroupMembers: TeacherGroupMember[];
  pairings: SubjectPairing[];
  lessonConstraints: SubjectLessonConstraint[];
  rooms: PublicRoom[];
  roomAssignments: SubjectRoomAssignment[];
  parallelLimits: SubjectParallelLimit[];
  conditions: ScheduleCondition[];
  preferences: SchedulePreferences;
  supervision: DutyOccurrence[];
  visibleSupervision: DutyOccurrence[];
}

export const defaultSchedulePreferences = (termId: string): SchedulePreferences => ({
  termId, strength: 'normal', progressConsistency: 'prefer', teacherDistribution: 'indifferent',
  lunchProtection: false, consecutivePolicy: 'preferSeparate', detectProgressConsistency: true,
});

type Position = Pick<ScheduleSlot, 'stageId' | 'weekday' | 'periodTypeId' | 'lessonIndex'>;
export const slotKey = (slot: Position) => [slot.stageId, slot.weekday, slot.periodTypeId, slot.lessonIndex].join(':');
export const occursInWeek = (mode: WeekMode, week: WeekMode) => week === 'weekly' || mode === 'weekly' || mode === week;
const weeksFor = (mode: WeekMode): WeekMode[] => mode === 'weekly' ? ['odd', 'even'] : [mode];

export function groupBy<T, K>(items: T[], key: (item: T) => K): Map<K, T[]> {
  const groups = new Map<K, T[]>();
  for (const item of items) {
    const group = key(item);
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group)!.push(item);
  }
  return groups;
}

export function createScheduleContext(data: ScheduleData) {
  const grades = new Map(data.grades.map((grade) => [grade.id, grade]));
  const classes = new Map(data.classes.map((schoolClass) => [schoolClass.id, schoolClass]));
  const stageForClass = (id: string) => grades.get(classes.get(id)?.gradeId ?? '')?.stageId;
  const slotsByStage = new Map<string, ScheduleSlot[]>();
  for (const routine of data.routines) {
    const slots: ScheduleSlot[] = [];
    for (const day of routine.teachingDays.filter((day) => day.isTeachingDay).sort((a, b) => a.weekday - b.weekday)) {
      let order = 0;
      for (const period of [...routine.periodTypes].sort((a, b) => a.sortOrder - b.sortOrder)) {
        const count = routine.dailyOverrides.find((row) => row.weekday === day.weekday && row.periodTypeId === period.id)?.lessonCount ?? period.defaultLessonCount;
        for (let index = 1; index <= count; index++) {
          const time = routine.lessonTimes.find((row) => row.periodTypeId === period.id && row.lessonIndex === index);
          slots.push({ stageId: routine.stageId, weekday: day.weekday, periodTypeId: period.id,
            lessonIndex: index, startMinute: time?.startMinute ?? null, endMinute: time?.endMinute ?? null,
            order: ++order, label: time?.label ?? `第${index}节`, periodName: period.name });
        }
      }
    }
    slotsByStage.set(routine.stageId, slots);
  }
  return {
    data, grades, classes, stageForClass, slotsByStage,
    slots: new Map([...slotsByStage.values()].flat().map((slot) => [slotKey(slot), slot])),
    itemsByDay: groupBy(data.items, (item) => item.weekday),
    itemsByClass: groupBy(data.items, (item) => item.classId),
    meetings: groupBy(data.items.filter((item) => item.meetingId), (item) => item.meetingId),
    subjects: new Map(data.subjects.map((subject) => [subject.id, subject.name])),
    teachers: new Map(data.teachers.map((teacher) => [teacher.id, [teacher.name, teacher.displayQualifier].filter(Boolean).join(' · ')])),
    groups: groupBy(data.teacherGroupMembers, (row) => row.teacherId),
    rooms: new Map(data.rooms.map((room) => [room.id, room])),
    locks: new Set(data.locks.map((lock) => `${lock.scope}:${lock.targetId}`)),
  };
}
export type ScheduleContext = ReturnType<typeof createScheduleContext>;

export function positionOf(context: ScheduleContext, item: ScheduleItem) {
  return item.weekday === null ? undefined : context.slots.get(slotKey(item as Position));
}

export function timesOverlap(a: DutyOccurrence['position'], b: DutyOccurrence['position']) {
  if (a.weekday !== b.weekday) return false;
  if (slotKey(a) === slotKey(b)) return true;
  return a.startMinute !== null && a.endMinute !== null && b.startMinute !== null && b.endMinute !== null &&
    a.startMinute < b.endMinute && b.startMinute < a.endMinute;
}

const scopeOrder = { school: 0, stage: 1, grade: 2, class: 3 };
function appliesTo(context: ScheduleContext, item: Pick<ScheduleItem, 'classId'>, row: { scopeType: keyof typeof scopeOrder; scopeId: string | null; stageId: string }) {
  if (row.stageId !== context.stageForClass(item.classId)) return false;
  switch (row.scopeType) {
    case 'school': return true;
    case 'stage': return row.scopeId === row.stageId;
    case 'grade': return row.scopeId === context.classes.get(item.classId)?.gradeId;
    case 'class': return row.scopeId === item.classId;
  }
}

function scoped<T extends Parameters<typeof appliesTo>[2]>(context: ScheduleContext, item: Pick<ScheduleItem, 'classId'>, rows: T[]) {
  return rows.filter((row) => appliesTo(context, item, row)).sort((a, b) => scopeOrder[b.scopeType] - scopeOrder[a.scopeType])[0];
}

const sameSlot = (row: Omit<Position, 'stageId'>, slot: ScheduleSlot) =>
  row.weekday === slot.weekday && row.periodTypeId === slot.periodTypeId && row.lessonIndex === slot.lessonIndex;

export function freeSlotFor(context: ScheduleContext, classId: string, slot: ScheduleSlot) {
  return scoped(context, { classId }, context.data.freeSlots.filter((row) => sameSlot(row, slot)));
}

export function roomFor(context: ScheduleContext, item: ScheduleItem) {
  return scoped(context, item, context.data.roomAssignments.filter((row) => row.subjectId === item.subjectId))?.roomId;
}

const lessonName = (context: ScheduleContext, item: ScheduleItem) => context.subjects.get(item.subjectId) ?? '课程';
const teacherName = (context: ScheduleContext, item: ScheduleItem) => context.teachers.get(item.teacherId ?? '') ?? '未分配教师';
const className = (context: ScheduleContext, item: ScheduleItem) => context.classes.get(item.classId)?.name ?? '班级';
const weekModeName = (mode: ScheduleItem['weekMode']) => mode === 'weekly' ? '每周' : mode === 'odd' ? '单周' : '双周';
const meetingKey = (item: ScheduleItem) => item.meetingId ?? item.id;
const teachingMeetingKey = (item: ScheduleItem) => item.combinedGroupId && item.meetingId
  ? `${item.combinedGroupId}:${item.meetingId}` : item.id;
const adjacent = (a: ScheduleSlot, b: ScheduleSlot) => a.stageId === b.stageId && a.weekday === b.weekday && Math.abs(a.order - b.order) === 1;

function presetsAt(context: ScheduleContext, item: ScheduleItem, slot: ScheduleSlot, week: WeekMode) {
  const subject = scoped(context, item, context.data.subjectPresets.filter((row) => row.subjectId === item.subjectId && sameSlot(row, slot)));
  const filterWeek = (row: { weekMode: WeekMode } & Omit<Position, 'stageId'>) => occursInWeek(row.weekMode, week) && sameSlot(row, slot);
  const ordered = <T extends { weekMode: WeekMode }>(rows: T[]) => rows.sort((a, b) => Number(b.weekMode === week) - Number(a.weekMode === week));
  const teacher = scoped(context, item, ordered(context.data.teacherPresets.filter((row) => row.teacherId === item.teacherId && filterWeek(row))));
  const groups = context.groups.get(item.teacherId ?? '') ?? [];
  const group = groups.map(({ groupId }) => scoped(context, item, ordered(context.data.teacherGroupPresets.filter(
    (row) => row.groupId === groupId && filterWeek(row)))));
  return [subject?.value, ...(teacher?.value && teacher.value !== 'auto' ? [teacher.value] : group.map((row) => row?.value))];
}

export function isLessonLocked(context: ScheduleContext, item: ScheduleItem) {
  return item.weekday !== null && (context.locks.has(`class:${item.classId}`) || context.locks.has(`teacher:${item.teacherId}`));
}

function withPosition(item: ScheduleItem, slot: ScheduleSlot | null): ScheduleItem {
  return { ...item, stageId: slot?.stageId ?? null, weekday: slot?.weekday ?? null,
    periodTypeId: slot?.periodTypeId ?? null, lessonIndex: slot?.lessonIndex ?? null };
}

function pairs(slots: ScheduleSlot[]) {
  const ordered = [...slots].sort((a, b) => a.weekday - b.weekday || a.order - b.order);
  let count = 0;
  for (let i = 1; i < ordered.length; i++) {
    if (adjacent(ordered[i - 1], ordered[i])) {
      count++;
      i++;
    }
  }
  return count;
}

function overlappingDuty(context: ScheduleContext, item: ScheduleItem, slot: ScheduleSlot) {
  return context.data.supervision.find((row) => {
    const p = row.position;
    return (!row.weekModes || row.weekModes.some((mode) => occursInWeek(mode, item.weekMode))) &&
      (row.teacherId === item.teacherId || row.post.classIds.includes(item.classId)) &&
      (timesOverlap(p, slot) || (row.teacherId === item.teacherId && p.weekday === slot.weekday && p.stageId !== slot.stageId &&
        [p.startMinute, p.endMinute, slot.startMinute, slot.endMinute].some((minute) => minute === null)));
  });
}

export function validateScheduleSupervision(data: ScheduleData) {
  const context = createScheduleContext(data);
  for (const duty of [...data.supervision, ...data.visibleSupervision]) {
    if (!context.teachers.has(duty.teacherId)) return `带班安排「${duty.post.name}」的教师已删除`;
    if (!context.slots.has(slotKey(duty.position)) || duty.post.classIds.some((id) => !context.classes.has(id))) {
      return `带班安排「${duty.post.name}」的班级或课节已变更`;
    }
  }
  for (const item of data.items) {
    const slot = positionOf(context, item);
    const duty = slot && overlappingDuty(context, item, slot);
    if (duty) return `${className(context, item)}的${lessonName(context, item)}与「${duty.post.name}」带班冲突`;
  }
}

function lessonLimit(context: ScheduleContext, item: ScheduleItem, rows: SubjectLessonConstraint[],
  weekday: number | null, field: keyof Pick<SubjectLessonConstraint, 'minimumDailyLessons' | 'maximumDailyLessons' |
    'minimumDailyConsecutivePairs' | 'maximumDailyConsecutivePairs' | 'minimumWeeklyConsecutivePairs' | 'maximumWeeklyConsecutivePairs'>) {
  return rows.filter((row) => appliesTo(context, item, row) && (row.weekday === null || row.weekday === weekday) && row[field] !== null)
    .sort((a, b) => scopeOrder[b.scopeType] - scopeOrder[a.scopeType] ||
      Number(b.weekday !== null) - Number(a.weekday !== null))[0]?.[field];
}

function hardBlock(context: ScheduleContext, item: ScheduleItem, changes: ScheduleItem[], ignored: Set<string>): string | undefined {
  const slot = positionOf(context, item);
  if (!slot || slot.stageId !== context.stageForClass(item.classId)) return '作息中没有这个课节';
  if (!item.teacherId) return `${className(context, item)}的${lessonName(context, item)}尚未指定教师`;
  const data = context.data;
  const free = freeSlotFor(context, item.classId, slot);
  if (free) return `${className(context, item)}此节为免任课${free.label ? `（${free.label}）` : ''}`;
  const duty = overlappingDuty(context, item, slot);
  if (duty) return `${duty.teacherName || teacherName(context, item)}此节已有带班安排「${duty.post.name}」`;
  const day = [...(context.itemsByDay.get(slot.weekday) ?? []), ...changes.filter((row) => row.weekday === slot.weekday)]
    .filter((row) => !ignored.has(row.id) || changes.includes(row));
  const roomId = roomFor(context, item);
  const room = roomId ? context.rooms.get(roomId) : undefined;
  if (roomId && !room) return '该科目配置的公共场室已不存在';
  const parallel = scoped(context, item, data.parallelLimits.filter((row) => row.subjectId === item.subjectId));
  const limits = data.lessonConstraints.filter((row) => row.subjectId === item.subjectId && appliesTo(context, item, row));

  for (const week of weeksFor(item.weekMode)) {
    if (presetsAt(context, item, slot, week).includes('forbid')) return `${lessonName(context, item)}或${teacherName(context, item)}在此节设为禁排`;
    const others = day.filter((row) => row.id !== item.id && occursInWeek(row.weekMode, week));
    const overlaps = others.filter((row) => {
      const p = positionOf(context, row);
      return p && timesOverlap(p, slot);
    });
    const classConflict = overlaps.find((row) => row.classId === item.classId);
    if (classConflict) return `${className(context, item)}此节已有${lessonName(context, classConflict)}`;
    const teacherConflict = overlaps.find((row) => row.teacherId === item.teacherId && teachingMeetingKey(row) !== teachingMeetingKey(item));
    if (teacherConflict) return `${teacherName(context, item)}在 ${className(context, teacherConflict)} 已有${lessonName(context, teacherConflict)}课`;
    if (room && new Set([item, ...overlaps.filter((row) => roomFor(context, row) === roomId)].map((row) => row.classId)).size > room.roomCount * room.capacityPerRoom) {
      return `公共场室「${room.name}」容量已满`;
    }
    const parallelRows = [item, ...overlaps].filter((row) => row.subjectId === item.subjectId);
    for (const row of parallelRows) {
      const limit = row === item ? parallel : scoped(context, row, data.parallelLimits.filter((rule) => rule.subjectId === row.subjectId));
      if (limit && new Set(parallelRows.map(teachingMeetingKey)).size > limit.maxParallelLessons) return `${lessonName(context, item)}同一时段最多并行 ${limit.maxParallelLessons} 节`;
    }
    const sameSubject = others.filter((row) => row.classId === item.classId && row.subjectId === item.subjectId);
    const daySlots = [slot, ...sameSubject.flatMap((row) => positionOf(context, row) ?? [])];
    const maxDayLessons = lessonLimit(context, item, limits, slot.weekday, 'maximumDailyLessons');
    const maxDayPairs = lessonLimit(context, item, limits, slot.weekday, 'maximumDailyConsecutivePairs');
    const maxWeekPairs = lessonLimit(context, item, limits, null, 'maximumWeeklyConsecutivePairs');
    if (maxDayLessons != null && daySlots.length > maxDayLessons) return '超过该科目的每天节数上限';
    if (maxDayPairs != null && pairs(daySlots) > maxDayPairs) return '超过该科目的每天连堂上限';
    if (maxWeekPairs != null) {
      const otherDays = [...(context.itemsByClass.get(item.classId) ?? []), ...changes.filter((row) => row.classId === item.classId)]
        .filter((row) => row.weekday !== slot.weekday && row.subjectId === item.subjectId && occursInWeek(row.weekMode, week) &&
          (!ignored.has(row.id) || changes.includes(row))).flatMap((row) => positionOf(context, row) ?? []);
      if (pairs([...daySlots, ...otherDays]) > maxWeekPairs) return '超过该科目的每周连堂上限';
    }
    const forcedPair = (lessonLimit(context, item, limits, slot.weekday, 'minimumDailyConsecutivePairs') ?? 0) > 0 ||
      (lessonLimit(context, item, limits, null, 'minimumWeeklyConsecutivePairs') ?? 0) > 0;
    if (!forcedPair && data.preferences.consecutivePolicy === 'requireSeparate' && daySlots.some((p) => adjacent(p, slot))) return '该科目设置了硬性不连堂';
    if (data.preferences.lunchProtection) {
      const slots: ScheduleSlot[] = context.slotsByStage.get(slot.stageId)!.filter((row) => row.weekday === slot.weekday);
      const ends = [slots.filter((row) => row.periodName.includes('上午')).at(-1), slots.find((row) => row.periodName.includes('下午'))];
      if (ends.every(Boolean) && ends.includes(slot) && others.some((row) => row.teacherId === item.teacherId && ends.includes(positionOf(context, row)))) {
        return `${teacherName(context, item)}需要保留午间休息`;
      }
    }
    for (const rule of data.conditions) {
      if (rule.weekday !== null && rule.weekday !== slot.weekday) continue;
      const label = rule.name || '自定义硬条件';
      const matches = (row: ScheduleItem) => rule.targetKind === 'teacher' ? row.teacherId === rule.targetId : row.classId === item.classId && row.subjectId === rule.targetId;
      if ((rule.kind === 'dailyLimit' || rule.kind === 'periodLimit') && matches(item)) {
        if (rule.kind === 'periodLimit' && rule.periodTypeId !== item.periodTypeId) continue;
        const cap = rule.exactCount ?? rule.maxCount;
        const candidates = rule.kind === 'periodLimit' && rule.weekday === null
          ? [...data.items.filter((row) => !ignored.has(row.id)), ...changes].filter((row) =>
            row.id !== item.id && row.weekday !== null && occursInWeek(row.weekMode, week))
          : others;
        if (cap !== null && new Set([item, ...candidates.filter((row) => matches(row) && (rule.kind !== 'periodLimit' || row.periodTypeId === rule.periodTypeId))].map(teachingMeetingKey)).size > cap) return `${label}：节数超过 ${cap}`;
      }
      if (rule.kind === 'teacherMutualExclusion' && overlaps.some((row) =>
        (item.teacherId === rule.targetId && row.teacherId === rule.otherId) || (item.teacherId === rule.otherId && row.teacherId === rule.targetId))) return `${label}：两位教师不能同时任课`;
      if (rule.kind === 'subjectMutualExclusion' && others.some((row) => row.classId === item.classId &&
        ((item.subjectId === rule.targetId && row.subjectId === rule.otherId) || (item.subjectId === rule.otherId && row.subjectId === rule.targetId)))) return `${label}：两科不能安排在同一天`;
      if (rule.kind === 'forbiddenAdjacency' && others.some((row) => {
        const p = positionOf(context, row);
        return row.classId === item.classId && p && adjacent(p, slot) &&
          (p.order > slot.order ? item.subjectId === rule.targetId && row.subjectId === rule.otherId : row.subjectId === rule.targetId && item.subjectId === rule.otherId);
      })) return `${label}：禁止科目相邻`;
    }
  }
}

function relatedItems(context: ScheduleContext, source: ScheduleItem) {
  const meeting = source.meetingId ? context.meetings.get(source.meetingId) ?? [source] : [source];
  const slot = positionOf(context, source);
  if (!slot || source.weekMode === 'weekly') return meeting;
  const counterparts = meeting.flatMap((item) => {
    const pairing = context.data.pairings.find((row) => row.classId === item.classId &&
      (item.weekMode === 'odd' ? row.oddSubjectId : row.evenSubjectId) === item.subjectId);
    return pairing ? (context.itemsByClass.get(item.classId) ?? []).filter((row) => row.weekMode !== 'weekly' && row.weekMode !== item.weekMode &&
      row.subjectId === (item.weekMode === 'odd' ? pairing.evenSubjectId : pairing.oddSubjectId) && positionOf(context, row) === positionOf(context, item))
      .flatMap((row) => context.meetings.get(row.meetingId) ?? [row]) : [];
  });
  return [...new Set([...meeting, ...counterparts])];
}

function manualMoveItems(context: ScheduleContext, source: ScheduleItem) {
  const related = relatedItems(context, source);
  const slot = positionOf(context, source);
  if (!slot || source.weekMode === 'weekly') return related;

  const alternatingPeers = (context.itemsByClass.get(source.classId) ?? [])
    .filter((row) => row.weekMode !== 'weekly' && row.weekMode !== source.weekMode && positionOf(context, row) === slot)
    .flatMap((row) => relatedItems(context, row));
  return [...new Set([...related, ...alternatingPeers])];
}

function matchingSlot(context: ScheduleContext, item: ScheduleItem, target: ScheduleSlot) {
  const stage = context.stageForClass(item.classId);
  if (stage === target.stageId) return target;
  if (!stage || target.startMinute === null || target.endMinute === null) return undefined;
  return context.slotsByStage.get(stage)?.find((slot) => slot.weekday === target.weekday && slot.startMinute === target.startMinute && slot.endMinute === target.endMinute);
}

function preferenceScore(context: ScheduleContext, item: ScheduleItem, slot: ScheduleSlot, ignored = new Set<string>(), changes: ScheduleItem[] = []) {
  const values = weeksFor(item.weekMode).flatMap((week) => presetsAt(context, item, slot, week));
  const day = [...(context.itemsByDay.get(slot.weekday) ?? []), ...changes]
    .filter((row) => row.id !== item.id && (!ignored.has(row.id) || changes.includes(row)) && occursInWeek(row.weekMode, item.weekMode));
  const sameSubject = day.filter((row) => row.subjectId === item.subjectId && row.classId === item.classId);
  const nearby = sameSubject.filter((row) => {
    const p = positionOf(context, row);
    return p && adjacent(p, slot);
  }).length;
  const teacherDay = day.filter((row) => row.teacherId === item.teacherId).length;
  const preferences = context.data.preferences;
  const paired = context.data.pairings.some((pairing) => pairing.classId === item.classId &&
    (item.weekMode === 'odd' ? pairing.oddSubjectId : pairing.evenSubjectId) === item.subjectId &&
    (context.itemsByClass.get(item.classId) ?? []).some((row) => row.weekMode !== 'weekly' && row.weekMode !== item.weekMode &&
      row.subjectId === (item.weekMode === 'odd' ? pairing.evenSubjectId : pairing.oddSubjectId) && positionOf(context, row) === slot));
  const grade = context.classes.get(item.classId)?.gradeId;
  const progress = day.some((row) => row.classId !== item.classId && context.classes.get(row.classId)?.gradeId === grade &&
    row.subjectId === item.subjectId);
  const forcedPair = context.data.lessonConstraints.some((rule) => rule.subjectId === item.subjectId && appliesTo(context, item, rule) &&
    ((rule.minimumWeeklyConsecutivePairs ?? 0) > 0 || (rule.minimumDailyConsecutivePairs ?? 0) > 0));
  return values.filter((value) => value === 'must').length * 1000 + values.filter((value) => value === 'prefer').length * 30 +
    nearby * (forcedPair ? 24 : preferences.consecutivePolicy === 'preferTogether' ? 8 : -7) -
    sameSubject.length * 2 + (paired ? 45 : 0) + (progress ? 4 : 0) +
    teacherDay * (preferences.teacherDistribution === 'spread' ? -3 : preferences.teacherDistribution === 'concentrate' ? 3 : 0);
}

export interface PlacementPreview {
  status: 'available' | 'swap' | 'caution' | 'blocked';
  reason: string;
  preferenceLoss?: boolean;
  items?: ScheduleItem[];
  changed?: ScheduleItem[];
}

export function previewPlacement(
  context: ScheduleContext, source: ScheduleItem, requestedTarget: ScheduleSlot | null, allowSwap = true, materialize = true,
  swapWithItem?: ScheduleItem,
): PlacementPreview {
  const blocked = (reason: string): PlacementPreview => ({ status: 'blocked', reason });
  const target = requestedTarget ? context.slots.get(slotKey(requestedTarget)) ?? null : null;
  if (requestedTarget && !target) return blocked('目标节次不在当前作息中');
  const moving = manualMoveItems(context, source);
  if (moving.some((item) => isLessonLocked(context, item) &&
    (!target || matchingSlot(context, item, target) !== positionOf(context, item)))) return blocked('该课节涉及已锁定的班级或教师');
  if (!target && source.weekday === null) return blocked('课程已在暂放区');
  const origin = positionOf(context, source);
  if (target && origin && matchingSlot(context, source, target) === origin) return blocked('课程已在这个位置');
  const replaced = new Map<string, ScheduleItem>();
  const changes: ScheduleItem[] = [];
  const ignored = new Set(moving.map((item) => item.id));
  const explicit = swapWithItem && positionOf(context, swapWithItem) === target && !ignored.has(swapWithItem.id) &&
    moving.some((row) => occursInWeek(row.weekMode, swapWithItem.weekMode)) ? swapWithItem : undefined;
  for (const item of moving) {
    const to = target ? matchingSlot(context, item, target) : null;
    if (target && !to) return blocked('合班课在其他学段找不到同一时段');
    if (to) {
      const from = positionOf(context, item);
      const occupants = (context.itemsByClass.get(item.classId) ?? []).filter((row) => !ignored.has(row.id) &&
        occursInWeek(row.weekMode, item.weekMode) && positionOf(context, row) === to);
      if (occupants.length && (!allowSwap || !from)) {
        const lessons = occupants.map((row) => `${lessonName(context, row)}（${weekModeName(row.weekMode)}）`).join('、');
        return blocked(`${className(context, item)}此节已有${lessons}`);
      }
      if (explicit && item.id === source.id && !occupants.some((row) => row.id === explicit.id)) {
        if (!allowSwap || !from) {
          return blocked(`${teacherName(context, explicit)}此节已有${className(context, explicit)}的${lessonName(context, explicit)}（${weekModeName(explicit.weekMode)}）`);
        }
        occupants.push(explicit);
      }
      for (const occupant of occupants) {
        for (const partner of relatedItems(context, occupant)) {
          if (isLessonLocked(context, partner)) return blocked('目标课节涉及已锁定的班级或教师');
          const swapTo = matchingSlot(context, partner, from!);
          if (!swapTo) return blocked('互换涉及的合班课找不到同一时段');
          const existing = replaced.get(partner.id);
          if (existing && positionOf(context, existing) !== swapTo) return blocked('合班课需要同时互换到同一时段');
          replaced.set(partner.id, withPosition(partner, swapTo));
        }
      }
    }
    changes.push(withPosition(item, to ?? null));
  }
  if (explicit && new Set([...replaced.values()].map(meetingKey)).size > 1) {
    return blocked('目标节次涉及多个课组，请先腾出目标节次');
  }
  changes.push(...replaced.values());
  for (const item of replaced.values()) ignored.add(item.id);
  let scoreLoss = false;
  for (const item of changes) {
    const slot = positionOf(context, item);
    if (slot) {
      const reason = hardBlock(context, item, changes, ignored);
      if (reason) return blocked(reason);
    }
    const before = (context.itemsByClass.get(item.classId) ?? []).find((row) => row.id === item.id);
    const oldSlot = before && positionOf(context, before);
    if (oldSlot) {
      const oldMust = weeksFor(item.weekMode).some((week) => presetsAt(context, item, oldSlot, week).includes('must'));
      if (oldMust && slot !== oldSlot && !changes.some((row) => row.classId === item.classId && row.subjectId === item.subjectId &&
        row.teacherId === item.teacherId && row.weekMode === item.weekMode && positionOf(context, row) === oldSlot)) return blocked('原课节设为必排');
      scoreLoss ||= !!slot && preferenceScore(context, before, oldSlot) > preferenceScore(context, item, slot, ignored, changes);
    }
  }
  const updated = new Map(changes.map((item) => [item.id, item]));
  const aggregate = allowSwap && moving.some((row) => row.weekday !== null) && hasAggregateRequirements(context.data);
  const items = materialize || aggregate ? context.data.items.map((item) => updated.get(item.id) ?? item) : undefined;
  if (aggregate && items) {
    let previous = aggregateIssuesCache.get(context);
    if (!previous) {
      previous = new Set(aggregateScheduleIssues(context));
      aggregateIssuesCache.set(context, previous);
    }
    const next = createScheduleContext({ ...context.data, items });
    const issue = aggregateScheduleIssues(next).find((message) => !previous.has(message));
    if (issue) return blocked(issue);
  }
  return {
    status: replaced.size ? 'swap' : scoreLoss ? 'caution' : 'available',
    reason: replaced.size ? (scoreLoss ? '可以互换，部分排课偏好会受影响' : '可以互换') :
      scoreLoss ? '可以落位，部分排课偏好会受影响' : target ? '可以落位' : '移入暂放区',
    preferenceLoss: scoreLoss,
    items: materialize ? items : undefined,
    changed: changes,
  };
}

export function prepareDemand(data: ScheduleData, classIds: string[], retainPlacements: boolean) {
  const context = createScheduleContext(data);
  const selected = new Set(classIds);
  for (const assignment of data.assignments) {
    if (assignment.combinedLessonGroupId && selected.has(assignment.classId)) {
      data.assignments.filter((row) => row.combinedLessonGroupId === assignment.combinedLessonGroupId).forEach((row) => selected.add(row.classId));
    }
  }
  const prior = groupBy(data.items, (row) => row.assignmentId);
  const usedIds = new Set(data.items.map((row) => row.id));
  const retainLocked = (row: ScheduleItem) => relatedItems(context, row).some((item) => isLessonLocked(context, item));
  const retained = data.items.filter((item) => !selected.has(item.classId));
  const demand: ScheduleItem[] = [];
  for (const assignment of data.assignments) {
    if (!selected.has(assignment.classId)) continue;
    const existing = (prior.get(assignment.id) ?? []).filter((row) => row.classId === assignment.classId)
      .sort((a, b) => Number(retainLocked(b)) - Number(retainLocked(a)) ||
        Number(b.weekday !== null) - Number(a.weekday !== null) ||
        (a.meetingId ?? a.id).localeCompare(b.meetingId ?? b.id, undefined, { numeric: true }));
    for (let index = 0; index < assignment.lessonCount; index++) {
      const old = existing[index];
      const group = assignment.combinedLessonGroupId;
      let id = old?.id ?? `${assignment.id}:lesson:${index + 1}`;
      if (!old) {
        while (usedIds.has(id)) id += ':new';
        usedIds.add(id);
      }
      const item: ScheduleItem = { id, termId: assignment.termId,
        assignmentId: assignment.id, classId: assignment.classId, teacherId: assignment.teacherId, subjectId: assignment.subjectId,
        weekMode: data.term.cycleMode === 'every_week' ? 'weekly' : assignment.weekMode, combinedGroupId: group,
        meetingId: group ? `${group}:meeting:${index + 1}` : null, stageId: null, weekday: null, periodTypeId: null, lessonIndex: null };
      const slot = old && positionOf(context, old);
      demand.push(old && slot && (retainPlacements || retainLocked(old)) ? withPosition(item, slot) : item);
    }
  }
  const groups = groupBy(demand, meetingKey);
  const groupByItem = new Map(demand.map((row) => [row.id, meetingKey(row)]));
  const byClass = groupBy(demand, (row) => row.classId);
  for (const pairing of data.pairings) {
    const rows = byClass.get(pairing.classId) ?? [];
    const odd = rows.filter((row) => row.weekMode === 'odd' && row.subjectId === pairing.oddSubjectId);
    const even = rows.filter((row) => row.weekMode === 'even' && row.subjectId === pairing.evenSubjectId);
    for (let index = 0; index < Math.min(odd.length, even.length); index++) {
      const left = groupByItem.get(odd[index].id)!;
      const right = groupByItem.get(even[index].id)!;
      if (left === right) continue;
      const key = `${pairing.id}:pair:${index + 1}`;
      const rows = [...groups.get(left)!, ...groups.get(right)!];
      groups.delete(left);
      groups.delete(right);
      groups.set(key, rows);
      for (const row of rows) groupByItem.set(row.id, key);
    }
  }
  for (const [key, rows] of groups) {
    if (rows.length < 2) continue;
    for (const row of rows) row.meetingId = key;
  }
  return [...retained, ...demand];
}

export function detectSchedule(data: ScheduleData) {
  const context = createScheduleContext(data);
  const issues = new Set<string>();
  const add = (item: ScheduleItem, message: string) => issues.add(`${className(context, item)} · ${lessonName(context, item)}：${message}`);
  for (const item of data.items) {
    if (item.weekday === null) continue;
    const blocker = hardBlock(context, item, [], new Set());
    if (blocker) add(item, blocker);
  }
  for (const meeting of context.meetings.values()) {
    const reference = meeting.map((row) => positionOf(context, row)).find(Boolean);
    if (reference && meeting.some((row) => {
      const p = positionOf(context, row);
      return !p || matchingSlot(context, row, reference) !== p;
    })) add(meeting[0], '合班课未安排在同一时段');
  }
  return [...new Set([...issues, ...aggregateScheduleIssues(context)])];
}

const aggregateIssuesCache = new WeakMap<ScheduleContext, Set<string>>();

function hasAggregateRequirements(data: ScheduleData) {
  return data.conditions.some((row) => row.minCount !== null || row.exactCount !== null) ||
    data.lessonConstraints.some((row) => row.minimumDailyLessons !== null || row.minimumDailyConsecutivePairs !== null ||
      row.minimumWeeklyConsecutivePairs !== null) ||
    (data.preferences.detectProgressConsistency && data.preferences.progressConsistency === 'require');
}

function aggregateScheduleIssues(context: ScheduleContext) {
  const { data } = context;
  const issues = new Set<string>();
  const add = (item: ScheduleItem, message: string) => issues.add(`${className(context, item)} · ${lessonName(context, item)}：${message}`);
  const demand = prepareDemand(data, data.classes.map((row) => row.id), true);
  const representatives = new Map(demand.map((row) => [`${row.classId}:${row.subjectId}:${row.weekMode}`, row]));
  for (const item of representatives.values()) {
    const allSlots = context.slotsByStage.get(context.stageForClass(item.classId) ?? '') ?? [];
    for (const week of weeksFor(item.weekMode)) {
      const classRows = (context.itemsByClass.get(item.classId) ?? []).filter((row) => occursInWeek(row.weekMode, week) && row.weekday !== null);
      const placed = classRows.filter((row) => row.subjectId === item.subjectId).flatMap((row) => positionOf(context, row) ?? []);
      const relevant = data.lessonConstraints.filter((row) => row.subjectId === item.subjectId);
      for (const weekday of new Set(allSlots.map((slot) => slot.weekday))) {
        const minimum = lessonLimit(context, item, relevant, weekday, 'minimumDailyLessons');
        const minPairs = lessonLimit(context, item, relevant, weekday, 'minimumDailyConsecutivePairs');
        const thatDay = placed.filter((slot) => slot.weekday === weekday);
        if (minimum != null && thatDay.length < minimum) add(item, `星期${weekday}未达到每日最少节数`);
        if (minPairs != null && pairs(thatDay) < minPairs) add(item, `星期${weekday}未达到每日最少连堂数`);
      }
      const weekly = lessonLimit(context, item, relevant, null, 'minimumWeeklyConsecutivePairs');
      if (weekly != null && pairs(placed) < weekly) add(item, '未达到每周最少连堂数');
      for (const slot of allSlots) {
        const values = presetsAt(context, item, slot, week);
        if (values[0] === 'must' && !placed.includes(slot)) add(item, `星期${slot.weekday} ${slot.periodName}${slot.label}尚未满足科目必排`);
      }
    }
  }
  const teachers = groupBy(demand.filter((row) => row.teacherId), (row) => row.teacherId);
  for (const [teacherId, lessons] of teachers) {
    const probes = new Map(lessons.map((row) => [row.classId, row]));
    for (const item of probes.values()) {
      for (const slot of context.slotsByStage.get(context.stageForClass(item.classId) ?? '') ?? []) {
        for (const week of weeksFor(item.weekMode)) {
          if (!presetsAt(context, item, slot, week).slice(1).includes('must')) continue;
          const occupied = (context.itemsByDay.get(slot.weekday) ?? []).some((row) => row.teacherId === teacherId && occursInWeek(row.weekMode, week) && positionOf(context, row) === slot);
          if (!occupied) issues.add(`${teacherName(context, item)}：星期${slot.weekday} ${slot.periodName}${slot.label}尚未满足教师必排`);
        }
      }
    }
  }
  for (const rule of data.conditions) {
    const minimum = rule.exactCount ?? rule.minCount;
    if (minimum === null || !['dailyLimit', 'periodLimit'].includes(rule.kind)) continue;
    const targets = new Map(demand.filter((row) => rule.targetKind === 'teacher' ? row.teacherId === rule.targetId : row.subjectId === rule.targetId)
      .map((row) => [`${rule.targetKind === 'teacher' ? context.stageForClass(row.classId) : row.classId}:${row.weekMode}`, row]));
    for (const item of targets.values()) {
      const slots = context.slotsByStage.get(context.stageForClass(item.classId) ?? '') ?? [];
      const hasPeriod = rule.kind !== 'periodLimit' || slots.some((slot) => slot.periodTypeId === rule.periodTypeId);
      const days = rule.kind === 'periodLimit' && rule.weekday === null && hasPeriod ? [null] :
        [...new Set(slots.filter((slot) => (rule.weekday === null || slot.weekday === rule.weekday) &&
          (rule.kind !== 'periodLimit' || slot.periodTypeId === rule.periodTypeId)).map((slot) => slot.weekday))];
      for (const day of days) for (const week of weeksFor(item.weekMode)) {
        const rows = (day === null ? data.items.filter((row) => row.weekday !== null) : context.itemsByDay.get(day) ?? []).filter((row) => occursInWeek(row.weekMode, week) &&
          (rule.targetKind === 'teacher' ? row.teacherId === rule.targetId : row.subjectId === rule.targetId && row.classId === item.classId) &&
          (rule.kind !== 'periodLimit' || row.periodTypeId === rule.periodTypeId));
        if (new Set(rows.map(teachingMeetingKey)).size < minimum) add(item, `${day ? `星期${day}` : '当前时段'}未达到${rule.name || '自定义条件'}的节数要求`);
      }
    }
  }
  if (data.preferences.detectProgressConsistency && data.preferences.progressConsistency === 'require') {
    for (const week of weeksFor('weekly')) {
      const byGradeSubject = groupBy(demand.filter((row) => occursInWeek(row.weekMode, week)),
        (row) => `${context.classes.get(row.classId)?.gradeId}:${row.subjectId}`);
      for (const sameSubject of byGradeSubject.values()) {
        const byClass = groupBy(sameSubject, (row) => row.classId);
        for (const peers of groupBy([...byClass.values()], (rows) => rows.length).values()) {
          if (peers.length < 2) continue;
          const actual = peers.map(([sample]) => (context.itemsByClass.get(sample.classId) ?? []).filter((row) =>
            row.subjectId === sample.subjectId && row.weekday !== null && occursInWeek(row.weekMode, week)));
          for (let day = 1; day <= 7; day++) {
            const totals = actual.map((rows) => rows.filter((row) => row.weekday! <= day).length);
            if (Math.max(...totals) - Math.min(...totals) > 1) {
              const [sample] = peers[0];
              issues.add(`${context.grades.get(context.classes.get(sample.classId)?.gradeId ?? '')?.name ?? '年级'} · ${lessonName(context, sample)}：星期${day}同级同科进度不同步`);
            }
          }
        }
      }
    }
  }
  return [...issues];
}

export function preflightSchedule(data: ScheduleData, classIds: string[]) {
  const context = createScheduleContext(data);
  const selected = new Set(classIds);
  const assignments = data.assignments.filter((row) => selected.has(row.classId));
  const issues = new Set<string>();
  for (const [classId, rows] of groupBy(assignments, (row) => row.classId)) {
    const slots = context.slotsByStage.get(context.stageForClass(classId) ?? '') ?? [];
    const capacity = slots.filter((slot) => !data.freeSlots.some((row) => appliesTo(context, rows[0], row) && sameSlot(row, slot))).length;
    if (weeksFor('weekly').some((week) => rows.filter((row) => occursInWeek(row.weekMode, week)).reduce((sum, row) => sum + row.lessonCount, 0) > capacity)) {
      issues.add(`${context.classes.get(classId)?.name}的任课节数超过可用课节（${capacity} 节）`);
    }
  }
  for (const row of assignments) if (!row.teacherId) issues.add(`${context.classes.get(row.classId)?.name} · ${context.subjects.get(row.subjectId)}尚未分配教师`);
  for (const schoolClass of data.classes.filter((row) => selected.has(row.id))) {
    const demands = data.requirements.filter((row) => row.gradeId === schoolClass.gradeId && (row.classId === schoolClass.id || row.classId === null));
    const defaults = new Map(demands.filter((row) => row.classId === null).map((row) => [`${row.subjectId}:${row.weekMode}`, row]));
    demands.filter((row) => row.classId !== null).forEach((row) => defaults.set(`${row.subjectId}:${row.weekMode}`, row));
    for (const demand of defaults.values()) {
      const assigned = assignments.filter((row) => row.classId === schoolClass.id && row.subjectId === demand.subjectId && row.weekMode === demand.weekMode)
        .reduce((sum, row) => sum + row.lessonCount, 0);
      if (assigned < demand.lessonCount) issues.add(`${schoolClass.name} · ${context.subjects.get(demand.subjectId)}还有 ${demand.lessonCount - assigned} 节未配置任课`);
    }
  }
  return [...issues];
}

function withScheduleChanges(context: ScheduleContext, changes: ScheduleItem[]): ScheduleContext {
  const replacements = new Map(changes.map((row) => [row.id, row]));
  const items = context.data.items.map((row) => replacements.get(row.id) ?? row);
  return {
    ...context, data: { ...context.data, items },
    itemsByDay: groupBy(items, (row) => row.weekday),
    itemsByClass: groupBy(items, (row) => row.classId),
    meetings: groupBy(items.filter((row) => row.meetingId), (row) => row.meetingId),
  };
}

function occupyingUnits(context: ScheduleContext, source: ScheduleItem, target: ScheduleSlot) {
  const moving = relatedItems(context, source);
  const ignored = new Set(moving.map((row) => row.id));
  const occupants = new Map<string, ScheduleItem>();
  for (const row of moving) {
    const slot = matchingSlot(context, row, target);
    if (!slot) return [];
    for (const other of context.itemsByDay.get(slot.weekday) ?? []) {
      if (ignored.has(other.id) || !occursInWeek(other.weekMode, row.weekMode)) continue;
      if (other.classId !== row.classId &&
          (other.teacherId !== row.teacherId || teachingMeetingKey(row) === teachingMeetingKey(other))) continue;
      const occupied = positionOf(context, other);
      if (occupied && timesOverlap(slot, occupied)) occupants.set(meetingKey(other), other);
    }
  }
  return [...occupants.values()];
}

function scheduleCandidates(context: ScheduleContext) {
  const cache = new Map<string, ScheduleSlot[]>();
  return (item: ScheduleItem) => {
    const members = relatedItems(context, item);
    const key = JSON.stringify([item.classId, ...members.map((row) => row.assignmentId).sort()]);
    const previous = cache.get(key);
    if (previous) return previous;
    const slots = context.slotsByStage.get(context.stageForClass(item.classId) ?? '') ?? [];
    const allowed = slots.filter((target) => members.every((row) => {
      const position = matchingSlot(context, row, target);
      return position && !freeSlotFor(context, row.classId, position) && !overlappingDuty(context, row, position) &&
        weeksFor(row.weekMode).every((week) => !presetsAt(context, row, position, week).includes('forbid'));
    }));
    cache.set(key, allowed);
    return allowed;
  };
}

function repairUnplaced(initial: ScheduleContext, units: ScheduleItem[], movable: Set<string>, slotsFor: (item: ScheduleItem) => ScheduleSlot[]) {
  const strength = initial.data.preferences.strength;
  const maxChecks = strength === 'fast' ? 3000 : strength === 'high' ? 30000 : 12000;
  const maxDepth = strength === 'fast' ? 1 : 2;
  let candidateChecks = 0;
  let context = initial;
  const check = (state: ScheduleContext, source: ScheduleItem, target: ScheduleSlot) => {
    if (candidateChecks >= maxChecks) return;
    candidateChecks++;
    return previewPlacement(state, source, target, false, false).changed;
  };
  const canMove = (state: ScheduleContext, item: ScheduleItem) => movable.has(meetingKey(item)) &&
    relatedItems(state, item).every((row) => {
      const slot = positionOf(state, row);
      return !isLessonLocked(state, row) && (!slot || !weeksFor(row.weekMode).some((week) => presetsAt(state, row, slot, week).includes('must')));
    });

  function rearrange(state: ScheduleContext, source: ScheduleItem, target: ScheduleSlot, depth: number, protectedUnits: Set<string>): ScheduleContext | undefined {
    const changes = check(state, source, target);
    if (changes) return withScheduleChanges(state, changes);
    if (!depth || candidateChecks >= maxChecks) return;
    const blockedBy = occupyingUnits(state, source, target);
    if (!blockedBy.length || blockedBy.length > 2 ||
        blockedBy.some((row) => protectedUnits.has(meetingKey(row)) || !canMove(state, row))) return;
    const lifted = blockedBy.flatMap((row) => relatedItems(state, row).map((item) => withPosition(item, null)));
    const reduced = withScheduleChanges(state, lifted);
    const placement = check(reduced, source, target);
    if (!placement) return;
    let next = withScheduleChanges(reduced, placement);
    const protectedNext = new Set([...protectedUnits, meetingKey(source), ...blockedBy.map(meetingKey)]);
    for (const blocker of blockedBy) {
      const waiting = lifted.find((row) => row.id === blocker.id)!;
      const origin = positionOf(state, blocker);
      const alternatives = slotsFor(waiting).filter((slot) => slot !== origin);
      let restored: ScheduleContext | undefined;
      for (const slot of alternatives) {
        const direct = check(next, waiting, slot);
        if (direct) { restored = withScheduleChanges(next, direct); break; }
        if (candidateChecks >= maxChecks) break;
      }
      if (!restored && depth > 1) {
        for (const slot of alternatives) {
          restored = rearrange(next, waiting, slot, depth - 1, protectedNext);
          if (restored || candidateChecks >= maxChecks) break;
        }
      }
      if (!restored) return;
      next = restored;
    }
    return next;
  }

  const mustCheckTotals = hasAggregateRequirements(initial.data);
  let knownIssues = new Set(mustCheckTotals ? aggregateScheduleIssues(context) : []);
  const outstanding = new Map(units.map((row) => [row.id, row]));
  for (let depth = 1; depth <= maxDepth && candidateChecks < maxChecks && outstanding.size; depth++) {
    for (const [id, item] of outstanding) {
      if (candidateChecks >= maxChecks) break;
      for (const target of slotsFor(item)) {
        const repaired = rearrange(context, item, target, depth, new Set());
        if (repaired) {
          const issues = mustCheckTotals ? aggregateScheduleIssues(repaired) : [];
          if (!issues.some((issue) => !knownIssues.has(issue))) {
            context = repaired;
            knownIssues = new Set(issues);
            outstanding.delete(id);
            break;
          }
        }
        if (candidateChecks >= maxChecks) break;
      }
    }
  }
  return { context, candidateChecks };
}

export function solveSchedule(
  data: ScheduleData, classIds: string[], retainPlacements = false, onProgress?: (done: number, total: number) => void,
  seed = 0, allowRearrangement = false,
) {
  const items = prepareDemand(data, classIds, retainPlacements);
  const selected = new Set(classIds);
  const selectedGroups = new Set(data.assignments.filter((row) => selected.has(row.classId)).map((row) => row.combinedLessonGroupId).filter(Boolean));
  const initial = createScheduleContext({ ...data, items });
  const inScope = (row: ScheduleItem) => selected.has(row.classId) ||
    (row.combinedGroupId !== null && selectedGroups.has(row.combinedGroupId));
  const candidates = items.filter((row) => row.weekday === null && inScope(row));
  const slotsFor = scheduleCandidates(initial);
  const units = [...new Map(candidates.map((row) => [meetingKey(row), row])).values()];
  const teacherWeight = groupBy(items, (row) => row.teacherId);
  units.sort((a, b) => {
    const weight = (item: ScheduleItem) => (initial.meetings.get(item.meetingId)?.length ?? 1) * 100 +
      (teacherWeight.get(item.teacherId)?.length ?? 0) + (item.weekMode === 'weekly' ? 20 : 0);
    return slotsFor(a).length - slotsFor(b).length || weight(b) - weight(a) || a.id.localeCompare(b.id);
  });
  let candidateChecks = 0;
  const waiting: ScheduleItem[] = [];
  let context = initial;
  const totalSteps = units.length + 1;
  onProgress?.(0, totalSteps);
  for (let index = 0; index < units.length; index++) {
    const item = units[index];
    const anchor = retainPlacements && item.meetingId ? context.meetings.get(item.meetingId)
      ?.map((row) => positionOf(context, row)).find((slot) => !!slot) : undefined;
    const slots = slotsFor(item).filter((slot) => !anchor || matchingSlot(context, item, anchor) === slot);
    let best: PlacementPreview | undefined;
    let bestScore = -Infinity;
    for (const slot of slots) {
      candidateChecks++;
      const preview = previewPlacement(context, item, slot, false, false);
      if (!preview.changed) continue;
      const score = preview.changed.reduce((sum, row) => sum + preferenceScore(context, row, positionOf(context, row)!), 0) -
        ((slot.weekday * 17 + slot.order * 11 + seed * slot.weekday * slot.order) % 71) / 71;
      if (score > bestScore) {
        bestScore = score;
        best = preview;
      }
    }
    if (best?.changed) {
      context = withScheduleChanges(context, best.changed);
    } else {
      waiting.push(item);
    }
    if (index % 8 === 7 || index === units.length - 1) onProgress?.(index + 1, totalSteps);
  }
  const repairable = waiting.filter((row) => relatedItems(context, row).every((member) => member.weekday === null));
  if (repairable.length) {
    const movable = new Set(items.filter(inScope).filter((row) => relatedItems(initial, row).every((member) =>
      inScope(member) && (allowRearrangement || member.weekday === null))).map(meetingKey));
    const repaired = repairUnplaced(context, repairable, movable, slotsFor);
    context = repaired.context;
    candidateChecks += repaired.candidateChecks;
  }

  // Recompute blockers against the saved arrangement after any displaced lessons have settled.
  const finalItems = new Map(context.data.items.map((row) => [row.id, row]));
  const blockers: Record<string, string[]> = {};
  for (const pending of waiting) {
    const item = finalItems.get(pending.id)!;
    if (item.weekday !== null) continue;
    const reasons = new Set<string>();
    for (const target of context.slotsByStage.get(context.stageForClass(item.classId) ?? '') ?? []) {
      candidateChecks++;
      const result = previewPlacement(context, item, target, false, false);
      if (result.status === 'blocked') reasons.add(result.reason);
      if (reasons.size === 5) break;
    }
    if (!reasons.size) reasons.add('当前排课范围内未找到满足全部约束的位置');
    for (const row of relatedItems(context, item)) {
      if (row.weekday === null) blockers[row.id] = [...reasons];
    }
  }
  onProgress?.(totalSteps, totalSteps);
  return { items: context.data.items, candidateChecks, blockers, issues: detectSchedule(context.data) };
}

export function reconcileSchedule(data: ScheduleData, baseline = data) {
  const original = createScheduleContext(baseline);
  const current = createScheduleContext(data);
  const previous = new Map([...baseline.items, ...data.items].map((row) => [row.id, row]));
  const demand = prepareDemand({ ...data, items: [...previous.values()] }, data.classes.map((row) => row.id), true);
  const accepted = new Map(demand.map((item) => [item.id, withPosition(item, null)]));
  const units = [...groupBy(demand, meetingKey).values()]
    .sort((a, b) => Number(b.some((row) => isLessonLocked(original, previous.get(row.id) ?? row))) -
      Number(a.some((row) => isLessonLocked(original, previous.get(row.id) ?? row))));
  const waiting: ScheduleItem[][] = [];
  const savePreview = (preview: PlacementPreview) => {
    for (const row of preview.changed ?? []) accepted.set(row.id, row);
  };
  const build = () => createScheduleContext({ ...data, locks: [], items: [...accepted.values()] });
  for (const unit of units) {
    const [item] = unit;
    const position = positionOf(current, item);
    if (!position || unit.some((row) => !positionOf(current, row))) { waiting.push(unit); continue; }
    const context = build();
    const target = context.slots.get(slotKey(position))!;
    if (unit.some((row) => matchingSlot(context, row, target) !== positionOf(context, row))) {
      waiting.push(unit);
      continue;
    }
    const preview = previewPlacement(context, accepted.get(item.id)!, target, false, false);
    if (preview.changed) savePreview(preview);
    else waiting.push(unit);
  }
  for (const [item] of waiting) {
    const context = build();
    const old = previous.get(item.id);
    const oldSlot = old && positionOf(original, old);
    const slots = context.slotsByStage.get(context.stageForClass(item.classId) ?? '') ?? [];
    const distance = (slot: ScheduleSlot) => oldSlot ?
      Math.abs(slot.weekday - oldSlot.weekday) * 16 + Math.abs(slot.order - oldSlot.order) : 0;
    const nearest = [...slots].sort((a, b) => distance(a) - distance(b) ||
      preferenceScore(context, item, b) - preferenceScore(context, item, a));
    for (const slot of nearest) {
      const preview = previewPlacement(context, accepted.get(item.id)!, slot, false, false);
      if (!preview.changed) continue;
      savePreview(preview);
      break;
    }
  }
  const items = [...accepted.values()];
  const locks = data.locks.filter((lock) => {
    const wasLocked = baseline.items.filter((row) => row.weekday !== null &&
      (lock.scope === 'class' ? row.classId === lock.targetId : row.teacherId === lock.targetId));
    return wasLocked.length > 0 && wasLocked.every((then) => {
      const now = accepted.get(then.id);
      return now && then.stageId === now.stageId && then.weekday === now.weekday && then.periodTypeId === now.periodTypeId &&
        then.lessonIndex === now.lessonIndex && then.teacherId === now.teacherId;
    });
  });
  return { items, locks };
}
