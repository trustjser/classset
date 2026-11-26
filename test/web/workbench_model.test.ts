import assert from 'node:assert/strict';
import test from 'node:test';
import type { WorkbenchSummary } from '../../src/domain/models.ts';

async function loadModel() {
  const model = await import('../../src/features/workbench/workbenchModel.ts').catch(
    () => null
  );
  assert.ok(model, 'workbench progress model should be available');
  return model;
}

test('routes an empty school to term setup with 4 preparation steps', async () => {
  const model = await loadModel();
  const progress = model.getWorkbenchProgress(false, null);

  assert.equal(progress.nextSection, 'terms');
  assert.equal(progress.completeCount, 0);
  assert.equal(progress.totalCount, 4);
  assert.equal(progress.steps.length, 4);
});

test('routes a prepared school to the first incomplete step among the 4 setup steps', async () => {
  const model = await loadModel();
  const summary: WorkbenchSummary = {
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
  };
  const progress = model.getWorkbenchProgress(true, summary);

  assert.equal(progress.nextSection, 'subjects');
  assert.equal(progress.completeCount, 2);
  assert.equal(progress.totalCount, 4);
});

test('does not invent a next task while the active term summary is loading', async () => {
  const model = await loadModel();
  const progress = model.getWorkbenchProgress(true, null);

  assert.equal(progress.isLoading, true);
  assert.equal(progress.nextSection, null);
});

test('reports all 4 basic setup steps ready and provides scheduling jump entry', async () => {
  const model = await loadModel();
  const summary: WorkbenchSummary = {
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
    hasSchedule: false,
  };
  const progress = model.getWorkbenchProgress(true, summary);

  assert.equal(progress.completeCount, 4);
  assert.equal(progress.totalCount, 4);
  assert.equal(progress.nextSection, 'scheduling');

  const unscheduledEntry = model.getScheduleEntryCopy(summary);
  assert.equal(unscheduledEntry.targetSection, 'scheduling');
  assert.equal(unscheduledEntry.actionLabel, '去排课');

  const scheduledEntry = model.getScheduleEntryCopy({
    ...summary,
    hasSchedule: true,
  });
  assert.equal(scheduledEntry.targetSection, 'scheduling');
  assert.equal(scheduledEntry.actionLabel, '打开课表');
});
