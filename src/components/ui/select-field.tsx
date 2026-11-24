import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

export interface SelectFieldOption {
  value: string;
  label: string;
}

const EMPTY_OPTION_VALUE = '__select_field_empty_option__';
const PLACEHOLDER_VALUE = '__select_field_placeholder__';

interface SelectFieldProps {
  value: string;
  onValueChange: (value: string) => void;
  options: SelectFieldOption[];
  ariaLabel: string;
  placeholder?: string;
  emptyText?: string;
  className?: string;
  disabled?: boolean;
}

export function SelectField({
  value,
  onValueChange,
  options,
  ariaLabel,
  placeholder = '请选择',
  emptyText = '无可选项',
  className = 'w-auto min-w-[9rem]',
  disabled,
}: SelectFieldProps) {
  const selected = options.find((option) => option.value === value);
  const selectedValue = selected
    ? (selected.value === '' ? EMPTY_OPTION_VALUE : selected.value)
    : PLACEHOLDER_VALUE;

  return (
    <Select
      value={selectedValue}
      disabled={disabled}
      onValueChange={(next) => onValueChange(next === EMPTY_OPTION_VALUE || next === PLACEHOLDER_VALUE ? '' : next)}
    >
      <SelectTrigger aria-label={ariaLabel} className={className}>
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {!selected && <SelectItem value={PLACEHOLDER_VALUE} disabled>
          {options.length ? placeholder : emptyText}
        </SelectItem>}
        {options.map((option) => (
          <SelectItem key={option.value || EMPTY_OPTION_VALUE} value={option.value || EMPTY_OPTION_VALUE}>
            {option.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
