/**
 * 课集 (ClassSet) 跨平台 SQLite 数据库适配层 (Tauri v2 Native + Web Browser IndexedDB/Wasm)
 * - 桌面端 (Tauri v2)：调用 @tauri-apps/plugin-sql 直连本机 school.sqlite
 * - Web 端 (Browser)：使用 sql.js (SQLite Wasm) + IndexedDB 持久化二进制数据库镜像，
 *   并支持一键导入/导出标准 .sqlite 文件（与桌面端和原 Flutter 端 100% 二进制兼容）
 */

import { SCHEMA_V19_DDL, SCHEMA_VERSION } from './schemaV19';
import { runTauriTransaction } from './tauriTransaction';
import type initSqlJs from 'sql.js';

type SqlJsRuntime = Awaited<ReturnType<typeof initSqlJs>>;
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

async function loadBytesFromIndexedDB(): Promise<Uint8Array | null> {
  if (typeof indexedDB === 'undefined') return null;
  return new Promise((resolve) => {
    try {
      const req = indexedDB.open(IDB_NAME, 1);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(IDB_STORE)) {
          db.createObjectStore(IDB_STORE);
        }
      };
      req.onsuccess = () => {
        const db = req.result;
        const tx = db.transaction(IDB_STORE, 'readonly');
        const getReq = tx.objectStore(IDB_STORE).get(IDB_KEY);
        getReq.onsuccess = () => {
          const val = getReq.result;
          resolve(val instanceof Uint8Array ? val : null);
        };
        getReq.onerror = () => resolve(null);
      };
      req.onerror = () => resolve(null);
    } catch {
      resolve(null);
    }
  });
}

async function saveBytesToIndexedDB(bytes: Uint8Array): Promise<void> {
  if (typeof indexedDB === 'undefined') return;
  return new Promise((resolve) => {
    try {
      const req = indexedDB.open(IDB_NAME, 1);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(IDB_STORE)) {
          db.createObjectStore(IDB_STORE);
        }
      };
      req.onsuccess = () => {
        const db = req.result;
        const tx = db.transaction(IDB_STORE, 'readwrite');
        tx.objectStore(IDB_STORE).put(bytes, IDB_KEY);
        tx.oncomplete = () => resolve();
        tx.onerror = () => resolve();
      };
      req.onerror = () => resolve();
    } catch {
      resolve();
    }
  });
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

  async exportSqliteBytes(): Promise<Uint8Array | null> {
    try {
      const { readFile, BaseDirectory } = await import('@tauri-apps/plugin-fs');
      return await readFile('school.sqlite', {
        baseDir: BaseDirectory.AppConfig,
      });
    } catch {
      return null;
    }
  }

  async importSqliteBytes(bytes: Uint8Array): Promise<void> {
    const { writeFile, BaseDirectory } = await import('@tauri-apps/plugin-fs');
    await writeFile('school.sqlite', bytes, {
      baseDir: BaseDirectory.AppConfig,
    });
    this.dbPromise = null;
    await this.init();
  }
}

/**
 * Web 浏览器端 SQLite 适配器 (sql.js Wasm + IndexedDB 二进制持久化 + 事务回滚)
 */
class WebSqliteAdapter implements SqlDatabaseAdapter {
  readonly runtimeMode = 'web-browser' as const;
  readonly schemaVersion = SCHEMA_VERSION;
  private sqlModule: SqlJsRuntime | null = null;
  private wasmDb: SqlJsDatabase | null = null;
  private initialized = false;
  private inTransaction = false;

  get engineStatus(): 'wasm-sqlite' | 'memory-fallback' {
    return this.wasmDb ? 'wasm-sqlite' : 'memory-fallback';
  }

  async init(): Promise<void> {
    if (this.initialized) return;
    try {
      const [{ default: initSqlJs }, { default: wasmUrl }] = await Promise.all([
        import('sql.js'),
        import('sql.js/dist/sql-wasm-browser.wasm?url'),
      ]);
      const SQL = await initSqlJs({
        // Match sql.js's runtime default while satisfying its required type.
        useOldExtensionFunctions: true,
        locateFile: () => wasmUrl,
      });
      this.sqlModule = SQL;

      const idbBytes = await loadBytesFromIndexedDB();
      const database =
        idbBytes && idbBytes.byteLength > 0
          ? new SQL.Database(idbBytes)
          : new SQL.Database();
      database.run('PRAGMA foreign_keys = ON;');
      database.run(SCHEMA_V19_DDL);
      this.wasmDb = database;
      await this.persistToStorage();
    } catch {
      this.wasmDb = null;
    }
    this.initialized = true;
  }

  private async persistToStorage(): Promise<void> {
    if (!this.wasmDb || this.inTransaction) return;
    try {
      const bytes = this.wasmDb.export();
      await saveBytesToIndexedDB(bytes);
    } catch {
      // ignore
    }
  }

  async select<T = Record<string, unknown>>(
    sql: string,
    bindValues: unknown[] = []
  ): Promise<T[]> {
    await this.init();
    if (!this.wasmDb) return [];
    const results = this.wasmDb.exec(sql, toSqlJsValues(bindValues));
    if (!results.length) return [];
    const { columns, values } = results[0];
    return values.map((row) => {
      const record: Record<string, unknown> = {};
      columns.forEach((col, idx) => {
        record[col] = row[idx];
      });
      return record as T;
    });
  }

  async execute(sql: string, bindValues: unknown[] = []): Promise<QueryResult> {
    await this.init();
    if (!this.wasmDb) return { rowsAffected: 0 };
    this.wasmDb.run(sql, toSqlJsValues(bindValues));
    await this.persistToStorage();
    return { rowsAffected: 1 };
  }

  async transaction<T>(fn: (tx: DbTransactionClient) => Promise<T>): Promise<T> {
    await this.init();
    if (!this.wasmDb) {
      return fn({
        select: this.select.bind(this),
        execute: this.execute.bind(this),
      });
    }
    this.inTransaction = true;
    this.wasmDb.run('BEGIN TRANSACTION');
    try {
      const result = await fn({
        select: this.select.bind(this),
        execute: this.execute.bind(this),
      });
      this.wasmDb.run('COMMIT');
      this.inTransaction = false;
      await this.persistToStorage();
      return result;
    } catch (err) {
      this.wasmDb.run('ROLLBACK');
      this.inTransaction = false;
      throw err;
    }
  }

  async exportSqliteBytes(): Promise<Uint8Array | null> {
    await this.init();
    if (!this.wasmDb) return null;
    return this.wasmDb.export();
  }

  async importSqliteBytes(bytes: Uint8Array): Promise<void> {
    await this.init();
    if (this.sqlModule) {
      this.wasmDb = new this.sqlModule.Database(bytes);
      this.wasmDb.run('PRAGMA foreign_keys = ON;');
      this.wasmDb.run(SCHEMA_V19_DDL);
      await saveBytesToIndexedDB(this.wasmDb.export());
    }
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
