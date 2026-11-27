import { useEffect } from 'react';
import { create } from 'zustand';
import { AgentService, agentErrorResult } from './agentService';
import { agentProposals } from './agentProposals';
import { getWebMcpContext, registerWebMcpTools } from './webMcpAdapter';

type AgentStatus = 'disabled' | 'starting' | 'ready' | 'unavailable' | 'failed';

interface WebAgentState {
  enabled: boolean;
  status: AgentStatus;
  setEnabled(enabled: boolean): void;
}

export const useWebAgent = create<WebAgentState>((set) => ({
  enabled: false,
  status: 'disabled',
  setEnabled: (enabled) => set({ enabled, status: enabled ? 'starting' : 'disabled' }),
}));

export function useWebAgentRegistration(available: boolean) {
  const enabled = useWebAgent((state) => state.enabled);
  useEffect(() => {
    if (!available || !enabled) return;

    const context = getWebMcpContext();
    if (!context) {
      useWebAgent.setState({ enabled: false, status: 'unavailable' });
      return;
    }

    const controller = new AbortController();
    const service = new AgentService(undefined, controller.signal);
    let disposed = false;
    const adapter = {
      listTools: () => service.listTools(),
      callTool: (name: string, args: unknown, signal?: AbortSignal) =>
        service.callTool(name, args, signal).catch(agentErrorResult),
    };
    void registerWebMcpTools(adapter, context, controller).then(
      () => {
        if (!controller.signal.aborted) useWebAgent.setState({ status: 'ready' });
      },
      () => {
        if (useWebAgent.getState().enabled && !disposed) {
          useWebAgent.setState({ enabled: false, status: 'failed' });
        }
      },
    );
    return () => {
      disposed = true;
      controller.abort();
      agentProposals.invalidate(({ channel }) => channel === controller.signal);
    };
  }, [available, enabled]);
}
