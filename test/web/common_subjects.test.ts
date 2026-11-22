import assert from 'node:assert/strict';
import test from 'node:test';
import { buildSubjectDraftInputs, COMMON_SUBJECTS, firstSubjectCharacter } from '../../src/features/subjects/commonSubjects.ts';

test('common subjects match the original quick-add list and keep its order', () => {
  assert.equal(COMMON_SUBJECTS.length, 18);
  const result = buildSubjectDraftInputs({ isNew: true, name: '', shortName: '',
    selectedCommonSubjects: ['音乐', '语文'], existingNames: [] });
  assert.equal(result.error, null);
  assert.deepEqual(result.subjects, [
    { name: '语文', shortName: '语' }, { name: '音乐', shortName: '音' },
  ]);
});

test('manual entry combines with quick-add and rejects duplicate names', () => {
  const combined = buildSubjectDraftInputs({ isNew: true, name: '书法', shortName: '书',
    selectedCommonSubjects: ['语文'], existingNames: [] });
  assert.deepEqual(combined.subjects.map((item) => item.name), ['书法', '语文']);
  assert.match(buildSubjectDraftInputs({ isNew: true, name: '语文', shortName: '语',
    selectedCommonSubjects: ['语文'], existingNames: [] }).error ?? '', /常用科目/);
  assert.match(buildSubjectDraftInputs({ isNew: true, name: '', shortName: '',
    selectedCommonSubjects: ['语文'], existingNames: ['语文'] }).error ?? '', /已存在/);
  assert.equal(firstSubjectCharacter(' 综合实践活动'), '综');
});
