import type { FreeSlot, StageRoutine } from '@/domain/models';
import { useAppStore } from '@/store/useAppStore';

export interface RoutineDraftSnapshot {
  routines: Record<string, StageRoutine>;
  freeSlots: Record<string, FreeSlot | null>;
  freeSlotBaselines: Record<string, FreeSlot | null>;
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

export function captureRoutineDraftSnapshot(
  termId: string,
  stageIds: string[]
): RoutineDraftSnapshot {
  const state = useAppStore.getState();
  const routines = Object.fromEntries(
    stageIds.flatMap((stageId) => {
      const draft = state.routineDraftsByStage[stageId];
      return draft ? [[stageId, draft] as const] : [];
    })
  );
  return clone({
    routines,
    freeSlots: state.freeSlotDraftsByTerm[termId] ?? {},
    freeSlotBaselines: state.freeSlotBaselinesByTerm[termId] ?? {},
  });
}

export function restoreRoutineDraftSnapshot(
  termId: string,
  stageIds: string[],
  snapshot: RoutineDraftSnapshot
): void {
  useAppStore.getState().restoreTermDraftSnapshot(
    termId,
    stageIds,
    clone(snapshot.routines),
    clone(snapshot.freeSlots),
    clone(snapshot.freeSlotBaselines)
  );
}
