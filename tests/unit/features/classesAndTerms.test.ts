import { describe, it, expect, beforeEach } from 'vitest';
import {
  toChineseNumeral,
  expandGradeTemplate,
  generateGradeNames,
  getGradeShortName,
  generateClassNamesForGrade,
} from '@/features/classes/gradeNameTemplates';
import {
  parseLocalDate,
  formatDateYmd,
  formatDateMd,
  getIsoWeekday,
  formatDateYmdWithWeekday,
  getWeek1MondayAnchor,
  getTeachingWeekStart,
  getTeachingWeekEnd,
  getTeachingWeekOfDate,
  isOddWeek,
  getWeekCycleLabel,
  getExceptionRangesForWeek,
  formatExceptionRangeLabel,
  buildMonthGridDates,
} from '@/features/terms/calendarUtils';
import { ROUTINE_TEMPLATES, templateSummary } from '@/features/routines/routineTemplates';
import {
  captureRoutineDraftSnapshot,
  restoreRoutineDraftSnapshot,
} from '@/features/routines/routineDraftHistory';
import { useAppStore } from '@/store/useAppStore';
import type { AcademicTerm, CalendarException, FreeSlot, StageRoutine } from '@/domain/models';

describe('features/classes/gradeNameTemplates.ts', () => {
  it('转换 0-99 及百以上数字为中文数字', () => {
    expect(toChineseNumeral(0)).toBe('零');
    expect(toChineseNumeral(1)).toBe('一');
    expect(toChineseNumeral(10)).toBe('十');
    expect(toChineseNumeral(12)).toBe('十二');
    expect(toChineseNumeral(20)).toBe('二十');
    expect(toChineseNumeral(35)).toBe('三十五');
    expect(toChineseNumeral(100)).toBe('100');
  });

  it('展开年级模板并跳过已存在名称', () => {
    expect(expandGradeTemplate('{N}年级', 3)).toBe('三年级');
    expect(expandGradeTemplate('高{n}', 2)).toBe('高2');

    expect(
      generateGradeNames({
        template: '{N}年级',
        count: 3,
        existingNames: ['一年级', ' 三年级 '],
      })
    ).toEqual(['二年级', '四年级', '五年级']);

    // 缺少占位符时返回空数组
    expect(
      generateGradeNames({ template: '固定年级', count: 2, existingNames: [] })
    ).toEqual([]);

    // count 钳制在 [1, 9]
    expect(
      generateGradeNames({ template: '{n}年级', count: 15, existingNames: [] })
    ).toHaveLength(9);
  });

  it('提取年级简称并生成班级名称预览', () => {
    expect(getGradeShortName('一年级')).toBe('一');
    expect(getGradeShortName('高一')).toBe('高一');

    expect(generateClassNamesForGrade('一年级', 2, '{年级}({n})班', '')).toEqual([
      '一(1)班',
      '一(2)班',
    ]);
    expect(generateClassNamesForGrade('一年级', 2, '{n} 班', '')).toEqual([
      '一（1）班',
      '一（2）班',
    ]);
    expect(generateClassNamesForGrade('一年级', 2, '{年级} {n} 班', '')).toEqual([
      '一年级 1 班',
      '一年级 2 班',
    ]);
    expect(generateClassNamesForGrade('高一', 2, '自定义…', '{年级}-{N}班')).toEqual([
      '高一-一班',
      '高一-二班',
    ]);
    // 空自定义模板回退到默认格式
    expect(generateClassNamesForGrade('高一', 1, '自定义…', '   ')).toEqual(['高一(1)班']);
  });
});

describe('features/terms/calendarUtils.ts', () => {
  const baseTerm: AcademicTerm = {
    id: 'term-1',
    title: '2026 秋',
    academicYear: '2026-2027',
    semesterLabel: '第一学期',
    firstTeachingWeekStart: '2026-09-02', // 2026-09-02 为周三
    teachingWeekCount: 20,
    cycleMode: 'alternating',
    createdAt: 1000,
  };

  it('基础日期解析、格式化与 ISO 星期计算', () => {
    const wed = parseLocalDate('2026-09-02');
    expect(formatDateYmd(wed)).toBe('2026-09-02');
    expect(formatDateMd(wed)).toBe('9月2日');
    expect(getIsoWeekday(wed)).toBe(3);
    expect(getIsoWeekday('2026-09-06')).toBe(7); // 周日为 7
    expect(formatDateYmdWithWeekday(null)).toBe('尚未设置');
    expect(formatDateYmdWithWeekday('2026-09-02')).toBe('2026-09-02（周三）');
  });

  it('第 1 周周一锚点、教学周起止及所属周次计算', () => {
    const anchor = getWeek1MondayAnchor(baseTerm);
    expect(anchor && formatDateYmd(anchor)).toBe('2026-08-31');

    const w2Start = getTeachingWeekStart(baseTerm, 2);
    const w2End = getTeachingWeekEnd(baseTerm, 2);
    expect(w2Start && formatDateYmd(w2Start)).toBe('2026-09-07');
    expect(w2End && formatDateYmd(w2End)).toBe('2026-09-13');

    // 越界周次返回 null
    expect(getTeachingWeekStart(baseTerm, 0)).toBeNull();
    expect(getTeachingWeekStart(baseTerm, 21)).toBeNull();

    // 早于第 1 周或超过总周数返回 null
    expect(getTeachingWeekOfDate(baseTerm, '2026-08-30')).toBeNull();
    expect(getTeachingWeekOfDate(baseTerm, '2026-09-02')).toBe(1);
    expect(getTeachingWeekOfDate(baseTerm, '2026-09-07')).toBe(2);

    // 未设置开学日期时返回 null
    expect(getWeek1MondayAnchor({ ...baseTerm, firstTeachingWeekStart: null })).toBeNull();
    expect(getTeachingWeekOfDate({ ...baseTerm, firstTeachingWeekStart: null }, '2026-09-02')).toBeNull();
  });

  it('单双周标签与周模式判断', () => {
    expect(isOddWeek(1)).toBe(true);
    expect(isOddWeek(2)).toBe(false);
    expect(getWeekCycleLabel(baseTerm, 1)).toBe('单周');
    expect(getWeekCycleLabel(baseTerm, 2)).toBe('双周');
    expect(getWeekCycleLabel({ ...baseTerm, cycleMode: 'every_week' }, 2)).toBe('每周相同');
  });

  it('合并同周连续同备注停课区间，补课保持独立条目', () => {
    const exceptions: CalendarException[] = [
      { id: 'e1', termId: 'term-1', date: '2026-09-01', kind: 'holiday', makeupWeekday: null, makeupForDate: null, note: ' 台风 ' },
      { id: 'e2', termId: 'term-1', date: '2026-09-02', kind: 'holiday', makeupWeekday: null, makeupForDate: null, note: '台风' },
      { id: 'e3', termId: 'term-1', date: '2026-09-04', kind: 'holiday', makeupWeekday: null, makeupForDate: null, note: '台风' },
      { id: 'e4', termId: 'term-1', date: '2026-09-05', kind: 'makeup', makeupWeekday: 2, makeupForDate: '2026-09-01', note: '调休' },
    ];
    const ranges = getExceptionRangesForWeek(baseTerm, 1, exceptions);
    expect(ranges).toHaveLength(3);
    expect(ranges[0]).toMatchObject({ startDate: '2026-09-01', endDate: '2026-09-02', kind: 'holiday' });
    expect(ranges[1]).toMatchObject({ startDate: '2026-09-04', endDate: '2026-09-04', kind: 'holiday' });
    expect(ranges[2]).toMatchObject({ startDate: '2026-09-05', kind: 'makeup' });

    expect(formatExceptionRangeLabel(baseTerm, ranges[0])).toBe('9月1日 – 9月2日 台风（停课）');
    expect(formatExceptionRangeLabel(baseTerm, ranges[2])).toBe('9月5日 补 9月1日（周二·单周） · 调休');
  });

  it('构建 42 格月历矩阵且首格恒为周一', () => {
    const grid = buildMonthGridDates(2026, 8); // 2026 年 9 月
    expect(grid).toHaveLength(42);
    expect(getIsoWeekday(grid[0])).toBe(1);
  });
});

describe('features/routines/routineTemplates.ts & routineDraftHistory.ts', () => {
  beforeEach(() => {
    useAppStore.setState({
      routineDraftsByStage: {},
      freeSlotDraftsByTerm: {},
      freeSlotBaselinesByTerm: {},
    });
  });

  it('templateSummary 正确格式化模板摘要', () => {
    expect(templateSummary(ROUTINE_TEMPLATES[1])).toBe('早读 1 节 · 上午 4 节 · 下午 3 节');
  });

  it('captureRoutineDraftSnapshot 与 restoreRoutineDraftSnapshot 深拷贝并恢复草稿状态', () => {
    const routine: StageRoutine = {
      stageId: 's1',
      teachingDays: [],
      periodTypes: [],
      dailyOverrides: [],
      lessonTimes: [],
    };
    const freeSlot: FreeSlot = {
      id: 'fs-1',
      scopeType: 'stage',
      scopeId: 's1',
      stageId: 's1',
      periodTypeId: 'pt-1',
      weekday: 1,
      lessonIndex: 1,
      label: '班会',
    };
    useAppStore.setState({
      routineDraftsByStage: { s1: routine },
      freeSlotDraftsByTerm: { 't1': { 'fs-1': freeSlot } },
      freeSlotBaselinesByTerm: { 't1': { 'fs-1': null } },
    });

    const snapshot = captureRoutineDraftSnapshot('t1', ['s1']);
    // 修改 store 状态
    useAppStore.setState({
      routineDraftsByStage: {},
      freeSlotDraftsByTerm: {},
      freeSlotBaselinesByTerm: {},
    });

    restoreRoutineDraftSnapshot('t1', ['s1'], snapshot);
    const state = useAppStore.getState();
    expect(state.routineDraftsByStage['s1']).toEqual(routine);
    expect(state.freeSlotDraftsByTerm['t1']?.['fs-1']).toEqual(freeSlot);
    expect(state.freeSlotBaselinesByTerm['t1']?.['fs-1']).toBeNull();
  });
});
