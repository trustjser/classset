import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import { build } from 'esbuild';
import initSqlJs from 'sql.js';
import { SCHEMA_V19_DDL } from '../../src/adapter/db/schemaV19.ts';

test('subject settings save through one SQLite transaction and roll back on error', async () => {
  const folder = await mkdtemp(join(tmpdir(), 'classset-subject-'));
  try {
    const bundle = join(folder, 'schoolRepository.mjs');
    await build({ entryPoints: [fileURLToPath(new URL('../../src/repository/schoolRepository.ts', import.meta.url))],
      outfile: bundle, bundle: true, platform: 'node', format: 'esm', packages: 'external' });
    const { SchoolRepository } = await import(pathToFileURL(bundle).href);
    const SQL = await initSqlJs({ locateFile: () => fileURLToPath(new URL('../../node_modules/sql.js/dist/sql-wasm.wasm', import.meta.url)) });
    const db = new SQL.Database();
    db.run('PRAGMA foreign_keys = ON');
    db.run(SCHEMA_V19_DDL);
    db.run("INSERT INTO academic_terms (id, title, academic_year, semester_label, teaching_week_count, cycle_mode, created_at) VALUES ('term', '学期', '2026', '一', 20, 'every_week', 1)");
    db.run("INSERT INTO school_stages (id, term_id, name, sort_order) VALUES ('stage', 'term', '小学部', 0)");
    db.run("INSERT INTO grade_groups (id, stage_id, name, sort_order) VALUES ('grade', 'stage', '一年级', 0)");
    db.run("INSERT INTO class_groups (id, grade_id, name, sort_order) VALUES ('class', 'grade', '一(1)班', 0)");
    db.run("INSERT INTO lesson_period_types (id, stage_id, name, default_lesson_count, sort_order) VALUES ('am', 'stage', '上午', 4, 0)");
    const adapter = {
      runtimeMode: 'web-browser', schemaVersion: 19, engineStatus: 'wasm-sqlite',
      async init() {},
      async select(sql: string, values: unknown[] = []) {
        const stmt = db.prepare(sql); stmt.bind(values); const rows = [];
        while (stmt.step()) rows.push(stmt.getAsObject());
        stmt.free(); return rows;
      },
      async execute(sql: string, values: unknown[] = []) {
        db.run(sql, values); return { rowsAffected: db.getRowsModified() };
      },
      async transaction<T>(fn: (tx: typeof adapter) => Promise<T>): Promise<T> {
        db.run('BEGIN');
        try { const result = await fn(adapter); db.run('COMMIT'); return result; }
        catch (error) { db.run('ROLLBACK'); throw error; }
      },
      async exportSqliteBytes() { return null; }, async importSqliteBytes() {},
    };
    const repository = new SchoolRepository(adapter);
    const subject = { id: 'math', termId: 'term', name: '数学', shortName: '数', sortOrder: 0 };
    await repository.saveSubjectChanges({
      upserts: [subject], deletedIds: [],
      requirementsByGrade: { grade: [{ id: 'requirement', subjectId: 'math', gradeId: 'grade',
        classId: 'class', weekMode: 'weekly', lessonCount: 4 }] },
      pairingsByClass: {},
      presetScopes: [{ subjectId: 'math', scopeType: 'stage', scopeId: 'stage', stageId: 'stage',
        rows: [{ id: 'preset', subjectId: 'math', scopeType: 'stage', scopeId: 'stage',
          stageId: 'stage', weekday: 1, periodTypeId: 'am', lessonIndex: 1, value: 'prefer' }] }],
      constraintScopes: [{ subjectId: 'math', scopeType: 'stage', scopeId: 'stage', stageId: 'stage',
        rows: [{ id: 'constraint', subjectId: 'math', scopeType: 'stage', scopeId: 'stage',
          stageId: 'stage', weekday: null, minimumDailyLessons: null, maximumDailyLessons: 2,
          minimumDailyConsecutivePairs: null, maximumDailyConsecutivePairs: null,
          minimumWeeklyConsecutivePairs: null, maximumWeeklyConsecutivePairs: null }] }],
      roomScopes: [],
    });
    assert.equal((await repository.loadSubjectRequirements('term'))[0].lessonCount, 4);
    assert.equal((await repository.loadSubjectPresets('term'))[0].value, 'prefer');
    assert.equal((await repository.loadSubjectLessonConstraints('term'))[0].maximumDailyLessons, 2);

    db.run("INSERT INTO public_rooms (id, name, room_count, capacity_per_room, sort_order) VALUES ('room', '实验室', 1, 30, 0)");
    await repository.saveSubjectChanges({
      upserts: [{ id: 'science', termId: 'term', name: '科学', shortName: '科', sortOrder: 1 }],
      deletedIds: [], requirementsByGrade: {},
      pairingsByClass: { class: [{ id: 'pair', classId: 'class', oddSubjectId: 'math', evenSubjectId: 'science' }] },
      presetScopes: [], constraintScopes: [],
      roomScopes: [{ subjectId: 'science', scopeType: 'stage', scopeId: 'stage', stageId: 'stage',
        assignment: { id: 'valid-room', subjectId: 'science', termId: 'term', stageId: 'stage',
          scopeType: 'stage', scopeId: 'stage', roomId: 'room' },
        limit: { id: 'limit', subjectId: 'science', termId: 'term', stageId: 'stage',
          scopeType: 'stage', scopeId: 'stage', maxParallelLessons: 1 } }],
    });
    assert.equal((await repository.loadSubjectPairings('term'))[0].evenSubjectId, 'science');
    assert.equal((await repository.loadSubjectRoomSettings('term')).assignments[0].roomId, 'room');
    assert.equal((await repository.loadSubjectRoomSettings('term')).limits[0].maxParallelLessons, 1);

    await assert.rejects(repository.saveSubjectChanges({
      upserts: [{ ...subject, name: '更名失败' }], deletedIds: [],
      requirementsByGrade: {}, pairingsByClass: {}, presetScopes: [], constraintScopes: [],
      roomScopes: [{ subjectId: 'math', scopeType: 'stage', scopeId: 'stage', stageId: 'stage',
        assignment: { id: 'bad-room', subjectId: 'math', termId: 'term', stageId: 'stage',
          scopeType: 'stage', scopeId: 'stage', roomId: 'missing-room' }, limit: null }],
    }));
    assert.equal((await repository.loadSubjects('term'))[0].name, '数学');
    db.close();
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});
