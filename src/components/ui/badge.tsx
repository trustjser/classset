import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

const badgeVariants = cva(
  'inline-flex items-center rounded-[6px] px-2 py-0.5 text-[12px] font-medium transition-colors duration-feedback',
  {
    variants: {
      variant: {
        default: 'bg-selection text-primary font-semibold',
        secondary: 'bg-table-header text-ink-secondary border border-table-divider',
        success: 'bg-success-surface text-success font-semibold',
        warning: 'bg-warning-surface text-warning font-semibold',
        destructive: 'bg-destructive-surface text-destructive font-semibold',
        outline: 'border border-border text-ink-secondary',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  }
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps) {
  return (
    <div className={cn(badgeVariants({ variant }), className)} {...props} />
  );
}

export { Badge, badgeVariants };
