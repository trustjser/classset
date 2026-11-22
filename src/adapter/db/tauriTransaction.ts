import type { DbTransactionClient, QueryResult } from './databaseAdapter';

type NativeInvoke = (
  command: string,
  args?: Record<string, unknown>
) => Promise<unknown>;

export async function runTauriTransaction<T>(
  invoke: NativeInvoke,
  fn: (tx: DbTransactionClient) => Promise<T>
): Promise<T> {
  const id = await invoke('begin_sqlite_transaction');
  if (typeof id !== 'number') throw new Error('无法建立 SQLite 事务');

  const tx: DbTransactionClient = {
    select: async <Row>(sql: string, values: unknown[] = []) =>
      (await invoke('select_sqlite_transaction', { id, sql, values })) as Row[],
    execute: async (sql: string, values: unknown[] = []) =>
      (await invoke('execute_sqlite_transaction', { id, sql, values })) as QueryResult,
  };

  try {
    const result = await fn(tx);
    await invoke('commit_sqlite_transaction', { id });
    return result;
  } catch (error) {
    try {
      await invoke('rollback_sqlite_transaction', { id });
    } catch {
      // 保留最初的写入或提交错误。
    }
    throw error;
  }
}
