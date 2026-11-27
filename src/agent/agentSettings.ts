import { create } from 'zustand';

const AUTO_APPLY_STORAGE_KEY = 'classset_agent_auto_apply_writes';

function loadInitialAutoApply(): boolean {
  try {
    return localStorage.getItem(AUTO_APPLY_STORAGE_KEY) === 'true';
  } catch {
    return false;
  }
}

interface AgentSettingsState {
  autoApplyWrites: boolean;
  setAutoApplyWrites(enabled: boolean): void;
}

export const useAgentSettings = create<AgentSettingsState>((set) => ({
  autoApplyWrites: loadInitialAutoApply(),
  setAutoApplyWrites(enabled) {
    try {
      localStorage.setItem(AUTO_APPLY_STORAGE_KEY, String(enabled));
    } catch {
      // ignore storage errors in restricted environments
    }
    set({ autoApplyWrites: enabled });
  },
}));

export function getAutoApplyWrites(): boolean {
  return useAgentSettings.getState().autoApplyWrites;
}
