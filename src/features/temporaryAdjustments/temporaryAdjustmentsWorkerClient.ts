import type { SchedulePosition } from '@/domain/supervision';
import {
  type ActualChangePreview,
  buildSchedulingProblem,
  type TemporaryTimetableState,
  validateTemporaryCancellation,
} from '@/domain/actualTimetable';
import {
  buildWeekMoveCandidates,
  buildWeekSwapCandidates,
  type CandidateMoveSlot,
} from '@/features/temporaryAdjustments/temporaryAdjustmentsHelpers';
import type {
  TemporaryWorkerRequest,
  TemporaryWorkerResponse,
} from './temporary-adjustments.worker';

class TemporaryAdjustmentsWorkerClient {
  private worker: Worker | null = null;
  private nextRequestId = 1;
  private syncedRevision: string | null = null;
  private pending = new Map<
    number,
    {
      resolve: (res: TemporaryWorkerResponse) => void;
      reject: (err: Error) => void;
    }
  >();

  private getWorker(): Worker | null {
    if (typeof Worker === 'undefined') return null;
    if (!this.worker) {
      this.worker = new Worker(
        new URL('./temporary-adjustments.worker.ts', import.meta.url),
        { type: 'module' }
      );
      this.worker.onmessage = ({
        data,
      }: MessageEvent<TemporaryWorkerResponse>) => {
        const entry = this.pending.get(data.id);
        if (!entry) return;
        this.pending.delete(data.id);
        if (data.type === 'error') {
          entry.reject(new Error(data.message));
        } else {
          entry.resolve(data);
        }
      };
      this.worker.onerror = (event) => {
        const err = new Error(event.message || '调代课 Worker 执行出错');
        for (const entry of this.pending.values()) {
          entry.reject(err);
        }
        this.pending.clear();
        this.worker?.terminate();
        this.worker = null;
        this.syncedRevision = null;
      };
    }
    return this.worker;
  }

  private sendRequest(
    buildReq: (id: number) => TemporaryWorkerRequest
  ): Promise<TemporaryWorkerResponse> {
    const worker = this.getWorker();
    if (!worker) {
      return Promise.reject(new Error('当前环境不支持 Web Worker'));
    }
    const id = this.nextRequestId++;
    const request = buildReq(id);
    return new Promise<TemporaryWorkerResponse>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      worker.postMessage(request);
    });
  }

  async ensureSynced(state: TemporaryTimetableState): Promise<void> {
    if (this.syncedRevision === state.revision && this.worker) {
      return;
    }
    await this.sendRequest((id) => ({
      id,
      type: 'syncState',
      state: {
        snapshot: state.snapshot,
        exceptions: state.exceptions,
        records: state.records,
        lessons: state.lessons,
        revision: state.revision,
        reconciliationPending: state.reconciliationPending,
        supervisions: state.supervisions,
        supervisionVersions: state.supervisionVersions,
        hasSupervisionCalendar: state.hasSupervisionCalendar,
      },
    }));
    this.syncedRevision = state.revision;
  }

  async computeWeekCandidates(params: {
    state: TemporaryTimetableState;
    sourceKey: string;
    kind: 'swap' | 'move';
    stageId?: string;
    visibleDates: string[];
  }): Promise<{
    swapCandidates: Map<string, ActualChangePreview>;
    moveCandidates: Map<string, CandidateMoveSlot>;
  }> {
    const { state, sourceKey, kind, stageId, visibleDates } = params;
    if (typeof Worker === 'undefined') {
      const problem = buildSchedulingProblem(state.snapshot);
      const source = state.lessons.find((l) => l.key === sourceKey);
      if (!source) {
        return { swapCandidates: new Map(), moveCandidates: new Map() };
      }
      if (kind === 'swap') {
        return {
          swapCandidates: buildWeekSwapCandidates(
            state,
            problem,
            source,
            visibleDates
          ),
          moveCandidates: new Map(),
        };
      }
      const routine = stageId
        ? state.snapshot.routines.find((r) => r.stageId === stageId)
        : state.snapshot.routines[0];
      return {
        swapCandidates: new Map(),
        moveCandidates: buildWeekMoveCandidates(
          state,
          problem,
          source,
          routine,
          visibleDates
        ),
      };
    }

    await this.ensureSynced(state);
    const res = await this.sendRequest((id) => ({
      id,
      type: 'computeWeekCandidates',
      sourceKey,
      kind,
      stageId,
      visibleDates,
    }));
    if (res.type !== 'computeWeekCandidatesResult') {
      throw new Error('Worker 返回类型不匹配');
    }
    return {
      swapCandidates: new Map(res.swapEntries),
      moveCandidates: new Map(res.moveEntries),
    };
  }

  async computeSubstituteCandidates(params: {
    state: TemporaryTimetableState;
    sourceKey: string;
    targetSubjectId: string;
  }): Promise<Record<string, ActualChangePreview>> {
    const { state, sourceKey, targetSubjectId } = params;
    if (typeof Worker === 'undefined') {
      const problem = buildSchedulingProblem(state.snapshot);
      const source = state.lessons.find((l) => l.key === sourceKey);
      const result: Record<string, ActualChangePreview> = {};
      if (source) {
        for (const t of state.snapshot.teachers) {
          if (t.id === source.item.teacherId) continue;
          result[t.id] = state.previewSubstitute(
            {
              sourceKey,
              teacherId: t.id,
              subjectId: targetSubjectId,
            },
            problem
          );
        }
      }
      return result;
    }

    await this.ensureSynced(state);
    const res = await this.sendRequest((id) => ({
      id,
      type: 'computeSubstituteCandidates',
      sourceKey,
      targetSubjectId,
    }));
    if (res.type !== 'computeSubstituteCandidatesResult') {
      throw new Error('Worker 返回类型不匹配');
    }
    return res.previewsByTeacherId;
  }

  async computeAdjustmentPreview(params: {
    state: TemporaryTimetableState;
    kind: 'swap' | 'move' | 'substitute';
    sourceKey: string;
    swapKey?: string | null;
    moveDate?: string | null;
    movePosition?: SchedulePosition | null;
    substituteTeacherId?: string | null;
    substituteSubjectId?: string | null;
    reason?: string;
    rangeStart?: string | null;
    rangeEnd?: string | null;
    excludedDates?: Set<string>;
  }): Promise<ActualChangePreview> {
    const {
      state,
      kind,
      sourceKey,
      swapKey,
      moveDate,
      movePosition,
      substituteTeacherId,
      substituteSubjectId,
      reason,
      rangeStart,
      rangeEnd,
      excludedDates,
    } = params;

    if (typeof Worker === 'undefined') {
      const problem = buildSchedulingProblem(state.snapshot);
      if (kind === 'swap' && swapKey) {
        return state.previewSwap(
          {
            firstKey: sourceKey,
            secondKey: swapKey,
            reason,
            rangeStart,
            rangeEnd,
            excludedDates,
          },
          problem
        );
      }
      if (kind === 'move' && moveDate && movePosition) {
        return state.previewMove(
          {
            sourceKey,
            targetDate: moveDate,
            targetPosition: movePosition,
            reason,
            rangeStart,
            rangeEnd,
            excludedDates,
          },
          problem
        );
      }
      if (kind === 'substitute' && substituteTeacherId) {
        return state.previewSubstitute(
          {
            sourceKey,
            teacherId: substituteTeacherId,
            subjectId: substituteSubjectId,
            reason,
            rangeStart,
            rangeEnd,
            excludedDates,
          },
          problem
        );
      }
      return { changes: [], errors: ['未选择完整的调整目标'], skippedDates: [] };
    }

    await this.ensureSynced(state);
    const res = await this.sendRequest((id) => ({
      id,
      type: 'computeAdjustmentPreview',
      kind,
      sourceKey,
      swapKey,
      moveDate,
      movePosition,
      substituteTeacherId,
      substituteSubjectId,
      reason,
      rangeStart,
      rangeEnd,
      excludedDates: excludedDates ? Array.from(excludedDates) : [],
    }));
    if (res.type !== 'computeAdjustmentPreviewResult') {
      throw new Error('Worker 返回类型不匹配');
    }
    return res.preview;
  }

  async validateCancellation(params: {
    state: TemporaryTimetableState;
    recordId: string;
  }): Promise<string | null> {
    const { state, recordId } = params;
    if (typeof Worker === 'undefined') {
      const idx = state.records.findIndex((r) => r.id === recordId);
      if (idx === -1) return '找不到该调整记录';
      try {
        validateTemporaryCancellation(state, state.records[idx], idx);
        return null;
      } catch (e) {
        return e instanceof Error ? e.message : String(e);
      }
    }

    await this.ensureSynced(state);
    const res = await this.sendRequest((id) => ({
      id,
      type: 'validateCancellation',
      recordId,
    }));
    if (res.type !== 'validateCancellationResult') {
      throw new Error('Worker 返回类型不匹配');
    }
    return res.blocker;
  }
}

export const temporaryAdjustmentsWorkerClient =
  new TemporaryAdjustmentsWorkerClient();
