export interface SchedulePosition {
  stageId: string;
  weekday: number;
  periodTypeId: string;
  lessonIndex: number;
  startMinute?: number | null;
  endMinute?: number | null;
}

export function sameCell(a: SchedulePosition, b: SchedulePosition): boolean {
  return (
    a.stageId === b.stageId &&
    a.weekday === b.weekday &&
    a.periodTypeId === b.periodTypeId &&
    a.lessonIndex === b.lessonIndex
  );
}

export function hasClockTime(p: SchedulePosition): boolean {
  return p.startMinute != null && p.endMinute != null;
}

export function overlaps(a: SchedulePosition, b: SchedulePosition): boolean {
  if (a.weekday !== b.weekday) return false;
  if (
    a.stageId === b.stageId &&
    a.periodTypeId === b.periodTypeId &&
    a.lessonIndex === b.lessonIndex
  ) {
    return true;
  }
  if (hasClockTime(a) && hasClockTime(b)) {
    return Math.max(a.startMinute!, b.startMinute!) < Math.min(a.endMinute!, b.endMinute!);
  }
  return false;
}

export type SupervisionKind = 'afterSchool' | 'morningStudy' | 'eveningStudy' | 'custom';

export const SUPERVISION_KIND_LABELS: Record<SupervisionKind, string> = {
  afterSchool: '课后服务',
  morningStudy: '早自习',
  eveningStudy: '晚自习',
  custom: '自定义',
};

export type SupervisionPreference = 'classTeacher' | 'gradeTeacher' | 'subjectTeacher';

export const SUPERVISION_PREFERENCE_LABELS: Record<SupervisionPreference, string> = {
  classTeacher: '任教班级优先',
  gradeTeacher: '本年级优先',
  subjectTeacher: '指定学科优先',
};

export type SupervisionMatchMode = 'matchFirst' | 'balanceFirst';
export type SupervisionMatchRequirement = 'none' | 'any' | 'all';

export interface SupervisionMatchingPreferences {
  order: SupervisionPreference[];
  enabled: SupervisionPreference[];
  mode: SupervisionMatchMode;
  requirement: SupervisionMatchRequirement;
}

export const defaultSupervisionMatchingPreferences: SupervisionMatchingPreferences = {
  order: ['classTeacher', 'gradeTeacher', 'subjectTeacher'],
  enabled: ['classTeacher', 'gradeTeacher'],
  mode: 'matchFirst',
  requirement: 'none',
};

export interface SupervisionTeacherPool {
  id: string;
  name: string;
  teacherIds: string[];
}

export const SUPERVISION_BASE_POOL_ID = '__default__';

export interface SupervisionPost {
  id: string;
  kind: SupervisionKind;
  name: string;
  groupName: string;
  location: string;
  stageId: string;
  weekday: number;
  periodTypeId: string;
  lessonIndices: number[];
  classIds: string[];
  teacherPoolId?: string | null;
  matchingPreferences?: SupervisionMatchingPreferences | null;
  targetSubjectIds?: string[];
}

export interface SupervisionTeacherRule {
  maxLessons?: number | null;
  maxDays?: number | null;
  unavailable?: SchedulePosition[];
}

export interface SupervisionDraft {
  termId: string;
  revision: number;
  posts: SupervisionPost[];
  teacherIds: string[];
  teacherPools: SupervisionTeacherPool[];
  defaultTeacherPoolId?: string | null;
  matchingPreferences: SupervisionMatchingPreferences;
  rules: Record<string, SupervisionTeacherRule>;
  assignments: Record<string, string>;
  manualPostIds: string[];
}

export interface SupervisionOccurrence {
  post: SupervisionPost;
  teacherId: string;
  teacherName: string;
  classNames: string[];
  position: SchedulePosition;
  startMinute?: number | null;
  endMinute?: number | null;
}

export interface SupervisionVersion {
  termId: string;
  effectiveDate: string; // YYYY-MM-DD
  draft: SupervisionDraft;
  occurrences: SupervisionOccurrence[];
}

export interface SupervisionPreview {
  effectiveDate: string;
  before?: SupervisionVersion | null;
  draft: SupervisionDraft;
  errors: string[];
  missingPostIds: string[];
  scheduleChanges: string[];
  replacedFutureDate?: string | null;
  fingerprint: string;
  canPublish: boolean;
}

export interface SupervisionSeed {
  stageId: string;
  scope: string;
  scopeId: string;
  weekday: number;
  periodTypeId: string;
  lessonIndex: number;
}

export function poolIdForPost(draft: SupervisionDraft, post: SupervisionPost): string {
  return post.teacherPoolId ?? draft.defaultTeacherPoolId ?? SUPERVISION_BASE_POOL_ID;
}

export function teachersForPost(draft: SupervisionDraft, post: SupervisionPost): Set<string> {
  const poolId = poolIdForPost(draft, post);
  if (poolId === SUPERVISION_BASE_POOL_ID) {
    return new Set(draft.teacherIds);
  }
  const pool = draft.teacherPools.find((p) => p.id === poolId);
  return new Set(pool?.teacherIds ?? []);
}

export function poolNameForPost(draft: SupervisionDraft, post: SupervisionPost): string {
  const poolId = poolIdForPost(draft, post);
  if (poolId === SUPERVISION_BASE_POOL_ID) return '基础候选池';
  const pool = draft.teacherPools.find((p) => p.id === poolId);
  return pool?.name ?? '候选池已失效';
}

export function allTeacherIdsInDraft(draft: SupervisionDraft): Set<string> {
  const set = new Set<string>(draft.teacherIds);
  for (const pool of draft.teacherPools) {
    for (const t of pool.teacherIds) {
      set.add(t);
    }
  }
  return set;
}

export function preferencesForPost(
  draft: SupervisionDraft,
  post: SupervisionPost
): SupervisionMatchingPreferences {
  return post.matchingPreferences ?? draft.matchingPreferences;
}
