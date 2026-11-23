import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import { build } from 'esbuild';
import initSqlJs from 'sql.js';
import { SCHEMA_V19_DDL } from '../../src/adapter/db/schemaV19.ts';

async function withRepository<T>(run: (repository: any, db: any) => Promise<T>) {
  const folder = await mkdtemp(join(tmpdir(), 'classset-demo-data-'));
  try {
    const bundle = join(folder, 'schoolRepository.mjs');
    await build({
      entryPoints: [fileURLToPath(new URL('../../src/repository/schoolRepository.ts', import.meta.url))],
      outfile: bundle,
      bundle: true,
      platform: 'node',
      format: 'esm',
      packages: 'external',
    });
    const { SchoolRepository } = await import(pathToFileURL(bundle).href);
    const SQL = await initSqlJs({
      locateFile: () => fileURLToPath(new URL('../../node_modules/sql.js/dist/sql-wasm.wasm', import.meta.url)),
    });
    const db = new SQL.Database();
    db.run('PRAGMA foreign_keys = ON');
    db.run(SCHEMA_V19_DDL);
    db.run("INSERT INTO academic_terms (id, title, academic_year, semester_label, teaching_week_count, cycle_mode, created_at) VALUES ('term', '演示学期', '2026-2027', '第一学期', 20, 'every_week', 1)");
    const adapter = {
      runtimeMode: 'web-browser', schemaVersion: 19, engineStatus: 'wasm-sqlite',
      async init() {},
      async select(sql: string, values: unknown[] = []) {
        const statement = db.prepare(sql);
        statement.bind(values);
        const rows = [];
        while (statement.step()) rows.push(statement.getAsObject());
        statement.free();
        return rows;
      },
      async execute(sql: string, values: unknown[] = []) {
        db.run(sql, values);
        return { rowsAffected: db.getRowsModified() };
      },
      async transaction<Tx>(fn: (tx: typeof adapter) => Promise<Tx>): Promise<Tx> {
        db.run('BEGIN');
        try {
          const result = await fn(adapter);
          db.run('COMMIT');
          return result;
        } catch (error) {
          db.run('ROLLBACK');
          throw error;
        }
      },
      async exportSqliteBytes() { return null; },
      async importSqliteBytes() {},
    };
    return await run(new SchoolRepository(adapter), db);
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
}

test('generates Flutter-equivalent school setup through the SQLite repository', async () => {
  await withRepository(async (repository) => {
    const { seedDemoData } = await import('../../src/features/workbench/demoData.ts');
    await repository.saveStage({ id: 'initial-primary', termId: 'term', name: '小学部', sortOrder: 0 });
    await seedDemoData(repository, 'term');

    const grades = await repository.loadGradesForTerm('term');
    const classes = await repository.loadClassesForTerm('term');
    const stages = await repository.loadStages('term');
    const subjects = await repository.loadSubjects('term');
    const teachers = await repository.loadTeachers();
    const requirements = await repository.loadSubjectRequirements('term');
    const assignments = await repository.loadTeacherAssignments('term');

    assert.equal(grades.length, 9);
    assert.equal(classes.length, 60);
    assert.equal(stages.length, 2);
    assert.equal(stages[0].id, 'initial-primary');
    assert.equal(subjects.length, 18);
    assert.ok(teachers.length > 0);
    assert.equal(requirements.length, 112);
    assert.equal(assignments.length, requirements.reduce((sum, item) => sum + classes.filter((cls) => cls.gradeId === item.gradeId).length, 0));
    const juniorRoutine = await repository.loadStageRoutine(stages[1].id);
    assert.deepEqual(juniorRoutine.teachingDays.filter((day) => day.isTeachingDay).map((day) => day.weekday), [1, 2, 3, 4, 5, 7]);
    assert.equal(juniorRoutine.periodTypes.length, 3);
    assert.equal((await repository.loadFreeSlots(stages[1].id)).length, 20);
    const freeSlots = await repository.loadFreeSlots(stages[1].id);
    assert.equal(freeSlots.filter((slot) => slot.label === '自习').length, 10);
    assert.equal(freeSlots.filter((slot) => slot.label === '不上课').length, 10);
    assert.deepEqual(juniorRoutine.commonPeriods?.map((period) => period.insertAfterLessonId), [`${stages[1].id}_am_2`, `${stages[1].id}_am_4`]);
    for (const requirement of requirements) {
      for (const schoolClass of classes.filter((item) => item.gradeId === requirement.gradeId)) {
        assert.equal(
          assignments.filter((item) => item.classId === schoolClass.id && item.subjectId === requirement.subjectId)
            .reduce((sum, item) => sum + item.lessonCount, 0),
          requirement.lessonCount,
        );
      }
    }
    for (const teacher of teachers) {
      assert.ok(assignments.filter((item) => item.teacherId === teacher.id)
        .reduce((sum, item) => sum + item.lessonCount, 0) <= 18);
    }
  });
});

test('refuses to seed over a custom routine in a demo stage', async () => {
  await withRepository(async (repository) => {
    await repository.saveStage({ id: 'stage', termId: 'term', name: '小学部', sortOrder: 0 });
    await repository.saveStageRoutine({
      stageId: 'stage',
      teachingDays: Array.from({ length: 7 }, (_, index) => ({
        id: `day-${index + 1}`, stageId: 'stage', weekday: index + 1, isTeachingDay: index < 5,
      })),
      periodTypes: [{ id: 'custom-am', stageId: 'stage', name: '早读', defaultLessonCount: 1, sortOrder: 0 }],
      dailyOverrides: [],
      lessonTimes: [{ id: 'custom-am_1', periodTypeId: 'custom-am', lessonIndex: 1, label: '第 1 节', startMinute: 450, endMinute: 480 }],
      commonPeriods: [],
    });
    const { seedDemoData } = await import('../../src/features/workbench/demoData.ts');

    await assert.rejects(seedDemoData(repository, 'term'), /已有作息/);
    assert.equal((await repository.loadGradesForTerm('term')).length, 0);
  });
});

test('refuses to seed a term that already contains grades', async () => {
  await withRepository(async (repository) => {
    await repository.saveStage({ id: 'stage', termId: 'term', name: '小学部', sortOrder: 0 });
    await repository.saveGrades([{ id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0 }]);
    const { seedDemoData } = await import('../../src/features/workbench/demoData.ts');

    await assert.rejects(seedDemoData(repository, 'term'), /已有年级数据/);
    assert.equal((await repository.loadGradesForTerm('term')).length, 1);
  });
});
