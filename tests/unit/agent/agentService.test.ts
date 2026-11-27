import { afterEach, describe, expect, it, vi } from 'vitest';
import { AgentService } from '@/agent/agentService';
import { useAgentSettings } from '@/agent/agentSettings';
import { defaultAgentToolExecutor } from '@/agent/domain/agentToolExecutor';
import { schoolRepository } from '@/repository/schoolRepository';

describe('AgentService', () => {
  afterEach(() => {
    useAgentSettings.getState().setAutoApplyWrites(false);
    vi.restoreAllMocks();
  });

  it('在读取仓储前拒绝无效日期、超过 31 天和未知参数', async () => {
    const executor = { executeTool: vi.fn() };
    const service = new AgentService(executor);
    for (const args of [
      { startDate: '2026-02-30', endDate: '2026-03-01' },
      { startDate: '2026-02-01', endDate: '2026-03-04' },
      { startDate: '2026-03-01', endDate: '2026-03-02', publish: true },
      null,
    ]) {
      await expect(service.callTool('classset_query_actual_timetable', args)).rejects.toThrow('参数');
    }
    expect(executor.executeTool).not.toHaveBeenCalled();
  });

  it('无写入通道时只公开只读工具并拒绝写入调用', async () => {
    const executor = { executeTool: vi.fn().mockResolvedValue({ hasTerm: false }) };
    const service = new AgentService(executor);
    expect(service.listTools().map((tool) => tool.name)).toEqual([
      'classset_get_context_and_gates', 'classset_query_actual_timetable',
    ]);
    await expect(service.callTool('classset_run_auto_schedule', {})).rejects.toThrow('工具不可用');
    expect(executor.executeTool).not.toHaveBeenCalled();
    await expect(service.callTool('classset_get_context_and_gates', {})).resolves.toEqual({ hasTerm: false });
  });

  it('启用写入通道且 SQLite 就绪时公开全部 14 个 MCP 工具（含班级与学段、科目节数、教师任课批量配置）', () => {
    const spy = vi.spyOn(schoolRepository, 'engineStatus', 'get').mockReturnValue('native-sqlite');
    try {
      const controller = new AbortController();
      const service = new AgentService({ executeTool: vi.fn() }, controller.signal);
      const toolNames = service.listTools().map((tool) => tool.name);
      expect(toolNames).toHaveLength(14);
      expect(toolNames).toContain('classset_batch_configure_classes_and_stages');
      expect(toolNames).toContain('classset_batch_configure_subjects_and_quotas');
      expect(toolNames).toContain('classset_batch_configure_teachers_and_assignments');
      expect(toolNames).toContain('classset_get_action_status');
    } finally {
      spy.mockRestore();
    }
  });

  it('关闭自动写入时写入工具返回 awaiting_confirmation；开启自动写入时直接落库并返回 committed', async () => {
    vi.spyOn(schoolRepository, 'engineStatus', 'get').mockReturnValue('native-sqlite');
    vi.spyOn(defaultAgentToolExecutor, 'resolveTermId').mockResolvedValue('term_1');
    const applyFn = vi.fn(async () => undefined);
    vi.spyOn(defaultAgentToolExecutor, 'prepareConfigureClassesAndStages').mockResolvedValue({
      termId: 'term_1',
      preview: {
        termId: 'term_1',
        upsertedStageCount: 0,
        upsertedGradeCount: 1,
        upsertedClassCount: 2,
        deletedStageCount: 0,
        deletedGradeCount: 0,
        deletedClassCount: 0,
        stages: [],
        grades: [],
        classes: [],
        notes: ['一年级：批量创建 2 个班级'],
      },
      apply: applyFn,
    });
    const writeSpy = vi
      .spyOn(schoolRepository, 'withAgentWrite')
      .mockImplementation(async (work) => {
        const fakeRepo = {
          loadActiveTermId: vi.fn(async () => 'term_1'),
          loadTerms: vi.fn(async () => []),
        } as unknown as typeof schoolRepository;
        return work(fakeRepo);
      });

    const controller = new AbortController();
    const service = new AgentService({ executeTool: vi.fn() }, controller.signal);

    // 1. 默认关闭自动写入：进入待确认提案
    useAgentSettings.getState().setAutoApplyWrites(false);
    const pendingRes = (await service.callTool(
      'classset_batch_configure_classes_and_stages',
      { grades: [{ name: '一年级', classCount: 2 }] }
    )) as { status: string; actionId?: string };
    expect(pendingRes.status).toBe('awaiting_confirmation');
    expect(pendingRes.actionId).toBeTruthy();
    expect(writeSpy).not.toHaveBeenCalled();

    // 2. 开启自动写入：直接写入并返回 committed
    useAgentSettings.getState().setAutoApplyWrites(true);
    const committedRes = (await service.callTool(
      'classset_batch_configure_classes_and_stages',
      { grades: [{ name: '一年级', classCount: 2 }] }
    )) as { status: string; actionId?: string };
    expect(committedRes.status).toBe('committed');
    expect(committedRes.actionId).toBeUndefined();
    expect(writeSpy).toHaveBeenCalledTimes(1);
    expect(applyFn).toHaveBeenCalledTimes(1);

    // 3. 即使开启自动写入，显式传 dryRun: true 仍只返回 preview
    const previewRes = (await service.callTool(
      'classset_batch_configure_classes_and_stages',
      { grades: [{ name: '一年级', classCount: 2 }], dryRun: true }
    )) as { status: string };
    expect(previewRes.status).toBe('preview');
    expect(writeSpy).toHaveBeenCalledTimes(1);
  });
});
