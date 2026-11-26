import { describe, it, expect, vi, afterEach } from 'vitest';
import { createId } from '@/domain/id';
import { getNavSectionAvailability, type WorkbenchSummary } from '@/domain/models';
import {
  completeRoutinePeriodTypes,
  formatRoutineTeachingDays,
  formatRoutinePeriods,
  formatRoutineSummary,
  getPeriodAccentColor,
} from '@/domain/routineUtils';
import {
  getCompletedPreparationCount,
  getCompletedPreparationSteps,
  getCurrentPreparationStep,
  getPreparationStepStatus,
  getScheduleEntryCopy,
  getStepCopyFor,
  getWorkbenchProgress,
  PREPARATION_STEP_TOTAL,
  PREPARATION_STEPS,
} from '@/features/workbench/workbenchModel';
import {
  parseNumericDraft,
  normalizeNumericValue,
  numericInputDraftReducer,
} from '@/lib/numberInput';
import { cn } from '@/lib/utils';
import type { StageRoutine } from '@/domain/models';

const baseSummary = (overrides: Partial<WorkbenchSummary> = {}): WorkbenchSummary => ({
  termId: 'term-1',
  stageCount: 1,
  gradeCount: 1,
  classCount: 1,
  subjectCount: 1,
  teacherCount: 1,
  publicRoomCount: 0,
  stagesDone: true,
  routineDone: true,
  subjectLessonsReady: true,
  teacherAssignmentsReady: true,
  hasSchedule: true,
  hasSavedTimetable: false,
  ...overrides,
});

describe('domain/id.ts - createId', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('生成符合 UUID v4 格式的唯一 ID', () => {
    const id1 = createId();
    const id2 = createId();
    expect(id1).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
    expect(id1).not.toBe(id2);
  });

  it('当 crypto.randomUUID 不可用时回退到 getRandomValues', () => {
    vi.stubGlobal('crypto', {
      getRandomValues: (arr: Uint8Array) => {
        for (let i = 0; i < arr.length; i++) arr[i] = i + 1;
        return arr;
      },
    });
    const id = createId();
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  it('当 crypto 完全不可用时仍能生成合法 UUID v4', () => {
    vi.stubGlobal('crypto', undefined);
    const id = createId();
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });
});

describe('domain/models.ts - getNavSectionAvailability', () => {
  it('无学期时仅允许基础入口，其余模块禁用并提示先创建学期', () => {
    expect(getNavSectionAvailability('terms', false, null)).toEqual({ enabled: true, reason: null });
    expect(getNavSectionAvailability('classes', false, null)).toEqual({
      enabled: false,
      reason: '请先创建学期',
    });
    expect(getNavSectionAvailability('scheduling', false, null)).toEqual({
      enabled: false,
      reason: '请先创建学期',
    });
  });

  it('有学期但 summary 为 null 时放行各模块', () => {
    expect(getNavSectionAvailability('subjects', true, null)).toEqual({ enabled: true, reason: null });
    expect(getNavSectionAvailability('teachers', true, null)).toEqual({ enabled: true, reason: null });
  });

  it('按级联门控规则控制科目、教师、排课与带班页面可用性', () => {
    const noStages = baseSummary({ stagesDone: false, routineDone: false });
    expect(getNavSectionAvailability('subjects', true, noStages)).toEqual({
      enabled: false,
      reason: '请先创建学段、年级与班级',
    });

    const noRoutine = baseSummary({ stagesDone: true, routineDone: false });
    expect(getNavSectionAvailability('supervision', true, noRoutine)).toEqual({
      enabled: false,
      reason: '请先完成各学段作息设置',
    });

    const noSubjects = baseSummary({ subjectLessonsReady: false });
    expect(getNavSectionAvailability('teachers', true, noSubjects)).toEqual({
      enabled: false,
      reason: '请先填写各年级科目节数',
    });

    const noTeachers = baseSummary({
      teacherAssignmentsReady: false,
      hasSchedule: false,
      hasSavedTimetable: false,
    });
    expect(getNavSectionAvailability('scheduling', true, noTeachers)).toEqual({
      enabled: false,
      reason: '请先补齐各班教师任课',
    });

    // 已有已保存课表时允许进入排课页面
    expect(
      getNavSectionAvailability(
        'scheduling',
        true,
        baseSummary({ teacherAssignmentsReady: false, hasSchedule: false, hasSavedTimetable: true })
      )
    ).toEqual({ enabled: true, reason: null });
  });
});

describe('features/workbench/workbenchModel.ts - 4步排课准备与排课入口', () => {
  it('排课准备精简为 4 个基础搭建步骤（不含开始排课）', () => {
    expect(PREPARATION_STEP_TOTAL).toBe(4);
    expect(PREPARATION_STEPS.map((s) => [s.number, s.title, s.section])).toEqual([
      [1, '学段与班级', 'classes'],
      [2, '作息设置', 'routines'],
      [3, '科目节数', 'subjects'],
      [4, '教师任课', 'teachers'],
    ]);
  });

  it('按级联顺序计算已完成步数、当前步骤与各步状态', () => {
    const step2Summary = baseSummary({
      stagesDone: true,
      routineDone: false,
      subjectLessonsReady: false,
      teacherAssignmentsReady: false,
      hasSchedule: false,
    });
    expect(getCompletedPreparationCount(step2Summary)).toBe(1);
    const currentStep = getCurrentPreparationStep(step2Summary);
    expect(currentStep?.key).toBe('routine');
    expect(getCompletedPreparationSteps(step2Summary).map((s) => s.key)).toEqual([
      'stagesAndClasses',
    ]);
    expect(
      PREPARATION_STEPS.map((step) =>
        getPreparationStepStatus(step, 1, currentStep)
      )
    ).toEqual(['done', 'current', 'locked', 'locked']);
  });

  it('4 步基础搭建全部完成后，当前准备步骤为空并提供排课与课表跳转入口', () => {
    const allSetupDone = baseSummary({
      stagesDone: true,
      routineDone: true,
      subjectLessonsReady: true,
      teacherAssignmentsReady: true,
      hasSchedule: false,
      hasSavedTimetable: false,
    });
    expect(getCompletedPreparationCount(allSetupDone)).toBe(4);
    expect(getCurrentPreparationStep(allSetupDone)).toBeNull();
    expect(getCompletedPreparationSteps(allSetupDone)).toHaveLength(4);

    const scheduleEntry = getScheduleEntryCopy(allSetupDone);
    expect(scheduleEntry.targetSection).toBe('scheduling');
    expect(scheduleEntry.actionLabel).toBe('去排课');

    const withSchedule = getScheduleEntryCopy(
      baseSummary({ hasSchedule: true })
    );
    expect(withSchedule.targetSection).toBe('scheduling');
    expect(withSchedule.actionLabel).toBe('打开课表');

    const progress = getWorkbenchProgress(true, allSetupDone);
    expect(progress.completeCount).toBe(4);
    expect(progress.totalCount).toBe(4);
    expect(progress.nextSection).toBe('scheduling');
  });

  it('为每个准备步骤生成对应的引导文案与统计摘要', () => {
    const summary = baseSummary({
      stageCount: 2,
      gradeCount: 9,
      classCount: 60,
      routineDone: true,
      teacherAssignmentsReady: false,
    });
    expect(getStepCopyFor(PREPARATION_STEPS[0], summary).meta).toContain('2 个学段 · 9 个年级 · 60 个班级');
    expect(getStepCopyFor(PREPARATION_STEPS[1], summary).meta).toBe('2 / 2 个学段已配置作息');
    expect(getStepCopyFor(PREPARATION_STEPS[2], summary).meta).toBe('已准备 9 个年级');
    expect(getStepCopyFor(PREPARATION_STEPS[3], summary).actionLabel).toBe('去分配教师任课');
  });
});

describe('domain/routineUtils.ts', () => {
  it('空时段列表时补全四段默认时段及默认节数', () => {
    const result = completeRoutinePeriodTypes([], 'stage-1');
    expect(result).toHaveLength(4);
    expect(result.map((p) => [p.name, p.defaultLessonCount, p.sortOrder])).toEqual([
      ['早上', 0, 0],
      ['上午', 4, 1],
      ['下午', 4, 2],
      ['晚上', 2, 3],
    ]);
  });

  it('能映射别名并保留自定义时段在后方', () => {
    const result = completeRoutinePeriodTypes(
      [
        { id: 'p1', stageId: 'old', name: '早读', defaultLessonCount: 1, sortOrder: 2 },
        { id: 'p2', stageId: 'old', name: '午练', defaultLessonCount: 1, sortOrder: 1 },
      ],
      'stage-1'
    );
    expect(result.map((p) => p.name)).toEqual(['早上', '上午', '下午', '晚上', '午练']);
    expect(result[0].defaultLessonCount).toBe(1);
    expect(result[1].defaultLessonCount).toBe(0); // 非空输入时缺失的默认时段节数为 0
    expect(result[4].sortOrder).toBe(4);
  });

  it('格式化上课日与时段摘要', () => {
    const makeRoutine = (days: number[], counts: number[]): StageRoutine => ({
      stageId: 's1',
      teachingDays: days.map((weekday) => ({
        id: `d-${weekday}`,
        stageId: 's1',
        weekday,
        isTeachingDay: true,
      })),
      periodTypes: ['早上', '上午', '下午', '晚上'].map((name, i) => ({
        id: `pt-${i}`,
        stageId: 's1',
        name,
        defaultLessonCount: counts[i] ?? 0,
        sortOrder: i,
      })),
      dailyOverrides: [],
      lessonTimes: [],
    });

    expect(formatRoutineTeachingDays(makeRoutine([1, 2, 3, 4, 5], []))).toBe('周一至周五');
    expect(formatRoutineTeachingDays(makeRoutine([1, 2, 3, 4, 5, 6], []))).toBe('周一至周六');
    expect(formatRoutineTeachingDays(makeRoutine([1, 2, 3, 4, 5, 6, 7], []))).toBe('每天上课');
    expect(formatRoutineTeachingDays(makeRoutine([1, 3, 5], []))).toBe('周一、周三、周五');
    expect(formatRoutineTeachingDays(makeRoutine([], []))).toBe('未设置上课日');

    expect(formatRoutinePeriods(makeRoutine([1], [0, 4, 3, 0]))).toBe('上午 4 · 下午 3');
    expect(formatRoutinePeriods(makeRoutine([1], [0, 0, 0, 0]))).toBe('尚未设置每日节数');
    expect(formatRoutineSummary(undefined)).toBe('作息尚未配置');
  });

  it('返回正确的时段配色', () => {
    expect(getPeriodAccentColor('早上', 2)).toBe('var(--color-purple)');
    expect(getPeriodAccentColor('早读', 0)).toBe('var(--color-purple)');
    expect(getPeriodAccentColor('上午', 0)).toBe('var(--color-accent)');
    expect(getPeriodAccentColor('下午', 0)).toBe('var(--color-success)');
    expect(getPeriodAccentColor('晚上', 0)).toBe('var(--color-ink-secondary)');
    expect(getPeriodAccentColor('自定义', 5)).toBe('var(--color-accent)');
  });
});

describe('lib/numberInput.ts & lib/utils.ts', () => {
  it('正确解析数字草稿与边界值归一化', () => {
    expect(parseNumericDraft('')).toBeNull();
    expect(parseNumericDraft('   ')).toBeNull();
    expect(parseNumericDraft('abc')).toBeNull();
    expect(parseNumericDraft('Infinity')).toBeNull();
    expect(parseNumericDraft(' 42 ')).toBe(42);
    expect(parseNumericDraft('0')).toBe(0);

    expect(normalizeNumericValue(null, 1, 10, 5)).toBe(5);
    expect(normalizeNumericValue(-3, 1, 10, 5)).toBe(1);
    expect(normalizeNumericValue(99, 1, 10, 5)).toBe(10);
    expect(normalizeNumericValue(7, 1, 10, 5)).toBe(7);
  });

  it('numericInputDraftReducer 正确处理编辑、恢复空值与归一化', () => {
    expect(numericInputDraftReducer('1', { type: 'edit', value: '' })).toBe('');
    expect(numericInputDraftReducer('  ', { type: 'restore-empty', fallback: 4 })).toBe('4');
    expect(numericInputDraftReducer('6', { type: 'restore-empty', fallback: 4 })).toBe('6');
    expect(
      numericInputDraftReducer('25', { type: 'normalize', min: 1, max: 20, fallback: 5 })
    ).toBe('20');
  });

  it('cn 正确合并并去重 Tailwind 类名', () => {
    expect(cn('px-2 py-1', false && 'hidden', 'px-4')).toBe('py-1 px-4');
  });
});
