/**
 * 课集 (ClassSet) 跨平台 SQLite 数据库适配层 (Tauri v2 Native + Web Browser IndexedDB/Wasm)
 * - 桌面端 (Tauri v2)：调用 @tauri-apps/plugin-sql 直连本机 school.sqlite
 * - Web 端 (Browser)：使用 sql.js (SQLite Wasm) + IndexedDB 持久化二进制数据库镜像，
 *   并支持一键导入/导出标准 .sqlite 文件（与桌面端和原 Flutter 端 100% 二进制兼容）
 */

import { SCHEMA_V19_DDL, SCHEMA_VERSION } from './schemaV19';
import { runTauriTransaction } from './tauriTransaction';
import {
  createEmptySqliteDatabase,
  exportSqliteSnapshot,
  insertBackupIntoBrowser,
  loadSqliteRuntime,
  readSqliteBackup,
  replaceNativeSqliteData,
} from './sqliteBackup';

type SqlJsRuntime = Awaited<ReturnType<typeof loadSqliteRuntime>>;
type SqlJsDatabase = InstanceType<SqlJsRuntime['Database']>;
type SqlJsValue = number | string | Uint8Array | null;

function toSqlJsValues(values: unknown[]): SqlJsValue[] {
  return values.map((value) => {
    if (
      value === null ||
      typeof value === 'number' ||
      typeof value === 'string' ||
      value instanceof Uint8Array
    ) {
      return value;
    }
    if (typeof value === 'boolean') return value ? 1 : 0;
    throw new TypeError(`不支持的 SQLite 参数类型：${typeof value}`);
  });
}

export interface QueryResult {
  rowsAffected: number;
  lastInsertId?: number;
}

export type DbTransactionClient = Pick<SqlDatabaseAdapter, 'select' | 'execute'>;

export interface SqlDatabaseAdapter {
  readonly runtimeMode: 'tauri-desktop' | 'web-browser';
  readonly schemaVersion: number;
  readonly engineStatus: 'native-sqlite' | 'wasm-sqlite' | 'memory-fallback';
  init(): Promise<void>;
  select<T = Record<string, unknown>>(sql: string, bindValues?: unknown[]): Promise<T[]>;
  execute(sql: string, bindValues?: unknown[]): Promise<QueryResult>;
  transaction<T>(fn: (tx: DbTransactionClient) => Promise<T>): Promise<T>;
  exportSqliteBytes(): Promise<Uint8Array | null>;
  importSqliteBytes(bytes: Uint8Array): Promise<void>;
  clearAllData(): Promise<void>;
}

/**
 * 检测当前是否运行在 Tauri v2 桌面端容器中
 */
export function isTauriDesktop(): boolean {
  return (
    typeof window !== 'undefined' &&
    ('__TAURI_INTERNALS__' in window || '__TAURI__' in window)
  );
}

/**
 * IndexedDB 辅助存储：用于 Web 端大容量持久化 SQLite 二进制镜像 (突破 LocalStorage 5MB 限制)
 */
const IDB_NAME = 'classset_sqlite_idb';
const IDB_STORE = 'sqlite_files';
const IDB_KEY = 'school.sqlite.v19';

function openStorage(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(IDB_NAME, 1);
    request.onupgradeneeded = () => {
      if (!request.result.objectStoreNames.contains(IDB_STORE)) {
        request.result.createObjectStore(IDB_STORE);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function loadBytesFromIndexedDB(): Promise<Uint8Array | null> {
  if (typeof indexedDB === 'undefined') return null;
  const db = await openStorage();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(IDB_STORE, 'readonly');
      const request = tx.objectStore(IDB_STORE).get(IDB_KEY);
      request.onsuccess = () => {
        resolve(request.result instanceof Uint8Array ? request.result : null);
      };
      request.onerror = () => reject(request.error);
    });
  } finally {
    db.close();
  }
}

async function saveBytesToIndexedDB(bytes: Uint8Array | null): Promise<void> {
  if (typeof indexedDB === 'undefined' && bytes === null) return;
  try {
    const db = await openStorage();
    try {
      await new Promise<void>((resolve, reject) => {
        const tx = db.transaction(IDB_STORE, 'readwrite');
        const store = tx.objectStore(IDB_STORE);
        if (bytes) store.put(bytes, IDB_KEY);
        else store.delete(IDB_KEY);
        tx.oncomplete = () => resolve();
        tx.onabort = () => reject(tx.error);
      });
    } finally {
      db.close();
    }
  } catch (error) {
    throw new Error('无法保存浏览器数据库，请检查存储空间和权限后重试。', { cause: error });
  }
}

/**
 * Tauri v2 桌面端原生 SQLite 适配器 (@tauri-apps/plugin-sql)
 */
class TauriSqliteAdapter implements SqlDatabaseAdapter {
  readonly runtimeMode = 'tauri-desktop' as const;
  readonly schemaVersion = SCHEMA_VERSION;
  readonly engineStatus = 'native-sqlite' as const;

  private dbPromise: Promise<{
    select<T>(sql: string, bindValues?: unknown[]): Promise<T>;
    execute(sql: string, bindValues?: unknown[]): Promise<QueryResult>;
  }> | null = null;

  private async getDb() {
    if (!this.dbPromise) {
      this.dbPromise = (async () => {
        const Database = (await import('@tauri-apps/plugin-sql')).default;
        const db = await Database.load('sqlite:school.sqlite');
        await db.execute('PRAGMA foreign_keys = ON;');
        return db;
      })();
    }
    return this.dbPromise;
  }

  async init(): Promise<void> {
    const db = await this.getDb();
    for (const statement of SCHEMA_V19_DDL.split(';')
      .map((s) => s.trim())
      .filter(Boolean)) {
      await db.execute(statement);
    }
  }

  async select<T = Record<string, unknown>>(
    sql: string,
    bindValues: unknown[] = []
  ): Promise<T[]> {
    const db = await this.getDb();
    return db.select<T[]>(sql, bindValues);
  }

  async execute(sql: string, bindValues: unknown[] = []): Promise<QueryResult> {
    const db = await this.getDb();
    return db.execute(sql, bindValues);
  }

  async transaction<T>(fn: (tx: DbTransactionClient) => Promise<T>): Promise<T> {
    await this.getDb();
    const { invoke } = await import('@tauri-apps/api/core');
    return runTauriTransaction(invoke, fn);
  }

  async exportSqliteBytes(): Promise<Uint8Array> {
    await this.getDb();
    const { invoke } = await import('@tauri-apps/api/core');
    return new Uint8Array(await invoke<ArrayBuffer>('export_sqlite_snapshot'));
  }

  async importSqliteBytes(bytes: Uint8Array): Promise<void> {
    const runtime = await loadSqliteRuntime();
    const schema = createEmptySqliteDatabase(runtime);
    try {
      const tables = readSqliteBackup(runtime, bytes, schema);
      await this.transaction((tx) => replaceNativeSqliteData(tx, tables));
    } finally {
      schema.close();
    }
  }

  async clearAllData(): Promise<void> {
    await this.transaction((tx) => replaceNativeSqliteData(tx));
  }
}

/**
 * Web SQLite is a single connection. Serialize work through IndexedDB commit
 * so a backup cannot replace an open transaction or race an older snapshot.
 */
class WebSqliteAdapter implements SqlDatabaseAdapter {
  readonly runtimeMode = 'web-browser' as const;
  readonly schemaVersion = SCHEMA_VERSION;
  private sqlModule: SqlJsRuntime | null = null;
  private wasmDb: SqlJsDatabase | null = null;
  private initialization: Promise<void> | undefined;
  private pending: Promise<unknown> = Promise.resolve();

  get engineStatus(): 'wasm-sqlite' | 'memory-fallback' {
    return this.wasmDb ? 'wasm-sqlite' : 'memory-fallback';
  }

  init(): Promise<void> {
    this.initialization ??= this.openDatabase();
    return this.initialization;
  }

  private async openDatabase(): Promise<void> {
    try {
      this.sqlModule = await loadSqliteRuntime();
      const bytes = await loadBytesFromIndexedDB();
      if (bytes?.length) {
        const database = new this.sqlModule.Database(bytes);
        try {
          database.run(SCHEMA_V19_DDL);
          this.wasmDb = database;
        } catch (error) {
          database.close();
          throw error;
        }
      } else {
        this.wasmDb = createEmptySqliteDatabase(this.sqlModule);
      }
    } catch {
      this.wasmDb = null;
    }
  }

  private enqueue<T>(operation: () => T | Promise<T>): Promise<T> {
    const result = this.pending.then(async () => {
      await this.init();
      return operation();
    });
    this.pending = result.catch(() => {});
    return result;
  }

  private async persist(database: SqlJsDatabase): Promise<void> {
    try {
      await saveBytesToIndexedDB(exportSqliteSnapshot(database));
    } catch {
      // Existing in-memory fallback for ordinary edits. Explicit backup
      // operations report persistence failures before switching databases.
    }
  }

  private client(database: SqlJsDatabase | null): DbTransactionClient {
    return {
      async select<T>(sql: string, values: unknown[] = []): Promise<T[]> {
        const result = database?.exec(sql, toSqlJsValues(values))[0];
        return result?.values.map((row) =>
          Object.fromEntries(result.columns.map((column, index) => [column, row[index]])) as T
        ) ?? [];
      },
      async execute(sql, values = []) {
        if (!database) return { rowsAffected: 0 };
        database.run(sql, toSqlJsValues(values));
        return { rowsAffected: database.getRowsModified() };
      },
    };
  }

  select<T = Record<string, unknown>>(sql: string, values: unknown[] = []): Promise<T[]> {
    return this.enqueue(() => this.client(this.wasmDb).select<T>(sql, values));
  }

  execute(sql: string, values: unknown[] = []): Promise<QueryResult> {
    return this.enqueue(async () => {
      const database = this.wasmDb;
      const result = await this.client(database).execute(sql, values);
      if (database) await this.persist(database);
      return result;
    });
  }

  transaction<T>(fn: (tx: DbTransactionClient) => Promise<T>): Promise<T> {
    return this.enqueue(async () => {
      const database = this.wasmDb;
      const client = this.client(database);
      if (!database) return fn(client);

      database.run('BEGIN TRANSACTION');
      let result: T;
      try {
        result = await fn(client);
        database.run('COMMIT');
      } catch (error) {
        database.run('ROLLBACK');
        throw error;
      }
      await this.persist(database);
      return result;
    });
  }

  exportSqliteBytes(): Promise<Uint8Array | null> {
    return this.enqueue(() => this.wasmDb ? exportSqliteSnapshot(this.wasmDb) : null);
  }

  importSqliteBytes(bytes: Uint8Array): Promise<void> {
    return this.enqueue(async () => {
      const runtime = this.sqlModule ?? await loadSqliteRuntime();
      const replacement = createEmptySqliteDatabase(runtime);
      try {
        const tables = readSqliteBackup(runtime, bytes, replacement);
        insertBackupIntoBrowser(replacement, tables);
        await saveBytesToIndexedDB(exportSqliteSnapshot(replacement));
      } catch (error) {
        replacement.close();
        throw error;
      }
      this.wasmDb?.close();
      this.wasmDb = replacement;
      this.sqlModule = runtime;
    });
  }

  clearAllData(): Promise<void> {
    return this.enqueue(async () => {
      await saveBytesToIndexedDB(null);
      this.wasmDb?.close();
      this.wasmDb = this.sqlModule ? createEmptySqliteDatabase(this.sqlModule) : null;
    });
  }
}

let activeAdapter: SqlDatabaseAdapter | null = null;

export function getDatabaseAdapter(): SqlDatabaseAdapter {
  if (!activeAdapter) {
    activeAdapter = isTauriDesktop()
      ? new TauriSqliteAdapter()
      : new WebSqliteAdapter();
  }
  return activeAdapter;
}
