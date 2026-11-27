import { createId } from '@/domain/id';

export type ProposalStatus = 'awaiting_confirmation' | 'committing' | 'committed' | 'rejected' | 'expired' | 'error';

interface Proposal {
  actionId: string;
  termId: string;
  expiresAt: number;
  status: ProposalStatus;
  data: unknown;
  message?: string;
  code?: string;
}

interface Entry {
  proposal: Proposal;
  channel: AbortSignal;
  commit?: () => Promise<void>;
}

export class AgentProposals {
  private readonly entries = new Map<string, Entry>();
  private readonly listeners = new Set<() => void>();
  private pending: Proposal[] = [];

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  };

  getPending = () => this.pending;

  private notify() {
    this.pending = [...this.entries.values()]
      .map(({ proposal }) => proposal)
      .filter(({ status }) => status === 'awaiting_confirmation' || status === 'committing');
    this.listeners.forEach((listener) => listener());
  }

  private update(entry: Entry, status: ProposalStatus, message?: string, code?: string) {
    entry.proposal = { ...entry.proposal, status, message, code };
    if (status !== 'awaiting_confirmation') entry.commit = undefined;
    this.notify();
    return entry.proposal;
  }

  create(termId: string, channel: AbortSignal, data: unknown, commit: () => Promise<void>) {
    if (channel.aborted) throw new Error('工具连接已关闭');
    const now = Date.now();
    this.entries.forEach((entry, id) => {
      if (entry.proposal.expiresAt < now && entry.proposal.status !== 'committing') this.entries.delete(id);
    });
    if (this.entries.size >= 50) throw new Error('待确认操作过多，请稍后重试。');
    const proposal: Proposal = {
      actionId: createId(),
      termId,
      expiresAt: now + 10 * 60_000,
      status: 'awaiting_confirmation',
      data,
    };
    this.entries.set(proposal.actionId, { proposal, channel, commit });
    this.notify();
    return proposal;
  }

  status(id: string, channel: AbortSignal) {
    const entry = this.entries.get(id);
    if (!entry || entry.channel !== channel || channel.aborted) {
      return { status: 'error', code: 'UNKNOWN_OUTCOME', message: '找不到此连接的操作结果。' };
    }
    if (entry.proposal.expiresAt <= Date.now() && entry.proposal.status !== 'committing') {
      return this.update(entry, 'expired');
    }
    return entry.proposal;
  }

  async confirm(id: string) {
    const entry = this.entries.get(id);
    if (!entry?.commit || entry.proposal.status !== 'awaiting_confirmation') return entry?.proposal;
    if (entry.channel.aborted || entry.proposal.expiresAt <= Date.now()) return this.update(entry, 'expired');
    const commit = entry.commit;
    this.update(entry, 'committing');
    try {
      await commit();
      return this.update(entry, 'committed');
    } catch (error) {
      const detail = error instanceof Error ? error.message : '';
      if (/数据库未就绪|无法保存浏览器数据库/u.test(detail)) {
        return this.update(entry, 'error', '本地存储不可用，请检查存储空间和权限后重试。', 'STORAGE_UNAVAILABLE');
      }
      if (/变更|已更新|已切换|重新生成|其他标签页/u.test(detail)) {
        return this.update(entry, 'error', '数据已更新，请重新生成预览。', 'STALE_PREVIEW');
      }
      return this.update(entry, 'error', '无法保存，请检查当前学期和草稿，再重新生成预览。', 'CONFLICT');
    }
  }

  reject(id: string) {
    const entry = this.entries.get(id);
    if (entry?.proposal.status === 'awaiting_confirmation') this.update(entry, 'rejected');
  }

  invalidate(filter: (entry: { channel: AbortSignal; termId: string }) => boolean) {
    this.entries.forEach((entry) => {
      if (entry.proposal.status === 'awaiting_confirmation' &&
          filter({ channel: entry.channel, termId: entry.proposal.termId })) {
        this.update(entry, 'expired');
      }
    });
  }
}

export const agentProposals = new AgentProposals();
