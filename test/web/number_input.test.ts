import assert from 'node:assert/strict';
import test from 'node:test';

async function getNumberInputHelpers() {
  const module = await import('../../src/lib/numberInput.ts').catch(() => null);
  assert.ok(module, 'numeric input draft helpers should be available');
  assert.equal(
    typeof module.numericInputDraftReducer,
    'function',
    'numeric input drafts should support edits and blur commits'
  );
  return module;
}

test('preserves an empty draft and accepts a re-entered value', async () => {
  const { numericInputDraftReducer } = await getNumberInputHelpers();

  const cleared = numericInputDraftReducer('2', { type: 'edit', value: '' });
  assert.equal(cleared, '');
  assert.equal(
    numericInputDraftReducer(cleared, { type: 'edit', value: '12' }),
    '12'
  );
});

test('normalizes a numeric draft to its range or fallback on blur', async () => {
  const { numericInputDraftReducer } = await getNumberInputHelpers();

  assert.equal(
    numericInputDraftReducer('31', {
      type: 'normalize',
      min: 1,
      max: 30,
      fallback: 2,
    }),
    '30'
  );
  assert.equal(
    numericInputDraftReducer('', {
      type: 'normalize',
      min: 1,
      max: 30,
      fallback: 2,
    }),
    '2'
  );
});

test('restores empty defaults without hiding out-of-range term values', async () => {
  const { numericInputDraftReducer } = await getNumberInputHelpers();

  assert.equal(
    numericInputDraftReducer('', { type: 'restore-empty', fallback: 20 }),
    '20'
  );
  assert.equal(
    numericInputDraftReducer('60', { type: 'restore-empty', fallback: 20 }),
    '60'
  );
});
