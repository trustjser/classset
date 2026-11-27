import type { DatabaseSync as NativeDatabase, SQLInputValue } from 'node:sqlite';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { SCHEMA_V19_DDL, SCHEMA_V19_TABLES } from '@/adapter/db/schemaV19';

vi.mock('sql.js/dist/sql-wasm-browser.wasm?url', () => ({
  default: process.cwd() + '/node_modules/sql.js/dist/sql-wasm.wasm',
}));

const { DatabaseSync } = process.getBuiltinModule('node:sqlite')!;

let image: Uint8Array | undefined;
let failWrite = false;

beforeEach(() => {
  vi.resetModules();
  image = undefined;
  failWrite = false;
  // Only the browser's storage boundary is simulated. The adapters use real SQLite.
  vi.stubGlobal('indexedDB', {
    open() {
      const request = { result: {
        close() {},
        transaction() {
          const tx = {
            objectStore: () => ({
              get() {
                const read = { result: image, onsuccess: () => {} };
                queueMicrotask(() => read.onsuccess());
                return read;
              },
              delete() {
                queueMicrotask(() => {
                  image = undefined;
                  tx.oncomplete?.();
                });
              },
              put(bytes: Uint8Array) {
                queueMicrotask(() => {
                  if (failWrite) {
                    tx.error = new Error('磁盘已满');
                    tx.onabort?.();
                  } else {
                    image = bytes;
                    tx.oncomplete?.();
                  }
                });
              },
            }),
            error: null as Error | null,
            oncomplete: null as (() => void) | null,
            onabort: null as (() => void) | null,
          };
          return tx;
        },
      }, onsuccess: () => {} };
      queueMicrotask(() => request.onsuccess());
      return request;
    },
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
  localStorage.clear();
});

async function browserDatabase() {
  const { getDatabaseAdapter } = await import('@/adapter/db/databaseAdapter');
  const adapter = getDatabaseAdapter();
  await adapter.init();
  expect(adapter.engineStatus).toBe('wasm-sqlite');
  return adapter;
}

function withNativeDatabase<T>(run: (db: NativeDatabase, path: string) => T): T {
  const folder = mkdtempSync(join(tmpdir(), 'classset-settings-'));
  const path = join(folder, 'school.sqlite');
  const db = new DatabaseSync(path);
  try {
    db.exec(SCHEMA_V19_DDL);
    return run(db, path);
  } finally {
    db.close();
    rmSync(folder, { recursive: true, force: true });
  }
}

function nativeBackup() {
  return withNativeDatabase((db, path) => {
    db.exec(`
      INSERT INTO academic_terms (id, title, academic_year, semester_label, created_at)
        VALUES ('from-desktop', '桌面学期', '2026', '秋', 1);
      INSERT INTO app_settings (id, school_name, active_term_id) VALUES (1, '桌面学校', 'from-desktop');
      INSERT INTO published_schedules VALUES ('from-desktop', '{"version":1}');
      INSERT INTO teachers (id, name) VALUES ('desktop-teacher', '桌面教师');
    `);
    return new Uint8Array(readFileSync(path));
  });
}

it('以原生 SQLite 备份覆盖浏览器数据，且重新打开后仍然生效', async () => {
  const adapter = await browserDatabase();
  await adapter.execute("INSERT INTO teachers (id, name) VALUES ('stale', '旧教师')");
  await adapter.importSqliteBytes(nativeBackup());

  vi.resetModules();
  const reopened = await browserDatabase();
  expect(await reopened.select('SELECT id, name FROM teachers')).toEqual([
    { id: 'desktop-teacher', name: '桌面教师' },
  ]);
  expect(await reopened.select('SELECT term_id, data_json FROM published_schedules')).toEqual([
    { term_id: 'from-desktop', data_json: '{"version":1}' },
  ]);
  expect(await reopened.select('SELECT active_term_id FROM app_settings')).toEqual([
    { active_term_id: 'from-desktop' },
  ]);
});

it('浏览器导出的快照可被原生 SQLite 打开', async () => {
  const adapter = await browserDatabase();
  await adapter.execute("INSERT INTO teachers (id, name) VALUES ('web', '网页教师')");
  const backup = await adapter.exportSqliteBytes();
  expect(backup).toBeInstanceOf(Uint8Array);
  const folder = mkdtempSync(join(tmpdir(), 'classset-settings-'));
  try {
    const { writeFileSync } = await import('node:fs');
    const path = join(folder, 'from-web.sqlite');
    writeFileSync(path, backup!);
    const db = new DatabaseSync(path);
    try {
      expect(db.prepare('SELECT name FROM teachers').get()).toMatchObject({ name: '网页教师' });
    } finally {
      db.close();
    }
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});

it('拒绝其他应用的 SQLite 文件并保留现有数据库', async () => {
  const adapter = await browserDatabase();
  await adapter.importSqliteBytes(nativeBackup());
  const unrelated = withNativeDatabase((db, path) => {
    db.exec('PRAGMA foreign_keys = OFF');
    for (const table of SCHEMA_V19_TABLES) db.exec(`DROP TABLE "${table}"`);
    db.exec('CREATE TABLE unrelated (id TEXT)');
    return new Uint8Array(readFileSync(path));
  });

  await expect(adapter.importSqliteBytes(unrelated)).rejects.toThrow(/备份/);
  expect(await adapter.select('SELECT school_name FROM app_settings')).toEqual([{ school_name: '桌面学校' }]);
});

it('浏览器备份写入失败时保留现有库和已持久化的数据', async () => {
  const adapter = await browserDatabase();
  await adapter.execute("INSERT INTO teachers (id, name) VALUES ('existing', '保留教师')");
  failWrite = true;
  await expect(adapter.importSqliteBytes(nativeBackup())).rejects.toThrow(/磁盘已满|保存/);
  expect(await adapter.select('SELECT name FROM teachers')).toEqual([{ name: '保留教师' }]);
  failWrite = false;
  vi.resetModules();
  expect(await (await browserDatabase()).select('SELECT name FROM teachers')).toEqual([{ name: '保留教师' }]);
});

it('清空移除所有业务表数据和浏览器降级数据，重新打开仍为空', async () => {
  const repoModule = await import('@/repository/schoolRepository');
  const { schoolRepository } = repoModule;
  await schoolRepository.initialize();
  await schoolRepository.importSqliteBytes(nativeBackup());
  localStorage.setItem('classset_schema_v19_fallback_store', '{"schoolName":"降级数据"}');

  await schoolRepository.clearAllData();
  vi.resetModules();
  const reopened = await browserDatabase();
  for (const table of SCHEMA_V19_TABLES) {
    expect(await reopened.select(`SELECT * FROM "${table}"`), table).toEqual([]);
  }
  expect(localStorage.getItem('classset_schema_v19_fallback_store')).toBeNull();
});

it('阻止覆盖操作越过正在执行的浏览器事务', async () => {
  const adapter = await browserDatabase();
  let release!: () => void;
  let started!: () => void;
  const running = new Promise<void>((resolve) => { started = resolve; });
  const wait = new Promise<void>((resolve) => { release = resolve; });
  const transaction = adapter.transaction(async (tx) => {
    await tx.execute("INSERT INTO teachers (id, name) VALUES ('old', '原事务教师')");
    started();
    await wait;
    await tx.execute("INSERT INTO teachers (id, name) VALUES ('old-2', '原事务教师')");
  });
  await running;
  const importing = adapter.importSqliteBytes(nativeBackup());
  release();
  await Promise.all([transaction, importing]);
  expect(await adapter.select('SELECT id FROM teachers')).toEqual([{ id: 'desktop-teacher' }]);
});

it('桌面适配器用一个原生 SQLite 事务覆盖浏览器备份，坏数据回滚', async () => {
  const web = await browserDatabase();
  await web.importSqliteBytes(nativeBackup());
  const webBackup = await web.exportSqliteBytes();
  expect(webBackup).not.toBeNull();

  vi.resetModules();
  vi.stubGlobal('__TAURI_INTERNALS__', {});
  const db = new DatabaseSync(':memory:');
  db.exec(SCHEMA_V19_DDL);
  db.exec("INSERT INTO teachers (id, name) VALUES ('stale', '旧桌面记录')");

  // Keep the Tauri adapter and transaction orchestration real. Substitute the
  // IPC endpoint with a native SQLite connection holding the transaction.
  vi.doMock('@tauri-apps/plugin-sql', () => ({
    default: { load: async () => ({
      select: async (sql: string) => db.prepare(sql).all(),
      execute: async (sql: string) => { db.exec(sql); },
    }) },
  }));
  vi.doMock('@tauri-apps/api/core', () => ({
    invoke: async (command: string, args?: { sql: string; values: SQLInputValue[] }) => {
      switch (command) {
        case 'begin_sqlite_transaction': db.exec('BEGIN'); return 1;
        case 'execute_sqlite_transaction': return db.prepare(args!.sql).run(...args!.values);
        case 'commit_sqlite_transaction': db.exec('COMMIT'); return;
        case 'rollback_sqlite_transaction': db.exec('ROLLBACK'); return;
        default: throw new Error('Unexpected IPC: ' + command);
      }
    },
  }));

  try {
    const { getDatabaseAdapter } = await import('@/adapter/db/databaseAdapter');
    const desktop = getDatabaseAdapter();
    expect(desktop.runtimeMode).toBe('tauri-desktop');
    await desktop.importSqliteBytes(webBackup!);
    expect(await desktop.select('SELECT id FROM teachers')).toEqual([{ id: 'desktop-teacher' }]);
    expect(await desktop.select('SELECT term_id FROM published_schedules')).toEqual([{ term_id: 'from-desktop' }]);

    const orphaned = withNativeDatabase((source, path) => {
      source.exec("PRAGMA foreign_keys = OFF; INSERT INTO published_schedules VALUES ('missing-term', '{}')");
      return new Uint8Array(readFileSync(path));
    });
    await expect(desktop.importSqliteBytes(orphaned)).rejects.toThrow(/FOREIGN KEY/);
    expect(await desktop.select('SELECT id FROM teachers')).toEqual([{ id: 'desktop-teacher' }]);

    await desktop.clearAllData();
    expect(await desktop.select('SELECT id FROM teachers')).toEqual([]);
    expect(await desktop.select('SELECT term_id FROM published_schedules')).toEqual([]);
  } finally {
    vi.doUnmock('@tauri-apps/plugin-sql');
    vi.doUnmock('@tauri-apps/api/core');
    db.close();
  }
});
