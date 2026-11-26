import type { AppSection, WorkbenchSummary } from '@/domain/models';

export type PreparationStepKey =
  | 'stagesAndClasses'
  | 'routine'
  | 'subjectLessons'
  | 'teacherAssignments';

export type PreparationStepStatus = 'done' | 'current' | 'locked';

export interface PreparationStepMeta {
  key: PreparationStepKey;
  index: number;
  number: number;
  title: string;
  section: AppSection;
}

export const PREPARATION_STEPS: readonly PreparationStepMeta[] = [
  {
    key: 'stagesAndClasses',
    index: 0,
    number: 1,
    title: '学段与班级',
    section: 'classes',
  },
  {
    key: 'routine',
    index: 1,
    number: 2,
    title: '作息设置',
    section: 'routines',
  },
  {
    key: 'subjectLessons',
    index: 2,
    number: 3,
    title: '科目节数',
    section: 'subjects',
  },
  {
    key: 'teacherAssignments',
    index: 3,
    number: 4,
    title: '教师任课',
    section: 'teachers',
  },
] as const;

export const PREPARATION_STEP_TOTAL = PREPARATION_STEPS.length; // 4

export interface StepCopy {
  title: string;
  description: string;
  actionLabel: string;
  meta: string;
  targetSection: AppSection;
}

/**
 * 计算已完成的基础搭建准备步骤数（0 ~ 4），严格遵循顺序级联语义。
 */
export function getCompletedPreparationCount(
  summary: WorkbenchSummary | null
): number {
  if (!summary) return 0;
  if (!summary.stagesDone) return 0;
  if (!summary.routineDone) return 1;
  if (!summary.subjectLessonsReady) return 2;
  if (!summary.teacherAssignmentsReady) return 3;
  return 4;
}

/**
 * 当前尚未完成的首个基础搭建步骤；若 4 步均已完成则返回 null。
 */
export function getCurrentPreparationStep(
  summary: WorkbenchSummary | null
): PreparationStepMeta | null {
  const doneCount = getCompletedPreparationCount(summary);
  return PREPARATION_STEPS[doneCount] ?? null;
}

/**
 * 获取每个准备步骤的状态（已完成 / 当前步骤 / 完成前一步后解锁）
 */
export function getPreparationStepStatus(
  step: PreparationStepMeta,
  doneCount: number,
  currentStep: PreparationStepMeta | null
): PreparationStepStatus {
  if (step.index < doneCount) return 'done';
  if (currentStep && step.key === currentStep.key) return 'current';
  return 'locked';
}

/**
 * 获取已完成的准备步骤列表（用于底部「已完成的准备」chips 展示）
 */
export function getCompletedPreparationSteps(
  summary: WorkbenchSummary | null
): PreparationStepMeta[] {
  const doneCount = getCompletedPreparationCount(summary);
  return PREPARATION_STEPS.slice(0, doneCount);
}

/**
 * 指定准备步骤的「接下来 / 回看调整」引导卡文案
 */
export function getStepCopyFor(
  step: PreparationStepMeta,
  summary: WorkbenchSummary | null
): StepCopy {
  const stageCount = summary?.stageCount ?? 0;
  const gradeCount = summary?.gradeCount ?? 0;
  const classCount = summary?.classCount ?? 0;

  switch (step.key) {
    case 'stagesAndClasses':
      return {
        title: '创建学段与班级',
        description:
          '先搭好学段、年级和班级，后面的作息与排课都挂靠在它上面。',
        actionLabel: '去创建学段与班级',
        meta:
          classCount > 0
            ? `已创建 ${stageCount} 个学段 · ${gradeCount} 个年级 · ${classCount} 个班级`
            : `已创建 ${stageCount} 个学段 · ${gradeCount} 个年级`,
        targetSection: 'classes',
      };
    case 'routine':
      return {
        title: '设置各学段作息',
        description:
          '按学段设置上课日、各时段节数与节次时间。完成后，科目节数会自动解锁。',
        actionLabel: '去设置作息',
        meta: summary?.routineDone
          ? `${stageCount} / ${stageCount} 个学段已配置作息`
          : `共 ${stageCount} 个学段待完善作息设置`,
        targetSection: 'routines',
      };
    case 'subjectLessons':
      return {
        title: '填写各年级的科目节数',
        description:
          '核对每个年级每周各科课时。完成后，教师任课会自动解锁。',
        actionLabel: '去填写科目节数',
        meta: `已准备 ${gradeCount} 个年级`,
        targetSection: 'subjects',
      };
    case 'teacherAssignments':
      return {
        title: '分配教师任课',
        description: '为各班科目分配教师，补齐每周所需节数。',
        actionLabel: '去分配教师任课',
        meta: summary?.teacherAssignmentsReady
          ? '各班任课已分配完整'
          : '请检查各班任课是否分配完整',
        targetSection: 'teachers',
      };
  }
}

/**
 * 当 4 步基础搭建全部完成（4 / 4 完成）时，主引导卡展示排课与课表跳转入口
 * （排课不再计入基础搭建步骤，仅在基础搭建完成后提供快捷跳转入口）
 */
export function getScheduleEntryCopy(
  summary: WorkbenchSummary | null
): StepCopy {
  const hasSchedule = Boolean(
    summary?.hasSchedule || summary?.hasSavedTimetable
  );
  if (hasSchedule) {
    return {
      title: '打开课表',
      description: '基础搭建已完成且已生成排课结果，可以查看和调整课表。',
      actionLabel: '打开课表',
      meta: '排课结果已保存',
      targetSection: 'scheduling',
    };
  }
  return {
    title: '前往排课与课表',
    description: '4 步基础准备已全部就绪，现在可以前往检查排课条件并生成课表。',
    actionLabel: '去排课',
    meta: '可在排课与课表页面检查条件并生成课表',
    targetSection: 'scheduling',
  };
}

export interface WorkbenchStep {
  section: AppSection;
  title: string;
  description: string;
  completed: boolean;
}

export interface WorkbenchProgress {
  steps: WorkbenchStep[];
  completeCount: number;
  totalCount: number;
  isLoading: boolean;
  nextSection: AppSection | null;
}

/**
 * 兼容汇总查询：返回精简后的 4 步基础准备进度
 */
export function getWorkbenchProgress(
  hasTerm: boolean,
  summary: WorkbenchSummary | null
): WorkbenchProgress {
  const doneCount = getCompletedPreparationCount(summary);
  const steps: WorkbenchStep[] = PREPARATION_STEPS.map((step) => ({
    section: step.section,
    title: step.title,
    description: getStepCopyFor(step, summary).description,
    completed: step.index < doneCount,
  }));

  const isLoading = hasTerm && summary === null;
  const currentStep = getCurrentPreparationStep(summary);
  const nextSection = !hasTerm
    ? 'terms'
    : isLoading
      ? null
      : (currentStep?.section ?? 'scheduling');

  return {
    steps,
    completeCount: doneCount,
    totalCount: PREPARATION_STEP_TOTAL,
    isLoading,
    nextSection,
  };
}
