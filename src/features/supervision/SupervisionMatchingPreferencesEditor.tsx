import { ArrowDown, ArrowUp } from 'lucide-react';
import { Checkbox } from '@/components/ui/checkbox';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import type {
  SupervisionMatchMode,
  SupervisionMatchRequirement,
  SupervisionMatchingPreferences,
  SupervisionPreference,
} from '@/domain/supervision';
import { SUPERVISION_PREFERENCE_LABELS } from '@/domain/supervision';

interface SupervisionMatchingPreferencesEditorProps {
  value: SupervisionMatchingPreferences;
  onChange: (value: SupervisionMatchingPreferences) => void;
}

const PREFERENCE_ORDER: SupervisionPreference[] = [
  'classTeacher',
  'gradeTeacher',
  'subjectTeacher',
];

export const MATCH_MODE_LABELS: Record<SupervisionMatchMode, string> = {
  matchFirst: '优先匹配任教关系',
  balanceFirst: '优先均衡带班工作量',
};

export const MATCH_REQUIREMENT_LABELS: Record<SupervisionMatchRequirement, string> = {
  none: '不强制，仅用于排序',
  any: '至少满足一项已启用偏好',
  all: '必须满足全部已启用偏好',
};

export const SupervisionMatchingPreferencesEditor = ({
  value,
  onChange,
}: SupervisionMatchingPreferencesEditorProps) => {
  const order = [
    ...value.order.filter(
      (preference, index, preferences) => preferences.indexOf(preference) === index
    ),
    ...PREFERENCE_ORDER.filter((preference) => !value.order.includes(preference)),
  ];

  const togglePreference = (preference: SupervisionPreference) => {
    const enabled = new Set(value.enabled);
    if (enabled.has(preference)) enabled.delete(preference);
    else enabled.add(preference);
    onChange({
      ...value,
      enabled: PREFERENCE_ORDER.filter((item) => enabled.has(item)),
    });
  };

  const movePreference = (preference: SupervisionPreference, direction: -1 | 1) => {
    const nextOrder = [...order];
    const index = nextOrder.indexOf(preference);
    const nextIndex = index + direction;
    if (index < 0 || nextIndex < 0 || nextIndex >= nextOrder.length) return;
    [nextOrder[index], nextOrder[nextIndex]] = [nextOrder[nextIndex], nextOrder[index]];
    onChange({ ...value, order: nextOrder });
  };

  return (
    <div className="space-y-3 border-t border-border pt-3">
      <div>
        <div className="flex items-center justify-between gap-2">
          <label className="text-xs font-medium text-ink">优先顺序</label>
          <span className="text-[10px] text-ink-secondary">勾选项按此顺序排序</span>
        </div>
        <div className="mt-1.5 space-y-1">
          {order.map((preference, index) => (
            <div
              key={preference}
              className="flex items-center justify-between gap-2 rounded-md px-1.5 py-1 hover:bg-canvas"
            >
              <div className="flex min-w-0 items-center gap-2">
                <Checkbox
                  checked={value.enabled.includes(preference)}
                  onCheckedChange={() => togglePreference(preference)}
                  aria-label={`启用${SUPERVISION_PREFERENCE_LABELS[preference]}`}
                />
                <span className="truncate text-xs text-ink">
                  {SUPERVISION_PREFERENCE_LABELS[preference]}
                </span>
              </div>
              <div className="flex shrink-0 items-center gap-1">
                <span className="w-4 text-center text-[10px] tabular-nums text-ink-secondary">
                  {index + 1}
                </span>
                <button
                  type="button"
                  disabled={index === 0}
                  onClick={() => movePreference(preference, -1)}
                  className="flex h-7 w-7 items-center justify-center rounded text-ink-secondary hover:bg-selection hover:text-primary disabled:cursor-not-allowed disabled:opacity-40"
                  aria-label={`上移${SUPERVISION_PREFERENCE_LABELS[preference]}`}
                >
                  <ArrowUp className="h-3.5 w-3.5" aria-hidden="true" />
                </button>
                <button
                  type="button"
                  disabled={index === order.length - 1}
                  onClick={() => movePreference(preference, 1)}
                  className="flex h-7 w-7 items-center justify-center rounded text-ink-secondary hover:bg-selection hover:text-primary disabled:cursor-not-allowed disabled:opacity-40"
                  aria-label={`下移${SUPERVISION_PREFERENCE_LABELS[preference]}`}
                >
                  <ArrowDown className="h-3.5 w-3.5" aria-hidden="true" />
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3">
        <div>
          <label className="mb-1 block text-xs font-medium text-ink">匹配方式</label>
          <Select
            value={value.mode}
            onValueChange={(mode) =>
              onChange({ ...value, mode: mode as SupervisionMatchMode })
            }
          >
            <SelectTrigger className="h-8 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {Object.entries(MATCH_MODE_LABELS).map(([mode, label]) => (
                <SelectItem key={mode} value={mode}>
                  {label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-ink">偏好要求</label>
          <Select
            value={value.requirement}
            onValueChange={(requirement) =>
              onChange({
                ...value,
                requirement: requirement as SupervisionMatchRequirement,
              })
            }
          >
            <SelectTrigger className="h-8 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {Object.entries(MATCH_REQUIREMENT_LABELS).map(([requirement, label]) => (
                <SelectItem key={requirement} value={requirement}>
                  {label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>
    </div>
  );
};
