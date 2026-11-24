import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Search } from 'lucide-react';
import { Input } from '@/components/ui/input';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { cn } from '@/lib/utils';

export interface SearchableSelectOption {
  value: string;
  label: string;
  keywords?: string;
}

interface SearchableSelectProps {
  value: string;
  onValueChange: (value: string) => void;
  options: SearchableSelectOption[];
  placeholder?: string;
  searchPlaceholder?: string;
  emptyText?: string;
  ariaLabel?: string;
  className?: string;
  triggerClassName?: string;
  disabled?: boolean;
}

const EMPTY_SENTINEL = '__searchable_select_empty__';

export const SearchableSelect: React.FC<SearchableSelectProps> = ({
  value,
  onValueChange,
  options,
  placeholder = '请选择',
  searchPlaceholder = '搜索…',
  emptyText = '无匹配项',
  ariaLabel,
  className,
  triggerClassName,
  disabled,
}) => {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const searchInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!open) return;
    const frame = requestAnimationFrame(() => searchInputRef.current?.focus());
    return () => cancelAnimationFrame(frame);
  }, [open]);

  const selectedOption = useMemo(
    () => options.find((item) => item.value === value),
    [options, value]
  );

  const filteredOptions = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return options;
    return options.filter((item) => {
      const target = `${item.label} ${item.keywords ?? ''}`.toLowerCase();
      return target.includes(q);
    });
  }, [options, query]);

  return (
    <Select
      disabled={disabled}
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (!next) setQuery('');
      }}
      value={value || EMPTY_SENTINEL}
      onValueChange={(next) => {
        if (next === EMPTY_SENTINEL) return;
        onValueChange(next);
      }}
    >
      <SelectTrigger aria-label={ariaLabel} className={cn(triggerClassName, className)}>
        <SelectValue placeholder={placeholder}>
          {selectedOption ? selectedOption.label : placeholder}
        </SelectValue>
      </SelectTrigger>
      <SelectContent
        onCloseAutoFocus={(event) => {
          event.preventDefault();
        }}
      >
        <div
          className="sticky top-0 z-10 mb-1 border-b border-border bg-surface pb-1.5"
          onPointerDown={(event) => event.stopPropagation()}
        >
          <div className="relative">
            <Search
              aria-hidden="true"
              className="pointer-events-none absolute left-2 top-2 h-3.5 w-3.5 text-ink-secondary"
            />
            <Input
              ref={searchInputRef}
              aria-label={searchPlaceholder}
              className="h-7 pl-7 text-[12px]"
              onChange={(event) => setQuery(event.target.value)}
              onKeyDown={(event) => {
                if (event.key !== 'Escape' && event.key !== 'Tab') {
                  event.stopPropagation();
                }
              }}
              placeholder={searchPlaceholder}
              value={query}
            />
          </div>
        </div>
        {filteredOptions.length === 0 ? (
          <div className="px-2.5 py-3 text-center text-[12px] text-ink-secondary">
            {emptyText}
          </div>
        ) : (
          filteredOptions.map((item) => (
            <SelectItem key={item.value} value={item.value}>
              {item.label}
            </SelectItem>
          ))
        )}
      </SelectContent>
    </Select>
  );
};
