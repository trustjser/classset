import type {
  CalendarException,
  GradeGroup,
  ScheduleCondition,
  ScopeType,
  StageRoutine,
  SubjectLessonConstraint,
  SubjectParallelLimit,
  Teacher,
  TemporaryCourseAdjustment,
  WeekMode,
} from './models';
import type { ScheduleData } from './scheduling';
import type {
  SchedulePosition,
  SupervisionOccurrence,
  SupervisionPost,
  SupervisionVersion,
} from './supervision';
import { hasClockTime, sameCell } from './supervision';
import {
  formatDateYmd,
  getIsoWeekday,
  getTeachingWeekOfDate,
  getWeek1MondayAnchor,
  parseLocalDate,
} from '../features/terms/calendarUtils';
import { resolveSubjectRoomAssignment } from '../features/publicRooms/publicRoomsData';

export const SUPERVISION_SUBSTITUTION_KIND = 'supervision-substitute';

export interface ActualScheduleItem {
  id: string;
  termId: string;
  assignmentId: string;
  classId: string;
  teacherId: string;
  subjectId: string;
  weekMode: WeekMode;
  combinedGroupId: string | null;
  meetingId: string | null;
  position: SchedulePosition | null;
}

export function actualItemAt(
  item: ActualScheduleItem,
  next: SchedulePosition | null
): ActualScheduleItem {
  return {
    ...item,
    position: next,
  };
}

export function actualItemToJson(item: ActualScheduleItem): Record<string, unknown> {
  return {
    id: item.id,
    termId: item.termId,
    assignmentId: item.assignmentId,
    classId: item.classId,
    teacherId: item.teacherId,
    subjectId: item.subjectId,
    weekMode: item.weekMode,
    combinedGroupId: item.combinedGroupId,
    meetingId: item.meetingId,
    position: item.position
      ? {
          stageId: item.position.stageId,
          weekday: item.position.weekday,
          periodTypeId: item.position.periodTypeId,
          lessonIndex: item.position.lessonIndex,
          startMinute: item.position.startMinute ?? null,
          endMinute: item.position.endMinute ?? null,
        }
      : null,
  };
}

export function actualItemFromJson(raw: Record<string, unknown>): ActualScheduleItem {
  const posRaw = raw.position as Record<string, unknown> | null | undefined;
  let position: SchedulePosition | null = null;
  if (posRaw && typeof posRaw === 'object') {
    position = {
      stageId: String(posRaw.stageId ?? ''),
      weekday: Number(posRaw.weekday ?? 1),
      periodTypeId: String(posRaw.periodTypeId ?? ''),
      lessonIndex: Number(posRaw.lessonIndex ?? 1),
      startMinute:
        posRaw.startMinute != null ? Number(posRaw.startMinute) : null,
      endMinute: posRaw.endMinute != null ? Number(posRaw.endMinute) : null,
    };
  } else if (
    raw.stageId != null &&
    raw.weekday != null &&
    raw.periodTypeId != null &&
    raw.lessonIndex != null
  ) {
    position = {
      stageId: String(raw.stageId),
      weekday: Number(raw.weekday),
      periodTypeId: String(raw.periodTypeId),
      lessonIndex: Number(raw.lessonIndex),
      startMinute: null,
      endMinute: null,
    };
  }
  return {
    id: String(raw.id ?? ''),
    termId: String(raw.termId ?? ''),
    assignmentId: String(raw.assignmentId ?? ''),
    classId: String(raw.classId ?? ''),
    teacherId: String(raw.teacherId ?? ''),
    subjectId: String(raw.subjectId ?? ''),
    weekMode: (raw.weekMode as WeekMode) ?? 'weekly',
    combinedGroupId:
      raw.combinedGroupId != null ? String(raw.combinedGroupId) : null,
    meetingId: raw.meetingId != null ? String(raw.meetingId) : null,
    position,
  };
}

/**
 * 一条周期课表在某个自然日实际出现的课次。
 * date 与 originDate 统一以 YYYY-MM-DD 格式存储。
 */
export interface ActualLesson {
  date: string; // YYYY-MM-DD
  originDate: string; // YYYY-MM-DD
  item: ActualScheduleItem;
  key: string;
}

export function createActualLesson(params: {
  date: string;
  item: ActualScheduleItem;
  originDate?: string;
}): ActualLesson {
  const date = params.date.slice(0, 10);
  const originDate = (params.originDate ?? params.date).slice(0, 10);
  return {
    date,
    originDate,
    item: params.item,
    key: `${params.item.id}:${originDate}`,
  };
}

export function actualLessonToJson(lesson: ActualLesson): Record<string, unknown> {
  return {
    date: `${lesson.date}T00:00:00.000`,
    originDate: `${lesson.originDate}T00:00:00.000`,
    item: actualItemToJson(lesson.item),
  };
}

export function actualLessonFromJson(raw: Record<string, unknown>): ActualLesson {
  const date = String(raw.date ?? '').slice(0, 10);
  const originDate = String(raw.originDate ?? raw.date ?? '').slice(0, 10);
  const item = actualItemFromJson(
    (raw.item as Record<string, unknown>) ?? {}
  );
  return createActualLesson({ date, originDate, item });
}

export interface ActualLessonChange {
  before: ActualLesson;
  after: ActualLesson;
}

export function actualLessonChangeToJson(
  change: ActualLessonChange
): Record<string, unknown> {
  return {
    before: actualLessonToJson(change.before),
    after: actualLessonToJson(change.after),
  };
}

export function actualLessonChangeFromJson(
  raw: Record<string, unknown>
): ActualLessonChange {
  return {
    before: actualLessonFromJson(
      (raw.before as Record<string, unknown>) ?? {}
    ),
    after: actualLessonFromJson((raw.after as Record<string, unknown>) ?? {}),
  };
}

export interface TemporaryMoveRequest {
  sourceKey: string;
  targetDate: string; // YYYY-MM-DD
  targetPosition: SchedulePosition;
  reason?: string;
  rangeStart?: string | null; // YYYY-MM-DD
  rangeEnd?: string | null; // YYYY-MM-DD
  excludedDates?: Set<string>; // YYYY-MM-DD
}

export interface TemporarySubstituteRequest {
  sourceKey: string;
  teacherId: string;
  subjectId?: string | null;
  reason?: string;
  rangeStart?: string | null;
  rangeEnd?: string | null;
  excludedDates?: Set<string>;
}

export interface TemporarySwapRequest {
  firstKey: string;
  secondKey: string;
  reason?: string;
  rangeStart?: string | null;
  rangeEnd?: string | null;
  excludedDates?: Set<string>;
}

export interface ActualSupervision {
  date: string; // YYYY-MM-DD
  occurrences: SupervisionOccurrence[];
  teacherId: string;
  teacherName: string;
  templateWeek?: number;
  eligibleTeacherIds: Set<string>;
  postId: string;
  post: SupervisionPost;
  classIds: string[];
  classNames: string[];
  key: string;
}

export function createActualSupervision(params: {
  date: string;
  occurrences: SupervisionOccurrence[];
  teacherId: string;
  teacherName: string;
  templateWeek?: number;
  eligibleTeacherIds?: Iterable<string>;
}): ActualSupervision {
  const date = params.date.slice(0, 10);
  const first = params.occurrences[0];
  const post = first.post;
  return {
    date,
    occurrences: params.occurrences,
    teacherId: params.teacherId,
    teacherName: params.teacherName,
    templateWeek: params.templateWeek,
    eligibleTeacherIds: new Set(params.eligibleTeacherIds ?? []),
    postId: post.id,
    post,
    classIds: post.classIds,
    classNames: first.classNames,
    key: `${date}:${post.id}`,
  };
}

export function supervisionWithTeacher(
  sup: ActualSupervision,
  teacherId: string,
  teacherName: string
): ActualSupervision {
  return createActualSupervision({
    date: sup.date,
    occurrences: sup.occurrences,
    teacherId,
    teacherName,
    templateWeek: sup.templateWeek,
    eligibleTeacherIds: sup.eligibleTeacherIds,
  });
}

export function actualSupervisionToJson(
  sup: ActualSupervision
): Record<string, unknown> {
  return {
    date: sup.date,
    occurrences: sup.occurrences,
    teacherId: sup.teacherId,
    teacherName: sup.teacherName,
  };
}

export function actualSupervisionFromJson(
  raw: Record<string, unknown>
): ActualSupervision {
  const occurrences = Array.isArray(raw.occurrences)
    ? (raw.occurrences as SupervisionOccurrence[])
    : [];
  return createActualSupervision({
    date: String(raw.date ?? '').slice(0, 10),
    occurrences,
    teacherId: String(raw.teacherId ?? ''),
    teacherName: String(raw.teacherName ?? ''),
  });
}

export function sameSupervisionAssignment(
  a: ActualSupervision,
  b: ActualSupervision
): boolean {
  if (a.key !== b.key || a.teacherId !== b.teacherId) return false;
  const setA = new Set(a.classIds);
  const setB = new Set(b.classIds);
  if (setA.size !== setB.size) return false;
  for (const id of setA) {
    if (!setB.has(id)) return false;
  }
  if (a.occurrences.length !== b.occurrences.length) return false;
  return a.occurrences.every((row) =>
    b.occurrences.some(
      (next) =>
        sameCell(next.position, row.position) &&
        (next.startMinute ?? next.position.startMinute ?? null) ===
          (row.startMinute ?? row.position.startMinute ?? null) &&
        (next.endMinute ?? next.position.endMinute ?? null) ===
          (row.endMinute ?? row.position.endMinute ?? null)
    )
  );
}

export interface TemporarySupervisionSubstituteRequest {
  date: string; // YYYY-MM-DD
  postId: string;
  teacherId: string;
  reason?: string;
}

export interface ActualSupervisionChange {
  before: ActualSupervision;
  after: ActualSupervision;
}

export function actualSupervisionChangeToJson(
  change: ActualSupervisionChange
): Record<string, unknown> {
  return {
    before: actualSupervisionToJson(change.before),
    after: actualSupervisionToJson(change.after),
  };
}

export function actualSupervisionChangeFromJson(
  raw: Record<string, unknown>
): ActualSupervisionChange {
  return {
    before: actualSupervisionFromJson(
      (raw.before as Record<string, unknown>) ?? {}
    ),
    after: actualSupervisionFromJson(
      (raw.after as Record<string, unknown>) ?? {}
    ),
  };
}

export interface SupervisionSubstitutePreview {
  change: ActualSupervisionChange | null;
  errors: string[];
}

export interface TemporaryAdjustmentRecord {
  id: string;
  kind: string;
  changes: ActualLessonChange[];
  reason: string;
  createdAt: number;
  cancelledAt: number | null;
  needsAttention: boolean;
  supervisionChange: ActualSupervisionChange | null;
}

export function recordWithAttention(
  record: TemporaryAdjustmentRecord,
  needsAttention: boolean
): TemporaryAdjustmentRecord {
  return {
    ...record,
    needsAttention,
  };
}

export interface ActualChangePreview {
  changes: ActualLessonChange[];
  errors: string[];
  skippedDates: string[]; // YYYY-MM-DD
}

export interface SchedulingProblem {
  snapshot: ScheduleData;
  positionsByClass: Map<string, SchedulePosition[]>;
  stageByClass: Map<string, string>;
  gradeByClass: Map<string, string>;
  assignmentStagesByTeacher: Map<string, Set<string>>;
  stageHasFullClock: Map<string, boolean>;
}

export function getTeacherDisplayName(teacher: Teacher): string {
  const q = teacher.displayQualifier?.trim();
  return q ? `${teacher.name}（${q}）` : teacher.name;
}

export function buildSchedulingProblem(snapshot: ScheduleData): SchedulingProblem {
  const gradeMap = new Map<string, GradeGroup>(
    snapshot.grades.map((g) => [g.id, g])
  );
  const stageByClass = new Map<string, string>();
  const gradeByClass = new Map<string, string>();
  for (const c of snapshot.classes) {
    gradeByClass.set(c.id, c.gradeId);
    const grade = gradeMap.get(c.gradeId);
    if (grade) {
      stageByClass.set(c.id, grade.stageId);
    }
  }

  const positionsByStage = new Map<string, SchedulePosition[]>();
  const stageHasFullClock = new Map<string, boolean>();
  for (const routine of snapshot.routines) {
    const teachingDays = routine.teachingDays
      .filter((d) => d.isTeachingDay)
      .sort((a, b) => a.weekday - b.weekday);
    const periods = [...routine.periodTypes].sort(
      (a, b) => a.sortOrder - b.sortOrder
    );
    const stagePositions: SchedulePosition[] = [];
    for (const day of teachingDays) {
      for (const period of periods) {
        const override = routine.dailyOverrides.find(
          (o) => o.periodTypeId === period.id && o.weekday === day.weekday
        );
        const count = override
          ? override.lessonCount
          : period.defaultLessonCount;
        for (let idx = 1; idx <= count; idx++) {
          const time = routine.lessonTimes.find(
            (t) => t.periodTypeId === period.id && t.lessonIndex === idx
          );
          stagePositions.push({
            stageId: routine.stageId,
            weekday: day.weekday,
            periodTypeId: period.id,
            lessonIndex: idx,
            startMinute: time?.startMinute ?? null,
            endMinute: time?.endMinute ?? null,
          });
        }
      }
    }
    positionsByStage.set(routine.stageId, stagePositions);
    stageHasFullClock.set(
      routine.stageId,
      stagePositions.length > 0 && stagePositions.every((p) => hasClockTime(p))
    );
  }

  const positionsByClass = new Map<string, SchedulePosition[]>();
  for (const c of snapshot.classes) {
    const stageId = stageByClass.get(c.id);
    positionsByClass.set(
      c.id,
      stageId ? [...(positionsByStage.get(stageId) ?? [])] : []
    );
  }

  const assignmentStagesByTeacher = new Map<string, Set<string>>();
  for (const assignment of snapshot.assignments) {
    if (!assignment.teacherId) continue;
    const st = stageByClass.get(assignment.classId);
    if (!st) continue;
    let set = assignmentStagesByTeacher.get(assignment.teacherId);
    if (!set) {
      set = new Set();
      assignmentStagesByTeacher.set(assignment.teacherId, set);
    }
    set.add(st);
  }

  return {
    snapshot,
    positionsByClass,
    stageByClass,
    gradeByClass,
    assignmentStagesByTeacher,
    stageHasFullClock,
  };
}

// ==================== O(1) 课次索引缓存 ====================

interface LessonsIndex {
  byKey: Map<string, ActualLesson>;
  byDate: Map<string, ActualLesson[]>;
  byWeek: Map<number, ActualLesson[]>;
  weekByDate: Map<string, number | null>;
  byMeetingAndDate: Map<string, ActualLesson[]>;
  stagesByTeacher: Map<string, Set<string>>;
}

const lessonsIndexCache = new WeakMap<ActualLesson[], LessonsIndex>();

function getLessonsIndex(
  lessons: ActualLesson[],
  problem: SchedulingProblem
): LessonsIndex {
  const cached = lessonsIndexCache.get(lessons);
  if (cached) return cached;

  const byKey = new Map<string, ActualLesson>();
  const byDate = new Map<string, ActualLesson[]>();
  const byWeek = new Map<number, ActualLesson[]>();
  const weekByDate = new Map<string, number | null>();
  const byMeetingAndDate = new Map<string, ActualLesson[]>();
  const stagesByTeacher = new Map<string, Set<string>>();

  for (const [tid, stages] of problem.assignmentStagesByTeacher.entries()) {
    stagesByTeacher.set(tid, new Set(stages));
  }

  const term = problem.snapshot.term;
  for (const lesson of lessons) {
    byKey.set(lesson.key, lesson);

    let dateList = byDate.get(lesson.date);
    if (!dateList) {
      dateList = [];
      byDate.set(lesson.date, dateList);
    }
    dateList.push(lesson);

    let week = weekByDate.get(lesson.date);
    if (week === undefined) {
      week = getTeachingWeekOfDate(term, lesson.date);
      weekByDate.set(lesson.date, week);
    }
    if (week != null) {
      let weekList = byWeek.get(week);
      if (!weekList) {
        weekList = [];
        byWeek.set(week, weekList);
      }
      weekList.push(lesson);
    }

    if (lesson.item.meetingId != null) {
      const mKey = `${lesson.item.meetingId}:${lesson.date}`;
      let mList = byMeetingAndDate.get(mKey);
      if (!mList) {
        mList = [];
        byMeetingAndDate.set(mKey, mList);
      }
      mList.push(lesson);
    }

    const st = problem.stageByClass.get(lesson.item.classId);
    if (st) {
      let tSet = stagesByTeacher.get(lesson.item.teacherId);
      if (!tSet) {
        tSet = new Set();
        stagesByTeacher.set(lesson.item.teacherId, tSet);
      }
      tSet.add(st);
    }
  }

  const index: LessonsIndex = {
    byKey,
    byDate,
    byWeek,
    weekByDate,
    byMeetingAndDate,
    stagesByTeacher,
  };
  lessonsIndexCache.set(lessons, index);
  return index;
}

function getCachedWeekOfDate(
  index: LessonsIndex,
  snapshot: ScheduleData,
  ymd: string
): number | null {
  const cached = index.weekByDate.get(ymd);
  if (cached !== undefined) return cached;
  const w = getTeachingWeekOfDate(snapshot.term, ymd);
  index.weekByDate.set(ymd, w);
  return w;
}

function positionsConflictOnDate(a: SchedulePosition, b: SchedulePosition): boolean {
  if (hasClockTime(a) && hasClockTime(b)) {
    return a.startMinute! < b.endMinute! && b.startMinute! < a.endMinute!;
  }
  return (
    a.stageId !== b.stageId ||
    (a.periodTypeId === b.periodTypeId && a.lessonIndex === b.lessonIndex)
  );
}

export function actualSupervisionConflict(
  snapshot: ScheduleData,
  lessons: ActualLesson[],
  supervisions: ActualSupervision[],
  supervision: ActualSupervision,
  teacherId: string
): string | null {
  for (const lesson of lessons) {
    if (lesson.date !== supervision.date) continue;
    const position = lesson.item.position;
    const teacherConflict = lesson.item.teacherId === teacherId;
    const classConflict = supervision.classIds.includes(lesson.item.classId);
    if (!position || (!teacherConflict && !classConflict)) continue;
    if (
      supervision.occurrences.some((row) =>
        positionsConflictOnDate(row.position, position)
      )
    ) {
      const subject = snapshot.subjects.find(
        (s) => s.id === lesson.item.subjectId
      );
      return `与${teacherConflict ? '教师' : '班级'}的${
        subject?.name ?? '正课'
      }时间冲突`;
    }
  }
  for (const other of supervisions) {
    if (other.date !== supervision.date || other.key === supervision.key) {
      continue;
    }
    if (
      other.teacherId !== teacherId &&
      !other.classIds.some((id) => supervision.classIds.includes(id))
    ) {
      continue;
    }
    if (
      supervision.occurrences.some((row) =>
        other.occurrences.some((next) =>
          positionsConflictOnDate(row.position, next.position)
        )
      )
    ) {
      return `与「${other.post.name}」带班时间冲突`;
    }
  }
  return null;
}

function addDaysYmd(ymd: string, deltaDays: number): string {
  const d = parseLocalDate(ymd);
  d.setDate(d.getDate() + deltaDays);
  return formatDateYmd(d);
}

function diffDaysYmd(a: string, b: string): number {
  const da = parseLocalDate(a);
  const db = parseLocalDate(b);
  return Math.round((da.getTime() - db.getTime()) / 86400000);
}

function occursInWeekMode(mode: WeekMode, oddWeek: boolean): boolean {
  return mode === 'weekly' || (oddWeek ? mode === 'odd' : mode === 'even');
}

function weekModesOverlap(left: WeekMode, right: WeekMode): boolean {
  return left === 'weekly' || right === 'weekly' || left === right;
}

function positionOverlaps(a: SchedulePosition, b: SchedulePosition): boolean {
  if (a.weekday !== b.weekday) return false;
  if (a.stageId === b.stageId) {
    if (a.periodTypeId === b.periodTypeId && a.lessonIndex === b.lessonIndex) {
      return true;
    }
    if (hasClockTime(a) && hasClockTime(b)) {
      return a.startMinute! < b.endMinute! && b.startMinute! < a.endMinute!;
    }
    return false;
  }
  if (hasClockTime(a) && hasClockTime(b)) {
    return a.startMinute! < b.endMinute! && b.startMinute! < a.endMinute!;
  }
  return false;
}

function positionHasSameClock(a: SchedulePosition, b: SchedulePosition): boolean {
  return (
    a.weekday === b.weekday &&
    hasClockTime(a) &&
    hasClockTime(b) &&
    a.startMinute === b.startMinute &&
    a.endMinute === b.endMinute
  );
}

function effectiveLessonCount(
  routine: StageRoutine,
  periodTypeId: string,
  weekday: number
): number {
  const override = routine.dailyOverrides.find(
    (o) => o.periodTypeId === periodTypeId && o.weekday === weekday
  );
  if (override) return override.lessonCount;
  return (
    routine.periodTypes.find((p) => p.id === periodTypeId)?.defaultLessonCount ??
    0
  );
}

function dateConflictLabel(ymd: string): string {
  const d = parseLocalDate(ymd);
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  const w = getIsoWeekday(d);
  return `${d.getMonth() + 1}月${d.getDate()}日（周${weekdays[w - 1]}）`;
}

function lessonConflictLabel(
  snapshot: ScheduleData,
  lesson: ActualLesson
): string {
  const subject = snapshot.subjects.find(
    (s) => s.id === lesson.item.subjectId
  );
  const teacher = snapshot.teachers.find(
    (t) => t.id === lesson.item.teacherId
  );
  const subjectName = subject?.name ?? lesson.item.subjectId;
  const teacherName = teacher
    ? getTeacherDisplayName(teacher)
    : lesson.item.teacherId;
  return `${subjectName}（${teacherName}）`;
}

function classConflictLabel(snapshot: ScheduleData, classId: string): string {
  const schoolClass = snapshot.classes.find((c) => c.id === classId);
  if (!schoolClass) return classId;
  const grade = snapshot.grades.find((g) => g.id === schoolClass.gradeId);
  const label = [grade?.name, schoolClass.name]
    .filter((v): v is string => Boolean(v && v.trim()))
    .join(' ');
  return label || classId;
}

function positionConflictLabel(
  snapshot: ScheduleData,
  position: SchedulePosition
): string {
  const routine = snapshot.routines.find((r) => r.stageId === position.stageId);
  const period = routine?.periodTypes.find(
    (p) => p.id === position.periodTypeId
  );
  const prefix = period?.name ? period.name : '';
  return `${prefix}第${position.lessonIndex}节`;
}

function supervisionVersionForDate(
  versions: SupervisionVersion[],
  ymd: string
): SupervisionVersion | null {
  let selected: SupervisionVersion | null = null;
  for (const version of versions) {
    const eff = version.effectiveDate.slice(0, 10);
    if (
      eff <= ymd &&
      (!selected || eff > selected.effectiveDate.slice(0, 10))
    ) {
      selected = version;
    }
  }
  return selected;
}

// ==================== ConstraintEvaluator 等价实现 ====================

interface ScheduleBlocker {
  code: string;
  message: string;
  conditionId?: string | null;
  position?: SchedulePosition | null;
  relatedIds?: string[];
}

function cellKey(p: SchedulePosition | null | undefined): string {
  if (!p) return '';
  return `${p.stageId}:${p.weekday}:${p.periodTypeId}:${p.lessonIndex}`;
}

function blockerIdentity(blocker: ScheduleBlocker): string {
  return `${blocker.code}:${blocker.conditionId ?? null}:${cellKey(
    blocker.position
  )}:${blocker.message.replace(/已排 \d+ 节/g, '已排 * 节')}`;
}

function blockerPlacedCount(blocker: ScheduleBlocker): number | null {
  const m = /已排 (\d+) 节/.exec(blocker.message);
  return m ? Number(m[1]) : null;
}

function isFreeSlot(
  snapshot: ScheduleData,
  problem: SchedulingProblem,
  classId: string,
  p: SchedulePosition
): boolean {
  const gradeId = problem.gradeByClass.get(classId);
  return snapshot.freeSlots.some(
    (slot) =>
      slot.stageId === p.stageId &&
      slot.weekday === p.weekday &&
      slot.periodTypeId === p.periodTypeId &&
      slot.lessonIndex === p.lessonIndex &&
      (slot.scopeType === 'school' ||
        (slot.scopeType === 'stage' && slot.scopeId === p.stageId) ||
        (slot.scopeType === 'grade' && slot.scopeId === gradeId) ||
        (slot.scopeType === 'class' && slot.scopeId === classId))
  );
}

function getSubjectPreset(
  snapshot: ScheduleData,
  problem: SchedulingProblem,
  item: ActualScheduleItem,
  p: SchedulePosition
): string {
  const gradeId = problem.gradeByClass.get(item.classId);
  const rows = snapshot.subjectPresets.filter(
    (row) =>
      row.subjectId === item.subjectId &&
      row.stageId === p.stageId &&
      row.weekday === p.weekday &&
      row.periodTypeId === p.periodTypeId &&
      row.lessonIndex === p.lessonIndex
  );
  if (rows.length === 0) return 'auto';
  const scopes: Array<[ScopeType, string | undefined]> = [
    ['class', item.classId],
    ['grade', gradeId],
    ['stage', p.stageId],
    ['school', snapshot.term.id],
  ];
  for (const [scopeType, scopeId] of scopes) {
    if (!scopeId) continue;
    const found = rows.find(
      (r) => r.scopeType === scopeType && r.scopeId === scopeId
    );
    if (found) return found.value;
  }
  return 'auto';
}

function getTeacherPreset(
  snapshot: ScheduleData,
  problem: SchedulingProblem,
  item: ActualScheduleItem,
  p: SchedulePosition
): string {
  if (
    snapshot.teacherPresets.length === 0 &&
    snapshot.teacherGroupPresets.length === 0
  ) {
    return 'auto';
  }
  const gradeId = problem.gradeByClass.get(item.classId);
  const groupIds = new Set(
    snapshot.teacherGroupMembers
      .filter((m) => m.teacherId === item.teacherId)
      .map((m) => m.groupId)
  );
  const scopes: Array<[ScopeType, string | undefined]> = [
    ['class', item.classId],
    ['grade', gradeId],
    ['stage', p.stageId],
    ['school', snapshot.term.id],
  ];
  for (const [scopeType, scopeId] of scopes) {
    if (!scopeId) continue;
    const personal = snapshot.teacherPresets.filter(
      (row) =>
        row.teacherId === item.teacherId &&
        row.scopeType === scopeType &&
        row.scopeId === scopeId &&
        row.stageId === p.stageId &&
        row.weekday === p.weekday &&
        row.periodTypeId === p.periodTypeId &&
        row.lessonIndex === p.lessonIndex
    );
    const groups = snapshot.teacherGroupPresets.filter(
      (row) =>
        groupIds.has(row.groupId) &&
        row.scopeType === scopeType &&
        row.scopeId === scopeId &&
        row.stageId === p.stageId &&
        row.weekday === p.weekday &&
        row.periodTypeId === p.periodTypeId &&
        row.lessonIndex === p.lessonIndex
    );
    if (personal.length > 0 || groups.length > 0) {
      if (personal.length > 0 && personal[0].value !== 'auto') {
        return personal[0].value;
      }
      const groupValues = new Set(
        groups.map((g) => g.value).filter((v) => v !== 'auto')
      );
      if (groupValues.has('forbid')) return 'forbid';
      if (groupValues.has('must')) return 'must';
      if (groupValues.has('prefer')) return 'prefer';
      return 'auto';
    }
  }
  return 'auto';
}

function resolveLessonConstraints(params: {
  constraints: SubjectLessonConstraint[];
  scope: ScopeType;
  scopeId: string;
  stageId: string;
  weekday: number | null;
  parentGradeId?: string;
}) {
  const { constraints, scope, scopeId, stageId, weekday, parentGradeId } =
    params;
  const scopes: Array<[ScopeType, string | undefined]> = [
    [scope, scopeId],
    ...(scope === 'class' && parentGradeId
      ? ([['grade', parentGradeId]] as Array<[ScopeType, string | undefined]>)
      : []),
    ...(scope !== 'stage'
      ? ([['stage', stageId]] as Array<[ScopeType, string | undefined]>)
      : []),
  ];
  const pick = (
    field:
      | 'minimumDailyLessons'
      | 'maximumDailyLessons'
      | 'minimumDailyConsecutivePairs'
      | 'maximumDailyConsecutivePairs'
      | 'minimumWeeklyConsecutivePairs'
      | 'maximumWeeklyConsecutivePairs'
  ): number | null => {
    for (const [sc, id] of scopes) {
      if (!id) continue;
      const days = weekday !== null ? [weekday, null] : [null];
      for (const d of days) {
        const match = constraints.find(
          (c) =>
            c.scopeType === sc &&
            c.scopeId === id &&
            c.stageId === stageId &&
            c.weekday === d &&
            c[field] != null
        );
        if (match && match[field] != null) return match[field];
      }
    }
    return null;
  };
  return {
    minimumDailyLessons: pick('minimumDailyLessons'),
    maximumDailyLessons: pick('maximumDailyLessons'),
    minimumDailyConsecutivePairs: pick('minimumDailyConsecutivePairs'),
    maximumDailyConsecutivePairs: pick('maximumDailyConsecutivePairs'),
    minimumWeeklyConsecutivePairs: pick('minimumWeeklyConsecutivePairs'),
    maximumWeeklyConsecutivePairs: pick('maximumWeeklyConsecutivePairs'),
  };
}

function resolveParallelLimit(params: {
  limits: SubjectParallelLimit[];
  subjectId: string;
  termId: string;
  stageId: string;
  gradeId?: string;
}): SubjectParallelLimit | null {
  const { limits, subjectId, termId, stageId, gradeId } = params;
  if (limits.length === 0) return null;
  const candidates: Array<[ScopeType, string | undefined]> = [
    ['grade', gradeId],
    ['stage', stageId],
  ];
  for (const [sc, id] of candidates) {
    if (!id) continue;
    const found = limits.find(
      (r) =>
        r.subjectId === subjectId &&
        r.termId === termId &&
        r.stageId === stageId &&
        r.scopeType === sc &&
        r.scopeId === id
    );
    if (found) return found;
  }
  return null;
}

function nextLessonPosition(
  snapshot: ScheduleData,
  p: SchedulePosition
): SchedulePosition | null {
  const routine = snapshot.routines.find((r) => r.stageId === p.stageId);
  if (!routine) return null;
  const periods = [...routine.periodTypes].sort(
    (a, b) => a.sortOrder - b.sortOrder
  );
  const cells: SchedulePosition[] = [];
  for (const period of periods) {
    const count = effectiveLessonCount(routine, period.id, p.weekday);
    for (let idx = 1; idx <= count; idx++) {
      cells.push({
        stageId: p.stageId,
        weekday: p.weekday,
        periodTypeId: period.id,
        lessonIndex: idx,
      });
    }
  }
  const index = cells.findIndex((c) => sameCell(c, p));
  return index >= 0 && index + 1 < cells.length ? cells[index + 1] : null;
}

function consecutivePairCount(
  snapshot: ScheduleData,
  rows: ActualScheduleItem[]
): number {
  let count = 0;
  for (const row of rows) {
    if (!row.position) continue;
    const next = nextLessonPosition(snapshot, row.position);
    if (
      next &&
      rows.some(
        (other) =>
          other.id !== row.id &&
          other.position != null &&
          sameCell(other.position, next)
      )
    ) {
      count++;
    }
  }
  return count;
}

function sameMeeting(left: ActualScheduleItem, right: ActualScheduleItem): boolean {
  return (
    left.meetingId != null &&
    left.meetingId === right.meetingId &&
    left.combinedGroupId != null &&
    left.combinedGroupId === right.combinedGroupId
  );
}

function conditionTargetMatches(
  condition: ScheduleCondition,
  item: ActualScheduleItem
): boolean {
  return condition.targetKind === 'subject'
    ? condition.targetId === item.subjectId
    : condition.targetId === item.teacherId;
}

function evaluatePlacement(
  problem: SchedulingProblem,
  placed: ActualScheduleItem[],
  candidateItems: ActualScheduleItem[]
): ScheduleBlocker[] {
  const snapshot = problem.snapshot;
  const blockers: ScheduleBlocker[] = [];
  const all = [...placed, ...candidateItems];
  const placedIds = new Set(candidateItems.map((i) => i.id));
  const otherItems = placed.filter((i) => !placedIds.has(i.id));
  const allWeekly = all.every((i) => i.weekMode === 'weekly');
  const oddWeekPasses = allWeekly ? [true] : [true, false];

  const block = (
    code: string,
    message: string,
    item: ActualScheduleItem,
    opts?: { conditionId?: string | null; relatedIds?: string[] }
  ) => {
    blockers.push({
      code,
      message,
      conditionId: opts?.conditionId ?? null,
      position: item.position,
      relatedIds: opts?.relatedIds ?? [],
    });
  };

  for (const item of candidateItems) {
    const position = item.position;
    const allowedPositions = problem.positionsByClass.get(item.classId) ?? [];
    if (!position || !allowedPositions.some((allowed) => sameCell(allowed, position))) {
      block('position', `班级 ${item.classId} 的候选节次不存在`, item);
      continue;
    }
    if (isFreeSlot(snapshot, problem, item.classId, position)) {
      block('freeSlot', '免任课位置不能排正课', item);
    }
    const subjectPreset = getSubjectPreset(snapshot, problem, item, position);
    if (subjectPreset === 'forbid') {
      block('subjectPreset', '科目预设禁止此位置', item);
    }
    const teacherPreset = getTeacherPreset(snapshot, problem, item, position);
    if (teacherPreset === 'forbid') {
      block('teacherPreset', '教师预设禁止此位置', item);
    }
    if (subjectPreset === 'must' && teacherPreset === 'forbid') {
      block('presetConflict', '科目一定排与教师不排相冲突', item);
    }
    for (const other of [...otherItems, ...candidateItems]) {
      if (
        other.id === item.id ||
        !other.position ||
        !weekModesOverlap(item.weekMode, other.weekMode)
      ) {
        continue;
      }
      if (item.classId === other.classId && sameCell(position, other.position)) {
        block('classOccupied', '班级该周次已有课', item, {
          relatedIds: [other.id],
        });
      }
      if (
        item.teacherId === other.teacherId &&
        !sameMeeting(item, other) &&
        positionOverlaps(position, other.position)
      ) {
        block('teacherOccupied', '教师该周次时间已有课', item, {
          relatedIds: [other.id],
        });
      }
    }

    // Check conditions
    for (const condition of snapshot.conditions) {
      if (condition.termId !== snapshot.term.id) continue;
      if (condition.kind === 'periodLimit' || condition.kind === 'dailyLimit') {
        if (
          !conditionTargetMatches(condition, item) ||
          (condition.kind === 'periodLimit' &&
            condition.periodTypeId !== position.periodTypeId) ||
          (condition.weekday != null && condition.weekday !== position.weekday)
        ) {
          continue;
        }
        const maximum = condition.exactCount ?? condition.maxCount;
        if (maximum == null) continue;
        for (const oddWeek of oddWeekPasses) {
          if (!occursInWeekMode(item.weekMode, oddWeek)) continue;
          const count = all.filter(
            (row) =>
              row.position != null &&
              occursInWeekMode(row.weekMode, oddWeek) &&
              conditionTargetMatches(condition, row) &&
              (condition.targetKind !== 'subject' ||
                row.classId === item.classId) &&
              (condition.kind !== 'periodLimit' ||
                row.position.periodTypeId === condition.periodTypeId) &&
              (condition.kind !== 'dailyLimit' ||
                row.position.weekday === position.weekday) &&
              (condition.weekday == null ||
                row.position.weekday === condition.weekday)
          ).length;
          if (count > maximum) {
            block(
              'conditionMaximum',
              `${condition.name ?? condition.id} 超过最多 ${maximum} 节`,
              item,
              { conditionId: condition.id }
            );
          }
        }
      } else if (condition.kind === 'teacherMutualExclusion') {
        if (
          item.teacherId !== condition.targetId &&
          item.teacherId !== condition.otherId
        ) {
          continue;
        }
        const otherId =
          item.teacherId === condition.targetId
            ? condition.otherId
            : condition.targetId;
        for (const other of all) {
          if (
            other.id !== item.id &&
            other.teacherId === otherId &&
            other.position != null &&
            weekModesOverlap(item.weekMode, other.weekMode) &&
            positionOverlaps(position, other.position)
          ) {
            block(
              'teacherMutualExclusion',
              `${condition.name ?? condition.id}：教师不能同时上课`,
              item,
              { conditionId: condition.id, relatedIds: [other.id] }
            );
          }
        }
      } else if (condition.kind === 'subjectMutualExclusion') {
        if (
          item.subjectId !== condition.targetId &&
          item.subjectId !== condition.otherId
        ) {
          continue;
        }
        const otherId =
          item.subjectId === condition.targetId
            ? condition.otherId
            : condition.targetId;
        for (const other of all) {
          if (
            other.id !== item.id &&
            other.classId === item.classId &&
            other.subjectId === otherId &&
            other.position?.weekday === position.weekday &&
            weekModesOverlap(item.weekMode, other.weekMode)
          ) {
            block(
              'subjectMutualExclusion',
              `${condition.name ?? condition.id}：两科不能同一天`,
              item,
              { conditionId: condition.id, relatedIds: [other.id] }
            );
          }
        }
      } else if (condition.kind === 'forbiddenAdjacency') {
        for (const other of all) {
          if (
            other.id === item.id ||
            other.classId !== item.classId ||
            other.position?.weekday !== position.weekday ||
            !weekModesOverlap(item.weekMode, other.weekMode)
          ) {
            continue;
          }
          const nextFromP = nextLessonPosition(snapshot, position);
          const nextFromOther = nextLessonPosition(snapshot, other.position);
          if (
            (item.subjectId === condition.targetId &&
              other.subjectId === condition.otherId &&
              nextFromP != null &&
              sameCell(nextFromP, other.position)) ||
            (other.subjectId === condition.targetId &&
              item.subjectId === condition.otherId &&
              nextFromOther != null &&
              sameCell(nextFromOther, position))
          ) {
            block(
              'forbiddenAdjacency',
              `${condition.name ?? condition.id}：禁止科目相邻`,
              item,
              { conditionId: condition.id, relatedIds: [other.id] }
            );
          }
        }
      }
    }

    // Check lesson limits
    const subjectConstraints = snapshot.lessonConstraints.filter(
      (rule) => rule.subjectId === item.subjectId
    );
    if (
      subjectConstraints.some(
        (rule) =>
          rule.maximumDailyLessons != null ||
          rule.maximumDailyConsecutivePairs != null ||
          rule.maximumWeeklyConsecutivePairs != null
      )
    ) {
      const gradeId = problem.gradeByClass.get(item.classId);
      for (const oddWeek of oddWeekPasses) {
        if (!occursInWeekMode(item.weekMode, oddWeek)) continue;
        const limits = resolveLessonConstraints({
          constraints: subjectConstraints,
          scope: 'class',
          scopeId: item.classId,
          stageId: position.stageId,
          weekday: position.weekday,
          parentGradeId: gradeId,
        });
        if (limits.maximumDailyLessons != null) {
          const count = all.filter(
            (row) =>
              row.position != null &&
              row.classId === item.classId &&
              row.subjectId === item.subjectId &&
              row.position.weekday === position.weekday &&
              occursInWeekMode(row.weekMode, oddWeek)
          ).length;
          if (count > limits.maximumDailyLessons) {
            block('subjectDailyMaximum', '科目单日节数超过上限', item);
          }
        }
        const weeklyRows = all.filter(
          (row) =>
            row.position != null &&
            row.classId === item.classId &&
            row.subjectId === item.subjectId &&
            occursInWeekMode(row.weekMode, oddWeek)
        );
        if (limits.maximumDailyConsecutivePairs != null) {
          const dayPairs = consecutivePairCount(
            snapshot,
            weeklyRows.filter((r) => r.position!.weekday === position.weekday)
          );
          if (dayPairs > limits.maximumDailyConsecutivePairs) {
            block('dailyConsecutiveMaximum', '科目单日连堂次数超过上限', item);
          }
        }
        if (limits.maximumWeeklyConsecutivePairs != null) {
          const teachingDays =
            snapshot.routines
              .find((r) => r.stageId === position.stageId)
              ?.teachingDays.filter((d) => d.isTeachingDay)
              .map((d) => d.weekday) ?? [];
          const weeklyPairs = teachingDays.reduce(
            (sum, day) =>
              sum +
              consecutivePairCount(
                snapshot,
                weeklyRows.filter((r) => r.position!.weekday === day)
              ),
            0
          );
          if (weeklyPairs > limits.maximumWeeklyConsecutivePairs) {
            block('weeklyConsecutiveMaximum', '科目每周连堂次数超过上限', item);
          }
        }
      }
    }

    // Check parallel and rooms
    const gradeId = problem.gradeByClass.get(item.classId);
    const limit = resolveParallelLimit({
      limits: snapshot.parallelLimits,
      subjectId: item.subjectId,
      termId: snapshot.term.id,
      stageId: position.stageId,
      gradeId,
    });
    if (limit) {
      const parallelLessons = new Set(
        all
          .filter(
            (row) =>
              row.position != null &&
              row.subjectId === item.subjectId &&
              weekModesOverlap(row.weekMode, item.weekMode) &&
              positionOverlaps(row.position, position)
          )
          .map((row) =>
            row.combinedGroupId == null
              ? row.id
              : `${row.combinedGroupId}:${row.meetingId ?? cellKey(row.position)}`
          )
      );
      if (parallelLessons.size > limit.maxParallelLessons) {
        block(
          'parallelLimit',
          `同科同时上课超过 ${limit.maxParallelLessons} 节`,
          item
        );
      }
    }

    if (snapshot.roomAssignments.length > 0) {
      const roomForRow = (row: ActualScheduleItem): string | null =>
        resolveSubjectRoomAssignment({
          assignments: snapshot.roomAssignments,
          subjectId: row.subjectId,
          termId: snapshot.term.id,
          stageId: row.position!.stageId,
          scope: 'class',
          scopeId: row.classId,
          parentGradeId: problem.gradeByClass.get(row.classId),
        })?.roomId ?? null;

      const roomId = roomForRow(item);
      if (roomId) {
        const room = snapshot.rooms.find((r) => r.id === roomId);
        if (!room) {
          block('room', `公共场室 ${roomId} 不存在`, item);
        } else {
          for (const oddWeek of oddWeekPasses) {
            if (!occursInWeekMode(item.weekMode, oddWeek)) continue;
            const classesUsingRoom = new Set(
              all
                .filter(
                  (row) =>
                    row.position != null &&
                    occursInWeekMode(row.weekMode, oddWeek) &&
                    positionOverlaps(row.position, position) &&
                    roomForRow(row) === roomId
                )
                .map((r) => r.classId)
            );
            if (classesUsingRoom.size > room.roomCount * room.capacityPerRoom) {
              block('roomCapacity', `公共场室 ${room.name} 容量已满`, item);
            }
          }
        }
      }
    }

    // Check hard globals (consecutivePolicy === 'requireSeparate' & lunchProtection)
    if (snapshot.preferences.consecutivePolicy === 'requireSeparate') {
      const stageId = problem.stageByClass.get(item.classId);
      const limits = stageId
        ? resolveLessonConstraints({
            constraints: snapshot.lessonConstraints.filter(
              (r) => r.subjectId === item.subjectId
            ),
            scope: 'class',
            scopeId: item.classId,
            stageId,
            weekday: position.weekday,
            parentGradeId: gradeId,
          })
        : null;
      const forced =
        (limits?.minimumDailyConsecutivePairs ?? 0) > 0 ||
        (limits?.minimumWeeklyConsecutivePairs ?? 0) > 0;
      if (!forced) {
        for (const other of all) {
          if (
            other.id !== item.id &&
            other.classId === item.classId &&
            other.subjectId === item.subjectId &&
            other.position?.weekday === position.weekday &&
            weekModesOverlap(item.weekMode, other.weekMode)
          ) {
            const nextP = nextLessonPosition(snapshot, position);
            const nextOther = nextLessonPosition(snapshot, other.position);
            if (
              (nextP && sameCell(nextP, other.position)) ||
              (nextOther && sameCell(nextOther, position))
            ) {
              block('consecutive', '该科目设置了硬性不连堂', item);
            }
          }
        }
      }
    }

    if (snapshot.preferences.lunchProtection) {
      const routine = snapshot.routines.find(
        (r) => r.stageId === position.stageId
      );
      if (routine) {
        const periods = [...routine.periodTypes].sort(
          (a, b) => a.sortOrder - b.sortOrder
        );
        const morning = periods.find((p) => p.name.includes('上午'));
        const afternoon = periods.find((p) => p.name.includes('下午'));
        if (morning && afternoon) {
          const morningEndCount = effectiveLessonCount(
            routine,
            morning.id,
            position.weekday
          );
          for (const other of all) {
            if (
              other.id === item.id ||
              other.teacherId !== item.teacherId ||
              other.position?.weekday !== position.weekday ||
              !weekModesOverlap(item.weekMode, other.weekMode)
            ) {
              continue;
            }
            const pair = [position, other.position];
            const atMorningEnd = pair.some(
              (cell) =>
                cell.periodTypeId === morning.id &&
                cell.lessonIndex === morningEndCount
            );
            const atAfternoonStart = pair.some(
              (cell) =>
                cell.periodTypeId === afternoon.id && cell.lessonIndex === 1
            );
            if (atMorningEnd && atAfternoonStart) {
              block('lunchProtection', '教师上午末节与下午首节连续有课', item);
            }
          }
        }
      }
    }
  }

  if (candidateItems.length > 1) {
    for (let i = 0; i < candidateItems.length; i++) {
      const first = candidateItems[i];
      for (let j = i + 1; j < candidateItems.length; j++) {
        const item = candidateItems[j];
        if (!first.position || !item.position) continue;
        const same =
          first.position.stageId === item.position.stageId
            ? sameCell(first.position, item.position)
            : positionHasSameClock(first.position, item.position);
        if (
          first.combinedGroupId != null &&
          first.combinedGroupId === item.combinedGroupId
        ) {
          if (!same || first.weekMode !== item.weekMode) {
            block('combined', '合班课必须同周次且节次时间完全一致', item);
          }
        } else if (
          first.meetingId != null &&
          first.meetingId === item.meetingId &&
          !same
        ) {
          block('pairing', '单双周配对必须共用同一节次', item);
        }
      }
    }
  }

  const unique = new Map<string, ScheduleBlocker>();
  for (const b of blockers) {
    const k = `${b.code}:${b.conditionId ?? null}:${cellKey(b.position)}:${(
      b.relatedIds ?? []
    ).join(',')}`;
    if (!unique.has(k)) unique.set(k, b);
  }
  return Array.from(unique.values());
}

function unmetHardRequirements(
  problem: SchedulingProblem,
  items: ActualScheduleItem[],
  affectedClassIds?: Set<string>
): ScheduleBlocker[] {
  const snapshot = problem.snapshot;
  const hasConditionMinimum = snapshot.conditions.some(
    (c) =>
      (c.kind === 'periodLimit' || c.kind === 'dailyLimit') &&
      (c.exactCount != null || c.minCount != null)
  );
  const hasLessonMinimum = snapshot.lessonConstraints.some(
    (r) =>
      r.minimumDailyLessons != null ||
      r.minimumDailyConsecutivePairs != null ||
      r.minimumWeeklyConsecutivePairs != null
  );
  const hasMustPreset =
    snapshot.subjectPresets.some((p) => p.value === 'must') ||
    snapshot.teacherPresets.some((p) => p.value === 'must') ||
    snapshot.teacherGroupPresets.some((p) => p.value === 'must');
  const hasRequiredProgress =
    snapshot.preferences.detectProgressConsistency &&
    snapshot.preferences.progressConsistency === 'require';

  if (
    !hasConditionMinimum &&
    !hasLessonMinimum &&
    !hasMustPreset &&
    !hasRequiredProgress
  ) {
    return [];
  }

  const allWeekly = items.every((i) => i.weekMode === 'weekly');
  const oddWeekPasses = allWeekly ? [true] : [true, false];

  const unmet: ScheduleBlocker[] = [];
  const byClassSubject = new Map<string, ActualScheduleItem[]>();
  for (const item of items) {
    if (affectedClassIds && !affectedClassIds.has(item.classId)) continue;
    const key = `${item.classId}:${item.subjectId}`;
    const list = byClassSubject.get(key) ?? [];
    list.push(item);
    byClassSubject.set(key, list);
  }

  for (const condition of snapshot.conditions) {
    if (condition.kind !== 'periodLimit' && condition.kind !== 'dailyLimit') {
      continue;
    }
    const minimum = condition.exactCount ?? condition.minCount;
    if (minimum == null) continue;
    const targets = items.filter((item) =>
      conditionTargetMatches(condition, item)
    );
    const classScopes =
      condition.targetKind === 'subject'
        ? Array.from(
            new Set(
              targets
                .map((i) => i.classId)
                .filter((cid) => !affectedClassIds || affectedClassIds.has(cid))
            )
          )
        : [''];
    const weekdays: Array<number | null> =
      condition.weekday == null && condition.kind === 'dailyLimit'
        ? Array.from(
            new Set(
              snapshot.routines.flatMap((r) =>
                r.teachingDays
                  .filter((d) => d.isTeachingDay)
                  .map((d) => d.weekday)
              )
            )
          )
        : [condition.weekday];

    for (const classId of classScopes) {
      for (const weekday of weekdays) {
        for (const oddWeek of oddWeekPasses) {
          if (
            !targets.some(
              (item) =>
                (classId === '' || item.classId === classId) &&
                occursInWeekMode(item.weekMode, oddWeek)
            )
          ) {
            continue;
          }
          const count = targets.filter((item) => {
            const p = item.position;
            return (
              p != null &&
              (classId === '' || item.classId === classId) &&
              (condition.kind !== 'periodLimit' ||
                p.periodTypeId === condition.periodTypeId) &&
              (weekday == null || p.weekday === weekday) &&
              occursInWeekMode(item.weekMode, oddWeek)
            );
          }).length;
          if (count < minimum) {
            const scope = classId === '' ? '' : `班级 ${classId} `;
            const day = weekday == null ? '' : `星期${weekday} `;
            unmet.push({
              code: 'minimum',
              message: `${condition.name ?? condition.id} ${scope}${day}${
                oddWeek ? '单' : '双'
              }周至少 ${minimum} 节，已排 ${count} 节`,
              conditionId: condition.id,
            });
          }
        }
      }
    }
  }

  for (const preset of snapshot.subjectPresets.filter(
    (p) => p.value === 'must'
  )) {
    const relevantClasses = snapshot.classes.filter((schoolClass) => {
      if (affectedClassIds && !affectedClassIds.has(schoolClass.id)) {
        return false;
      }
      const stageId = problem.stageByClass.get(schoolClass.id);
      const gradeId = schoolClass.gradeId;
      return (
        stageId === preset.stageId &&
        (preset.scopeType === 'school' ||
          (preset.scopeType === 'stage' && preset.scopeId === stageId) ||
          (preset.scopeType === 'grade' && preset.scopeId === gradeId) ||
          (preset.scopeType === 'class' && preset.scopeId === schoolClass.id))
      );
    });
    for (const schoolClass of relevantClasses) {
      const subjectItems = byClassSubject.get(
        `${schoolClass.id}:${preset.subjectId}`
      );
      if (!subjectItems) continue;
      const requiredPosition: SchedulePosition = {
        stageId: preset.stageId,
        weekday: preset.weekday,
        periodTypeId: preset.periodTypeId,
        lessonIndex: preset.lessonIndex,
      };
      const effectiveItems = subjectItems.filter(
        (item) =>
          getSubjectPreset(snapshot, problem, item, requiredPosition) === 'must'
      );
      if (effectiveItems.length === 0) continue;
      for (const oddWeek of oddWeekPasses) {
        if (
          !effectiveItems.some((item) =>
            occursInWeekMode(item.weekMode, oddWeek)
          )
        ) {
          continue;
        }
        const exists = effectiveItems.some(
          (item) =>
            item.position != null &&
            sameCell(item.position, requiredPosition) &&
            occursInWeekMode(item.weekMode, oddWeek)
        );
        if (!exists) {
          unmet.push({
            code: 'mustPreset',
            message: `班级 ${schoolClass.id} 科目 ${
              preset.subjectId
            } 的一定排位置未满足（${oddWeek ? '单' : '双'}周）`,
            relatedIds: [schoolClass.id, preset.id],
          });
        }
      }
    }
  }

  if (hasLessonMinimum) {
    for (const subjectItems of byClassSubject.values()) {
      const sample = subjectItems[0];
      const stageId = problem.stageByClass.get(sample.classId);
      const gradeId = problem.gradeByClass.get(sample.classId);
      if (!stageId) continue;
      const subjectRules = snapshot.lessonConstraints.filter(
        (r) =>
          r.subjectId === sample.subjectId &&
          (r.minimumDailyLessons != null ||
            r.minimumDailyConsecutivePairs != null ||
            r.minimumWeeklyConsecutivePairs != null)
      );
      if (subjectRules.length === 0) continue;
      const routine = snapshot.routines.find((r) => r.stageId === stageId);
      if (!routine) continue;
      const teachingDays = routine.teachingDays
        .filter((d) => d.isTeachingDay)
        .map((d) => d.weekday);
      for (const oddWeek of oddWeekPasses) {
        const weeklyRows = subjectItems.filter(
          (row) =>
            row.position != null && occursInWeekMode(row.weekMode, oddWeek)
        );
        let weeklyPairs = 0;
        for (const day of teachingDays) {
          const limits = resolveLessonConstraints({
            constraints: subjectRules,
            scope: 'class',
            scopeId: sample.classId,
            stageId,
            weekday: day,
            parentGradeId: gradeId,
          });
          const dayRows = weeklyRows.filter((r) => r.position!.weekday === day);
          const pairs = consecutivePairCount(snapshot, dayRows);
          weeklyPairs += pairs;
          if (
            limits.minimumDailyLessons != null &&
            dayRows.length < limits.minimumDailyLessons
          ) {
            unmet.push({
              code: 'dailyMinimum',
              message: `班级 ${sample.classId} 科目 ${sample.subjectId} ${
                oddWeek ? '单' : '双'
              }周星期${day} 的日课节下限未满足`,
            });
          }
          if (
            limits.minimumDailyConsecutivePairs != null &&
            pairs < limits.minimumDailyConsecutivePairs
          ) {
            unmet.push({
              code: 'dailyConsecutiveMinimum',
              message: `班级 ${sample.classId} 科目 ${sample.subjectId} ${
                oddWeek ? '单' : '双'
              }周星期${day} 的连堂下限未满足`,
            });
          }
        }
        const weeklyLimits = resolveLessonConstraints({
          constraints: subjectRules,
          scope: 'class',
          scopeId: sample.classId,
          stageId,
          weekday: null,
          parentGradeId: gradeId,
        });
        if (
          weeklyLimits.minimumWeeklyConsecutivePairs != null &&
          weeklyPairs < weeklyLimits.minimumWeeklyConsecutivePairs
        ) {
          unmet.push({
            code: 'weeklyConsecutiveMinimum',
            message: `班级 ${sample.classId} 科目 ${sample.subjectId} ${
              oddWeek ? '单' : '双'
            }周的每周连堂下限未满足`,
          });
        }
      }
    }
  }

  return unmet;
}

// ==================== ActualTimetable 核心引擎 ====================

export class ActualTimetable {
  previewSupervisionSubstitute(params: {
    snapshot: ScheduleData;
    lessons: ActualLesson[];
    supervisions: ActualSupervision[];
    versions: SupervisionVersion[];
    request: TemporarySupervisionSubstituteRequest;
  }): SupervisionSubstitutePreview {
    const { snapshot, lessons, supervisions, versions, request } = params;
    const reqKey = `${request.date.slice(0, 10)}:${request.postId}`;
    const source = supervisions.find((row) => row.key === reqKey);
    const teacher = snapshot.teachers.find((row) => row.id === request.teacherId);
    if (!source || !teacher) {
      return { change: null, errors: ['带班岗位或替班教师不存在'] };
    }
    if (source.teacherId === teacher.id) {
      return { change: null, errors: ['请选择不同的教师'] };
    }
    const version = supervisionVersionForDate(versions, source.date);
    if (!version || !version.draft.teacherIds.includes(teacher.id)) {
      return { change: null, errors: ['教师不在该方案的候选范围'] };
    }
    const unavailable = version.draft.rules[teacher.id]?.unavailable ?? [];
    if (
      source.occurrences.some((row) =>
        unavailable.some((slot) => sameCell(slot, row.position))
      )
    ) {
      return { change: null, errors: ['教师在该节次禁排带班'] };
    }
    const conflict = actualSupervisionConflict(
      snapshot,
      lessons,
      supervisions,
      source,
      teacher.id
    );
    if (conflict) {
      return { change: null, errors: [conflict] };
    }
    return {
      change: {
        before: source,
        after: supervisionWithTeacher(
          source,
          teacher.id,
          getTeacherDisplayName(teacher)
        ),
      },
      errors: [],
    };
  }

  checkSupervisionChanges(
    supervisions: ActualSupervision[],
    changes: ActualLessonChange[]
  ): string[] {
    if (supervisions.length === 0 || changes.length === 0) return [];
    const errors = new Set<string>();
    for (const change of changes) {
      const target = change.after;
      const position = target.item.position;
      if (!position) continue;
      for (const supervision of supervisions) {
        if (
          supervision.date !== target.date ||
          (supervision.teacherId !== target.item.teacherId &&
            !supervision.classIds.includes(target.item.classId))
        ) {
          continue;
        }
        if (
          supervision.occurrences.some((row) =>
            positionsConflictOnDate(row.position, position)
          )
        ) {
          errors.add(
            `${dateConflictLabel(target.date)}与「${
              supervision.post.name
            }」带班冲突`
          );
        }
      }
    }
    return Array.from(errors);
  }

  expandSupervision(
    snapshot: ScheduleData,
    exceptions: CalendarException[],
    versions: SupervisionVersion[]
  ): ActualSupervision[] {
    if (versions.length === 0) return [];
    const result: ActualSupervision[] = [];
    for (const day of this.actualDays(snapshot, exceptions)) {
      const version = supervisionVersionForDate(versions, day.date);
      if (!version) continue;
      const byPost = new Map<string, SupervisionOccurrence[]>();
      for (const row of version.occurrences) {
        if (row.position.weekday === day.weekday) {
          const list = byPost.get(row.post.id) ?? [];
          list.push(row);
          byPost.set(row.post.id, list);
        }
      }
      for (const rows of byPost.values()) {
        rows.sort((a, b) => a.position.lessonIndex - b.position.lessonIndex);
        result.push(
          createActualSupervision({
            date: day.date,
            occurrences: rows,
            teacherId: rows[0].teacherId,
            teacherName: rows[0].teacherName,
            eligibleTeacherIds: version.draft.teacherIds,
            templateWeek: day.templateWeek,
          })
        );
      }
    }
    return result;
  }

  expand(
    snapshot: ScheduleData,
    exceptions: CalendarException[]
  ): ActualLesson[] {
    const problem = buildSchedulingProblem(snapshot);
    const result: ActualLesson[] = [];
    for (const day of this.actualDays(snapshot, exceptions)) {
      for (const item of snapshot.items) {
        if (
          !item.teacherId ||
          item.weekday == null ||
          item.stageId == null ||
          item.periodTypeId == null ||
          item.lessonIndex == null
        ) {
          continue;
        }
        if (
          item.weekday !== day.weekday ||
          !occursInWeekMode(item.weekMode, day.templateWeek % 2 === 1)
        ) {
          continue;
        }
        const raw: SchedulePosition = {
          stageId: item.stageId,
          weekday: item.weekday,
          periodTypeId: item.periodTypeId,
          lessonIndex: item.lessonIndex,
        };
        const canonical =
          (problem.positionsByClass.get(item.classId) ?? []).find((c) =>
            sameCell(c, raw)
          ) ?? raw;
        const actualItem: ActualScheduleItem = {
          id: item.id,
          termId: item.termId,
          assignmentId: item.assignmentId,
          classId: item.classId,
          teacherId: item.teacherId,
          subjectId: item.subjectId,
          weekMode: item.weekMode,
          combinedGroupId: item.combinedGroupId,
          meetingId: item.meetingId,
          position: canonical,
        };
        result.push(
          createActualLesson({
            date: day.date,
            item: actualItem,
          })
        );
      }
    }
    return result;
  }

  private *actualDays(
    snapshot: ScheduleData,
    exceptions: CalendarException[]
  ): Iterable<{ date: string; weekday: number; templateWeek: number }> {
    const start = getWeek1MondayAnchor(snapshot.term);
    if (!start) return;
    const exceptionsByDay = new Map<string, CalendarException>();
    for (const ex of exceptions) {
      exceptionsByDay.set(ex.date.slice(0, 10), ex);
    }
    const totalDays = snapshot.term.teachingWeekCount * 7;
    for (let offset = 0; offset < totalDays; offset++) {
      const d = new Date(
        start.getFullYear(),
        start.getMonth(),
        start.getDate() + offset
      );
      const ymd = formatDateYmd(d);
      const exception = exceptionsByDay.get(ymd);
      if (exception?.kind === 'holiday') continue;
      const templateDate = exception?.makeupForDate?.slice(0, 10) ?? ymd;
      const templateWeek = getTeachingWeekOfDate(snapshot.term, templateDate);
      if (templateWeek == null) continue;
      yield {
        date: ymd,
        weekday: exception?.makeupWeekday ?? getIsoWeekday(d),
        templateWeek,
      };
    }
  }

  apply(
    lessons: ActualLesson[],
    changes: ActualLessonChange[]
  ): ActualLesson[] {
    if (changes.length === 0) return lessons;
    const replacements = new Map<string, ActualLesson>();
    for (const change of changes) {
      replacements.set(change.before.key, change.after);
    }
    return lessons.map((lesson) => replacements.get(lesson.key) ?? lesson);
  }

  checkChanges(
    snapshot: ScheduleData,
    lessons: ActualLesson[],
    changes: ActualLessonChange[]
  ): ActualChangePreview {
    return this.checkHardChanges(snapshot, lessons, {
      changes,
      errors: [],
      skippedDates: [],
    });
  }

  previewSubstitute(params: {
    snapshot: ScheduleData;
    lessons: ActualLesson[];
    exceptions: CalendarException[];
    sourceKey: string;
    teacherId: string;
    subjectId?: string | null;
    problem?: SchedulingProblem;
  }): ActualChangePreview {
    const {
      snapshot,
      lessons,
      exceptions,
      sourceKey,
      teacherId,
      subjectId,
      problem,
    } = params;
    const resolvedProblem = problem ?? buildSchedulingProblem(snapshot);
    const index = getLessonsIndex(lessons, resolvedProblem);
    const source = index.byKey.get(sourceKey);
    if (
      !source ||
      !source.item.position ||
      !snapshot.teachers.some((t) => t.id === teacherId) ||
      (subjectId != null && !snapshot.subjects.some((s) => s.id === subjectId))
    ) {
      return {
        changes: [],
        errors: ['课次、代课教师或科目不存在'],
        skippedDates: [],
      };
    }
    if (
      snapshot.locks.some(
        (lock) =>
          lock.scope === 'teacher' &&
          (lock.targetId === source.item.teacherId ||
            lock.targetId === teacherId)
      )
    ) {
      return { changes: [], errors: ['教师课表已锁定'], skippedDates: [] };
    }
    if (
      teacherId === source.item.teacherId &&
      (subjectId == null || subjectId === source.item.subjectId)
    ) {
      return {
        changes: [],
        errors: ['请选择不同的教师或科目'],
        skippedDates: [],
      };
    }
    const group =
      source.item.meetingId == null
        ? [source]
        : index.byMeetingAndDate.get(`${source.item.meetingId}:${source.date}`) ?? [
            source,
          ];
    if (
      group.some((member) =>
        snapshot.locks.some(
          (lock) =>
            lock.scope === 'teacher' && lock.targetId === member.item.teacherId
        )
      )
    ) {
      return { changes: [], errors: ['教师课表已锁定'], skippedDates: [] };
    }
    const replacements = new Map<string, ActualLesson>();
    for (const member of group) {
      const original = member.item;
      replacements.set(
        member.key,
        createActualLesson({
          date: member.date,
          originDate: member.originDate,
          item: {
            ...original,
            teacherId,
            subjectId: subjectId ?? original.subjectId,
          },
        })
      );
    }
    const proposal = this.internalPreviewMove({
      snapshot,
      lessons: lessons.map((l) => replacements.get(l.key) ?? l),
      exceptions,
      sourceKey,
      targetDate: source.date,
      targetPosition: source.item.position,
      problem: resolvedProblem,
    });
    const result: ActualChangePreview = {
      changes:
        proposal.errors.length === 0
          ? group.map((member) => ({
              before: member,
              after: replacements.get(member.key)!,
            }))
          : [],
      errors: proposal.errors,
      skippedDates: [],
    };
    return this.checkHardChanges(snapshot, lessons, result, resolvedProblem);
  }

  previewSwap(params: {
    snapshot: ScheduleData;
    lessons: ActualLesson[];
    exceptions: CalendarException[];
    firstKey: string;
    secondKey: string;
    problem?: SchedulingProblem;
  }): ActualChangePreview {
    const { snapshot, lessons, exceptions, firstKey, secondKey, problem } =
      params;
    const resolvedProblem = problem ?? buildSchedulingProblem(snapshot);
    const index = getLessonsIndex(lessons, resolvedProblem);
    const first = index.byKey.get(firstKey);
    const second = index.byKey.get(secondKey);
    if (
      !first ||
      !second ||
      firstKey === secondKey ||
      first.item.classId !== second.item.classId ||
      !first.item.position ||
      !second.item.position
    ) {
      return {
        changes: [],
        errors: ['请选择同一班级的另一课次'],
        skippedDates: [],
      };
    }
    const groupFor = (item: ActualLesson): ActualLesson[] =>
      item.item.meetingId == null
        ? [item]
        : index.byMeetingAndDate.get(`${item.item.meetingId}:${item.date}`) ?? [
            item,
          ];
    const firstGroup = groupFor(first);
    const secondGroup = groupFor(second);
    const firstClasses = new Set(firstGroup.map((i) => i.item.classId));
    const secondClasses = new Set(secondGroup.map((i) => i.item.classId));
    const sameClassSet =
      firstClasses.size === secondClasses.size &&
      Array.from(firstClasses).every((id) => secondClasses.has(id));
    if (
      !sameClassSet ||
      firstClasses.size !== firstGroup.length ||
      secondClasses.size !== secondGroup.length
    ) {
      return {
        changes: [],
        errors: ['两个课组的参与班级不一致，无法整体换课'],
        skippedDates: [],
      };
    }

    const firstKeys = new Set(firstGroup.map((i) => i.key));
    const secondKeys = new Set(secondGroup.map((i) => i.key));
    const firstMove = this.internalPreviewMove({
      snapshot,
      lessons,
      exceptions,
      sourceKey: firstKey,
      targetDate: second.date,
      targetPosition: second.item.position,
      problem: resolvedProblem,
      ignoredKeys: secondKeys,
      index,
    });
    const secondMove = this.internalPreviewMove({
      snapshot,
      lessons,
      exceptions,
      sourceKey: secondKey,
      targetDate: first.date,
      targetPosition: first.item.position,
      problem: resolvedProblem,
      ignoredKeys: firstKeys,
      index,
    });
    const errors = [...firstMove.errors, ...secondMove.errors];
    const changes: ActualLessonChange[] = [];
    if (errors.length === 0) {
      for (const change of firstMove.changes) {
        const counterpart = secondMove.changes.find(
          (other) => other.before.item.classId === change.before.item.classId
        );
        if (!counterpart) {
          errors.push('课组班级不一致');
          break;
        }
        changes.push(change, counterpart);
      }
    }
    if (errors.length === 0) {
      const proposed = this.apply(lessons, changes);
      const proposedIndex = getLessonsIndex(proposed, resolvedProblem);
      for (const change of changes) {
        const after = change.after;
        const checked = this.internalPreviewMove({
          snapshot,
          lessons: proposed,
          exceptions,
          sourceKey: after.key,
          targetDate: after.date,
          targetPosition: after.item.position!,
          problem: resolvedProblem,
          index: proposedIndex,
        });
        errors.push(...checked.errors);
      }
    }
    const uniqueErrors = Array.from(new Set(errors));
    return this.checkHardChanges(
      snapshot,
      lessons,
      {
        changes: uniqueErrors.length === 0 ? changes : [],
        errors: uniqueErrors,
        skippedDates: [],
      },
      resolvedProblem
    );
  }

  previewMove(params: {
    snapshot: ScheduleData;
    lessons: ActualLesson[];
    exceptions: CalendarException[];
    sourceKey: string;
    targetDate: string;
    targetPosition: SchedulePosition;
    problem?: SchedulingProblem;
  }): ActualChangePreview {
    const resolvedProblem =
      params.problem ?? buildSchedulingProblem(params.snapshot);
    const preview = this.internalPreviewMove({
      ...params,
      problem: resolvedProblem,
    });
    return this.checkHardChanges(
      params.snapshot,
      params.lessons,
      preview,
      resolvedProblem
    );
  }

  private internalPreviewMove(params: {
    snapshot: ScheduleData;
    lessons: ActualLesson[];
    exceptions: CalendarException[];
    sourceKey: string;
    targetDate: string;
    targetPosition: SchedulePosition;
    groupPart?: boolean;
    problem?: SchedulingProblem;
    ignoredKeys?: Set<string>;
    index?: LessonsIndex;
  }): ActualChangePreview {
    const {
      snapshot,
      lessons,
      exceptions,
      sourceKey,
      groupPart = false,
      problem,
      ignoredKeys,
    } = params;
    const resolvedProblem = problem ?? buildSchedulingProblem(snapshot);
    const index = params.index ?? getLessonsIndex(lessons, resolvedProblem);
    const targetDate = params.targetDate.slice(0, 10);
    let targetPosition = params.targetPosition;
    const source = index.byKey.get(sourceKey);
    const errors: string[] = [];
    if (!source || ignoredKeys?.has(source.key)) {
      return { changes: [], errors: ['原课次不存在'], skippedDates: [] };
    }

    const canonicalTarget = (
      resolvedProblem.positionsByClass.get(source.item.classId) ?? []
    ).find((p) => sameCell(p, targetPosition));
    if (canonicalTarget) targetPosition = canonicalTarget;

    if (!groupPart && source.item.meetingId != null) {
      const rawGroup =
        index.byMeetingAndDate.get(`${source.item.meetingId}:${source.date}`) ??
        [];
      const group = ignoredKeys
        ? rawGroup.filter((l) => !ignoredKeys.has(l.key))
        : rawGroup;
      if (group.length > 1) {
        const keys = new Set(group.map((l) => l.key));
        const changes: ActualLessonChange[] = [];
        const groupErrors: string[] = [];
        for (const member of group) {
          const allowed =
            resolvedProblem.positionsByClass.get(member.item.classId) ?? [];
          const destination = allowed.find((p) =>
            p.stageId === targetPosition.stageId
              ? sameCell(p, targetPosition)
              : positionHasSameClock(p, targetPosition)
          );
          if (!destination) {
            groupErrors.push('合班成员的目标节次不存在或时间不一致');
            continue;
          }
          const combinedIgnored = new Set<string>(ignoredKeys ?? []);
          for (const k of keys) {
            if (k !== member.key) combinedIgnored.add(k);
          }
          const preview = this.internalPreviewMove({
            snapshot,
            lessons,
            exceptions,
            sourceKey: member.key,
            targetDate,
            targetPosition: destination,
            groupPart: true,
            problem: resolvedProblem,
            ignoredKeys: combinedIgnored,
            index,
          });
          groupErrors.push(...preview.errors);
          changes.push(...preview.changes);
        }
        if (groupErrors.length === 0 && changes.length === group.length) {
          const normalized = (lesson: ActualLesson): ActualScheduleItem => ({
            ...lesson.item,
            id: lesson.key,
            weekMode: 'weekly',
          });
          const candidate = changes.map((c) => normalized(c.after));
          const week = getCachedWeekOfDate(index, snapshot, targetDate);
          const weekLessons = (week != null ? index.byWeek.get(week) : null) ?? [];
          const others = weekLessons
            .filter(
              (l) =>
                !keys.has(l.key) &&
                !ignoredKeys?.has(l.key) &&
                l.item.position != null
            )
            .map(normalized);
          const dayLessons = index.byDate.get(targetDate) ?? [];
          const sameDayKeys = new Set(
            dayLessons
              .filter((l) => !ignoredKeys?.has(l.key))
              .map((l) => l.key)
          );
          const blockers = this.evaluatePlacementByDate(
            resolvedProblem,
            others,
            candidate,
            sameDayKeys
          );
          groupErrors.push(...blockers.map((b) => b.message));
        }
        return {
          changes: groupErrors.length === 0 ? changes : [],
          errors: groupErrors,
          skippedDates: [],
        };
      }
      if (source.item.combinedGroupId != null) {
        return {
          changes: [],
          errors: ['合班课组不完整，请先处理课表'],
          skippedDates: [],
        };
      }
    }

    if (
      snapshot.locks.some(
        (lock) =>
          (lock.scope === 'class' && lock.targetId === source.item.classId) ||
          (lock.scope === 'teacher' && lock.targetId === source.item.teacherId)
      )
    ) {
      errors.push('班级或教师课表已锁定');
    }

    const stage = resolvedProblem.stageByClass.get(source.item.classId);
    const checkCrossStageClock = (stages: Set<string>, resource: string) => {
      if (stages.size < 2) return;
      for (const stageId of stages) {
        if (!resolvedProblem.stageHasFullClock.get(stageId)) {
          errors.push(`${resource}涉及跨学段，学段 ${stageId} 缺少完整节次时间`);
        }
      }
    };

    const teacherStages = new Set<string>(
      index.stagesByTeacher.get(source.item.teacherId) ?? []
    );
    if (stage) teacherStages.add(stage);
    checkCrossStageClock(teacherStages, '教师');

    if (source.item.combinedGroupId != null) {
      const groupStages = new Set<string>();
      if (stage) groupStages.add(stage);
      for (const item of snapshot.items) {
        if (item.combinedGroupId === source.item.combinedGroupId) {
          const st = resolvedProblem.stageByClass.get(item.classId);
          if (st) groupStages.add(st);
        }
      }
      checkCrossStageClock(groupStages, '合班课');
    }

    if (stage && snapshot.roomAssignments.length > 0) {
      const room = resolveSubjectRoomAssignment({
        assignments: snapshot.roomAssignments,
        subjectId: source.item.subjectId,
        termId: snapshot.term.id,
        stageId: stage,
        scope: 'class',
        scopeId: source.item.classId,
        parentGradeId: resolvedProblem.gradeByClass.get(source.item.classId),
      })?.roomId;
      if (room) {
        const roomStages = new Set<string>([stage]);
        for (const a of snapshot.roomAssignments) {
          if (a.roomId === room) roomStages.add(a.stageId);
        }
        checkCrossStageClock(roomStages, '公共场室');
      }
    }

    const exception = exceptions.find(
      (e) => e.date.slice(0, 10) === targetDate
    );
    if (exception?.kind === 'holiday') {
      errors.push('目标日期停课');
    }
    const templateWeekday =
      exception?.makeupWeekday ?? getIsoWeekday(targetDate);
    const routine = snapshot.routines.find((r) => r.stageId === stage);
    const period = routine?.periodTypes.find(
      (p) => p.id === targetPosition.periodTypeId
    );
    const isTeachingDay =
      routine?.teachingDays.some(
        (d) => d.weekday === targetPosition.weekday && d.isTeachingDay
      ) ?? false;
    const targetWeek = getCachedWeekOfDate(index, snapshot, targetDate);
    if (
      stage !== targetPosition.stageId ||
      !routine ||
      !period ||
      targetPosition.weekday !== templateWeekday ||
      !isTeachingDay ||
      targetPosition.lessonIndex < 1 ||
      targetPosition.lessonIndex >
        effectiveLessonCount(routine, period.id, targetPosition.weekday) ||
      targetWeek == null
    ) {
      errors.push('目标课位不存在');
    }

    // 仅扫描目标自然日的课次（约 20~50 条），避免扫描全学期 10,000+ 条课次
    const sameDayLessons = index.byDate.get(targetDate) ?? [];
    for (const other of sameDayLessons) {
      if (
        other.key === source.key ||
        ignoredKeys?.has(other.key) ||
        !other.item.position
      ) {
        continue;
      }
      const rawPosition = other.item.position;
      const position =
        (resolvedProblem.positionsByClass.get(other.item.classId) ?? []).find(
          (p) => sameCell(p, rawPosition)
        ) ?? rawPosition;
      const isOverlap =
        targetPosition.stageId === position.stageId
          ? (targetPosition.periodTypeId === position.periodTypeId &&
              targetPosition.lessonIndex === position.lessonIndex) ||
            (hasClockTime(targetPosition) &&
              hasClockTime(position) &&
              targetPosition.startMinute! < position.endMinute! &&
              position.startMinute! < targetPosition.endMinute!)
          : hasClockTime(targetPosition) &&
            hasClockTime(position) &&
            targetPosition.startMinute! < position.endMinute! &&
            position.startMinute! < targetPosition.endMinute!;

      if (isOverlap && source.item.classId === other.item.classId) {
        errors.push(
          `换入「${lessonConflictLabel(snapshot, source)}」时，` +
            `班级「${classConflictLabel(snapshot, other.item.classId)}」在` +
            `${dateConflictLabel(targetDate)}${positionConflictLabel(
              snapshot,
              position
            )}` +
            `已有「${lessonConflictLabel(snapshot, other)}」`
        );
      }
      if (isOverlap && source.item.teacherId === other.item.teacherId) {
        const teacher = snapshot.teachers.find(
          (t) => t.id === source.item.teacherId
        );
        const teacherName = teacher
          ? getTeacherDisplayName(teacher)
          : source.item.teacherId;
        errors.push(
          `换入「${lessonConflictLabel(
            snapshot,
            source
          )}」时，教师「${teacherName}」` +
            `在${dateConflictLabel(targetDate)}${positionConflictLabel(
              snapshot,
              position
            )}` +
            `已为「${classConflictLabel(snapshot, other.item.classId)}」上` +
            `「${lessonConflictLabel(snapshot, other)}」`
        );
      }
      if (
        !isOverlap &&
        targetPosition.stageId !== position.stageId &&
        source.item.teacherId === other.item.teacherId &&
        (!hasClockTime(targetPosition) || !hasClockTime(position))
      ) {
        errors.push('跨学段教师缺少节次时间');
      }
    }

    if (errors.length === 0) {
      const actualItem = (
        lesson: ActualLesson,
        pos: SchedulePosition
      ): ActualScheduleItem => ({
        ...lesson.item,
        id: lesson.key,
        weekMode: 'weekly',
        position: pos,
      });
      const weekLessons =
        (targetWeek != null ? index.byWeek.get(targetWeek) : null) ?? [];
      const placed = weekLessons
        .filter(
          (l) =>
            l.key !== source.key &&
            !ignoredKeys?.has(l.key) &&
            l.item.position != null
        )
        .map((l) => actualItem(l, l.item.position!));
      const candidate = actualItem(source, targetPosition);
      const sameDayKeys = new Set(
        sameDayLessons
          .filter((l) => !ignoredKeys?.has(l.key))
          .map((l) => l.key)
      );
      const blockers = this.evaluatePlacementByDate(
        resolvedProblem,
        placed,
        [candidate],
        sameDayKeys
      );
      errors.push(...blockers.map((b) => b.message));
    }

    if (errors.length > 0) {
      return { changes: [], errors, skippedDates: [] };
    }

    return {
      changes: [
        {
          before: source,
          after: createActualLesson({
            date: targetDate,
            originDate: source.originDate,
            item: actualItemAt(source.item, targetPosition),
          }),
        },
      ],
      errors: [],
      skippedDates: [],
    };
  }

  private evaluatePlacementByDate(
    problem: SchedulingProblem,
    placed: ActualScheduleItem[],
    candidateItems: ActualScheduleItem[],
    sameDayKeys: Set<string>
  ): ScheduleBlocker[] {
    const weekly = evaluatePlacement(problem, placed, candidateItems);
    const daily = evaluatePlacement(
      problem,
      placed.filter((item) => sameDayKeys.has(item.id)),
      candidateItems
    );
    const isDailyRule = (blocker: ScheduleBlocker): boolean => {
      if (
        [
          'classOccupied',
          'teacherOccupied',
          'teacherMutualExclusion',
          'subjectMutualExclusion',
          'forbiddenAdjacency',
          'subjectDailyMaximum',
          'dailyConsecutiveMaximum',
          'parallelLimit',
          'roomCapacity',
          'consecutive',
          'lunchProtection',
        ].includes(blocker.code)
      ) {
        return true;
      }
      if (blocker.code === 'conditionMaximum') {
        const condition = problem.snapshot.conditions.find(
          (item) => item.id === blocker.conditionId
        );
        return (
          condition != null &&
          (condition.kind === 'dailyLimit' || condition.weekday != null)
        );
      }
      return false;
    };
    return [
      ...weekly.filter((b) => !isDailyRule(b)),
      ...daily.filter((b) => isDailyRule(b)),
    ];
  }

  private checkHardChanges(
    snapshot: ScheduleData,
    lessons: ActualLesson[],
    preview: ActualChangePreview,
    problem?: SchedulingProblem
  ): ActualChangePreview {
    if (preview.errors.length > 0 || preview.changes.length === 0) {
      return preview;
    }
    const resolvedProblem = problem ?? buildSchedulingProblem(snapshot);
    const oldIndex = getLessonsIndex(lessons, resolvedProblem);
    const after = this.apply(lessons, preview.changes);
    const newIndex = getLessonsIndex(after, resolvedProblem);

    const weeks = new Set<number>();
    const affectedClassIds = new Set<string>();
    for (const change of preview.changes) {
      affectedClassIds.add(change.before.item.classId);
      affectedClassIds.add(change.after.item.classId);
      const beforeWeek = getCachedWeekOfDate(
        oldIndex,
        snapshot,
        change.before.date
      );
      const afterWeek = getCachedWeekOfDate(
        oldIndex,
        snapshot,
        change.after.date
      );
      if (beforeWeek != null) weeks.add(beforeWeek);
      if (afterWeek != null) weeks.add(afterWeek);
    }

    const normalize = (
      lesson: ActualLesson,
      unplaced = false
    ): ActualScheduleItem => ({
      ...lesson.item,
      id: lesson.key,
      weekMode: 'weekly',
      position: unplaced ? null : lesson.item.position,
    });

    const errors: string[] = [];
    for (const week of weeks) {
      const oldLessons = oldIndex.byWeek.get(week) ?? [];
      const newLessons = newIndex.byWeek.get(week) ?? [];
      const oldKeys = new Set(oldLessons.map((l) => l.key));
      const newKeys = new Set(newLessons.map((l) => l.key));
      const oldItems: ActualScheduleItem[] = [
        ...oldLessons.map((l) => normalize(l)),
        ...newLessons
          .filter((l) => !oldKeys.has(l.key))
          .map((l) => normalize(l, true)),
      ];
      const newItems: ActualScheduleItem[] = [
        ...newLessons.map((l) => normalize(l)),
        ...oldLessons
          .filter((l) => !newKeys.has(l.key))
          .map((l) => normalize(l, true)),
      ];
      const oldBlockers = new Map<string, ScheduleBlocker>();
      for (const b of unmetHardRequirements(
        resolvedProblem,
        oldItems,
        affectedClassIds
      )) {
        oldBlockers.set(blockerIdentity(b), b);
      }
      for (const b of unmetHardRequirements(
        resolvedProblem,
        newItems,
        affectedClassIds
      )) {
        const prev = oldBlockers.get(blockerIdentity(b));
        const prevCount = prev ? blockerPlacedCount(prev) : null;
        const currCount = blockerPlacedCount(b);
        if (
          !prev ||
          (prevCount != null && currCount != null && currCount < prevCount)
        ) {
          errors.push(`第 ${week} 周：${b.message}`);
        }
      }
    }
    return errors.length === 0
      ? preview
      : { changes: [], errors, skippedDates: preview.skippedDates };
  }
}

// ==================== TemporaryTimetableState ====================

export class TemporaryTimetableState {
  readonly snapshot: ScheduleData;
  readonly exceptions: CalendarException[];
  readonly records: TemporaryAdjustmentRecord[];
  readonly lessons: ActualLesson[];
  readonly revision: string;
  readonly reconciliationPending: boolean;
  readonly supervisions: ActualSupervision[];
  readonly supervisionVersions: SupervisionVersion[];
  readonly hasSupervisionCalendar: boolean;

  constructor(params: {
    snapshot: ScheduleData;
    exceptions: CalendarException[];
    records: TemporaryAdjustmentRecord[];
    lessons: ActualLesson[];
    revision: string;
    reconciliationPending: boolean;
    supervisions?: ActualSupervision[];
    supervisionVersions?: SupervisionVersion[];
    hasSupervisionCalendar?: boolean;
  }) {
    this.snapshot = params.snapshot;
    this.exceptions = params.exceptions;
    this.records = params.records;
    this.lessons = params.lessons;
    this.revision = params.revision;
    this.reconciliationPending = params.reconciliationPending;
    this.supervisions = params.supervisions ?? [];
    this.supervisionVersions = params.supervisionVersions ?? [];
    this.hasSupervisionCalendar = params.hasSupervisionCalendar ?? false;
  }

  stageIdForClass(classId: string): string | undefined {
    const cls = this.snapshot.classes.find((c) => c.id === classId);
    return this.snapshot.grades.find((g) => g.id === cls?.gradeId)?.stageId;
  }

  gradeIdForClass(classId: string): string | undefined {
    return this.snapshot.classes.find((c) => c.id === classId)?.gradeId;
  }

  previewSupervisionSubstitute(
    request: TemporarySupervisionSubstituteRequest
  ): SupervisionSubstitutePreview {
    if (this.reconciliationPending) {
      return { change: null, errors: ['请先完成课表协调'] };
    }
    const reqKey = `${request.date.slice(0, 10)}:${request.postId}`;
    if (
      this.records.some(
        (record) =>
          record.cancelledAt == null &&
          record.supervisionChange?.before.key === reqKey
      )
    ) {
      return { change: null, errors: ['该岗位已有替班记录，请先撤销'] };
    }
    return new ActualTimetable().previewSupervisionSubstitute({
      snapshot: this.snapshot,
      lessons: this.lessons,
      supervisions: this.supervisions,
      versions: this.supervisionVersions,
      request,
    });
  }

  private originalOccurrence(
    anchor: ActualLesson,
    date: string
  ): ActualLesson | undefined {
    const offset = diffDaysYmd(date, anchor.date);
    const origin = addDaysYmd(anchor.originDate, offset);
    return this.lessons.find(
      (item) =>
        item.item.id === anchor.item.id &&
        item.originDate === origin &&
        item.date === date
    );
  }

  previewMove(
    request: TemporaryMoveRequest,
    problem?: SchedulingProblem
  ): ActualChangePreview {
    if (this.reconciliationPending) {
      return { changes: [], errors: ['请先完成课表协调'], skippedDates: [] };
    }
    const resolvedProblem = problem ?? buildSchedulingProblem(this.snapshot);
    if (request.rangeStart != null || request.rangeEnd != null) {
      const start = request.rangeStart?.slice(0, 10);
      const end = request.rangeEnd?.slice(0, 10);
      const source = this.lessons.find((l) => l.key === request.sourceKey);
      if (!start || !end || end < start || !source) {
        return {
          changes: [],
          errors: ['日期范围或原课次无效'],
          skippedDates: [],
        };
      }
      const engine = new ActualTimetable();
      let projected = this.lessons;
      const changes: ActualLessonChange[] = [];
      const errors: string[] = [];
      const skipped: string[] = [];
      const usedKeys = new Set<string>();
      const sourceWeekday = getIsoWeekday(source.date);
      const excluded = request.excludedDates ?? new Set<string>();

      for (
        let date = start;
        date <= end;
        date = addDaysYmd(date, 1)
      ) {
        if (getIsoWeekday(date) !== sourceWeekday || excluded.has(date)) {
          continue;
        }
        const original = this.originalOccurrence(source, date);
        const lesson = original
          ? projected.find((item) => item.key === original.key)
          : undefined;
        if (!lesson) {
          skipped.push(date);
          continue;
        }
        const delta = diffDaysYmd(date, source.date);
        const targetDate = addDaysYmd(request.targetDate.slice(0, 10), delta);
        if (targetDate < start || targetDate > end) {
          errors.push(`${date}：目标日期超出范围`);
          continue;
        }
        const preview = engine.previewMove({
          snapshot: this.snapshot,
          lessons: projected,
          exceptions: this.exceptions,
          sourceKey: lesson.key,
          targetDate,
          targetPosition: request.targetPosition,
          problem: resolvedProblem,
        });
        if (preview.errors.length > 0) {
          errors.push(...preview.errors.map((err) => `${date}：${err}`));
        } else if (
          preview.changes.some((c) => usedKeys.has(c.before.key))
        ) {
          errors.push(`${date}：课次已被本次其他调整使用`);
        } else {
          for (const c of preview.changes) usedKeys.add(c.before.key);
          changes.push(...preview.changes);
          projected = engine.apply(projected, preview.changes);
        }
      }
      return this.guardInvalid({
        changes,
        errors,
        skippedDates: skipped,
      });
    }
    return this.guardInvalid(
      new ActualTimetable().previewMove({
        snapshot: this.snapshot,
        lessons: this.lessons,
        exceptions: this.exceptions,
        sourceKey: request.sourceKey,
        targetDate: request.targetDate,
        targetPosition: request.targetPosition,
        problem: resolvedProblem,
      })
    );
  }

  previewSubstitute(
    request: TemporarySubstituteRequest,
    problem?: SchedulingProblem
  ): ActualChangePreview {
    if (this.reconciliationPending) {
      return { changes: [], errors: ['请先完成课表协调'], skippedDates: [] };
    }
    const resolvedProblem = problem ?? buildSchedulingProblem(this.snapshot);
    if (request.rangeStart != null || request.rangeEnd != null) {
      const start = request.rangeStart?.slice(0, 10);
      const end = request.rangeEnd?.slice(0, 10);
      const source = this.lessons.find((l) => l.key === request.sourceKey);
      if (!start || !end || end < start || !source) {
        return {
          changes: [],
          errors: ['日期范围或原课次无效'],
          skippedDates: [],
        };
      }
      const engine = new ActualTimetable();
      let projected = this.lessons;
      const changes: ActualLessonChange[] = [];
      const errors: string[] = [];
      const skipped: string[] = [];
      const usedKeys = new Set<string>();
      const sourceWeekday = getIsoWeekday(source.date);
      const excluded = request.excludedDates ?? new Set<string>();

      for (
        let date = start;
        date <= end;
        date = addDaysYmd(date, 1)
      ) {
        if (getIsoWeekday(date) !== sourceWeekday || excluded.has(date)) {
          continue;
        }
        const original = this.originalOccurrence(source, date);
        const lesson = original
          ? projected.find((item) => item.key === original.key)
          : undefined;
        if (!lesson) {
          skipped.push(date);
          continue;
        }
        const preview = engine.previewSubstitute({
          snapshot: this.snapshot,
          lessons: projected,
          exceptions: this.exceptions,
          sourceKey: lesson.key,
          teacherId: request.teacherId,
          subjectId: request.subjectId,
          problem: resolvedProblem,
        });
        if (preview.errors.length > 0) {
          errors.push(...preview.errors.map((err) => `${date}：${err}`));
        } else if (
          preview.changes.some((c) => usedKeys.has(c.before.key))
        ) {
          errors.push(`${date}：课次已被本次其他调整使用`);
        } else {
          for (const c of preview.changes) usedKeys.add(c.before.key);
          changes.push(...preview.changes);
          projected = engine.apply(projected, preview.changes);
        }
      }
      return this.guardInvalid({
        changes,
        errors,
        skippedDates: skipped,
      });
    }
    return this.guardInvalid(
      new ActualTimetable().previewSubstitute({
        snapshot: this.snapshot,
        lessons: this.lessons,
        exceptions: this.exceptions,
        sourceKey: request.sourceKey,
        teacherId: request.teacherId,
        subjectId: request.subjectId,
        problem: resolvedProblem,
      })
    );
  }

  previewSwap(
    request: TemporarySwapRequest,
    problem?: SchedulingProblem
  ): ActualChangePreview {
    if (this.reconciliationPending) {
      return { changes: [], errors: ['请先完成课表协调'], skippedDates: [] };
    }
    const resolvedProblem = problem ?? buildSchedulingProblem(this.snapshot);
    if (request.rangeStart != null || request.rangeEnd != null) {
      const start = request.rangeStart?.slice(0, 10);
      const end = request.rangeEnd?.slice(0, 10);
      const firstLesson = this.lessons.find((l) => l.key === request.firstKey);
      const secondLesson = this.lessons.find(
        (l) => l.key === request.secondKey
      );
      if (!start || !end || end < start || !firstLesson || !secondLesson) {
        return {
          changes: [],
          errors: ['日期范围或原课次无效'],
          skippedDates: [],
        };
      }
      const engine = new ActualTimetable();
      let projected = this.lessons;
      const changes: ActualLessonChange[] = [];
      const errors: string[] = [];
      const skipped: string[] = [];
      const usedKeys = new Set<string>();
      const firstWeekday = getIsoWeekday(firstLesson.date);
      const excluded = request.excludedDates ?? new Set<string>();

      for (
        let date = start;
        date <= end;
        date = addDaysYmd(date, 1)
      ) {
        if (getIsoWeekday(date) !== firstWeekday || excluded.has(date)) {
          continue;
        }
        const originalSource = this.originalOccurrence(firstLesson, date);
        if (originalSource && usedKeys.has(originalSource.key)) {
          errors.push(`${date}：课次已被本次其他换课使用`);
          continue;
        }
        const source = originalSource
          ? projected.find((l) => l.key === originalSource.key)
          : undefined;
        if (!source) {
          skipped.push(date);
          continue;
        }
        const targetDate = addDaysYmd(
          secondLesson.date,
          diffDaysYmd(date, firstLesson.date)
        );
        if (targetDate < start || targetDate > end) {
          errors.push(`${date}：目标日期超出范围`);
          continue;
        }
        const originalTarget = this.originalOccurrence(
          secondLesson,
          targetDate
        );
        if (originalTarget && usedKeys.has(originalTarget.key)) {
          errors.push(`${date}：目标课次已被本次其他换课使用`);
          continue;
        }
        const target = originalTarget
          ? projected.find((l) => l.key === originalTarget.key)
          : undefined;
        if (!target) {
          errors.push(`${date}：目标课次不存在`);
          continue;
        }
        const preview = engine.previewSwap({
          snapshot: this.snapshot,
          lessons: projected,
          exceptions: this.exceptions,
          firstKey: source.key,
          secondKey: target.key,
          problem: resolvedProblem,
        });
        if (preview.errors.length > 0) {
          errors.push(...preview.errors.map((err) => `${date}：${err}`));
        } else if (
          preview.changes.some((c) => usedKeys.has(c.before.key))
        ) {
          errors.push(`${date}：课组已被本次其他换课使用`);
        } else {
          for (const c of preview.changes) usedKeys.add(c.before.key);
          changes.push(...preview.changes);
          projected = engine.apply(projected, preview.changes);
        }
      }
      return this.guardInvalid({
        changes,
        errors,
        skippedDates: skipped,
      });
    }
    return this.guardInvalid(
      new ActualTimetable().previewSwap({
        snapshot: this.snapshot,
        lessons: this.lessons,
        exceptions: this.exceptions,
        firstKey: request.firstKey,
        secondKey: request.secondKey,
        problem: resolvedProblem,
      })
    );
  }

  private guardInvalid(preview: ActualChangePreview): ActualChangePreview {
    if (preview.changes.length === 0) return preview;
    const supervisionErrors = new ActualTimetable().checkSupervisionChanges(
      this.supervisions,
      preview.changes
    );
    if (supervisionErrors.length > 0) {
      return {
        changes: [],
        errors: supervisionErrors,
        skippedDates: preview.skippedDates,
      };
    }
    for (const invalid of this.records) {
      if (!invalid.needsAttention || invalid.cancelledAt != null) continue;
      for (const stale of invalid.changes) {
        for (const proposed of preview.changes) {
          if (stale.before.key === proposed.before.key) {
            return {
              changes: [],
              errors: ['所选课次存在需要处理的调整记录'],
              skippedDates: preview.skippedDates,
            };
          }
          for (const old of [stale.before, stale.after]) {
            for (const next of [proposed.before, proposed.after]) {
              const sameDate = old.date === next.date;
              const sharedResource =
                old.item.classId === next.item.classId ||
                old.item.teacherId === next.item.teacherId ||
                this.snapshot.roomAssignments.length > 0 ||
                (this.snapshot.parallelLimits.length > 0 &&
                  old.item.subjectId === next.item.subjectId);
              const sameWeekWithRules =
                getTeachingWeekOfDate(this.snapshot.term, old.date) ===
                  getTeachingWeekOfDate(this.snapshot.term, next.date) &&
                (this.snapshot.conditions.length > 0 ||
                  this.snapshot.lessonConstraints.length > 0);
              if ((sameDate && sharedResource) || sameWeekWithRules) {
                return {
                  changes: [],
                  errors: ['相关课次存在需要处理的调整记录'],
                  skippedDates: preview.skippedDates,
                };
              }
            }
          }
        }
      }
    }
    return preview;
  }
}

// ==================== 投影与撤销校验 ====================

export function projectTemporaryTimetable(input: {
  snapshot: ScheduleData;
  exceptions: CalendarException[];
  records: TemporaryAdjustmentRecord[];
  supervisionVersions: SupervisionVersion[];
}): {
  lessons: ActualLesson[];
  records: TemporaryAdjustmentRecord[];
  supervisions: ActualSupervision[];
} {
  const engine = new ActualTimetable();
  const problem = buildSchedulingProblem(input.snapshot);
  let lessons = engine.expand(input.snapshot, input.exceptions);
  const supervisions = engine.expandSupervision(
    input.snapshot,
    input.exceptions,
    input.supervisionVersions
  );
  const records: TemporaryAdjustmentRecord[] = [];

  for (const record of input.records) {
    const supervisionChange = record.supervisionChange;
    if (supervisionChange != null) {
      if (record.cancelledAt != null) {
        records.push(record);
        continue;
      }
      const before = supervisionChange.before;
      const after = supervisionChange.after;
      const index = supervisions.findIndex((row) => row.key === before.key);
      const current = index === -1 ? null : supervisions[index];
      const preview = engine.previewSupervisionSubstitute({
        snapshot: input.snapshot,
        lessons,
        supervisions,
        versions: input.supervisionVersions,
        request: {
          date: before.date,
          postId: before.postId,
          teacherId: after.teacherId,
        },
      });
      const valid =
        current != null &&
        sameSupervisionAssignment(current, before) &&
        preview.change != null &&
        sameSupervisionAssignment(preview.change.after, after);
      if (valid && preview.change) {
        supervisions[index] = preview.change.after;
      }
      records.push(recordWithAttention(record, !valid));
      continue;
    }

    const changes = record.changes;
    let invalid =
      new Set(changes.map((c) => c.before.key)).size !== changes.length;
    if (record.cancelledAt == null) {
      const lessonIdx = getLessonsIndex(lessons, problem);
      for (const change of changes) {
        const current = lessonIdx.byKey.get(change.before.key);
        if (
          !current ||
          JSON.stringify(actualLessonToJson(current)) !==
            JSON.stringify(actualLessonToJson(change.before))
        ) {
          invalid = true;
          break;
        }
      }
      if (!invalid && changes.length > 0) {
        let preview: ActualChangePreview | null = null;
        if (record.kind === 'move' || record.kind === 'substitute') {
          let projected = lessons;
          const verified: ActualLessonChange[] = [];
          const errors: string[] = [];
          for (let index = 0; index < changes.length; ) {
            const change = changes[index];
            const position = change.after.item.position;
            if (!position) {
              errors.push('目标位置不存在');
              break;
            }
            const one =
              record.kind === 'move'
                ? engine.previewMove({
                    snapshot: input.snapshot,
                    lessons: projected,
                    exceptions: input.exceptions,
                    sourceKey: change.before.key,
                    targetDate: change.after.date,
                    targetPosition: position,
                    problem,
                  })
                : engine.previewSubstitute({
                    snapshot: input.snapshot,
                    lessons: projected,
                    exceptions: input.exceptions,
                    sourceKey: change.before.key,
                    teacherId: change.after.item.teacherId,
                    subjectId: change.after.item.subjectId,
                    problem,
                  });
            if (one.errors.length > 0) {
              errors.push(...one.errors);
              break;
            }
            verified.push(...one.changes);
            projected = engine.apply(projected, one.changes);
            if (one.changes.length === 0) {
              errors.push('调整课次为空');
              break;
            }
            index += one.changes.length;
          }
          preview = { changes: verified, errors, skippedDates: [] };
        } else if (record.kind === 'swap' && changes.length % 2 === 0) {
          let projected = lessons;
          const verified: ActualLessonChange[] = [];
          const errors: string[] = [];
          for (let i = 0; i < changes.length; ) {
            const one = engine.previewSwap({
              snapshot: input.snapshot,
              lessons: projected,
              exceptions: input.exceptions,
              firstKey: changes[i].before.key,
              secondKey: changes[i + 1].before.key,
              problem,
            });
            if (one.errors.length > 0) {
              errors.push(...one.errors);
              break;
            }
            verified.push(...one.changes);
            projected = engine.apply(projected, one.changes);
            if (one.changes.length === 0) {
              errors.push('调整课次为空');
              break;
            }
            i += one.changes.length;
          }
          preview = { changes: verified, errors, skippedDates: [] };
        }

        const canonical = (values: ActualLessonChange[]) => {
          const sorted = [...values].sort((a, b) =>
            a.before.key.localeCompare(b.before.key)
          );
          return JSON.stringify(sorted.map(actualLessonChangeToJson));
        };

        if (
          !preview ||
          preview.errors.length > 0 ||
          canonical(preview.changes) !== canonical(changes) ||
          engine.checkSupervisionChanges(supervisions, changes).length > 0
        ) {
          invalid = true;
        }
      } else if (changes.length === 0) {
        invalid = true;
      }
      if (!invalid) {
        lessons = engine.apply(lessons, changes);
      }
    }
    records.push(recordWithAttention(record, invalid));
  }

  return { lessons, records, supervisions };
}

export function validateTemporaryCancellation(
  state: TemporaryTimetableState,
  record: TemporaryAdjustmentRecord,
  index: number
): void {
  const supervisionChange = record.supervisionChange;
  if (supervisionChange != null) {
    if (record.needsAttention) return;
    const before = supervisionChange.before;
    const conflict = actualSupervisionConflict(
      state.snapshot,
      state.lessons,
      state.supervisions,
      before,
      before.teacherId
    );
    if (conflict) {
      throw new Error(`恢复原带班教师存在冲突：${conflict}`);
    }
    return;
  }

  const keys = new Set(record.changes.map((c) => c.before.key));
  if (
    state.records
      .slice(index + 1)
      .some(
        (later) =>
          later.cancelledAt == null &&
          later.changes.some((c) => keys.has(c.before.key))
      )
  ) {
    throw new Error('请先取消引用这些课次的后续调整');
  }

  const activeChanges = record.needsAttention ? [] : record.changes;
  const engine = new ActualTimetable();
  const problem = buildSchedulingProblem(state.snapshot);
  for (const change of activeChanges) {
    const target = change.before.item.position;
    if (!target) throw new Error('原课次位置已失效');
    const preview =
      record.kind === 'substitute'
        ? engine.previewSubstitute({
            snapshot: state.snapshot,
            lessons: state.lessons,
            exceptions: state.exceptions,
            sourceKey: change.after.key,
            teacherId: change.before.item.teacherId,
            subjectId: change.before.item.subjectId,
            problem,
          })
        : engine.previewMove({
            snapshot: state.snapshot,
            lessons: state.lessons.filter(
              (lesson) =>
                !keys.has(lesson.key) ||
                lesson.key === change.after.key ||
                (change.after.item.meetingId != null &&
                  lesson.item.meetingId === change.after.item.meetingId &&
                  lesson.date === change.after.date)
            ),
            exceptions: state.exceptions,
            sourceKey: change.after.key,
            targetDate: change.before.date,
            targetPosition: target,
            problem,
          });
    if (preview.errors.length > 0) {
      throw new Error(`恢复原课次存在冲突：${preview.errors.join('；')}`);
    }
  }

  if (!record.needsAttention) {
    const reverse: ActualLessonChange[] = record.changes.map((c) => ({
      before: c.after,
      after: c.before,
    }));
    const supervisionErrors = engine.checkSupervisionChanges(
      state.supervisions,
      reverse
    );
    if (supervisionErrors.length > 0) {
      throw new Error(`恢复原课次存在冲突：${supervisionErrors.join('；')}`);
    }
    const hardCheck = engine.checkChanges(
      state.snapshot,
      state.lessons,
      reverse
    );
    if (hardCheck.errors.length > 0) {
      throw new Error(`恢复原课次存在冲突：${hardCheck.errors.join('；')}`);
    }
    const restored = engine.apply(state.lessons, reverse);
    for (const change of reverse) {
      const position = change.after.item.position;
      if (!position) throw new Error('原课次位置已失效');
      const check = engine.previewMove({
        snapshot: state.snapshot,
        lessons: restored,
        exceptions: state.exceptions,
        sourceKey: change.after.key,
        targetDate: change.after.date,
        targetPosition: position,
        problem,
      });
      if (check.errors.length > 0) {
        throw new Error(`恢复原课次存在冲突：${check.errors.join('；')}`);
      }
    }
  }
}

export function parseAdjustmentRow(
  row: TemporaryCourseAdjustment
): TemporaryAdjustmentRecord {
  try {
    const parsed = JSON.parse(row.changesJson);
    if (row.kind === SUPERVISION_SUBSTITUTION_KIND) {
      return {
        id: row.id,
        kind: row.kind,
        reason: row.reason,
        createdAt: row.createdAt,
        cancelledAt: row.cancelledAt,
        needsAttention: false,
        supervisionChange: actualSupervisionChangeFromJson(
          parsed as Record<string, unknown>
        ),
        changes: [],
      };
    }
    const list = Array.isArray(parsed) ? parsed : [];
    return {
      id: row.id,
      kind: row.kind,
      reason: row.reason,
      createdAt: row.createdAt,
      cancelledAt: row.cancelledAt,
      needsAttention: false,
      supervisionChange: null,
      changes: list.map((item) =>
        actualLessonChangeFromJson(item as Record<string, unknown>)
      ),
    };
  } catch {
    return {
      id: row.id,
      kind: row.kind,
      reason: row.reason,
      createdAt: row.createdAt,
      cancelledAt: row.cancelledAt,
      needsAttention: true,
      supervisionChange: null,
      changes: [],
    };
  }
}
