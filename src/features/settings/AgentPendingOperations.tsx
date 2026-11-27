import { useId, useState, useSyncExternalStore } from 'react';
import { agentProposals } from '@/agent/agentProposals';
import { Button } from '@/components/ui/button';
import type { ClassSetAgentToolExecutor } from '@/agent/domain/agentToolExecutor';
import { useAppStore } from '@/store/useAppStore';

type MovePreview = Awaited<ReturnType<ClassSetAgentToolExecutor['prepareMoveOrSwapLesson']>>['preview'];
type SolvePreview = Awaited<ReturnType<ClassSetAgentToolExecutor['prepareAutoSchedule']>>['preview'];
type PendingPreview = (MovePreview & { toolName: 'classset_move_or_swap_lesson' })
  | (SolvePreview & { toolName: 'classset_run_auto_schedule' })
  | {
      toolName:
        | 'classset_batch_configure_classes_and_stages'
        | 'classset_batch_configure_subjects_and_quotas'
        | 'classset_batch_configure_teachers_and_assignments'
        | 'classset_configure_schedule_rules'
        | 'classset_cancel_temporary_adjustment';
      notes: string[];
    }
  | { toolName: 'classset_apply_temporary_adjustment'; notes: string[]; skippedDates: string[] }
  | (Awaited<ReturnType<ClassSetAgentToolExecutor['prepareCreateSupervisionPosts']>>['preview'] & { toolName: 'classset_batch_create_supervision_posts' })
  | (Awaited<ReturnType<ClassSetAgentToolExecutor['prepareAllocateSupervision']>>['preview'] & { toolName: 'classset_auto_allocate_supervision' })
  | (Awaited<ReturnType<ClassSetAgentToolExecutor['preparePublishSupervision']>>['preview'] & { toolName: 'classset_publish_supervision_version' });

function location(item: MovePreview['changes'][number]['before']) {
  if (item?.weekday == null) return '暂放区';
  const weekday = ['一', '二', '三', '四', '五', '六', '日'][item.weekday - 1];
  return `周${weekday} · 第 ${item.lessonIndex} 节`;
}

function describeOperation(preview: PendingPreview): { title: string; summary?: string; changes: string[] } {
  switch (preview.toolName) {
    case 'classset_batch_configure_classes_and_stages':
      return { title: '批量配置班级与学段', changes: preview.notes };
    case 'classset_batch_configure_subjects_and_quotas':
      return { title: '批量配置科目与节数', changes: preview.notes };
    case 'classset_batch_configure_teachers_and_assignments':
      return { title: '批量配置教师与任课', changes: preview.notes };
    case 'classset_configure_schedule_rules':
      return { title: '配置排课规则', changes: preview.notes };
    case 'classset_cancel_temporary_adjustment':
      return { title: '撤销调代课', changes: preview.notes };
    case 'classset_apply_temporary_adjustment':
      return {
        title: '应用调代课',
        summary: preview.skippedDates.length ? `跳过 ${preview.skippedDates.join('、')}` : undefined,
        changes: preview.notes,
      };
    case 'classset_batch_create_supervision_posts':
      return {
        title: '创建带班岗位',
        changes: preview.createdPosts.map((post) =>
          `${post.name} · 星期${post.weekday} · 第 ${post.lessonIndices.join('、')} 节`),
      };
    case 'classset_auto_allocate_supervision':
      return {
        title: '分配带班教师',
        summary: `已分配 ${preview.assignedCount} 个岗位，待分配 ${preview.unassignedPostIds.length} 个。`,
        changes: preview.changes.map((row) => `${row.postName} · ${row.before} → ${row.after}`),
      };
    case 'classset_publish_supervision_version':
      return {
        title: '发布带班版本',
        summary: `${preview.effectiveDate} 生效。` +
          (preview.replacedFutureDate ? `将替换自 ${preview.replacedFutureDate} 起的后续版本。` : ''),
        changes: preview.scheduleChanges,
      };
    default: {
      const automatic = preview.toolName === 'classset_run_auto_schedule';
      return {
        title: automatic ? '自动排课' : '移动或互换草稿课节',
        summary: automatic ? `已排 ${preview.placedItems} 节，暂放 ${preview.unplacedItems.length} 节。` : preview.reason,
        changes: preview.changes.map(({ before, after, className, subjectName }) =>
          `${className} · ${subjectName} · ${location(before)} → ${location(after)}`),
      };
    }
  }
}

export function AgentPendingOperations() {
  const id = useId();
  const termId = useAppStore((state) => state.activeTermId);
  const pending = useSyncExternalStore(agentProposals.subscribe, agentProposals.getPending)
    .filter((proposal) => proposal.termId === termId);
  const [message, setMessage] = useState('');
  if (!pending.length && !message) return null;

  async function confirm(actionId: string) {
    if (useAppStore.getState().navigationGuard?.isDirty()) {
      setMessage('请先保存或放弃工作台中未保存的修改。');
      return;
    }
    const result = await agentProposals.confirm(actionId);
    if (result?.status !== 'committed') {
      setMessage(result?.message ?? '预览已失效，请重新提交请求。');
      return;
    }
    setMessage('已保存操作。');
    if (result.termId === useAppStore.getState().activeTermId) {
      try {
        await useAppStore.getState().refreshTermData(result.termId);
      } catch {
        setMessage('已保存操作。刷新失败，请重新打开课表。');
      }
    }
  }

  return (
    <section aria-labelledby={id} className="rounded-card bg-surface px-5 py-5 sm:px-6">
      <h2 id={id} className="text-base font-semibold text-ink">待确认操作</h2>
      {pending.map((proposal) => {
        const { title, summary, changes } = describeOperation(proposal.data as PendingPreview);
        return (
          <div key={proposal.actionId} className="mt-3 border-t border-control-border pt-3">
            <p className="text-sm font-medium text-ink">{title}</p>
            {summary && <p className="mt-1 text-sm text-ink-secondary">{summary}</p>}
            {changes.length > 0 && (
              <ul className="mt-2 max-h-64 space-y-1 overflow-y-auto text-sm text-ink-secondary">
                {changes.map((change, index) => <li key={index}>{change}</li>)}
              </ul>
            )}
            <div className="mt-3 flex flex-wrap gap-2">
              <Button size="sm" disabled={proposal.status === 'committing'} onClick={() => void confirm(proposal.actionId)}>
                确认保存
              </Button>
              <Button size="sm" variant="outline" disabled={proposal.status === 'committing'}
                onClick={() => { agentProposals.reject(proposal.actionId); setMessage('已拒绝操作。'); }}>
                拒绝
              </Button>
            </div>
          </div>
        );
      })}
      {message && <p className="mt-2 text-sm text-ink-secondary" role="status">{message}</p>}
    </section>
  );
}
