import { CLASSSET_AGENT_TOOL_SCHEMAS, type ClassSetAgentToolName } from '@/agent/domain/agentToolSchemas';
import {
  defaultAgentToolExecutor,
  type ApplyTemporaryAdjustmentArgs,
  type AutoAllocateSupervisionArgs,
  type BatchConfigureClassesAndStagesArgs,
  type BatchConfigureSubjectsAndQuotasArgs,
  type BatchConfigureTeachersAndAssignmentsArgs,
  type BatchCreateSupervisionPostsArgs,
  type CancelTemporaryAdjustmentArgs,
  type ConfigureScheduleRulesArgs,
  type MoveOrSwapLessonArgs,
  type PublishSupervisionVersionArgs,
  type RunAutoScheduleArgs,
} from '@/agent/domain/agentToolExecutor';
import { schoolRepository } from '@/repository/schoolRepository';
import Ajv from 'ajv';
import { agentProposals } from './agentProposals';
import { getAutoApplyWrites } from './agentSettings';
import { solveAgentSchedule } from './solveAgentSchedule';
import { createId } from '@/domain/id';
import { useAppStore } from '@/store/useAppStore';

interface ToolExecutor {
  executeTool(name: ClassSetAgentToolName, args: Record<string, unknown>): Promise<unknown>;
}

export function agentErrorResult(error: unknown) {
  const detail = error instanceof Error ? error.message : '';
  const classification = [
    { match: /参数|不属于当前学期|必须提供|工具不可用|查询游标|找不到|不能为空|不能分配|超过需求|合班设置失败|至少需要保留/u, code: 'INVALID_ARGUMENT', message: '请检查参数、日期和本次操作使用的 ID 或名称。' },
    { match: /找不到.*学期|先创建学期/u, code: 'TERM_NOT_FOUND', message: '请在课集选择有效学期。' },
    { match: /协调/u, code: 'RECONCILIATION_REQUIRED', message: '请在排课与课表中确认草稿协调。' },
    { match: /前置|请先|暂未/u, code: 'GATE_BLOCKED', message: '请在课集检查当前学期的准备进度。' },
    { match: /操作过多/u, code: 'BUSY', message: '请处理现有的待确认操作后重试。' },
    { match: /超大|结果过大/u, code: 'RESULT_TOO_LARGE', message: '请缩小日期范围或指定班级、教师。' },
  ].find(({ match }) => match.test(detail));
  return {
    status: 'error' as const,
    requestId: createId(),
    code: classification?.code ?? 'NOT_READY',
    message: classification?.message ?? '工具暂不可用，请检查课集中的数据和连接状态。',
  };
}

const readTools = CLASSSET_AGENT_TOOL_SCHEMAS.filter((tool) => tool.readOnly);
const prepareTools = {
  classset_batch_configure_classes_and_stages: (args: unknown) =>
    defaultAgentToolExecutor.prepareConfigureClassesAndStages(args as BatchConfigureClassesAndStagesArgs),
  classset_batch_configure_subjects_and_quotas: (args: unknown) =>
    defaultAgentToolExecutor.prepareConfigureSubjectsAndQuotas(args as BatchConfigureSubjectsAndQuotasArgs),
  classset_batch_configure_teachers_and_assignments: (args: unknown) =>
    defaultAgentToolExecutor.prepareConfigureTeachersAndAssignments(args as BatchConfigureTeachersAndAssignmentsArgs),
  classset_configure_schedule_rules: (args: unknown) =>
    defaultAgentToolExecutor.prepareConfigureScheduleRules(args as ConfigureScheduleRulesArgs),
  classset_move_or_swap_lesson: (args: unknown) =>
    defaultAgentToolExecutor.prepareMoveOrSwapLesson(args as MoveOrSwapLessonArgs),
  classset_run_auto_schedule: (args: unknown, signal: AbortSignal) =>
    defaultAgentToolExecutor.prepareAutoSchedule(args as RunAutoScheduleArgs, (request) => solveAgentSchedule(request, signal)),
  classset_batch_create_supervision_posts: (args: unknown) =>
    defaultAgentToolExecutor.prepareCreateSupervisionPosts(args as BatchCreateSupervisionPostsArgs),
  classset_auto_allocate_supervision: (args: unknown) =>
    defaultAgentToolExecutor.prepareAllocateSupervision(args as AutoAllocateSupervisionArgs),
  classset_publish_supervision_version: (args: unknown) =>
    defaultAgentToolExecutor.preparePublishSupervision(args as PublishSupervisionVersionArgs),
  classset_apply_temporary_adjustment: (args: unknown) =>
    defaultAgentToolExecutor.prepareTemporaryAdjustment(args as ApplyTemporaryAdjustmentArgs),
  classset_cancel_temporary_adjustment: (args: unknown) =>
    defaultAgentToolExecutor.prepareCancelTemporaryAdjustment(args as CancelTemporaryAdjustmentArgs),
};
function isPreparedTool(name: string): name is keyof typeof prepareTools {
  return Object.prototype.hasOwnProperty.call(prepareTools, name);
}
const enabledWrites = CLASSSET_AGENT_TOOL_SCHEMAS.filter(({ name }) => isPreparedTool(name));
const statusTool = {
  name: 'classset_get_action_status', readOnly: true,
  description: '查询本连接创建的待确认操作。使用工具返回的 actionId。',
  inputSchema: {
    type: 'object', properties: { actionId: { type: 'string', minLength: 1, maxLength: 64 } },
    required: ['actionId'], additionalProperties: false,
  },
} as const;
const ajv = new Ajv({ ownProperties: true });
const validators = new Map([...readTools, ...enabledWrites, statusTool].map((tool) => [
  tool.name, ajv.compile<Record<string, unknown>>(tool.inputSchema),
]));

function boundPreview<T extends Record<string, unknown>>(preview: T): Record<string, unknown> {
  return Object.fromEntries(Object.entries(preview).flatMap(([name, value]) => Array.isArray(value) && value.length > 30
    ? [[name, value.slice(0, 30)], [`${name}Total`, value.length]]
    : [[name, value]]));
}

function calendarTimestamp(value: string): number {
  const date = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new Error('日期参数必须是有效的日历日期');
  }
  return date.getTime();
}

async function pageTimetable(value: unknown, args: Record<string, unknown>) {
  const result = value as Awaited<ReturnType<typeof defaultAgentToolExecutor.queryActualTimetable>>;
  const { lessons, supervisions, activeAdjustments, ...summary } = result;
  const pageSize = (args.pageSize as number | undefined) ?? 100;
  const groups = [
    { name: 'lessons', items: lessons },
    { name: 'supervisions', items: supervisions },
    { name: 'activeAdjustments', items: activeAdjustments },
  ] as const;
  const total = groups.reduce((sum, group) => sum + group.items.length, 0);
  const { cursor, pageSize: _pageSize, ...query } = args;
  const queryKey = Object.entries(query).sort(([a], [b]) => a.localeCompare(b));
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify([queryKey, result])));
  const version = [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  const match = typeof cursor === 'string' ? /^(\d+)\.([a-f0-9]{64})$/.exec(cursor) : null;
  if (cursor !== undefined && (!match || match[2] !== version || Number(match[1]) >= total)) {
    throw new Error('查询游标已失效，请从第一页重新查询。');
  }
  const offset = match ? Number(match[1]) : 0;
  let groupStart = 0;
  const pages = Object.fromEntries(groups.map(({ name, items }) => {
    const start = Math.max(0, offset - groupStart);
    const end = Math.max(0, offset + pageSize - groupStart);
    groupStart += items.length;
    return [name, items.slice(start, end)];
  }));
  return {
    ...summary,
    ...pages,
    hasPublishedSchedule: true,
    nextCursor: offset + pageSize < total ? `${offset + pageSize}.${version}` : null,
  };
}

export class AgentService {
  constructor(
    private readonly executor: ToolExecutor = defaultAgentToolExecutor,
    private readonly channel?: AbortSignal,
  ) {}

  listTools() {
    return this.channel && schoolRepository.engineStatus !== 'memory-fallback'
      ? [...readTools, ...enabledWrites, statusTool] : readTools;
  }

  async callTool(name: string, args: unknown, requestSignal?: AbortSignal): Promise<unknown> {
    if (this.channel?.aborted || requestSignal?.aborted) throw new Error('工具请求已取消');
    const tool = this.listTools().find((candidate) => candidate.name === name);
    if (!tool) throw new Error('工具不可用');
    const validate = validators.get(tool.name);
    if (JSON.stringify(args)?.length > 16_384 || !validate || !validate(args)) {
      throw new Error('工具参数不符合要求');
    }
    if (tool.name === 'classset_query_actual_timetable') {
      const start = calendarTimestamp(args.startDate as string);
      const end = calendarTimestamp(args.endDate as string);
      if (end < start || end - start >= 31 * 86_400_000) {
        throw new Error('日期参数应为最多 31 天的正向区间');
      }
      if (this.channel) {
        const termId = await defaultAgentToolExecutor.resolveTermId(args.termId as string | undefined);
        if (!await schoolRepository.loadPublishedSchedule(termId)) {
          return { hasPublishedSchedule: false, termId, lessons: [], supervisions: [] };
        }
      }
    }
    if (tool.name === statusTool.name) {
      const action = agentProposals.status(args.actionId as string, this.channel!);
      if (!('actionId' in action)) return action;
      const { data: _data, expiresAt, ...result } = action;
      return { ...result, expiresAt: new Date(expiresAt).toISOString() };
    }
    if (isPreparedTool(tool.name) && this.channel) {
      const activeTermId = await defaultAgentToolExecutor.resolveTermId();
      if (args.termId && args.termId !== activeTermId) throw new Error('只能修改当前学期的草稿课表');
      const adjustment = tool.name === 'classset_apply_temporary_adjustment' ||
        tool.name === 'classset_cancel_temporary_adjustment';
      if (adjustment && !await schoolRepository.loadPublishedSchedule(activeTermId)) {
        throw new Error('请先发布正式课程课表，再操作调代课。');
      }
      const normalized = { ...args, termId: activeTermId };
      if (tool.name === 'classset_publish_supervision_version') calendarTimestamp(args.effectiveDate as string);
      if (tool.name === 'classset_apply_temporary_adjustment') {
        for (const date of [args.targetDate, args.rangeStart, args.rangeEnd, ...(args.excludedDates as string[] ?? [])]) {
          if (typeof date === 'string') calendarTimestamp(date);
        }
      }
      const controller = new AbortController();
      const abort = () => controller.abort();
      const signals = requestSignal ? [requestSignal, this.channel] : [this.channel];
      for (const signal of signals) {
        if (signal.aborted) abort();
        else signal.addEventListener('abort', abort, { once: true });
      }
      const { preview, apply } = await prepareTools[tool.name](normalized, controller.signal).finally(() => {
        signals.forEach((signal) => signal.removeEventListener('abort', abort));
      });
      if (controller.signal.aborted) throw new Error('工具请求已取消');
      const data = boundPreview(preview);
      if (!apply || args.dryRun) return { status: 'preview', data };
      const commitWrite = async () => {
        await schoolRepository.withAgentWrite(async (repo) => {
          const current = await repo.loadActiveTermId() ?? (await repo.loadTerms())[0]?.id;
          if (current !== activeTermId) throw new Error('当前学期已切换，请重新生成预览');
          if (adjustment && !await repo.loadPublishedSchedule(activeTermId)) {
            throw new Error('正式课程课表已变更，请重新生成预览。');
          }
          await apply(repo);
        });
      };
      if (getAutoApplyWrites()) {
        const appState = useAppStore.getState();
        if (appState.navigationGuard?.isDirty()) {
          throw new Error('操作过多：工作台有未保存的修改，请先保存或放弃后再自动写入');
        }
        await commitWrite();
        if (appState.activeTermId === activeTermId) {
          await appState.refreshTermData(activeTermId).catch(() => undefined);
        }
        return { status: 'committed', data, message: '已自动写入并保存。' };
      }
      const proposal = agentProposals.create(activeTermId, this.channel, { ...preview, toolName: tool.name }, commitWrite);
      return { status: proposal.status, actionId: proposal.actionId, data,
        expiresAt: new Date(proposal.expiresAt).toISOString(), nextStep: '请在课集设置中查看并确认操作。' };
    }
    const result = await this.executor.executeTool(tool.name as ClassSetAgentToolName, args);
    const response = tool.name === 'classset_query_actual_timetable' && this.channel
      ? await pageTimetable(result, args) : result;
    if (JSON.stringify(response)?.length > 256_000) {
      throw new Error('查询结果过大，请缩小日期范围或指定班级、教师');
    }
    return response;
  }
}
