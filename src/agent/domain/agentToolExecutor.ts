/**
 * 课集 (ClassSet) AI Agent 统一工具执行器与 WebMCP / WorkBuddy MCP 桥接层
 * 将 13 个标准 AI Agent 工具直接连接到 scheduling.ts、supervision.ts、actualTimetable.ts 与 schoolRepository.ts
 */

import { createId } from '../../domain/id';
import {
  type AppSection,
  type ClassGroup,
  getNavSectionAvailability,
  type GradeGroup,
  type PresetValue,
  type ScheduleCondition,
  type SchedulePreferences,
  type SchoolStage,
  type ScopeType,
  type Subject,
  type SubjectLessonConstraint,
  type SubjectPairing,
  type SubjectPreset,
  type SubjectRequirement,
  type Teacher,
  type TeacherAssignment,
  type TeacherPreset,
  type WeekMode,
} from '../../domain/models';
import {
  createScheduleContext,
  preflightSchedule,
  previewPlacement,
  type ScheduleSlot,
  slotKey,
  solveSchedule,
} from '../../domain/scheduling';
import {
  defaultSupervisionMatchingPreferences,
  type SchedulePosition,
  type SupervisionDraft,
  type SupervisionKind,
  type SupervisionMatchingPreferences,
  type SupervisionPost,
  type SupervisionTeacherRule,
} from '../../domain/supervision';
import { SupervisionAllocator } from '../../domain/supervisionAllocator';
import { postErrors } from '../../domain/supervisionValidation';
import {
  actualLessonChangeToJson,
  type ActualLessonChange,
  actualSupervisionChangeToJson,
  buildSchedulingProblem,
  getTeacherDisplayName,
} from '../../domain/actualTimetable';
import {
  CLASSSET_AGENT_TOOL_SCHEMAS,
  type ClassSetAgentToolName,
  type ClassSetAgentToolSchema,
} from './agentToolSchemas';
import {
  SchoolRepository,
  schoolRepository,
} from '../../repository/schoolRepository';
import { scheduleRevision } from '../../repository/scheduleStorage';
import { getIsoWeekday } from '../../features/terms/calendarUtils';
import type { SolveRequest } from '../../features/scheduling/schedule.worker';

export interface GetContextAndGatesArgs {
  termId?: string;
  includeDictionaries?: Array<
    | 'stages_and_routines'
    | 'grades_and_classes'
    | 'subjects'
    | 'teachers'
    | 'public_rooms'
    | 'locks'
  >;
}

export interface BatchConfigureClassesAndStagesArgs {
  termId?: string;
  dryRun?: boolean;
  stages?: Array<{
    id?: string;
    name: string;
    sortOrder?: number;
  }>;
  deletedStageIds?: string[];
  grades?: Array<{
    id?: string;
    stageId?: string;
    stageName?: string;
    name: string;
    sortOrder?: number;
    classCount?: number;
  }>;
  deletedGradeIds?: string[];
  classes?: Array<{
    id?: string;
    gradeId?: string;
    gradeName?: string;
    name: string;
    sortOrder?: number;
  }>;
  deletedClassIds?: string[];
}

export interface BatchConfigureSubjectsAndQuotasArgs {
  termId?: string;
  dryRun?: boolean;
  subjects?: Array<{
    id?: string;
    name: string;
    shortName?: string;
    sortOrder?: number;
  }>;
  deletedSubjectIds?: string[];
  requirements?: Array<{
    subjectId?: string;
    subjectName?: string;
    gradeId?: string;
    gradeName?: string;
    classId?: string | null;
    weekMode?: WeekMode;
    lessonCount: number;
  }>;
  lessonConstraints?: Array<{
    subjectId?: string;
    subjectName?: string;
    scopeType: ScopeType;
    scopeId: string;
    stageId: string;
    weekday?: number | null;
    minimumDailyLessons?: number | null;
    maximumDailyLessons?: number | null;
    minimumDailyConsecutivePairs?: number | null;
    maximumDailyConsecutivePairs?: number | null;
    minimumWeeklyConsecutivePairs?: number | null;
    maximumWeeklyConsecutivePairs?: number | null;
  }>;
  pairings?: Array<{
    classId: string;
    oddSubjectId: string;
    evenSubjectId: string;
  }>;
}

export interface BatchConfigureTeachersAndAssignmentsArgs {
  termId?: string;
  dryRun?: boolean;
  teachers?: Array<{
    id?: string;
    name: string;
    shortName?: string;
    displayQualifier?: string;
    sortOrder?: number;
    subjectIds?: string[];
    subjectNames?: string[];
  }>;
  deletedTeacherIds?: string[];
  assignments?: Array<{
    classId?: string;
    gradeName?: string;
    className?: string;
    subjectId?: string;
    subjectName?: string;
    teacherId?: string | null;
    teacherName?: string;
    weekMode?: WeekMode;
    lessonCount?: number;
  }>;
  combinedGroups?: Array<{
    classIds: string[];
    subjectId?: string;
    subjectName?: string;
    weekMode?: WeekMode;
    disband?: boolean;
  }>;
}

export interface ConfigureScheduleRulesArgs {
  termId?: string;
  dryRun?: boolean;
  teacherPresets?: Array<{
    teacherId: string;
    scopeType: ScopeType;
    scopeId: string;
    stageId: string;
    weekday: number;
    periodTypeId: string;
    lessonIndex: number;
    weekMode: WeekMode;
    value: PresetValue;
  }>;
  subjectPresets?: Array<{
    subjectId: string;
    scopeType: ScopeType;
    scopeId: string;
    stageId: string;
    weekday: number;
    periodTypeId: string;
    lessonIndex: number;
    value: PresetValue;
  }>;
  conditions?: Array<{
    id?: string;
    kind:
      | 'dailyLimit'
      | 'periodLimit'
      | 'teacherMutualExclusion'
      | 'subjectMutualExclusion'
      | 'forbiddenAdjacency';
    name?: string | null;
    targetKind: 'teacher' | 'subject';
    targetId: string;
    otherId?: string | null;
    periodTypeId?: string | null;
    weekday?: number | null;
    minCount?: number | null;
    maxCount?: number | null;
    exactCount?: number | null;
  }>;
  replaceAllConditions?: boolean;
  preferences?: Partial<Omit<SchedulePreferences, 'termId'>>;
}

export interface RunAutoScheduleArgs {
  termId?: string;
  classIds?: string[];
  retainPlacements?: boolean;
  allowRearrangement?: boolean;
  seed?: number;
  publish?: boolean;
  dryRun?: boolean;
}

export interface MoveOrSwapLessonArgs {
  termId?: string;
  sourceItemId: string;
  targetSlot: SchedulePosition | null;
  allowSwap?: boolean;
  swapWithItemId?: string;
  dryRun?: boolean;
}

export interface BatchCreateSupervisionPostsArgs {
  termId?: string;
  kind: SupervisionKind;
  name: string;
  stageId: string;
  classIds: string[];
  combineClasses?: boolean;
  groupName?: string;
  location?: string;
  weekdays: number[];
  periodTypeId: string;
  lessonIndices: number[];
  consecutiveLessons?: boolean;
  teacherPoolId?: string | null;
  targetSubjectIds?: string[];
  dryRun?: boolean;
}

export interface AutoAllocateSupervisionArgs {
  termId?: string;
  matchingPreferences?: Partial<SupervisionMatchingPreferences>;
  teacherRules?: Array<{
    teacherId: string;
    maxLessons?: number | null;
    maxDays?: number | null;
    unavailable?: SchedulePosition[];
  }>;
  retainManualAssignments?: boolean;
  dryRun?: boolean;
}

export interface PublishSupervisionVersionArgs {
  termId?: string;
  effectiveDate: string;
  dryRun?: boolean;
}

export interface QueryActualTimetableArgs {
  termId?: string;
  startDate: string;
  endDate: string;
  classId?: string;
  teacherId?: string;
  findCandidatesForSourceKey?: string;
}

export interface ApplyTemporaryAdjustmentArgs {
  termId?: string;
  kind: 'move' | 'substitute' | 'swap' | 'supervision-substitute';
  sourceKey?: string;
  targetDate?: string;
  targetPosition?: SchedulePosition;
  substituteTeacherId?: string;
  substituteSubjectId?: string | null;
  secondKey?: string;
  supervisionPostId?: string;
  supervisionPositions?: SchedulePosition[];
  rangeStart?: string | null;
  rangeEnd?: string | null;
  excludedDates?: string[];
  reason?: string;
  dryRun?: boolean;
}

export interface CancelTemporaryAdjustmentArgs {
  termId?: string;
  dryRun?: boolean;
  recordId: string;
}

export interface ClassSetAgentExecutableTool extends ClassSetAgentToolSchema {
  execute: (args: Record<string, unknown>) => Promise<unknown>;
}

const GATED_SECTIONS: readonly AppSection[] = [
  'classes',
  'routines',
  'subjects',
  'teachers',
  'scheduling',
  'supervision',
  'temporaryAdjustments',
] as const;

function splitConsecutiveIndices(indices: number[]): number[][] {
  const uniqueSorted = [...new Set(indices)].sort((a, b) => a - b);
  if (uniqueSorted.length === 0) return [];
  const groups: number[][] = [];
  let current: number[] = [uniqueSorted[0]];
  for (let i = 1; i < uniqueSorted.length; i++) {
    const idx = uniqueSorted[i];
    if (idx === current[current.length - 1] + 1) {
      current.push(idx);
    } else {
      groups.push(current);
      current = [idx];
    }
  }
  groups.push(current);
  return groups;
}

function enumerateDatesInRange(startDate: string, endDate: string): string[] {
  const start = startDate.slice(0, 10);
  const end = endDate.slice(0, 10);
  if (end < start) return [];
  const dates: string[] = [];
  const cursor = new Date(`${start}T00:00:00`);
  const last = new Date(`${end}T00:00:00`);
  if (Number.isNaN(cursor.getTime()) || Number.isNaN(last.getTime())) return [];
  while (cursor <= last && dates.length < 370) {
    const y = cursor.getFullYear();
    const m = String(cursor.getMonth() + 1).padStart(2, '0');
    const d = String(cursor.getDate()).padStart(2, '0');
    dates.push(`${y}-${m}-${d}`);
    cursor.setDate(cursor.getDate() + 1);
  }
  return dates;
}

function weekModeLabel(mode: WeekMode): string {
  return mode === 'weekly' ? '每周' : mode === 'odd' ? '单周' : '双周';
}

export class ClassSetAgentToolExecutor {
  private readonly repo: SchoolRepository;

  constructor(repo: SchoolRepository = schoolRepository) {
    this.repo = repo;
  }

  /**
   * 解析当前操作的目标学期 ID
   */
  async resolveTermId(requestedTermId?: string): Promise<string> {
    const terms = await this.repo.loadTerms();
    if (requestedTermId && requestedTermId.trim()) {
      const target = terms.find((t) => t.id === requestedTermId.trim());
      if (!target) {
        throw new Error(`找不到指定的学期：${requestedTermId}`);
      }
      return target.id;
    }
    const activeId = await this.repo.loadActiveTermId();
    if (activeId && terms.some((t) => t.id === activeId)) {
      return activeId;
    }
    if (terms.length > 0) {
      return terms[0].id;
    }
    throw new Error('请先创建学期');
  }

  /**
   * 强制校验步骤级联门控规则（getNavSectionAvailability）
   */
  private async assertSectionGate(section: AppSection, termId: string) {
    const summary = await this.repo.loadWorkbenchSummary(termId);
    const gate = getNavSectionAvailability(section, true, summary);
    if (!gate.enabled) {
      throw new Error(gate.reason ?? `当前未满足「${section}」的前置步骤级联要求`);
    }
    return summary;
  }

  /**
   * 统一分发入口：根据 Tool 名称执行对应领域与仓储操作
   */
  async executeTool(
    name: ClassSetAgentToolName,
    rawArgs: Record<string, unknown> = {}
  ): Promise<unknown> {
    switch (name) {
      case 'classset_get_context_and_gates':
        return this.getContextAndGates(rawArgs as unknown as GetContextAndGatesArgs);
      case 'classset_batch_configure_classes_and_stages':
        return this.batchConfigureClassesAndStages(
          rawArgs as unknown as BatchConfigureClassesAndStagesArgs
        );
      case 'classset_batch_configure_subjects_and_quotas':
        return this.batchConfigureSubjectsAndQuotas(
          rawArgs as unknown as BatchConfigureSubjectsAndQuotasArgs
        );
      case 'classset_batch_configure_teachers_and_assignments':
        return this.batchConfigureTeachersAndAssignments(
          rawArgs as unknown as BatchConfigureTeachersAndAssignmentsArgs
        );
      case 'classset_configure_schedule_rules':
        return this.configureScheduleRules(
          rawArgs as unknown as ConfigureScheduleRulesArgs
        );
      case 'classset_run_auto_schedule':
        return this.runAutoSchedule(rawArgs as unknown as RunAutoScheduleArgs);
      case 'classset_move_or_swap_lesson':
        return this.moveOrSwapLesson(rawArgs as unknown as MoveOrSwapLessonArgs);
      case 'classset_batch_create_supervision_posts':
        return this.batchCreateSupervisionPosts(
          rawArgs as unknown as BatchCreateSupervisionPostsArgs
        );
      case 'classset_auto_allocate_supervision':
        return this.autoAllocateSupervision(
          rawArgs as unknown as AutoAllocateSupervisionArgs
        );
      case 'classset_publish_supervision_version':
        return this.publishSupervisionVersion(
          rawArgs as unknown as PublishSupervisionVersionArgs
        );
      case 'classset_query_actual_timetable':
        return this.queryActualTimetable(
          rawArgs as unknown as QueryActualTimetableArgs
        );
      case 'classset_apply_temporary_adjustment':
        return this.applyTemporaryAdjustment(
          rawArgs as unknown as ApplyTemporaryAdjustmentArgs
        );
      case 'classset_cancel_temporary_adjustment':
        return this.cancelTemporaryAdjustment(
          rawArgs as unknown as CancelTemporaryAdjustmentArgs
        );
      default: {
        const exhaustive: never = name;
        throw new Error(`未知的课集 AI Agent 工具：${String(exhaustive)}`);
      }
    }
  }

  /**
   * 0. 读取全局上下文与步骤级联门控状态
   */
  async getContextAndGates(args: GetContextAndGatesArgs = {}) {
    const terms = await this.repo.loadTerms();
    if (terms.length === 0) {
      const gates = Object.fromEntries(
        GATED_SECTIONS.map((sec) => [
          sec,
          getNavSectionAvailability(sec, false, null),
        ])
      );
      return {
        hasTerm: false,
        term: null,
        summary: null,
        gates,
        dictionaries: {},
      };
    }

    const termId = await this.resolveTermId(args.termId);
    const [summary, data] = await Promise.all([
      this.repo.loadWorkbenchSummary(termId),
      args.includeDictionaries?.length ? this.repo.loadSchedulingData(termId) : null,
    ]);

    const gates = Object.fromEntries(
      GATED_SECTIONS.map((sec) => [
        sec,
        getNavSectionAvailability(sec, true, summary),
      ])
    );

    const include = new Set(args.includeDictionaries);

    const dictionaries: Record<string, unknown> = {};
    if (!data) {
      return { hasTerm: true, term: terms.find((term) => term.id === termId), summary, gates, dictionaries };
    }
    if (include.has('stages_and_routines')) {
      dictionaries.stages = data.stages;
      dictionaries.routines = data.routines;
    }
    if (include.has('grades_and_classes')) {
      dictionaries.grades = data.grades;
      dictionaries.classes = data.classes;
    }
    if (include.has('subjects')) {
      dictionaries.subjects = data.subjects;
      dictionaries.requirements = data.requirements;
    }
    if (include.has('teachers')) {
      dictionaries.teachers = data.teachers;
      dictionaries.assignments = data.assignments;
    }
    if (include.has('public_rooms')) {
      dictionaries.publicRooms = data.rooms;
    }
    if (include.has('locks')) {
      dictionaries.locks = data.locks;
    }

    return {
      hasTerm: true,
      term: data.term,
      summary,
      gates,
      dictionaries,
    };
  }

  /**
   * 0.1 批量配置「班级与学段」
   */
  async batchConfigureClassesAndStages(args: BatchConfigureClassesAndStagesArgs) {
    const proposal = await this.prepareConfigureClassesAndStages(args);
    if (!args.dryRun) await proposal.apply(this.repo);
    return proposal.preview;
  }

  async prepareConfigureClassesAndStages(args: BatchConfigureClassesAndStagesArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('classes', termId);

    const [existingStages, existingGrades, existingClasses] = await Promise.all([
      this.repo.loadStages(termId),
      this.repo.loadGradesForTerm(termId),
      this.repo.loadClassesForTerm(termId),
    ]);

    const deletedStageSet = new Set(args.deletedStageIds ?? []);
    const deletedGradeSet = new Set(args.deletedGradeIds ?? []);
    const deletedClassSet = new Set(args.deletedClassIds ?? []);

    for (const stageId of deletedStageSet) {
      if (!existingStages.some((s) => s.id === stageId)) {
        throw new Error(`要删除的学段不属于当前学期：${stageId}`);
      }
    }
    for (const gradeId of deletedGradeSet) {
      if (!existingGrades.some((g) => g.id === gradeId)) {
        throw new Error(`要删除的年级不属于当前学期：${gradeId}`);
      }
    }
    for (const classId of deletedClassSet) {
      if (!existingClasses.some((c) => c.id === classId)) {
        throw new Error(`要删除的班级不属于当前学期：${classId}`);
      }
    }

    const notes: string[] = [];
    const activeStages = existingStages
      .filter((s) => !deletedStageSet.has(s.id))
      .map((s) => ({ ...s }));
    const stagesToSave: SchoolStage[] = [];

    for (const s of existingStages.filter((row) => deletedStageSet.has(row.id))) {
      notes.push(`删除学段「${s.name}」`);
    }

    for (const input of args.stages ?? []) {
      const trimmed = input.name.trim();
      if (!trimmed) throw new Error('学段名称不能为空');
      const existing = input.id
        ? activeStages.find((s) => s.id === input.id)
        : activeStages.find((s) => s.name === trimmed);
      if (input.id && !existing) {
        throw new Error(`学段不属于当前学期：${input.id}`);
      }
      if (existing) {
        const nextStage: SchoolStage = {
          ...existing,
          name: trimmed,
          sortOrder: input.sortOrder ?? existing.sortOrder,
        };
        Object.assign(existing, nextStage);
        stagesToSave.push(nextStage);
        notes.push(`更新学段「${trimmed}」`);
      } else {
        const nextStage: SchoolStage = {
          id: createId(),
          termId,
          name: trimmed,
          sortOrder: input.sortOrder ?? activeStages.length,
        };
        activeStages.push(nextStage);
        stagesToSave.push(nextStage);
        notes.push(`新增学段「${trimmed}」`);
      }
    }

    if (activeStages.length === 0) {
      throw new Error('当前学期至少需要保留一个学段');
    }

    const activeGrades = existingGrades
      .filter((g) => !deletedGradeSet.has(g.id) && !deletedStageSet.has(g.stageId))
      .map((g) => ({ ...g }));
    const gradesToSave: GradeGroup[] = [];

    for (const g of existingGrades.filter((row) => deletedGradeSet.has(row.id))) {
      notes.push(`删除年级「${g.name}」`);
    }

    const resolveStageForGrade = (input: { stageId?: string; stageName?: string }): SchoolStage => {
      if (input.stageId) {
        const found = activeStages.find((s) => s.id === input.stageId);
        if (!found) throw new Error(`找不到学段 ID：${input.stageId}`);
        return found;
      }
      if (input.stageName) {
        const found = activeStages.find((s) => s.name === input.stageName?.trim());
        if (!found) throw new Error(`找不到学段名称：${input.stageName}`);
        return found;
      }
      if (activeStages.length === 1) {
        return activeStages[0];
      }
      throw new Error('当前学期存在多个学段，请通过 stageId 或 stageName 指定年级所属学段');
    };

    const classCountRequests: Array<{ grade: GradeGroup; classCount: number }> = [];

    for (const input of args.grades ?? []) {
      const trimmed = input.name.trim();
      if (!trimmed) throw new Error('年级名称不能为空');
      const existing = input.id
        ? activeGrades.find((g) => g.id === input.id)
        : activeGrades.find(
            (g) =>
              g.name === trimmed &&
              (!input.stageId || g.stageId === input.stageId) &&
              (!input.stageName ||
                activeStages.find((s) => s.id === g.stageId)?.name ===
                  input.stageName.trim())
          );
      if (input.id && !existing) {
        throw new Error(`年级不属于当前学期：${input.id}`);
      }
      if (existing) {
        const targetStage =
          input.stageId || input.stageName
            ? resolveStageForGrade(input)
            : activeStages.find((s) => s.id === existing.stageId)!;
        const nextGrade: GradeGroup = {
          ...existing,
          stageId: targetStage.id,
          name: trimmed,
          sortOrder: input.sortOrder ?? existing.sortOrder,
        };
        Object.assign(existing, nextGrade);
        gradesToSave.push(nextGrade);
        notes.push(`更新年级「${trimmed}」`);
        if (input.classCount !== undefined) {
          classCountRequests.push({ grade: nextGrade, classCount: input.classCount });
        }
      } else {
        const targetStage = resolveStageForGrade(input);
        const nextGrade: GradeGroup = {
          id: createId(),
          stageId: targetStage.id,
          name: trimmed,
          sortOrder: input.sortOrder ?? activeGrades.length,
        };
        activeGrades.push(nextGrade);
        gradesToSave.push(nextGrade);
        notes.push(`新增年级「${targetStage.name} · ${trimmed}」`);
        if (input.classCount !== undefined) {
          classCountRequests.push({ grade: nextGrade, classCount: input.classCount });
        }
      }
    }

    const activeGradeIds = new Set(activeGrades.map((g) => g.id));
    const activeClasses = existingClasses
      .filter((c) => !deletedClassSet.has(c.id) && activeGradeIds.has(c.gradeId))
      .map((c) => ({ ...c }));
    const classesToSaveMap = new Map<string, ClassGroup>();

    for (const c of existingClasses.filter((row) => deletedClassSet.has(row.id))) {
      const gradeName = existingGrades.find((g) => g.id === c.gradeId)?.name ?? '';
      notes.push(`删除班级「${gradeName} ${c.name}」`.trim());
    }

    // 处理 grades.classCount 自动批量生成 1班 ~ N班
    for (const { grade, classCount } of classCountRequests) {
      let createdForGrade = 0;
      for (let i = 1; i <= classCount; i++) {
        const className = `${i}班`;
        const exists = activeClasses.find(
          (c) => c.gradeId === grade.id && c.name === className
        );
        if (!exists) {
          const newClass: ClassGroup = {
            id: createId(),
            gradeId: grade.id,
            name: className,
            sortOrder: i - 1,
          };
          activeClasses.push(newClass);
          classesToSaveMap.set(newClass.id, newClass);
          createdForGrade++;
        }
      }
      if (createdForGrade > 0) {
        notes.push(`${grade.name}：批量创建 ${createdForGrade} 个班级（共 ${classCount} 个班）`);
      }
    }

    const resolveGradeForClass = (input: { gradeId?: string; gradeName?: string }): GradeGroup => {
      if (input.gradeId) {
        const found = activeGrades.find((g) => g.id === input.gradeId);
        if (!found) throw new Error(`找不到年级 ID：${input.gradeId}`);
        return found;
      }
      if (input.gradeName) {
        const found = activeGrades.find((g) => g.name === input.gradeName?.trim());
        if (!found) throw new Error(`找不到年级名称：${input.gradeName}`);
        return found;
      }
      if (activeGrades.length === 1) {
        return activeGrades[0];
      }
      throw new Error('请通过 gradeId 或 gradeName 指定班级所属年级');
    };

    for (const input of args.classes ?? []) {
      const trimmed = input.name.trim();
      if (!trimmed) throw new Error('班级名称不能为空');
      const existing = input.id
        ? activeClasses.find((c) => c.id === input.id)
        : activeClasses.find((c) => {
            if (c.name !== trimmed) return false;
            if (input.gradeId) return c.gradeId === input.gradeId;
            if (input.gradeName) {
              return (
                activeGrades.find((g) => g.id === c.gradeId)?.name ===
                input.gradeName.trim()
              );
            }
            return activeGrades.length === 1;
          });
      if (input.id && !existing) {
        throw new Error(`班级不属于当前学期：${input.id}`);
      }
      if (existing) {
        const targetGrade =
          input.gradeId || input.gradeName
            ? resolveGradeForClass(input)
            : activeGrades.find((g) => g.id === existing.gradeId)!;
        const nextClass: ClassGroup = {
          ...existing,
          gradeId: targetGrade.id,
          name: trimmed,
          sortOrder: input.sortOrder ?? existing.sortOrder,
        };
        Object.assign(existing, nextClass);
        classesToSaveMap.set(nextClass.id, nextClass);
        notes.push(`更新班级「${targetGrade.name} ${trimmed}」`);
      } else {
        const targetGrade = resolveGradeForClass(input);
        const existingInGrade = activeClasses.filter((c) => c.gradeId === targetGrade.id);
        const nextClass: ClassGroup = {
          id: createId(),
          gradeId: targetGrade.id,
          name: trimmed,
          sortOrder: input.sortOrder ?? existingInGrade.length,
        };
        activeClasses.push(nextClass);
        classesToSaveMap.set(nextClass.id, nextClass);
        notes.push(`新增班级「${targetGrade.name} ${trimmed}」`);
      }
    }

    const classesToSave = Array.from(classesToSaveMap.values());

    return {
      termId,
      preview: {
        termId,
        upsertedStageCount: stagesToSave.length,
        upsertedGradeCount: gradesToSave.length,
        upsertedClassCount: classesToSave.length,
        deletedStageCount: deletedStageSet.size,
        deletedGradeCount: deletedGradeSet.size,
        deletedClassCount: deletedClassSet.size,
        stages: activeStages,
        grades: activeGrades,
        classes: activeClasses,
        notes,
      },
      apply: async (repository: SchoolRepository) => {
        if (await new ClassSetAgentToolExecutor(repository).resolveTermId() !== termId) {
          throw new Error('当前学期已切换，请重新生成预览');
        }
        for (const classId of deletedClassSet) {
          await repository.deleteClass(classId);
        }
        for (const gradeId of deletedGradeSet) {
          await repository.deleteGrade(gradeId);
        }
        for (const stageId of deletedStageSet) {
          await repository.deleteStage(stageId);
        }
        for (const stage of stagesToSave) {
          await repository.saveStage(stage);
        }
        if (gradesToSave.length > 0) {
          await repository.saveGrades(gradesToSave);
        }
        if (classesToSave.length > 0) {
          await repository.saveClasses(classesToSave);
        }
      },
    };
  }

  /**
   * 0.2 批量配置「科目节数」
   */
  async batchConfigureSubjectsAndQuotas(args: BatchConfigureSubjectsAndQuotasArgs) {
    const proposal = await this.prepareConfigureSubjectsAndQuotas(args);
    if (!args.dryRun) await proposal.apply(this.repo);
    return proposal.preview;
  }

  async prepareConfigureSubjectsAndQuotas(args: BatchConfigureSubjectsAndQuotasArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('subjects', termId);

    const [
      existingSubjects,
      existingRequirements,
      existingConstraints,
      existingPairings,
      grades,
      classes,
      stages,
    ] = await Promise.all([
      this.repo.loadSubjects(termId),
      this.repo.loadSubjectRequirements(termId),
      this.repo.loadSubjectLessonConstraints(termId),
      this.repo.loadSubjectPairings(termId),
      this.repo.loadGradesForTerm(termId),
      this.repo.loadClassesForTerm(termId),
      this.repo.loadStages(termId),
    ]);

    const deletedIds = [...new Set(args.deletedSubjectIds ?? [])];
    const deletedSet = new Set(deletedIds);
    for (const id of deletedIds) {
      if (!existingSubjects.some((s) => s.id === id)) {
        throw new Error(`要删除的科目不属于当前学期：${id}`);
      }
    }

    const notes: string[] = [];
    for (const sub of existingSubjects.filter((s) => deletedSet.has(s.id))) {
      notes.push(`删除科目「${sub.name}」`);
    }

    const activeSubjects = existingSubjects
      .filter((s) => !deletedSet.has(s.id))
      .map((s) => ({ ...s }));
    const upserts: Subject[] = [];

    for (const input of args.subjects ?? []) {
      const trimmed = input.name.trim();
      if (!trimmed) throw new Error('科目名称不能为空');
      const shortName = (input.shortName?.trim() || trimmed.slice(0, 1)).slice(0, 4);
      const existing = input.id
        ? activeSubjects.find((s) => s.id === input.id)
        : activeSubjects.find((s) => s.name === trimmed);
      if (input.id && !existing) {
        throw new Error(`科目不属于当前学期：${input.id}`);
      }
      if (existing) {
        const nextSub: Subject = {
          ...existing,
          name: trimmed,
          shortName: input.shortName ? shortName : existing.shortName,
          sortOrder: input.sortOrder ?? existing.sortOrder,
        };
        Object.assign(existing, nextSub);
        upserts.push(nextSub);
        notes.push(`更新科目「${trimmed}」（简称：${nextSub.shortName}）`);
      } else {
        const nextSub: Subject = {
          id: createId(),
          termId,
          name: trimmed,
          shortName,
          sortOrder: input.sortOrder ?? activeSubjects.length,
        };
        activeSubjects.push(nextSub);
        upserts.push(nextSub);
        notes.push(`新增科目「${trimmed}」（简称：${shortName}）`);
      }
    }

    const resolveSubject = (input: { subjectId?: string; subjectName?: string }): Subject => {
      if (input.subjectId) {
        const found = activeSubjects.find((s) => s.id === input.subjectId);
        if (!found) throw new Error(`找不到科目 ID：${input.subjectId}`);
        return found;
      }
      if (input.subjectName) {
        const found = activeSubjects.find((s) => s.name === input.subjectName?.trim());
        if (!found) throw new Error(`找不到科目名称：${input.subjectName}`);
        return found;
      }
      throw new Error('请提供 subjectId 或 subjectName');
    };

    const resolveGrade = (input: {
      gradeId?: string;
      gradeName?: string;
      classId?: string | null;
    }): GradeGroup => {
      if (input.gradeId) {
        const found = grades.find((g) => g.id === input.gradeId);
        if (!found) throw new Error(`找不到年级 ID：${input.gradeId}`);
        return found;
      }
      if (input.gradeName) {
        const found = grades.find((g) => g.name === input.gradeName?.trim());
        if (!found) throw new Error(`找不到年级名称：${input.gradeName}`);
        return found;
      }
      if (input.classId) {
        const cls = classes.find((c) => c.id === input.classId);
        if (!cls) throw new Error(`找不到班级 ID：${input.classId}`);
        const found = grades.find((g) => g.id === cls.gradeId);
        if (found) return found;
      }
      if (grades.length === 1) return grades[0];
      throw new Error('请提供 gradeId 或 gradeName');
    };

    const requirementsByGrade: Record<string, SubjectRequirement[]> = {};
    const touchedGrades = new Set<string>();
    const reqListByGrade = new Map<string, Map<string, SubjectRequirement>>();

    for (const grade of grades) {
      const map = new Map<string, SubjectRequirement>();
      for (const req of existingRequirements.filter(
        (r) => r.gradeId === grade.id && !deletedSet.has(r.subjectId)
      )) {
        map.set(`${req.subjectId}:${req.classId ?? ''}:${req.weekMode}`, req);
      }
      reqListByGrade.set(grade.id, map);
    }

    let updatedRequirementCount = 0;
    for (const input of args.requirements ?? []) {
      const subject = resolveSubject(input);
      const grade = resolveGrade(input);
      if (input.classId) {
        const cls = classes.find((c) => c.id === input.classId);
        if (!cls || cls.gradeId !== grade.id) {
          throw new Error(`班级 ${input.classId} 不属于年级 ${grade.name}`);
        }
      }
      const weekMode: WeekMode = input.weekMode ?? 'weekly';
      const gradeMap = reqListByGrade.get(grade.id)!;
      const key = `${subject.id}:${input.classId ?? ''}:${weekMode}`;
      const prev = gradeMap.get(key);
      const scopeLabel = input.classId
        ? `${grade.name} ${classes.find((c) => c.id === input.classId)?.name ?? input.classId}`
        : grade.name;

      if (input.lessonCount <= 0) {
        if (prev) {
          gradeMap.delete(key);
          touchedGrades.add(grade.id);
          updatedRequirementCount++;
          notes.push(`${scopeLabel} · ${subject.name}（${weekModeLabel(weekMode)}）：${prev.lessonCount} 节 → 0 节`);
        }
      } else {
        const nextReq: SubjectRequirement = {
          id: prev?.id ?? createId(),
          subjectId: subject.id,
          gradeId: grade.id,
          classId: input.classId ?? null,
          weekMode,
          lessonCount: input.lessonCount,
        };
        gradeMap.set(key, nextReq);
        touchedGrades.add(grade.id);
        updatedRequirementCount++;
        notes.push(
          `${scopeLabel} · ${subject.name}（${weekModeLabel(weekMode)}）：${prev?.lessonCount ?? 0} 节 → ${input.lessonCount} 节`
        );
      }
    }

    for (const gradeId of touchedGrades) {
      requirementsByGrade[gradeId] = Array.from(
        reqListByGrade.get(gradeId)?.values() ?? []
      );
    }

    const constraintScopes: Array<{
      subjectId: string;
      scopeType: ScopeType;
      scopeId: string;
      stageId: string;
      rows: SubjectLessonConstraint[];
    }> = [];
    let updatedConstraintCount = 0;

    if (args.lessonConstraints && args.lessonConstraints.length > 0) {
      const stageIds = new Set(stages.map((s) => s.id));
      const grouped = new Map<
        string,
        {
          subjectId: string;
          scopeType: ScopeType;
          scopeId: string;
          stageId: string;
          items: NonNullable<BatchConfigureSubjectsAndQuotasArgs['lessonConstraints']>;
        }
      >();

      for (const item of args.lessonConstraints) {
        if (!stageIds.has(item.stageId)) {
          throw new Error(`学段不属于当前学期：${item.stageId}`);
        }
        const subject = resolveSubject(item);
        const sKey = `${subject.id}::${item.scopeType}::${item.scopeId}::${item.stageId}`;
        let group = grouped.get(sKey);
        if (!group) {
          group = {
            subjectId: subject.id,
            scopeType: item.scopeType,
            scopeId: item.scopeId,
            stageId: item.stageId,
            items: [],
          };
          grouped.set(sKey, group);
        }
        group.items.push(item);
      }

      for (const group of grouped.values()) {
        const currentRows = existingConstraints.filter(
          (row) =>
            row.subjectId === group.subjectId &&
            row.scopeType === group.scopeType &&
            row.scopeId === group.scopeId &&
            row.stageId === group.stageId
        );
        const byWeekday = new Map<string, SubjectLessonConstraint>(
          currentRows.map((row) => [String(row.weekday ?? 'all'), row])
        );
        for (const item of group.items) {
          const wKey = String(item.weekday ?? 'all');
          const prev = byWeekday.get(wKey);
          byWeekday.set(wKey, {
            id: prev?.id ?? createId(),
            subjectId: group.subjectId,
            scopeType: group.scopeType,
            scopeId: group.scopeId,
            stageId: group.stageId,
            weekday: item.weekday ?? null,
            minimumDailyLessons:
              item.minimumDailyLessons !== undefined
                ? item.minimumDailyLessons
                : prev?.minimumDailyLessons ?? null,
            maximumDailyLessons:
              item.maximumDailyLessons !== undefined
                ? item.maximumDailyLessons
                : prev?.maximumDailyLessons ?? null,
            minimumDailyConsecutivePairs:
              item.minimumDailyConsecutivePairs !== undefined
                ? item.minimumDailyConsecutivePairs
                : prev?.minimumDailyConsecutivePairs ?? null,
            maximumDailyConsecutivePairs:
              item.maximumDailyConsecutivePairs !== undefined
                ? item.maximumDailyConsecutivePairs
                : prev?.maximumDailyConsecutivePairs ?? null,
            minimumWeeklyConsecutivePairs:
              item.minimumWeeklyConsecutivePairs !== undefined
                ? item.minimumWeeklyConsecutivePairs
                : prev?.minimumWeeklyConsecutivePairs ?? null,
            maximumWeeklyConsecutivePairs:
              item.maximumWeeklyConsecutivePairs !== undefined
                ? item.maximumWeeklyConsecutivePairs
                : prev?.maximumWeeklyConsecutivePairs ?? null,
          });
          updatedConstraintCount++;
        }
        constraintScopes.push({
          subjectId: group.subjectId,
          scopeType: group.scopeType,
          scopeId: group.scopeId,
          stageId: group.stageId,
          rows: Array.from(byWeekday.values()),
        });
      }
      if (updatedConstraintCount > 0) {
        notes.push(`更新科目课节与连堂约束 ${updatedConstraintCount} 项`);
      }
    }

    const pairingsByClass: Record<string, SubjectPairing[]> = {};
    if (args.pairings && args.pairings.length > 0) {
      const classSet = new Set(classes.map((c) => c.id));
      const subjectSet = new Set(activeSubjects.map((s) => s.id));
      const byClass = new Map<string, SubjectPairing[]>();

      for (const p of args.pairings) {
        if (!classSet.has(p.classId)) throw new Error(`班级不属于当前学期：${p.classId}`);
        if (!subjectSet.has(p.oddSubjectId) || !subjectSet.has(p.evenSubjectId)) {
          throw new Error('单双周配对科目不属于当前学期');
        }
        const list =
          byClass.get(p.classId) ??
          existingPairings.filter(
            (row) =>
              row.classId === p.classId &&
              !deletedSet.has(row.oddSubjectId) &&
              !deletedSet.has(row.evenSubjectId)
          );
        list.push({
          id: createId(),
          classId: p.classId,
          oddSubjectId: p.oddSubjectId,
          evenSubjectId: p.evenSubjectId,
        });
        byClass.set(p.classId, list);
      }
      for (const [cid, rows] of byClass.entries()) {
        pairingsByClass[cid] = rows;
      }
      notes.push(`更新单双周科目配对 ${args.pairings.length} 项`);
    }

    return {
      termId,
      preview: {
        termId,
        upsertedSubjectCount: upserts.length,
        deletedSubjectCount: deletedIds.length,
        updatedRequirementCount,
        updatedConstraintCount,
        subjects: activeSubjects,
        notes,
      },
      apply: async (repository: SchoolRepository) => {
        if (await new ClassSetAgentToolExecutor(repository).resolveTermId() !== termId) {
          throw new Error('当前学期已切换，请重新生成预览');
        }
        await repository.saveSubjectChanges({
          upserts,
          deletedIds,
          requirementsByGrade,
          pairingsByClass,
          presetScopes: [],
          constraintScopes,
          roomScopes: [],
        });
      },
    };
  }

  /**
   * 0.3 批量配置「教师任课」
   */
  async batchConfigureTeachersAndAssignments(
    args: BatchConfigureTeachersAndAssignmentsArgs
  ) {
    const proposal = await this.prepareConfigureTeachersAndAssignments(args);
    if (!args.dryRun) await proposal.apply(this.repo);
    return proposal.preview;
  }

  async prepareConfigureTeachersAndAssignments(
    args: BatchConfigureTeachersAndAssignmentsArgs
  ) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('teachers', termId);

    const [
      existingTeachers,
      existingAssignments,
      subjects,
      requirements,
      grades,
      classes,
    ] = await Promise.all([
      this.repo.loadTeachers(),
      this.repo.loadTeacherAssignments(termId),
      this.repo.loadSubjects(termId),
      this.repo.loadSubjectRequirements(termId),
      this.repo.loadGradesForTerm(termId),
      this.repo.loadClassesForTerm(termId),
    ]);

    const deletedTeacherIds = [...new Set(args.deletedTeacherIds ?? [])];
    const deletedTeacherSet = new Set(deletedTeacherIds);
    for (const id of deletedTeacherIds) {
      if (!existingTeachers.some((t) => t.id === id)) {
        throw new Error(`找不到要删除的教师：${id}`);
      }
    }

    const notes: string[] = [];
    for (const t of existingTeachers.filter((row) => deletedTeacherSet.has(row.id))) {
      notes.push(`删除教师「${getTeacherDisplayName(t)}」`);
    }

    const activeTeachers: Teacher[] = existingTeachers
      .filter((t) => !deletedTeacherSet.has(t.id))
      .map((t) => ({ ...t, subjectIds: [...(t.subjectIds ?? [])] }));
    const teachersToSave: Teacher[] = [];

    for (const input of args.teachers ?? []) {
      const trimmed = input.name.trim();
      if (!trimmed) throw new Error('教师姓名不能为空');
      const qualifier = (input.displayQualifier ?? '').trim();
      const shortName = (input.shortName?.trim() || trimmed.slice(0, 1)).slice(0, 4);

      const resolvedSubjectIds = new Set<string>(input.subjectIds ?? []);
      for (const sName of input.subjectNames ?? []) {
        const sub = subjects.find((s) => s.name === sName.trim());
        if (!sub) throw new Error(`找不到科目名称：${sName}`);
        resolvedSubjectIds.add(sub.id);
      }
      for (const sid of resolvedSubjectIds) {
        if (!subjects.some((s) => s.id === sid)) {
          throw new Error(`科目不属于当前学期：${sid}`);
        }
      }

      const existing = input.id
        ? activeTeachers.find((t) => t.id === input.id)
        : activeTeachers.find(
            (t) =>
              t.name === trimmed &&
              (input.displayQualifier === undefined ||
                t.displayQualifier === qualifier)
          );
      if (input.id && !existing) {
        throw new Error(`找不到教师 ID：${input.id}`);
      }

      if (existing) {
        const nextSubjectIds =
          input.subjectIds !== undefined || input.subjectNames !== undefined
            ? [...resolvedSubjectIds]
            : existing.subjectIds ?? [];
        const nextTeacher: Teacher = {
          ...existing,
          name: trimmed,
          shortName: input.shortName ? shortName : existing.shortName,
          displayQualifier:
            input.displayQualifier !== undefined
              ? qualifier
              : existing.displayQualifier,
          sortOrder: input.sortOrder ?? existing.sortOrder,
          subjectIds: nextSubjectIds,
        };
        Object.assign(existing, nextTeacher);
        teachersToSave.push(nextTeacher);
        notes.push(`更新教师「${getTeacherDisplayName(nextTeacher)}」`);
      } else {
        const nextTeacher: Teacher = {
          id: createId(),
          name: trimmed,
          shortName,
          displayQualifier: qualifier,
          sortOrder: input.sortOrder ?? activeTeachers.length,
          subjectIds: [...resolvedSubjectIds],
        };
        activeTeachers.push(nextTeacher);
        teachersToSave.push(nextTeacher);
        notes.push(`新增教师「${getTeacherDisplayName(nextTeacher)}」`);
      }
    }

    const gradeMap = new Map(grades.map((g) => [g.id, g]));
    const resolveClass = (input: {
      classId?: string;
      gradeName?: string;
      className?: string;
    }): ClassGroup => {
      if (input.classId) {
        const found = classes.find((c) => c.id === input.classId);
        if (!found) throw new Error(`班级不属于当前学期：${input.classId}`);
        return found;
      }
      if (input.className) {
        const rawClass = input.className.trim();
        const rawGrade = input.gradeName?.trim();
        const found = classes.find((c) => {
          const gradeName = gradeMap.get(c.gradeId)?.name ?? '';
          if (rawGrade) {
            return gradeName === rawGrade && c.name === rawClass;
          }
          return (
            c.name === rawClass ||
            `${gradeName}${c.name}` === rawClass ||
            `${gradeName} ${c.name}` === rawClass
          );
        });
        if (!found) {
          throw new Error(
            `找不到班级：${[input.gradeName, input.className].filter(Boolean).join(' ')}`
          );
        }
        return found;
      }
      throw new Error('请通过 classId 或 className 指定班级');
    };

    const resolveSubject = (input: {
      subjectId?: string;
      subjectName?: string;
    }): Subject => {
      if (input.subjectId) {
        const found = subjects.find((s) => s.id === input.subjectId);
        if (!found) throw new Error(`科目不属于当前学期：${input.subjectId}`);
        return found;
      }
      if (input.subjectName) {
        const found = subjects.find((s) => s.name === input.subjectName?.trim());
        if (!found) throw new Error(`找不到科目名称：${input.subjectName}`);
        return found;
      }
      throw new Error('请通过 subjectId 或 subjectName 指定科目');
    };

    const resolveTeacher = (input: {
      teacherId?: string | null;
      teacherName?: string;
    }): Teacher | null => {
      if (input.teacherId) {
        const found = activeTeachers.find((t) => t.id === input.teacherId);
        if (!found) throw new Error(`找不到教师 ID：${input.teacherId}`);
        return found;
      }
      if (input.teacherName) {
        const trimmed = input.teacherName.trim();
        const found = activeTeachers.find(
          (t) => t.name === trimmed || getTeacherDisplayName(t) === trimmed
        );
        if (!found) throw new Error(`找不到教师姓名：${input.teacherName}`);
        return found;
      }
      return null;
    };

    const demandForCell = (
      schoolClass: ClassGroup,
      subjectId: string,
      weekMode: WeekMode
    ): number => {
      const specific = requirements.filter(
        (r) => r.classId === schoolClass.id && r.subjectId === subjectId
      );
      const scoped = specific.length
        ? specific
        : requirements.filter(
            (r) =>
              r.classId === null &&
              r.gradeId === schoolClass.gradeId &&
              r.subjectId === subjectId
          );
      return scoped.find((r) => r.weekMode === weekMode)?.lessonCount ?? 0;
    };

    // 按 (classId, subjectId) 组织任课更新
    const workingAssignments = existingAssignments
      .filter((a) => !deletedTeacherSet.has(a.teacherId ?? ''))
      .map((a) => ({ ...a }));
    const cellsToReplace = new Map<
      string,
      { classId: string; subjectId: string; assignments: TeacherAssignment[] }
    >();

    // 若同一请求里对同一个 (classId, subjectId, weekMode) 传入多条教师任课（例如合教分课时），累积处理
    const incomingByCell = new Map<
      string,
      Array<{
        schoolClass: ClassGroup;
        subject: Subject;
        teacher: Teacher | null;
        weekMode: WeekMode;
        lessonCount?: number;
      }>
    >();

    for (const input of args.assignments ?? []) {
      const schoolClass = resolveClass(input);
      const subject = resolveSubject(input);
      const teacher = resolveTeacher(input);
      const weekMode: WeekMode = input.weekMode ?? 'weekly';
      const cellKey = `${schoolClass.id}::${subject.id}`;
      const list = incomingByCell.get(cellKey) ?? [];
      list.push({
        schoolClass,
        subject,
        teacher,
        weekMode,
        lessonCount: input.lessonCount,
      });
      incomingByCell.set(cellKey, list);
    }

    for (const [cellKey, entries] of incomingByCell.entries()) {
      const { schoolClass, subject } = entries[0];
      const gradeName = gradeMap.get(schoolClass.gradeId)?.name ?? '';
      const classLabel = `${gradeName} ${schoolClass.name}`.trim();
      const existingInCell = workingAssignments.filter(
        (a) => a.classId === schoolClass.id && a.subjectId === subject.id
      );

      // 保留未被本次修改涉及的 weekMode 任课行
      const touchedModes = new Set(entries.map((e) => e.weekMode));
      const nextCellRows: TeacherAssignment[] = existingInCell.filter(
        (a) => !touchedModes.has(a.weekMode)
      );

      for (const mode of touchedModes) {
        const modeEntries = entries.filter((e) => e.weekMode === mode);
        const demand = demandForCell(schoolClass, subject.id, mode);
        const activeEntries = modeEntries.filter(
          (e) => e.teacher !== null && (e.lessonCount === undefined || e.lessonCount > 0)
        );

        if (activeEntries.length === 0) {
          notes.push(`${classLabel} · ${subject.name}（${weekModeLabel(mode)}）：清空任课教师`);
          continue;
        }

        if (demand <= 0) {
          throw new Error(
            `${classLabel} · ${subject.name}（${weekModeLabel(mode)}）尚未设置科目节数需求，不能分配任课`
          );
        }

        let total = 0;
        activeEntries.forEach((entry, index) => {
          const count = entry.lessonCount ?? demand;
          total += count;
          const prevRow = existingInCell.find(
            (a) =>
              a.weekMode === mode &&
              (a.teacherId === entry.teacher!.id || activeEntries.length === 1)
          );
          nextCellRows.push({
            id:
              prevRow && activeEntries.length === 1
                ? prevRow.id
                : createId(),
            termId,
            teacherId: entry.teacher!.id,
            subjectId: subject.id,
            classId: schoolClass.id,
            weekMode: mode,
            lessonCount: count,
            sortOrder: index,
            combinedLessonGroupId: null,
          });
          notes.push(
            `${classLabel} · ${subject.name}（${weekModeLabel(mode)} ${count} 节）→ ${getTeacherDisplayName(entry.teacher!)}`
          );
        });

        if (total > demand) {
          throw new Error(
            `${classLabel} · ${subject.name} 任课总节数超过需求（${total}/${demand}）`
          );
        }
      }

      cellsToReplace.set(cellKey, {
        classId: schoolClass.id,
        subjectId: subject.id,
        assignments: nextCellRows,
      });
    }

    // 构造模拟更新后的全量 assignments 用于校验 combinedGroups
    const projectedAssignments: TeacherAssignment[] = [
      ...workingAssignments.filter(
        (a) => !cellsToReplace.has(`${a.classId}::${a.subjectId}`)
      ),
      ...Array.from(cellsToReplace.values()).flatMap((c) => c.assignments),
    ];

    const combinedOperations: Array<{
      assignmentIds: string[];
      groupId: string | null;
    }> = [];

    for (const group of args.combinedGroups ?? []) {
      const subject = resolveSubject(group);
      const weekMode: WeekMode = group.weekMode ?? 'weekly';
      const matched = projectedAssignments.filter(
        (a) =>
          group.classIds.includes(a.classId) &&
          a.subjectId === subject.id &&
          a.weekMode === weekMode &&
          a.teacherId !== null
      );
      if (matched.length !== group.classIds.length) {
        throw new Error(
          `合班设置失败：所选班级在「${subject.name}（${weekModeLabel(weekMode)}）」尚未全部配置唯一任课教师`
        );
      }
      const groupId = group.disband ? null : createId();
      combinedOperations.push({
        assignmentIds: matched.map((a) => a.id),
        groupId,
      });
      const classNames = group.classIds
        .map((cid) => {
          const cls = classes.find((c) => c.id === cid);
          const gName = cls ? gradeMap.get(cls.gradeId)?.name ?? '' : '';
          return cls ? `${gName}${cls.name}` : cid;
        })
        .join('、');
      notes.push(
        `${subject.name}（${classNames}）：${group.disband ? '解除合班上课' : '设为合班上课'}`
      );
    }

    return {
      termId,
      preview: {
        termId,
        upsertedTeacherCount: teachersToSave.length,
        deletedTeacherCount: deletedTeacherIds.length,
        updatedAssignmentCellCount: cellsToReplace.size,
        combinedGroupCount: combinedOperations.length,
        teachers: activeTeachers,
        notes,
      },
      apply: async (repository: SchoolRepository) => {
        if (await new ClassSetAgentToolExecutor(repository).resolveTermId() !== termId) {
          throw new Error('当前学期已切换，请重新生成预览');
        }
        if (teachersToSave.length > 0) {
          await repository.saveTeachers(teachersToSave);
        }
        for (const teacherId of deletedTeacherIds) {
          await repository.deleteTeacher(teacherId);
        }
        for (const cell of cellsToReplace.values()) {
          await repository.replaceTeacherAssignments({
            termId,
            classId: cell.classId,
            subjectId: cell.subjectId,
            assignments: cell.assignments,
          });
        }
        for (const op of combinedOperations) {
          await repository.setCombinedTeacherAssignments(
            termId,
            op.assignmentIds,
            op.groupId
          );
        }
      },
    };
  }

  /**
   * 1. 批量配置排课预设与硬条件
   */
  async configureScheduleRules(args: ConfigureScheduleRulesArgs) {
    const proposal = await this.prepareConfigureScheduleRules(args);
    if (!args.dryRun) await proposal.apply(this.repo);
    return proposal.preview;
  }

  async prepareConfigureScheduleRules(args: ConfigureScheduleRulesArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('scheduling', termId);

    const latestData = await this.repo.loadSchedulingData(termId);
    const operations: Array<(repository: SchoolRepository) => Promise<void>> = [];
    const notes: string[] = [];
    const context = createScheduleContext(latestData);
    for (const preset of [...args.teacherPresets ?? [], ...args.subjectPresets ?? []]) {
      if (!context.slots.has(slotKey(preset))) throw new Error('预设中的节次不属于当前学期');
      const scopes = { school: [termId], stage: latestData.stages.map(({ id }) => id),
        grade: latestData.grades.map(({ id }) => id), class: latestData.classes.map(({ id }) => id) };
      if (!scopes[preset.scopeType].includes(preset.scopeId)) throw new Error('预设范围不属于当前学期');
    }
    let updatedTeacherCount = 0;
    if (args.teacherPresets && args.teacherPresets.length > 0) {
      const existing = latestData.teacherPresets;
      const byTeacher = new Map<
        string,
        NonNullable<ConfigureScheduleRulesArgs['teacherPresets']>
      >();
      for (const item of args.teacherPresets) {
        const list = byTeacher.get(item.teacherId) ?? [];
        list.push(item);
        byTeacher.set(item.teacherId, list);
      }

      for (const [teacherId, incoming] of byTeacher.entries()) {
        const teacher = latestData.teachers.find((row) => row.id === teacherId);
        if (!teacher) throw new Error('教师不属于当前学期');
        const currentForTeacher = existing.filter(
          (row) => row.teacherId === teacherId
        );
        const slotMap = new Map<string, TeacherPreset>();
        const keyOf = (row: {
          scopeType: ScopeType;
          scopeId: string;
          stageId: string;
          weekday: number;
          periodTypeId: string;
          lessonIndex: number;
          weekMode: WeekMode;
        }) =>
          `${row.scopeType}:${row.scopeId}:${row.stageId}:${row.weekday}:${row.periodTypeId}:${row.lessonIndex}:${row.weekMode}`;

        for (const row of currentForTeacher) {
          slotMap.set(keyOf(row), row);
        }
        for (const row of incoming) {
          const k = keyOf(row);
          notes.push(`${getTeacherDisplayName(teacher)} · 周${row.weekday}第 ${row.lessonIndex} 节 · ${slotMap.get(k)?.value ?? 'auto'} → ${row.value}`);
          if (row.value === 'auto') {
            slotMap.delete(k);
          } else {
            const prev = slotMap.get(k);
            slotMap.set(k, {
              id: prev?.id ?? createId(),
              termId,
              teacherId,
              scopeType: row.scopeType,
              scopeId: row.scopeId,
              stageId: row.stageId,
              weekday: row.weekday,
              periodTypeId: row.periodTypeId,
              lessonIndex: row.lessonIndex,
              weekMode: row.weekMode,
              value: row.value,
            });
          }
        }
        operations.push((repository) => repository.replaceTeacherPresets(termId, teacherId, [...slotMap.values()]));
        updatedTeacherCount++;
      }
    }

    let updatedSubjectScopeCount = 0;
    if (args.subjectPresets && args.subjectPresets.length > 0) {
      const existing = latestData.subjectPresets;
      const scopeGroups = new Map<
        string,
        {
          subjectId: string;
          scopeType: ScopeType;
          scopeId: string;
          stageId: string;
          incoming: NonNullable<ConfigureScheduleRulesArgs['subjectPresets']>;
        }
      >();

      for (const row of args.subjectPresets) {
        const sKey = `${row.subjectId}::${row.scopeType}::${row.scopeId}::${row.stageId}`;
        let group = scopeGroups.get(sKey);
        if (!group) {
          group = {
            subjectId: row.subjectId,
            scopeType: row.scopeType,
            scopeId: row.scopeId,
            stageId: row.stageId,
            incoming: [],
          };
          scopeGroups.set(sKey, group);
        }
        group.incoming.push(row);
      }

      const presetScopes: Array<{
        subjectId: string;
        scopeType: ScopeType;
        scopeId: string;
        stageId: string;
        rows: SubjectPreset[];
      }> = [];

      for (const group of scopeGroups.values()) {
        const subject = latestData.subjects.find((row) => row.id === group.subjectId);
        if (!subject) throw new Error('科目不属于当前学期');
        const currentInScope = existing.filter(
          (row) =>
            row.subjectId === group.subjectId &&
            row.scopeType === group.scopeType &&
            row.scopeId === group.scopeId &&
            row.stageId === group.stageId
        );
        const cellMap = new Map<string, SubjectPreset>();
        const cellKey = (row: {
          weekday: number;
          periodTypeId: string;
          lessonIndex: number;
        }) => `${row.weekday}:${row.periodTypeId}:${row.lessonIndex}`;

        for (const row of currentInScope) {
          cellMap.set(cellKey(row), row);
        }
        for (const row of group.incoming) {
          const k = cellKey(row);
          notes.push(`${subject.name} · 周${row.weekday}第 ${row.lessonIndex} 节 · ${cellMap.get(k)?.value ?? 'auto'} → ${row.value}`);
          if (row.value === 'auto') {
            cellMap.delete(k);
          } else {
            const prev = cellMap.get(k);
            cellMap.set(k, {
              id: prev?.id ?? createId(),
              subjectId: group.subjectId,
              scopeType: group.scopeType,
              scopeId: group.scopeId,
              stageId: group.stageId,
              weekday: row.weekday,
              periodTypeId: row.periodTypeId,
              lessonIndex: row.lessonIndex,
              value: row.value,
            });
          }
        }
        presetScopes.push({
          subjectId: group.subjectId,
          scopeType: group.scopeType,
          scopeId: group.scopeId,
          stageId: group.stageId,
          rows: Array.from(cellMap.values()),
        });
        updatedSubjectScopeCount++;
      }

      operations.push((repository) => repository.saveSubjectChanges({
        upserts: [],
        deletedIds: [],
        requirementsByGrade: {},
        pairingsByClass: {},
        presetScopes,
        constraintScopes: [],
        roomScopes: [],
      }));
    }

    let nextConditions = latestData.conditions;
    if (args.conditions !== undefined) {
      const normalizedIncoming: ScheduleCondition[] = args.conditions.map(
        (cond) => ({
          id: cond.id ?? createId(),
          termId,
          kind: cond.kind,
          name: cond.name ?? null,
          targetKind: cond.targetKind,
          targetId: cond.targetId,
          otherId: cond.otherId ?? null,
          periodTypeId: cond.periodTypeId ?? null,
          weekday: cond.weekday ?? null,
          minCount: cond.minCount ?? null,
          maxCount: cond.maxCount ?? null,
          exactCount: cond.exactCount ?? null,
        })
      );

      if (args.replaceAllConditions) {
        nextConditions = normalizedIncoming;
      } else {
        const byId = new Map(
          latestData.conditions.map((row) => [row.id, row])
        );
        for (const cond of normalizedIncoming) {
          byId.set(cond.id, cond);
        }
        nextConditions = Array.from(byId.values());
      }
    }

    const nextPreferences: SchedulePreferences = {
      ...latestData.preferences,
      ...(args.preferences ?? {}),
      termId,
    };

    if (args.conditions !== undefined || args.preferences !== undefined) {
      if (args.conditions !== undefined) notes.push(`硬条件 ${latestData.conditions.length} 项 → ${nextConditions.length} 项`);
      for (const [key, value] of Object.entries(args.preferences ?? {})) {
        const before = latestData.preferences[key as keyof SchedulePreferences];
        if (before !== value) notes.push(`${key} · ${String(before)} → ${String(value)}`);
      }
      operations.push(async (repository) => {
        const current = await repository.loadSchedulingData(termId);
        await repository.saveScheduleConfiguration(current, nextConditions, nextPreferences, current.locks);
      });
    }

    return {
      termId,
      preview: {
        termId, updatedTeacherCount, updatedSubjectScopeCount, conditionCount: nextConditions.length,
        preferences: nextPreferences, notes,
      },
      apply: async (repository: SchoolRepository) => {
        if (scheduleRevision(await repository.loadSchedulingData(termId)) !== scheduleRevision(latestData)) {
          throw new Error('排课规则已变更，请重新生成预览');
        }
        for (const operation of operations) await operation(repository);
      },
    };
  }

  /**
   * 2. 执行自动排课求解器
   */
  async runAutoSchedule(args: RunAutoScheduleArgs = {}) {
    const proposal = await this.prepareAutoSchedule(args);
    let published = false;
    if (!args.dryRun && proposal.apply) {
      await proposal.apply(this.repo);
      if (args.publish && proposal.preview.status === 'complete') {
        const refreshed = await this.repo.loadSchedulingData(proposal.termId);
        await this.repo.publishSchedule(refreshed);
        published = true;
      }
    }
    return { ...proposal.preview, dryRun: Boolean(args.dryRun), published };
  }

  async prepareAutoSchedule(
    args: RunAutoScheduleArgs,
    solve: (request: SolveRequest) => ReturnType<typeof solveSchedule> | Promise<ReturnType<typeof solveSchedule>> =
      ({ data, classIds, keepPlacements, seed, allowRearrangement }) =>
        solveSchedule(data, classIds, keepPlacements, undefined, seed, allowRearrangement),
  ) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('scheduling', termId);

    const data = await this.repo.loadSchedulingData(termId);
    if (await this.repo.loadPendingScheduleBaseline(data)) {
      throw new Error('请先在排课与课表中确认草稿协调');
    }
    const targetClassIds =
      args.classIds && args.classIds.length > 0
        ? args.classIds
        : data.classes.map((c) => c.id);

    if (targetClassIds.some((id) => !data.classes.some((row) => row.id === id))) {
      throw new Error('班级不属于当前学期');
    }
    const preflightIssues = preflightSchedule(data, targetClassIds);
    if (preflightIssues.length > 0) {
      return {
        termId,
        preview: {
          status: 'preflight_failed' as const,
          termId,
          classIds: targetClassIds,
          preflightIssues,
          totalItems: 0,
          placedItems: 0,
          unplacedItems: [],
          blockers: {},
          issues: preflightIssues,
          candidateChecks: 0,
          changes: [],
        },
        apply: null,
      };
    }

    const seed = args.seed ?? 0;
    const solved = await solve({
      data, classIds: targetClassIds, keepPlacements: args.retainPlacements ?? true,
      allowRearrangement: args.allowRearrangement ?? true, seed,
    });
    const previous = new Map(data.items.map((item) => [item.id, item]));
    const placed = solved.items.filter((item) => item.weekday !== null);
    const unplaced = solved.items.filter((item) => item.weekday === null);
    const complete = unplaced.length === 0 && solved.issues.length === 0;
    return {
      termId,
      preview: {
        status: complete ? 'complete' as const : 'partial' as const,
        termId,
        classIds: targetClassIds,
        preflightIssues: [],
        totalItems: solved.items.length,
        placedItems: placed.length,
        unplacedItems: unplaced,
        blockers: solved.blockers,
        issues: solved.issues,
        candidateChecks: solved.candidateChecks,
        changes: solved.items.flatMap((after) => {
          const before = previous.get(after.id) ?? null;
          if (before && before.stageId === after.stageId && before.weekday === after.weekday &&
              before.periodTypeId === after.periodTypeId && before.lessonIndex === after.lessonIndex) return [];
          return [{
            before, after,
            className: data.classes.find((item) => item.id === after.classId)?.name ?? after.classId,
            subjectName: data.subjects.find((item) => item.id === after.subjectId)?.name ?? after.subjectId,
          }];
        }),
      },
      apply: async (repository: SchoolRepository) => {
        if (await new ClassSetAgentToolExecutor(repository).resolveTermId() !== termId) {
          throw new Error('当前学期已切换，请重新生成预览');
        }
        await repository.saveScheduleDraft(data, solved.items, {
          report: {
            classIds: targetClassIds, seed, strength: data.preferences.strength,
            candidateChecks: solved.candidateChecks, blockers: solved.blockers, issues: solved.issues,
          },
        });
      },
    };
  }

  /**
   * 3. 移动、互换单个课节或移入暂放区
   */
  async moveOrSwapLesson(args: MoveOrSwapLessonArgs) {
    const proposal = await this.prepareMoveOrSwapLesson(args);
    const committed = !args.dryRun && proposal.apply !== null;
    if (committed) await proposal.apply?.(this.repo);
    return { ...proposal.preview, dryRun: Boolean(args.dryRun), committed };
  }

  async prepareMoveOrSwapLesson(args: MoveOrSwapLessonArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('scheduling', termId);

    const data = await this.repo.loadSchedulingData(termId);
    if (await this.repo.loadPendingScheduleBaseline(data)) {
      throw new Error('请先在排课与课表中确认草稿协调');
    }
    const context = createScheduleContext(data);
    const source = data.items.find((item) => item.id === args.sourceItemId);
    if (!source) {
      throw new Error(`找不到指定的课节：${args.sourceItemId}`);
    }

    let requestedTarget: ScheduleSlot | null = null;
    if (args.targetSlot !== null) {
      requestedTarget =
        context.slots.get(slotKey(args.targetSlot)) ??
        ({
          ...args.targetSlot,
          startMinute: null,
          endMinute: null,
          order: 0,
          label: '',
          periodName: '',
        } as ScheduleSlot);
    }

    const swapWithItem = args.swapWithItemId
      ? data.items.find((item) => item.id === args.swapWithItemId)
      : undefined;

    const preview = previewPlacement(
      context,
      source,
      requestedTarget,
      args.allowSwap ?? true,
      true,
      swapWithItem
    );

    const items = preview.status !== 'blocked' ? preview.items : undefined;
    return {
      termId,
      preview: {
        termId,
        status: preview.status,
        reason: preview.reason,
        preferenceLoss: Boolean(preview.preferenceLoss),
        changedItems: preview.changed ?? [],
        changes: (preview.changed ?? []).map((after) => ({
          before: data.items.find((item) => item.id === after.id) ?? null,
          after,
          className: data.classes.find((item) => item.id === after.classId)?.name ?? after.classId,
          subjectName: data.subjects.find((item) => item.id === after.subjectId)?.name ?? after.subjectId,
        })),
      },
      apply: items ? async (repository: SchoolRepository) => {
        if (await new ClassSetAgentToolExecutor(repository).resolveTermId() !== termId) {
          throw new Error('当前学期已切换，请重新生成预览');
        }
        await repository.saveScheduleDraft(data, items);
      } : null,
    };
  }

  /**
   * 4. 批量创建带班岗位草稿
   */
  async batchCreateSupervisionPosts(args: BatchCreateSupervisionPostsArgs) {
    const proposal = await this.prepareCreateSupervisionPosts(args);
    const result = args.dryRun ? undefined : await proposal.apply?.(this.repo);
    return { ...proposal.preview, ...result, dryRun: Boolean(args.dryRun) };
  }

  async prepareCreateSupervisionPosts(args: BatchCreateSupervisionPostsArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('supervision', termId);

    const [snapshot, existingDraft] = await Promise.all([
      this.repo.loadSchedulingData(termId),
      this.repo.loadSupervisionDraftData(termId),
    ]);

    const baseDraft: SupervisionDraft = existingDraft ?? {
      termId,
      revision: 0,
      posts: [],
      teacherIds: snapshot.teachers.map((t) => t.id),
      teacherPools: [],
      defaultTeacherPoolId: null,
      matchingPreferences: defaultSupervisionMatchingPreferences,
      rules: {},
      assignments: {},
      manualPostIds: [],
    };

    const classScopes: string[][] = args.combineClasses
      ? [[...args.classIds]]
      : args.classIds.map((cid) => [cid]);

    const sortedIndices = [...new Set(args.lessonIndices)].sort((a, b) => a - b);
    const lessonGroups: number[][] = args.consecutiveLessons
      ? splitConsecutiveIndices(sortedIndices)
      : sortedIndices.map((idx) => [idx]);

    const sortedWeekdays = [...new Set(args.weekdays)].sort((a, b) => a - b);
    const createdPosts: SupervisionPost[] = [];

    for (const scopeClassIds of classScopes) {
      for (const weekday of sortedWeekdays) {
        for (const indices of lessonGroups) {
          createdPosts.push({
            id: createId(),
            kind: args.kind,
            name: args.name.trim(),
            groupName: (args.groupName ?? '').trim(),
            location: (args.location ?? '').trim(),
            stageId: args.stageId,
            weekday,
            periodTypeId: args.periodTypeId,
            lessonIndices: indices,
            classIds: scopeClassIds,
            teacherPoolId: args.teacherPoolId ?? null,
            matchingPreferences: null,
            targetSubjectIds: args.targetSubjectIds ?? [],
          });
        }
      }
    }

    const nextDraft: SupervisionDraft = {
      ...baseDraft,
      posts: [...baseDraft.posts, ...createdPosts],
    };

    const errors = postErrors(snapshot, nextDraft);
    return {
      termId,
      preview: {
        termId, createdPosts, totalPostsInDraft: nextDraft.posts.length, errors,
        saved: false, revision: baseDraft.revision,
      },
      apply: errors.length > 0 ? null : async (repository: SchoolRepository) => {
        await this.assertSupervisionInputCurrent(repository, snapshot, existingDraft);
        const saved = await repository.saveSupervisionDraftData(nextDraft, existingDraft?.revision);
        return { saved: true, revision: saved.revision };
      },
    };
  }

  private async assertSupervisionInputCurrent(
    repository: SchoolRepository,
    snapshot: Awaited<ReturnType<SchoolRepository['loadSchedulingData']>>,
    expectedDraft: Awaited<ReturnType<SchoolRepository['loadSupervisionDraftData']>>,
  ) {
    if (await new ClassSetAgentToolExecutor(repository).resolveTermId() !== snapshot.term.id) {
      throw new Error('当前学期已切换，请重新生成预览');
    }
    const [current, draft] = await Promise.all([
      repository.loadSchedulingData(snapshot.term.id),
      repository.loadSupervisionDraftData(snapshot.term.id),
    ]);
    if (scheduleRevision(current) !== scheduleRevision(snapshot) || draft?.revision !== expectedDraft?.revision) {
      throw new Error('带班资料已变更，请重新生成预览');
    }
  }

  /**
   * 5. 自动分配带班教师
   */
  async autoAllocateSupervision(args: AutoAllocateSupervisionArgs = {}) {
    const proposal = await this.prepareAllocateSupervision(args);
    const result = args.dryRun ? undefined : await proposal.apply?.(this.repo);
    return { ...proposal.preview, ...result, dryRun: Boolean(args.dryRun) };
  }

  async prepareAllocateSupervision(args: AutoAllocateSupervisionArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('supervision', termId);

    const [snapshot, existingDraft] = await Promise.all([
      this.repo.loadSchedulingData(termId),
      this.repo.loadSupervisionDraftData(termId),
    ]);

    if (!existingDraft || existingDraft.posts.length === 0) {
      throw new Error('当前没有待分配的带班岗位草稿，请先创建带班岗位');
    }

    const nextRules: Record<string, SupervisionTeacherRule> = {
      ...existingDraft.rules,
    };
    if (args.teacherRules) {
      for (const rule of args.teacherRules) {
        const prev = nextRules[rule.teacherId] ?? {};
        nextRules[rule.teacherId] = {
          maxLessons:
            rule.maxLessons !== undefined ? rule.maxLessons : prev.maxLessons,
          maxDays: rule.maxDays !== undefined ? rule.maxDays : prev.maxDays,
          unavailable:
            rule.unavailable !== undefined
              ? rule.unavailable
              : prev.unavailable,
        };
      }
    }

    const configuredDraft: SupervisionDraft = {
      ...existingDraft,
      teacherIds:
        existingDraft.teacherIds.length > 0
          ? existingDraft.teacherIds
          : snapshot.teachers.map((t) => t.id),
      matchingPreferences: {
        ...existingDraft.matchingPreferences,
        ...(args.matchingPreferences ?? {}),
      },
      rules: nextRules,
      manualPostIds:
        args.retainManualAssignments === false
          ? []
          : existingDraft.manualPostIds,
    };

    const allocator = new SupervisionAllocator();
    const allocated = allocator.fill(snapshot, configuredDraft);
    const errors = postErrors(snapshot, allocated);

    const assignedPostIds = allocated.posts
      .filter((p) => Boolean(allocated.assignments[p.id]))
      .map((p) => p.id);
    const unassignedPostIds = allocated.posts
      .filter((p) => !allocated.assignments[p.id])
      .map((p) => p.id);

    return {
      termId,
      preview: {
        termId, totalPosts: allocated.posts.length, assignedCount: assignedPostIds.length,
        unassignedPostIds, assignments: allocated.assignments, errors, revision: allocated.revision,
        changes: allocated.posts.flatMap((post) => {
          const before = existingDraft.assignments[post.id];
          const after = allocated.assignments[post.id];
          if (before === after) return [];
          const name = (id?: string) => snapshot.teachers.find((teacher) => teacher.id === id)?.name ?? id ?? '未分配';
          return [{ postId: post.id, postName: post.name, before: name(before), after: name(after) }];
        }),
      },
      apply: errors.length > 0 ? null : async (repository: SchoolRepository) => {
        await this.assertSupervisionInputCurrent(repository, snapshot, existingDraft);
        const saved = await repository.saveSupervisionDraftData(allocated, existingDraft.revision);
        return { revision: saved.revision };
      },
    };
  }

  /**
   * 6. 校验并发布带班方案版本
   */
  async publishSupervisionVersion(args: PublishSupervisionVersionArgs) {
    const proposal = await this.preparePublishSupervision(args);
    const result = args.dryRun ? undefined : await proposal.apply?.(this.repo);
    return { ...proposal.preview, ...result, dryRun: Boolean(args.dryRun) };
  }

  async preparePublishSupervision(args: PublishSupervisionVersionArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('supervision', termId);

    const snapshot = await this.repo.loadSchedulingData(termId);

    const preview = await this.repo.previewSupervisionPublish(
      termId,
      args.effectiveDate
    );
    return {
      termId,
      preview: {
        termId,
        effectiveDate: preview.effectiveDate,
        canPublish: preview.canPublish,
        errors: preview.errors,
        missingPostIds: preview.missingPostIds,
        scheduleChanges: preview.scheduleChanges,
        replacedFutureDate: preview.replacedFutureDate ?? null,
        published: false,
      },
      apply: preview.canPublish ? async (repository: SchoolRepository) => {
        if (await new ClassSetAgentToolExecutor(repository).resolveTermId() !== termId) {
          throw new Error('当前学期已切换，请重新生成预览');
        }
        const current = await repository.previewSupervisionPublish(termId, args.effectiveDate);
        const equivalent = ({ fingerprint: _fingerprint, ...fields }: typeof current) => JSON.stringify(fields);
        if (equivalent(current) !== equivalent(preview) ||
            scheduleRevision(await repository.loadSchedulingData(termId)) !== scheduleRevision(snapshot)) {
          throw new Error('带班发布预览已变更，请重新生成预览');
        }
        await repository.publishSupervision(termId, current);
        return { published: true };
      } : null,
    };
  }

  /**
   * 7. 查询指定日期范围的实际课表与无冲突调代课候选方案
   */
  async queryActualTimetable(args: QueryActualTimetableArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('temporaryAdjustments', termId);

    const state = await this.repo.loadTemporaryTimetable(termId);
    const start = args.startDate.slice(0, 10);
    const end = args.endDate.slice(0, 10);

    const classMap = new Map(
      state.snapshot.classes.map((c) => [c.id, c.name])
    );
    const subjectMap = new Map(
      state.snapshot.subjects.map((s) => [s.id, s.name])
    );
    const teacherMap = new Map(
      state.snapshot.teachers.map((t) => [t.id, getTeacherDisplayName(t)])
    );
    if (args.classId && !classMap.has(args.classId)) throw new Error('班级不属于当前学期');
    if (args.teacherId && !teacherMap.has(args.teacherId)) throw new Error('教师不属于当前学期');

    const filteredLessons = state.lessons
      .filter(
        (l) =>
          l.date >= start &&
          l.date <= end &&
          (!args.classId || l.item.classId === args.classId) &&
          (!args.teacherId || l.item.teacherId === args.teacherId)
      )
      .map((lesson) => ({
        sourceKey: lesson.key,
        date: lesson.date,
        originDate: lesson.originDate,
        itemId: lesson.item.id,
        classId: lesson.item.classId,
        className: classMap.get(lesson.item.classId) ?? lesson.item.classId,
        subjectId: lesson.item.subjectId,
        subjectName:
          subjectMap.get(lesson.item.subjectId) ?? lesson.item.subjectId,
        teacherId: lesson.item.teacherId,
        teacherName:
          teacherMap.get(lesson.item.teacherId) ?? lesson.item.teacherId,
        weekMode: lesson.item.weekMode,
        position: lesson.item.position,
      }));

    const filteredSupervisions = state.supervisions
      .filter(
        (sup) =>
          sup.date >= start &&
          sup.date <= end &&
          (!args.classId || sup.classIds.includes(args.classId)) &&
          (!args.teacherId || sup.teacherId === args.teacherId)
      )
      .map((sup) => ({
        key: sup.key,
        date: sup.date,
        postId: sup.postId,
        postName: sup.post.name,
        teacherId: sup.teacherId,
        teacherName: sup.teacherName,
        classIds: sup.classIds,
        classNames: sup.classNames,
        positions: sup.occurrences.map((o) => o.position),
      }));

    let candidates: {
      sourceKey: string;
      availableSubstituteTeachers: Array<{ teacherId: string; teacherName: string }>;
      availableSwapLessons: Array<{
        secondKey: string;
        date: string;
        subjectName: string;
        teacherName: string;
        position: SchedulePosition | null;
      }>;
      availableMoveSlots: Array<{
        targetDate: string;
        targetPosition: SchedulePosition;
      }>;
    } | null = null;

    if (args.findCandidatesForSourceKey) {
      const source = state.lessons.find(
        (l) => l.key === args.findCandidatesForSourceKey
      );
      if (source) {
        const problem = buildSchedulingProblem(state.snapshot);
        const availableSubstituteTeachers = state.snapshot.teachers
          .filter((t) => {
            const preview = state.previewSubstitute(
              {
                sourceKey: source.key,
                teacherId: t.id,
              },
              problem
            );
            return preview.errors.length === 0 && preview.changes.length > 0;
          })
          .map((t) => ({
            teacherId: t.id,
            teacherName: getTeacherDisplayName(t),
          }));

        const sameClassLessonsInRange = state.lessons.filter(
          (l) =>
            l.key !== source.key &&
            l.item.classId === source.item.classId &&
            l.date >= start &&
            l.date <= end
        );

        const availableSwapLessons = sameClassLessonsInRange
          .filter((other) => {
            const preview = state.previewSwap(
              {
                firstKey: source.key,
                secondKey: other.key,
              },
              problem
            );
            return preview.errors.length === 0 && preview.changes.length > 0;
          })
          .map((other) => ({
            secondKey: other.key,
            date: other.date,
            subjectName:
              subjectMap.get(other.item.subjectId) ?? other.item.subjectId,
            teacherName:
              teacherMap.get(other.item.teacherId) ?? other.item.teacherId,
            position: other.item.position,
          }));

        const classPositions =
          problem.positionsByClass.get(source.item.classId) ?? [];
        const dates = enumerateDatesInRange(start, end);
        const exceptionByDate = new Map(
          state.exceptions.map((ex) => [ex.date.slice(0, 10), ex])
        );
        const availableMoveSlots: Array<{
          targetDate: string;
          targetPosition: SchedulePosition;
        }> = [];

        for (const date of dates) {
          const ex = exceptionByDate.get(date);
          if (ex?.kind === 'holiday') continue;
          const templateWeekday = ex?.makeupWeekday ?? getIsoWeekday(date);
          for (const pos of classPositions) {
            if (pos.weekday !== templateWeekday) continue;
            const preview = state.previewMove(
              {
                sourceKey: source.key,
                targetDate: date,
                targetPosition: pos,
              },
              problem
            );
            if (preview.errors.length === 0 && preview.changes.length > 0) {
              availableMoveSlots.push({
                targetDate: date,
                targetPosition: pos,
              });
            }
          }
        }

        candidates = {
          sourceKey: source.key,
          availableSubstituteTeachers,
          availableSwapLessons,
          availableMoveSlots,
        };
      }
    }

    return {
      termId,
      startDate: start,
      endDate: end,
      reconciliationPending: state.reconciliationPending,
      lessons: filteredLessons,
      supervisions: filteredSupervisions,
      activeAdjustments: state.records
        .filter((r) => r.cancelledAt === null)
        .map((r) => ({
          id: r.id,
          kind: r.kind,
          reason: r.reason,
          createdAt: r.createdAt,
          needsAttention: r.needsAttention,
        })),
      candidates,
    };
  }

  /**
   * 8. 执行或预览临时调代课（移课 / 正课代课 / 换课 / 带班替班）
   */
  async applyTemporaryAdjustment(args: ApplyTemporaryAdjustmentArgs) {
    const proposal = await this.prepareTemporaryAdjustment(args);
    const committed = !args.dryRun && proposal.apply !== null;
    if (committed) await proposal.apply?.(this.repo);
    return { ...proposal.preview, dryRun: Boolean(args.dryRun), committed };
  }

  async prepareTemporaryAdjustment(args: ApplyTemporaryAdjustmentArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('temporaryAdjustments', termId);

    const state = await this.repo.loadTemporaryTimetable(termId);
    const notes = (changes: ActualLessonChange[]) => changes.map(({ before, after }) => {
      const label = (lesson: typeof before) => {
        const teacher = state.snapshot.teachers.find((row) => row.id === lesson.item.teacherId);
        const subject = state.snapshot.subjects.find((row) => row.id === lesson.item.subjectId);
        return `${lesson.date} 第 ${lesson.item.position?.lessonIndex ?? "—"} 节 ${subject?.name ?? ''} ${teacher ? getTeacherDisplayName(teacher) : ''}`;
      };
      return `${label(before)} → ${label(after)}`;
    });
    const excludedSet = args.excludedDates
      ? new Set(args.excludedDates.map((d) => d.slice(0, 10)))
      : undefined;

    if (args.kind === 'supervision-substitute') {
      if (
        !args.targetDate ||
        !args.supervisionPostId ||
        !args.substituteTeacherId
      ) {
        throw new Error(
          '带班替班(supervision-substitute)必须提供 targetDate、supervisionPostId 与 substituteTeacherId'
        );
      }
      const request = {
        date: args.targetDate,
        postId: args.supervisionPostId,
        teacherId: args.substituteTeacherId,
        positions: args.supervisionPositions,
        reason: args.reason,
      };
      const preview = state.previewSupervisionSubstitute(request);
      const canCommit = preview.errors.length === 0 && preview.change !== null;
      return {
        termId,
        preview: {
          termId,
          kind: args.kind,
          canCommit,
          errors: preview.errors,
          skippedDates: [],
          supervisionChange: preview.change
            ? actualSupervisionChangeToJson(preview.change)
            : null,
          changes: [],
          notes: preview.change ? [`${request.date} 带班岗位更换教师`] : [],
        },
        apply: canCommit ? async (repository: SchoolRepository) => {
          await repository.commitTemporarySupervisionSubstitute({ termId, request, expectedRevision: state.revision });
        } : null,
      };
    }

    if (!args.sourceKey) {
      throw new Error(`调代课操作(${args.kind})必须提供 sourceKey`);
    }

    if (args.kind === 'move') {
      if (!args.targetDate || !args.targetPosition) {
        throw new Error('移课(move)必须提供 targetDate 与 targetPosition');
      }
      const request = {
        sourceKey: args.sourceKey,
        targetDate: args.targetDate,
        targetPosition: args.targetPosition,
        reason: args.reason,
        rangeStart: args.rangeStart ?? null,
        rangeEnd: args.rangeEnd ?? null,
        excludedDates: excludedSet,
      };
      const preview = state.previewMove(request);
      const canCommit =
        preview.errors.length === 0 && preview.changes.length > 0;
      return {
        termId,
        preview: {
          termId,
          kind: args.kind,
          canCommit,
          errors: preview.errors,
          skippedDates: preview.skippedDates,
          changes: preview.changes.map(actualLessonChangeToJson),
          supervisionChange: null,
          notes: notes(preview.changes),
        },
        apply: canCommit ? async (repository: SchoolRepository) => {
          await repository.commitTemporaryMove({ termId, request, expectedRevision: state.revision });
        } : null,
      };
    }

    if (args.kind === 'substitute') {
      if (!args.substituteTeacherId) {
        throw new Error('代课(substitute)必须提供 substituteTeacherId');
      }
      const request = {
        sourceKey: args.sourceKey,
        teacherId: args.substituteTeacherId,
        subjectId: args.substituteSubjectId ?? null,
        reason: args.reason,
        rangeStart: args.rangeStart ?? null,
        rangeEnd: args.rangeEnd ?? null,
        excludedDates: excludedSet,
      };
      const preview = state.previewSubstitute(request);
      const canCommit =
        preview.errors.length === 0 && preview.changes.length > 0;
      return {
        termId,
        preview: {
          termId,
          kind: args.kind,
          canCommit,
          errors: preview.errors,
          skippedDates: preview.skippedDates,
          changes: preview.changes.map(actualLessonChangeToJson),
          supervisionChange: null,
          notes: notes(preview.changes),
        },
        apply: canCommit ? async (repository: SchoolRepository) => {
          await repository.commitTemporarySubstitute({ termId, request, expectedRevision: state.revision });
        } : null,
      };
    }

    if (args.kind === 'swap') {
      if (!args.secondKey) {
        throw new Error('换课(swap)必须提供 secondKey');
      }
      const request = {
        firstKey: args.sourceKey,
        secondKey: args.secondKey,
        reason: args.reason,
        rangeStart: args.rangeStart ?? null,
        rangeEnd: args.rangeEnd ?? null,
        excludedDates: excludedSet,
      };
      const preview = state.previewSwap(request);
      const canCommit =
        preview.errors.length === 0 && preview.changes.length > 0;
      return {
        termId,
        preview: {
          termId,
          kind: args.kind,
          canCommit,
          errors: preview.errors,
          skippedDates: preview.skippedDates,
          changes: preview.changes.map(actualLessonChangeToJson),
          supervisionChange: null,
          notes: notes(preview.changes),
        },
        apply: canCommit ? async (repository: SchoolRepository) => {
          await repository.commitTemporarySwap({ termId, request, expectedRevision: state.revision });
        } : null,
      };
    }

    throw new Error(`不支持的调代课类型：${String(args.kind)}`);
  }

  /**
   * 9. 撤销一条已生效的调代课或带班替班记录
   */
  async cancelTemporaryAdjustment(args: CancelTemporaryAdjustmentArgs) {
    const proposal = await this.prepareCancelTemporaryAdjustment(args);
    if (!args.dryRun) await proposal.apply(this.repo);
    return { ...proposal.preview, cancelled: !args.dryRun };
  }

  async prepareCancelTemporaryAdjustment(args: CancelTemporaryAdjustmentArgs) {
    const termId = await this.resolveTermId(args.termId);
    await this.assertSectionGate('temporaryAdjustments', termId);
    const state = await this.repo.loadTemporaryTimetable(termId);
    const record = state.records.find((item) => item.id === args.recordId && item.cancelledAt === null);
    if (!record) throw new Error('当前学期没有这条有效调代课记录');
    return {
      termId,
      preview: {
        termId,
        recordId: record.id,
        reason: record.reason,
        kind: record.kind,
        notes: record.changes.map(({ before, after }) => `${after.date} 第 ${after.item.position?.lessonIndex ?? "—"} 节 → ${before.date} 第 ${before.item.position?.lessonIndex ?? "—"} 节`),
        supervisionChange: record.supervisionChange ? actualSupervisionChangeToJson({
          before: record.supervisionChange.after, after: record.supervisionChange.before,
        }) : null,
      },
      apply: async (repository: SchoolRepository) => {
        await repository.cancelTemporaryAdjustment({ termId, adjustmentId: args.recordId, expectedRevision: state.revision });
      },
    };
  }

  /**
   * 生成包含 Schema 与 execute 回调的完整可执行工具列表（供 MCP Server 或 WebMCP 直接消费）
   */
  createExecutableTools(): ClassSetAgentExecutableTool[] {
    return CLASSSET_AGENT_TOOL_SCHEMAS.map((schema) => ({
      ...schema,
      execute: (args: Record<string, unknown>) =>
        this.executeTool(schema.name, args),
    }));
  }
}

export interface WebMcpModelContext {
  registerTool?: (tool: {
    name: string;
    description: string;
    inputSchema: Record<string, unknown>;
    execute: (args: Record<string, unknown>) => Promise<unknown>;
  }) => void;
}

/**
 * 将课集 13 个核心 AI Agent 工具一键注册到 Chrome WebMCP (document.modelContext / navigator.modelContext)
 */
export function registerClassSetToolsToWebMCP(
  executor: ClassSetAgentToolExecutor = new ClassSetAgentToolExecutor(),
  targetContext?: WebMcpModelContext | null
): { registered: boolean; toolCount: number } {
  const resolvedContext: WebMcpModelContext | undefined =
    targetContext ??
    (typeof document !== 'undefined'
      ? (document as unknown as { modelContext?: WebMcpModelContext })
          .modelContext
      : undefined) ??
    (typeof navigator !== 'undefined'
      ? (navigator as unknown as { modelContext?: WebMcpModelContext })
          .modelContext
      : undefined);

  if (!resolvedContext?.registerTool) {
    return { registered: false, toolCount: 0 };
  }

  const tools = executor.createExecutableTools();
  for (const tool of tools) {
    resolvedContext.registerTool({
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema as unknown as Record<string, unknown>,
      execute: tool.execute,
    });
  }

  return { registered: true, toolCount: tools.length };
}

export const defaultAgentToolExecutor = new ClassSetAgentToolExecutor();
