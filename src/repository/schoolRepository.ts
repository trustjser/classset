/**
 * 课集 (ClassSet) SchoolRepository 完整实现 (阶段 2 交付：Schema v19 双端同构仓储层)
 * 严格对齐原 lib/data/repositories/school_repository.dart 与 drift_school_repository.dart
 * - 当 SQLite 引擎就绪（Tauri Native SQLite 或 Web SQLite Wasm + IndexedDB）时，双端 100% 走同一套 SQL 事务与外键级联；
 * - 当 Web 端处于无 Wasm CDN 的受限离线环境时，自动无缝回退到内存 + LocalStorage 存储；
 * - 支持一键导入 / 导出标准 school.sqlite 二进制文件，与原 Flutter 端及 Tauri 桌面端 100% 互通。
 */

import {
  DbTransactionClient,
  getDatabaseAdapter,
  isTauriDesktop,
  SqlDatabaseAdapter,
} from '../adapter/db/databaseAdapter';
import type {
  SupervisionDraft as SupervisionDraftModel,
  SupervisionVersion,
  SupervisionPreview,
} from '../domain/supervision';
import { defaultSupervisionMatchingPreferences } from '../domain/supervision';
import { postErrors, occurrences } from '../domain/supervisionValidation';
import { SupervisionAllocator } from '../domain/supervisionAllocator';
import { SupervisionMatching } from '../domain/supervisionMatching';
import {
  AcademicTerm,
  CalendarException,
  ClassGroup,
  CommonPeriod,
  FreeSlot,
  GradeGroup,
  LessonPeriodType,
  PublicRoom,
  ScheduleCondition,
  ScheduleItem,
  ScheduleLock,
  SchedulePreferences,
  SchoolStage,
  ScopeType,
  StageRoutine,
  Subject,
  SubjectLessonConstraint,
  SubjectPairing,
  SubjectPreset,
  SubjectRoomAssignment,
  SubjectParallelLimit,
  SubjectRequirement,
  SupervisionDraft,
  SupervisionPlanVersion,
  Teacher,
  TeacherAssignment,
  TeacherGroup,
  TeacherGroupMember,
  TeacherGroupPreset,
  TeacherPreset,
  TemporaryCourseAdjustment,
  WorkbenchSummary,
  WeekMode,
} from '../domain/models';

import { defaultSchedulePreferences, validateScheduleSupervision, type DutyOccurrence, type ScheduleData } from '../domain/scheduling';
import {
  type ActualChangePreview,
  actualLessonChangeToJson,
  actualSupervisionChangeToJson,
  parseAdjustmentRow,
  projectTemporaryTimetable,
  SUPERVISION_SUBSTITUTION_KIND,
  type TemporaryAdjustmentRecord,
  type TemporaryMoveRequest,
  type TemporarySubstituteRequest,
  type TemporarySupervisionSubstituteRequest,
  type TemporarySwapRequest,
  TemporaryTimetableState,
  validateTemporaryCancellation,
} from '../domain/actualTimetable';
import { PublicRoomTermData } from '../features/publicRooms/publicRoomsData';
import { createId } from '../domain/id';
import { formatDateYmd, getIsoWeekday, getTeachingWeekEnd, getTeachingWeekOfDate, getTeachingWeekStart, parseLocalDate } from '../features/terms/calendarUtils';
import { createStoredRun, readStoredRun, readStoredSchedule, scheduleReconciliationRevision, scheduleRevision, writeStoredSchedule, type ScheduleRunReport } from './scheduleStorage';

const WEB_FALLBACK_KEY = 'classset_schema_v19_fallback_store';

interface FallbackStore {
  schoolName: string;
  activeTermId: string | null;
  terms: AcademicTerm[];
  stages: SchoolStage[];
  grades: GradeGroup[];
  classes: ClassGroup[];
  periodTypes: LessonPeriodType[];
  routinesByStage: Record<string, StageRoutine>;
  freeSlots: FreeSlot[];
  commonPeriods: CommonPeriod[];
  calendarExceptions: CalendarException[];
  subjects: Subject[];
  requirements: SubjectRequirement[];
  presets: SubjectPreset[];
  pairings: SubjectPairing[];
  constraints: SubjectLessonConstraint[];
  subjectRoomAssignments: SubjectRoomAssignment[];
  subjectParallelLimits: SubjectParallelLimit[];
  teachers: Teacher[];
  teacherGroups: TeacherGroup[];
  teacherGroupMembers: TeacherGroupMember[];
  teacherAssignments: TeacherAssignment[];
  teacherPresets: TeacherPreset[];
  teacherGroupPresets: TeacherGroupPreset[];
  publicRooms: PublicRoom[];
  scheduleItems: ScheduleItem[];
  publishedSchedules: Record<string, string>;
  scheduleBaselines: Record<string, string>;
  scheduleReports: Record<string, string>;
  scheduleLocks: ScheduleLock[];
  scheduleConditions: ScheduleCondition[];
  schedulePreferences: Record<string, SchedulePreferences>;
  supervisionDrafts: Record<string, SupervisionDraft>;
  supervisionVersions: SupervisionPlanVersion[];
  adjustments: TemporaryCourseAdjustment[];
  routineDoneByTerm: Record<string, boolean>;
  subjectLessonsReadyByTerm: Record<string, boolean>;
  teacherAssignmentsReadyByTerm: Record<string, boolean>;
  hasScheduleByTerm: Record<string, boolean>;
}

type SqlRow = Record<string, unknown>;

function createRecordId(): string {
  return createId();
}

function validateStageRoutine(routine: StageRoutine): void {
  if (!routine.stageId.trim()) throw new Error('学段 ID 不能为空');

  const weekdays = new Set<number>();
  for (const day of routine.teachingDays) {
    if (
      day.stageId !== routine.stageId ||
      !Number.isInteger(day.weekday) ||
      day.weekday < 1 ||
      day.weekday > 7 ||
      weekdays.has(day.weekday)
    ) {
      throw new Error('上课日必须是星期一至星期日，且每个星期只能配置一次');
    }
    weekdays.add(day.weekday);
  }
  if (weekdays.size !== 7) throw new Error('请完整配置星期一至星期日的上课安排');

  const periodsById = new Map<string, LessonPeriodType>();
  for (const period of routine.periodTypes) {
    if (!period.id.trim() || period.stageId !== routine.stageId || periodsById.has(period.id)) {
      throw new Error('时段类型 ID 无效或重复');
    }
    if (!period.name.trim()) throw new Error('时段名称不能为空');
    if (
      !Number.isInteger(period.defaultLessonCount) ||
      period.defaultLessonCount < 0 ||
      period.defaultLessonCount > 9
    ) {
      throw new Error('每个时段每天可设置 0 到 9 节');
    }
    periodsById.set(period.id, period);
  }

  const lessonIds = new Set<string>();
  const lessonKeys = new Set<string>();
  for (const time of routine.lessonTimes) {
    const period = periodsById.get(time.periodTypeId);
    const key = `${time.periodTypeId}:${time.lessonIndex}`;
    if (
      !period ||
      !time.id.trim() ||
      !Number.isInteger(time.lessonIndex) ||
      time.lessonIndex < 1 ||
      time.lessonIndex > period.defaultLessonCount ||
      lessonIds.has(time.id) ||
      lessonKeys.has(key)
    ) {
      throw new Error('节次配置与时段节数不一致');
    }
    if ((time.startMinute === null) !== (time.endMinute === null)) {
      throw new Error(`「${period.name} ${time.label}」的开始和结束时间需要同时填写`);
    }
    if (
      time.startMinute !== null &&
      time.endMinute !== null &&
      (!Number.isInteger(time.startMinute) ||
        !Number.isInteger(time.endMinute) ||
        time.startMinute < 0 ||
        time.endMinute > 1439 ||
        time.startMinute >= time.endMinute)
    ) {
      throw new Error(`「${period.name} ${time.label}」开始时间必须早于结束时间`);
    }
    lessonIds.add(time.id);
    lessonKeys.add(key);
  }

  const overrideKeys = new Set<string>();
  for (const override of routine.dailyOverrides) {
    const key = `${override.periodTypeId}:${override.weekday}`;
    if (
      !periodsById.has(override.periodTypeId) ||
      !Number.isInteger(override.weekday) ||
      override.weekday < 1 ||
      override.weekday > 7 ||
      !Number.isInteger(override.lessonCount) ||
      override.lessonCount < 0 ||
      override.lessonCount > 9 ||
      !override.id.trim() ||
      override.stageId !== routine.stageId ||
      overrideKeys.has(key)
    ) {
      throw new Error('每日节数差异配置无效或重复');
    }
    overrideKeys.add(key);
  }
}

function shiftStoredDate(value: unknown, days: number): unknown {
  if (typeof value !== 'string' || days === 0) return value;
  const datePart = value.slice(0, 10);
  const date = new Date(`${datePart}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime())) return value;
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function calendarDateShift(sourceStart: unknown, targetStart: string | null): number {
  if (typeof sourceStart !== 'string' || !targetStart) return 0;
  const sourceDate = new Date(`${sourceStart.slice(0, 10)}T00:00:00.000Z`);
  const targetDate = new Date(`${targetStart.slice(0, 10)}T00:00:00.000Z`);
  if (Number.isNaN(sourceDate.getTime()) || Number.isNaN(targetDate.getTime())) {
    return 0;
  }
  return Math.round((targetDate.getTime() - sourceDate.getTime()) / 86_400_000);
}

function mapScopeId(
  scopeType: unknown,
  scopeId: unknown,
  targetTermId: string,
  stageIds: ReadonlyMap<string, string>,
  gradeIds: ReadonlyMap<string, string>,
  classIds: ReadonlyMap<string, string>
): string | null {
  if (typeof scopeId !== 'string') return null;
  switch (scopeType) {
    case 'school':
      return targetTermId;
    case 'stage':
      return stageIds.get(scopeId) ?? null;
    case 'grade':
      return gradeIds.get(scopeId) ?? null;
    case 'class':
      return classIds.get(scopeId) ?? null;
    default:
      return null;
  }
}

async function insertSqlRows(
  tx: Pick<SqlDatabaseAdapter, 'execute'>,
  table: string,
  rows: SqlRow[]
): Promise<void> {
  if (rows.length === 0) return;
  const columns = Object.keys(rows[0]);
  const columnSql = columns.map((column) => `"${column}"`).join(', ');
  const rowsPerStatement = Math.max(1, Math.floor(900 / columns.length));
  for (let offset = 0; offset < rows.length; offset += rowsPerStatement) {
    const batch = rows.slice(offset, offset + rowsPerStatement);
    const rowSql = `(${columns.map(() => '?').join(', ')})`;
    const valuesSql = batch.map(() => rowSql).join(', ');
    const values = batch.flatMap((row) => columns.map((column) => row[column]));
    await tx.execute(`INSERT INTO "${table}" (${columnSql}) VALUES ${valuesSql}`, values);
  }
}

async function deleteSqlScopeReferences(
  tx: DbTransactionClient,
  scopeType: 'class' | 'grade',
  scopeIds: string[]
): Promise<void> {
  if (scopeIds.length === 0) return;
  const placeholders = scopeIds.map(() => '?').join(', ');
  const params = [scopeType, ...scopeIds];
  for (const table of [
    'free_slots',
    'subject_presets',
    'subject_lesson_constraints',
    'teacher_presets',
    'teacher_group_presets',
    'subject_room_assignments',
    'subject_parallel_limits',
  ]) {
    await tx.execute(
      `DELETE FROM ${table} WHERE scope_type = ? AND scope_id IN (${placeholders})`,
      params
    );
  }
  if (scopeType === 'class') {
    await tx.execute(
      `DELETE FROM schedule_locks WHERE scope = 'class' AND target_id IN (${placeholders})`,
      scopeIds
    );
  }
  await tx.execute(
    `DELETE FROM schedule_conditions WHERE target_id IN (${placeholders}) OR other_id IN (${placeholders})`,
    [...scopeIds, ...scopeIds]
  );
}

function deleteFallbackScopeReferences(
  store: FallbackStore,
  scopeType: 'class' | 'grade',
  scopeIds: Set<string>
): void {
  store.freeSlots = store.freeSlots.filter(
    (slot) => slot.scopeType !== scopeType || !scopeIds.has(slot.scopeId)
  );
  store.presets = store.presets.filter(
    (preset) => preset.scopeType !== scopeType || !scopeIds.has(preset.scopeId)
  );
  store.constraints = store.constraints.filter(
    (constraint) =>
      constraint.scopeType !== scopeType || !scopeIds.has(constraint.scopeId)
  );
  store.teacherPresets = store.teacherPresets.filter(
    (preset) => preset.scopeType !== scopeType || !scopeIds.has(preset.scopeId)
  );
  store.teacherGroupPresets = store.teacherGroupPresets.filter(
    (preset) => preset.scopeType !== scopeType || !scopeIds.has(preset.scopeId)
  );
  if (scopeType === 'class') {
    store.scheduleLocks = store.scheduleLocks.filter(
      (lock) => lock.scope !== 'class' || !scopeIds.has(lock.targetId)
    );
  }
  store.scheduleConditions = store.scheduleConditions.filter(
    (condition) =>
      !scopeIds.has(condition.targetId ?? '') && !scopeIds.has(condition.otherId ?? '')
  );
}

function cloneFallbackTerm(
  store: FallbackStore,
  sourceTermId: string,
  targetTerm: AcademicTerm
): void {
  if (sourceTermId === targetTerm.id) {
    throw new Error('复制后的学期 ID 不能与来源学期相同');
  }
  const sourceTerm = store.terms.find((term) => term.id === sourceTermId);
  if (!sourceTerm) throw new Error('来源学期不存在');
  if (store.terms.some((term) => term.id === targetTerm.id)) {
    throw new Error('目标学期已存在');
  }

  const dateShift = calendarDateShift(
    sourceTerm.firstTeachingWeekStart,
    targetTerm.firstTeachingWeekStart
  );
  const copyId = () => createRecordId();
  const stageIds = new Map<string, string>();
  const gradeIds = new Map<string, string>();
  const classIds = new Map<string, string>();
  const periodIds = new Map<string, string>();
  const lessonIds = new Map<string, string>();
  const subjectIds = new Map<string, string>();
  const groupIds = new Map<string, string>();
  const sourceClasses = [...store.classes];
  const classesByGrade = new Map<string, ClassGroup[]>();
  for (const schoolClass of sourceClasses) {
    const classes = classesByGrade.get(schoolClass.gradeId) ?? [];
    classes.push(schoolClass);
    classesByGrade.set(schoolClass.gradeId, classes);
  }

  store.terms.unshift({
    ...targetTerm,
    title: targetTerm.title.trim(),
    academicYear: targetTerm.academicYear.trim(),
    semesterLabel: targetTerm.semesterLabel.trim(),
  });

  const sourceStages = store.stages.filter((stage) => stage.termId === sourceTermId);
  for (const stage of sourceStages) {
    const id = copyId();
    stageIds.set(stage.id, id);
    store.stages.push({ ...stage, id, termId: targetTerm.id });
  }

  const sourceGrades = store.grades.filter((grade) => stageIds.has(grade.stageId));
  for (const grade of sourceGrades) {
    const stageId = stageIds.get(grade.stageId);
    if (!stageId) continue;
    const id = copyId();
    gradeIds.set(grade.id, id);
    store.grades.push({ ...grade, id, stageId });
  }

  for (const grade of sourceGrades) {
    const targetGradeId = gradeIds.get(grade.id);
    if (!targetGradeId) continue;
    for (const cls of classesByGrade.get(grade.id) ?? []) {
      const id = copyId();
      classIds.set(cls.id, id);
      store.classes.push({ ...cls, id, gradeId: targetGradeId });
    }
  }

  for (const period of [...store.periodTypes]) {
    const stageId = stageIds.get(period.stageId);
    if (!stageId) continue;
    const id = copyId();
    periodIds.set(period.id, id);
    store.periodTypes.push({ ...period, id, stageId });
    for (let index = 1; index <= period.defaultLessonCount; index++) {
      lessonIds.set(`${period.id}_${index}`, `${id}_${index}`);
    }
  }

  for (const [sourceStageId, routine] of Object.entries(store.routinesByStage)) {
    const stageId = stageIds.get(sourceStageId);
    if (!stageId) continue;
    const copiedPeriods = routine.periodTypes.flatMap((period) => {
      const periodTypeId = periodIds.get(period.id);
      return periodTypeId ? [{ ...period, id: periodTypeId, stageId }] : [];
    });
    const copiedPeriodIds = new Set(copiedPeriods.map((period) => period.id));
    store.routinesByStage[stageId] = {
      stageId,
      teachingDays: routine.teachingDays.map((day) => ({
        ...day,
        id: `td_${stageId}_${day.weekday}`,
        stageId,
      })),
      periodTypes: copiedPeriods,
      dailyOverrides: routine.dailyOverrides.flatMap((override) => {
        const periodTypeId = periodIds.get(override.periodTypeId);
        return periodTypeId && copiedPeriodIds.has(periodTypeId)
          ? [
              {
                ...override,
                id: `${stageId}_${periodTypeId}_${override.weekday}`,
                stageId,
                periodTypeId,
              },
            ]
          : [];
      }),
      lessonTimes: routine.lessonTimes.flatMap((time) => {
        const periodTypeId = periodIds.get(time.periodTypeId);
        return periodTypeId && copiedPeriodIds.has(periodTypeId)
          ? [{ ...time, id: `${periodTypeId}_${time.lessonIndex}`, periodTypeId }]
          : [];
      }),
    };
  }

  const sourceSubjects = store.subjects.filter((subject) => subject.termId === sourceTermId);
  for (const subject of sourceSubjects) {
    const id = copyId();
    subjectIds.set(subject.id, id);
    store.subjects.push({ ...subject, id, termId: targetTerm.id });
  }

  for (const slot of [...store.freeSlots]) {
    const stageId = stageIds.get(slot.stageId);
    const periodTypeId = periodIds.get(slot.periodTypeId);
    const scopeId = mapScopeId(
      slot.scopeType,
      slot.scopeId,
      targetTerm.id,
      stageIds,
      gradeIds,
      classIds
    );
    if (!stageId || !periodTypeId || !scopeId) continue;
    store.freeSlots.push({ ...slot, id: copyId(), stageId, periodTypeId, scopeId });
  }

  for (const commonPeriod of [...store.commonPeriods]) {
    const stageId = stageIds.get(commonPeriod.stageId);
    if (!stageId) continue;
    store.commonPeriods.push({
      ...commonPeriod,
      id: copyId(),
      stageId,
      insertAfterLessonId: commonPeriod.insertAfterLessonId
        ? lessonIds.get(commonPeriod.insertAfterLessonId) ?? null
        : null,
    });
  }

  for (const exception of [...store.calendarExceptions]) {
    if (exception.termId !== sourceTermId) continue;
    store.calendarExceptions.push({
      ...exception,
      id: copyId(),
      termId: targetTerm.id,
      date: shiftStoredDate(exception.date, dateShift) as string,
      makeupForDate: exception.makeupForDate
        ? (shiftStoredDate(exception.makeupForDate, dateShift) as string)
        : null,
    });
  }

  for (const requirement of [...store.requirements]) {
    const subjectId = subjectIds.get(requirement.subjectId);
    const gradeId = gradeIds.get(requirement.gradeId);
    if (!subjectId || !gradeId) continue;
    const classId = requirement.classId ? classIds.get(requirement.classId) : null;
    if (requirement.classId && !classId) continue;
    store.requirements.push({
      ...requirement,
      id: copyId(),
      subjectId,
      gradeId,
      classId: classId ?? null,
    });
  }

  for (const preset of [...store.presets]) {
    const subjectId = subjectIds.get(preset.subjectId);
    const stageId = stageIds.get(preset.stageId);
    const periodTypeId = periodIds.get(preset.periodTypeId);
    const scopeId = mapScopeId(
      preset.scopeType,
      preset.scopeId,
      targetTerm.id,
      stageIds,
      gradeIds,
      classIds
    );
    if (!subjectId || !stageId || !periodTypeId || !scopeId) continue;
    store.presets.push({ ...preset, id: copyId(), subjectId, stageId, periodTypeId, scopeId });
  }

  for (const pairing of [...store.pairings]) {
    const classId = classIds.get(pairing.classId);
    const oddSubjectId = subjectIds.get(pairing.oddSubjectId);
    const evenSubjectId = subjectIds.get(pairing.evenSubjectId);
    if (!classId || !oddSubjectId || !evenSubjectId) continue;
    store.pairings.push({ ...pairing, id: copyId(), classId, oddSubjectId, evenSubjectId });
  }

  for (const constraint of [...store.constraints]) {
    const subjectId = subjectIds.get(constraint.subjectId);
    const stageId = stageIds.get(constraint.stageId);
    const scopeId = mapScopeId(
      constraint.scopeType,
      constraint.scopeId,
      targetTerm.id,
      stageIds,
      gradeIds,
      classIds
    );
    if (!subjectId || !stageId || !scopeId) continue;
    store.constraints.push({ ...constraint, id: copyId(), subjectId, stageId, scopeId });
  }

  for (const assignment of [...store.subjectRoomAssignments]) {
    if (assignment.termId !== sourceTermId) continue;
    const subjectId = subjectIds.get(assignment.subjectId);
    const stageId = stageIds.get(assignment.stageId);
    const scopeId = mapScopeId(assignment.scopeType, assignment.scopeId,
      targetTerm.id, stageIds, gradeIds, classIds);
    if (!subjectId || !stageId || !scopeId) continue;
    store.subjectRoomAssignments.push({ ...assignment, id: copyId(), subjectId,
      termId: targetTerm.id, stageId, scopeId });
  }
  for (const limit of [...store.subjectParallelLimits]) {
    if (limit.termId !== sourceTermId) continue;
    const subjectId = subjectIds.get(limit.subjectId);
    const stageId = stageIds.get(limit.stageId);
    const scopeId = mapScopeId(limit.scopeType, limit.scopeId,
      targetTerm.id, stageIds, gradeIds, classIds);
    if (!subjectId || !stageId || !scopeId) continue;
    store.subjectParallelLimits.push({ ...limit, id: copyId(), subjectId,
      termId: targetTerm.id, stageId, scopeId });
  }

  for (const group of [...store.teacherGroups]) {
    if (group.termId !== sourceTermId) continue;
    const id = copyId();
    groupIds.set(group.id, id);
    store.teacherGroups.push({ ...group, id, termId: targetTerm.id });
  }
  for (const member of [...store.teacherGroupMembers]) {
    const groupId = groupIds.get(member.groupId);
    if (groupId) store.teacherGroupMembers.push({ ...member, groupId });
  }

  for (const assignment of [...store.teacherAssignments]) {
    if (assignment.termId !== sourceTermId) continue;
    const subjectId = subjectIds.get(assignment.subjectId);
    const classId = classIds.get(assignment.classId);
    if (!subjectId || !classId) continue;
    store.teacherAssignments.push({
      ...assignment,
      id: copyId(),
      termId: targetTerm.id,
      subjectId,
      classId,
    });
  }

  for (const preset of [...store.teacherPresets]) {
    if (preset.termId !== sourceTermId) continue;
    const stageId = stageIds.get(preset.stageId);
    const periodTypeId = periodIds.get(preset.periodTypeId);
    const scopeId = mapScopeId(
      preset.scopeType,
      preset.scopeId,
      targetTerm.id,
      stageIds,
      gradeIds,
      classIds
    );
    if (!stageId || !periodTypeId || !scopeId) continue;
    store.teacherPresets.push({
      ...preset,
      id: copyId(),
      termId: targetTerm.id,
      stageId,
      periodTypeId,
      scopeId,
    });
  }
  for (const preset of [...store.teacherGroupPresets]) {
    const groupId = groupIds.get(preset.groupId);
    if (!groupId) continue;
    const stageId = stageIds.get(preset.stageId);
    const periodTypeId = periodIds.get(preset.periodTypeId);
    const scopeId = mapScopeId(preset.scopeType, preset.scopeId, targetTerm.id, stageIds, gradeIds, classIds);
    if (stageId && periodTypeId && scopeId) {
      store.teacherGroupPresets.push({ ...preset, id: copyId(), groupId, stageId, periodTypeId, scopeId });
    }
  }

  store.teachers = store.teachers.map((teacher) => {
    const subjectIdsForTeacher = (teacher.subjectIds ?? [])
      .map((subjectId) => subjectIds.get(subjectId))
      .filter((subjectId): subjectId is string => subjectId != null);
    return subjectIdsForTeacher.length
      ? { ...teacher, subjectIds: [...new Set([...(teacher.subjectIds ?? []), ...subjectIdsForTeacher])] }
      : teacher;
  });

  if (store.schedulePreferences[sourceTermId]) {
    store.schedulePreferences[targetTerm.id] = { ...store.schedulePreferences[sourceTermId] };
  }
  if (store.routineDoneByTerm[sourceTermId]) store.routineDoneByTerm[targetTerm.id] = true;
  if (store.subjectLessonsReadyByTerm[sourceTermId]) {
    store.subjectLessonsReadyByTerm[targetTerm.id] = true;
  }
  if (store.teacherAssignmentsReadyByTerm[sourceTermId]) {
    store.teacherAssignmentsReadyByTerm[targetTerm.id] = true;
  }
  store.hasScheduleByTerm[targetTerm.id] = false;
}

function createEmptyFallbackStore(): FallbackStore {
  return {
    schoolName: '',
    activeTermId: null,
    terms: [],
    stages: [],
    grades: [],
    classes: [],
    periodTypes: [],
    routinesByStage: {},
    freeSlots: [],
    commonPeriods: [],
    calendarExceptions: [],
    subjects: [],
    requirements: [],
    presets: [],
    pairings: [],
    constraints: [],
    subjectRoomAssignments: [],
    subjectParallelLimits: [],
    teachers: [],
    teacherGroups: [],
    teacherGroupMembers: [],
    teacherAssignments: [],
    teacherPresets: [],
    teacherGroupPresets: [],
    publicRooms: [],
    scheduleItems: [],
    publishedSchedules: {},
    scheduleBaselines: {},
    scheduleReports: {},
    scheduleLocks: [],
    scheduleConditions: [],
    schedulePreferences: {},
    supervisionDrafts: {},
    supervisionVersions: [],
    adjustments: [],
    routineDoneByTerm: {},
    subjectLessonsReadyByTerm: {},
    teacherAssignmentsReadyByTerm: {},
    hasScheduleByTerm: {},
  };
}

export class SchoolRepository {
  private readonly adapter: SqlDatabaseAdapter;

  constructor(adapter: SqlDatabaseAdapter = getDatabaseAdapter()) {
    this.adapter = adapter;
  }

  get runtimeMode() {
    return this.adapter.runtimeMode;
  }

  get engineStatus() {
    return this.adapter.engineStatus;
  }

  async withAgentWrite<T>(work: (repository: SchoolRepository) => Promise<T>): Promise<T> {
    if (!this.useSqlEngine) throw new Error('本地数据库未就绪，无法保存确认的操作');
    const adapter = this.adapter;
    const run = async (tx: DbTransactionClient) => {
      const unavailable = async (): Promise<never> => { throw new Error('操作只能在当前事务内执行'); };
      const repository = new SchoolRepository({
        runtimeMode: adapter.runtimeMode,
        schemaVersion: adapter.schemaVersion,
        engineStatus: adapter.engineStatus,
        select: (sql, values) => tx.select(sql, values),
        execute: (sql, values) => tx.execute(sql, values),
        transaction: (run) => run(tx),
        init: unavailable,
        exportSqliteBytes: unavailable,
        importSqliteBytes: unavailable,
        clearAllData: unavailable,
      });
      return work(repository);
    };
    return adapter.durableTransaction ? adapter.durableTransaction(run) : adapter.transaction(run);
  }

  /**
   * 当 Tauri 原生 SQLite 或 Web SQLite Wasm 引擎已就绪时，双端均走真正的 SQLite v19 引擎
   */
  private get useSqlEngine(): boolean {
    return (
      this.adapter.engineStatus === 'native-sqlite' ||
      this.adapter.engineStatus === 'wasm-sqlite'
    );
  }

  private loadFallback(): FallbackStore {
    try {
      const raw = localStorage.getItem(WEB_FALLBACK_KEY);
      if (raw) {
        const merged = {
          ...createEmptyFallbackStore(),
          ...(JSON.parse(raw) as FallbackStore),
        };
        merged.routinesByStage ??= {};
        return merged;
      }
    } catch {
      // ignore
    }
    const emptyStore = createEmptyFallbackStore();
    this.saveFallback(emptyStore);
    return emptyStore;
  }

  private saveFallback(store: FallbackStore): void {
    try {
      localStorage.setItem(WEB_FALLBACK_KEY, JSON.stringify(store));
    } catch {
      // ignore
    }
  }

  async initialize(): Promise<void> {
    await this.adapter.init();
    if (this.useSqlEngine) {
      const settings = await this.adapter.select<{ id: number }>(
        'SELECT id FROM app_settings WHERE id = 1'
      );
      if (settings.length === 0) {
        await this.adapter.execute(
          'INSERT OR IGNORE INTO app_settings (id, school_name, active_term_id) VALUES (1, ?, NULL)',
          ['']
        );
      }
    } else {
      this.loadFallback();
    }
  }


  // ==================== 1. 全局学校设置与学期管理 ====================

  async loadSchoolName(): Promise<string> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{ school_name: string }>(
        'SELECT school_name FROM app_settings WHERE id = 1'
      );
      return rows[0]?.school_name ?? '';
    }
    return this.loadFallback().schoolName;
  }

  async saveSchoolName(name: string): Promise<void> {
    const trimmed = name.trim();
    if (this.useSqlEngine) {
      await this.adapter.execute(
        'INSERT INTO app_settings (id, school_name) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET school_name = excluded.school_name',
        [trimmed]
      );
      return;
    }
    const store = this.loadFallback();
    store.schoolName = trimmed;
    this.saveFallback(store);
  }

  async loadActiveTermId(): Promise<string | null> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{ active_term_id: string | null }>(
        'SELECT active_term_id FROM app_settings WHERE id = 1'
      );
      return rows[0]?.active_term_id ?? null;
    }
    return this.loadFallback().activeTermId;
  }

  async saveActiveTermId(termId: string | null): Promise<void> {
    if (this.useSqlEngine) {
      await this.adapter.execute(
        'INSERT INTO app_settings (id, active_term_id) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET active_term_id = excluded.active_term_id',
        [termId]
      );
      return;
    }
    const store = this.loadFallback();
    store.activeTermId = termId;
    this.saveFallback(store);
  }

  async loadTerms(): Promise<AcademicTerm[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        title: string;
        academic_year: string;
        semester_label: string;
        first_teaching_week_start: string | null;
        teaching_week_count: number;
        cycle_mode: 'every_week' | 'alternating';
        created_at: number;
      }>('SELECT * FROM academic_terms ORDER BY created_at DESC');
      return rows.map((r) => ({
        id: r.id,
        title: r.title,
        academicYear: r.academic_year,
        semesterLabel: r.semester_label,
        firstTeachingWeekStart: r.first_teaching_week_start,
        teachingWeekCount: r.teaching_week_count,
        cycleMode: r.cycle_mode,
        createdAt: r.created_at,
      }));
    }
    return this.loadFallback().terms;
  }

  async saveTerm(term: AcademicTerm): Promise<void> {
    await this.captureScheduleBaseline(term.id);
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        const existing = await tx.select<{ id: string }>(
          'SELECT id FROM academic_terms WHERE id = ?',
          [term.id]
        );
        await tx.execute(
          `INSERT INTO academic_terms (id, title, academic_year, semester_label, first_teaching_week_start, teaching_week_count, cycle_mode, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(id) DO UPDATE SET
             title = excluded.title,
             academic_year = excluded.academic_year,
             semester_label = excluded.semester_label,
             first_teaching_week_start = excluded.first_teaching_week_start,
             teaching_week_count = excluded.teaching_week_count,
             cycle_mode = excluded.cycle_mode`,
          [
            term.id,
            term.title,
            term.academicYear,
            term.semesterLabel,
            term.firstTeachingWeekStart,
            term.teachingWeekCount,
            term.cycleMode,
            term.createdAt,
          ]
        );

        if (existing.length === 0) {
          const stageId = `stage_${term.id}_primary`;
          await tx.execute(
            'INSERT INTO school_stages (id, term_id, name, sort_order) VALUES (?, ?, ?, 0)',
            [stageId, term.id, '小学部']
          );
        }
      });
      return;
    }

    const store = this.loadFallback();
    const idx = store.terms.findIndex((t) => t.id === term.id);
    if (idx >= 0) {
      store.terms[idx] = term;
    } else {
      store.terms.unshift(term);
      const stageId = `stage_${term.id}_primary`;
      store.stages.push({
        id: stageId,
        termId: term.id,
        name: '小学部',
        sortOrder: 0,
      });
    }
    this.saveFallback(store);
  }

  async cloneTerm(sourceTermId: string, targetTerm: AcademicTerm): Promise<void> {
    if (!this.useSqlEngine) {
      const store = this.loadFallback();
      cloneFallbackTerm(store, sourceTermId, targetTerm);
      this.saveFallback(store);
      return;
    }

    if (sourceTermId === targetTerm.id) {
      throw new Error('复制后的学期 ID 不能与来源学期相同');
    }

    await this.adapter.transaction(async (tx) => {
      const sourceTerms = await tx.select<SqlRow>(
        'SELECT * FROM academic_terms WHERE id = ?',
        [sourceTermId]
      );
      if (sourceTerms.length === 0) throw new Error('来源学期不存在');
      const sourceTerm = sourceTerms[0];
      const targetTerms = await tx.select<{ id: string }>(
        'SELECT id FROM academic_terms WHERE id = ?',
        [targetTerm.id]
      );
      if (targetTerms.length > 0) throw new Error('目标学期已存在');

      await tx.execute(
        `INSERT INTO academic_terms (id, title, academic_year, semester_label, first_teaching_week_start, teaching_week_count, cycle_mode, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          targetTerm.id,
          targetTerm.title.trim(),
          targetTerm.academicYear.trim(),
          targetTerm.semesterLabel.trim(),
          targetTerm.firstTeachingWeekStart,
          targetTerm.teachingWeekCount,
          targetTerm.cycleMode,
          targetTerm.createdAt,
        ]
      );

      const selectRows = (table: string, where: string, values: unknown[] = []) =>
        tx.select<SqlRow>(`SELECT * FROM "${table}" WHERE ${where}`, values);
      const rowsForIds = (table: string, column: string, ids: string[]) =>
        ids.length === 0
          ? Promise.resolve([] as SqlRow[])
          : selectRows(
              table,
              `"${column}" IN (${ids.map(() => '?').join(', ')})`,
              ids
            );
      const duplicateRows = async (
        table: string,
        rows: SqlRow[],
        transform: (row: SqlRow) => SqlRow | null = (row) => ({
          ...row,
          id: createRecordId(),
        })
      ): Promise<Map<string, string>> => {
        const idMap = new Map<string, string>();
        const copies: SqlRow[] = [];
        for (const row of rows) {
          const target = transform(row);
          if (!target) continue;
          copies.push(target);
          if (typeof row.id === 'string' && typeof target.id === 'string') {
            idMap.set(row.id, target.id);
          }
        }
        await insertSqlRows(tx, table, copies);
        return idMap;
      };

      const dateShift = calendarDateShift(
        sourceTerm.first_teaching_week_start,
        targetTerm.firstTeachingWeekStart
      );
      const stageRows = await selectRows('school_stages', 'term_id = ?', [sourceTermId]);
      const stageIds = await duplicateRows('school_stages', stageRows, (row) => ({
        ...row,
        id: createRecordId(),
        term_id: targetTerm.id,
      }));

      const gradeRows = await rowsForIds(
        'grade_groups',
        'stage_id',
        [...stageIds.keys()]
      );
      const gradeIds = await duplicateRows('grade_groups', gradeRows, (row) => {
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        return stageId ? { ...row, id: createRecordId(), stage_id: stageId } : null;
      });
      const classRows = await rowsForIds('class_groups', 'grade_id', [...gradeIds.keys()]);
      const classIds = await duplicateRows('class_groups', classRows, (row) => {
        const gradeId = typeof row.grade_id === 'string' ? gradeIds.get(row.grade_id) : null;
        return gradeId ? { ...row, id: createRecordId(), grade_id: gradeId } : null;
      });

      const periodRows = await rowsForIds(
        'lesson_period_types',
        'stage_id',
        [...stageIds.keys()]
      );
      const periodIds = await duplicateRows('lesson_period_types', periodRows, (row) => {
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        return stageId ? { ...row, id: createRecordId(), stage_id: stageId } : null;
      });
      const stageTeachingDays = await rowsForIds(
        'stage_teaching_days',
        'stage_id',
        [...stageIds.keys()]
      );
      await duplicateRows('stage_teaching_days', stageTeachingDays, (row) => {
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        return stageId ? { ...row, id: createRecordId(), stage_id: stageId } : null;
      });

      const lessonRows = await rowsForIds('lesson_times', 'period_type_id', [...periodIds.keys()]);
      const lessonIds = new Map<string, string>();
      const lessonCopies: SqlRow[] = [];
      for (const row of lessonRows) {
        const periodId = typeof row.period_type_id === 'string'
          ? periodIds.get(row.period_type_id)
          : null;
        if (!periodId) continue;
        const id = `${periodId}_${String(row.lesson_index)}`;
        lessonCopies.push({ ...row, id, period_type_id: periodId });
        if (typeof row.id === 'string') lessonIds.set(row.id, id);
      }
      await insertSqlRows(tx, 'lesson_times', lessonCopies);

      const overrides = await rowsForIds('daily_lesson_overrides', 'stage_id', [...stageIds.keys()]);
      await duplicateRows('daily_lesson_overrides', overrides, (row) => {
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        const periodId = typeof row.period_type_id === 'string'
          ? periodIds.get(row.period_type_id)
          : null;
        return stageId && periodId
          ? { ...row, id: createRecordId(), stage_id: stageId, period_type_id: periodId }
          : null;
      });

      const mapScope = (row: SqlRow) =>
        mapScopeId(
          row.scope_type,
          row.scope_id,
          targetTerm.id,
          stageIds,
          gradeIds,
          classIds
        );
      const freeSlots = await rowsForIds('free_slots', 'stage_id', [...stageIds.keys()]);
      await duplicateRows('free_slots', freeSlots, (row) => {
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        const periodId = typeof row.period_type_id === 'string'
          ? periodIds.get(row.period_type_id)
          : null;
        const scopeId = mapScope(row);
        return stageId && periodId && scopeId
          ? {
              ...row,
              id: createRecordId(),
              stage_id: stageId,
              period_type_id: periodId,
              scope_id: scopeId,
            }
          : null;
      });
      const commonPeriods = await rowsForIds(
        'common_periods',
        'stage_id',
        [...stageIds.keys()]
      );
      await duplicateRows('common_periods', commonPeriods, (row) => {
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        const previousLessonId = typeof row.insert_after_lesson_id === 'string'
          ? lessonIds.get(row.insert_after_lesson_id)
          : null;
        return stageId
          ? {
              ...row,
              id: createRecordId(),
              stage_id: stageId,
              insert_after_lesson_id: previousLessonId ?? null,
            }
          : null;
      });

      const subjectRows = await selectRows('subjects', 'term_id = ?', [sourceTermId]);
      const subjectIds = await duplicateRows('subjects', subjectRows, (row) => ({
        ...row,
        id: createRecordId(),
        term_id: targetTerm.id,
      }));
      const subjectTags = await rowsForIds(
        'teacher_subject_tags',
        'subject_id',
        [...subjectIds.keys()]
      );
      await duplicateRows('teacher_subject_tags', subjectTags, (row) => {
        const subjectId = typeof row.subject_id === 'string' ? subjectIds.get(row.subject_id) : null;
        return subjectId ? { ...row, subject_id: subjectId } : null;
      });

      const requirements = await rowsForIds(
        'subject_requirements',
        'grade_id',
        [...gradeIds.keys()]
      );
      await duplicateRows('subject_requirements', requirements, (row) => {
        const subjectId = typeof row.subject_id === 'string' ? subjectIds.get(row.subject_id) : null;
        const gradeId = typeof row.grade_id === 'string' ? gradeIds.get(row.grade_id) : null;
        const classId = typeof row.class_id === 'string' ? classIds.get(row.class_id) : null;
        return subjectId && gradeId && (row.class_id == null || classId)
          ? { ...row, id: createRecordId(), subject_id: subjectId, grade_id: gradeId, class_id: classId ?? null }
          : null;
      });
      const subjectPresets = await rowsForIds(
        'subject_presets',
        'subject_id',
        [...subjectIds.keys()]
      );
      await duplicateRows('subject_presets', subjectPresets, (row) => {
        const subjectId = typeof row.subject_id === 'string' ? subjectIds.get(row.subject_id) : null;
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        const periodId = typeof row.period_type_id === 'string'
          ? periodIds.get(row.period_type_id)
          : null;
        const scopeId = mapScope(row);
        return subjectId && stageId && periodId && scopeId
          ? {
              ...row,
              id: createRecordId(),
              subject_id: subjectId,
              stage_id: stageId,
              period_type_id: periodId,
              scope_id: scopeId,
            }
          : null;
      });
      const pairings = await rowsForIds('subject_pairings', 'class_id', [...classIds.keys()]);
      await duplicateRows('subject_pairings', pairings, (row) => {
        const classId = typeof row.class_id === 'string' ? classIds.get(row.class_id) : null;
        const oddSubjectId = typeof row.odd_subject_id === 'string'
          ? subjectIds.get(row.odd_subject_id)
          : null;
        const evenSubjectId = typeof row.even_subject_id === 'string'
          ? subjectIds.get(row.even_subject_id)
          : null;
        return classId && oddSubjectId && evenSubjectId
          ? {
              ...row,
              id: createRecordId(),
              class_id: classId,
              odd_subject_id: oddSubjectId,
              even_subject_id: evenSubjectId,
            }
          : null;
      });
      const constraints = await rowsForIds(
        'subject_lesson_constraints',
        'subject_id',
        [...subjectIds.keys()]
      );
      await duplicateRows('subject_lesson_constraints', constraints, (row) => {
        const subjectId = typeof row.subject_id === 'string' ? subjectIds.get(row.subject_id) : null;
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        const scopeId = mapScope(row);
        return subjectId && stageId && scopeId
          ? { ...row, id: createRecordId(), subject_id: subjectId, stage_id: stageId, scope_id: scopeId }
          : null;
      });

      const roomAssignments = await selectRows(
        'subject_room_assignments',
        'term_id = ?',
        [sourceTermId]
      );
      await duplicateRows('subject_room_assignments', roomAssignments, (row) => {
        const subjectId = typeof row.subject_id === 'string' ? subjectIds.get(row.subject_id) : null;
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        const scopeId = mapScope(row);
        return subjectId && stageId && scopeId
          ? {
              ...row,
              id: createRecordId(),
              subject_id: subjectId,
              term_id: targetTerm.id,
              stage_id: stageId,
              scope_id: scopeId,
            }
          : null;
      });
      const parallelLimits = await selectRows(
        'subject_parallel_limits',
        'term_id = ?',
        [sourceTermId]
      );
      await duplicateRows('subject_parallel_limits', parallelLimits, (row) => {
        const subjectId = typeof row.subject_id === 'string' ? subjectIds.get(row.subject_id) : null;
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        const scopeId = mapScope(row);
        return subjectId && stageId && scopeId
          ? {
              ...row,
              id: createRecordId(),
              subject_id: subjectId,
              term_id: targetTerm.id,
              stage_id: stageId,
              scope_id: scopeId,
            }
          : null;
      });

      const exceptions = await selectRows('calendar_exceptions', 'term_id = ?', [sourceTermId]);
      await duplicateRows('calendar_exceptions', exceptions, (row) => ({
        ...row,
        id: createRecordId(),
        term_id: targetTerm.id,
        date: shiftStoredDate(row.date, dateShift),
        makeup_for_date: shiftStoredDate(row.makeup_for_date, dateShift),
      }));

      const groups = await selectRows('teacher_groups', 'term_id = ?', [sourceTermId]);
      const groupIds = await duplicateRows('teacher_groups', groups, (row) => ({
        ...row,
        id: createRecordId(),
        term_id: targetTerm.id,
      }));
      const groupMembers = await rowsForIds(
        'teacher_group_members',
        'group_id',
        [...groupIds.keys()]
      );
      await duplicateRows('teacher_group_members', groupMembers, (row) => {
        const groupId = typeof row.group_id === 'string' ? groupIds.get(row.group_id) : null;
        return groupId ? { ...row, group_id: groupId } : null;
      });

      const assignments = await selectRows('teacher_assignments', 'term_id = ?', [sourceTermId]);
      const combinedGroupIds = new Map<string, string>();
      await duplicateRows('teacher_assignments', assignments, (row) => {
        const subjectId = typeof row.subject_id === 'string' ? subjectIds.get(row.subject_id) : null;
        const classId = typeof row.class_id === 'string' ? classIds.get(row.class_id) : null;
        if (!subjectId || !classId) return null;
        const oldGroupId = typeof row.combined_lesson_group_id === 'string'
          ? row.combined_lesson_group_id
          : null;
        if (oldGroupId && !combinedGroupIds.has(oldGroupId)) {
          combinedGroupIds.set(oldGroupId, createRecordId());
        }
        return {
          ...row,
          id: createRecordId(),
          term_id: targetTerm.id,
          subject_id: subjectId,
          class_id: classId,
          combined_lesson_group_id: oldGroupId ? combinedGroupIds.get(oldGroupId) : null,
        };
      });

      const teacherPresets = await selectRows('teacher_presets', 'term_id = ?', [sourceTermId]);
      await duplicateRows('teacher_presets', teacherPresets, (row) => {
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        const periodId = typeof row.period_type_id === 'string'
          ? periodIds.get(row.period_type_id)
          : null;
        const scopeId = mapScope(row);
        return stageId && periodId && scopeId
          ? {
              ...row,
              id: createRecordId(),
              term_id: targetTerm.id,
              stage_id: stageId,
              period_type_id: periodId,
              scope_id: scopeId,
            }
          : null;
      });
      const groupPresets = await rowsForIds(
        'teacher_group_presets',
        'group_id',
        [...groupIds.keys()]
      );
      await duplicateRows('teacher_group_presets', groupPresets, (row) => {
        const groupId = typeof row.group_id === 'string' ? groupIds.get(row.group_id) : null;
        const stageId = typeof row.stage_id === 'string' ? stageIds.get(row.stage_id) : null;
        const periodId = typeof row.period_type_id === 'string'
          ? periodIds.get(row.period_type_id)
          : null;
        const scopeId = mapScope(row);
        return groupId && stageId && periodId && scopeId
          ? {
              ...row,
              id: createRecordId(),
              group_id: groupId,
              stage_id: stageId,
              period_type_id: periodId,
              scope_id: scopeId,
            }
          : null;
      });

      const sourcePreferences = await selectRows(
        'schedule_preferences',
        'term_id = ?',
        [sourceTermId]
      );
      await duplicateRows('schedule_preferences', sourcePreferences, (row) => ({
        ...row,
        term_id: targetTerm.id,
      }));
    });
  }

  async deleteTerm(termId: string): Promise<void> {
    if (this.useSqlEngine) {
      await this.adapter.execute('DELETE FROM academic_terms WHERE id = ?', [termId]);
      return;
    }
    const store = this.loadFallback();
    store.terms = store.terms.filter((t) => t.id !== termId);
    store.scheduleItems = store.scheduleItems.filter((row) => row.termId !== termId);
    store.scheduleLocks = store.scheduleLocks.filter((row) => row.termId !== termId);
    store.scheduleConditions = store.scheduleConditions.filter((row) => row.termId !== termId);
    delete store.schedulePreferences[termId];
    delete store.publishedSchedules[termId];
    delete store.scheduleBaselines[termId];
    delete store.scheduleReports[termId];
    store.stages = store.stages.filter((s) => s.termId !== termId);
    this.saveFallback(store);
  }

  // ==================== 2. 学段、年级与班级结构 ====================

  async loadStages(termId: string): Promise<SchoolStage[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        term_id: string;
        name: string;
        sort_order: number;
      }>('SELECT * FROM school_stages WHERE term_id = ? ORDER BY sort_order ASC', [termId]);
      return rows.map((r) => ({
        id: r.id,
        termId: r.term_id,
        name: r.name,
        sortOrder: r.sort_order,
      }));
    }
    return this.loadFallback().stages.filter((s) => s.termId === termId);
  }

  async saveStage(stage: SchoolStage): Promise<void> {
    if (this.useSqlEngine) {
      await this.adapter.execute(
        `INSERT INTO school_stages (id, term_id, name, sort_order)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET name = excluded.name, sort_order = excluded.sort_order`,
        [stage.id, stage.termId, stage.name, stage.sortOrder]
      );
      return;
    }
    const store = this.loadFallback();
    const idx = store.stages.findIndex((s) => s.id === stage.id);
    if (idx >= 0) store.stages[idx] = stage;
    else store.stages.push(stage);
    this.saveFallback(store);
  }

  async deleteStage(stageId: string): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.execute('DELETE FROM school_stages WHERE id = ?', [stageId]);
      return;
    }
    const store = this.loadFallback();
    store.stages = store.stages.filter((s) => s.id !== stageId);
    delete store.routinesByStage[stageId];
    store.periodTypes = store.periodTypes.filter((p) => p.stageId !== stageId);
    store.freeSlots = store.freeSlots.filter((slot) => slot.stageId !== stageId);
    store.commonPeriods = store.commonPeriods.filter((period) => period.stageId !== stageId);
    this.saveFallback(store);
  }

  async loadGradesForTerm(termId: string): Promise<GradeGroup[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        stage_id: string;
        name: string;
        sort_order: number;
      }>(
        `SELECT g.* FROM grade_groups g
         JOIN school_stages s ON s.id = g.stage_id
         WHERE s.term_id = ?
         ORDER BY s.sort_order ASC, g.sort_order ASC`,
        [termId]
      );
      return rows.map((r) => ({
        id: r.id,
        stageId: r.stage_id,
        name: r.name,
        sortOrder: r.sort_order,
      }));
    }
    const store = this.loadFallback();
    const stageIds = new Set(store.stages.filter((s) => s.termId === termId).map((s) => s.id));
    return store.grades.filter((g) => stageIds.has(g.stageId));
  }

  async saveGrades(grades: GradeGroup[]): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const grade of grades) {
          await tx.execute(
            `INSERT INTO grade_groups (id, stage_id, name, sort_order)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET name = excluded.name, sort_order = excluded.sort_order`,
            [grade.id, grade.stageId, grade.name, grade.sortOrder]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    for (const grade of grades) {
      const idx = store.grades.findIndex((g) => g.id === grade.id);
      if (idx >= 0) store.grades[idx] = grade;
      else store.grades.push(grade);
    }
    this.saveFallback(store);
  }

  async deleteGrade(gradeId: string): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        const classes = await tx.select<{ id: string }>(
          'SELECT id FROM class_groups WHERE grade_id = ?',
          [gradeId]
        );
        const classIds = classes.map((row) => row.id);
        await deleteSqlScopeReferences(tx, 'class', classIds);
        await deleteSqlScopeReferences(tx, 'grade', [gradeId]);
        await tx.execute('DELETE FROM grade_groups WHERE id = ?', [gradeId]);
      });
      return;
    }

    const store = this.loadFallback();
    const classIds = new Set(
      store.classes.filter((schoolClass) => schoolClass.gradeId === gradeId).map((item) => item.id)
    );
    deleteFallbackScopeReferences(store, 'class', classIds);
    deleteFallbackScopeReferences(store, 'grade', new Set([gradeId]));
    store.grades = store.grades.filter((grade) => grade.id !== gradeId);
    store.classes = store.classes.filter((schoolClass) => !classIds.has(schoolClass.id));
    store.requirements = store.requirements.filter(
      (requirement) => requirement.gradeId !== gradeId && !classIds.has(requirement.classId ?? '')
    );
    store.pairings = store.pairings.filter((pairing) => !classIds.has(pairing.classId));
    store.teacherAssignments = store.teacherAssignments.filter(
      (assignment) => !classIds.has(assignment.classId)
    );
    store.scheduleItems = store.scheduleItems.filter((item) => !classIds.has(item.classId));
    this.saveFallback(store);
  }

  async loadClassesForTerm(termId: string): Promise<ClassGroup[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        grade_id: string;
        name: string;
        sort_order: number;
      }>(
        `SELECT c.* FROM class_groups c
         JOIN grade_groups g ON g.id = c.grade_id
         JOIN school_stages s ON s.id = g.stage_id
         WHERE s.term_id = ?
         ORDER BY s.sort_order ASC, g.sort_order ASC, c.sort_order ASC`,
        [termId]
      );
      return rows.map((r) => ({
        id: r.id,
        gradeId: r.grade_id,
        name: r.name,
        sortOrder: r.sort_order,
      }));
    }
    const store = this.loadFallback();
    const stageIds = new Set(store.stages.filter((s) => s.termId === termId).map((s) => s.id));
    const gradeIds = new Set(store.grades.filter((g) => stageIds.has(g.stageId)).map((g) => g.id));
    return store.classes.filter((c) => gradeIds.has(c.gradeId));
  }

  async saveClasses(classes: ClassGroup[]): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const cls of classes) {
          await tx.execute(
            `INSERT INTO class_groups (id, grade_id, name, sort_order)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET name = excluded.name, sort_order = excluded.sort_order`,
            [cls.id, cls.gradeId, cls.name, cls.sortOrder]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    for (const cls of classes) {
      const idx = store.classes.findIndex((c) => c.id === cls.id);
      if (idx >= 0) store.classes[idx] = cls;
      else store.classes.push(cls);
    }
    this.saveFallback(store);
  }

  async deleteClass(classId: string): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await deleteSqlScopeReferences(tx, 'class', [classId]);
        await tx.execute('DELETE FROM class_groups WHERE id = ?', [classId]);
      });
      return;
    }

    const store = this.loadFallback();
    deleteFallbackScopeReferences(store, 'class', new Set([classId]));
    store.classes = store.classes.filter((schoolClass) => schoolClass.id !== classId);
    store.requirements = store.requirements.filter(
      (requirement) => requirement.classId !== classId
    );
    store.pairings = store.pairings.filter((pairing) => pairing.classId !== classId);
    store.teacherAssignments = store.teacherAssignments.filter(
      (assignment) => assignment.classId !== classId
    );
    store.scheduleItems = store.scheduleItems.filter((item) => item.classId !== classId);
    this.saveFallback(store);
  }

  // ==================== 3. 作息、免任课、公共时段与日历例外 ====================

  async loadStageRoutine(stageId: string): Promise<StageRoutine> {
    if (this.useSqlEngine) {
      const [days, periods, overrides, times, commonPeriods] = await Promise.all([
        this.adapter.select<{
          id: string;
          stage_id: string;
          weekday: number;
          is_teaching_day: number;
        }>('SELECT * FROM stage_teaching_days WHERE stage_id = ? ORDER BY weekday ASC', [stageId]),
        this.adapter.select<{
          id: string;
          stage_id: string;
          name: string;
          default_lesson_count: number;
          sort_order: number;
        }>('SELECT * FROM lesson_period_types WHERE stage_id = ? ORDER BY sort_order ASC', [stageId]),
        this.adapter.select<{
          id: string;
          stage_id: string;
          period_type_id: string;
          weekday: number;
          lesson_count: number;
        }>('SELECT * FROM daily_lesson_overrides WHERE stage_id = ?', [stageId]),
        this.adapter.select<{
          id: string;
          period_type_id: string;
          lesson_index: number;
          label: string;
          start_minute: number | null;
          end_minute: number | null;
        }>(
          `SELECT lt.* FROM lesson_times lt
           JOIN lesson_period_types pt ON pt.id = lt.period_type_id
           WHERE pt.stage_id = ?
           ORDER BY pt.sort_order ASC, lt.lesson_index ASC`,
          [stageId]
        ),
        this.adapter.select<{
          id: string;
          stage_id: string;
          name: string;
          insert_after_lesson_id: string | null;
          duration_minutes: number;
          sort_order: number;
          start_minute: number | null;
          end_minute: number | null;
        }>(
          'SELECT * FROM common_periods WHERE stage_id = ? ORDER BY sort_order ASC, name ASC',
          [stageId]
        ),
      ]);

      return {
        stageId,
        teachingDays: days.map((d) => ({
          id: d.id,
          stageId: d.stage_id,
          weekday: d.weekday,
          isTeachingDay: Boolean(d.is_teaching_day),
        })),
        periodTypes: periods.map((p) => ({
          id: p.id,
          stageId: p.stage_id,
          name: p.name,
          defaultLessonCount: p.default_lesson_count,
          sortOrder: p.sort_order,
        })),
        dailyOverrides: overrides.map((o) => ({
          id: o.id,
          stageId: o.stage_id,
          periodTypeId: o.period_type_id,
          weekday: o.weekday,
          lessonCount: o.lesson_count,
        })),
        lessonTimes: times.map((t) => ({
          id: t.id,
          periodTypeId: t.period_type_id,
          lessonIndex: t.lesson_index,
          label: t.label,
          startMinute: t.start_minute,
          endMinute: t.end_minute,
        })),
        commonPeriods: commonPeriods.map((period) => ({
          id: period.id,
          stageId: period.stage_id,
          name: period.name,
          insertAfterLessonId: period.insert_after_lesson_id,
          durationMinutes: period.duration_minutes,
          sortOrder: period.sort_order,
          startMinute: period.start_minute,
          endMinute: period.end_minute,
        })),
      };
    }

    const store = this.loadFallback();
    const savedRoutine = store.routinesByStage[stageId];
    const commonPeriods = store.commonPeriods.filter((period) => period.stageId === stageId);
    if (savedRoutine) return { ...savedRoutine, commonPeriods };
    return {
      stageId,
      teachingDays: [1, 2, 3, 4, 5, 6, 7].map((w) => ({
        id: `td_${stageId}_${w}`,
        stageId,
        weekday: w,
        isTeachingDay: w <= 5,
      })),
      periodTypes: store.periodTypes.filter((p) => p.stageId === stageId),
      dailyOverrides: [],
      lessonTimes: [],
      commonPeriods,
    };
  }

  async saveStageRoutine(routine: StageRoutine): Promise<void> {
    await this.captureScheduleBaselines();
    validateStageRoutine(routine);

    const periodIds = new Set(routine.periodTypes.map((period) => period.id));
    const periodCounts = new Map(
      routine.periodTypes.map((period) => [period.id, period.defaultLessonCount])
    );
    const validLessonIds = new Set(routine.lessonTimes.map((time) => time.id));

    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        const stageRows = await tx.select<{ id: string; term_id: string }>(
          'SELECT id, term_id FROM school_stages WHERE id = ?',
          [routine.stageId]
        );
        const stage = stageRows[0];
        if (!stage) throw new Error('找不到要保存的学段');

        const previousPeriods = await tx.select<{ id: string }>(
          'SELECT id FROM lesson_period_types WHERE stage_id = ?',
          [routine.stageId]
        );
        const previousPeriodIds = new Set(previousPeriods.map((period) => period.id));
        const removedPeriodIds = [...previousPeriodIds].filter((id) => !periodIds.has(id));
        if (removedPeriodIds.length > 0) {
          const scheduledPeriods = await tx.select<{ period_type_id: string }>(
            `SELECT DISTINCT period_type_id FROM schedule_items
             WHERE period_type_id IN (${removedPeriodIds.map(() => '?').join(', ')}) LIMIT 1`,
            removedPeriodIds
          );
          if (scheduledPeriods.length > 0) {
            throw new Error('该时段仍被已有课表使用，请先重新安排相关课节后再删除。');
          }
        }
        const preservedFreeSlots = await tx.select<{
          id: string;
          period_type_id: string;
          lesson_index: number;
        }>(
          'SELECT id, period_type_id, lesson_index FROM free_slots WHERE stage_id = ?',
          [routine.stageId]
        );
        const preservedCommonPeriods = await tx.select<{
          id: string;
          insert_after_lesson_id: string | null;
        }>(
          'SELECT id, insert_after_lesson_id FROM common_periods WHERE stage_id = ?',
          [routine.stageId]
        );
        const previousLessons = await tx.select<{
          id: string;
          period_type_id: string;
        }>(
          `SELECT lt.id, lt.period_type_id FROM lesson_times lt
           JOIN lesson_period_types pt ON pt.id = lt.period_type_id
           WHERE pt.stage_id = ?`,
          [routine.stageId]
        );
        const previousLessonPeriodById = new Map(
          previousLessons.map((lesson) => [lesson.id, lesson.period_type_id])
        );

        const incomingPeriods = routine.periodTypes.map((period) => period.id);
        if (incomingPeriods.length > 0) {
          const conflicts = await tx.select<{ id: string; stage_id: string }>(
            `SELECT id, stage_id FROM lesson_period_types
             WHERE id IN (${incomingPeriods.map(() => '?').join(', ')})`,
            incomingPeriods
          );
          if (conflicts.some((row) => row.stage_id !== routine.stageId)) {
            throw new Error('时段类型 ID 已被其他学段使用');
          }
        }

        // 教学日和按天差异在同一事务中整体替换。
        await tx.execute('DELETE FROM stage_teaching_days WHERE stage_id = ?', [routine.stageId]);
        for (const day of routine.teachingDays) {
          await tx.execute(
            `INSERT INTO stage_teaching_days (id, stage_id, weekday, is_teaching_day)
             VALUES (?, ?, ?, ?)`,
            [day.id, routine.stageId, day.weekday, day.isTeachingDay ? 1 : 0]
          );
        }
        await tx.execute('DELETE FROM daily_lesson_overrides WHERE stage_id = ?', [routine.stageId]);

        for (const oldPeriodId of previousPeriodIds) {
          if (periodIds.has(oldPeriodId)) continue;
          await tx.execute('DELETE FROM lesson_period_types WHERE id = ?', [oldPeriodId]);
        }

        for (const period of routine.periodTypes) {
          if (previousPeriodIds.has(period.id)) {
            await tx.execute(
              `UPDATE lesson_period_types
               SET name = ?, default_lesson_count = ?, sort_order = ?
               WHERE id = ? AND stage_id = ?`,
              [
                period.name.trim(),
                period.defaultLessonCount,
                period.sortOrder,
                period.id,
                routine.stageId,
              ]
            );
          } else {
            await tx.execute(
              `INSERT INTO lesson_period_types
               (id, stage_id, name, default_lesson_count, sort_order)
               VALUES (?, ?, ?, ?, ?)`,
              [
                period.id,
                routine.stageId,
                period.name.trim(),
                period.defaultLessonCount,
                period.sortOrder,
              ]
            );
          }

          await tx.execute('DELETE FROM lesson_times WHERE period_type_id = ?', [period.id]);
          for (const time of routine.lessonTimes.filter((item) => item.periodTypeId === period.id)) {
            await tx.execute(
              `INSERT INTO lesson_times
               (id, period_type_id, lesson_index, label, start_minute, end_minute)
               VALUES (?, ?, ?, ?, ?, ?)`,
              [
                time.id,
                period.id,
                time.lessonIndex,
                time.label,
                time.startMinute,
                time.endMinute,
              ]
            );
          }
        }

        for (const override of routine.dailyOverrides) {
          await tx.execute(
            `INSERT INTO daily_lesson_overrides
             (id, stage_id, period_type_id, weekday, lesson_count)
             VALUES (?, ?, ?, ?, ?)`,
            [
              override.id,
              routine.stageId,
              override.periodTypeId,
              override.weekday,
              override.lessonCount,
            ]
          );
        }

        // 节数缩减或删除时，分块清理已不存在的免任课格，减少 Tauri IPC 往返。
        const invalidFreeSlotIds = preservedFreeSlots.flatMap((slot) => {
          const count = periodCounts.get(slot.period_type_id);
          return count !== undefined && slot.lesson_index <= count ? [] : [slot.id];
        });
        for (let offset = 0; offset < invalidFreeSlotIds.length; offset += 500) {
          const batch = invalidFreeSlotIds.slice(offset, offset + 500);
          await tx.execute(
            `DELETE FROM free_slots WHERE id IN (${batch.map(() => '?').join(', ')})`,
            batch
          );
        }

        // 公共时段的锚点若落在已删除节次，移到该时段最后一节；时段已删除时放到最前。
        for (const commonPeriod of preservedCommonPeriods) {
          const anchor = commonPeriod.insert_after_lesson_id;
          if (!anchor || validLessonIds.has(anchor)) continue;
          const oldPeriodId = previousLessonPeriodById.get(anchor) ??
            routine.periodTypes.find((period) => anchor.startsWith(`${period.id}_`))?.id;
          const lastLesson = oldPeriodId
            ? routine.lessonTimes
                .filter((time) => time.periodTypeId === oldPeriodId)
                .sort((a, b) => b.lessonIndex - a.lessonIndex)[0]
            : undefined;
          await tx.execute(
            'UPDATE common_periods SET insert_after_lesson_id = ? WHERE id = ?',
            [lastLesson?.id ?? null, commonPeriod.id]
          );
        }

        if (routine.commonPeriods) {
          const incomingCommonPeriods = routine.commonPeriods.map((period) => {
            const anchor = period.insertAfterLessonId;
            if (!anchor || validLessonIds.has(anchor)) return period;
            const oldPeriodId = previousLessonPeriodById.get(anchor) ??
              routine.periodTypes.find((item) => anchor.startsWith(`${item.id}_`))?.id;
            const lastLesson = oldPeriodId
              ? routine.lessonTimes
                  .filter((time) => time.periodTypeId === oldPeriodId)
                  .sort((a, b) => b.lessonIndex - a.lessonIndex)[0]
              : undefined;
            return { ...period, insertAfterLessonId: lastLesson?.id ?? null };
          });
          const incomingCommonPeriodIds = incomingCommonPeriods.map((period) => period.id);
          if (incomingCommonPeriodIds.length > 0) {
            const conflicts = await tx.select<{ id: string; stage_id: string }>(
              `SELECT id, stage_id FROM common_periods
               WHERE id IN (${incomingCommonPeriodIds.map(() => '?').join(', ')})`,
              incomingCommonPeriodIds
            );
            if (conflicts.some((row) => row.stage_id !== routine.stageId)) {
              throw new Error('公共时段 ID 已被其他学段使用');
            }
            await tx.execute(
              `DELETE FROM common_periods
               WHERE stage_id = ? AND id NOT IN (${incomingCommonPeriodIds.map(() => '?').join(', ')})`,
              [routine.stageId, ...incomingCommonPeriodIds]
            );
          } else {
            await tx.execute('DELETE FROM common_periods WHERE stage_id = ?', [routine.stageId]);
          }
          const existingCommonPeriodIds = new Set(
            preservedCommonPeriods.map((period) => period.id)
          );
          for (const period of incomingCommonPeriods) {
            const values = [
              period.name.trim(),
              period.insertAfterLessonId,
              period.durationMinutes,
              period.sortOrder,
              period.startMinute,
              period.endMinute,
            ];
            if (existingCommonPeriodIds.has(period.id)) {
              await tx.execute(
                `UPDATE common_periods
                 SET name = ?, insert_after_lesson_id = ?, duration_minutes = ?,
                     sort_order = ?, start_minute = ?, end_minute = ?
                 WHERE id = ? AND stage_id = ?`,
                [...values, period.id, routine.stageId]
              );
            } else {
              await tx.execute(
                `INSERT INTO common_periods
                 (id, stage_id, name, insert_after_lesson_id, duration_minutes,
                  sort_order, start_minute, end_minute)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                [period.id, routine.stageId, ...values]
              );
            }
          }
        }

        if (previousPeriodIds.size === 0) {
          const siblings = await tx.select<{ id: string }>(
            'SELECT id FROM school_stages WHERE term_id = ? AND id <> ? LIMIT 1',
            [stage.term_id, routine.stageId]
          );
          if (siblings.length > 0) {
            const schoolSlots = await tx.select<{
              id: string;
              period_type_id: string;
              period_name: string;
              weekday: number;
              lesson_index: number;
              label: string;
            }>(
              `SELECT fs.id, fs.period_type_id, pt.name AS period_name,
                      fs.weekday, fs.lesson_index, fs.label
               FROM free_slots fs
               JOIN lesson_period_types pt ON pt.id = fs.period_type_id
               WHERE fs.scope_type = 'school' AND fs.scope_id = ?`,
              [stage.term_id]
            );
            const targetPeriodsByName = new Map<string, string>();
            for (const period of routine.periodTypes) {
              if (!targetPeriodsByName.has(period.name)) {
                targetPeriodsByName.set(period.name, period.id);
              }
            }
            const seenSchoolSlots = new Set<string>();
            for (const slot of schoolSlots) {
              const key = `${slot.period_name}:${slot.weekday}:${slot.lesson_index}:${slot.label}`;
              if (seenSchoolSlots.has(key)) continue;
              seenSchoolSlots.add(key);
              const targetPeriodId = targetPeriodsByName.get(slot.period_name);
              const hasLesson = routine.lessonTimes.some(
                (time) =>
                  time.periodTypeId === targetPeriodId &&
                  time.lessonIndex === slot.lesson_index
              );
              if (!targetPeriodId || !hasLesson) continue;
              await tx.execute(
                `INSERT OR IGNORE INTO free_slots
                 (id, scope_type, scope_id, stage_id, period_type_id, weekday, lesson_index, label)
                 VALUES (?, 'school', ?, ?, ?, ?, ?, ?)`,
                [
                  `${routine.stageId}_inh_${slot.id}`,
                  stage.term_id,
                  routine.stageId,
                  targetPeriodId,
                  slot.weekday,
                  slot.lesson_index,
                  slot.label,
                ]
              );
            }
          }
        }
      });
      return;
    }

    const store = this.loadFallback();
    const hadRoutine = Boolean(
      store.routinesByStage[routine.stageId]?.periodTypes.length ||
        store.periodTypes.some((period) => period.stageId === routine.stageId)
    );
    const previousRoutine = store.routinesByStage[routine.stageId];
    const removedPeriodIds = (previousRoutine?.periodTypes ??
      store.periodTypes.filter((period) => period.stageId === routine.stageId))
      .map((period) => period.id)
      .filter((id) => !periodIds.has(id));
    if (
      store.scheduleItems.some(
        (item) => item.periodTypeId !== null && removedPeriodIds.includes(item.periodTypeId)
      )
    ) {
      throw new Error('该时段仍被已有课表使用，请先重新安排相关课节后再删除。');
    }
    const oldPeriodByLessonId = new Map(
      (previousRoutine?.lessonTimes ?? []).map((time) => [time.id, time.periodTypeId])
    );
    store.routinesByStage[routine.stageId] = routine;
    store.periodTypes = [
      ...store.periodTypes.filter((period) => period.stageId !== routine.stageId),
      ...routine.periodTypes,
    ];
    store.freeSlots = store.freeSlots.filter((slot) => {
      if (slot.stageId !== routine.stageId) return true;
      const count = periodCounts.get(slot.periodTypeId);
      return count !== undefined && slot.lessonIndex <= count;
    });
    const incomingCommonPeriods = routine.commonPeriods ?? store.commonPeriods.filter(
      (period) => period.stageId === routine.stageId
    );
    const normalizedCommonPeriods = incomingCommonPeriods.map((period) => {
      if (period.stageId !== routine.stageId || !period.insertAfterLessonId) return period;
      if (validLessonIds.has(period.insertAfterLessonId)) return period;
      const oldPeriodId =
        oldPeriodByLessonId.get(period.insertAfterLessonId) ??
        routine.periodTypes.find((item) =>
          period.insertAfterLessonId?.startsWith(`${item.id}_`)
        )?.id;
      const lastLesson = oldPeriodId
        ? routine.lessonTimes
            .filter((time) => time.periodTypeId === oldPeriodId)
            .sort((a, b) => b.lessonIndex - a.lessonIndex)[0]
        : undefined;
      return { ...period, insertAfterLessonId: lastLesson?.id ?? null };
    });
    store.commonPeriods = [
      ...store.commonPeriods.filter((period) => period.stageId !== routine.stageId),
      ...normalizedCommonPeriods,
    ];
    if (!hadRoutine) {
      const stage = store.stages.find((item) => item.id === routine.stageId);
      const hasSibling = store.stages.some(
        (item) => item.termId === stage?.termId && item.id !== routine.stageId
      );
      if (stage && hasSibling) {
        const targetPeriodsByName = new Map<string, string>();
        for (const period of routine.periodTypes) {
          if (!targetPeriodsByName.has(period.name)) {
            targetPeriodsByName.set(period.name, period.id);
          }
        }
        const sourceSlots = store.freeSlots.filter(
          (slot) => slot.scopeType === 'school' && slot.scopeId === stage.termId
        );
        const seenSchoolSlots = new Set<string>();
        for (const slot of sourceSlots) {
          const sourcePeriod = store.periodTypes.find(
            (period) => period.id === slot.periodTypeId
          );
          if (!sourcePeriod) continue;
          const key = `${sourcePeriod.name}:${slot.weekday}:${slot.lessonIndex}:${slot.label}`;
          if (seenSchoolSlots.has(key)) continue;
          seenSchoolSlots.add(key);
          const targetPeriodId = targetPeriodsByName.get(sourcePeriod.name);
          const hasLesson = routine.lessonTimes.some(
            (time) =>
              time.periodTypeId === targetPeriodId &&
              time.lessonIndex === slot.lessonIndex
          );
          if (!targetPeriodId || !hasLesson) continue;
          store.freeSlots.push({
            ...slot,
            id: `${routine.stageId}_inh_${slot.id}`,
            stageId: routine.stageId,
            periodTypeId: targetPeriodId,
          });
        }
      }
    }
    this.saveFallback(store);
  }

  async loadFreeSlots(stageId: string): Promise<FreeSlot[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        scope_type: ScopeType;
        scope_id: string;
        stage_id: string;
        period_type_id: string;
        weekday: number;
        lesson_index: number;
        label: string;
      }>('SELECT * FROM free_slots WHERE stage_id = ?', [stageId]);
      return rows.map((r) => ({
        id: r.id,
        scopeType: r.scope_type,
        scopeId: r.scope_id,
        stageId: r.stage_id,
        periodTypeId: r.period_type_id,
        weekday: r.weekday,
        lessonIndex: r.lesson_index,
        label: r.label,
      }));
    }
    return this.loadFallback().freeSlots.filter((f) => f.stageId === stageId);
  }

  async saveFreeSlot(slot: FreeSlot): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.execute(
        `INSERT INTO free_slots (id, scope_type, scope_id, stage_id, period_type_id, weekday, lesson_index, label)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET label = excluded.label`,
        [
          slot.id,
          slot.scopeType,
          slot.scopeId,
          slot.stageId,
          slot.periodTypeId,
          slot.weekday,
          slot.lessonIndex,
          slot.label,
        ]
      );
      return;
    }
    const store = this.loadFallback();
    const idx = store.freeSlots.findIndex((f) => f.id === slot.id);
    if (idx >= 0) store.freeSlots[idx] = slot;
    else store.freeSlots.push(slot);
    this.saveFallback(store);
  }

  async deleteFreeSlot(slotId: string): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.execute('DELETE FROM free_slots WHERE id = ?', [slotId]);
      return;
    }
    const store = this.loadFallback();
    store.freeSlots = store.freeSlots.filter((f) => f.id !== slotId);
    this.saveFallback(store);
  }

  async saveFreeSlotChanges(
    upserts: FreeSlot[],
    deleteIds: string[]
  ): Promise<void> {
    if (upserts.length === 0 && deleteIds.length === 0) return;
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (let offset = 0; offset < deleteIds.length; offset += 500) {
          const batch = deleteIds.slice(offset, offset + 500);
          await tx.execute(
            `DELETE FROM free_slots WHERE id IN (${batch.map(() => '?').join(', ')})`,
            batch
          );
        }
        for (const slot of upserts) {
          await tx.execute(
            `INSERT INTO free_slots
             (id, scope_type, scope_id, stage_id, period_type_id, weekday, lesson_index, label)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET
               scope_type = excluded.scope_type,
               scope_id = excluded.scope_id,
               stage_id = excluded.stage_id,
               period_type_id = excluded.period_type_id,
               weekday = excluded.weekday,
               lesson_index = excluded.lesson_index,
               label = excluded.label`,
            [
              slot.id,
              slot.scopeType,
              slot.scopeId,
              slot.stageId,
              slot.periodTypeId,
              slot.weekday,
              slot.lessonIndex,
              slot.label,
            ]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    const removed = new Set(deleteIds);
    const upserted = new Map(upserts.map((slot) => [slot.id, slot]));
    store.freeSlots = store.freeSlots
      .filter((slot) => !removed.has(slot.id) && !upserted.has(slot.id))
      .concat(upserts);
    this.saveFallback(store);
  }

  async loadCalendarExceptions(termId: string): Promise<CalendarException[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        term_id: string;
        date: string;
        kind: 'holiday' | 'makeup';
        makeup_weekday: number | null;
        makeup_for_date: string | null;
        note: string;
      }>('SELECT * FROM calendar_exceptions WHERE term_id = ? ORDER BY date ASC', [termId]);
      return rows.map((r) => ({
        id: r.id,
        termId: r.term_id,
        date: r.date,
        kind: r.kind,
        makeupWeekday: r.makeup_weekday,
        makeupForDate: r.makeup_for_date,
        note: r.note,
      }));
    }
    return this.loadFallback().calendarExceptions.filter((e) => e.termId === termId);
  }

  async saveCalendarExceptions(params: {
    termId: string;
    upserts: CalendarException[];
    deleteIds: string[];
  }): Promise<void> {
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const id of params.deleteIds) {
          await tx.execute('DELETE FROM calendar_exceptions WHERE id = ?', [id]);
        }
        for (const ex of params.upserts) {
          await tx.execute(
            `INSERT INTO calendar_exceptions (id, term_id, date, kind, makeup_weekday, makeup_for_date, note)
             VALUES (?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET
               date = excluded.date,
               kind = excluded.kind,
               makeup_weekday = excluded.makeup_weekday,
               makeup_for_date = excluded.makeup_for_date,
               note = excluded.note`,
            [
              ex.id,
              params.termId,
              ex.date,
              ex.kind,
              ex.makeupWeekday,
              ex.makeupForDate,
              ex.note,
            ]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    const delSet = new Set(params.deleteIds);
    store.calendarExceptions = store.calendarExceptions.filter((e) => !delSet.has(e.id));
    for (const ex of params.upserts) {
      const idx = store.calendarExceptions.findIndex((e) => e.id === ex.id);
      if (idx >= 0) store.calendarExceptions[idx] = ex;
      else store.calendarExceptions.push(ex);
    }
    this.saveFallback(store);
  }

  // ==================== 4. 科目、需求、预设、配对、课节限制与公共场室 ====================

  async loadSubjects(termId: string): Promise<Subject[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        term_id: string | null;
        name: string;
        short_name: string;
        sort_order: number;
      }>('SELECT * FROM subjects WHERE term_id = ? ORDER BY sort_order ASC', [termId]);
      return rows.map((r) => ({
        id: r.id,
        termId: r.term_id,
        name: r.name,
        shortName: r.short_name,
        sortOrder: r.sort_order,
      }));
    }
    return this.loadFallback().subjects.filter((s) => s.termId === termId || s.termId === null);
  }

  async saveSubjects(subjects: Subject[]): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const sub of subjects) {
          await tx.execute(
            `INSERT INTO subjects (id, term_id, name, short_name, sort_order)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET
               name = excluded.name,
               short_name = excluded.short_name,
               sort_order = excluded.sort_order`,
            [sub.id, sub.termId, sub.name, sub.shortName, sub.sortOrder]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    for (const sub of subjects) {
      const idx = store.subjects.findIndex((s) => s.id === sub.id);
      if (idx >= 0) store.subjects[idx] = sub;
      else store.subjects.push(sub);
    }
    this.saveFallback(store);
  }

  async loadSubjectRequirements(termId: string): Promise<SubjectRequirement[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string; subject_id: string; grade_id: string; class_id: string | null;
        week_mode: SubjectRequirement['weekMode']; lesson_count: number;
      }>(`SELECT r.* FROM subject_requirements r
          JOIN subjects s ON s.id = r.subject_id
          WHERE s.term_id = ?`, [termId]);
      return rows.map((row) => ({
        id: row.id, subjectId: row.subject_id, gradeId: row.grade_id,
        classId: row.class_id, weekMode: row.week_mode, lessonCount: row.lesson_count,
      }));
    }
    const subjectIds = new Set(this.loadFallback().subjects.filter((s) => s.termId === termId).map((s) => s.id));
    return this.loadFallback().requirements.filter((row) => subjectIds.has(row.subjectId));
  }

  async loadSubjectPresets(termId: string): Promise<SubjectPreset[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string; subject_id: string; scope_type: ScopeType; scope_id: string;
        stage_id: string; weekday: number; period_type_id: string; lesson_index: number;
        value: SubjectPreset['value'];
      }>(`SELECT p.* FROM subject_presets p JOIN subjects s ON s.id = p.subject_id
          WHERE s.term_id = ?`, [termId]);
      return rows.map((row) => ({
        id: row.id, subjectId: row.subject_id, scopeType: row.scope_type,
        scopeId: row.scope_id, stageId: row.stage_id, weekday: row.weekday,
        periodTypeId: row.period_type_id, lessonIndex: row.lesson_index, value: row.value,
      }));
    }
    const store = this.loadFallback();
    const subjectIds = new Set(store.subjects.filter((row) => row.termId === termId).map((row) => row.id));
    return store.presets.filter((row) => subjectIds.has(row.subjectId));
  }

  async loadSubjectLessonConstraints(termId: string): Promise<SubjectLessonConstraint[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string; subject_id: string; scope_type: ScopeType; scope_id: string; stage_id: string;
        weekday: number | null; minimum_daily_lessons: number | null; maximum_daily_lessons: number | null;
        minimum_daily_consecutive_pairs: number | null; maximum_daily_consecutive_pairs: number | null;
        minimum_weekly_consecutive_pairs: number | null; maximum_weekly_consecutive_pairs: number | null;
      }>(`SELECT c.* FROM subject_lesson_constraints c JOIN subjects s ON s.id = c.subject_id
          WHERE s.term_id = ?`, [termId]);
      return rows.map((row) => ({ id: row.id, subjectId: row.subject_id,
        scopeType: row.scope_type, scopeId: row.scope_id, stageId: row.stage_id,
        weekday: row.weekday, minimumDailyLessons: row.minimum_daily_lessons,
        maximumDailyLessons: row.maximum_daily_lessons,
        minimumDailyConsecutivePairs: row.minimum_daily_consecutive_pairs,
        maximumDailyConsecutivePairs: row.maximum_daily_consecutive_pairs,
        minimumWeeklyConsecutivePairs: row.minimum_weekly_consecutive_pairs,
        maximumWeeklyConsecutivePairs: row.maximum_weekly_consecutive_pairs }));
    }
    const store = this.loadFallback();
    const subjectIds = new Set(store.subjects.filter((row) => row.termId === termId).map((row) => row.id));
    return store.constraints.filter((row) => subjectIds.has(row.subjectId));
  }

  async loadSubjectRoomSettings(termId: string): Promise<{
    assignments: SubjectRoomAssignment[]; limits: SubjectParallelLimit[];
  }> {
    if (this.useSqlEngine) {
      const [assignmentRows, limitRows] = await Promise.all([
        this.adapter.select<{ id: string; subject_id: string; term_id: string; stage_id: string;
          scope_type: ScopeType; scope_id: string; room_id: string | null }>(
          'SELECT * FROM subject_room_assignments WHERE term_id = ?', [termId]),
        this.adapter.select<{ id: string; subject_id: string; term_id: string; stage_id: string;
          scope_type: ScopeType; scope_id: string; max_parallel_lessons: number }>(
          'SELECT * FROM subject_parallel_limits WHERE term_id = ?', [termId]),
      ]);
      return {
        assignments: assignmentRows.map((row) => ({ id: row.id, subjectId: row.subject_id,
          termId: row.term_id, stageId: row.stage_id, scopeType: row.scope_type,
          scopeId: row.scope_id, roomId: row.room_id })),
        limits: limitRows.map((row) => ({ id: row.id, subjectId: row.subject_id,
          termId: row.term_id, stageId: row.stage_id, scopeType: row.scope_type,
          scopeId: row.scope_id, maxParallelLessons: row.max_parallel_lessons })),
      };
    }
    const store = this.loadFallback();
    return { assignments: store.subjectRoomAssignments.filter((row) => row.termId === termId),
      limits: store.subjectParallelLimits.filter((row) => row.termId === termId) };
  }

  async deleteSubject(subjectId: string): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.execute('DELETE FROM subjects WHERE id = ?', [subjectId]);
      return;
    }
    const store = this.loadFallback();
    store.subjects = store.subjects.filter((row) => row.id !== subjectId);
    store.requirements = store.requirements.filter((row) => row.subjectId !== subjectId);
    store.presets = store.presets.filter((row) => row.subjectId !== subjectId);
    store.constraints = store.constraints.filter((row) => row.subjectId !== subjectId);
    store.subjectRoomAssignments = store.subjectRoomAssignments.filter((row) => row.subjectId !== subjectId);
    store.subjectParallelLimits = store.subjectParallelLimits.filter((row) => row.subjectId !== subjectId);
    store.pairings = store.pairings.filter((row) => row.oddSubjectId !== subjectId && row.evenSubjectId !== subjectId);
    store.teacherAssignments = store.teacherAssignments.filter((row) => row.subjectId !== subjectId);
    this.saveFallback(store);
  }

  async loadSubjectPairings(termId: string): Promise<SubjectPairing[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string; class_id: string; odd_subject_id: string; even_subject_id: string;
      }>(`SELECT p.* FROM subject_pairings p
          JOIN class_groups c ON c.id = p.class_id
          JOIN grade_groups g ON g.id = c.grade_id
          JOIN school_stages st ON st.id = g.stage_id
          WHERE st.term_id = ?`, [termId]);
      return rows.map((row) => ({ id: row.id, classId: row.class_id, oddSubjectId: row.odd_subject_id, evenSubjectId: row.even_subject_id }));
    }
    const store = this.loadFallback();
    const stageIds = new Set(store.stages.filter((row) => row.termId === termId).map((row) => row.id));
    const gradeIds = new Set(store.grades.filter((row) => stageIds.has(row.stageId)).map((row) => row.id));
    const classIds = new Set(store.classes.filter((row) => gradeIds.has(row.gradeId)).map((row) => row.id));
    return store.pairings.filter((row) => classIds.has(row.classId));
  }

  async replaceClassPairings(classId: string, pairings: SubjectPairing[]): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await tx.execute('DELETE FROM subject_pairings WHERE class_id = ?', [classId]);
        for (const row of pairings) {
          await tx.execute('INSERT INTO subject_pairings (id, class_id, odd_subject_id, even_subject_id) VALUES (?, ?, ?, ?)',
            [row.id, classId, row.oddSubjectId, row.evenSubjectId]);
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.pairings = store.pairings.filter((row) => row.classId !== classId).concat(pairings);
    this.saveFallback(store);
  }

  async saveSubjectChanges(changes: {
    upserts: Subject[];
    deletedIds: string[];
    requirementsByGrade: Record<string, SubjectRequirement[]>;
    pairingsByClass: Record<string, SubjectPairing[]>;
    presetScopes: Array<{
      subjectId: string; scopeType: ScopeType; scopeId: string; stageId: string;
      rows: SubjectPreset[];
    }>;
    constraintScopes: Array<{
      subjectId: string; scopeType: ScopeType; scopeId: string; stageId: string;
      rows: SubjectLessonConstraint[];
    }>;
    roomScopes: Array<{
      subjectId: string; scopeType: ScopeType; scopeId: string; stageId: string;
      assignment: SubjectRoomAssignment | null; limit: SubjectParallelLimit | null;
    }>;
  }): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const subject of changes.upserts) {
          await tx.execute(`INSERT INTO subjects (id, term_id, name, short_name, sort_order)
            VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET
            name = excluded.name, short_name = excluded.short_name,
            sort_order = excluded.sort_order`,
            [subject.id, subject.termId, subject.name, subject.shortName, subject.sortOrder]);
        }
        for (const [gradeId, rows] of Object.entries(changes.requirementsByGrade)) {
          await tx.execute('DELETE FROM subject_requirements WHERE grade_id = ?', [gradeId]);
          for (const row of rows) {
            await tx.execute(`INSERT INTO subject_requirements
              (id, subject_id, grade_id, class_id, week_mode, lesson_count)
              VALUES (?, ?, ?, ?, ?, ?)`,
              [row.id, row.subjectId, gradeId, row.classId, row.weekMode, row.lessonCount]);
          }
        }
        for (const [classId, rows] of Object.entries(changes.pairingsByClass)) {
          await tx.execute('DELETE FROM subject_pairings WHERE class_id = ?', [classId]);
          for (const row of rows) {
            await tx.execute('INSERT INTO subject_pairings (id, class_id, odd_subject_id, even_subject_id) VALUES (?, ?, ?, ?)',
              [row.id, classId, row.oddSubjectId, row.evenSubjectId]);
          }
        }
        for (const scope of changes.presetScopes) {
          await tx.execute(`DELETE FROM subject_presets WHERE subject_id = ? AND scope_type = ?
            AND scope_id = ? AND stage_id = ?`,
            [scope.subjectId, scope.scopeType, scope.scopeId, scope.stageId]);
          for (const row of scope.rows) {
            await tx.execute(`INSERT INTO subject_presets
              (id, subject_id, scope_type, scope_id, stage_id, weekday, period_type_id, lesson_index, value)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
              [row.id, scope.subjectId, scope.scopeType, scope.scopeId, scope.stageId,
                row.weekday, row.periodTypeId, row.lessonIndex, row.value]);
          }
        }
        for (const scope of changes.constraintScopes) {
          await tx.execute(`DELETE FROM subject_lesson_constraints WHERE subject_id = ?
            AND scope_type = ? AND scope_id = ? AND stage_id = ?`,
            [scope.subjectId, scope.scopeType, scope.scopeId, scope.stageId]);
          for (const row of scope.rows) {
            await tx.execute(`INSERT INTO subject_lesson_constraints (id, subject_id,
              scope_type, scope_id, stage_id, weekday, minimum_daily_lessons,
              maximum_daily_lessons, minimum_daily_consecutive_pairs,
              maximum_daily_consecutive_pairs, minimum_weekly_consecutive_pairs,
              maximum_weekly_consecutive_pairs) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
              [row.id, scope.subjectId, scope.scopeType, scope.scopeId, scope.stageId,
                row.weekday, row.minimumDailyLessons, row.maximumDailyLessons,
                row.minimumDailyConsecutivePairs, row.maximumDailyConsecutivePairs,
                row.minimumWeeklyConsecutivePairs, row.maximumWeeklyConsecutivePairs]);
          }
        }
        for (const scope of changes.roomScopes) {
          const bind = [scope.subjectId, scope.scopeType, scope.scopeId, scope.stageId];
          await tx.execute(`DELETE FROM subject_room_assignments WHERE subject_id = ? AND scope_type = ? AND scope_id = ? AND stage_id = ?`, bind);
          await tx.execute(`DELETE FROM subject_parallel_limits WHERE subject_id = ? AND scope_type = ? AND scope_id = ? AND stage_id = ?`, bind);
          if (scope.assignment) await tx.execute(`INSERT INTO subject_room_assignments
            (id, subject_id, term_id, stage_id, scope_type, scope_id, room_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)`, [scope.assignment.id, scope.subjectId,
              scope.assignment.termId, scope.stageId, scope.scopeType, scope.scopeId, scope.assignment.roomId]);
          if (scope.limit) await tx.execute(`INSERT INTO subject_parallel_limits
            (id, subject_id, term_id, stage_id, scope_type, scope_id, max_parallel_lessons)
            VALUES (?, ?, ?, ?, ?, ?, ?)`, [scope.limit.id, scope.subjectId,
              scope.limit.termId, scope.stageId, scope.scopeType, scope.scopeId, scope.limit.maxParallelLessons]);
        }
        for (const id of changes.deletedIds) await tx.execute('DELETE FROM subjects WHERE id = ?', [id]);
      });
      return;
    }
    const store = this.loadFallback();
    for (const subject of changes.upserts) {
      const index = store.subjects.findIndex((row) => row.id === subject.id);
      if (index < 0) store.subjects.push(subject);
      else store.subjects[index] = subject;
    }
    for (const [gradeId, rows] of Object.entries(changes.requirementsByGrade)) {
      store.requirements = store.requirements.filter((row) => row.gradeId !== gradeId).concat(rows);
    }
    for (const [classId, rows] of Object.entries(changes.pairingsByClass)) {
      store.pairings = store.pairings.filter((row) => row.classId !== classId).concat(rows);
    }
    for (const scope of changes.presetScopes) {
      store.presets = store.presets.filter((row) =>
        !(row.subjectId === scope.subjectId && row.scopeType === scope.scopeType &&
          row.scopeId === scope.scopeId && row.stageId === scope.stageId)).concat(scope.rows);
    }
    for (const scope of changes.constraintScopes) {
      store.constraints = store.constraints.filter((row) =>
        !(row.subjectId === scope.subjectId && row.scopeType === scope.scopeType &&
          row.scopeId === scope.scopeId && row.stageId === scope.stageId)).concat(scope.rows);
    }
    for (const scope of changes.roomScopes) {
      store.subjectRoomAssignments = store.subjectRoomAssignments.filter((row) =>
        !(row.subjectId === scope.subjectId && row.scopeType === scope.scopeType &&
          row.scopeId === scope.scopeId && row.stageId === scope.stageId));
      store.subjectParallelLimits = store.subjectParallelLimits.filter((row) =>
        !(row.subjectId === scope.subjectId && row.scopeType === scope.scopeType &&
          row.scopeId === scope.scopeId && row.stageId === scope.stageId));
      if (scope.assignment) store.subjectRoomAssignments.push(scope.assignment);
      if (scope.limit) store.subjectParallelLimits.push(scope.limit);
    }
    const deleted = new Set(changes.deletedIds);
    store.subjects = store.subjects.filter((row) => !deleted.has(row.id));
    store.requirements = store.requirements.filter((row) => !deleted.has(row.subjectId));
    store.presets = store.presets.filter((row) => !deleted.has(row.subjectId));
    store.constraints = store.constraints.filter((row) => !deleted.has(row.subjectId));
    store.subjectRoomAssignments = store.subjectRoomAssignments.filter((row) => !deleted.has(row.subjectId));
    store.subjectParallelLimits = store.subjectParallelLimits.filter((row) => !deleted.has(row.subjectId));
    store.pairings = store.pairings.filter((row) => !deleted.has(row.oddSubjectId) && !deleted.has(row.evenSubjectId));
    store.teacherAssignments = store.teacherAssignments.filter((row) => !deleted.has(row.subjectId));
    this.saveFallback(store);
  }

  async replaceGradeRequirements(
    gradeId: string,
    requirements: SubjectRequirement[]
  ): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await tx.execute('DELETE FROM subject_requirements WHERE grade_id = ?', [gradeId]);
        for (const req of requirements) {
          await tx.execute(
            `INSERT INTO subject_requirements (id, subject_id, grade_id, class_id, week_mode, lesson_count)
             VALUES (?, ?, ?, ?, ?, ?)`,
            [req.id, req.subjectId, gradeId, req.classId, req.weekMode, req.lessonCount]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.requirements = store.requirements
      .filter((r) => r.gradeId !== gradeId)
      .concat(requirements);
    this.saveFallback(store);
  }

  async loadPublicRooms(): Promise<PublicRoom[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        name: string;
        room_count: number;
        capacity_per_room: number;
        sort_order: number;
      }>('SELECT * FROM public_rooms ORDER BY sort_order ASC');
      return rows.map((r) => ({
        id: r.id,
        name: r.name,
        roomCount: r.room_count,
        capacityPerRoom: r.capacity_per_room,
        sortOrder: r.sort_order,
      }));
    }
    return this.loadFallback().publicRooms;
  }

  async savePublicRooms(rooms: PublicRoom[]): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const room of rooms) {
          await tx.execute(
            `INSERT INTO public_rooms (id, name, room_count, capacity_per_room, sort_order)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET
               name = excluded.name,
               room_count = excluded.room_count,
               capacity_per_room = excluded.capacity_per_room,
               sort_order = excluded.sort_order`,
            [room.id, room.name, room.roomCount, room.capacityPerRoom, room.sortOrder]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    const incomingById = new Map(rooms.map((r) => [r.id, r]));
    const merged = store.publicRooms
      .filter((r) => !incomingById.has(r.id))
      .concat(rooms)
      .sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
    store.publicRooms = merged;
    this.saveFallback(store);
  }

  async deletePublicRoom(roomId: string): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await tx.execute('DELETE FROM subject_room_assignments WHERE room_id = ?', [roomId]);
        await tx.execute('DELETE FROM public_rooms WHERE id = ?', [roomId]);
      });
      return;
    }
    const store = this.loadFallback();
    store.subjectRoomAssignments = store.subjectRoomAssignments.filter(
      (a) => a.roomId !== roomId
    );
    store.publicRooms = store.publicRooms.filter((r) => r.id !== roomId);
    this.saveFallback(store);
  }

  async loadRoomReferences(roomId: string): Promise<SubjectRoomAssignment[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        subject_id: string;
        term_id: string;
        stage_id: string;
        scope_type: ScopeType;
        scope_id: string;
        room_id: string | null;
      }>(
        'SELECT * FROM subject_room_assignments WHERE room_id = ? ORDER BY term_id ASC, stage_id ASC, subject_id ASC',
        [roomId]
      );
      return rows.map((row) => ({
        id: row.id,
        subjectId: row.subject_id,
        termId: row.term_id,
        stageId: row.stage_id,
        scopeType: row.scope_type,
        scopeId: row.scope_id,
        roomId: row.room_id,
      }));
    }
    return this.loadFallback()
      .subjectRoomAssignments.filter((a) => a.roomId === roomId)
      .sort(
        (a, b) =>
          a.termId.localeCompare(b.termId) ||
          a.stageId.localeCompare(b.stageId) ||
          a.subjectId.localeCompare(b.subjectId)
      );
  }

  async loadPublicRoomTermData(termId: string): Promise<PublicRoomTermData> {
    const [stages, grades, classes, subjects, roomSettings] = await Promise.all([
      this.loadStages(termId),
      this.loadGradesForTerm(termId),
      this.loadClassesForTerm(termId),
      this.loadSubjects(termId),
      this.loadSubjectRoomSettings(termId),
    ]);
    return new PublicRoomTermData({
      termId,
      stages,
      grades,
      classes,
      assignments: roomSettings.assignments,
      subjects,
    });
  }

  // ==================== 5. 教师、分组、任课与预排 ====================

  async loadTeachers(): Promise<Teacher[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        name: string;
        short_name: string;
        display_qualifier: string;
        sort_order: number;
      }>('SELECT * FROM teachers ORDER BY sort_order ASC');
      const tags = await this.adapter.select<{ teacher_id: string; subject_id: string }>(
        'SELECT teacher_id, subject_id FROM teacher_subject_tags'
      );
      const subjectIdsByTeacher = new Map<string, string[]>();
      for (const tag of tags) {
        const ids = subjectIdsByTeacher.get(tag.teacher_id) ?? [];
        ids.push(tag.subject_id);
        subjectIdsByTeacher.set(tag.teacher_id, ids);
      }
      return rows.map((r) => ({
        id: r.id,
        name: r.name,
        shortName: r.short_name,
        displayQualifier: r.display_qualifier,
        sortOrder: r.sort_order,
        subjectIds: subjectIdsByTeacher.get(r.id) ?? [],
      }));
    }
    return this.loadFallback().teachers;
  }

  async saveTeachers(teachers: Teacher[]): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const tch of teachers) {
          await tx.execute(
            `INSERT INTO teachers (id, name, short_name, display_qualifier, sort_order)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET
               name = excluded.name,
               short_name = excluded.short_name,
               display_qualifier = excluded.display_qualifier,
               sort_order = excluded.sort_order`,
            [tch.id, tch.name, tch.shortName, tch.displayQualifier, tch.sortOrder]
          );
          if (tch.subjectIds !== undefined) {
            await tx.execute('DELETE FROM teacher_subject_tags WHERE teacher_id = ?', [tch.id]);
            for (const subjectId of new Set(tch.subjectIds)) {
              await tx.execute(
                'INSERT INTO teacher_subject_tags (teacher_id, subject_id) VALUES (?, ?)',
                [tch.id, subjectId]
              );
            }
          }
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teachers = [...store.teachers.filter((item) => !teachers.some((next) => next.id === item.id)), ...teachers];
    this.saveFallback(store);
  }

  async deleteTeacher(teacherId: string): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.execute('DELETE FROM teachers WHERE id = ?', [teacherId]);
      return;
    }
    const store = this.loadFallback();
    store.teachers = store.teachers.filter((item) => item.id !== teacherId);
    store.teacherAssignments = store.teacherAssignments.map((item) => item.teacherId === teacherId ? { ...item, teacherId: null } : item);
    store.teacherGroupMembers = store.teacherGroupMembers.filter((item) => item.teacherId !== teacherId);
    store.teacherPresets = store.teacherPresets.filter((item) => item.teacherId !== teacherId);
    this.saveFallback(store);
  }

  async loadTeacherGroups(termId: string): Promise<TeacherGroup[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{ id: string; term_id: string; name: string; description: string; sort_order: number }>(
        'SELECT * FROM teacher_groups WHERE term_id = ? ORDER BY sort_order, name', [termId]
      );
      return rows.map((row) => ({ id: row.id, termId: row.term_id, name: row.name, description: row.description, sortOrder: row.sort_order }));
    }
    return this.loadFallback().teacherGroups.filter((group) => group.termId === termId);
  }

  async saveTeacherGroup(group: TeacherGroup): Promise<void> {
    if (this.useSqlEngine) {
      await this.adapter.execute(
        `INSERT INTO teacher_groups (id, term_id, name, description, sort_order) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET name = excluded.name, description = excluded.description, sort_order = excluded.sort_order`,
        [group.id, group.termId, group.name, group.description, group.sortOrder]
      );
      return;
    }
    const store = this.loadFallback();
    store.teacherGroups = [...store.teacherGroups.filter((item) => item.id !== group.id), group];
    this.saveFallback(store);
  }

  async deleteTeacherGroup(groupId: string): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.execute('DELETE FROM teacher_groups WHERE id = ?', [groupId]);
      return;
    }
    const store = this.loadFallback();
    store.teacherGroups = store.teacherGroups.filter((item) => item.id !== groupId);
    store.teacherGroupMembers = store.teacherGroupMembers.filter((item) => item.groupId !== groupId);
    store.teacherGroupPresets = store.teacherGroupPresets.filter((item) => item.groupId !== groupId);
    this.saveFallback(store);
  }

  async loadTeacherGroupMembers(termId: string): Promise<TeacherGroupMember[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{ group_id: string; teacher_id: string }>(
        'SELECT m.group_id, m.teacher_id FROM teacher_group_members m JOIN teacher_groups g ON g.id = m.group_id WHERE g.term_id = ?', [termId]
      );
      return rows.map((row) => ({ groupId: row.group_id, teacherId: row.teacher_id }));
    }
    const groups = new Set(this.loadFallback().teacherGroups.filter((item) => item.termId === termId).map((item) => item.id));
    return this.loadFallback().teacherGroupMembers.filter((item) => groups.has(item.groupId));
  }

  async replaceTeacherGroupMembers(groupId: string, members: TeacherGroupMember[]): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await tx.execute('DELETE FROM teacher_group_members WHERE group_id = ?', [groupId]);
        for (const teacherId of new Set(members.map((item) => item.teacherId))) {
          await tx.execute('INSERT INTO teacher_group_members (group_id, teacher_id) VALUES (?, ?)', [groupId, teacherId]);
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teacherGroupMembers = [...store.teacherGroupMembers.filter((item) => item.groupId !== groupId), ...members];
    this.saveFallback(store);
  }

  async loadTeacherAssignments(termId: string): Promise<TeacherAssignment[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        term_id: string;
        teacher_id: string | null;
        subject_id: string;
        class_id: string;
        week_mode: 'weekly' | 'odd' | 'even';
        lesson_count: number;
        sort_order: number;
        combined_lesson_group_id: string | null;
      }>('SELECT * FROM teacher_assignments WHERE term_id = ? ORDER BY sort_order ASC', [termId]);
      return rows.map((r) => ({
        id: r.id,
        termId: r.term_id,
        teacherId: r.teacher_id,
        subjectId: r.subject_id,
        classId: r.class_id,
        weekMode: r.week_mode,
        lessonCount: r.lesson_count,
        sortOrder: r.sort_order,
        combinedLessonGroupId: r.combined_lesson_group_id,
      }));
    }
    return this.loadFallback().teacherAssignments.filter((a) => a.termId === termId);
  }

  private async validateTeacherAssignmentCapacity(termId: string, proposed: TeacherAssignment[], retained: TeacherAssignment[]): Promise<void> {
    if (!proposed.length) return;
    const [classes, subjects, teachers, requirements] = await Promise.all([
      this.loadClassesForTerm(termId), this.loadSubjects(termId), this.loadTeachers(), this.loadSubjectRequirements(termId),
    ]);
    const classById = new Map(classes.map((item) => [item.id, item]));
    const subjectIds = new Set(subjects.map((item) => item.id));
    const teacherIds = new Set(teachers.map((item) => item.id));
    const ids = new Set<string>();
    for (const item of proposed) {
      if (item.termId !== termId || !classById.has(item.classId) || !subjectIds.has(item.subjectId) ||
        item.teacherId && !teacherIds.has(item.teacherId) || !Number.isInteger(item.lessonCount) || item.lessonCount <= 0 || ids.has(item.id)) {
        throw new Error('任课分配记录、教师、科目或节数无效');
      }
      ids.add(item.id);
    }
    for (const item of proposed.filter((row) => !!row.teacherId)) {
      const schoolClass = classById.get(item.classId)!;
      const specific = requirements.filter((row) => row.classId === item.classId && row.subjectId === item.subjectId);
      const scoped = specific.length ? specific : requirements.filter((row) => row.classId === null && row.gradeId === schoolClass.gradeId && row.subjectId === item.subjectId);
      const demand = scoped.find((row) => row.weekMode === item.weekMode)?.lessonCount ?? 0;
      if (demand <= 0) throw new Error('该班级科目与周模式尚未设置节数需求，不能分配任课');
      const total = [...retained, ...proposed].filter((row) => row.teacherId && row.classId === item.classId && row.subjectId === item.subjectId && row.weekMode === item.weekMode)
        .reduce((sum, row) => sum + row.lessonCount, 0);
      if (total > demand) throw new Error(`任课总节数超过需求（${total}/${demand}），请先调整分配`);
    }
  }

  async replaceTeacherAssignments(params: {
    termId: string;
    classId: string;
    subjectId: string;
    assignments: TeacherAssignment[];
  }): Promise<void> {
    const previous = await this.loadTeacherAssignments(params.termId);
    const currentCell = previous.filter((item) => item.classId === params.classId && item.subjectId === params.subjectId);
    const nextById = new Map(params.assignments.map((item) => [item.id, item]));
    const unchanged = currentCell.length === params.assignments.length && currentCell.every((item) => {
      const next = nextById.get(item.id);
      return next && item.teacherId === next.teacherId && item.weekMode === next.weekMode &&
        item.lessonCount === next.lessonCount && item.sortOrder === next.sortOrder &&
        item.combinedLessonGroupId === next.combinedLessonGroupId;
    });
    if (unchanged) return;
    const clearGroups = new Set(currentCell.map((item) => item.combinedLessonGroupId).filter((id): id is string => !!id));
    await this.validateTeacherAssignmentCapacity(params.termId, params.assignments,
      previous.filter((item) => item.classId !== params.classId || item.subjectId !== params.subjectId));
    await this.captureScheduleBaseline(params.termId);
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const groupId of clearGroups) {
          await tx.execute('UPDATE teacher_assignments SET combined_lesson_group_id = NULL WHERE term_id = ? AND combined_lesson_group_id = ?', [params.termId, groupId]);
        }
        const oldIds = currentCell.map((item) => item.id);
        const nextIds = new Set(params.assignments.map((item) => item.id));
        for (const id of oldIds) if (!nextIds.has(id)) await tx.execute('DELETE FROM teacher_assignments WHERE id = ?', [id]);
        for (const a of params.assignments) {
          await tx.execute(
            `INSERT INTO teacher_assignments (id, term_id, teacher_id, subject_id, class_id, week_mode, lesson_count, sort_order, combined_lesson_group_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET teacher_id = excluded.teacher_id, week_mode = excluded.week_mode,
               lesson_count = excluded.lesson_count, sort_order = excluded.sort_order,
               combined_lesson_group_id = excluded.combined_lesson_group_id`,
            [
              a.id,
              params.termId,
              a.teacherId,
              params.subjectId,
              params.classId,
              a.weekMode,
              a.lessonCount,
              a.sortOrder,
              clearGroups.size ? null : a.combinedLessonGroupId,
            ]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teacherAssignments = store.teacherAssignments.map((item) => item.termId === params.termId && item.combinedLessonGroupId && clearGroups.has(item.combinedLessonGroupId) ? { ...item, combinedLessonGroupId: null } : item);
    store.teacherAssignments = store.teacherAssignments
      .filter(
        (a) =>
          !(
            a.termId === params.termId &&
            a.classId === params.classId &&
            a.subjectId === params.subjectId
          )
      )
      .concat(params.assignments.map((item) => clearGroups.size ? { ...item, combinedLessonGroupId: null } : item));
    this.saveFallback(store);
  }

  async addTeacherAssignments(termId: string, assignments: TeacherAssignment[]): Promise<void> {
    await this.captureScheduleBaseline(termId);
    if (assignments.some((item) => item.termId !== termId || item.lessonCount <= 0 || !item.teacherId)) {
      throw new Error('任课信息不完整');
    }
    const existing = await this.loadTeacherAssignments(termId);
    if (assignments.some((item) => existing.some((row) => row.id === item.id))) throw new Error('任课 ID 重复');
    await this.validateTeacherAssignmentCapacity(termId, assignments, existing);
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const item of assignments) {
          await tx.execute(
            `INSERT INTO teacher_assignments (id, term_id, teacher_id, subject_id, class_id, week_mode, lesson_count, sort_order, combined_lesson_group_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [item.id, termId, item.teacherId, item.subjectId, item.classId, item.weekMode, item.lessonCount, item.sortOrder, item.combinedLessonGroupId]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teacherAssignments.push(...assignments);
    this.saveFallback(store);
  }

  async deleteTeacherAssignments(termId: string, assignmentIds: string[]): Promise<void> {
    await this.captureScheduleBaseline(termId);
    if (!assignmentIds.length) return;
    const deleted = new Set(assignmentIds);
    const groupIds = new Set((await this.loadTeacherAssignments(termId)).filter((item) => deleted.has(item.id)).map((item) => item.combinedLessonGroupId).filter((id): id is string => !!id));
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const groupId of groupIds) await tx.execute('UPDATE teacher_assignments SET combined_lesson_group_id = NULL WHERE term_id = ? AND combined_lesson_group_id = ?', [termId, groupId]);
        for (const id of assignmentIds) {
          await tx.execute('DELETE FROM teacher_assignments WHERE term_id = ? AND id = ?', [termId, id]);
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teacherAssignments = store.teacherAssignments.filter((item) => item.termId !== termId || !deleted.has(item.id)).map((item) => item.termId === termId && item.combinedLessonGroupId && groupIds.has(item.combinedLessonGroupId) ? { ...item, combinedLessonGroupId: null } : item);
    this.saveFallback(store);
  }

  async setCombinedTeacherAssignments(termId: string, assignmentIds: string[], groupId: string | null): Promise<void> {
    await this.captureScheduleBaseline(termId);
    const all = await this.loadTeacherAssignments(termId);
    const ids = new Set(assignmentIds);
    const selected = all.filter((item) => ids.has(item.id));
    if (selected.length !== ids.size) throw new Error('合班任课不存在');
    if (!groupId) {
      const groupIds = new Set(selected.map((item) => item.combinedLessonGroupId).filter((id): id is string => !!id));
      for (const item of all) if (item.combinedLessonGroupId && groupIds.has(item.combinedLessonGroupId)) ids.add(item.id);
    }
    if (groupId) {
      if (selected.length < 2 || new Set(selected.map((item) => item.classId)).size !== selected.length ||
        selected.some((item) => !item.teacherId || !!item.combinedLessonGroupId) ||
        new Set(selected.map((item) => `${item.teacherId}:${item.subjectId}:${item.weekMode}:${item.lessonCount}`)).size !== 1) {
        throw new Error('合班必须选择不同班级、同一教师、科目、周模式和节数的未合班任课');
      }
    }
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        for (const id of ids) {
          await tx.execute('UPDATE teacher_assignments SET combined_lesson_group_id = ? WHERE term_id = ? AND id = ?', [groupId, termId, id]);
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teacherAssignments = store.teacherAssignments.map((item) => item.termId === termId && ids.has(item.id) ? { ...item, combinedLessonGroupId: groupId } : item);
    this.saveFallback(store);
  }

  async loadTeacherPresets(termId: string): Promise<TeacherPreset[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{ id: string; term_id: string; teacher_id: string; scope_type: ScopeType; scope_id: string; stage_id: string; weekday: number; period_type_id: string; lesson_index: number; week_mode: TeacherPreset['weekMode']; value: TeacherPreset['value'] }>(
        'SELECT * FROM teacher_presets WHERE term_id = ?', [termId]
      );
      return rows.map((row) => ({ id: row.id, termId: row.term_id, teacherId: row.teacher_id, scopeType: row.scope_type, scopeId: row.scope_id, stageId: row.stage_id, weekday: row.weekday, periodTypeId: row.period_type_id, lessonIndex: row.lesson_index, weekMode: row.week_mode, value: row.value }));
    }
    return this.loadFallback().teacherPresets.filter((item) => item.termId === termId);
  }

  async replaceTeacherPresets(termId: string, teacherId: string, presets: TeacherPreset[]): Promise<void> {
    await this.captureScheduleBaseline(termId);
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await tx.execute('DELETE FROM teacher_presets WHERE term_id = ? AND teacher_id = ?', [termId, teacherId]);
        for (const item of presets) {
          await tx.execute(`INSERT INTO teacher_presets (id, term_id, teacher_id, scope_type, scope_id, stage_id, weekday, period_type_id, lesson_index, week_mode, value)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, [item.id, termId, teacherId, item.scopeType, item.scopeId, item.stageId, item.weekday, item.periodTypeId, item.lessonIndex, item.weekMode, item.value]);
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teacherPresets = [...store.teacherPresets.filter((item) => item.termId !== termId || item.teacherId !== teacherId), ...presets];
    this.saveFallback(store);
  }

  async loadTeacherGroupPresets(termId: string): Promise<TeacherGroupPreset[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{ id: string; group_id: string; scope_type: ScopeType; scope_id: string; stage_id: string; weekday: number; period_type_id: string; lesson_index: number; week_mode: TeacherGroupPreset['weekMode']; value: TeacherGroupPreset['value'] }>(
        'SELECT p.* FROM teacher_group_presets p JOIN teacher_groups g ON g.id = p.group_id WHERE g.term_id = ?', [termId]
      );
      return rows.map((row) => ({ id: row.id, groupId: row.group_id, scopeType: row.scope_type, scopeId: row.scope_id, stageId: row.stage_id, weekday: row.weekday, periodTypeId: row.period_type_id, lessonIndex: row.lesson_index, weekMode: row.week_mode, value: row.value }));
    }
    const groups = new Set(this.loadFallback().teacherGroups.filter((item) => item.termId === termId).map((item) => item.id));
    return this.loadFallback().teacherGroupPresets.filter((item) => groups.has(item.groupId));
  }

  async replaceTeacherGroupPresets(groupId: string, presets: TeacherGroupPreset[]): Promise<void> {
    await this.captureScheduleBaselines();
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await tx.execute('DELETE FROM teacher_group_presets WHERE group_id = ?', [groupId]);
        for (const item of presets) {
          await tx.execute(`INSERT INTO teacher_group_presets (id, group_id, scope_type, scope_id, stage_id, weekday, period_type_id, lesson_index, week_mode, value)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, [item.id, groupId, item.scopeType, item.scopeId, item.stageId, item.weekday, item.periodTypeId, item.lessonIndex, item.weekMode, item.value]);
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teacherGroupPresets = [...store.teacherGroupPresets.filter((item) => item.groupId !== groupId), ...presets];
    this.saveFallback(store);
  }

  // ==================== 6. 排课课表、带班安排与临时调代课 ====================

  async loadScheduleItems(termId: string, client: DbTransactionClient = this.adapter): Promise<ScheduleItem[]> {
    if (this.useSqlEngine) {
      const rows = await client.select<{
        id: string;
        term_id: string;
        assignment_id: string;
        class_id: string;
        teacher_id: string | null;
        subject_id: string;
        week_mode: 'weekly' | 'odd' | 'even';
        combined_group_id: string | null;
        meeting_id: string | null;
        stage_id: string | null;
        weekday: number | null;
        period_type_id: string | null;
        lesson_index: number | null;
      }>('SELECT * FROM schedule_items WHERE term_id = ?', [termId]);
      return rows.map((r) => ({
        id: r.id,
        termId: r.term_id,
        assignmentId: r.assignment_id,
        classId: r.class_id,
        teacherId: r.teacher_id,
        subjectId: r.subject_id,
        weekMode: r.week_mode,
        combinedGroupId: r.combined_group_id,
        meetingId: r.meeting_id,
        stageId: r.stage_id,
        weekday: r.weekday,
        periodTypeId: r.period_type_id,
        lessonIndex: r.lesson_index,
      }));
    }
    return this.loadFallback().scheduleItems.filter((i) => i.termId === termId);
  }

  async loadSchedulingData(termId: string): Promise<ScheduleData> {
    const [terms, stages, grades, classes, subjects, teachers, assignments, requirements, items,
      subjectPresets, teacherPresets, teacherGroupPresets, teacherGroupMembers, pairings,
      lessonConstraints, rooms, roomSettings, config] = await Promise.all([
      this.loadTerms(), this.loadStages(termId), this.loadGradesForTerm(termId), this.loadClassesForTerm(termId),
      this.loadSubjects(termId), this.loadTeachers(), this.loadTeacherAssignments(termId), this.loadSubjectRequirements(termId),
      this.loadScheduleItems(termId), this.loadSubjectPresets(termId), this.loadTeacherPresets(termId),
      this.loadTeacherGroupPresets(termId), this.loadTeacherGroupMembers(termId), this.loadSubjectPairings(termId),
      this.loadSubjectLessonConstraints(termId), this.loadPublicRooms(), this.loadSubjectRoomSettings(termId),
      this.loadScheduleConfiguration(termId),
    ]);
    const term = terms.find((row) => row.id === termId);
    if (!term) throw new Error('找不到当前学期');
    const [routines, freeSlots, supervision] = await Promise.all([
      Promise.all(stages.map((stage) => this.loadStageRoutine(stage.id))),
      Promise.all(stages.map((stage) => this.loadFreeSlots(stage.id))).then((rows) => rows.flat()),
      this.loadScheduleDuties(term),
    ]);
    return {
      term, stages, grades, classes, subjects, teachers, assignments, requirements, items, routines, freeSlots,
      subjectPresets, teacherPresets, teacherGroupPresets, teacherGroupMembers, pairings, lessonConstraints, rooms,
      roomAssignments: roomSettings.assignments, parallelLimits: roomSettings.limits, ...config, ...supervision,
    };
  }

  private async loadScheduleDuties(source: AcademicTerm) {
    const term = { ...source, firstTeachingWeekStart: source.firstTeachingWeekStart?.slice(0, 10) ?? null };
    const rows = this.useSqlEngine
      ? (await this.adapter.select<{ payload: string; effective_date: string }>(
        'SELECT payload, effective_date FROM supervision_plan_versions WHERE term_id = ? ORDER BY effective_date', [term.id]))
        .map((row) => ({ effectiveDate: row.effective_date, payload: row.payload }))
      : this.loadFallback().supervisionVersions.filter((row) => row.termId === term.id)
        .sort((a, b) => a.effectiveDate.localeCompare(b.effectiveDate));
    const versions = rows.map((row) => ({ effectiveDate: row.effectiveDate.slice(0, 10),
      occurrences: (JSON.parse(row.payload) as { occurrences?: DutyOccurrence[] }).occurrences ?? [] }));
    versions.reverse();
    const occurrencesOn = (date: string) => versions.find((row) => row.effectiveDate <= date)?.occurrences ?? [];
    const today = formatDateYmd(new Date());
    const visibleSupervision = occurrencesOn(today);
    const start = getTeachingWeekStart(term, 1);
    const end = getTeachingWeekEnd(term, term.teachingWeekCount);
    if (!versions.length || !start || !end) return { supervision: visibleSupervision, visibleSupervision };
    const exceptions = new Map((await this.loadCalendarExceptions(term.id)).map((row) => [row.date.slice(0, 10), row]));
    const reservations = new Map<string, DutyOccurrence>();
    const day = parseLocalDate(today);
    if (day < start) day.setTime(start.getTime());
    if (term.firstTeachingWeekStart && formatDateYmd(day) < term.firstTeachingWeekStart.slice(0, 10)) {
      day.setTime(parseLocalDate(term.firstTeachingWeekStart.slice(0, 10)).getTime());
    }
    for (; day <= end; day.setDate(day.getDate() + 1)) {
      const date = formatDateYmd(day);
      const exception = exceptions.get(date);
      if (exception?.kind === 'holiday') continue;
      const templateDate = exception?.makeupForDate?.slice(0, 10) ?? date;
      const weekday = exception?.makeupWeekday ?? getIsoWeekday(templateDate);
      const week = getTeachingWeekOfDate(term, templateDate);
      const mode: WeekMode = term.cycleMode === 'alternating' && week ? (week % 2 === 1 ? 'odd' : 'even') : 'weekly';
      for (const occurrence of occurrencesOn(date).filter((row) => row.position.weekday === weekday)) {
        const key = JSON.stringify([occurrence.post.id, occurrence.teacherId, occurrence.position]);
        const previous = reservations.get(key);
        if (!previous) reservations.set(key, { ...occurrence, weekModes: [mode] });
        else if (!previous.weekModes!.includes(mode)) previous.weekModes!.push(mode);
      }
    }
    return { supervision: [...reservations.values()], visibleSupervision };
  }

  private async loadScheduleConfiguration(termId: string, client: DbTransactionClient = this.adapter) {
    if (!this.useSqlEngine) {
      const store = this.loadFallback();
      return {
        locks: store.scheduleLocks.filter((row) => row.termId === termId),
        conditions: store.scheduleConditions.filter((row) => row.termId === termId),
        preferences: store.schedulePreferences[termId] ?? defaultSchedulePreferences(termId),
      };
    }
    const [locks, rules, settings] = await Promise.all([
      client.select<{ id: string; scope: ScheduleLock['scope']; target_id: string }>(
        'SELECT * FROM schedule_locks WHERE term_id = ?', [termId]),
      client.select<{
        id: string; kind: string; name: string | null; target_kind: string | null; target_id: string | null;
        other_id: string | null; period_type_id: string | null; weekday: number | null;
        min_count: number | null; max_count: number | null; exact_count: number | null;
      }>('SELECT * FROM schedule_conditions WHERE term_id = ? ORDER BY id', [termId]),
      client.select<{
        strength: string; progress_consistency: string; teacher_distribution: string;
        lunch_protection: number; consecutive_policy: string; detect_progress_consistency: number;
      }>('SELECT * FROM schedule_preferences WHERE term_id = ?', [termId]),
    ]);
    const p = settings[0];
    return {
      locks: locks.map((row) => ({ id: row.id, termId, scope: row.scope, targetId: row.target_id })),
      conditions: rules.map((row) => ({ id: row.id, termId, kind: row.kind, name: row.name, targetKind: row.target_kind,
        targetId: row.target_id, otherId: row.other_id, periodTypeId: row.period_type_id, weekday: row.weekday,
        minCount: row.min_count, maxCount: row.max_count, exactCount: row.exact_count })),
      preferences: p ? { termId, strength: p.strength, progressConsistency: p.progress_consistency,
        teacherDistribution: p.teacher_distribution, lunchProtection: !!p.lunch_protection,
        consecutivePolicy: p.consecutive_policy, detectProgressConsistency: !!p.detect_progress_consistency }
        : defaultSchedulePreferences(termId),
    };
  }

  async saveScheduleConfiguration(data: ScheduleData, conditions: ScheduleCondition[], preferences: SchedulePreferences, locks = data.locks) {
    await this.assertScheduleCurrent(data);
    const termId = data.term.id;
    const nextRevision = scheduleReconciliationRevision({ ...data, conditions, preferences });
    if (nextRevision !== scheduleReconciliationRevision(data)) await this.captureScheduleBaseline(termId);
    const baselinePayload = await this.loadScheduleBaselinePayload(termId);
    const restored = baselinePayload && scheduleReconciliationRevision(readStoredSchedule(baselinePayload)) === nextRevision;
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await this.assertScheduleWriteCurrent(tx, data, baselinePayload);
        await tx.execute('DELETE FROM schedule_conditions WHERE term_id = ?', [termId]);
        for (const row of conditions) {
          await tx.execute('INSERT INTO schedule_conditions (id, term_id, kind, name, target_kind, target_id, other_id, period_type_id, weekday, min_count, max_count, exact_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [row.id, termId, row.kind, row.name, row.targetKind, row.targetId, row.otherId, row.periodTypeId, row.weekday, row.minCount, row.maxCount, row.exactCount]);
        }
        await tx.execute('DELETE FROM schedule_locks WHERE term_id = ?', [termId]);
        for (const row of locks) await tx.execute('INSERT INTO schedule_locks (id, term_id, scope, target_id) VALUES (?, ?, ?, ?)',
          [row.id, termId, row.scope, row.targetId]);
        await tx.execute('INSERT OR REPLACE INTO schedule_preferences (term_id, strength, progress_consistency, teacher_distribution, lunch_protection, consecutive_policy, detect_progress_consistency) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [termId, preferences.strength, preferences.progressConsistency, preferences.teacherDistribution, Number(preferences.lunchProtection),
            preferences.consecutivePolicy, Number(preferences.detectProgressConsistency)]);
        if (restored) await tx.execute('DELETE FROM schedule_reconciliation_baselines WHERE term_id = ?', [termId]);
      });
    } else {
      const store = this.loadFallback();
      store.scheduleConditions = store.scheduleConditions.filter((row) => row.termId !== termId).concat(conditions);
      store.scheduleLocks = store.scheduleLocks.filter((row) => row.termId !== termId).concat(locks);
      store.schedulePreferences[termId] = preferences;
      if (restored) delete store.scheduleBaselines[termId];
      this.saveFallback(store);
    }
  }

  async loadPublishedSchedule(termId: string): Promise<ScheduleData | null> {
    const payload = this.useSqlEngine
      ? (await this.adapter.select<{ data_json: string }>('SELECT data_json FROM published_schedules WHERE term_id = ?', [termId]))[0]?.data_json
      : this.loadFallback().publishedSchedules[termId];
    return payload ? readStoredSchedule(payload) : null;
  }

  private async loadScheduleBaselinePayload(termId: string, tx: DbTransactionClient = this.adapter) {
    if (!this.useSqlEngine) return this.loadFallback().scheduleBaselines[termId];
    return (await tx.select<{ snapshot_json: string }>(
      'SELECT snapshot_json FROM schedule_reconciliation_baselines WHERE term_id = ?', [termId]))[0]?.snapshot_json;
  }

  async loadPendingScheduleBaseline(current: ScheduleData) {
    const payload = await this.loadScheduleBaselinePayload(current.term.id);
    if (!payload) return null;
    const baseline = readStoredSchedule(payload);
    return scheduleReconciliationRevision(baseline) === scheduleReconciliationRevision(current) ? null : baseline;
  }

  private async captureScheduleBaseline(termId: string) {
    if (this.useSqlEngine) {
      const placed = await this.adapter.select<{ id: string }>('SELECT id FROM schedule_items WHERE term_id = ? AND weekday IS NOT NULL LIMIT 1', [termId]);
      if (placed.length === 0) return;
    } else if (!this.loadFallback().scheduleItems.some((row) => row.termId === termId && row.weekday !== null)) {
      return;
    }
    if (await this.loadScheduleBaselinePayload(termId)) return;
    const payload = writeStoredSchedule(await this.loadSchedulingData(termId), false);
    if (this.useSqlEngine) {
      await this.adapter.execute('INSERT OR IGNORE INTO schedule_reconciliation_baselines (term_id, snapshot_json, created_at) VALUES (?, ?, ?)',
        [termId, payload, Math.floor(Date.now() / 1000)]);
    } else {
      const store = this.loadFallback();
      store.scheduleBaselines[termId] ??= payload;
      this.saveFallback(store);
    }
  }

  private async captureScheduleBaselines() {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{ term_id: string }>('SELECT DISTINCT term_id FROM schedule_items WHERE weekday IS NOT NULL');
      for (const row of rows) await this.captureScheduleBaseline(row.term_id);
    } else {
      for (const termId of new Set(this.loadFallback().scheduleItems.filter((row) => row.weekday !== null).map((row) => row.termId))) {
        await this.captureScheduleBaseline(termId);
      }
    }
  }

  private async assertScheduleCurrent(expected: ScheduleData) {
    const current = await this.loadSchedulingData(expected.term.id);
    if (scheduleRevision(current) !== scheduleRevision(expected)) throw new Error('草稿或排课资料已变更，请刷新后重新操作');
  }

  private async assertScheduleWriteCurrent(tx: DbTransactionClient, data: ScheduleData, baselinePayload: string | undefined) {
    const termId = data.term.id;
    const [items, config] = await Promise.all([this.loadScheduleItems(termId, tx), this.loadScheduleConfiguration(termId, tx)]);
    if (scheduleRevision({ ...data, items, ...config }) !== scheduleRevision(data) ||
        await this.loadScheduleBaselinePayload(termId, tx) !== baselinePayload) {
      throw new Error('草稿或排课资料已变更，请刷新后重新操作');
    }
  }

  async publishSchedule(data: ScheduleData) {
    await this.assertScheduleCurrent(data);
    const termId = data.term.id;
    const baseline = await this.loadScheduleBaselinePayload(termId);
    if (baseline && scheduleReconciliationRevision(readStoredSchedule(baseline)) !== scheduleReconciliationRevision(data)) throw new Error('请先完成草稿课表协调');
    const items = data.items.filter((row) => row.weekday !== null);
    if (!items.length) throw new Error('请先安排课节');
    const dutyIssue = validateScheduleSupervision(data);
    if (dutyIssue) throw new Error(dutyIssue);
    const published = { ...data, items, locks: [] };
    const payload = writeStoredSchedule(published, true);
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await this.assertScheduleWriteCurrent(tx, data, baseline);
        await tx.execute('INSERT OR REPLACE INTO published_schedules (term_id, data_json) VALUES (?, ?)', [termId, payload]);
      });
    } else {
      const store = this.loadFallback();
      store.publishedSchedules[termId] = payload;
      this.saveFallback(store);
    }
    return published;
  }

  async saveScheduleDraft(data: ScheduleData, items: ScheduleItem[], options: {
    locks?: ScheduleLock[];
    baseline?: ScheduleData;
    report?: ScheduleRunReport;
  } = {}) {
    const termId = data.term.id;
    await this.assertScheduleCurrent(data);
    const baselinePayload = await this.loadScheduleBaselinePayload(termId);
    const pending = baselinePayload ? readStoredSchedule(baselinePayload) : null;
    if (pending && scheduleReconciliationRevision(pending) !== scheduleReconciliationRevision(data) &&
        (!options.baseline || scheduleRevision(options.baseline) !== scheduleRevision(pending))) {
      throw new Error('请先完成草稿课表协调');
    }
    if (options.baseline && !pending) throw new Error('协调资料已更新，请刷新后重新预览');
    if (items.some((row) => row.termId !== termId)) throw new Error('课节不属于当前学期');
    const report = options.report && createStoredRun(data, items, options.report);
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await this.assertScheduleWriteCurrent(tx, data, baselinePayload);
        const existing = new Map(data.items.map((row) => [row.id, row]));
        const next = new Set(items.map((row) => row.id));
        for (const row of data.items) {
          if (!next.has(row.id)) await tx.execute('DELETE FROM schedule_items WHERE term_id = ? AND id = ?', [termId, row.id]);
        }
        for (const row of items) {
          const old = existing.get(row.id);
          if (old && Object.keys(row).every((key) => row[key as keyof ScheduleItem] === old[key as keyof ScheduleItem])) continue;
          await tx.execute(`INSERT INTO schedule_items (id, term_id, assignment_id, class_id, teacher_id, subject_id, week_mode,
            combined_group_id, meeting_id, stage_id, weekday, period_type_id, lesson_index) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET assignment_id = excluded.assignment_id, class_id = excluded.class_id,
            teacher_id = excluded.teacher_id, subject_id = excluded.subject_id, week_mode = excluded.week_mode,
            combined_group_id = excluded.combined_group_id, meeting_id = excluded.meeting_id, stage_id = excluded.stage_id,
            weekday = excluded.weekday, period_type_id = excluded.period_type_id, lesson_index = excluded.lesson_index`,
            [row.id, termId, row.assignmentId, row.classId, row.teacherId, row.subjectId, row.weekMode, row.combinedGroupId,
              row.meetingId, row.stageId, row.weekday, row.periodTypeId, row.lessonIndex]);
        }
        if (options.locks) {
          await tx.execute('DELETE FROM schedule_locks WHERE term_id = ?', [termId]);
          for (const row of options.locks) await tx.execute('INSERT INTO schedule_locks (id, term_id, scope, target_id) VALUES (?, ?, ?, ?)',
            [row.id, termId, row.scope, row.targetId]);
        }
        if (baselinePayload) await tx.execute('DELETE FROM schedule_reconciliation_baselines WHERE term_id = ?', [termId]);
        if (report) {
          await tx.execute('INSERT INTO schedule_run_reports (id, term_id, created_at, solver_version, seed, strength, input_fingerprint, report_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [report.id, termId, Math.floor(Date.now() / 1000), report.config.solverVersion, report.config.seed, report.config.strength,
              report.inputFingerprint, JSON.stringify(report)]);
        }
      });
    } else {
      const store = this.loadFallback();
      store.scheduleItems = store.scheduleItems.filter((row) => row.termId !== termId).concat(items);
      if (options.locks) store.scheduleLocks = store.scheduleLocks.filter((row) => row.termId !== termId).concat(options.locks);
      if (report) store.scheduleReports[termId] = JSON.stringify(report);
      delete store.scheduleBaselines[termId];
      this.saveFallback(store);
    }
  }

  async loadLatestScheduleReport(termId: string): Promise<ScheduleRunReport | null> {
    const payload = this.useSqlEngine
      ? (await this.adapter.select<{ report_json: string }>(
        'SELECT report_json FROM schedule_run_reports WHERE term_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1', [termId]))[0]?.report_json
      : this.loadFallback().scheduleReports[termId];
    return payload ? readStoredRun(payload) : null;
  }

  async loadSupervisionDraft(termId: string): Promise<SupervisionDraft | null> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{ term_id: string; payload: string }>(
        'SELECT * FROM supervision_drafts WHERE term_id = ?',
        [termId]
      );
      return rows[0] ? { termId: rows[0].term_id, payload: rows[0].payload } : null;
    }
    return this.loadFallback().supervisionDrafts[termId] ?? null;
  }

  async saveSupervisionDraft(draft: SupervisionDraft): Promise<void> {
    if (this.useSqlEngine) {
      await this.adapter.execute(
        `INSERT INTO supervision_drafts (term_id, payload)
         VALUES (?, ?)
         ON CONFLICT(term_id) DO UPDATE SET payload = excluded.payload`,
        [draft.termId, draft.payload]
      );
      return;
    }
    const store = this.loadFallback();
    store.supervisionDrafts[draft.termId] = draft;
    this.saveFallback(store);
  }

  async loadSupervisionDraftData(termId: string): Promise<SupervisionDraftModel | null> {
    const raw = await this.loadSupervisionDraft(termId);
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw.payload);
      return {
        termId: parsed.termId ?? termId,
        revision: parsed.revision ?? 0,
        posts: parsed.posts ?? [],
        teacherIds: parsed.teacherIds ?? [],
        teacherPools: parsed.teacherPools ?? [],
        defaultTeacherPoolId: parsed.defaultTeacherPoolId ?? null,
        matchingPreferences: parsed.matchingPreferences ?? defaultSupervisionMatchingPreferences,
        rules: parsed.rules ?? {},
        assignments: parsed.assignments ?? {},
        manualPostIds: parsed.manualPostIds ?? [],
      };
    } catch {
      return null;
    }
  }

  async saveSupervisionDraftData(
    draft: SupervisionDraftModel,
    expectedRevision?: number
  ): Promise<SupervisionDraftModel> {
    const nextRevision = (expectedRevision ?? draft.revision) + 1;
    const nextDraft: SupervisionDraftModel = {
      ...draft,
      revision: nextRevision,
    };
    await this.saveSupervisionDraft({
      termId: draft.termId,
      payload: JSON.stringify(nextDraft),
    });
    return nextDraft;
  }

  async loadSupervisionVersions(termId: string): Promise<SupervisionVersion[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{ payload: string; effective_date: string }>(
        'SELECT payload, effective_date FROM supervision_plan_versions WHERE term_id = ? ORDER BY effective_date ASC',
        [termId]
      );
      return rows.map((r) => {
        try {
          return JSON.parse(r.payload) as SupervisionVersion;
        } catch {
          return {
            termId,
            effectiveDate: r.effective_date,
            draft: {
              termId,
              revision: 0,
              posts: [],
              teacherIds: [],
              teacherPools: [],
              matchingPreferences: defaultSupervisionMatchingPreferences,
              rules: {},
              assignments: {},
              manualPostIds: [],
            },
            occurrences: [],
          };
        }
      });
    }
    const store = this.loadFallback();
    return store.supervisionVersions
      .filter((v) => v.termId === termId)
      .map((v) => {
        try {
          return JSON.parse(v.payload) as SupervisionVersion;
        } catch {
          return {
            termId,
            effectiveDate: v.effectiveDate,
            draft: {
              termId,
              revision: 0,
              posts: [],
              teacherIds: [],
              teacherPools: [],
              matchingPreferences: defaultSupervisionMatchingPreferences,
              rules: {},
              assignments: {},
              manualPostIds: [],
            },
            occurrences: [],
          };
        }
      });
  }

  async previewSupervisionPublish(
    termId: string,
    effectiveDate: string
  ): Promise<SupervisionPreview> {
    const draft = await this.loadSupervisionDraftData(termId);
    if (!draft) {
      throw new Error('请先保存带班草稿');
    }
    const snapshot = await this.loadSchedulingData(termId);
    const versions = await this.loadSupervisionVersions(termId);
    const before = versions
      .filter((v) => v.effectiveDate <= effectiveDate)
      .sort((a, b) => b.effectiveDate.localeCompare(a.effectiveDate))[0] ?? null;

    const validationErrors = postErrors(snapshot, draft);
    const missingPostIds: string[] = [];
    const blockerErrors: string[] = [];
    const allocator = new SupervisionAllocator();
    const matching = new SupervisionMatching(snapshot);

    for (const post of draft.posts) {
      const assignedTeacher = draft.assignments[post.id];
      if (!assignedTeacher) {
        missingPostIds.push(post.id);
      } else {
        const blockers = allocator.teacherBlockers(snapshot, draft, post, assignedTeacher, matching);
        for (const b of blockers) {
          blockerErrors.push(`${post.name}：${b}`);
        }
      }
    }

    const allErrors = [...validationErrors, ...blockerErrors];

    const scheduleChanges: string[] = [];
    if (before) {
      const beforeMap = new Map(before.draft.posts.map((p) => [p.id, before.draft.assignments[p.id]]));
      for (const post of draft.posts) {
        const prevTeacher = beforeMap.get(post.id);
        const curTeacher = draft.assignments[post.id];
        if (!prevTeacher && curTeacher) {
          scheduleChanges.push(`新增岗位「${post.name}」指派教师`);
        } else if (prevTeacher && curTeacher && prevTeacher !== curTeacher) {
          scheduleChanges.push(`岗位「${post.name}」更换带班教师`);
        }
      }
    }

    const replaced = versions.find((v) => v.effectiveDate > effectiveDate);

    return {
      effectiveDate,
      before,
      draft,
      errors: allErrors,
      missingPostIds,
      scheduleChanges,
      replacedFutureDate: replaced ? replaced.effectiveDate : null,
      fingerprint: `${termId}_${effectiveDate}_${Date.now()}`,
      canPublish: allErrors.length === 0 && missingPostIds.length === 0,
    };
  }

  async publishSupervision(termId: string, preview: SupervisionPreview): Promise<void> {
    if (!preview.canPublish) {
      throw new Error('带班方案仍有错误或未分配岗位，无法确认');
    }
    const snapshot = await this.loadSchedulingData(termId);
    const occs = occurrences(snapshot, preview.draft);
    const version: SupervisionVersion = {
      termId,
      effectiveDate: preview.effectiveDate,
      draft: preview.draft,
      occurrences: occs,
    };

    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await tx.execute(
          'DELETE FROM supervision_plan_versions WHERE term_id = ? AND effective_date >= ?',
          [termId, preview.effectiveDate]
        );
        await tx.execute(
          'INSERT INTO supervision_plan_versions (term_id, effective_date, payload) VALUES (?, ?, ?)',
          [termId, preview.effectiveDate, JSON.stringify(version)]
        );
        await tx.execute('DELETE FROM supervision_drafts WHERE term_id = ?', [termId]);
      });
      return;
    }

    const store = this.loadFallback();
    store.supervisionVersions = store.supervisionVersions.filter(
      (v) => !(v.termId === termId && v.effectiveDate >= preview.effectiveDate)
    );
    store.supervisionVersions.push({
      termId,
      effectiveDate: preview.effectiveDate,
      payload: JSON.stringify(version),
    });
    delete store.supervisionDrafts[termId];
    this.saveFallback(store);
  }

  async loadTemporaryAdjustments(termId: string): Promise<TemporaryCourseAdjustment[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
        id: string;
        term_id: string;
        kind: string;
        changes_json: string;
        reason: string;
        created_at: number;
        cancelled_at: number | null;
      }>(
        'SELECT * FROM temporary_course_adjustments WHERE term_id = ? ORDER BY created_at ASC, rowid ASC',
        [termId]
      );
      return rows.map((r) => ({
        id: r.id,
        termId: r.term_id,
        kind: r.kind,
        changesJson: r.changes_json,
        reason: r.reason,
        createdAt: r.created_at,
        cancelledAt: r.cancelled_at,
      }));
    }
    return this.loadFallback()
      .adjustments.filter((a) => a.termId === termId)
      .sort((a, b) => a.createdAt - b.createdAt);
  }

  private computeTemporaryRevision(
    snapshot: ScheduleData,
    exceptions: CalendarException[],
    records: TemporaryAdjustmentRecord[],
    supervisions: SupervisionVersion[] = []
  ): string {
    return JSON.stringify({
      schedule: scheduleRevision(snapshot),
      supervision: supervisions.map((row) => [
        row.effectiveDate,
        row.draft.revision,
        row.occurrences.length,
      ]),
      exceptions: exceptions.map((e) => [
        e.id,
        e.date,
        e.kind,
        e.makeupWeekday,
        e.makeupForDate,
      ]),
      records: records.map((r) => [r.id, r.cancelledAt]),
    });
  }

  async loadTemporaryTimetable(termId: string): Promise<TemporaryTimetableState> {
    const [draft, published, rawExceptions, supervisionVersions, supervisionDraft, rawRows] =
      await Promise.all([
        this.loadSchedulingData(termId),
        this.loadPublishedSchedule(termId),
        this.loadCalendarExceptions(termId),
        this.loadSupervisionVersions(termId),
        this.loadSupervisionDraftData(termId),
        this.loadTemporaryAdjustments(termId),
      ]);
    const exceptions = [...rawExceptions].sort(
      (a, b) => a.date.localeCompare(b.date) || a.id.localeCompare(b.id)
    );
    const baseline = await this.loadPendingScheduleBaseline(draft);
    const snapshot = published ?? draft;
    const hasSupervisionCalendar =
      supervisionVersions.length > 0 ||
      (supervisionDraft?.posts.length ?? 0) > 0;
    const parsedRecords = rawRows.map(parseAdjustmentRow);
    const projected = projectTemporaryTimetable({
      snapshot,
      exceptions,
      records: parsedRecords,
      supervisionVersions,
    });
    return new TemporaryTimetableState({
      snapshot,
      exceptions,
      records: projected.records,
      lessons: projected.lessons,
      supervisions: projected.supervisions,
      supervisionVersions,
      hasSupervisionCalendar,
      revision: this.computeTemporaryRevision(
        snapshot,
        exceptions,
        projected.records,
        supervisionVersions
      ),
      reconciliationPending: baseline !== null,
    });
  }

  async commitTemporarySupervisionSubstitute(params: {
    termId: string;
    request: TemporarySupervisionSubstituteRequest;
    expectedRevision: string;
  }): Promise<void> {
    const state = await this.loadTemporaryTimetable(params.termId);
    if (state.revision !== params.expectedRevision) {
      throw new Error('课表或调课记录已变更，请刷新后重试');
    }
    if (state.reconciliationPending) {
      throw new Error('课表待协调，请先在排课与课表页面完成协调');
    }
    const preview = state.previewSupervisionSubstitute(params.request);
    if (preview.errors.length > 0 || !preview.change) {
      throw new Error(preview.errors.join('；'));
    }
    const row: TemporaryCourseAdjustment = {
      id: createRecordId(),
      termId: params.termId,
      kind: SUPERVISION_SUBSTITUTION_KIND,
      changesJson: JSON.stringify(actualSupervisionChangeToJson(preview.change)),
      reason: (params.request.reason ?? '').trim(),
      createdAt: Math.floor(Date.now() / 1000),
      cancelledAt: null,
    };
    if (this.useSqlEngine) {
      await this.adapter.execute(
        `INSERT INTO temporary_course_adjustments (id, term_id, kind, changes_json, reason, created_at, cancelled_at)
         VALUES (?, ?, ?, ?, ?, ?, NULL)`,
        [row.id, row.termId, row.kind, row.changesJson, row.reason, row.createdAt]
      );
      return;
    }
    const store = this.loadFallback();
    store.adjustments.push(row);
    this.saveFallback(store);
  }

  private async commitTemporaryChanges(params: {
    termId: string;
    kind: 'move' | 'swap' | 'substitute';
    reason?: string;
    expectedRevision: string;
    build: (state: TemporaryTimetableState) => ActualChangePreview;
  }): Promise<void> {
    const state = await this.loadTemporaryTimetable(params.termId);
    if (state.revision !== params.expectedRevision) {
      throw new Error('课表或调课记录已变更，请刷新后重试');
    }
    if (state.reconciliationPending) {
      throw new Error('课表待协调，请先在排课与课表页面完成协调');
    }
    const preview = params.build(state);
    if (preview.errors.length > 0 || preview.changes.length === 0) {
      throw new Error(
        preview.errors.length === 0
          ? '没有可生效的调整课次'
          : preview.errors.join('；')
      );
    }
    const row: TemporaryCourseAdjustment = {
      id: createRecordId(),
      termId: params.termId,
      kind: params.kind,
      changesJson: JSON.stringify(preview.changes.map(actualLessonChangeToJson)),
      reason: (params.reason ?? '').trim(),
      createdAt: Math.floor(Date.now() / 1000),
      cancelledAt: null,
    };
    if (this.useSqlEngine) {
      await this.adapter.execute(
        `INSERT INTO temporary_course_adjustments (id, term_id, kind, changes_json, reason, created_at, cancelled_at)
         VALUES (?, ?, ?, ?, ?, ?, NULL)`,
        [row.id, row.termId, row.kind, row.changesJson, row.reason, row.createdAt]
      );
      return;
    }
    const store = this.loadFallback();
    store.adjustments.push(row);
    this.saveFallback(store);
  }

  async commitTemporaryMove(params: {
    termId: string;
    request: TemporaryMoveRequest;
    expectedRevision: string;
  }): Promise<void> {
    await this.commitTemporaryChanges({
      termId: params.termId,
      kind: 'move',
      reason: params.request.reason,
      expectedRevision: params.expectedRevision,
      build: (state) => state.previewMove(params.request),
    });
  }

  async commitTemporarySubstitute(params: {
    termId: string;
    request: TemporarySubstituteRequest;
    expectedRevision: string;
  }): Promise<void> {
    await this.commitTemporaryChanges({
      termId: params.termId,
      kind: 'substitute',
      reason: params.request.reason,
      expectedRevision: params.expectedRevision,
      build: (state) => state.previewSubstitute(params.request),
    });
  }

  async commitTemporarySwap(params: {
    termId: string;
    request: TemporarySwapRequest;
    expectedRevision: string;
  }): Promise<void> {
    await this.commitTemporaryChanges({
      termId: params.termId,
      kind: 'swap',
      reason: params.request.reason,
      expectedRevision: params.expectedRevision,
      build: (state) => state.previewSwap(params.request),
    });
  }

  async cancelTemporaryAdjustment(params: {
    termId: string;
    adjustmentId: string;
    expectedRevision: string;
  }): Promise<void> {
    const state = await this.loadTemporaryTimetable(params.termId);
    if (state.revision !== params.expectedRevision) {
      throw new Error('课表或调课记录已变更，请刷新后重试');
    }
    const index = state.records.findIndex(
      (r) => r.id === params.adjustmentId && r.cancelledAt == null
    );
    if (index === -1) {
      throw new Error('未找到有效的调课记录');
    }
    const record = state.records[index];
    if (state.reconciliationPending && !record.needsAttention) {
      throw new Error('课表待协调期间仅可取消需处理的调整记录');
    }
    validateTemporaryCancellation(state, record, index);
    const cancelledAt = Math.floor(Date.now() / 1000);
    if (this.useSqlEngine) {
      await this.adapter.execute(
        `UPDATE temporary_course_adjustments
         SET cancelled_at = ?
         WHERE id = ? AND term_id = ? AND cancelled_at IS NULL`,
        [cancelledAt, params.adjustmentId, params.termId]
      );
      return;
    }
    const store = this.loadFallback();
    store.adjustments = store.adjustments.map((item) =>
      item.id === params.adjustmentId && item.termId === params.termId && item.cancelledAt == null
        ? { ...item, cancelledAt }
        : item
    );
    this.saveFallback(store);
  }

  // ==================== 7. 工作台汇总与步骤级联门控校验 ====================

  async loadWorkbenchSummary(termId: string): Promise<WorkbenchSummary> {
    if (this.useSqlEngine) {
      const [rows] = await this.adapter.select<{
        stage_count: number;
        grade_count: number;
        class_count: number;
        subject_count: number;
        teacher_count: number;
        room_count: number;
        period_type_count: number;
        requirement_count: number;
        assigned_teacher_count: number;
        has_schedule: number;
        has_saved_timetable: number;
      }>(
        `SELECT
           (SELECT COUNT(*) FROM school_stages WHERE term_id = ?) AS stage_count,
           (SELECT COUNT(*) FROM grade_groups g JOIN school_stages s ON s.id = g.stage_id WHERE s.term_id = ?) AS grade_count,
           (SELECT COUNT(*) FROM class_groups c JOIN grade_groups g ON g.id = c.grade_id JOIN school_stages s ON s.id = g.stage_id WHERE s.term_id = ?) AS class_count,
           (SELECT COUNT(*) FROM subjects WHERE term_id = ?) AS subject_count,
           (SELECT COUNT(*) FROM teachers) AS teacher_count,
           (SELECT COUNT(*) FROM public_rooms) AS room_count,
           (SELECT COUNT(*) FROM lesson_period_types p JOIN school_stages s ON s.id = p.stage_id WHERE s.term_id = ?) AS period_type_count,
           (SELECT COUNT(*) FROM subject_requirements r JOIN subjects s ON s.id = r.subject_id WHERE s.term_id = ? AND r.lesson_count > 0) AS requirement_count,
           (SELECT COUNT(*) FROM teacher_assignments WHERE term_id = ? AND teacher_id IS NOT NULL) AS assigned_teacher_count,
           EXISTS (SELECT 1 FROM schedule_items WHERE term_id = ? AND weekday IS NOT NULL) AS has_schedule,
           (EXISTS (SELECT 1 FROM published_schedules WHERE term_id = ?) OR
            EXISTS (SELECT 1 FROM schedule_reconciliation_baselines WHERE term_id = ?)) AS has_saved_timetable`,
        [termId, termId, termId, termId, termId, termId, termId, termId, termId, termId]
      );

      const stageCount = rows?.stage_count ?? 0;
      const gradeCount = rows?.grade_count ?? 0;
      const classCount = rows?.class_count ?? 0;
      const subjectCount = rows?.subject_count ?? 0;
      const teacherCount = rows?.teacher_count ?? 0;
      const roomCount = rows?.room_count ?? 0;
      const stagesDone = stageCount > 0 && gradeCount > 0 && classCount > 0;
      const routineDone = stagesDone && (rows?.period_type_count ?? 0) > 0;
      const subjectLessonsReady = routineDone && (rows?.requirement_count ?? 0) > 0;
      const teacherAssignmentsReady =
        subjectLessonsReady && (rows?.assigned_teacher_count ?? 0) > 0;
      const hasSchedule = teacherAssignmentsReady && (rows?.has_schedule ?? 0) > 0;

      return {
        termId,
        stageCount,
        gradeCount,
        classCount,
        subjectCount,
        teacherCount,
        publicRoomCount: roomCount,
        stagesDone,
        routineDone,
        subjectLessonsReady,
        teacherAssignmentsReady,
        hasSchedule,
        hasSavedTimetable: Boolean(rows?.has_schedule || rows?.has_saved_timetable),
      };
    }

    const store = this.loadFallback();
    const stages = store.stages.filter((s) => s.termId === termId);
    const stageIds = new Set(stages.map((s) => s.id));
    const grades = store.grades.filter((g) => stageIds.has(g.stageId));
    const gradeIds = new Set(grades.map((g) => g.id));
    const classes = store.classes.filter((c) => gradeIds.has(c.gradeId));
    const subjects = store.subjects.filter((s) => s.termId === termId);
    const subjectIds = new Set(subjects.map((subject) => subject.id));
    const periodTypes = store.periodTypes.filter((period) => stageIds.has(period.stageId));
    const requirements = store.requirements.filter(
      (requirement) =>
        subjectIds.has(requirement.subjectId) && requirement.lessonCount > 0
    );
    const assignments = store.teacherAssignments.filter(
      (assignment) => assignment.termId === termId && assignment.teacherId != null
    );
    const scheduleItems = store.scheduleItems.filter(
      (item) => item.termId === termId && item.weekday != null
    );

    const stagesDone = stages.length > 0 && grades.length > 0 && classes.length > 0;
    const routineDone = stagesDone && periodTypes.length > 0;
    const subjectLessonsReady = routineDone && requirements.length > 0;
    const teacherAssignmentsReady = subjectLessonsReady && assignments.length > 0;
    const hasSchedule = teacherAssignmentsReady && scheduleItems.length > 0;

    return {
      termId,
      stageCount: stages.length,
      gradeCount: grades.length,
      classCount: classes.length,
      subjectCount: subjects.length,
      teacherCount: store.teachers.length,
      publicRoomCount: store.publicRooms.length,
      stagesDone,
      routineDone,
      subjectLessonsReady,
      teacherAssignmentsReady,
      hasSchedule,
      hasSavedTimetable: Boolean(scheduleItems.length || store.publishedSchedules[termId] || store.scheduleBaselines[termId]),
    };
  }

  async updateCascadeStageFlag(
    termId: string,
    flag: 'routineDone' | 'subjectLessonsReady' | 'teacherAssignmentsReady' | 'hasSchedule',
    value: boolean
  ): Promise<void> {
    const store = this.loadFallback();
    if (flag === 'routineDone') store.routineDoneByTerm[termId] = value;
    if (flag === 'subjectLessonsReady') store.subjectLessonsReadyByTerm[termId] = value;
    if (flag === 'teacherAssignmentsReady') store.teacherAssignmentsReadyByTerm[termId] = value;
    if (flag === 'hasSchedule') store.hasScheduleByTerm[termId] = value;
    this.saveFallback(store);
  }

  // ==================== 8. 双端 .sqlite 二进制数据库导入与导出 ====================

  async exportSqliteBytes(): Promise<Uint8Array | null> {
    return this.adapter.exportSqliteBytes();
  }

  async importSqliteBytes(bytes: Uint8Array): Promise<void> {
    await this.adapter.importSqliteBytes(bytes);
    this.removeFallback();
  }

  async clearAllData(): Promise<void> {
    await this.adapter.clearAllData();
    this.removeFallback();
  }

  private removeFallback(): void {
    try {
      localStorage.removeItem(WEB_FALLBACK_KEY);
    } catch {
      // Storage can be unavailable in restricted browser contexts.
    }
  }

  get isDesktop(): boolean {
    return isTauriDesktop();
  }
}

export const schoolRepository = new SchoolRepository();
