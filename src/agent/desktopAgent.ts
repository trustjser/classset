import { Channel, invoke } from '@tauri-apps/api/core';
import { create } from 'zustand';
import { AgentService, agentErrorResult } from './agentService';
import { agentProposals } from './agentProposals';

interface Connection {
  url: string;
  token: string;
}

interface ToolCall {
  requestId: string;
  name: string;
  arguments: unknown;
}

interface DesktopAgentState {
  connection: Connection | null;
  busy: boolean;
  error: string | null;
  toggle(): Promise<void>;
}

async function respond(service: AgentService, request: ToolCall) {
  const requestController = new AbortController();
  const timer = setTimeout(() => requestController.abort(), 25_000);
  try {
    const response = await service.callTool(request.name, request.arguments, requestController.signal).then(
      (data) => (data && typeof data === 'object' && 'status' in data ? data : { status: 'ok', data }),
      agentErrorResult,
    );
    await invoke('complete_agent_mcp_call', { requestId: request.requestId, response });
  } finally {
    clearTimeout(timer);
  }
}

let connectionController: AbortController | null = null;

export const useDesktopAgent = create<DesktopAgentState>((set, get) => ({
  connection: null,
  busy: false,
  error: null,
  async toggle() {
    if (get().busy) return;
    set({ busy: true, error: null });
    try {
      if (get().connection) {
        await invoke('stop_agent_mcp');
        const signal = connectionController?.signal;
        connectionController?.abort();
        agentProposals.invalidate(({ channel }) => channel === signal);
        connectionController = null;
        set({ connection: null });
        return;
      }
      const controller = new AbortController();
      const service = new AgentService(undefined, controller.signal);
      const channel = new Channel<ToolCall>();
      channel.onmessage = (request) => void respond(service, request).catch(() => undefined);
      const connection = await invoke<Connection>('start_agent_mcp', {
        channel,
        tools: service.listTools().map(({ name, description, inputSchema, readOnly }) =>
          ({ name, description, inputSchema, annotations: { readOnlyHint: readOnly } })),
      });
      connectionController = controller;
      set({ connection });
    } catch {
      set({ error: '无法切换本机 AI 连接，请重试。' });
    } finally {
      set({ busy: false });
    }
  },
}));
