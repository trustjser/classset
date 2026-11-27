import { useId, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Switch } from '@/components/ui/switch';
import { useDesktopAgent } from '@/agent/desktopAgent';
import { useAgentSettings } from '@/agent/agentSettings';

export const CLASSSET_SKILL_URL = 'https://classset.app/skills/classset-scheduling/SKILL.md';

export function buildAgentSetupPrompt(configJson: string): string {
  return [
    '请帮我把「课集 (ClassSet)」本地 MCP 服务配置到你的连接器中，并安装课集排课技能：',
    '',
    '1. 配置 MCP 服务：',
    '如果你支持自动修改 MCP 配置文件（如 mcp.json / 客户端设置），请直接将以下 `classset` 服务添加到 `mcpServers` 中并重载连接；如果仅支持手动添加，请按以下参数填写或引导我完成：',
    '',
    '```json',
    configJson,
    '```',
    '',
    '2. 下载并安装课集技能（Skill）：',
    `请从课集官网获取技能文档：${CLASSSET_SKILL_URL}`,
    '- 如果你支持技能（Skills）管理，请将下载到的 `SKILL.md` 安装并启用为名为 `classset-scheduling` 的技能；',
    '- 如果你不支持独立的 Skill 系统，请先完整阅读该文档内容并作为后续操作课集的行为规范。',
    '',
    '3. 运行与交互约定：',
    '- 协议类型：Streamable HTTP (`type: "http"`，需携带 `Authorization: Bearer ...` 请求头)。',
    '- 调用前请保持课集桌面端主窗口打开可见；若我重新开关了课集中的 AI 连接，端口与令牌会重新生成，届时需同步更新配置。',
    '- 所有写入类工具均采用“预览提案 + 课集内确认”机制，调用后请提醒我在课集「设置 -> 待确认操作」中点击确认保存。',
  ].join('\n');
}


export function DesktopAgentSettings() {
  const id = useId();
  const autoWriteId = useId();
  const { connection, busy, error, toggle } = useDesktopAgent();
  const { autoApplyWrites, setAutoApplyWrites } = useAgentSettings();
  const [feedback, setFeedback] = useState('');

  const config = connection && JSON.stringify({
    mcpServers: {
      classset: {
        type: 'http',
        url: connection.url,
        headers: { Authorization: `Bearer ${connection.token}` },
      },
    },
  }, null, 2);

  const setupPrompt = config ? buildAgentSetupPrompt(config) : null;

  async function copyText(text: string | null, successMessage: string) {
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      setFeedback(successMessage);
    } catch {
      setFeedback('无法访问剪贴板，可以展开下方内容并手动复制。');
    }
  }

  return (
    <section aria-labelledby={id} className="rounded-card bg-surface px-5 py-5 sm:px-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 id={id} className="text-base font-semibold text-ink">AI Agent 连接（MCP）</h2>
        </div>
        <Switch aria-labelledby={id} checked={Boolean(connection)} disabled={busy}
          onCheckedChange={() => { setFeedback(''); void toggle(); }} />
      </div>
      <div className={`mt-4 flex items-start justify-between gap-4 border-t border-border pt-4 ${connection ? '' : 'opacity-60'}`}>
        <div>
          <h3 id={autoWriteId} className="text-sm font-medium text-ink">自动写入（免人工确认）</h3>
          <p className="mt-1 text-xs leading-5 text-ink-secondary">
            开启后，AI Agent 调用写入类工具将直接保存到本地数据库并刷新页面，不再需要手动点击确认；关闭时每次修改均需在下方待确认列表中审批。
            {!connection && '（需先开启上方 AI Agent 连接（MCP）后才可配置）'}
          </p>
        </div>
        <Switch aria-labelledby={autoWriteId} checked={autoApplyWrites}
          disabled={!connection || busy}
          onCheckedChange={setAutoApplyWrites} />
      </div>
      {config && setupPrompt && (
        <div className="mt-4 space-y-3">
          <p className="text-sm text-ink-secondary">
            复制下方自动配置提示词发送给你的 AI Agent 即可引导其自动接入 MCP 并安装课集技能.
          </p>
          <div className="space-y-2 pt-1">
            <details className="text-sm">
              <summary className="cursor-pointer select-none text-ink-secondary hover:text-ink">查看自动配置提示词</summary>
              <pre className="mt-2 whitespace-pre-wrap break-words rounded-control bg-canvas p-3 text-xs leading-relaxed text-ink select-auto">{setupPrompt}</pre>
            </details>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={() => void copyText(setupPrompt, '已复制自动配置提示词（含 MCP 配置与技能安装指引），可直接粘贴发送给你的 AI Agent。')}>
              复制自动配置提示词
            </Button>
          </div>
        </div>
      )}
      {(feedback || error) && <p role="status" className="mt-2 text-sm text-ink-secondary">{error ?? feedback}</p>}
    </section>
  );
}
