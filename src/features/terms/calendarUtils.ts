/**
 * 教学日历与单双周领域计算工具
 * 严格遵循 DESIGN.md 第 9 节「日历领域约束」：
 * - 学期保存第 1 教学周锚点与教学周数，不虚构独立起止日期
 * - 第 1 周固定为单周，之后自动交替；停课、补课不移动周次锚点
 * - 月历周一至周日排列，每行左侧只显示一次教学周与单双周标记
 * - 连续停课日期与相同备注自动合并为区间显示
 */

import { AcademicTerm, CalendarException } from '../../domain/models';

export const WEEKDAY_SHORT_NAMES = ['一', '二', '三', '四', '五', '六', '日'] as const;

export function parseLocalDate(ymd: string): Date {
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(y, (m || 1) - 1, d || 1);
}

export function formatDateYmd(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function formatDateMd(ymdOrDate: string | Date): string {
  const date = typeof ymdOrDate === 'string' ? parseLocalDate(ymdOrDate) : ymdOrDate;
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

export function getIsoWeekday(ymdOrDate: string | Date): number {
  const date = typeof ymdOrDate === 'string' ? parseLocalDate(ymdOrDate) : ymdOrDate;
  const day = date.getDay();
  return day === 0 ? 7 : day;
}

export function formatDateYmdWithWeekday(ymd: string | null): string {
  if (!ymd) return '尚未设置';
  const date = parseLocalDate(ymd);
  const w = WEEKDAY_SHORT_NAMES[getIsoWeekday(date) - 1];
  return `${ymd}（周${w}）`;
}

/**
 * 获取第 1 教学周所在周的周一锚点日期
 */
export function getWeek1MondayAnchor(term: AcademicTerm): Date | null {
  if (!term.firstTeachingWeekStart) return null;
  const start = parseLocalDate(term.firstTeachingWeekStart);
  const isoDay = getIsoWeekday(start);
  const monday = new Date(start);
  monday.setDate(start.getDate() - (isoDay - 1));
  return monday;
}

export function getTeachingWeekStart(term: AcademicTerm, weekNumber: number): Date | null {
  const anchor = getWeek1MondayAnchor(term);
  if (!anchor || weekNumber < 1 || weekNumber > term.teachingWeekCount) return null;
  const d = new Date(anchor);
  d.setDate(anchor.getDate() + (weekNumber - 1) * 7);
  return d;
}

export function getTeachingWeekEnd(term: AcademicTerm, weekNumber: number): Date | null {
  const start = getTeachingWeekStart(term, weekNumber);
  if (!start) return null;
  const end = new Date(start);
  end.setDate(start.getDate() + 6);
  return end;
}

export function getTeachingWeekOfDate(term: AcademicTerm, ymdOrDate: string | Date): number | null {
  const anchor = getWeek1MondayAnchor(term);
  if (!anchor) return null;
  const target = typeof ymdOrDate === 'string' ? parseLocalDate(ymdOrDate) : ymdOrDate;
  const t0 = new Date(target.getFullYear(), target.getMonth(), target.getDate()).getTime();
  const a0 = new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate()).getTime();
  const diffDays = Math.floor((t0 - a0) / 86400000);
  if (diffDays < 0) return null;
  const week = Math.floor(diffDays / 7) + 1;
  return week >= 1 && week <= term.teachingWeekCount ? week : null;
}

export function isOddWeek(weekNumber: number): boolean {
  return weekNumber % 2 === 1;
}

export function getWeekCycleLabel(term: AcademicTerm, weekNumber: number): string {
  if (term.cycleMode === 'every_week') return '每周相同';
  return isOddWeek(weekNumber) ? '单周' : '双周';
}

export interface CalendarExceptionRange {
  id: string;
  kind: 'holiday' | 'makeup';
  startDate: string;
  endDate: string;
  note: string;
  makeupForDate: string | null;
  makeupWeekday: number | null;
  exceptions: CalendarException[];
}

/**
 * 将某教学周内的例外按「连续停课日期 + 相同备注」合并为区间，补课保持单日条目
 */
export function getExceptionRangesForWeek(
  term: AcademicTerm,
  weekNumber: number,
  allExceptions: CalendarException[]
): CalendarExceptionRange[] {
  const weekExceptions = allExceptions
    .filter((ex) => getTeachingWeekOfDate(term, ex.date) === weekNumber)
    .sort((a, b) => a.date.localeCompare(b.date));

  const ranges: CalendarExceptionRange[] = [];

  for (const ex of weekExceptions) {
    if (ex.kind === 'makeup') {
      ranges.push({
        id: ex.id,
        kind: 'makeup',
        startDate: ex.date,
        endDate: ex.date,
        note: ex.note,
        makeupForDate: ex.makeupForDate,
        makeupWeekday: ex.makeupWeekday,
        exceptions: [ex],
      });
      continue;
    }

    const last = ranges[ranges.length - 1];
    if (last && last.kind === 'holiday' && last.note.trim() === ex.note.trim()) {
      const prevEnd = parseLocalDate(last.endDate);
      const curr = parseLocalDate(ex.date);
      const diff = Math.round((curr.getTime() - prevEnd.getTime()) / 86400000);
      if (diff === 1) {
        last.endDate = ex.date;
        last.exceptions.push(ex);
        continue;
      }
    }

    ranges.push({
      id: ex.id,
      kind: 'holiday',
      startDate: ex.date,
      endDate: ex.date,
      note: ex.note,
      makeupForDate: null,
      makeupWeekday: null,
      exceptions: [ex],
    });
  }

  return ranges;
}

export function formatExceptionRangeLabel(
  term: AcademicTerm,
  range: CalendarExceptionRange
): string {
  if (range.kind === 'makeup') {
    const base = `${formatDateMd(range.startDate)} 补`;
    if (!range.makeupForDate) return `${base}课`;
    const targetWeek = getTeachingWeekOfDate(term, range.makeupForDate);
    const wName = WEEKDAY_SHORT_NAMES[getIsoWeekday(range.makeupForDate) - 1];
    const cycle = targetWeek ? getWeekCycleLabel(term, targetWeek) : '';
    const extra = range.note.trim() ? ` · ${range.note.trim()}` : '';
    return `${base} ${formatDateMd(range.makeupForDate)}（周${wName}·${cycle}）${extra}`;
  }

  const datePart =
    range.startDate === range.endDate
      ? formatDateMd(range.startDate)
      : `${formatDateMd(range.startDate)} – ${formatDateMd(range.endDate)}`;
  return range.note.trim() ? `${datePart} ${range.note.trim()}（停课）` : `${datePart} 停课`;
}

/**
 * 生成指定月份的 42 格（6 行 × 周一至周日）公历日期矩阵
 */
export function buildMonthGridDates(year: number, monthIndex0: number): Date[] {
  const firstOfMonth = new Date(year, monthIndex0, 1);
  const isoDay = getIsoWeekday(firstOfMonth);
  const mondayOffset = isoDay - 1;
  const firstVisible = new Date(year, monthIndex0, 1 - mondayOffset);
  return Array.from({ length: 42 }, (_, idx) => {
    const d = new Date(firstVisible);
    d.setDate(firstVisible.getDate() + idx);
    return d;
  });
}
