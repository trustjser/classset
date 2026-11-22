import type { AppSection, WorkbenchSummary } from '@/domain/models';

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

export function getWorkbenchProgress(
  hasTerm: boolean,
  summary: WorkbenchSummary | null
): WorkbenchProgress {
  const steps: WorkbenchStep[] = [
    {
      section: 'terms',
      title: '学期与日历',
      description: '确定教学周、单双周与日历例外',
      completed: hasTerm,
    },
    {
      section: 'classes',
      title: '班级与学段',
      description: summary
        ? `${summary.stageCount} 个学段 · ${summary.gradeCount} 个年级 · ${summary.classCount} 个班级`
        : '建立学段、年级与班级结构',
      completed: summary?.stagesDone ?? false,
    },
    {
      section: 'routines',
      title: '作息设置',
      description: '按学段设置教学日、节次与上课时间',
      completed: summary?.routineDone ?? false,
    },
    {
      section: 'subjects',
      title: '科目节数',
      description: '为各年级安排科目与每周课时',
      completed: summary?.subjectLessonsReady ?? false,
    },
    {
      section: 'teachers',
      title: '教师任课',
      description: '把教师分配到对应班级与科目',
      completed: summary?.teacherAssignmentsReady ?? false,
    },
    {
      section: 'scheduling',
      title: '排课与课表',
      description: '生成课表并检查时间冲突',
      completed: summary?.hasSchedule ?? false,
    },
  ];

  const completeCount = steps.filter((step) => step.completed).length;
  const isLoading = hasTerm && summary === null;
  const nextSection = !hasTerm
    ? 'terms'
    : isLoading
      ? null
      : (steps.find((step) => !step.completed)?.section ?? null);

  return {
    steps,
    completeCount,
    totalCount: steps.length,
    isLoading,
    nextSection,
  };
}
