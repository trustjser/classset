import assert from 'node:assert/strict';
import test from 'node:test';
import type { LessonPeriodType } from '../../src/domain/models.ts';

async function complete(periods: LessonPeriodType[]) {
  const routineUtils = await import('../../src/domain/routineUtils.ts');
  assert.equal(
    typeof routineUtils.completeRoutinePeriodTypes,
    'function',
    '作息标准化需要补齐固定时段'
  );
  return routineUtils.completeRoutinePeriodTypes(periods, 'stage-1');
}

test('new routine includes an editable morning period with zero lessons', async () => {
  const periods = await complete([]);
  assert.deepEqual(
    periods.map((period) => [period.name, period.defaultLessonCount]),
    [['早上', 0], ['上午', 4], ['下午', 4], ['晚上', 2]]
  );
});

test('existing three-period routine gains morning without changing saved period IDs', async () => {
  const source: LessonPeriodType[] = [
    { id: 'am', stageId: 'stage-1', name: '上午', defaultLessonCount: 3, sortOrder: 0 },
    { id: 'pm', stageId: 'stage-1', name: '下午', defaultLessonCount: 4, sortOrder: 1 },
    { id: 'evening', stageId: 'stage-1', name: '晚上', defaultLessonCount: 1, sortOrder: 2 },
  ];
  const periods = await complete(source);
  assert.deepEqual(periods.map((period) => period.name), ['早上', '上午', '下午', '晚上']);
  assert.equal(periods[0].defaultLessonCount, 0);
  assert.deepEqual(periods.slice(1).map((period) => period.id), ['am', 'pm', 'evening']);
});
