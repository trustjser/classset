import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  buildInitialTermFromWizard,
  clampSetupWeekCount,
  getDefaultTermTitle,
  getSchoolIdentityPreview,
  getTermRangePreview,
  SCHOOL_NAME_SUGGESTIONS,
  validateSetupTermDraft,
} from '@/features/setup/setupWizardLogic';
import { useAppStore } from '@/store/useAppStore';
import { schoolRepository } from '@/repository/schoolRepository';

describe('features/setup/setupWizardLogic.ts - 初次访问向导逻辑', () => {
  it('根据当前月份生成默认学期名称（7月起为秋季学期，其余为春季学期）', () => {
    expect(getDefaultTermTitle(new Date(2026, 2, 15))).toBe('2026 学年 · 春季学期');
    expect(getDefaultTermTitle(new Date(2026, 8, 1))).toBe('2026 学年 · 秋季学期');
  });

  it('生成学校名片实时预览（支持留空默认占位与自定义校名首字提取）', () => {
    expect(getSchoolIdentityPreview('   ')).toEqual({
      hasCustomName: false,
      displayName: '未命名学校',
      initial: '校',
    });
    expect(getSchoolIdentityPreview(' 青木实验小学 ')).toEqual({
      hasCustomName: true,
      displayName: '青木实验小学',
      initial: '青',
    });
    expect(SCHOOL_NAME_SUGGESTIONS).toContain('青木实验小学');
  });

  it('钳制总周数并实时计算学期起止范围预览', () => {
    expect(clampSetupWeekCount('')).toBe(20);
    expect(clampSetupWeekCount(0)).toBe(1);
    expect(clampSetupWeekCount(60)).toBe(52);
    expect(clampSetupWeekCount('18')).toBe(18);

    const noDate = getTermRangePreview({
      startDate: '',
      weekCount: 20,
      cycleMode: 'alternating',
    });
    expect(noDate.hasDate).toBe(false);
    expect(noDate.rangeLabel).toBe('选择第 1 教学周起始日后自动推算学期范围');
    expect(noDate.summaryLabel).toContain('单双周交替（第 1 周为单周）');

    const withDate = getTermRangePreview({
      startDate: '2026-09-01',
      weekCount: 2,
      cycleMode: 'every_week',
    });
    expect(withDate.hasDate).toBe(true);
    expect(withDate.rangeLabel).toBe('2026-09-01 至 2026-09-14');
    expect(withDate.summaryLabel).toContain('每周使用同一套课表');
  });

  it('校验第 2 步学期表单必填项与周数边界', () => {
    expect(
      validateSetupTermDraft({
        termTitle: '  ',
        firstTeachingWeekStart: '',
        weekCountText: '0',
      })
    ).toEqual({
      valid: false,
      titleError: '请输入学期名称',
      dateError: '请选择第 1 教学周起始日期',
      weekCountError: '请输入 1–52 之间的周数',
    });

    expect(
      validateSetupTermDraft({
        termTitle: '2026 学年 · 秋季学期',
        firstTeachingWeekStart: '2026-09-01',
        weekCountText: '20',
      })
    ).toEqual({
      valid: true,
      titleError: null,
      dateError: null,
      weekCountError: null,
    });
  });

  it('buildInitialTermFromWizard 正确提取学年与学期标签', () => {
    const term = buildInitialTermFromWizard(
      {
        termTitle: ' 2026-2027 学年春季学期 ',
        firstTeachingWeekStart: '2027-02-22',
        weekCountText: '19',
        cycleMode: 'alternating',
      },
      new Date(2027, 1, 10)
    );
    expect(term.title).toBe('2026-2027 学年春季学期');
    expect(term.academicYear).toBe('2026-2027');
    expect(term.semesterLabel).toBe('春季学期');
    expect(term.firstTeachingWeekStart).toBe('2027-02-22');
    expect(term.teachingWeekCount).toBe(19);
    expect(term.cycleMode).toBe('alternating');
  });
});

describe('store/useAppStore.ts - completeInitialSetup', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    useAppStore.setState({
      schoolName: '',
      terms: [],
      activeTermId: null,
      selectedSection: 'terms',
    });
  });

  it('依次保存学校名称、第一个学期与激活学期 ID，并切入工作台', async () => {
    const term = buildInitialTermFromWizard({
      termTitle: '2026 学年 · 秋季学期',
      firstTeachingWeekStart: '2026-09-01',
      weekCountText: '20',
      cycleMode: 'alternating',
    });

    const saveNameSpy = vi.spyOn(schoolRepository, 'saveSchoolName').mockResolvedValue(undefined);
    const saveTermSpy = vi.spyOn(schoolRepository, 'saveTerm').mockResolvedValue(undefined);
    const saveActiveSpy = vi.spyOn(schoolRepository, 'saveActiveTermId').mockResolvedValue(undefined);
    vi.spyOn(schoolRepository, 'loadTerms').mockResolvedValue([term]);
    const refreshSpy = vi.spyOn(useAppStore.getState(), 'refreshTermData').mockResolvedValue(undefined);

    await useAppStore.getState().completeInitialSetup('  青木实验小学  ', term);

    expect(saveNameSpy).toHaveBeenCalledWith('青木实验小学');
    expect(saveTermSpy).toHaveBeenCalledWith(term);
    expect(saveActiveSpy).toHaveBeenCalledWith(term.id);
    expect(refreshSpy).toHaveBeenCalledWith(term.id);

    const state = useAppStore.getState();
    expect(state.schoolName).toBe('青木实验小学');
    expect(state.activeTermId).toBe(term.id);
    expect(state.terms).toEqual([term]);
    expect(state.selectedSection).toBe('workbench');
  });
});
