import type { SolveRequest, SolveResponse } from '@/features/scheduling/schedule.worker';

export function solveAgentSchedule(request: SolveRequest, signal: AbortSignal) {
  if (signal.aborted) return Promise.reject(new Error('排课请求已取消'));
  const worker = new Worker(new URL('../features/scheduling/schedule.worker.ts', import.meta.url), { type: 'module' });
  let abort: () => void;
  return new Promise<Extract<SolveResponse, { type: 'complete' }>['result']>((resolve, reject) => {
    abort = () => reject(new Error('排课请求已取消'));
    signal.addEventListener('abort', abort, { once: true });
    worker.onmessage = ({ data }: MessageEvent<SolveResponse>) => {
      if (data.type === 'complete') resolve(data.result);
      if (data.type === 'error') reject(new Error(data.message));
    };
    worker.onerror = () => reject(new Error('排课计算失败'));
    worker.postMessage(request);
  }).finally(() => {
    signal.removeEventListener('abort', abort);
    worker.terminate();
  });
}
