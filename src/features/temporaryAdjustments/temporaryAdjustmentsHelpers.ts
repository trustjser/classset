import type {
  AcademicTerm,
  CalendarException,
  ClassGroup,
  GradeGroup,
  StageRoutine,
  Subject,
  Teacher,
} from '@/domain/models';
import type { SchedulePosition } from '@/domain/supervision';
import { hasClockTime, sameCell } from '@/domain/supervision';
import {
  type ActualChangePreview,
  type ActualLesson,
  type ActualLessonChange,
  type ActualSupervision,
  getTeacherDisplayName,
  type SchedulingProblem,
  SUPERVISION_SUBSTITUTION_KIND,
  type TemporaryAdjustmentRecord,
  type TemporaryTimetableState,
} from '@/domain/actualTimetable';
import {
  formatDateYmd,
  getIsoWeekday,
  getTeachingWeekEnd,
  getTeachingWeekOfDate,
  getTeachingWeekStart,
  parseLocalDate,
} from '@/features/terms/calendarUtils';

export type AdjustmentKind = 'swap' | 'move' | 'substitute';

export interface CandidateMoveSlot {
  date: string;
  position: SchedulePosition;
  preview: ActualChangePreview;
}

export function clampWeekIndex(week: number, term: AcademicTerm): number {
  const maxWeek = Math.max(0, term.teachingWeekCount - 1);
  return Math.max(0, Math.min(week, maxWeek));
}

export function defaultWeekIndex(term: AcademicTerm): number {
  const current = (getTeachingWeekOfDate(term, new Date()) ?? 1) - 1;
  return clampWeekIndex(current, term);
}

export function getWeekStartDate(term: AcademicTerm, weekIndex: number): string {
  const monday = getTeachingWeekStart(
    term,
    clampWeekIndex(weekIndex, term) + 1
  );
  if (monday) return formatDateYmd(monday);
  const now = new Date();
  const iso = getIsoWeekday(now);
  now.setDate(now.getDate() - (iso - 1));
  return formatDateYmd(now);
}

export function getTermEndDate(term: AcademicTerm): string {
  const end = getTeachingWeekEnd(term, Math.max(1, term.teachingWeekCount));
  if (end) return formatDateYmd(end);
  return formatDateYmd(new Date());
}

export function formatShortMd(ymd: string): string {
  const d = parseLocalDate(ymd.slice(0, 10));
  return `${d.getMonth() + 1}/${d.getDate()}`;
}

export function formatChineseMdWeekday(ymd: string): string {
  const d = parseLocalDate(ymd.slice(0, 10));
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  const w = getIsoWeekday(d);
  return `${d.getMonth() + 1}月${d.getDate()}日（周${names[w - 1]}）`;
}

export function weekdayShortLabel(weekday: number): string {
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return names[weekday - 1] ?? `周${weekday}`;
}

export function formatTimestampTime(tsSecondsOrMs: number): string {
  const ms = tsSecondsOrMs < 1e11 ? tsSecondsOrMs * 1000 : tsSecondsOrMs;
  const d = new Date(ms);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(
    d.getHours()
  )}:${pad(d.getMinutes())}`;
}

export function formatMinuteClock(minute: number | null | undefined): string | null {
  if (minute == null || !Number.isFinite(minute)) return null;
  const h = Math.floor(minute / 60);
  const m = minute % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

export function getClassDisplayName(
  classId: string,
  classes: ClassGroup[],
  grades: GradeGroup[]
): string {
  const cls = classes.find((c) => c.id === classId);
  if (!cls) return '已移除班级';
  const grade = grades.find((g) => g.id === cls.gradeId);
  if (!grade) return cls.name;
  return cls.name.startsWith(grade.name)
    ? cls.name
    : `${grade.name} ${cls.name}`;
}

export function getSubjectDisplayName(
  subjectId: string,
  subjects: Subject[]
): string {
  return subjects.find((s) => s.id === subjectId)?.name ?? '未命名科目';
}

export function getTeacherNameById(
  teacherId: string,
  teachers: Teacher[]
): string {
  const t = teachers.find((item) => item.id === teacherId);
  return t ? getTeacherDisplayName(t) : '未指派教师';
}

export function getPeriodLessonLabel(
  state: TemporaryTimetableState,
  position: SchedulePosition | null
): string {
  if (!position) return '未排课位';
  const routine = state.snapshot.routines.find(
    (r) => r.stageId === position.stageId
  );
  const period = routine?.periodTypes.find(
    (p) => p.id === position.periodTypeId
  );
  return `${period?.name ?? ''}第 ${position.lessonIndex} 节`;
}

export function getVisibleScheduleDates(
  state: TemporaryTimetableState,
  routine: StageRoutine | undefined,
  weekStartYmd: string
): string[] {
  const teachingWeekdays = new Set<number>(
    routine
      ? routine.teachingDays
          .filter((d) => d.isTeachingDay)
          .map((d) => d.weekday)
      : state.snapshot.routines.flatMap((r) =>
          r.teachingDays.filter((d) => d.isTeachingDay).map((d) => d.weekday)
        )
  );
  const dates: string[] = [];
  const rawStart = parseLocalDate(weekStartYmd);
  const startIso = getIsoWeekday(rawStart);
  const start = new Date(
    rawStart.getFullYear(),
    rawStart.getMonth(),
    rawStart.getDate() - (startIso - 1)
  );
  for (let i = 0; i < 7; i++) {
    const d = new Date(
      start.getFullYear(),
      start.getMonth(),
      start.getDate() + i
    );
    const ymd = formatDateYmd(d);
    const isoWeekday = getIsoWeekday(d);
    const exception = state.exceptions.find(
      (e) => e.date.slice(0, 10) === ymd
    );
    if (exception?.kind === 'holiday' && isoWeekday >= 6) {
      continue;
    }
    const scheduleWeekday = exception?.makeupWeekday ?? isoWeekday;
    if (exception != null || teachingWeekdays.has(scheduleWeekday)) {
      dates.push(ymd);
    }
  }
  return dates;
}

export function getScheduleWeekdayForDate(
  exceptions: CalendarException[],
  ymd: string
): number | null {
  const ex = exceptions.find((e) => e.date.slice(0, 10) === ymd);
  if (ex?.kind === 'holiday') return null;
  return ex?.makeupWeekday ?? getIsoWeekday(ymd);
}

export function effectiveLessonCountOnDay(
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

export function findActiveRecordForLesson(
  state: TemporaryTimetableState,
  lesson: ActualLesson
): TemporaryAdjustmentRecord | null {
  for (let i = state.records.length - 1; i >= 0; i--) {
    const record = state.records[i];
    if (record.cancelledAt != null || record.needsAttention) continue;
    if (record.changes.some((c) => c.after.key === lesson.key)) {
      return record;
    }
  }
  return null;
}

export function findActiveRecordForSupervision(
  state: TemporaryTimetableState,
  supervision: ActualSupervision
): TemporaryAdjustmentRecord | null {
  for (let i = state.records.length - 1; i >= 0; i--) {
    const record = state.records[i];
    if (record.cancelledAt != null || record.needsAttention) continue;
    if (record.supervisionChange?.after.key === supervision.key) {
      return record;
    }
  }
  return null;
}

export function adjustmentKindLabel(kind: string): string {
  switch (kind) {
    case 'swap':
      return '换课';
    case 'move':
      return '移课';
    case 'substitute':
      return '代课';
    case SUPERVISION_SUBSTITUTION_KIND:
      return '带班替班';
    default:
      return kind;
  }
}

export function recordClassIds(record: TemporaryAdjustmentRecord): string[] {
  if (record.supervisionChange) {
    return Array.from(
      new Set([
        ...record.supervisionChange.before.classIds,
        ...record.supervisionChange.after.classIds,
      ])
    );
  }
  return Array.from(
    new Set(
      record.changes.flatMap((c) => [
        c.before.item.classId,
        c.after.item.classId,
      ])
    )
  );
}

export function recordTeacherIds(record: TemporaryAdjustmentRecord): string[] {
  if (record.supervisionChange) {
    return Array.from(
      new Set([
        record.supervisionChange.before.teacherId,
        record.supervisionChange.after.teacherId,
      ])
    );
  }
  return Array.from(
    new Set(
      record.changes.flatMap((c) => [
        c.before.item.teacherId,
        c.after.item.teacherId,
      ])
    )
  );
}

export function recordDates(record: TemporaryAdjustmentRecord): string[] {
  if (record.supervisionChange) {
    return [record.supervisionChange.before.date];
  }
  return Array.from(
    new Set(record.changes.flatMap((c) => [c.before.date, c.after.date]))
  ).sort();
}

export function describeLessonChange(
  state: TemporaryTimetableState,
  change: ActualLessonChange,
  kind: string
): string {
  const beforeSubject = getSubjectDisplayName(
    change.before.item.subjectId,
    state.snapshot.subjects
  );
  const afterSubject = getSubjectDisplayName(
    change.after.item.subjectId,
    state.snapshot.subjects
  );
  const beforeTeacher = getTeacherNameById(
    change.before.item.teacherId,
    state.snapshot.teachers
  );
  const afterTeacher = getTeacherNameById(
    change.after.item.teacherId,
    state.snapshot.teachers
  );
  const beforeSlot = `${formatChineseMdWeekday(change.before.date)} ${getPeriodLessonLabel(
    state,
    change.before.item.position
  )}`;
  const afterSlot = `${formatChineseMdWeekday(change.after.date)} ${getPeriodLessonLabel(
    state,
    change.after.item.position
  )}`;

  if (kind === 'substitute') {
    const subPart =
      beforeSubject !== afterSubject
        ? `（改上${afterSubject}）`
        : '';
    return `${beforeSlot} · ${beforeSubject}：${beforeTeacher} → ${afterTeacher}${subPart}`;
  }
  return `${beforeSubject}（${beforeTeacher}）：${beforeSlot} → ${afterSlot}`;
}

export function describeRecordSummary(
  state: TemporaryTimetableState,
  record: TemporaryAdjustmentRecord
): string {
  if (record.supervisionChange) {
    const sc = record.supervisionChange;
    return `${formatChineseMdWeekday(sc.before.date)} · ${sc.before.post.name}：${
      sc.before.teacherName
    } → ${sc.after.teacherName}`;
  }
  if (record.changes.length === 0) return '无变更明细';
  if (record.kind === 'swap' && record.changes.length >= 2) {
    const first = record.changes[0];
    const second = record.changes[1];
    const s1 = getSubjectDisplayName(
      first.before.item.subjectId,
      state.snapshot.subjects
    );
    const s2 = getSubjectDisplayName(
      second.before.item.subjectId,
      state.snapshot.subjects
    );
    const slot1 = `${formatShortMd(first.before.date)} ${getPeriodLessonLabel(
      state,
      first.before.item.position
    )}`;
    const slot2 = `${formatShortMd(second.before.date)} ${getPeriodLessonLabel(
      state,
      second.before.item.position
    )}`;
    const extra =
      record.changes.length > 2
        ? ` 等 ${Math.floor(record.changes.length / 2)} 组互换`
        : '';
    return `${slot1} ${s1} ⇄ ${slot2} ${s2}${extra}`;
  }
  const firstDesc = describeLessonChange(state, record.changes[0], record.kind);
  return record.changes.length > 1
    ? `${firstDesc}（共 ${record.changes.length} 课次）`
    : firstDesc;
}

export interface TeacherRowSlot {
  key: string;
  labelTop: string;
  labelBottom: string;
  sortKey: number;
  matches: (position: SchedulePosition) => boolean;
}

export function buildTeacherGridRows(
  state: TemporaryTimetableState,
  lessons: ActualLesson[]
): TeacherRowSlot[] {
  const stageOrder = new Map(
    state.snapshot.stages.map((s, idx) => [s.id, idx])
  );
  const stageById = new Map(state.snapshot.stages.map((s) => [s.id, s]));

  // Check if all teacher lessons in the week have clock times
  const positions: SchedulePosition[] = [];
  for (const lesson of lessons) {
    if (lesson.item.position) positions.push(lesson.item.position);
  }
  if (positions.length === 0) {
    // Fallback to first stage routine if teacher has no lessons this week
    const firstRoutine = state.snapshot.routines[0];
    if (!firstRoutine) return [];
    const rows: TeacherRowSlot[] = [];
    const periods = [...firstRoutine.periodTypes].sort(
      (a, b) => a.sortOrder - b.sortOrder
    );
    for (const period of periods) {
      for (let i = 1; i <= period.defaultLessonCount; i++) {
        const lt = firstRoutine.lessonTimes.find(
          (t) => t.periodTypeId === period.id && t.lessonIndex === i
        );
        const startClock = formatMinuteClock(lt?.startMinute);
        rows.push({
          key: `${firstRoutine.stageId}:${period.id}:${i}`,
          labelTop: `${period.name}第 ${i} 节`,
          labelBottom: startClock ?? '',
          sortKey: period.sortOrder * 100 + i,
          matches: (pos) =>
            pos.stageId === firstRoutine.stageId &&
            pos.periodTypeId === period.id &&
            pos.lessonIndex === i,
        });
      }
    }
    return rows;
  }

  const allHaveClock =
    state.snapshot.stages.length > 1 &&
    positions.every((p) => hasClockTime(p));

  const map = new Map<string, TeacherRowSlot>();
  for (const pos of positions) {
    const routine = state.snapshot.routines.find(
      (r) => r.stageId === pos.stageId
    );
    const period = routine?.periodTypes.find(
      (p) => p.id === pos.periodTypeId
    );
    const lt = routine?.lessonTimes.find(
      (t) =>
        t.periodTypeId === pos.periodTypeId && t.lessonIndex === pos.lessonIndex
    );
    const startMinute = pos.startMinute ?? lt?.startMinute ?? null;
    const endMinute = pos.endMinute ?? lt?.endMinute ?? null;

    if (allHaveClock && startMinute != null && endMinute != null) {
      const key = `clock:${startMinute}:${endMinute}`;
      if (!map.has(key)) {
        map.set(key, {
          key,
          labelTop: formatMinuteClock(startMinute) ?? '',
          labelBottom: formatMinuteClock(endMinute) ?? '',
          sortKey: startMinute * 10000 + endMinute,
          matches: (p) =>
            p.startMinute === startMinute && p.endMinute === endMinute,
        });
      }
    } else {
      const key = `cell:${pos.stageId}:${pos.periodTypeId}:${pos.lessonIndex}`;
      if (!map.has(key)) {
        const stIdx = stageOrder.get(pos.stageId) ?? 0;
        const pOrder = period?.sortOrder ?? 0;
        const stagePrefix =
          state.snapshot.stages.length > 1
            ? `${stageById.get(pos.stageId)?.name ?? ''} `
            : '';
        map.set(key, {
          key,
          labelTop: `${stagePrefix}${period?.name ?? ''}`,
          labelBottom: `第 ${pos.lessonIndex} 节`,
          sortKey:
            startMinute != null
              ? startMinute
              : stIdx * 10000 + pOrder * 100 + pos.lessonIndex,
          matches: (p) =>
            p.stageId === pos.stageId &&
            p.periodTypeId === pos.periodTypeId &&
            p.lessonIndex === pos.lessonIndex,
        });
      }
    }
  }
  return Array.from(map.values()).sort((a, b) => a.sortKey - b.sortKey);
}

export function buildWeekMoveCandidates(
  state: TemporaryTimetableState,
  problem: SchedulingProblem,
  source: ActualLesson,
  routine: StageRoutine | undefined,
  visibleDates: string[]
): Map<string, CandidateMoveSlot> {
  const result = new Map<string, CandidateMoveSlot>();
  if (!routine) return result;
  const classId = source.item.classId;
  const periods = [...routine.periodTypes].sort(
    (a, b) => a.sortOrder - b.sortOrder
  );

  for (const date of visibleDates) {
    const scheduleWeekday = getScheduleWeekdayForDate(state.exceptions, date);
    if (scheduleWeekday == null) continue;
    const isTeaching = routine.teachingDays.some(
      (d) => d.weekday === scheduleWeekday && d.isTeachingDay
    );
    if (!isTeaching) continue;

    for (const period of periods) {
      const count = effectiveLessonCountOnDay(
        routine,
        period.id,
        scheduleWeekday
      );
      for (let lessonIdx = 1; lessonIdx <= count; lessonIdx++) {
        const occupied = state.lessons.some(
          (l) =>
            l.item.classId === classId &&
            l.date === date &&
            l.item.position?.periodTypeId === period.id &&
            l.item.position?.lessonIndex === lessonIdx
        );
        if (occupied) continue;

        const lt = routine.lessonTimes.find(
          (t) =>
            t.periodTypeId === period.id && t.lessonIndex === lessonIdx
        );
        const targetPosition: SchedulePosition = {
          stageId: routine.stageId,
          weekday: scheduleWeekday,
          periodTypeId: period.id,
          lessonIndex: lessonIdx,
          startMinute: lt?.startMinute ?? null,
          endMinute: lt?.endMinute ?? null,
        };
        const slotKey = `${date}:${period.id}:${lessonIdx}`;
        const preview = state.previewMove(
          {
            sourceKey: source.key,
            targetDate: date,
            targetPosition,
          },
          problem
        );
        result.set(slotKey, {
          date,
          position: targetPosition,
          preview,
        });
      }
    }
  }
  return result;
}

export function buildWeekSwapCandidates(
  state: TemporaryTimetableState,
  problem: SchedulingProblem,
  source: ActualLesson,
  visibleDates: string[]
): Map<string, ActualChangePreview> {
  const result = new Map<string, ActualChangePreview>();
  const dateSet = new Set(visibleDates);
  for (const lesson of state.lessons) {
    if (
      lesson.item.classId !== source.item.classId ||
      !dateSet.has(lesson.date) ||
      lesson.key === source.key
    ) {
      continue;
    }
    const preview = state.previewSwap(
      {
        firstKey: source.key,
        secondKey: lesson.key,
      },
      problem
    );
    result.set(lesson.key, preview);
  }
  return result;
}

export function sameMoveSlot(
  aDate: string | null,
  aPos: SchedulePosition | null,
  bDate: string,
  bPos: SchedulePosition
): boolean {
  if (!aDate || !aPos) return false;
  return aDate === bDate && sameCell(aPos, bPos);
}
