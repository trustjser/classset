import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test, { after } from 'node:test';
import { build } from 'esbuild';

const folder = await mkdtemp(join(tmpdir(), 'classset-teacher-workbook-'));
const bundle = join(folder, 'workbook.mjs');
await build({ entryPoints: [fileURLToPath(new URL('../../src/features/teachers/teacherWorkbook.ts', import.meta.url))],
  outfile: bundle, bundle: true, platform: 'node', format: 'esm' });
const { buildTeachersWorkbook, parseTeachersWorkbook, buildAssignmentsWorkbook, parseAssignmentsWorkbook } = await import(pathToFileURL(bundle).href);
after(() => rm(folder, { recursive: true, force: true }));

test('teacher workbook preserves subjects and groups across export and import', async () => {
  const teacher = { id: 'teacher', name: '李老师', shortName: '李', displayQualifier: '', sortOrder: 0, subjectIds: ['math'] };
  const group = { id: 'group', termId: 'term', name: '数学组', description: '', sortOrder: 0 };
  const subject = { id: 'math', termId: 'term', name: '数学', shortName: '数', sortOrder: 0 };
  const bytes = await buildTeachersWorkbook([teacher], [group], [{ groupId: 'group', teacherId: 'teacher' }], [subject]);
  assert.deepEqual(await parseTeachersWorkbook(bytes), [{ name: '李老师', shortName: '李', groups: ['数学组'], subjects: ['数学'] }]);
});

test('assignment workbook round-trips class and week mode', async () => {
  const stage = { id: 'stage', termId: 'term', name: '小学部', sortOrder: 0 };
  const grade = { id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0 };
  const schoolClass = { id: 'class', gradeId: 'grade', name: '一班', sortOrder: 0 };
  const subject = { id: 'math', termId: 'term', name: '数学', shortName: '数', sortOrder: 0 };
  const teacher = { id: 'teacher', name: '李老师', shortName: '李', displayQualifier: '', sortOrder: 0 };
  const assignment = { id: 'assignment', termId: 'term', teacherId: 'teacher', classId: 'class', subjectId: 'math', weekMode: 'odd', lessonCount: 2, sortOrder: 0, combinedLessonGroupId: null };
  const bytes = await buildAssignmentsWorkbook([stage], [grade], [schoolClass], [subject], [teacher], [assignment]);
  assert.deepEqual(await parseAssignmentsWorkbook(bytes), [{ stage: '小学部', grade: '一年级', schoolClass: '一班', subject: '数学', teacher: '李老师', weekMode: 'odd', lessonCount: 2 }]);
});
