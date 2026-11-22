import assert from 'node:assert/strict';
import test from 'node:test';

async function loadRunner() {
  const module = await import('../../src/adapter/db/tauriTransaction.ts').catch(() => null);
  assert.ok(module, '桌面端需要专用的事务执行器');
  return module.runTauriTransaction;
}

test('desktop transaction uses one native session for reads and writes', async () => {
  const run = await loadRunner();
  const calls: Array<[string, Record<string, unknown> | undefined]> = [];
  const invoke = async (command: string, args?: Record<string, unknown>) => {
    calls.push([command, args]);
    if (command === 'begin_sqlite_transaction') return 7;
    if (command === 'select_sqlite_transaction') return [{ id: 'grade-1' }];
    if (command === 'execute_sqlite_transaction') return { rowsAffected: 1 };
    if (command === 'commit_sqlite_transaction') return null;
    throw new Error('unexpected command: ' + command);
  };

  const result = await run(invoke, async (tx) => {
    const rows = await tx.select<{ id: string }>('SELECT id FROM grade_groups');
    await tx.execute('UPDATE grade_groups SET sort_order = ? WHERE id = ?', [2, rows[0].id]);
    return rows[0].id;
  });

  assert.equal(result, 'grade-1');
  assert.deepEqual(calls.map(([command]) => command), [
    'begin_sqlite_transaction',
    'select_sqlite_transaction',
    'execute_sqlite_transaction',
    'commit_sqlite_transaction',
  ]);
  assert.ok(calls.slice(1).every(([, args]) => args?.id === 7));
});

test('desktop transaction rolls back when a write fails', async () => {
  const run = await loadRunner();
  const calls: string[] = [];
  const invoke = async (command: string) => {
    calls.push(command);
    if (command === 'begin_sqlite_transaction') return 9;
    if (command === 'execute_sqlite_transaction') throw new Error('write failed');
    return null;
  };

  await assert.rejects(
    run(invoke, async (tx) => tx.execute('UPDATE grade_groups SET sort_order = 1')),
    /write failed/
  );
  assert.deepEqual(calls, [
    'begin_sqlite_transaction',
    'execute_sqlite_transaction',
    'rollback_sqlite_transaction',
  ]);
});
