import assert from 'node:assert/strict';
import test from 'node:test';
import type { WorkbenchSummary } from '../../src/domain/models.ts';

async function getProgress(
  hasTerm: boolean,
  summary: WorkbenchSummary | null
) {
  const model = await import('../../src/features/workbench/workbenchModel.ts').catch(
    () => null
  );
  assert.ok(model, 'workbench progress model should be available');
  return model.getWorkbenchProgress(hasTerm, summary);
}

test('routes an empty school to term setup', async () => {
  const progress = await getProgress(false, null);

  assert.equal(progress.nextSection, 'terms');
  assert.equal(progress.completeCount, 0);
  assert.equal(progress.totalCount, 6);
});

test('routes a prepared school to the first incomplete step', async () => {
  const progress = await getProgress(true, {
    termId: 'term-1',
    stageCount: 1,
    gradeCount: 6,
    classCount: 12,
    subjectCount: 8,
    teacherCount: 24,
    publicRoomCount: 0,
    stagesDone: true,
    routineDone: true,
    subjectLessonsReady: false,
    teacherAssignmentsReady: false,
    hasSchedule: false,
  });

  assert.equal(progress.nextSection, 'subjects');
  assert.equal(progress.completeCount, 3);
});

test('does not invent a next task while the active term summary is loading', async () => {
  const progress = await getProgress(true, null);

  assert.equal(progress.isLoading, true);
  assert.equal(progress.nextSection, null);
});

test('reports completion after all six preparation steps are ready', async () => {
  const progress = await getProgress(true, {
    termId: 'term-1',
    stageCount: 1,
    gradeCount: 6,
    classCount: 12,
    subjectCount: 8,
    teacherCount: 24,
    publicRoomCount: 0,
    stagesDone: true,
    routineDone: true,
    subjectLessonsReady: true,
    teacherAssignmentsReady: true,
    hasSchedule: true,
  });

  assert.equal(progress.nextSection, null);
  assert.equal(progress.completeCount, 6);
});
