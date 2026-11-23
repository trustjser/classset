import React, { useEffect, useState } from 'react';
import { Plus, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { SearchableSelect } from '@/components/ui/searchable-select';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import type { Teacher, TeacherAssignment, WeekMode } from '@/domain/models';

export type AssignmentDraft = {
  id?: string;
  teacherId: string;
  weekMode: WeekMode;
  lessonCount: number;
  combinedLessonGroupId?: string | null;
};

const modes: WeekMode[] = ['weekly', 'odd', 'even'];
const modeLabels: Record<WeekMode, string> = { weekly: '每周', odd: '单周', even: '双周' };

type EditorBodyProps = {
  className: string;
  subjectName: string;
  initialDrafts: AssignmentDraft[];
  teachers: Teacher[];
  required: Record<WeekMode, number>;
  error?: string;
  headerClassName?: string;
  onCancel: () => void;
  onSave: (drafts: AssignmentDraft[]) => Promise<boolean>;
};

const AssignmentEditorBody: React.FC<EditorBodyProps> = ({
  className,
  subjectName,
  initialDrafts,
  teachers,
  required,
  error,
  headerClassName,
  onCancel,
  onSave,
}) => {
  const [drafts, setDrafts] = useState<AssignmentDraft[]>(initialDrafts);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setDrafts(initialDrafts);
  }, [initialDrafts]);

  const availableModes = modes.filter((mode) => required[mode] > 0);
  const defaultMode = availableModes[0] ?? 'weekly';
  const newDraft = (): AssignmentDraft => ({ teacherId: '', weekMode: defaultMode, lessonCount: 1 });
  const assignedByMode = Object.fromEntries(
    modes.map((mode) => [
      mode,
      drafts.filter((row) => row.teacherId && row.weekMode === mode).reduce((sum, row) => sum + row.lessonCount, 0),
    ]),
  ) as Record<WeekMode, number>;
  const remaining = modes
    .filter((mode) => required[mode] > 0)
    .map((mode) => `${modeLabels[mode]} ${required[mode] - assignedByMode[mode]} 节`)
    .join(' · ');
  const invalid =
    drafts.some((row) => !row.teacherId || !availableModes.includes(row.weekMode) || !Number.isInteger(row.lessonCount) || row.lessonCount < 1) ||
    modes.some((mode) => assignedByMode[mode] > required[mode]);
  const update = (index: number, patch: Partial<AssignmentDraft>) =>
    setDrafts((rows) => rows.map((row, at) => (at === index ? { ...row, ...patch } : row)));
  const teacherOptions = teachers.map((teacher) => ({
    value: teacher.id,
    label: teacher.displayQualifier ? `${teacher.name} · ${teacher.displayQualifier}` : teacher.name,
    keywords: `${teacher.shortName} ${teacher.displayQualifier}`,
  }));

  return (
    <div className="text-[12px]">
      <div className={`mb-2 flex items-center justify-between gap-2 ${headerClassName ?? ''}`}>
        <strong className="min-w-0 truncate text-[14px]">
          分配 {className} {subjectName} {modes.reduce((sum, mode) => sum + required[mode], 0)}节
        </strong>
        <button type="button" className="inline-flex shrink-0 items-center gap-1 text-primary" onClick={() => setDrafts((rows) => [...rows, newDraft()])}>
          <Plus className="h-4 w-4" />添加分担教师
        </button>
      </div>
      <div className="grid grid-cols-[minmax(0,1fr)_96px_72px_24px] gap-2 border-b border-border pb-1.5 text-ink-secondary">
        <span>教师</span><span>周模式</span><span>节数</span>
      </div>
      <div className="max-h-64 space-y-2 overflow-y-auto py-2">
        {drafts.map((row, index) => (
          <div key={row.id ?? `new-${index}`} className="grid grid-cols-[minmax(0,1fr)_96px_72px_24px] items-center gap-2">
            <SearchableSelect
              ariaLabel="教师"
              value={row.teacherId}
              onValueChange={(teacherId) => update(index, { teacherId })}
              options={teacherOptions}
              placeholder="请选择教师"
              searchPlaceholder="搜索教师…"
              emptyText="未找到匹配教师"
              triggerClassName="h-9 min-w-0"
            />
            <Select value={row.weekMode} onValueChange={(value) => update(index, { weekMode: value as WeekMode })}>
              <SelectTrigger aria-label="周模式" className="h-9 min-w-0 px-2">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {availableModes.map((mode) => (
                  <SelectItem key={mode} value={mode}>{modeLabels[mode]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Input
              aria-label="节数"
              type="number"
              min={1}
              className="h-9 px-2"
              value={row.lessonCount}
              onChange={(event) => update(index, { lessonCount: Number(event.target.value) })}
            />
            <button
              type="button"
              aria-label="移除此行"
              disabled={drafts.length === 1}
              onClick={() => setDrafts((rows) => rows.filter((_, at) => at !== index))}
              className="text-ink-secondary disabled:opacity-30"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        ))}
      </div>
      <div className={`text-ink-secondary ${modes.some((mode) => assignedByMode[mode] > required[mode]) ? 'text-warning' : ''}`}>
        剩余可分配：{remaining}
      </div>
      {error && <div role="alert" className="mt-2 text-destructive">{error}</div>}
      <div className="mt-1 text-ink-secondary">未分配节数留在课程池，无需添加“未分配”分担行。</div>
      <div className="mt-3 flex justify-end gap-2">
        <Button variant="ghost" size="sm" onClick={onCancel}>取消</Button>
        <Button
          size="sm"
          disabled={saving || invalid}
          onClick={async () => {
            setSaving(true);
            try {
              await onSave(drafts);
            } finally {
              setSaving(false);
            }
          }}
        >
          保存
        </Button>
      </div>
    </div>
  );
};

type Props = {
  className: string;
  subjectName: string;
  assignments: TeacherAssignment[];
  teachers: Teacher[];
  required: Record<WeekMode, number>;
  disabled?: boolean;
  error?: string;
  onSave: (drafts: AssignmentDraft[]) => Promise<boolean>;
};

export const AssignmentCellPopover: React.FC<Props> = ({ className, subjectName, assignments, teachers, required, disabled, error, onSave }) => {
  const [open, setOpen] = useState(false);
  const [initialDrafts, setInitialDrafts] = useState<AssignmentDraft[]>([]);
  const availableModes = modes.filter((mode) => required[mode] > 0);
  const defaultMode = availableModes[0] ?? 'weekly';
  const setOpened = (next: boolean) => {
    if (next) {
      setInitialDrafts(
        assignments.length
          ? assignments.map((item) => ({
              id: item.id,
              teacherId: item.teacherId ?? '',
              weekMode: item.weekMode,
              lessonCount: item.lessonCount,
              combinedLessonGroupId: item.combinedLessonGroupId,
            }))
          : [{ teacherId: '', weekMode: defaultMode, lessonCount: 1 }],
      );
    }
    setOpen(next);
  };
  const unassigned = modes
    .filter((mode) => required[mode] > 0)
    .map((mode) => {
      const count = required[mode] - assignments.filter((item) => item.weekMode === mode && item.teacherId).reduce((sum, item) => sum + item.lessonCount, 0);
      return count > 0 ? `未分配(${mode === 'weekly' ? '' : mode === 'odd' ? '单·' : '双·'}${count})` : '';
    })
    .filter(Boolean);

  return (
    <Popover open={open} onOpenChange={setOpened}>
      <PopoverTrigger asChild>
        <button
          disabled={disabled}
          aria-label={`编辑${className}${subjectName}任课`}
          className="flex h-12 w-full items-center justify-center gap-1 overflow-hidden px-2 text-[12px] text-ink hover:bg-selection focus:outline-none focus:ring-2 focus:ring-inset focus:ring-primary disabled:cursor-default disabled:hover:bg-transparent"
        >
          <span className="min-w-0 truncate">
            {assignments.length
              ? assignments.map((item) => `${teachers.find((teacher) => teacher.id === item.teacherId)?.name ?? '未知教师'}(${item.lessonCount}${item.weekMode === 'weekly' ? '' : `·${modeLabels[item.weekMode]}`})`).join(' ')
              : !unassigned.length
                ? '—'
                : ''}
          </span>
          {!!unassigned.length && <span className="shrink-0 whitespace-nowrap text-warning">{unassigned.join(' ')}</span>}
        </button>
      </PopoverTrigger>
      <PopoverContent align="start" side="bottom" collisionPadding={12} className="max-h-[min(560px,calc(100vh-24px))] w-[min(460px,calc(100vw-24px))] overflow-y-auto p-3.5">
        <AssignmentEditorBody
          className={className}
          subjectName={subjectName}
          initialDrafts={initialDrafts}
          teachers={teachers}
          required={required}
          error={error}
          onCancel={() => setOpen(false)}
          onSave={async (drafts) => {
            const ok = await onSave(drafts);
            if (ok) setOpen(false);
            return ok;
          }}
        />
      </PopoverContent>
    </Popover>
  );
};

export const AssignmentEditorDialog: React.FC<{
  open: boolean;
  onOpenChange: (open: boolean) => void;
  className: string;
  subjectName: string;
  initialDrafts: AssignmentDraft[];
  teachers: Teacher[];
  required: Record<WeekMode, number>;
  error?: string;
  onSave: (drafts: AssignmentDraft[]) => Promise<boolean>;
}> = ({ open, onOpenChange, className, subjectName, initialDrafts, teachers, required, error, onSave }) => (
  <Dialog open={open} onOpenChange={onOpenChange}>
    <DialogContent showCloseButton={false} className="w-[min(480px,calc(100vw-24px))] max-w-[480px] p-4">
      <DialogTitle className="sr-only">分配 {className} {subjectName} 任课</DialogTitle>
      <DialogDescription className="sr-only">选择任课教师、周模式与节数。</DialogDescription>
      <AssignmentEditorBody
        className={className}
        subjectName={subjectName}
        initialDrafts={initialDrafts}
        teachers={teachers}
        required={required}
        error={error}
        onCancel={() => onOpenChange(false)}
        onSave={async (drafts) => {
          const ok = await onSave(drafts);
          if (ok) onOpenChange(false);
          return ok;
        }}
      />
    </DialogContent>
  </Dialog>
);
