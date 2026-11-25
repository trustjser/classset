import { createId } from '@/domain/id';
import type { AcademicTerm, CycleMode } from '@/domain/models';
import { formatDateYmd, parseLocalDate } from '@/features/terms/calendarUtils';

export const SETUP_WIZARD_TOTAL_STEPS = 2 as const;

export const SCHOOL_NAME_SUGGESTIONS = [
  '青木实验小学',
  '青木初级中学',
  '第一高级中学',
  '实验学校',
] as const;

export function getDefaultTermTitle(now: Date = new Date()): string {
  const semesterLabel = now.getMonth() >= 6 ? '秋季学期' : '春季学期';
  return `${now.getFullYear()} 学年 · ${semesterLabel}`;
}

export function getSchoolIdentityPreview(schoolName: string): {
  hasCustomName: boolean;
  displayName: string;
  initial: string;
} {
  const trimmed = schoolName.trim();
  const hasCustomName = trimmed.length > 0;
  const firstChar = Array.from(trimmed)[0];
  return {
    hasCustomName,
    displayName: hasCustomName ? trimmed : '未命名学校',
    initial: hasCustomName && firstChar ? firstChar : '校',
  };
}

export function clampSetupWeekCount(raw: string | number): number {
  const num = typeof raw === 'number' ? raw : Number.parseInt(raw.trim(), 10);
  if (!Number.isFinite(num)) return 20;
  return Math.max(1, Math.min(52, num));
}

export function getTermRangePreview(params: {
  startDate: string;
  weekCount: number;
  cycleMode: CycleMode;
}): {
  hasDate: boolean;
  rangeLabel: string;
  summaryLabel: string;
} {
  const { startDate, weekCount, cycleMode } = params;
  const clampedWeeks = clampSetupWeekCount(weekCount);
  const trimmedDate = startDate.trim();
  const hasDate = /^\d{4}-\d{2}-\d{2}$/.test(trimmedDate);
  const cycleText =
    cycleMode === 'alternating'
      ? '单双周交替（第 1 周为单周）'
      : '每周使用同一套课表';

  if (!hasDate) {
    return {
      hasDate: false,
      rangeLabel: '选择第 1 教学周起始日后自动推算学期范围',
      summaryLabel: `共 ${clampedWeeks} 个教学周 · ${cycleText} · 默认创建 1 个学段`,
    };
  }

  const start = parseLocalDate(trimmedDate);
  const end = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  end.setDate(end.getDate() + clampedWeeks * 7 - 1);

  return {
    hasDate: true,
    rangeLabel: `${formatDateYmd(start)} 至 ${formatDateYmd(end)}`,
    summaryLabel: `共 ${clampedWeeks} 个教学周 · ${cycleText} · 默认创建 1 个学段`,
  };
}

export function validateSetupTermDraft(params: {
  termTitle: string;
  firstTeachingWeekStart: string;
  weekCountText: string;
}): {
  valid: boolean;
  titleError: string | null;
  dateError: string | null;
  weekCountError: string | null;
} {
  const titleError = params.termTitle.trim() ? null : '请输入学期名称';
  const dateError = /^\d{4}-\d{2}-\d{2}$/.test(params.firstTeachingWeekStart.trim())
    ? null
    : '请选择第 1 教学周起始日期';
  const count = Number.parseInt(params.weekCountText.trim(), 10);
  const weekCountError =
    !Number.isInteger(count) || count < 1 || count > 52
      ? '请输入 1–52 之间的周数'
      : null;

  return {
    valid: !titleError && !dateError && !weekCountError,
    titleError,
    dateError,
    weekCountError,
  };
}

export function buildInitialTermFromWizard(
  params: {
    termTitle: string;
    firstTeachingWeekStart: string;
    weekCountText: string;
    cycleMode: CycleMode;
  },
  now: Date = new Date()
): AcademicTerm {
  const title = params.termTitle.trim();
  const yearMatch = /\d{4}(?:-\d{4})?/.exec(title);
  const year = now.getFullYear();
  const academicYear = yearMatch?.[0] ?? `${year}-${year + 1}`;
  const semesterLabel = title.includes('春')
    ? '春季学期'
    : title.includes('秋')
    ? '秋季学期'
    : now.getMonth() >= 6
    ? '秋季学期'
    : '春季学期';
  const count = Number.parseInt(params.weekCountText.trim(), 10);
  const teachingWeekCount = Number.isInteger(count) && count >= 1 && count <= 52 ? count : 20;

  return {
    id: `term_${createId()}`,
    title,
    academicYear,
    semesterLabel,
    firstTeachingWeekStart: params.firstTeachingWeekStart.trim() || null,
    teachingWeekCount,
    cycleMode: params.cycleMode,
    createdAt: now.getTime(),
  };
}
