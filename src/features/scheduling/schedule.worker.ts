import { solveSchedule, type ScheduleData } from '../../domain/scheduling';

export interface SolveRequest {
  data: ScheduleData;
  classIds: string[];
  keepPlacements: boolean;
  allowRearrangement: boolean;
  seed: number;
}

export type SolveResponse =
  | { type: 'progress'; done: number; total: number }
  | { type: 'complete'; result: ReturnType<typeof solveSchedule> }
  | { type: 'error'; message: string };

self.onmessage = ({ data: request }: MessageEvent<SolveRequest>) => {
  try {
    const { data, classIds, keepPlacements, seed, allowRearrangement } = request;
    const attempts = data.preferences.strength === 'high' ? 3 : data.preferences.strength === 'fast' ? 1 : 2;
    const placedBefore = new Map(data.items.filter((row) => row.weekday !== null).map((row) => [row.id, row]));
    let best: ReturnType<typeof solveSchedule> | undefined;
    let candidateChecks = 0;
    for (let attempt = 0; attempt < attempts; attempt++) {
      const result = solveSchedule(data, classIds, keepPlacements, (done, total) => {
        const message: SolveResponse = { type: 'progress', done: attempt * total + done, total: attempts * total };
        self.postMessage(message);
      }, seed + attempt, allowRearrangement);
      candidateChecks += result.candidateChecks;
      const score = (candidate: typeof result) => candidate.items.reduce((sum, row) => sum +
        (row.weekday === null ? 0 : row.weekMode === 'weekly' ? 2 : 1), 0) - candidate.issues.length * 2;
      const movedCount = (candidate: typeof result) => candidate.items.filter((row) => {
        const previous = placedBefore.get(row.id);
        return previous && (row.weekday !== previous.weekday || row.stageId !== previous.stageId ||
          row.periodTypeId !== previous.periodTypeId || row.lessonIndex !== previous.lessonIndex);
      }).length;
      if (!best || score(result) > score(best) ||
          (allowRearrangement && score(result) === score(best) && movedCount(result) < movedCount(best))) best = result;
    }
    const message: SolveResponse = { type: 'complete', result: { ...best!, candidateChecks } };
    self.postMessage(message);
  } catch (error) {
    const message: SolveResponse = { type: 'error', message: String(error) };
    self.postMessage(message);
  }
};
