import { expect, it, vi } from 'vitest';
import { registerWebMcpTools } from '@/agent/webMcpAdapter';

it('注册只读工具并在关闭时取消注册', async () => {
  const registerTool = vi.fn();
  const service = { listTools: () => [{ name: 'read', description: '查询', inputSchema: { type: 'object' } }], callTool: vi.fn().mockResolvedValue('ok') };
  const dispose = await registerWebMcpTools(service, { registerTool });
  expect(registerTool).toHaveBeenCalledOnce();
  const [tool, options] = registerTool.mock.calls[0];
  await expect(tool.execute({})).resolves.toBe('ok');
  dispose();
  expect(options.signal.aborted).toBe(true);
});
