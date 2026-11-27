import { expect, it, vi } from 'vitest';
import { AgentProposals } from '@/agent/agentProposals';

it('提案由原连接查询，应用确认后只提交一次', async () => {
  const proposals = new AgentProposals();
  const channel = new AbortController();
  const other = new AbortController();
  const commit = vi.fn(async () => {});
  const proposal = proposals.create('term', channel.signal, { changes: [] }, commit);
  expect(commit).not.toHaveBeenCalled();
  expect(proposals.status(proposal.actionId, other.signal)).toMatchObject({ status: 'error' });
  await Promise.all([proposals.confirm(proposal.actionId), proposals.confirm(proposal.actionId)]);
  expect(commit).toHaveBeenCalledOnce();
  expect(proposals.status(proposal.actionId, channel.signal)).toMatchObject({ status: 'committed' });
});

it('关闭连接后拒绝确认', async () => {
  const proposals = new AgentProposals();
  const channel = new AbortController();
  const commit = vi.fn(async () => {});
  const proposal = proposals.create('term', channel.signal, {}, commit);
  channel.abort();
  await proposals.confirm(proposal.actionId);
  expect(commit).not.toHaveBeenCalled();
});
