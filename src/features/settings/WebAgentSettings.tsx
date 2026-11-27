import { useId } from 'react';
import { Switch } from '@/components/ui/switch';
import { useWebAgent } from '@/agent/useWebAgent';
import { useAgentSettings } from '@/agent/agentSettings';
import { getWebMcpContext } from '@/agent/webMcpAdapter';

export function WebAgentSettings() {
  const id = useId();
  const autoWriteId = useId();
  const { enabled, status, setEnabled } = useWebAgent();
  const { autoApplyWrites, setAutoApplyWrites } = useAgentSettings();
  const supported = Boolean(getWebMcpContext());

  return (
    <section aria-labelledby={id} className="rounded-card bg-surface px-5 py-5 sm:px-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 id={id} className="text-base font-semibold text-ink">浏览器 AI</h2>
          <p className="mt-1 text-sm text-ink-secondary">
            开启后，浏览器 AI 可查询学期和实际课表，也可提交草稿课节移动预览。查询结果可能包含教师姓名。
          </p>
        </div>
        <Switch aria-labelledby={id} checked={enabled} disabled={!supported} onCheckedChange={setEnabled} />
      </div>
      <div className={`mt-4 flex items-start justify-between gap-4 border-t border-border pt-4 ${supported && enabled ? '' : 'opacity-60'}`}>
        <div>
          <h3 id={autoWriteId} className="text-sm font-medium text-ink">自动写入（免人工确认）</h3>
          <p className="mt-1 text-xs leading-5 text-ink-secondary">
            开启后，浏览器 AI 提交的写入操作将直接保存到本地数据库并刷新页面，不再需要手动点击确认。
            {(!supported || !enabled) && '（需先开启上方浏览器 AI（WebMCP）后才可配置）'}
          </p>
        </div>
        <Switch aria-labelledby={autoWriteId} checked={autoApplyWrites} disabled={!supported || !enabled} onCheckedChange={setAutoApplyWrites} />
      </div>
      <p role="status" className="mt-2 text-sm text-ink-secondary">
        {!supported && '当前浏览器不支持 WebMCP。'}
        {supported && status === 'starting' && '正在注册查询工具…'}
        {supported && status === 'ready' && '浏览器 AI 已连接。'}
        {supported && status === 'failed' && '注册失败，可以重新开启。'}
      </p>
    </section>
  );
}
