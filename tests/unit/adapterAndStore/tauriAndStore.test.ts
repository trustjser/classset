import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { runTauriTransaction } from '@/adapter/db/tauriTransaction';
import { isTauriDesktop } from '@/adapter/db/databaseAdapter';
import { useAppStore } from '@/store/useAppStore';
import { schoolRepository } from '@/repository/schoolRepository';
import type { AcademicTerm, ClassGroup, FreeSlot, StageRoutine } from '@/domain/models';

describe('adapter/db/tauriTransaction.ts', () => {
  it('正常事务执行 select/execute 并提交', async () => {
    const invoke = vi.fn(async (cmd: string) => {
      if (cmd === 'begin_sqlite_transaction') return 7;
      if (cmd === 'select_sqlite_transaction') return [{ id: '1' }];
      if (cmd === 'execute_sqlite_transaction') return { rowsAffected: 1, lastInsertId: 1 };
      return undefined;
    });

    const result = await runTauriTransaction(invoke, async (tx) => {
      const rows = await tx.select<{ id: string }>('SELECT id FROM terms');
      await tx.execute('UPDATE terms SET title = ?', ['新学期']);
      return rows;
    });

    expect(result).toEqual([{ id: '1' }]);
    expect(invoke).toHaveBeenCalledWith('commit_sqlite_transaction', { id: 7 });
    expect(invoke).not.toHaveBeenCalledWith('rollback_sqlite_transaction', expect.anything());
  });

  it('begin 返回非数字事务 ID 时抛出异常', async () => {
    const invoke = vi.fn(async () => 'invalid-id');
    await expect(runTauriTransaction(invoke, async () => 'ok')).rejects.toThrow('无法建立 SQLite 事务');
  });

  it('事务内写入失败时自动回滚并保留原始错误', async () => {
    const invoke = vi.fn(async (cmd: string) => {
      if (cmd === 'begin_sqlite_transaction') return 9;
      if (cmd === 'execute_sqlite_transaction') throw new Error('UNIQUE constraint failed');
      if (cmd === 'rollback_sqlite_transaction') throw new Error('rollback error should be swallowed');
      return undefined;
    });

    await expect(
      runTauriTransaction(invoke, async (tx) => {
        await tx.execute('INSERT INTO terms VALUES (?)', ['dup']);
      })
    ).rejects.toThrow('UNIQUE constraint failed');
    expect(invoke).toHaveBeenCalledWith('rollback_sqlite_transaction', { id: 9 });
  });
});

describe('adapter/db/databaseAdapter.ts - isTauriDesktop', () => {
  afterEach(() => {
    delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
  });

  it('根据 window.__TAURI_INTERNALS__ 正确识别桌面端运行环境', () => {
    expect(isTauriDesktop()).toBe(false);
    (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__ = {};
    expect(isTauriDesktop()).toBe(true);
  });
});

describe('store/useAppStore.ts - 状态管理核心动作 (Mock Repository)', () => {
  const sampleTerm: AcademicTerm = {
    id: 't1',
    title: '2026 秋',
    academicYear: '2026-2027',
    semesterLabel: '第一学期',
    firstTeachingWeekStart: '2026-09-01',
    teachingWeekCount: 20,
    cycleMode: 'every_week',
    createdAt: 1000,
  };

  beforeEach(() => {
    vi.restoreAllMocks();
    useAppStore.setState({
      initialized: false,
      schoolName: '',
      activeTermId: null,
      terms: [],
      stages: [],
      grades: [],
      classes: [],
      routinesByStage: {},
      routineDraftsByStage: {},
      freeSlotsByStage: {},
      freeSlotDraftsByTerm: {},
      freeSlotBaselinesByTerm: {},
      selectedSection: 'workbench',
      pendingNavigationSection: null,
      navigationGuard: null,
      subjectDraftDirty: false,
      lastClassFillUndo: null,
    });
  });

  it('bootstrap 初始化学校名称、学期列表并加载当前学期数据', async () => {
    vi.spyOn(schoolRepository, 'initialize').mockResolvedValue(undefined);
    vi.spyOn(schoolRepository, 'loadSchoolName').mockResolvedValue('实验中学');
    vi.spyOn(schoolRepository, 'loadTerms').mockResolvedValue([sampleTerm]);
    vi.spyOn(schoolRepository, 'loadActiveTermId').mockResolvedValue('t1');
    vi.spyOn(schoolRepository, 'loadTeachers').mockResolvedValue([]);
    vi.spyOn(schoolRepository, 'loadPublicRooms').mockResolvedValue([]);
    const refreshSpy = vi.spyOn(useAppStore.getState(), 'refreshTermData').mockResolvedValue(undefined);

    await useAppStore.getState().bootstrap();
    const state = useAppStore.getState();
    expect(state.initialized).toBe(true);
    expect(state.schoolName).toBe('实验中学');
    expect(state.activeTermId).toBe('t1');
    expect(refreshSpy).toHaveBeenCalledWith('t1');
  });

  it('removeTerm 拒绝删除当前激活学期，允许删除非激活学期', async () => {
    const deleteSpy = vi.spyOn(schoolRepository, 'deleteTerm').mockResolvedValue(undefined);
    const loadTermsSpy = vi.spyOn(schoolRepository, 'loadTerms').mockResolvedValue([sampleTerm]);
    useAppStore.setState({ activeTermId: 't1', terms: [sampleTerm] });

    await useAppStore.getState().removeTerm('t1');
    expect(deleteSpy).not.toHaveBeenCalled();

    await useAppStore.getState().removeTerm('t2');
    expect(deleteSpy).toHaveBeenCalledWith('t2');
    expect(loadTermsSpy).toHaveBeenCalled();
  });

  it('applyBatchClassFill 与 undoBatchClassFill 正确处理去重跳过与撤销恢复', async () => {
    const c1: ClassGroup = { id: 'c1', gradeId: 'g1', name: '一(1)班', sortOrder: 0 };
    const c2: ClassGroup = { id: 'c2', gradeId: 'g1', name: '一(2)班', sortOrder: 1 };
    useAppStore.setState({ activeTermId: 't1', classes: [c1, c2] });

    const saveClassesSpy = vi.spyOn(schoolRepository, 'saveClasses').mockResolvedValue(undefined);
    vi.spyOn(useAppStore.getState(), 'refreshTermData').mockImplementation(async () => {
      useAppStore.setState({
        classes: [
          { ...c1, name: '新1班' },
          c2,
        ],
      });
    });

    const result = await useAppStore.getState().applyBatchClassFill([
      { target: c1, newName: '新1班' },
      { target: c2, newName: '新1班' }, // 同年级重名应被跳过
    ]);
    expect(result).toEqual({ updatedCount: 1, skippedCount: 1 });
    expect(saveClassesSpy).toHaveBeenCalledWith([{ ...c1, name: '新1班' }]);

    const restored = await useAppStore.getState().undoBatchClassFill();
    expect(restored).toBe(1);
    expect(saveClassesSpy).toHaveBeenLastCalledWith([c1]);
  });

  it('setFreeSlotDraft 在恢复至基线值时自动清除草稿', () => {
    const slot: FreeSlot = {
      id: 'fs1', scopeType: 'stage', scopeId: 's1', stageId: 's1',
      periodTypeId: 'pt1', weekday: 1, lessonIndex: 1, label: '班会',
    };
    useAppStore.setState({ freeSlotsByStage: { s1: [slot] } });

    useAppStore.getState().setFreeSlotDraft('t1', 'fs1', { ...slot, label: '自习' });
    expect(useAppStore.getState().freeSlotDraftsByTerm['t1']?.['fs1']?.label).toBe('自习');

    // 改回原始值后应自动移除草稿与基线记录
    useAppStore.getState().setFreeSlotDraft('t1', 'fs1', slot);
    expect(useAppStore.getState().freeSlotDraftsByTerm['t1']?.['fs1']).toBeUndefined();
    expect(useAppStore.getState().freeSlotBaselinesByTerm['t1']?.['fs1']).toBeUndefined();
  });

  it('saveStageRoutine 裁剪多余节次时间并清理公共时段失效锚点', async () => {
    const saveRoutineSpy = vi.spyOn(schoolRepository, 'saveStageRoutine').mockResolvedValue(undefined);
    vi.spyOn(schoolRepository, 'saveFreeSlotChanges').mockResolvedValue(undefined);
    vi.spyOn(schoolRepository, 'loadWorkbenchSummary').mockResolvedValue(null as never);

    useAppStore.setState({
      stages: [{ id: 's1', termId: 't1', name: '小学部', sortOrder: 0 }],
    });

    const routine: StageRoutine = {
      stageId: 's1',
      teachingDays: [],
      periodTypes: [{ id: 'pt1', stageId: 's1', name: '上午', defaultLessonCount: 1, sortOrder: 0 }],
      dailyOverrides: [],
      lessonTimes: [
        { id: 'pt1_1', periodTypeId: 'pt1', lessonIndex: 1, label: '第1节', startMinute: 480, endMinute: 520 },
        { id: 'pt1_2', periodTypeId: 'pt1', lessonIndex: 2, label: '第2节', startMinute: 530, endMinute: 570 },
      ],
      commonPeriods: [
        { id: 'cp1', stageId: 's1', name: '大课间', insertAfterLessonId: 'pt1_2', durationMinutes: 20, sortOrder: 0, startMinute: null, endMinute: null },
      ],
    };

    await useAppStore.getState().saveStageRoutine(routine);
    const savedArg = saveRoutineSpy.mock.calls[0][0];
    expect(savedArg.lessonTimes).toHaveLength(1);
    expect(savedArg.commonPeriods?.[0].insertAfterLessonId).toBe('pt1_1');
  });

  it('setSelectedSection 与 resolvePendingNavigation 在有未保存草稿守卫时按用户选择拦截或放行跳转', async () => {
    const save = vi.fn(async () => true);
    const discard = vi.fn();
    useAppStore.setState({
      selectedSection: 'subjects',
      subjectDraftDirty: true,
      navigationGuard: { label: '科目节数', isDirty: () => true, save, discard },
    });

    useAppStore.getState().setSelectedSection('teachers');
    expect(useAppStore.getState().selectedSection).toBe('subjects');
    expect(useAppStore.getState().pendingNavigationSection).toBe('teachers');

    await useAppStore.getState().resolvePendingNavigation('cancel');
    expect(useAppStore.getState().selectedSection).toBe('subjects');
    expect(useAppStore.getState().pendingNavigationSection).toBeNull();
    expect(save).not.toHaveBeenCalled();
    expect(discard).not.toHaveBeenCalled();

    useAppStore.getState().setSelectedSection('teachers');
    await useAppStore.getState().resolvePendingNavigation('discard');
    expect(discard).toHaveBeenCalledTimes(1);
    expect(useAppStore.getState().selectedSection).toBe('teachers');
    expect(useAppStore.getState().pendingNavigationSection).toBeNull();
    expect(useAppStore.getState().navigationGuard).toBeNull();
    expect(useAppStore.getState().subjectDraftDirty).toBe(false);
  });
});
