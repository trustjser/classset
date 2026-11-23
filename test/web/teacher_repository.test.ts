import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import { build } from 'esbuild';
import initSqlJs from 'sql.js';
import { SCHEMA_V19_DDL } from '../../src/adapter/db/schemaV19.ts';

test('teacher assignments, groups and presets persist in SQLite and teacher deletion releases courses', async () => {
  const folder = await mkdtemp(join(tmpdir(), 'classset-teacher-repo-'));
  try {
    const bundle = join(folder, 'schoolRepository.mjs');
    await build({ entryPoints: [fileURLToPath(new URL('../../src/repository/schoolRepository.ts', import.meta.url))],
      outfile: bundle, bundle: true, platform: 'node', format: 'esm', packages: 'external' });
    const { SchoolRepository } = await import(pathToFileURL(bundle).href);
    const SQL = await initSqlJs({ locateFile: () => fileURLToPath(new URL('../../node_modules/sql.js/dist/sql-wasm.wasm', import.meta.url)) });
    const db = new SQL.Database();
    db.run('PRAGMA foreign_keys = ON'); db.run(SCHEMA_V19_DDL);
    db.run("INSERT INTO academic_terms (id, title, academic_year, semester_label, teaching_week_count, cycle_mode, created_at) VALUES ('term', '学期', '2026', '一', 20, 'every_week', 1)");
    db.run("INSERT INTO school_stages (id, term_id, name, sort_order) VALUES ('stage', 'term', '小学部', 0)");
    db.run("INSERT INTO grade_groups (id, stage_id, name, sort_order) VALUES ('grade', 'stage', '一年级', 0)");
    db.run("INSERT INTO class_groups (id, grade_id, name, sort_order) VALUES ('class', 'grade', '一班', 0)");
    db.run("INSERT INTO class_groups (id, grade_id, name, sort_order) VALUES ('class2', 'grade', '二班', 1)");
    db.run("INSERT INTO lesson_period_types (id, stage_id, name, default_lesson_count, sort_order) VALUES ('am', 'stage', '上午', 4, 0)");
    db.run("INSERT INTO subjects (id, term_id, name, short_name, sort_order) VALUES ('math', 'term', '数学', '数', 0)");
    db.run("INSERT INTO subject_requirements (id, subject_id, grade_id, class_id, week_mode, lesson_count) VALUES ('demand', 'math', 'grade', 'class', 'weekly', 5)");
    db.run("INSERT INTO subject_requirements (id, subject_id, grade_id, class_id, week_mode, lesson_count) VALUES ('demand2', 'math', 'grade', 'class2', 'weekly', 5)");
    const adapter = {
      runtimeMode: 'web-browser', schemaVersion: 19, engineStatus: 'wasm-sqlite', async init() {},
      async select(sql: string, values: unknown[] = []) { const stmt = db.prepare(sql); stmt.bind(values); const rows = []; while (stmt.step()) rows.push(stmt.getAsObject()); stmt.free(); return rows; },
      async execute(sql: string, values: unknown[] = []) { db.run(sql, values); return { rowsAffected: db.getRowsModified() }; },
      async transaction<T>(fn: (tx: typeof adapter) => Promise<T>): Promise<T> { db.run('BEGIN'); try { const result = await fn(adapter); db.run('COMMIT'); return result; } catch (error) { db.run('ROLLBACK'); throw error; } },
      async exportSqliteBytes() { return null; }, async importSqliteBytes() {},
    };
    const repository = new SchoolRepository(adapter);
    await repository.saveTeachers([{ id: 'teacher', name: '张老师', shortName: '张', displayQualifier: '', sortOrder: 0, subjectIds: ['math'] }]);
    assert.deepEqual((await repository.loadTeachers())[0].subjectIds, ['math']);
    await repository.saveTeacherGroup({ id: 'group', termId: 'term', name: '数学组', description: '', sortOrder: 0 });
    await repository.replaceTeacherGroupMembers('group', [{ groupId: 'group', teacherId: 'teacher' }]);
    assert.equal((await repository.loadTeacherGroupMembers('term')).length, 1);
    const assignment = { id: 'assignment', termId: 'term', teacherId: 'teacher', subjectId: 'math', classId: 'class', weekMode: 'weekly', lessonCount: 3, sortOrder: 0, combinedLessonGroupId: null };
    await repository.addTeacherAssignments('term', [assignment]);
    assert.equal((await repository.loadTeacherAssignments('term'))[0].lessonCount, 3);
    await assert.rejects(repository.addTeacherAssignments('term', [{ ...assignment, id: 'too-many', lessonCount: 3 }]), /超过需求/);
    assert.equal((await repository.loadTeacherAssignments('term')).length, 1);
    await repository.addTeacherAssignments('term', [{ ...assignment, id: 'assignment2', classId: 'class2' }]);
    db.run("INSERT INTO schedule_items (id, term_id, assignment_id, class_id, teacher_id, subject_id, week_mode) VALUES ('scheduled', 'term', 'assignment', 'class', 'teacher', 'math', 'weekly')");
    await repository.setCombinedTeacherAssignments('term', ['assignment', 'assignment2'], 'combined');
    assert.equal((await repository.loadTeacherAssignments('term')).filter((item: { combinedLessonGroupId: string | null }) => item.combinedLessonGroupId === 'combined').length, 2);
    await repository.replaceTeacherAssignments({ termId: 'term', classId: 'class', subjectId: 'math', assignments: [{ ...assignment, lessonCount: 2 }] });
    assert.equal((await repository.loadTeacherAssignments('term')).find((item: { id: string }) => item.id === 'assignment2')?.combinedLessonGroupId, null);
    assert.equal(db.exec("SELECT id FROM schedule_items WHERE id = 'scheduled'")[0]?.values.length, 1);
    const preset = { id: 'preset', termId: 'term', teacherId: 'teacher', scopeType: 'stage', scopeId: 'stage', stageId: 'stage', weekday: 1, periodTypeId: 'am', lessonIndex: 1, weekMode: 'weekly', value: 'prefer' };
    await repository.replaceTeacherPresets('term', 'teacher', [preset]);
    assert.equal((await repository.loadTeacherPresets('term'))[0].value, 'prefer');
    await repository.replaceTeacherGroupPresets('group', [{ ...preset, id: 'group-preset', groupId: 'group' }]);
    assert.equal((await repository.loadTeacherGroupPresets('term')).length, 1);
    await repository.deleteTeacher('teacher');
    assert.equal((await repository.loadTeacherAssignments('term'))[0].teacherId, null);
    assert.equal((await repository.loadTeacherGroupMembers('term')).length, 0);
    db.close();
  } finally { await rm(folder, { recursive: true, force: true }); }
});
