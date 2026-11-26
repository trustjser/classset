import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ScheduleData } from '@/domain/scheduling';
import type {
  DbTransactionClient,
  SqlDatabaseAdapter,
} from '@/adapter/db/databaseAdapter';
import { SchoolRepository } from '@/repository/schoolRepository';

function createAdapter(
  engineStatus: SqlDatabaseAdapter['engineStatus'] = 'wasm-sqlite'
) {
  const select = vi.fn(
    async (_sql: string, _values: unknown[] = []): Promise<unknown[]> => []
  );
  const execute = vi.fn(
    async (_sql: string, _values: unknown[] = []) => ({ rowsAffected: 1 })
  );
  const adapter = {
    runtimeMode: 'web-browser' as const,
    schemaVersion: 19,
    engineStatus,
    init: vi.fn(async () => undefined),
    select: select as SqlDatabaseAdapter['select'],
    execute,
    transaction: vi.fn(
      async <T>(run: (tx: DbTransactionClient) => Promise<T>) =>
        run({ select, execute } as unknown as DbTransactionClient)
    ),
    exportSqliteBytes: vi.fn(async () => null),
    importSqliteBytes: vi.fn(async (_bytes: Uint8Array) => undefined),
  } as unknown as SqlDatabaseAdapter;

  return { adapter, select, execute };
}

describe('repository/schoolRepository.ts', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  afterEach(() => {
    localStorage.clear();
  });

  it('修剪学校名称后写入 SQL，并从 Adapter 读取保存值', async () => {
    const { adapter, select, execute } = createAdapter();
    let storedName = '';
    execute.mockImplementation(async (_sql, values = []) => {
      storedName = String(values[0] ?? '');
      return { rowsAffected: 1 };
    });
    select.mockImplementation(async () =>
      storedName ? [{ school_name: storedName }] : []
    );
    const repository = new SchoolRepository(adapter);

    await repository.saveSchoolName('  青木实验小学  ');

    expect(execute).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO app_settings'),
      ['青木实验小学']
    );
    await expect(repository.loadSchoolName()).resolves.toBe('青木实验小学');
  });

  it('设置记录不存在时返回空学校名称', async () => {
    const { adapter, select } = createAdapter();
    const repository = new SchoolRepository(adapter);

    await expect(repository.loadSchoolName()).resolves.toBe('');
    expect(select).toHaveBeenCalledWith(
      'SELECT school_name FROM app_settings WHERE id = 1'
    );
  });

  it('Adapter 写入失败时保留数据库错误并拒绝保存', async () => {
    const { adapter, execute } = createAdapter();
    execute.mockRejectedValue(new Error('database unavailable'));
    const repository = new SchoolRepository(adapter);

    await expect(repository.saveSchoolName('青木实验小学')).rejects.toThrow(
      'database unavailable'
    );
  });

  it('SQL 引擎不可用时通过 Web fallback 保存并读取学校名称', async () => {
    const { adapter, execute } = createAdapter('memory-fallback');
    const repository = new SchoolRepository(adapter);

    await repository.saveSchoolName('  青木实验小学  ');

    expect(await repository.loadSchoolName()).toBe('青木实验小学');
    expect(execute).not.toHaveBeenCalled();
    const fallback = JSON.parse(
      localStorage.getItem('classset_schema_v19_fallback_store') ?? '{}'
    ) as { schoolName?: string };
    expect(fallback.schoolName).toBe('青木实验小学');
  });

  it('按学期 ID 读取已发布课表，缺少记录时返回 null', async () => {
    const expected = { term: { id: 'term-2' } } as ScheduleData;
    const { adapter, select } = createAdapter();
    select.mockResolvedValueOnce([
      { data_json: JSON.stringify({ workbench: expected }) },
    ]);
    select.mockResolvedValueOnce([]);
    const repository = new SchoolRepository(adapter);

    await expect(repository.loadPublishedSchedule('term-2')).resolves.toEqual(
      expected
    );
    await expect(repository.loadPublishedSchedule('missing')).resolves.toBeNull();
    expect(select).toHaveBeenNthCalledWith(
      1,
      'SELECT data_json FROM published_schedules WHERE term_id = ?',
      ['term-2']
    );
    expect(select).toHaveBeenNthCalledWith(
      2,
      'SELECT data_json FROM published_schedules WHERE term_id = ?',
      ['missing']
    );
  });

  it('已发布课表 JSON 损坏时向调用方抛出解析错误', async () => {
    const { adapter, select } = createAdapter();
    select.mockResolvedValue([{ data_json: '{broken-json' }]);
    const repository = new SchoolRepository(adapter);

    await expect(repository.loadPublishedSchedule('term-1')).rejects.toThrow(
      SyntaxError
    );
  });
});
