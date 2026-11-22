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
  TeacherPreset,
  TemporaryCourseAdjustment,
  WorkbenchSummary,
} from '../domain/models';

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
  publicRooms: PublicRoom[];
  scheduleItems: ScheduleItem[];
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
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `row_${Date.now()}_${Math.random().toString(36).slice(2)}`;
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
    publicRooms: [],
    scheduleItems: [],
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
          'INSERT INTO app_settings (id, school_name, active_term_id) VALUES (1, ?, NULL)',
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
    store.publicRooms = rooms;
    this.saveFallback(store);
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
      return rows.map((r) => ({
        id: r.id,
        name: r.name,
        shortName: r.short_name,
        displayQualifier: r.display_qualifier,
        sortOrder: r.sort_order,
      }));
    }
    return this.loadFallback().teachers;
  }

  async saveTeachers(teachers: Teacher[]): Promise<void> {
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
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teachers = teachers;
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

  async replaceTeacherAssignments(params: {
    termId: string;
    classId: string;
    subjectId: string;
    assignments: TeacherAssignment[];
  }): Promise<void> {
    if (this.useSqlEngine) {
      await this.adapter.transaction(async (tx) => {
        await tx.execute(
          'DELETE FROM teacher_assignments WHERE term_id = ? AND class_id = ? AND subject_id = ?',
          [params.termId, params.classId, params.subjectId]
        );
        for (const a of params.assignments) {
          await tx.execute(
            `INSERT INTO teacher_assignments (id, term_id, teacher_id, subject_id, class_id, week_mode, lesson_count, sort_order, combined_lesson_group_id)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              a.id,
              params.termId,
              a.teacherId,
              params.subjectId,
              params.classId,
              a.weekMode,
              a.lessonCount,
              a.sortOrder,
              a.combinedLessonGroupId,
            ]
          );
        }
      });
      return;
    }
    const store = this.loadFallback();
    store.teacherAssignments = store.teacherAssignments
      .filter(
        (a) =>
          !(
            a.termId === params.termId &&
            a.classId === params.classId &&
            a.subjectId === params.subjectId
          )
      )
      .concat(params.assignments);
    this.saveFallback(store);
  }

  // ==================== 6. 排课课表、带班安排与临时调代课 ====================

  async loadScheduleItems(termId: string): Promise<ScheduleItem[]> {
    if (this.useSqlEngine) {
      const rows = await this.adapter.select<{
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
        'SELECT * FROM temporary_course_adjustments WHERE term_id = ? ORDER BY created_at DESC',
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
    return this.loadFallback().adjustments.filter((a) => a.termId === termId);
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
           EXISTS (SELECT 1 FROM schedule_items WHERE term_id = ? AND weekday IS NOT NULL) AS has_schedule`,
        [termId, termId, termId, termId, termId, termId, termId, termId]
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
  }

  get isDesktop(): boolean {
    return isTauriDesktop();
  }
}

export const schoolRepository = new SchoolRepository();
