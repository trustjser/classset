import * as React from 'react';
import { cn } from '@/lib/utils';

export interface ProgressProps extends React.ComponentPropsWithoutRef<'div'> {
  value?: number | null;
}

const Progress = React.forwardRef<HTMLDivElement, ProgressProps>(
  ({ className, value, ...props }, ref) => {
    const percent = value === null || value === undefined || !Number.isFinite(value)
      ? null
      : Math.min(100, Math.max(0, value));

    return (
      <div
        {...props}
        ref={ref}
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={percent ?? undefined}
        aria-valuetext={percent === null ? '正在准备排课' : `${Math.round(percent)}%`}
        className={cn('relative h-2 w-full overflow-hidden rounded-full bg-table-header', className)}
      >
        <div
          className={cn('h-full rounded-full bg-primary transition-[width] duration-300 ease-out', percent === null && 'w-2/5 animate-pulse')}
          style={percent === null ? undefined : { width: `${percent}%` }}
        />
      </div>
    );
  }
);
Progress.displayName = 'Progress';

export { Progress };
