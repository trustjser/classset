import type { CalendarException } from '@/domain/models';
import type { ScheduleData } from '@/domain/scheduling';
import type { SchedulePosition, SupervisionVersion } from '@/domain/supervision';
import {
  type ActualChangePreview,
  type ActualLesson,
  type ActualSupervision,
  buildSchedulingProblem,
  projectTemporaryTimetable,
  type SchedulingProblem,
  type TemporaryAdjustmentRecord,
  TemporaryTimetableState,
  validateTemporaryCancellation,
} from '@/domain/actualTimetable';
import {
  buildWeekMoveCandidates,
  buildWeekSwapCandidates,
  type CandidateMoveSlot,
} from '@/features/temporaryAdjustments/temporaryAdjustmentsHelpers';

export interface SerializedTemporaryState {
  snapshot: ScheduleData;
  exceptions: CalendarException[];
  records: TemporaryAdjustmentRecord[];
  lessons: ActualLesson[];
  revision: string;
  reconciliationPending: boolean;
  supervisions: ActualSupervision[];
  supervisionVersions: SupervisionVersion[];
  hasSupervisionCalendar: boolean;
}

export type TemporaryWorkerRequest =
  | {
      id: number;
      type: 'syncState';
      state: SerializedTemporaryState;
    }
  | {
      id: number;
      type: 'projectTimetable';
      snapshot: ScheduleData;
      exceptions: CalendarException[];
      records: TemporaryAdjustmentRecord[];
      supervisionVersions: SupervisionVersion[];
      revision: string;
      reconciliationPending: boolean;
      hasSupervisionCalendar: boolean;
    }
  | {
      id: number;
      type: 'computeWeekCandidates';
      sourceKey: string;
      kind: 'swap' | 'move';
      stageId?: string;
      visibleDates: string[];
    }
  | {
      id: number;
      type: 'computeSubstituteCandidates';
      sourceKey: string;
      targetSubjectId: string;
    }
  | {
      id: number;
      type: 'computeAdjustmentPreview';
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
      excludedDates?: string[];
    }
  | {
      id: number;
      type: 'validateCancellation';
      recordId: string;
    };

export type TemporaryWorkerResponse =
  | {
      id: number;
      type: 'syncStateResult';
    }
  | {
      id: number;
      type: 'projectTimetableResult';
      lessons: ActualLesson[];
      records: TemporaryAdjustmentRecord[];
      supervisions: ActualSupervision[];
    }
  | {
      id: number;
      type: 'computeWeekCandidatesResult';
      swapEntries: Array<[string, ActualChangePreview]>;
      moveEntries: Array<[string, CandidateMoveSlot]>;
    }
  | {
      id: number;
      type: 'computeSubstituteCandidatesResult';
      previewsByTeacherId: Record<string, ActualChangePreview>;
    }
  | {
      id: number;
      type: 'computeAdjustmentPreviewResult';
      preview: ActualChangePreview;
    }
  | {
      id: number;
      type: 'validateCancellationResult';
      blocker: string | null;
    }
  | {
      id: number;
      type: 'error';
      message: string;
    };

let cachedState: TemporaryTimetableState | null = null;
let cachedProblem: SchedulingProblem | null = null;

function hydrateState(raw: SerializedTemporaryState): void {
  const supervisions = raw.supervisions.map((s) => ({
    ...s,
    eligibleTeacherIds:
      s.eligibleTeacherIds instanceof Set
        ? s.eligibleTeacherIds
        : new Set(Array.isArray(s.eligibleTeacherIds) ? s.eligibleTeacherIds : []),
  }));
  cachedState = new TemporaryTimetableState({
    snapshot: raw.snapshot,
    exceptions: raw.exceptions,
    records: raw.records,
    lessons: raw.lessons,
    revision: raw.revision,
    reconciliationPending: raw.reconciliationPending,
    supervisions,
    supervisionVersions: raw.supervisionVersions,
    hasSupervisionCalendar: raw.hasSupervisionCalendar,
  });
  cachedProblem = buildSchedulingProblem(raw.snapshot);
}

self.onmessage = ({ data: req }: MessageEvent<TemporaryWorkerRequest>) => {
  try {
    switch (req.type) {
      case 'syncState': {
        hydrateState(req.state);
        const res: TemporaryWorkerResponse = {
          id: req.id,
          type: 'syncStateResult',
        };
        self.postMessage(res);
        break;
      }

      case 'projectTimetable': {
        const projected = projectTemporaryTimetable({
          snapshot: req.snapshot,
          exceptions: req.exceptions,
          records: req.records,
          supervisionVersions: req.supervisionVersions,
        });
        cachedState = new TemporaryTimetableState({
          snapshot: req.snapshot,
          exceptions: req.exceptions,
          records: projected.records,
          lessons: projected.lessons,
          supervisions: projected.supervisions,
          supervisionVersions: req.supervisionVersions,
          hasSupervisionCalendar: req.hasSupervisionCalendar,
          revision: req.revision,
          reconciliationPending: req.reconciliationPending,
        });
        cachedProblem = buildSchedulingProblem(req.snapshot);
        const res: TemporaryWorkerResponse = {
          id: req.id,
          type: 'projectTimetableResult',
          lessons: projected.lessons,
          records: projected.records,
          supervisions: projected.supervisions,
        };
        self.postMessage(res);
        break;
      }

      case 'computeWeekCandidates': {
        if (!cachedState || !cachedProblem) {
          throw new Error('Worker 状态尚未同步');
        }
        const source = cachedState.lessons.find((l) => l.key === req.sourceKey);
        if (!source) {
          const res: TemporaryWorkerResponse = {
            id: req.id,
            type: 'computeWeekCandidatesResult',
            swapEntries: [],
            moveEntries: [],
          };
          self.postMessage(res);
          break;
        }
        if (req.kind === 'swap') {
          const map = buildWeekSwapCandidates(
            cachedState,
            cachedProblem,
            source,
            req.visibleDates
          );
          const res: TemporaryWorkerResponse = {
            id: req.id,
            type: 'computeWeekCandidatesResult',
            swapEntries: Array.from(map.entries()),
            moveEntries: [],
          };
          self.postMessage(res);
        } else {
          const routine = req.stageId
            ? cachedState.snapshot.routines.find((r) => r.stageId === req.stageId)
            : cachedState.snapshot.routines[0];
          const map = buildWeekMoveCandidates(
            cachedState,
            cachedProblem,
            source,
            routine,
            req.visibleDates
          );
          const res: TemporaryWorkerResponse = {
            id: req.id,
            type: 'computeWeekCandidatesResult',
            swapEntries: [],
            moveEntries: Array.from(map.entries()),
          };
          self.postMessage(res);
        }
        break;
      }

      case 'computeSubstituteCandidates': {
        if (!cachedState || !cachedProblem) {
          throw new Error('Worker 状态尚未同步');
        }
        const source = cachedState.lessons.find((l) => l.key === req.sourceKey);
        const previewsByTeacherId: Record<string, ActualChangePreview> = {};
        if (source) {
          for (const teacher of cachedState.snapshot.teachers) {
            if (teacher.id === source.item.teacherId) continue;
            previewsByTeacherId[teacher.id] = cachedState.previewSubstitute(
              {
                sourceKey: source.key,
                teacherId: teacher.id,
                subjectId: req.targetSubjectId,
              },
              cachedProblem
            );
          }
        }
        const res: TemporaryWorkerResponse = {
          id: req.id,
          type: 'computeSubstituteCandidatesResult',
          previewsByTeacherId,
        };
        self.postMessage(res);
        break;
      }

      case 'computeAdjustmentPreview': {
        if (!cachedState || !cachedProblem) {
          throw new Error('Worker 状态尚未同步');
        }
        const excludedSet = new Set(req.excludedDates ?? []);
        let preview: ActualChangePreview = {
          changes: [],
          errors: ['未选择完整的调整目标'],
          skippedDates: [],
        };
        if (req.kind === 'swap' && req.swapKey) {
          preview = cachedState.previewSwap(
            {
              firstKey: req.sourceKey,
              secondKey: req.swapKey,
              reason: req.reason,
              rangeStart: req.rangeStart,
              rangeEnd: req.rangeEnd,
              excludedDates: excludedSet,
            },
            cachedProblem
          );
        } else if (req.kind === 'move' && req.moveDate && req.movePosition) {
          preview = cachedState.previewMove(
            {
              sourceKey: req.sourceKey,
              targetDate: req.moveDate,
              targetPosition: req.movePosition,
              reason: req.reason,
              rangeStart: req.rangeStart,
              rangeEnd: req.rangeEnd,
              excludedDates: excludedSet,
            },
            cachedProblem
          );
        } else if (req.kind === 'substitute' && req.substituteTeacherId) {
          preview = cachedState.previewSubstitute(
            {
              sourceKey: req.sourceKey,
              teacherId: req.substituteTeacherId,
              subjectId: req.substituteSubjectId,
              reason: req.reason,
              rangeStart: req.rangeStart,
              rangeEnd: req.rangeEnd,
              excludedDates: excludedSet,
            },
            cachedProblem
          );
        }
        const res: TemporaryWorkerResponse = {
          id: req.id,
          type: 'computeAdjustmentPreviewResult',
          preview,
        };
        self.postMessage(res);
        break;
      }

      case 'validateCancellation': {
        if (!cachedState) {
          throw new Error('Worker 状态尚未同步');
        }
        const idx = cachedState.records.findIndex(
          (r) => r.id === req.recordId
        );
        let blocker: string | null = null;
        if (idx === -1) {
          blocker = '找不到该调整记录';
        } else {
          try {
            validateTemporaryCancellation(
              cachedState,
              cachedState.records[idx],
              idx
            );
          } catch (e) {
            blocker = e instanceof Error ? e.message : String(e);
          }
        }
        const res: TemporaryWorkerResponse = {
          id: req.id,
          type: 'validateCancellationResult',
          blocker,
        };
        self.postMessage(res);
        break;
      }
    }
  } catch (error) {
    const res: TemporaryWorkerResponse = {
      id: req.id,
      type: 'error',
      message: error instanceof Error ? error.message : String(error),
    };
    self.postMessage(res);
  }
};
