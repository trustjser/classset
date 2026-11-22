export function parseNumericDraft(value: string): number | null {
  if (value.trim() === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function normalizeNumericValue(
  value: number | null,
  min: number,
  max: number,
  fallback: number
): number {
  return Math.max(min, Math.min(max, value ?? fallback));
}

type NumericInputDraftAction =
  | { type: 'edit'; value: string }
  | { type: 'normalize'; min: number; max: number; fallback: number }
  | { type: 'restore-empty'; fallback: number };

export function numericInputDraftReducer(
  draft: string,
  action: NumericInputDraftAction
): string {
  if (action.type === 'edit') return action.value;
  if (action.type === 'restore-empty') {
    return parseNumericDraft(draft) === null ? String(action.fallback) : draft;
  }

  return String(
    normalizeNumericValue(
      parseNumericDraft(draft),
      action.min,
      action.max,
      action.fallback
    )
  );
}
