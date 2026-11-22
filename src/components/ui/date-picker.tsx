import { useEffect, useMemo, useState } from 'react';
import { CalendarDays, ChevronLeft, ChevronRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/utils';

const WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六'];

function parseDate(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const [, year, month, day] = match;
  const date = new Date(Number(year), Number(month) - 1, Number(day));
  return date.getFullYear() === Number(year) &&
    date.getMonth() === Number(month) - 1 &&
    date.getDate() === Number(day)
    ? date
    : null;
}

function formatDate(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

export interface DatePickerProps {
  value: string;
  onChange: (value: string) => void;
  min?: string;
  max?: string;
  placeholder?: string;
  ariaLabel?: string;
  className?: string;
}

export function DatePicker({
  value,
  onChange,
  min,
  max,
  placeholder = '选择日期',
  ariaLabel = '选择日期',
  className,
}: DatePickerProps) {
  const selectedDate = parseDate(value);
  const [open, setOpen] = useState(false);
  const [visibleMonth, setVisibleMonth] = useState(() => {
    const initial = selectedDate ?? new Date();
    return new Date(initial.getFullYear(), initial.getMonth(), 1);
  });

  useEffect(() => {
    const nextDate = parseDate(value);
    if (nextDate) setVisibleMonth(new Date(nextDate.getFullYear(), nextDate.getMonth(), 1));
  }, [value]);

  const dates = useMemo(() => {
    const monthStart = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1);
    const gridStart = new Date(
      monthStart.getFullYear(),
      monthStart.getMonth(),
      1 - monthStart.getDay()
    );
    return Array.from({ length: 42 }, (_, index) =>
      new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + index)
    );
  }, [visibleMonth]);

  const previousMonthEnd = formatDate(
    new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 0)
  );
  const nextMonthStart = formatDate(
    new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + 1, 1)
  );

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          aria-label={ariaLabel}
          className={cn(
            'h-9 w-full justify-start gap-2 border-control-border px-3 text-left text-[12.5px] font-normal',
            !value && 'text-ink-secondary',
            className
          )}
          type="button"
          variant="outline"
        >
          <CalendarDays aria-hidden="true" className="h-4 w-4 shrink-0 text-ink-secondary" />
          <span className="truncate font-mono">{value || placeholder}</span>
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-[280px] p-3">
        <div className="mb-3 flex items-center justify-between">
          <Button
            aria-label="上个月"
            className="h-8 w-8"
            disabled={Boolean(min && previousMonthEnd < min)}
            onClick={() => setVisibleMonth((month) => new Date(month.getFullYear(), month.getMonth() - 1, 1))}
            size="icon"
            type="button"
            variant="ghost"
          >
            <ChevronLeft aria-hidden="true" className="h-4 w-4" />
          </Button>
          <div aria-live="polite" className="text-[13px] font-semibold">
            {visibleMonth.getFullYear()} 年 {visibleMonth.getMonth() + 1} 月
          </div>
          <Button
            aria-label="下个月"
            className="h-8 w-8"
            disabled={Boolean(max && nextMonthStart > max)}
            onClick={() => setVisibleMonth((month) => new Date(month.getFullYear(), month.getMonth() + 1, 1))}
            size="icon"
            type="button"
            variant="ghost"
          >
            <ChevronRight aria-hidden="true" className="h-4 w-4" />
          </Button>
        </div>
        <div className="grid grid-cols-7 text-center">
          {WEEKDAYS.map((weekday) => (
            <div className="py-1.5 text-[10.5px] font-medium text-ink-secondary" key={weekday}>
              {weekday}
            </div>
          ))}
          {dates.map((date) => {
            const dateValue = formatDate(date);
            const inVisibleMonth = date.getMonth() === visibleMonth.getMonth();
            const isDisabled = Boolean((min && dateValue < min) || (max && dateValue > max));
            const isSelected = dateValue === value;
            const isToday = dateValue === formatDate(new Date());
            return (
              <button
                aria-label={dateValue}
                aria-pressed={isSelected}
                className={cn(
                  'mx-auto flex h-8 w-8 items-center justify-center rounded-md text-[11.5px] transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  isSelected
                    ? 'bg-primary font-semibold text-primary-foreground'
                    : 'text-ink hover:bg-selection hover:text-primary',
                  !inVisibleMonth && 'text-ink-secondary/45',
                  isToday && !isSelected && 'border border-primary/35',
                  isDisabled && 'pointer-events-none opacity-30'
                )}
                disabled={isDisabled}
                key={dateValue}
                onClick={() => {
                  onChange(dateValue);
                  setOpen(false);
                }}
                type="button"
              >
                {date.getDate()}
              </button>
            );
          })}
        </div>
      </PopoverContent>
    </Popover>
  );
}
