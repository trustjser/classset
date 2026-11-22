import type { LessonPeriodType, StageRoutine } from './models';

export const DEFAULT_ROUTINE_PERIODS = [
  { name: '早上', count: 0 },
  { name: '上午', count: 4 },
  { name: '下午', count: 4 },
  { name: '晚上', count: 2 },
] as const;

const PERIOD_KEYS = ['early', 'morning', 'afternoon', 'evening'] as const;
const PERIOD_ALIASES: Record<string, string> = {
  早读: '早上',
  上午时段: '上午',
  下午时段: '下午',
  晚自习: '晚上',
};

export function completeRoutinePeriodTypes(
  periods: LessonPeriodType[],
  stageId: string
): LessonPeriodType[] {
  const source = [...periods]
    .sort((a, b) => a.sortOrder - b.sortOrder)
    .map((period) => ({
      ...period,
      stageId,
      name: PERIOD_ALIASES[period.name] ?? period.name,
    }));
  const usedIds = new Set<string>();
  const builtIn = DEFAULT_ROUTINE_PERIODS.map((definition, index) => {
    const existing = source.find(
      (period) => period.name === definition.name && !usedIds.has(period.id)
    );
    if (existing) {
      usedIds.add(existing.id);
      return { ...existing, sortOrder: index };
    }
    return {
      id: `pt_${stageId}_${PERIOD_KEYS[index]}`,
      stageId,
      name: definition.name,
      defaultLessonCount: periods.length === 0 ? definition.count : 0,
      sortOrder: index,
    };
  });
  const custom = source
    .filter((period) => !usedIds.has(period.id))
    .map((period, index) => ({ ...period, sortOrder: builtIn.length + index }));
  return [...builtIn, ...custom];
}

export const WEEKDAY_SHORT_NAMES = ['一', '二', '三', '四', '五', '六', '日'] as const;

export function formatRoutineTeachingDays(
  routine: StageRoutine,
  emptyLabel = '未设置上课日'
): string {
  const activeDays = routine.teachingDays
    .filter((day) => day.isTeachingDay)
    .map((day) => day.weekday)
    .sort((a, b) => a - b);
  if (activeDays.length === 7) return '每天上课';
  if (
    activeDays.length === 5 &&
    activeDays.every((weekday, index) => weekday === index + 1)
  ) {
    return '周一至周五';
  }
  if (
    activeDays.length === 6 &&
    activeDays.every((weekday, index) => weekday === index + 1)
  ) {
    return '周一至周六';
  }
  return activeDays.length
    ? activeDays.map((weekday) => `周${WEEKDAY_SHORT_NAMES[weekday - 1]}`).join('、')
    : emptyLabel;
}

export function formatRoutinePeriods(
  routine: StageRoutine,
  emptyLabel = '尚未设置每日节数',
  separator = ' · '
): string {
  const periods = routine.periodTypes
    .filter((period) => period.defaultLessonCount > 0)
    .map((period) => `${period.name} ${period.defaultLessonCount}`);
  return periods.length ? periods.join(separator) : emptyLabel;
}

export function formatRoutineSummary(routine?: StageRoutine): string {
  if (!routine) return '作息尚未配置';
  return [
    formatRoutineTeachingDays(routine, '未设置上课天'),
    formatRoutinePeriods(routine, '未设时段', ' + '),
  ].join(' · ');
}

const PERIOD_ACCENT_PRESETS = [
  'var(--color-purple)',
  'var(--color-accent)',
  'var(--color-success)',
  'var(--color-ink-secondary)',
] as const;

/**
 * 与 Flutter 端 `periodVisualFor` 保持一致的时段配色：
 * 早上/早读 = 紫，上午 = 蓝，下午 = 绿，晚上 = 深灰；自定义时段在四套预设间轮换。
 */
export function getPeriodAccentColor(periodName: string, index: number): string {
  switch (periodName) {
    case '早上':
    case '早读':
      return PERIOD_ACCENT_PRESETS[0];
    case '上午':
      return PERIOD_ACCENT_PRESETS[1];
    case '下午':
      return PERIOD_ACCENT_PRESETS[2];
    case '晚上':
      return PERIOD_ACCENT_PRESETS[3];
    default:
      return PERIOD_ACCENT_PRESETS[index % PERIOD_ACCENT_PRESETS.length];
  }
}
