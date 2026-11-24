/**
 * 课集 (ClassSet) 领域模型定义 (Schema v19 全量 29 张表模型)
 * 严格对齐 lib/domain/models/ 与 docs/data-schema.md
 */

export type CycleMode = 'every_week' | 'alternating';
export type WeekMode = 'weekly' | 'odd' | 'even';
export type ScopeType = 'school' | 'stage' | 'grade' | 'class';
export type PresetValue = 'auto' | 'prefer' | 'must' | 'forbid';

export type AppSection =
  | 'workbench'
  | 'terms'
  | 'classes'
  | 'routines'
  | 'publicRooms'
  | 'subjects'
  | 'teachers'
  | 'scheduling'
  | 'supervision'
  | 'temporaryAdjustments';

export interface AcademicTerm {
  id: string;
  title: string;
  academicYear: string;
  semesterLabel: string;
  firstTeachingWeekStart: string | null;
  teachingWeekCount: number;
  cycleMode: CycleMode;
  createdAt: number;
}

export interface SchoolStage {
  id: string;
  termId: string;
  name: string;
  sortOrder: number;
}

export interface GradeGroup {
  id: string;
  stageId: string;
  name: string;
  sortOrder: number;
}

export interface ClassGroup {
  id: string;
  gradeId: string;
  name: string;
  sortOrder: number;
}

export interface StageTeachingDay {
  id: string;
  stageId: string;
  weekday: number;
  isTeachingDay: boolean;
}

export interface LessonPeriodType {
  id: string;
  stageId: string;
  name: string;
  defaultLessonCount: number;
  sortOrder: number;
}

export interface DailyLessonOverride {
  id: string;
  stageId: string;
  periodTypeId: string;
  weekday: number;
  lessonCount: number;
}

export interface LessonTime {
  id: string;
  periodTypeId: string;
  lessonIndex: number;
  label: string;
  startMinute: number | null;
  endMinute: number | null;
}

export interface StageRoutine {
  stageId: string;
  teachingDays: StageTeachingDay[];
  periodTypes: LessonPeriodType[];
  dailyOverrides: DailyLessonOverride[];
  lessonTimes: LessonTime[];
  commonPeriods?: CommonPeriod[];
}

export interface FreeSlot {
  id: string;
  scopeType: ScopeType;
  scopeId: string;
  stageId: string;
  periodTypeId: string;
  weekday: number;
  lessonIndex: number;
  label: string;
}

export interface CommonPeriod {
  id: string;
  stageId: string;
  name: string;
  insertAfterLessonId: string | null;
  durationMinutes: number;
  sortOrder: number;
  startMinute: number | null;
  endMinute: number | null;
}

export interface CalendarException {
  id: string;
  termId: string;
  date: string;
  kind: 'holiday' | 'makeup';
  makeupWeekday: number | null;
  makeupForDate: string | null;
  note: string;
}

export interface Subject {
  id: string;
  termId: string | null;
  name: string;
  shortName: string;
  sortOrder: number;
}

export interface SubjectRequirement {
  id: string;
  subjectId: string;
  gradeId: string;
  classId: string | null;
  weekMode: WeekMode;
  lessonCount: number;
}

export interface SubjectPreset {
  id: string;
  subjectId: string;
  scopeType: ScopeType;
  scopeId: string;
  stageId: string;
  weekday: number;
  periodTypeId: string;
  lessonIndex: number;
  value: PresetValue;
}

export interface SubjectPairing {
  id: string;
  classId: string;
  oddSubjectId: string;
  evenSubjectId: string;
}

export interface SubjectLessonConstraint {
  id: string;
  subjectId: string;
  scopeType: ScopeType;
  scopeId: string;
  stageId: string;
  weekday: number | null;
  minimumDailyLessons: number | null;
  maximumDailyLessons: number | null;
  minimumDailyConsecutivePairs: number | null;
  maximumDailyConsecutivePairs: number | null;
  minimumWeeklyConsecutivePairs: number | null;
  maximumWeeklyConsecutivePairs: number | null;
}

export interface PublicRoom {
  id: string;
  name: string;
  roomCount: number;
  capacityPerRoom: number;
  sortOrder: number;
}

export interface SubjectRoomAssignment {
  id: string;
  subjectId: string;
  termId: string;
  stageId: string;
  scopeType: ScopeType;
  scopeId: string;
  roomId: string | null;
}

export interface SubjectParallelLimit {
  id: string;
  subjectId: string;
  termId: string;
  stageId: string;
  scopeType: ScopeType;
  scopeId: string;
  maxParallelLessons: number;
}

export interface Teacher {
  id: string;
  name: string;
  shortName: string;
  displayQualifier: string;
  sortOrder: number;
  subjectIds?: string[];
}

export interface TeacherGroup {
  id: string;
  termId: string;
  name: string;
  description: string;
  sortOrder: number;
}

export interface TeacherGroupMember {
  groupId: string;
  teacherId: string;
}

export interface TeacherAssignment {
  id: string;
  termId: string;
  teacherId: string | null;
  subjectId: string;
  classId: string;
  weekMode: WeekMode;
  lessonCount: number;
  sortOrder: number;
  combinedLessonGroupId: string | null;
}

export interface TeacherPreset {
  id: string;
  termId: string;
  teacherId: string;
  scopeType: ScopeType;
  scopeId: string;
  stageId: string;
  weekday: number;
  periodTypeId: string;
  lessonIndex: number;
  weekMode: WeekMode;
  value: PresetValue;
}

export interface TeacherGroupPreset {
  id: string;
  groupId: string;
  scopeType: ScopeType;
  scopeId: string;
  stageId: string;
  weekday: number;
  periodTypeId: string;
  lessonIndex: number;
  weekMode: WeekMode;
  value: PresetValue;
}

export interface ScheduleItem {
  id: string;
  termId: string;
  assignmentId: string;
  classId: string;
  teacherId: string | null;
  subjectId: string;
  weekMode: WeekMode;
  combinedGroupId: string | null;
  meetingId: string | null;
  stageId: string | null;
  weekday: number | null;
  periodTypeId: string | null;
  lessonIndex: number | null;
}

export interface ScheduleLock {
  id: string;
  termId: string;
  scope: 'class' | 'teacher';
  targetId: string;
}

export interface ScheduleCondition {
  id: string;
  termId: string;
  kind: string;
  name: string | null;
  targetKind: string | null;
  targetId: string | null;
  otherId: string | null;
  periodTypeId: string | null;
  weekday: number | null;
  minCount: number | null;
  maxCount: number | null;
  exactCount: number | null;
}

export interface SchedulePreferences {
  termId: string;
  strength: string;
  progressConsistency: string;
  teacherDistribution: string;
  lunchProtection: boolean;
  consecutivePolicy: string;
  detectProgressConsistency: boolean;
}

export interface SupervisionDraft {
  termId: string;
  payload: string;
}

export interface SupervisionPlanVersion {
  termId: string;
  effectiveDate: string;
  payload: string;
}

export interface TemporaryCourseAdjustment {
  id: string;
  termId: string;
  kind: string;
  changesJson: string;
  reason: string;
  createdAt: number;
  cancelledAt: number | null;
}

/**
 * 工作台与步骤级联门控进度摘要（对齐 app.dart navSectionAvailability）
 */
export interface WorkbenchSummary {
  termId: string;
  stageCount: number;
  gradeCount: number;
  classCount: number;
  subjectCount: number;
  teacherCount: number;
  publicRoomCount: number;
  stagesDone: boolean;
  routineDone: boolean;
  subjectLessonsReady: boolean;
  teacherAssignmentsReady: boolean;
  hasSchedule: boolean;
  hasSavedTimetable?: boolean;
}

/**
 * 侧栏菜单步骤级联门控规则（严格遵循「步骤级联限制」规范）
 */
export function getNavSectionAvailability(
  section: AppSection,
  hasTerm: boolean,
  summary: WorkbenchSummary | null
): { enabled: boolean; reason: string | null } {
  if (!hasTerm) {
    if (section === 'workbench' || section === 'terms' || section === 'publicRooms') {
      return { enabled: true, reason: null };
    }
    return { enabled: false, reason: '请先创建学期' };
  }

  if (!summary) {
    return { enabled: true, reason: null };
  }

  const routineGate = () => {
    if (summary.routineDone) return { enabled: true, reason: null };
    return summary.stagesDone
      ? { enabled: false, reason: '请先完成各学段作息设置' }
      : { enabled: false, reason: '请先创建学段、年级与班级' };
  };

  switch (section) {
    case 'workbench':
    case 'terms':
    case 'publicRooms':
    case 'classes':
    case 'routines':
      return { enabled: true, reason: null };
    case 'subjects':
    case 'supervision':
      return routineGate();
    case 'teachers':
      return summary.subjectLessonsReady
        ? { enabled: true, reason: null }
        : { enabled: false, reason: '请先填写各年级科目节数' };
    case 'scheduling':
      return summary.teacherAssignmentsReady || summary.hasSchedule || summary.hasSavedTimetable
        ? { enabled: true, reason: null }
        : { enabled: false, reason: '请先补齐各班教师任课' };
    case 'temporaryAdjustments':
      return summary.hasSchedule
        ? { enabled: true, reason: null }
        : { enabled: false, reason: '请先在排课与课表中生成课表' };
  }
}
