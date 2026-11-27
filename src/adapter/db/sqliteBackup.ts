import type initSqlJs from 'sql.js';
import type { DbTransactionClient } from './databaseAdapter';
import { SCHEMA_V19_DDL, SCHEMA_V19_TABLES, SCHEMA_VERSION } from './schemaV19';

type SqlJsRuntime = Awaited<ReturnType<typeof initSqlJs>>;
type SqlJsDatabase = InstanceType<SqlJsRuntime['Database']>;
type BackupValue = number | string | Uint8Array | null;

let sqliteRuntime: Promise<SqlJsRuntime> | undefined;

export function loadSqliteRuntime(): Promise<SqlJsRuntime> {
  sqliteRuntime ??= Promise.all([
    import('sql.js'),
    import('sql.js/dist/sql-wasm-browser.wasm?url'),
  ]).then(([{ default: init }, { default: wasmUrl }]) =>
    init({ useOldExtensionFunctions: true, locateFile: () => wasmUrl })
  ).catch((error: unknown) => {
    sqliteRuntime = undefined;
    throw error;
  });
  return sqliteRuntime;
}

export function createEmptySqliteDatabase(runtime: SqlJsRuntime): SqlJsDatabase {
  const database = new runtime.Database();
  database.run(SCHEMA_V19_DDL);
  return database;
}

function quote(identifier: string): string {
  return '"' + identifier.replaceAll('"', '""') + '"';
}

type BackupTable = {
  name: string;
  columns: string[];
  rows: BackupValue[][];
};

export function exportSqliteSnapshot(database: SqlJsDatabase): Uint8Array {
  // sql.js reopens its connection after export and resets per-connection pragmas.
  const bytes = database.export();
  database.run('PRAGMA foreign_keys = ON');
  return bytes;
}

export function readSqliteBackup(
  runtime: SqlJsRuntime,
  bytes: Uint8Array,
  schema: SqlJsDatabase
): BackupTable[] {
  const header = new TextDecoder().decode(bytes.subarray(0, 16));
  if (header !== 'SQLite format 3\0') {
    throw new Error('无法识别此备份，请选择课集导出的 .sqlite 文件。');
  }

  const source = new runtime.Database(bytes);
  try {
    source.run('PRAGMA trusted_schema = OFF');
    const version = Number(source.exec('PRAGMA user_version')[0].values[0][0]);
    const check = source.exec('PRAGMA quick_check(1)')[0].values[0][0];
    if (version > SCHEMA_VERSION || check !== 'ok') throw new Error('Unsupported backup');

    const sourceTables = new Set(
      source.exec("SELECT name FROM sqlite_schema WHERE type = 'table'")[0]?.values.map(([name]) => name)
    );
    return SCHEMA_V19_TABLES.map((table) => {
      if (!sourceTables.has(table)) throw new Error('Missing table');
      const columnsOf = (db: SqlJsDatabase) =>
        db.exec('PRAGMA table_info(' + quote(table) + ')')[0].values.map((row) => String(row[1]));
      const available = new Set(columnsOf(source));
      const columns = columnsOf(schema);
      if (!columns.every((column) => available.has(column))) throw new Error('Missing column');
      const names = columns.map(quote).join(', ');
      const rows = source.exec('SELECT ' + names + ' FROM ' + quote(table))[0]?.values ?? [];
      return { name: table, columns, rows };
    });
  } catch {
    throw new Error('备份文件损坏或版本不兼容，请重新选择课集导出的备份。');
  } finally {
    source.close();
  }
}

export function insertBackupIntoBrowser(database: SqlJsDatabase, tables: BackupTable[]): void {
  for (const { name, columns, rows } of tables) {
    if (!rows.length) continue;
    const placeholders = columns.map(() => '?').join(', ');
    const statement = database.prepare(
      'INSERT INTO ' + quote(name) + ' (' + columns.map(quote).join(', ') + ') VALUES (' + placeholders + ')'
    );
    try {
      for (const row of rows) statement.run(row);
    } finally {
      statement.free();
    }
  }
}

export async function replaceNativeSqliteData(
  tx: DbTransactionClient,
  tables: BackupTable[] = []
): Promise<void> {
  for (const table of [...SCHEMA_V19_TABLES].reverse()) {
    await tx.execute('DELETE FROM ' + quote(table));
  }
  for (const { name, columns, rows } of tables) {
    // Keep both the number of bind parameters and the size of IPC batches bounded.
    const placeholders = '(' + columns.map(() => '?').join(', ') + ')';
    const statement = 'INSERT INTO ' + quote(name) + ' (' + columns.map(quote).join(', ') + ') VALUES ';
    const batchSize = Math.floor(999 / columns.length);
    for (let offset = 0; offset < rows.length; offset += batchSize) {
      const batch = rows.slice(offset, offset + batchSize);
      await tx.execute(
        statement + batch.map(() => placeholders).join(', '),
        batch.flat().map((value) => value instanceof Uint8Array ? Array.from(value) : value)
      );
    }
  }
}
