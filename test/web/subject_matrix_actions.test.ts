import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test, { after } from 'node:test';
import { build } from 'esbuild';
import type { ClassGroup, GradeGroup, Subject } from '../../src/domain/models.ts';

const folder = await mkdtemp(join(tmpdir(), 'classset-matrix-'));
const bundle = join(folder, 'subjectMatrixActions.mjs');
await build({ entryPoints: [fileURLToPath(new URL('../../src/features/subjects/subjectMatrixActions.ts', import.meta.url))],
  outfile: bundle, bundle: true, platform: 'node', format: 'esm' });
const { applyMatrixCells, copyMatrixText, pasteMatrixGrid, rectangleKeys } =
  await import(pathToFileURL(bundle).href);
after(() => rm(folder, { recursive: true, force: true }));

const subjects: Subject[] = [
  { id: 'math', termId: 'term', name: '数学', shortName: '数', sortOrder: 0 },
  { id: 'science', termId: 'term', name: '科学', shortName: '科', sortOrder: 1 },
];
const grades: GradeGroup[] = [
  { id: 'g1', stageId: 'stage', name: '一年级', sortOrder: 0 },
  { id: 'g2', stageId: 'stage', name: '二年级', sortOrder: 1 },
];
const classes: ClassGroup[] = [
  { id: 'c1', gradeId: 'g1', name: '一(1)班', sortOrder: 0 },
  { id: 'c2', gradeId: 'g1', name: '一(2)班', sortOrder: 1 },
  { id: 'c3', gradeId: 'g2', name: '二(1)班', sortOrder: 0 },
];

test('drag selection covers a rectangle regardless of direction', () => {
  assert.deepEqual(rectangleKeys(subjects, grades, { row: 1, column: 1 }, { row: 0, column: 0 }),
    ['math:g1', 'math:g2', 'science:g1', 'science:g2']);
});

test('batch fill and Delete clear every selected grade cell', () => {
  const keys = ['math:g1', 'science:g2'];
  const filled = applyMatrixCells(keys, '3|1|1', classes, {}, true);
  assert.equal(filled.values['math:c2'].odd, 1);
  assert.equal(filled.values['science:c3'].weekly, 3);
  const cleared = applyMatrixCells(keys, '', classes, filled.values, true);
  assert.equal(cleared.values['math:c1'].weekly, 0);
  assert.equal(cleared.values['science:c3'].even, 0);
});

test('grid paste is atomic and anchors at the original drag start', () => {
  const current = { 'math:c1': { weekly: 9, odd: 0, even: 0 } };
  const selection = rectangleKeys(subjects, grades, { row: 1, column: 1 }, { row: 0, column: 0 });
  const valid = pasteMatrixGrid('2\t3\n4\t5', 'science:g2', selection,
    subjects, grades, classes, current, false);
  assert.equal(valid.values['science:c3'].weekly, 2);
  assert.equal(valid.values['math:c1'].weekly, 9);
  const bad = pasteMatrixGrid('2\tinvalid', 'math:g1', ['math:g1'],
    subjects, grades, classes, current, false);
  assert.match(bad.error ?? '', /第 1 行第 2 列/);
  assert.deepEqual(bad.values, current);
});

test('copy emits class-specific values in tab and newline grid format', () => {
  const values = {
    'math:c1': { weekly: 3, odd: 0, even: 0 },
    'math:c2': { weekly: 4, odd: 0, even: 0 },
    'math:c3': { weekly: 5, odd: 0, even: 0 },
    'science:c1': { weekly: 1, odd: 0, even: 0 },
    'science:c2': { weekly: 1, odd: 0, even: 0 },
    'science:c3': { weekly: 2, odd: 0, even: 0 },
  };
  assert.equal(copyMatrixText(['math:g1', 'math:g2', 'science:g1', 'science:g2'],
    subjects, grades, classes, values), '3,4\t5\n1\t2');
});
