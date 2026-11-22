import { useState } from 'react';
import { Check, ChevronDown, Clock3, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/utils';

function toMinutes(value: string | undefined): number | null {
  if (!value) return null;
  const match = /^(\d{2}):(\d{2})$/.exec(value);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  return hours <= 23 && minutes <= 59 ? hours * 60 + minutes : null;
}

function fromMinutes(value: number): string {
  return `${String(Math.floor(value / 60)).padStart(2, '0')}:${String(value % 60).padStart(2, '0')}`;
}

export interface TimePickerProps {
  value: string;
  onChange: (value: string) => void;
  min?: string;
  max?: string;
  placeholder?: string;
  ariaLabel?: string;
  className?: string;
  allowClear?: boolean;
}

export function TimePicker({
  value,
  onChange,
  min,
  max,
  placeholder = '选择时间',
  ariaLabel = '选择时间',
  className,
  allowClear = false,
}: TimePickerProps) {
  const [open, setOpen] = useState(false);
  const [pendingMinutes, setPendingMinutes] = useState(() => toMinutes(value) ?? 8 * 60);
  const selectedMinutes = toMinutes(value);
  const minMinutes = toMinutes(min);
  const maxMinutes = toMinutes(max);
  const pendingHour = Math.floor(pendingMinutes / 60);
  const pendingMinute = pendingMinutes % 60;
  const isAllowed = (minutes: number) =>
    (minMinutes === null || minutes >= minMinutes) &&
    (maxMinutes === null || minutes <= maxMinutes);

  return (
    <Popover
      open={open}
      onOpenChange={(nextOpen) => {
        if (nextOpen) setPendingMinutes(selectedMinutes ?? 8 * 60);
        setOpen(nextOpen);
      }}
    >
      <PopoverTrigger asChild>
        <Button
          aria-label={ariaLabel}
          className={cn(
            'h-9 w-full min-w-0 justify-between overflow-hidden border-control-border px-2.5 text-[12.5px] font-normal tabular-nums',
            !value && 'text-ink-secondary',
            className
          )}
          title={value || placeholder}
          type="button"
          variant="outline"
        >
          <span className="inline-flex min-w-0 flex-1 items-center gap-1.5 overflow-hidden whitespace-nowrap">
            <Clock3 aria-hidden="true" className="h-3.5 w-3.5 shrink-0 text-ink-secondary" />
            <span className="min-w-0 truncate">{value || placeholder}</span>
          </span>
          <ChevronDown aria-hidden="true" className="h-3.5 w-3.5 shrink-0 text-ink-secondary" />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-[248px] p-3">
        <div className="mb-2 flex items-center justify-between">
          <span className="text-[11px] font-medium text-ink-secondary">选择时间</span>
          <span className="font-mono text-[16px] font-semibold tabular-nums text-ink">
            {fromMinutes(pendingMinutes)}
          </span>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <div className="mb-1 text-center text-[10px] text-ink-secondary">时</div>
            <div aria-label="小时" className="h-48 overflow-y-auto rounded-md border border-border p-1">
              {Array.from({ length: 24 }, (_, hour) => {
                const nextMinutes = hour * 60 + pendingMinute;
                const isSelected = hour === pendingHour;
                return (
                  <button
                    aria-pressed={isSelected}
                    className={cn(
                      'flex h-7 w-full items-center justify-center rounded text-[11.5px] tabular-nums transition-colors hover:bg-selection',
                      isSelected && 'bg-selection font-semibold text-primary',
                      !isAllowed(nextMinutes) && 'pointer-events-none opacity-35'
                    )}
                    disabled={!isAllowed(nextMinutes)}
                    key={hour}
                    onClick={() => setPendingMinutes(nextMinutes)}
                    type="button"
                  >
                    {String(hour).padStart(2, '0')}
                  </button>
                );
              })}
            </div>
          </div>
          <div>
            <div className="mb-1 text-center text-[10px] text-ink-secondary">分</div>
            <div aria-label="分钟" className="h-48 overflow-y-auto rounded-md border border-border p-1">
              {Array.from({ length: 60 }, (_, minute) => {
                const nextMinutes = pendingHour * 60 + minute;
                const isSelected = minute === pendingMinute;
                return (
                  <button
                    aria-pressed={isSelected}
                    className={cn(
                      'flex h-7 w-full items-center justify-center rounded text-[11.5px] tabular-nums transition-colors hover:bg-selection',
                      isSelected && 'bg-selection font-semibold text-primary',
                      !isAllowed(nextMinutes) && 'pointer-events-none opacity-35'
                    )}
                    disabled={!isAllowed(nextMinutes)}
                    key={minute}
                    onClick={() => setPendingMinutes(nextMinutes)}
                    type="button"
                  >
                    {String(minute).padStart(2, '0')}
                  </button>
                );
              })}
            </div>
          </div>
        </div>
        <div className="mt-3 flex justify-between gap-2">
          {allowClear ? (
            <Button
              className="h-8 px-2.5 text-[11px]"
              disabled={!value}
              onClick={() => {
                onChange('');
                setOpen(false);
              }}
              type="button"
              variant="ghost"
            >
              <X aria-hidden="true" className="h-3.5 w-3.5" />
              清空
            </Button>
          ) : <span />}
          <Button
            className="h-8 px-3 text-[11px]"
            disabled={!isAllowed(pendingMinutes)}
            onClick={() => {
              onChange(fromMinutes(pendingMinutes));
              setOpen(false);
            }}
            type="button"
          >
            <Check aria-hidden="true" className="h-3.5 w-3.5" />
            确定
          </Button>
        </div>
      </PopoverContent>
    </Popover>
  );
}
