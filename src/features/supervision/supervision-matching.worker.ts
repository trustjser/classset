import { SupervisionAllocator } from '@/domain/supervisionAllocator';
import type { SupervisionDraft } from '@/domain/supervision';
import type { ScheduleData } from '@/domain/scheduling';

export interface SupervisionMatchRequest {
  snapshot: ScheduleData;
  draft: SupervisionDraft;
}

export type SupervisionMatchResponse =
  | { type: 'complete'; draft: SupervisionDraft }
  | { type: 'error'; message: string };

self.onmessage = ({ data: request }: MessageEvent<SupervisionMatchRequest>) => {
  try {
    const draft = new SupervisionAllocator().fill(request.snapshot, request.draft);
    const response: SupervisionMatchResponse = { type: 'complete', draft };
    self.postMessage(response);
  } catch (error) {
    const response: SupervisionMatchResponse = {
      type: 'error',
      message: error instanceof Error ? error.message : String(error),
    };
    self.postMessage(response);
  }
};
