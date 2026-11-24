import type { AcademicTerm, CommonPeriod, ScheduleItem } from '../domain/models';
import type { DutyOccurrence, ScheduleData, ScheduleSlot } from '../domain/scheduling';
import { createScheduleContext, defaultSchedulePreferences, positionOf } from '../domain/scheduling';

export function scheduleRevision(data: ScheduleData): string {
  return JSON.stringify(data, (_key, value: unknown) => {
    if (Array.isArray(value)) return [...value].sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)));
    return value;
  });
}

export function scheduleReconciliationRevision(data: ScheduleData): string {
  const preferences = {
    ...defaultSchedulePreferences(data.term.id),
    lunchProtection: data.preferences.lunchProtection,
    consecutivePolicy: data.preferences.consecutivePolicy === 'requireSeparate' ? 'requireSeparate' : 'preferSeparate',
    progressConsistency: data.preferences.detectProgressConsistency && data.preferences.progressConsistency === 'require' ? 'require' : 'prefer',
  };
  return scheduleRevision({ ...data, locks: [], preferences });
}

interface StoredRoutine {
  stageId: string;
  teachingWeekdays: number[];
  periodTypes: Array<Omit<ScheduleData['routines'][number]['periodTypes'][number], 'stageId'> & {
    lessonTimes: Array<Omit<ScheduleData['routines'][number]['lessonTimes'][number], 'id' | 'periodTypeId'> & { id?: string }>;
  }>;
  overrides: Array<Omit<ScheduleData['routines'][number]['dailyOverrides'][number], 'id' | 'stageId'>>;
}

type StoredItem = Omit<ScheduleItem, keyof Pick<ScheduleSlot, 'stageId' | 'weekday' | 'periodTypeId' | 'lessonIndex'>> & {
  position: DutyOccurrence['position'] | null;
};

type Scoped<T> = Omit<T, 'scopeType'> & { scope: T extends { scopeType: infer S } ? S : never };
interface StoredSchedule extends Pick<ScheduleData, 'stages' | 'grades' | 'classes' | 'subjects' | 'teachers' |
  'assignments' | 'requirements' | 'teacherGroupMembers' | 'pairings' | 'rooms' | 'supervision' | 'visibleSupervision'> {
  term: Omit<AcademicTerm, 'createdAt'> & { createdAt: string };
  inputFingerprint: string;
  routines: StoredRoutine[];
  existingItems: StoredItem[];
  freeSlots?: Scoped<ScheduleData['freeSlots'][number]>[];
  subjectPresets?: Scoped<ScheduleData['subjectPresets'][number]>[];
  teacherPresets?: Scoped<ScheduleData['teacherPresets'][number]>[];
  teacherGroupPresets?: Scoped<ScheduleData['teacherGroupPresets'][number]>[];
  lessonConstraints?: Scoped<ScheduleData['lessonConstraints'][number]>[];
  roomAssignments?: Scoped<ScheduleData['roomAssignments'][number]>[];
  parallelLimits?: Scoped<ScheduleData['parallelLimits'][number]>[];
  conditions?: Array<{ id: string; termId: string; type: string; targetType: string | null; targetId: string | null;
    otherTargetId: string | null; periodTypeId: string | null; weekday: number | null; minimum: number | null;
    maximum: number | null; exact: number | null; name: string | null }>;
  preferences: { strength: string; progressConsistency: string; teacherDistribution: string; protectLunchBreak: boolean; consecutiveMode: string; checkProgressConsistency: boolean };
  locks: Array<{ termId: string; scope: 'schoolClass' | 'teacher'; targetId: string }>;
}

function encodeScope<T extends { scopeType: string }>({ scopeType, ...row }: T) {
  return { ...row, scope: scopeType };
}

function decodeScope<T extends { scope: string }>({ scope, ...row }: T) {
  return { ...row, scopeType: scope as 'school' | 'stage' | 'grade' | 'class' };
}

function plainPosition(context: ReturnType<typeof createScheduleContext>, item: ScheduleItem): StoredItem['position'] {
  const slot = positionOf(context, item);
  if (!slot) return null;
  return { stageId: slot.stageId, weekday: slot.weekday, periodTypeId: slot.periodTypeId, lessonIndex: slot.lessonIndex,
    startMinute: slot.startMinute, endMinute: slot.endMinute };
}

export function encodeScheduleSnapshot(data: ScheduleData, fingerprint = scheduleRevision(data)) {
  const context = createScheduleContext(data);
  return {
    term: { ...data.term, createdAt: new Date(data.term.createdAt).toISOString() },
    inputFingerprint: fingerprint,
    stages: data.stages, grades: data.grades, classes: data.classes,
    routines: data.routines.map((routine) => ({
      stageId: routine.stageId,
      teachingWeekdays: routine.teachingDays.filter((row) => row.isTeachingDay).map((row) => row.weekday),
      periodTypes: routine.periodTypes.map((period) => ({ ...period, lessonTimes: routine.lessonTimes.filter((row) => row.periodTypeId === period.id) })),
      overrides: routine.dailyOverrides,
    })),
    subjects: data.subjects, teachers: data.teachers.map((teacher) => ({ ...teacher, subjectIds: teacher.subjectIds ?? [] })),
    assignments: data.assignments.filter((row) => row.teacherId), requirements: data.requirements,
    existingItems: data.items.filter((row) => row.teacherId).map((row) => ({ ...row, position: plainPosition(context, row) })),
    locks: data.locks.map((row) => ({ ...row, scope: row.scope === 'class' ? 'schoolClass' : 'teacher' })),
    freeSlots: data.freeSlots.map(encodeScope), subjectPresets: data.subjectPresets.map(encodeScope),
    teacherPresets: data.teacherPresets.map(encodeScope), teacherGroupPresets: data.teacherGroupPresets.map(encodeScope),
    teacherGroupMembers: data.teacherGroupMembers.map((row) => ({ ...row, id: `${row.groupId}:${row.teacherId}` })),
    pairings: data.pairings, lessonConstraints: data.lessonConstraints.map(encodeScope),
    rooms: data.rooms, roomAssignments: data.roomAssignments.map(encodeScope), parallelLimits: data.parallelLimits.map(encodeScope),
    conditions: data.conditions.map((row) => ({ id: row.id, termId: row.termId, name: row.name, type: row.kind,
      targetType: row.targetKind, targetId: row.targetId, otherTargetId: row.otherId, periodTypeId: row.periodTypeId,
      weekday: row.weekday, minimum: row.minCount, maximum: row.maxCount, exact: row.exactCount })),
    preferences: { strength: data.preferences.strength, progressConsistency: data.preferences.progressConsistency,
      teacherDistribution: data.preferences.teacherDistribution, protectLunchBreak: data.preferences.lunchProtection,
      consecutiveMode: data.preferences.consecutivePolicy, checkProgressConsistency: data.preferences.detectProgressConsistency },
    supervision: data.supervision, visibleSupervision: data.visibleSupervision,
    allowedPeriodTypeIdsBySubject: {}, requiredConsecutivePairsByRequirement: {},
  };
}

export function decodeScheduleSnapshot(snapshot: StoredSchedule, commonPeriods: Record<string, CommonPeriod[]> = {}): ScheduleData {
  return {
    term: { ...snapshot.term, createdAt: Date.parse(snapshot.term.createdAt) },
    stages: snapshot.stages, grades: snapshot.grades, classes: snapshot.classes,
    subjects: snapshot.subjects, teachers: snapshot.teachers, assignments: snapshot.assignments ?? [],
    requirements: snapshot.requirements ?? [], pairings: snapshot.pairings ?? [], rooms: snapshot.rooms ?? [],
    supervision: snapshot.supervision ?? [], visibleSupervision: snapshot.visibleSupervision ?? snapshot.supervision ?? [],
    freeSlots: (snapshot.freeSlots ?? []).map(decodeScope), subjectPresets: (snapshot.subjectPresets ?? []).map(decodeScope),
    teacherPresets: (snapshot.teacherPresets ?? []).map(decodeScope), teacherGroupPresets: (snapshot.teacherGroupPresets ?? []).map(decodeScope),
    lessonConstraints: (snapshot.lessonConstraints ?? []).map(decodeScope), roomAssignments: (snapshot.roomAssignments ?? []).map(decodeScope),
    parallelLimits: (snapshot.parallelLimits ?? []).map(decodeScope), teacherGroupMembers: snapshot.teacherGroupMembers ?? [],
    locks: (snapshot.locks ?? []).map((row) => ({ ...row, scope: row.scope === 'teacher' ? 'teacher' : 'class', id: `${row.termId}:${row.scope === 'teacher' ? 'teacher' : 'class'}:${row.targetId}` })),
    conditions: (snapshot.conditions ?? []).map((row) => ({ id: row.id, termId: row.termId, name: row.name, kind: row.type,
      targetKind: row.targetType, targetId: row.targetId, otherId: row.otherTargetId, periodTypeId: row.periodTypeId,
      weekday: row.weekday, minCount: row.minimum, maxCount: row.maximum, exactCount: row.exact })),
    preferences: snapshot.preferences ? { termId: snapshot.term.id, strength: snapshot.preferences.strength,
      progressConsistency: snapshot.preferences.progressConsistency, teacherDistribution: snapshot.preferences.teacherDistribution,
      lunchProtection: snapshot.preferences.protectLunchBreak, consecutivePolicy: snapshot.preferences.consecutiveMode,
      detectProgressConsistency: snapshot.preferences.checkProgressConsistency } : defaultSchedulePreferences(snapshot.term.id),
    items: snapshot.existingItems.map(({ position, ...item }) => ({ ...item, stageId: position?.stageId ?? null,
      weekday: position?.weekday ?? null, periodTypeId: position?.periodTypeId ?? null, lessonIndex: position?.lessonIndex ?? null })),
    routines: snapshot.routines.map((routine) => ({
      stageId: routine.stageId,
      teachingDays: routine.teachingWeekdays.map((weekday) => ({ id: `${routine.stageId}:${weekday}`, stageId: routine.stageId, weekday, isTeachingDay: true })),
      periodTypes: routine.periodTypes.map(({ lessonTimes: _, ...row }) => ({ ...row, stageId: routine.stageId })),
      dailyOverrides: routine.overrides.map((row) => ({ ...row, id: `${row.periodTypeId}:${row.weekday}`, stageId: routine.stageId })),
      lessonTimes: routine.periodTypes.flatMap((period) => period.lessonTimes.map((row) => ({ ...row, periodTypeId: period.id, id: row.id ?? `${period.id}:${row.lessonIndex}` }))),
      commonPeriods: commonPeriods[routine.stageId],
    })),
  };
}

export function readStoredSchedule(payload: string): ScheduleData {
  const decoded = JSON.parse(payload) as { snapshot?: StoredSchedule; commonPeriods?: Record<string, CommonPeriod[]>; workbench?: ScheduleData } & StoredSchedule;
  return decoded.workbench ?? decodeScheduleSnapshot(decoded.snapshot ?? decoded, decoded.commonPeriods);
}

export function writeStoredSchedule(data: ScheduleData, published: boolean) {
  const snapshot = encodeScheduleSnapshot(data, 'classset-workbench-v1');
  const commonPeriods = Object.fromEntries(data.routines.map((row) => [row.stageId, row.commonPeriods ?? []]));
  return JSON.stringify(published ? { snapshot, commonPeriods, workbench: data } : { ...snapshot, workbench: data });
}

export interface ScheduleRunReport {
  classIds: string[];
  seed: number;
  strength: string;
  candidateChecks: number;
  blockers: Record<string, string[]>;
  issues: string[];
}

export function createStoredRun(data: ScheduleData, items: ScheduleItem[], report: ScheduleRunReport) {
  const message = (value: string) => ({ code: 'constraint', message: value });
  const placed = items.filter((row) => row.weekday !== null);
  return {
    id: crypto.randomUUID(), termId: data.term.id, inputFingerprint: 'classset-workbench-v1',
    config: { selectedClassIds: report.classIds, seed: report.seed, strength: report.strength, solverVersion: 'classset-workbench-v3' },
    items: encodeScheduleSnapshot({ ...data, items }, 'classset-workbench-v1').existingItems,
    report: { totalItems: items.length, placedItems: placed.length, coverage: placed.reduce((sum, row) => sum + (row.weekMode === 'weekly' ? 2 : 1), 0),
      candidateChecks: report.candidateChecks, preferenceScores: {}, unmetHardRequirements: report.issues.map(message),
      unplaced: items.filter((row) => row.weekday === null).map((row) => ({ itemId: row.id, blockers: (report.blockers[row.id] ?? []).map(message) })) },
  };
}

export function readStoredRun(payload: string): ScheduleRunReport {
  const run = JSON.parse(payload) as ReturnType<typeof createStoredRun>;
  return {
    classIds: run.config.selectedClassIds, seed: run.config.seed, strength: run.config.strength,
    candidateChecks: run.report.candidateChecks, issues: run.report.unmetHardRequirements.map((row) => row.message),
    blockers: Object.fromEntries(run.report.unplaced.map((row) => [row.itemId, row.blockers.map((blocker) => blocker.message)])),
  };
}
