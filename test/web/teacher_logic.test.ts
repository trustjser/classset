import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test, { after } from 'node:test';
import { build } from 'esbuild';

const folder = await mkdtemp(join(tmpdir(), 'classset-teacher-'));
const bundle = join(folder, 'teacher.mjs');
await build({ entryPoints: [fileURLToPath(new URL('../../src/features/teachers/teacherLogic.ts', import.meta.url))], outfile: bundle, bundle: true, platform: 'node', format: 'esm', alias: { '@': fileURLToPath(new URL('../../src', import.meta.url)) } });
const { remainingCourses, assignmentError, resolveTeacherPreset, teacherWeeklyLoad, combinedLessonCandidates } = await import(pathToFileURL(bundle).href);
after(() => rm(folder, { recursive: true, force: true }));

const schoolClass = { id: 'c', gradeId: 'g', name: '一班', sortOrder: 0 };
const subject = { id: 's', termId: 't', name: '数学', shortName: '', sortOrder: 0 };
const requirement = { id: 'r', subjectId: 's', gradeId: 'g', classId: null, weekMode: 'weekly', lessonCount: 5 };
const assigned = { id: 'a', termId: 't', teacherId: 'teacher', subjectId: 's', classId: 'c', weekMode: 'weekly', lessonCount: 2, sortOrder: 0, combinedLessonGroupId: null };

test('unassigned pool counts only remaining demand, including inherited grade requirements', () => {
  assert.deepEqual(remainingCourses([schoolClass], [subject], [requirement], [assigned]), [{ classId: 'c', subjectId: 's', weekMode: 'weekly', remainingLessons: 3 }]);
  assert.equal(remainingCourses([schoolClass], [subject], [requirement], [{ ...assigned, lessonCount: 5 }]).length, 0);
});

test('batch assignment rejects a cell that exceeds demand', () => {
  assert.match(assignmentError([{ ...assigned, id: 'b', lessonCount: 4 }], [schoolClass], [subject], [requirement], [assigned]) ?? '', /超过科目节数需求/);
  assert.equal(assignmentError([{ ...assigned, id: 'b', lessonCount: 3 }], [schoolClass], [subject], [requirement], [assigned]), null);
});

test('teacher personal preset wins; conflicting group presets are reported', () => {
  const group = { id: 'p', groupId: 'group', scopeType: 'stage', scopeId: 'stage', stageId: 'stage', weekday: 1, periodTypeId: 'am', lessonIndex: 1, weekMode: 'weekly', value: 'prefer' };
  assert.equal(resolveTeacherPreset(undefined, [group, { ...group, id: 'q', value: 'forbid' }]), 'conflict');
  assert.equal(resolveTeacherPreset({ ...group, termId: 'term', teacherId: 'teacher', value: 'must' }, [group]), 'must');
});

test('weekly load averages alternating weeks and counts combined class only once', () => {
  assert.equal(teacherWeeklyLoad([assigned, { ...assigned, id: 'odd', weekMode: 'odd', lessonCount: 3 }, { ...assigned, id: 'even', weekMode: 'even', lessonCount: 1 }]), 4);
  assert.equal(teacherWeeklyLoad([{ ...assigned, combinedLessonGroupId: 'joint' }, { ...assigned, id: 'other', combinedLessonGroupId: 'joint' }]), 2);
});

test('combined lessons require matching teacher, subject, week mode and count in distinct classes', () => {
  const rows = [assigned, { ...assigned, id: 'b', classId: 'c2' }, { ...assigned, id: 'duplicate', classId: 'c' },
    { ...assigned, id: 'other-mode', classId: 'c3', weekMode: 'odd' }, { ...assigned, id: 'already-combined', classId: 'c4', combinedLessonGroupId: 'joint' },
    { ...assigned, id: 'other-teacher', classId: 'c5', teacherId: 'other' }];
  const candidates = combinedLessonCandidates(rows, 'teacher');
  assert.equal(candidates.length, 1);
  assert.deepEqual(candidates[0].rows.map((item: { id: string }) => item.id), ['a', 'b']);
});
