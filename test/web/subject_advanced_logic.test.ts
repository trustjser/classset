import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test, { after } from 'node:test';
import { build } from 'esbuild';
import type { SubjectLessonConstraint } from '../../src/domain/models.ts';

const folder = await mkdtemp(join(tmpdir(), 'classset-advanced-'));
const bundle = join(folder, 'advanced.mjs');
await build({ entryPoints: [fileURLToPath(new URL('../../src/features/subjects/subjectAdvancedLogic.ts', import.meta.url))],
  outfile: bundle, bundle: true, platform: 'node', format: 'esm' });
const { resolveConstraintField, validateConstraintRanges } = await import(pathToFileURL(bundle).href);
after(() => rm(folder, { recursive: true, force: true }));

const stage = { id: 'stage', termId: 'term', name: '小学部', sortOrder: 0 };
const grade = { id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0 };
const schoolClass = { id: 'class', gradeId: 'grade', name: '一(1)班', sortOrder: 0 };
const row = (scopeType: SubjectLessonConstraint['scopeType'], scopeId: string,
  weekday: number | null, fields: Partial<SubjectLessonConstraint>): SubjectLessonConstraint => ({
  id: `${scopeType}-${scopeId}-${weekday}`, subjectId: 'subject', scopeType, scopeId, stageId: 'stage', weekday,
  minimumDailyLessons: null, maximumDailyLessons: null,
  minimumDailyConsecutivePairs: null, maximumDailyConsecutivePairs: null,
  minimumWeeklyConsecutivePairs: null, maximumWeeklyConsecutivePairs: null, ...fields,
});

test('weekday and class overrides inherit missing fields from wider scopes and daily defaults', () => {
  const rows = [
    row('stage', 'stage', null, { minimumDailyLessons: 1, maximumDailyLessons: 4 }),
    row('grade', 'grade', 2, { minimumDailyLessons: 2 }),
    row('class', 'class', null, { maximumDailyLessons: 3 }),
  ];
  assert.equal(resolveConstraintField(rows, [schoolClass], 'term', 'class', 'class', 'stage', 2, 'minimumDailyLessons'), 2);
  assert.equal(resolveConstraintField(rows, [schoolClass], 'term', 'class', 'class', 'stage', 2, 'maximumDailyLessons'), 3);
  assert.equal(resolveConstraintField(rows, [schoolClass], 'term', 'class', 'class', 'stage', 3, 'minimumDailyLessons'), 1);
});

test('rejects bounds that conflict only after scope inheritance', () => {
  const rows = [
    row('stage', 'stage', null, { minimumDailyLessons: 3 }),
    row('grade', 'grade', 2, { maximumDailyLessons: 2 }),
  ];
  assert.match(validateConstraintRanges(rows, [stage], [grade], [schoolClass], { stage: [1, 2] }, 'term') ?? '', /上下限冲突/);
  assert.equal(validateConstraintRanges([row('grade', 'grade', 2, { maximumDailyLessons: 4 }), rows[0]],
    [stage], [grade], [schoolClass], { stage: [1, 2] }, 'term'), null);
});
