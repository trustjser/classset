import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import { build } from 'esbuild';

test('Excel template round-trips the original grade and per-class lesson format', async () => {
  const folder = await mkdtemp(join(tmpdir(), 'classset-workbook-'));
  try {
    const bundle = join(folder, 'subjectWorkbook.mjs');
    await build({ entryPoints: [fileURLToPath(new URL('../../src/features/subjects/subjectWorkbook.ts', import.meta.url))],
      outfile: bundle, bundle: true, platform: 'node', format: 'esm' });
    const { buildSubjectWorkbook, parseSubjectWorkbook } = await import(pathToFileURL(bundle).href);
    const stages = [{ id: 'stage', termId: 'term', name: '小学部', sortOrder: 0 }];
    const grades = [{ id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0 }];
    const classes = [
      { id: 'c1', gradeId: 'grade', name: '一(1)班', sortOrder: 0 },
      { id: 'c2', gradeId: 'grade', name: '一(2)班', sortOrder: 1 },
    ];
    const subjects = [{ id: 'math', termId: 'term', name: '数学', shortName: '数', sortOrder: 0 }];
    const bytes = await buildSubjectWorkbook({ stages, grades, classes, subjects,
      values: { 'math:c1': { weekly: 3, odd: 1, even: 0 },
        'math:c2': { weekly: 4, odd: 0, even: 1 } }, includeExisting: true });
    assert.ok(bytes.length > 1000);
    const plan = await parseSubjectWorkbook(bytes, stages, grades, classes, subjects, true);
    assert.deepEqual(plan.errors, []);
    assert.equal(plan.values['math:c1'].odd, 1);
    assert.equal(plan.values['math:c2'].even, 1);
    const bad = await parseSubjectWorkbook(new Uint8Array([1, 2, 3]), stages, grades, classes, subjects, false);
    assert.ok(bad.errors.length > 0);
  } finally {
    await rm(folder, { recursive: true, force: true });
  }
});
