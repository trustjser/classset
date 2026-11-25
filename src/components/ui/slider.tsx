import * as React from 'react';
import { cn } from '@/lib/utils';

export interface SliderProps
  extends Omit<React.HTMLAttributes<HTMLDivElement>, 'defaultValue' | 'onChange'> {
  value?: number[];
  defaultValue?: number[];
  min?: number;
  max?: number;
  step?: number;
  disabled?: boolean;
  onValueChange?: (value: number[]) => void;
}

function clampAndStep(raw: number, min: number, max: number, step: number): number {
  const clamped = Math.min(max, Math.max(min, raw));
  if (step <= 0) return clamped;
  const steps = Math.round((clamped - min) / step);
  return Math.min(max, Math.max(min, min + steps * step));
}

const Slider = React.forwardRef<HTMLDivElement, SliderProps>(
  (
    {
      className,
      value,
      defaultValue,
      min = 0,
      max = 100,
      step = 1,
      disabled = false,
      onValueChange,
      'aria-label': ariaLabel,
      'aria-labelledby': ariaLabelledBy,
      ...props
    },
    ref
  ) => {
    const trackRef = React.useRef<HTMLDivElement | null>(null);
    const [internalValue, setInternalValue] = React.useState<number[]>(
      () => defaultValue ?? [min]
    );
    const currentValues = value ?? internalValue;
    const current = clampAndStep(currentValues[0] ?? min, min, max, step);
    const span = Math.max(1e-6, max - min);
    const percent = Math.min(100, Math.max(0, ((current - min) / span) * 100));

    const commitValue = React.useCallback(
      (nextVal: number) => {
        if (disabled) return;
        const normalized = clampAndStep(nextVal, min, max, step);
        if (normalized === current) return;
        const nextArray = [normalized];
        if (value === undefined) {
          setInternalValue(nextArray);
        }
        onValueChange?.(nextArray);
      },
      [current, disabled, max, min, onValueChange, step, value]
    );

    const updateFromClientX = React.useCallback(
      (clientX: number) => {
        const track = trackRef.current;
        if (!track || disabled) return;
        const rect = track.getBoundingClientRect();
        if (rect.width <= 0) return;
        const ratio = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
        commitValue(min + ratio * (max - min));
      },
      [commitValue, disabled, max, min]
    );

    const handlePointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
      if (disabled) return;
      event.preventDefault();
      event.currentTarget.setPointerCapture(event.pointerId);
      updateFromClientX(event.clientX);
    };

    const handlePointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
      if (disabled || !event.currentTarget.hasPointerCapture(event.pointerId)) return;
      updateFromClientX(event.clientX);
    };

    const handleKeyDown = (event: React.KeyboardEvent<HTMLSpanElement>) => {
      if (disabled) return;
      if (event.key === 'ArrowRight' || event.key === 'ArrowUp') {
        event.preventDefault();
        commitValue(current + step);
      } else if (event.key === 'ArrowLeft' || event.key === 'ArrowDown') {
        event.preventDefault();
        commitValue(current - step);
      } else if (event.key === 'Home') {
        event.preventDefault();
        commitValue(min);
      } else if (event.key === 'End') {
        event.preventDefault();
        commitValue(max);
      } else if (event.key === 'PageUp') {
        event.preventDefault();
        commitValue(current + step * 2);
      } else if (event.key === 'PageDown') {
        event.preventDefault();
        commitValue(current - step * 2);
      }
    };

    return (
      <div
        ref={ref}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        className={cn(
          'relative flex h-5 w-full touch-none select-none items-center',
          disabled ? 'cursor-not-allowed opacity-50' : 'cursor-pointer',
          className
        )}
        {...props}
      >
        <div
          ref={trackRef}
          className="relative h-1.5 w-full grow overflow-hidden rounded-full bg-border"
        >
          <div
            className="absolute h-full bg-primary"
            style={{ width: `${percent}%` }}
          />
        </div>
        <span
          role="slider"
          tabIndex={disabled ? -1 : 0}
          aria-label={ariaLabel}
          aria-labelledby={ariaLabelledBy}
          aria-valuemin={min}
          aria-valuemax={max}
          aria-valuenow={current}
          aria-disabled={disabled}
          onKeyDown={handleKeyDown}
          style={{ left: `calc(${percent}% - 8px)` }}
          className="absolute block h-4 w-4 rounded-full border-2 border-primary bg-surface shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none"
        />
      </div>
    );
  }
);
Slider.displayName = 'Slider';

export { Slider };
