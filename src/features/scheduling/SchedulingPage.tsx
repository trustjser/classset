import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type DragEvent, type ReactNode } from 'react';
import { ArrowDownToLine, CalendarDays, Check, CheckCircle2, ChevronDown, ChevronRight, ChevronUp, Loader2, Lock, LockOpen, MousePointerClick, Redo2, Search, SlidersHorizontal, Sparkles, Trash2, Undo2, Upload, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Progress } from '@/components/ui/progress';
import { SearchableSelect } from '@/components/ui/searchable-select';
import { SelectField } from '@/components/ui/select-field';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import type { ScheduleItem, ScheduleLock, WeekMode } from '@/domain/models';
import {
  createScheduleContext, detectSchedule, freeSlotFor, groupBy, isLessonLocked, occursInWeek, positionOf, prepareDemand,
  preflightSchedule, previewPlacement, reconcileSchedule, roomFor, slotKey, timesOverlap,
  type ScheduleContext, type ScheduleData, type ScheduleSlot,
} from '@/domain/scheduling';
import { schoolRepository } from '@/repository/schoolRepository';
import type { ScheduleRunReport } from '@/repository/scheduleStorage';
import { useAppStore } from '@/store/useAppStore';
import { useStickyToolbar } from '@/hooks/useStickyToolbar';
import { getSubjectColor } from '@/styles/subjectColors';
import { TimetableGrid, clockLabel, slotName, weekdayName } from './TimetableGrid';
import { ScheduleRulesDialog } from './ScheduleRulesDialog';
import type { SolveRequest, SolveResponse } from './schedule.worker';
import { defaultExportOptions, type ExportOptions } from './scheduleExport';
import './scheduling.css';

type View = 'class' | 'teacher' | 'all' | 'room';
type Modal = 'solve' | 'rules' | 'publish' | 'clear' | 'detect' | 'report' | 'export' | 'reconcile' | null;
type Reconciliation = ReturnType<typeof reconcileSchedule>;
type Edit = { before: ScheduleItem[]; after: ScheduleItem[] };
type StageClassGroup = { id: string; name: string; classes: Array<{ id: string; name: string }> };

const weekLabels: Record<WeekMode, string> = { weekly: '每周', odd: '单周', even: '双周' };
const viewOptions = [['class', '班级课表'], ['teacher', '教师课表'], ['all', '总课表'], ['room', '场室课表']] as const;
const DRAG_SCROLL_EDGE = 80;
const DRAG_SCROLL_MAX_SPEED = 620;

function edgeScrollSpeed(position: number, start: number, end: number) {
  const fromStart = position - start;
  if (fromStart >= 0 && fromStart < DRAG_SCROLL_EDGE) {
    const intensity = (DRAG_SCROLL_EDGE - fromStart) / DRAG_SCROLL_EDGE;
    return -DRAG_SCROLL_MAX_SPEED * intensity * intensity;
  }
  const toEnd = end - position;
  if (toEnd >= 0 && toEnd < DRAG_SCROLL_EDGE) {
    const intensity = (DRAG_SCROLL_EDGE - toEnd) / DRAG_SCROLL_EDGE;
    return DRAG_SCROLL_MAX_SPEED * intensity * intensity;
  }
  return 0;
}

function findDragScrollTarget(start: Element | null, axis: 'x' | 'y', x: number, y: number) {
  let current = start;
  while (current) {
    if (current instanceof HTMLElement && current !== document.body && current !== document.documentElement) {
      const style = window.getComputedStyle(current);
      const overflow = axis === 'x' ? style.overflowX : style.overflowY;
      const maxOffset = axis === 'x' ? current.scrollWidth - current.clientWidth : current.scrollHeight - current.clientHeight;
      if ((overflow === 'auto' || overflow === 'scroll') && maxOffset > 1) {
        const bounds = current.getBoundingClientRect();
        if (x >= bounds.left && x <= bounds.right && y >= bounds.top && y <= bounds.bottom) {
          const speed = edgeScrollSpeed(axis === 'x' ? x : y, axis === 'x' ? bounds.left : bounds.top,
            axis === 'x' ? bounds.right : bounds.bottom);
          const offset = axis === 'x' ? current.scrollLeft : current.scrollTop;
          const canScroll = speed < 0 ? offset > 0 : speed > 0 && offset < maxOffset;
          if (canScroll) return { element: current, speed };
        }
      }
    }
    current = current.parentElement;
  }

  const root = document.scrollingElement;
  if (root instanceof HTMLElement) {
    const maxOffset = axis === 'x' ? root.scrollWidth - root.clientWidth : root.scrollHeight - root.clientHeight;
    const offset = axis === 'x' ? root.scrollLeft : root.scrollTop;
    const speed = edgeScrollSpeed(axis === 'x' ? x : y, 0, axis === 'x' ? window.innerWidth : window.innerHeight);
    const canScroll = speed < 0 ? offset > 0 : speed > 0 && offset < maxOffset;
    if (maxOffset > 1 && canScroll) return { element: root, speed };
  }
  return null;
}

function Segment<T extends string>({ label, value, options, onChange }: {
  label: string; value: T; options: ReadonlyArray<readonly [T, ReactNode]>; onChange: (value: T) => void;
}) {
  return <Tabs value={value} onValueChange={(next) => onChange(next as T)}>
    <TabsList aria-label={label} className="h-8 rounded-control bg-table-header p-0.5">
      {options.map(([id, text]) => <TabsTrigger key={id} value={id} className="h-7 px-2.5 py-0.5 text-[12px]">{text}</TabsTrigger>)}
    </TabsList>
  </Tabs>;
}

function PickList({ label, value, options, onChange, searchable = false }: {
  label: string; value: string; options: Array<{ id: string; name: string }>; onChange: (id: string) => void; searchable?: boolean;
}) {
  const controlClass = 'h-8 w-auto min-w-[8rem] max-w-[15rem]';
  if (searchable) return <SearchableSelect
    ariaLabel={label}
    className={controlClass}
    emptyText={`没有匹配的${label}`}
    options={options.map((row) => ({ value: row.id, label: row.name }))}
    onValueChange={onChange}
    placeholder={options.length ? `选择${label}` : `无可选${label}`}
    searchPlaceholder={`搜索${label}`}
    value={value}
  />;
  return <SelectField
    ariaLabel={label}
    className={controlClass}
    options={options.map((row) => ({ value: row.id, label: row.name }))}
    onValueChange={onChange}
    placeholder={`选择${label}`}
    value={value}
  />;
}

function StageClassTreeSelect({ groups, value, onChange }: {
  groups: StageClassGroup[];
  value: string;
  onChange: (id: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set());
  const selected = groups.flatMap((stage) => stage.classes.map((schoolClass) => ({ stage, schoolClass })))
    .find((row) => row.schoolClass.id === value);
  const normalizedQuery = query.trim().toLocaleLowerCase();
  const filteredGroups = groups.map((stage) => {
    const stageMatches = stage.name.toLocaleLowerCase().includes(normalizedQuery);
    const classes = normalizedQuery && !stageMatches
      ? stage.classes.filter((schoolClass) => schoolClass.name.toLocaleLowerCase().includes(normalizedQuery))
      : stage.classes;
    return { ...stage, classes, stageMatches };
  }).filter((stage) => !normalizedQuery || stage.stageMatches || stage.classes.length > 0);

  return <Popover open={open} onOpenChange={(next) => { setOpen(next); if (!next) setQuery(''); }}>
    <PopoverTrigger asChild>
      <Button type="button" variant="ghost" size="sm"
        aria-label={selected ? `学段与班级：${selected.stage.name}，${selected.schoolClass.name}` : '学段与班级'}
        className="h-8 justify-between gap-2">
        <span className="flex min-w-0 flex-1 items-center gap-1.5 text-left">
          {selected ? <>
            <span className="max-w-[4rem] shrink-0 truncate text-xs font-medium text-ink-secondary">{selected.stage.name}</span>
            <span className="shrink-0 text-ink-secondary">·</span>
            <span className="min-w-0 truncate font-semibold text-ink">{selected.schoolClass.name}</span>
          </> : <span className="truncate">选择班级</span>}
        </span>
        <ChevronDown aria-hidden="true" className="h-4 w-4 shrink-0" />
      </Button>
    </PopoverTrigger>
    <PopoverContent align="start" side="bottom" collisionPadding={12}
      className="w-[min(15rem,calc(100vw-24px))] p-1.5">
      <div role="group" aria-label="学段与班级" className="max-h-[min(22rem,60vh)] overflow-y-auto">
        <div className="sticky top-0 z-10 border-b border-border bg-surface px-1 pb-2 pt-1">
          <div className="relative">
            <Search aria-hidden="true" className="pointer-events-none absolute left-2 top-2 h-4 w-4 text-ink-secondary" />
            <Input autoFocus aria-label="搜索学段或班级" className="h-8 pl-8 text-sm"
              placeholder="搜索学段或班级" value={query} onChange={(event) => setQuery(event.target.value)} />
          </div>
        </div>
        {filteredGroups.map((stage) => {
          const expanded = !!normalizedQuery || !collapsed.has(stage.id);
          return <div key={stage.id}>
            <Button type="button" variant="ghost" size="sm" aria-expanded={expanded}
              className="h-8 w-full justify-start gap-2 px-2 font-semibold"
              onClick={() => setCollapsed((current) => {
                const next = new Set(current);
                if (next.has(stage.id)) next.delete(stage.id);
                else next.add(stage.id);
                return next;
              })}>
              <ChevronRight aria-hidden="true" className={`h-3.5 w-3.5 ${expanded ? 'rotate-90' : ''}`} />
              <span className="truncate">{stage.name}</span>
            </Button>
            {expanded && <div role="group" aria-label={stage.name} className="ml-3 border-l border-border pl-2">
              {stage.classes.length ? stage.classes.map((schoolClass) => {
                const isSelected = schoolClass.id === value;
                return <Button key={schoolClass.id} type="button" variant="ghost" size="sm" aria-pressed={isSelected}
                  className={`h-8 w-full justify-between gap-2 px-2 text-left ${isSelected ? 'border border-brand-accent bg-selection font-semibold text-ink hover:bg-selection' : 'text-ink'}`}
                  style={isSelected ? { color: 'var(--color-ink)' } : undefined}
                  onClick={() => { onChange(schoolClass.id); setOpen(false); }}>
                  <span className="truncate">{schoolClass.name}</span>
                  <Check aria-hidden="true" className={`h-3.5 w-3.5 shrink-0 ${isSelected ? 'text-brand-accent' : 'opacity-0'}`} />
                </Button>;
              }) : <p className="px-2 py-1 text-xs text-ink-secondary">暂无班级</p>}
            </div>}
          </div>;
        })}
        {normalizedQuery && filteredGroups.length === 0 &&
          <p className="px-2 py-3 text-center text-xs text-ink-secondary">没有匹配的学段或班级</p>}
      </div>
    </PopoverContent>
  </Popover>;
}

function ModalFrame({ title, description, children, actions, onClose, wide = false }: {
  title: string; description: string; children?: ReactNode; actions?: ReactNode; onClose: () => void; wide?: boolean;
}) {
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}>
    <DialogContent className={`flex max-h-[86vh] flex-col gap-0 overflow-hidden p-0 ${wide ? 'max-w-[730px]' : ''}`}>
      <DialogHeader className="shrink-0 px-6 pt-6 pb-3.5 pr-12">
        <DialogTitle>{title}</DialogTitle>
        <DialogDescription>{description}</DialogDescription>
      </DialogHeader>
      {children && <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-6 py-4">{children}</div>}
      <DialogFooter className="shrink-0 px-6 py-3.5">{actions ?? <Button onClick={onClose}>完成</Button>}</DialogFooter>
    </DialogContent>
  </Dialog>;
}

export function SchedulingPage({ termId }: { termId: string | null }) {
  return termId ? <TermSchedulingPage key={termId} termId={termId} /> : <p className="schedule-empty">请先选择学期。</p>;
}

function AnimatedScheduleSlot({ version, children }: { version: string; children: ReactNode }) {
  const element = useRef<HTMLDivElement>(null);
  const stableHeight = useRef<number | null>(null);

  useLayoutEffect(() => {
    const current = element.current;
    if (!current) return;
    if (stableHeight.current === null) {
      current.style.height = 'auto';
      stableHeight.current = current.getBoundingClientRect().height;
      return;
    }

    const startHeight = current.style.height && current.style.height !== 'auto'
      ? current.getBoundingClientRect().height
      : stableHeight.current;
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    current.style.transition = 'none';
    current.style.height = 'auto';
    const targetHeight = Math.max(54, current.scrollHeight, current.closest('td')?.clientHeight ?? 0);
    if (reduceMotion || Math.abs(targetHeight - startHeight) < 1) {
      current.style.height = 'auto';
      current.style.transition = '';
      stableHeight.current = current.getBoundingClientRect().height;
      return;
    }

    current.style.height = `${startHeight}px`;
    void current.offsetHeight;
    current.style.transition = '';
    current.style.height = `${targetHeight}px`;

    const finishTransition = (event: Event) => {
      const transition = event as TransitionEvent;
      if (transition.target !== current || transition.propertyName !== 'height') return;
      current.style.height = 'auto';
      stableHeight.current = current.getBoundingClientRect().height;
    };
    current.addEventListener('transitionend', finishTransition);
    return () => current.removeEventListener('transitionend', finishTransition);
  }, [version]);

  return <div ref={element} className="schedule-slot-layers">{children}</div>;
}

function TermSchedulingPage({ termId }: { termId: string }) {
  const toolbarRef = useStickyToolbar<HTMLElement>();
  const dark = useAppStore((state) => state.resolvedDark);
  const schoolName = useAppStore((state) => state.schoolName);
  const [draft, setDraft] = useState<ScheduleData | null>(null);
  const [published, setPublished] = useState<ScheduleData | null>(null);
  const [baseline, setBaseline] = useState<ScheduleData | null>(null);
  const [report, setReport] = useState<ScheduleRunReport | null>(null);
  const [version, setVersion] = useState<'draft' | 'published'>('draft');
  const [view, setView] = useState<View>('class');
  const [showTeacherView, setShowTeacherView] = useState(true);
  const [week, setWeek] = useState<WeekMode>('weekly');
  const [overviewStage, setOverviewStage] = useState('all');
  const [classId, setClassId] = useState('');
  const [teacherId, setTeacherId] = useState('');
  const [roomId, setRoomId] = useState('');
  const [overview, setOverview] = useState<'grid' | 'day'>('grid');
  const [day, setDay] = useState(1);
  const [selected, setSelected] = useState<string | null>(null);
  const [moving, setMoving] = useState<string | null>(null);
  const [hovered, setHovered] = useState<ScheduleSlot | null>(null);
  const [poolExpanded, setPoolExpanded] = useState(false);
  const [poolDragOver, setPoolDragOver] = useState(false);
  const [poolScope, setPoolScope] = useState<'class' | 'all'>('class');
  const [modal, setModal] = useState<Modal>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [feedback, setFeedback] = useState('');
  const [history, setHistory] = useState<{ undo: Edit[]; redo: Edit[] }>({ undo: [], redo: [] });
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [solveClasses, setSolveClasses] = useState<string[]>([]);
  const [solveClassQuery, setSolveClassQuery] = useState('');
  const [keepPlacements, setKeepPlacements] = useState(false);
  const [supplement, setSupplement] = useState(false);
  const [seed, setSeed] = useState('');
  const [strength, setStrength] = useState('normal');
  const [detection, setDetection] = useState<string[]>([]);
  const [reconciliation, setReconciliation] = useState<Reconciliation | null>(null);
  const [exportOptions, setExportOptions] = useState<ExportOptions>(defaultExportOptions);
  const [exportTab, setExportTab] = useState<'content' | 'print' | 'split'>('content');
  const worker = useRef<Worker | null>(null);
  const cancelSolve = useRef<(() => void) | null>(null);
  const running = useRef(false);
  const schedulePageRef = useRef<HTMLDivElement | null>(null);
  const nativeDragActiveRef = useRef(false);
  const lastDragOverAtRef = useRef<number | null>(null);

  const reload = useCallback(async () => {
    const [data, snapshot, latest] = await Promise.all([
      schoolRepository.loadSchedulingData(termId), schoolRepository.loadPublishedSchedule(termId), schoolRepository.loadLatestScheduleReport(termId),
    ]);
    const pending = await schoolRepository.loadPendingScheduleBaseline(data);
    setDraft(data);
    setBaseline(pending);
    setPublished(snapshot);
    setReport(latest);
  }, [termId]);
  useEffect(() => {
    void reload().catch((reason) => setError(String(reason))).finally(() => setLoading(false));
    return () => { cancelSolve.current?.(); worker.current?.terminate(); };
  }, [reload]);
  useEffect(() => {
    if (!feedback) return;
    const timeout = window.setTimeout(() => setFeedback(''), 5000);
    return () => window.clearTimeout(timeout);
  }, [feedback]);
  useEffect(() => {
    const stopAutoScroll = () => {
      nativeDragActiveRef.current = false;
      lastDragOverAtRef.current = null;
    };
    const scrollAtEdge = (event: WindowEventMap['dragover']) => {
      if (!nativeDragActiveRef.current) return;
      const page = schedulePageRef.current;
      const target = event.target instanceof Element ? event.target : null;
      if (!page || !target || !page.contains(target)) return;
      const pageBounds = page.getBoundingClientRect();
      if (event.clientX < pageBounds.left || event.clientX > pageBounds.right ||
        event.clientY < pageBounds.top || event.clientY > pageBounds.bottom) return;

      const elapsed = lastDragOverAtRef.current === null ? 16
        : Math.min(64, Math.max(8, event.timeStamp - lastDragOverAtRef.current));
      lastDragOverAtRef.current = event.timeStamp;
      const tableScroller = target.closest('.schedule-table-scroll');
      const horizontal = findDragScrollTarget(tableScroller, 'x', event.clientX, event.clientY);
      const vertical = findDragScrollTarget(page.parentElement, 'y', event.clientX, event.clientY);
      if (horizontal) horizontal.element.scrollLeft += horizontal.speed * elapsed / 1000;
      if (vertical) vertical.element.scrollTop += vertical.speed * elapsed / 1000;
    };
    window.addEventListener('dragover', scrollAtEdge, true);
    window.addEventListener('dragend', stopAutoScroll, true);
    window.addEventListener('drop', stopAutoScroll, true);
    return () => {
      window.removeEventListener('dragover', scrollAtEdge, true);
      window.removeEventListener('dragend', stopAutoScroll, true);
      window.removeEventListener('drop', stopAutoScroll, true);
    };
  }, []);

  const schedule = version === 'published' ? published : baseline ?? draft;
  const context = useMemo(() => {
    if (!schedule) return null;
    const items = version === 'draft' && !baseline && !schedule.items.length
      ? prepareDemand(schedule, schedule.classes.map((row) => row.id), true) : schedule.items;
    return createScheduleContext({ ...schedule, items });
  }, [schedule, baseline, version]);
  const readOnly = version === 'published' || baseline !== null;
  const displayWeek = schedule?.term.cycleMode === 'alternating' ? week : 'weekly';
  const stages = useMemo(() => [...(schedule?.stages ?? [])].sort((a, b) => a.sortOrder - b.sortOrder), [schedule]);
  const classGroups = useMemo<StageClassGroup[]>(() => {
    if (!context) return [];
    return stages.map((row) => ({
      id: row.id,
      name: row.name,
      classes: [...context.data.classes].filter((item) => context.stageForClass(item.id) === row.id)
        .sort((a, b) => (context.grades.get(a.gradeId)?.sortOrder ?? 0) - (context.grades.get(b.gradeId)?.sortOrder ?? 0) || a.sortOrder - b.sortOrder)
        .map(({ id, name }) => ({ id, name })),
    }));
  }, [context, stages]);
  const activeClassGroup = classGroups.find((group) => group.classes.some((row) => row.id === classId)) ??
    classGroups.find((group) => group.classes.length > 0);
  const stageId = activeClassGroup?.id ?? stages[0]?.id ?? '';
  const classes = classGroups.find((group) => group.id === stageId)?.classes ?? [];
  const displayedClass = classes.find((row) => row.id === classId) ?? classes[0];
  const displayedTeacher = schedule?.teachers.find((row) => row.id === teacherId) ?? schedule?.teachers[0];
  const displayedRoom = schedule?.rooms.find((row) => row.id === roomId) ?? schedule?.rooms[0];
  const selectedItem = context?.data.items.find((row) => row.id === selected);
  const movingItem = context?.data.items.find((row) => row.id === moving);
  const linkedTeacherId = selectedItem?.teacherId ?? movingItem?.teacherId;
  const split = view === 'class' && showTeacherView;
  const canDropToPool = !readOnly && !busy && movingItem?.weekday != null;
  const targetClass = movingItem?.classId ?? displayedClass?.id;
  const mainStage = context?.stageForClass(targetClass ?? '') ?? stageId;
  const visibleItems = useMemo(() => context?.data.items.filter((row) => occursInWeek(row.weekMode, displayWeek)) ?? [], [context, displayWeek]);
  const solveIssues = useMemo(() => draft && modal === 'solve' ? preflightSchedule(draft, solveClasses) : [], [draft, modal, solveClasses]);
  const canMoveLessons = !readOnly && (view === 'class' || view === 'teacher');
  const teacherTargetId = view === 'teacher' ? displayedTeacher?.id : linkedTeacherId;
  const teacherLessonsBySlot = useMemo(() => {
    if (!teacherTargetId) return new Map<string, ScheduleItem[]>();
    return groupBy(visibleItems.filter((row) => row.teacherId === teacherTargetId && row.weekday !== null),
      (row) => slotKey(row as Parameters<typeof slotKey>[0]));
  }, [teacherTargetId, visibleItems]);
  const teacherSwapTarget = useCallback((slot: ScheduleSlot) => {
    const lessons = teacherLessonsBySlot.get(slotKey(slot));
    return lessons?.length === 1 ? lessons[0] : undefined;
  }, [teacherLessonsBySlot]);
  const targets = useMemo(() => {
    if (!context || !movingItem || busy || !canMoveLessons) return undefined;
    const sourceSlot = positionOf(context, movingItem);
    const slots = view === 'teacher' ? [...context.slots.values()] : context.slotsByStage.get(mainStage) ?? [];
    return new Map(slots.filter((slot) => !sourceSlot || slot.stageId !== sourceSlot.stageId || slotKey(slot) !== slotKey(sourceSlot)).map((slot) =>      [slotKey(slot), previewPlacement(context, movingItem, slot, true, false, teacherSwapTarget(slot))]));
  }, [context, movingItem, busy, canMoveLessons, view, mainStage, teacherSwapTarget]);
  const hoverPreview = hovered && targets?.get(slotKey(hovered));
  const linkedCorrections = hoverPreview && hoverPreview.status === 'swap' && hoverPreview.changed ? new Map(hoverPreview.changed.map((row) => [row.id, row])) : null;
  const resetSelection = () => { setSelected(null); setMoving(null); setHovered(null); };
  const finishMove = () => { setMoving(null); setHovered(null); };
  const closeModal = () => { if (!running.current) setModal(null); };

  const perform = async (action: () => Promise<void>) => {
    if (running.current) return false;
    running.current = true;
    setBusy(true);
    setError('');
    try {
      await action();
      return true;
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : String(reason));
      if (String(reason).includes('已变更')) {
        await reload().catch(() => {});
        setHistory({ undo: [], redo: [] });
        resetSelection();
      }
      return false;
    } finally {
      running.current = false;
      setBusy(false);
    }
  };

  const refreshSummary = () => {
    const store = useAppStore.getState();
    if (store.activeTermId === termId) void schoolRepository.loadWorkbenchSummary(termId).then((summary) => {
      if (useAppStore.getState().activeTermId === termId) useAppStore.setState({ summary, lastPersistedAt: new Date() });
    }).catch(() => {});
  };

  const saveItems = async (items: ScheduleItem[], message: string, record = true) => {
    if (!draft || readOnly) return false;
    const before = draft.items;
    return perform(async () => {
      await schoolRepository.saveScheduleDraft(draft, items);
      setDraft({ ...draft, items });
      if (record) setHistory((previous) => ({ undo: [...previous.undo.slice(-29), { before, after: items }], redo: [] }));
      setFeedback(message);
      refreshSummary();
    });
  };

  const selectLesson = (item: ScheduleItem) => {
    if (selected === item.id) {
      resetSelection();
      setFeedback('');
      return;
    }
    setSelected(item.id);
    setHovered(null);
    setFeedback('');
    setMoving(canMoveLessons && !busy && context && !isLessonLocked(context, item) && item.id !== moving ? item.id : null);
  };

  const beginDrag = (event: DragEvent, item: ScheduleItem) => {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', item.id);
    nativeDragActiveRef.current = true;
    lastDragOverAtRef.current = null;
    setSelected(item.id);
    setMoving(item.id);
    setFeedback('');
  };

  const place = async (slot: ScheduleSlot | null, itemId = moving) => {
    if (!context || !itemId || readOnly || busy) return;
    const item = context.data.items.find((row) => row.id === itemId);
    if (!item) return;
    const preview = previewPlacement(context, item, slot, true, true, slot ? teacherSwapTarget(slot) : undefined);
    if (!preview.items) {
      if (slot) setHovered(slot);
      else setFeedback(preview.reason);
      return;
    }
    if (await saveItems(preview.items, slot ? (preview.status === 'swap' ? '已互换课节' : `已放入 ${slotName(slot)}`) : '已移入暂放区')) {
      finishMove();
      setSelected(item.id);
    }
  };

  const undoRedo = async (kind: 'undo' | 'redo') => {
    const edit = history[kind].at(-1);
    if (!edit) return;
    if (await saveItems(kind === 'undo' ? edit.before : edit.after, kind === 'undo' ? '已撤销调整' : '已重做调整', false)) {
      const other = kind === 'undo' ? 'redo' : 'undo';
      setHistory((current) => ({ ...current, [kind]: current[kind].slice(0, -1), [other]: [...current[other], edit] }));
      resetSelection();
    }
  };

  function openSolve(keep = false) {
    if (!draft || readOnly) return;
    const classIds = view === 'teacher' && displayedTeacher
      ? [...new Set(visibleItems.filter((row) => row.teacherId === displayedTeacher.id && row.weekday === null).map((row) => row.classId))]
      : poolScope === 'all' ? draft.classes.map((row) => row.id) : displayedClass ? [displayedClass.id] : [];
    setSolveClasses(keep && classIds.length ? classIds : draft.classes.map((row) => row.id));
    setSolveClassQuery('');
    setKeepPlacements(keep);
    setSupplement(keep);
    setSeed('');
    setStrength(draft.preferences.strength);
    setModal('solve');
  }

  function runSolver() {
    if (!draft || !solveClasses.length || readOnly) return;
    const runSeed = seed ? Number(seed) : Date.now() % 0x7fffffff;
    const request: SolveRequest = { data: { ...draft, preferences: { ...draft.preferences, strength } },
      classIds: solveClasses, keepPlacements, allowRearrangement: supplement && keepPlacements, seed: runSeed };
    const before = draft.items;
    setModal(null);
    finishMove();
    void perform(async () => {
      const instance = new Worker(new URL('./schedule.worker.ts', import.meta.url), { type: 'module' });
      worker.current = instance;
      setProgress({ done: 0, total: 0 });
      try {
        const result = await new Promise<Extract<SolveResponse, { type: 'complete' }>['result'] | null>((resolve, reject) => {
          instance.onmessage = ({ data }: MessageEvent<SolveResponse>) => {
            if (data.type === 'progress') setProgress(data);
            else if (data.type === 'complete') resolve(data.result);
            else reject(new Error(data.message));
          };
          instance.onerror = (event) => reject(new Error(event.message || '排课计算失败'));
          cancelSolve.current = () => { instance.terminate(); resolve(null); };
          instance.postMessage(request);
        });
        cancelSolve.current = null;
        if (!result) { setFeedback('已取消排课'); return; }
        setProgress(null);
        const latest: ScheduleRunReport = { classIds: solveClasses, seed: runSeed, strength,
          candidateChecks: result.candidateChecks, blockers: result.blockers, issues: result.issues };
        await schoolRepository.saveScheduleDraft(draft, result.items, { report: latest });
        setDraft({ ...draft, items: result.items });
        setReport(latest);
        setHistory((previous) => ({ undo: [...previous.undo.slice(-29), { before, after: result.items }], redo: [] }));
        setFeedback(`已排 ${result.items.filter((row) => row.weekday !== null).length} 节，暂放 ${result.items.filter((row) => row.weekday === null).length} 节`);
        refreshSummary();
      } finally {
        instance.terminate();
        worker.current = null;
        cancelSolve.current = null;
        setProgress(null);
      }
    });
  }
  function changeLock() {
    if (!context || !draft || readOnly) return;
    const scope = view === 'teacher' ? 'teacher' : 'class';
    const ids = view === 'all' ? draft.classes.filter((row) => overviewStage === 'all' || context.stageForClass(row.id) === overviewStage)
      .map((row) => row.id) :
      [view === 'teacher' ? displayedTeacher?.id : displayedClass?.id].filter((id): id is string => !!id);
    const targetsWithSchedule = ids.filter((id) => draft.items.some((row) => row.weekday !== null && (scope === 'teacher' ? row.teacherId : row.classId) === id));
    if (!targetsWithSchedule.length) return;
    const hasLocks = targetsWithSchedule.every((id) => context.locks.has(`${scope}:${id}`));
    const locks = draft.locks.filter((row) => row.scope !== scope || !targetsWithSchedule.includes(row.targetId));
    if (!hasLocks) locks.push(...targetsWithSchedule.map((id): ScheduleLock => ({ id: `${termId}:${scope}:${id}`, termId, scope, targetId: id })));
    void perform(async () => {
      await schoolRepository.saveScheduleDraft(draft, draft.items, { locks });
      setDraft({ ...draft, locks });
      setHistory({ undo: [], redo: [] });
      finishMove();
      setFeedback(hasLocks ? '已解除锁定' : '已锁定课表');
    });
  }

  if (loading) return <p className="schedule-empty" role="status">正在读取课表…</p>;
  if (!draft) return <div className="schedule-panel schedule-empty"><p role="alert">{error || '无法读取课表'}</p>
    <Button size="sm" variant="outline" className="mt-2" onClick={() => void perform(reload)}>重试</Button></div>;

  const lockedIds = new Set(draft.items.filter((row) => row.weekday !== null && (view === 'all' ?
    overviewStage === 'all' || context?.stageForClass(row.classId) === overviewStage :
    view === 'teacher' ? row.teacherId === displayedTeacher?.id : row.classId === displayedClass?.id))
    .map((row) => view === 'teacher' ? `teacher:${row.teacherId}` : `class:${row.classId}`));
  const canLock = lockedIds.size > 0;
  const locked = canLock && [...lockedIds].every((id) => context?.locks.has(id));
  const overviewStages = stages.filter((row) => overviewStage === 'all' || row.id === overviewStage);
  const pool = visibleItems.filter((row) => row.weekday === null && (view === 'teacher'
    ? row.teacherId === displayedTeacher?.id : poolScope === 'all' || row.classId === displayedClass?.id));
  const hasUnplacedInSchool = visibleItems.some((row) => row.weekday === null);
  const assignedCount = context?.data.items.filter((row) => row.weekday !== null).length ?? 0;
  const baselineContext = baseline && modal === 'reconcile' ? createScheduleContext(baseline) : null;

  function itemLabel(item: ScheduleItem, source = context) {
    return `${source?.classes.get(item.classId)?.name ?? ''} · ${source?.subjects.get(item.subjectId) ?? '课程'}`;
  }

  const renderLesson = (item: ScheduleItem, detail: 'class' | 'teacher' | 'both', interactive = false, preview = false) => {
    if (!context) return null;
    const color = getSubjectColor(item.subjectId, dark);
    const teacher = context.teachers.get(item.teacherId ?? '') ?? '未分配教师';
    const schoolClass = context.classes.get(item.classId)?.name;
    const subject = context.subjects.get(item.subjectId) ?? '课程';
    const blocked = isLessonLocked(context, item);
    const lockedOnTimetable = blocked && item.weekday !== null;
    const subtitle = [detail !== 'class' && schoolClass, detail !== 'teacher' && teacher,
      item.weekMode !== 'weekly' && weekLabels[item.weekMode], item.combinedGroupId && '合班'].filter(Boolean).join(' · ');
    const title = `${subject} · ${subtitle}${lockedOnTimetable ? ' · 已锁定' : ''}${preview ? ' · 预览' : ''}`;
    const props = { className: 'schedule-lesson', title, style: { '--lesson-bg': color.background, '--lesson-ink': color.foreground, '--lesson-border': `${color.foreground}30` } as CSSProperties };
    const contents = <><strong>{subject}</strong>
      <small className={lockedOnTimetable ? 'schedule-lesson-locked-details' : undefined}>{subtitle}{preview ? ' · 预览' : ''}</small>
      {lockedOnTimetable && <Lock aria-hidden="true" className="schedule-lesson-lock" />}
    </>;
    return interactive ? <button key={item.id} type="button" {...props} aria-label={title} aria-pressed={item.id === selected}
      draggable={!busy && !readOnly && !blocked}
      onClick={() => selectLesson(item)} onDragStart={(event) => beginDrag(event, item)}
      onDragEnd={() => { nativeDragActiveRef.current = false; lastDragOverAtRef.current = null; setHovered(null); }}>{contents}</button>
      : <div key={item.id} {...props}>{contents}</div>;
  };

  function grid(stageKey: string, title: string, items: ScheduleItem[], options: {
    mode: 'class' | 'teacher' | 'room' | 'all';
    id?: string;
    active?: boolean;
    dropOnly?: boolean;
    ghost?: boolean;
  }) {
    if (!context) return null;
    const routine = context.data.routines.find((row) => row.stageId === stageKey);
    const anchors = new Map(routine?.lessonTimes.map((row) => [row.id, `${row.periodTypeId}:${row.lessonIndex}`]));
    const slots = context.slotsByStage.get(stageKey) ?? [];
    const atStage = items.filter((row) => row.stageId === stageKey && row.weekday !== null);
    const bySlot = groupBy(atStage, (row) => slotKey(row as Parameters<typeof slotKey>[0]));
    const previewBySlot = linkedCorrections && (options.active || options.ghost)
      ? groupBy(items.flatMap((item) => {
        const next = linkedCorrections.get(item.id);
        return next?.stageId === stageKey && next.weekday !== null ? [next] : [];
      }), (row) => slotKey(row as Parameters<typeof slotKey>[0])) : null;
    const duties = groupBy(context.data.visibleSupervision.filter((row) => row.position.stageId === stageKey && (
      options.mode === 'class' ? row.post.classIds.includes(options.id ?? '') :
      options.mode === 'teacher' ? row.teacherId === options.id : options.mode === 'all'
    )), (row) => slotKey(row.position));
    const periodIds = routine && [...routine.periodTypes].sort((a, b) => a.sortOrder - b.sortOrder).map((row) => row.id);
    return <TimetableGrid key={stageKey} title={title} slots={slots} commonPeriods={routine?.commonPeriods} anchors={anchors} periodIds={periodIds}
      preview={options.active ? targets : undefined}
      previewSlot={options.active ? hovered : null}
      selectedSlot={options.active && selectedItem ? positionOf(context, selectedItem) : undefined}
      dragSourceSlot={options.active && movingItem && movingItem.weekday !== null ? positionOf(context, movingItem) : undefined}
      onActivate={options.active ? (slot) => void place(slot) : undefined}
      onHover={options.active && moving ? setHovered : undefined}
      onDrop={options.active ? (slot, event) => { event.preventDefault(); void place(slot, event.dataTransfer.getData('text/plain') || moving); } : undefined}
      highlight={options.ghost ? (slot) => !!hovered && timesOverlap(slot, hovered) : undefined}
      render={(slot) => {
        const key = slotKey(slot);
        const lessons = bySlot.get(key) ?? [];
        const cellDuties = duties.get(key) ?? [];
        const free = options.mode === 'class' && options.id ? freeSlotFor(context, options.id, slot) : undefined;
        const incoming = previewBySlot?.get(key) ?? [];
        const hasPreview = previewBySlot !== null && (incoming.length > 0 || lessons.some((item) => linkedCorrections?.has(item.id)));
        const detail = options.mode === 'class' ? 'class' : options.mode === 'teacher' ? 'teacher' : 'both';
        if (!lessons.length && !cellDuties.length && !free && !hasPreview) return null;
        const slotContent = (rows: ScheduleItem[], affected = false) => <>
          {free && <div className="schedule-lesson schedule-free-slot">{free.label || '免任课'}</div>}
          {rows.map((item) => renderLesson(item, detail, !affected && !!options.active && !options.dropOnly && !busy,
            affected && !!linkedCorrections?.has(item.id)))}
          {cellDuties.map((row) => <div key={row.post.id} className="schedule-lesson">
            <strong>{row.post.name}</strong><small>{options.mode === 'teacher' ? row.classNames.join('、') : row.teacherName} · 带班</small>
          </div>)}
          {!rows.length && !cellDuties.length && !free && <span className="schedule-empty-slot" aria-hidden="true" />}
        </>;
        const previewLessons = [...lessons.filter((item) => !linkedCorrections?.has(item.id)), ...incoming];
        const contentVersion = [
          hasPreview,
          [...lessons, ...previewLessons].map((item) => `${item.id}:${item.subjectId}:${item.teacherId}:${item.classId}:${item.weekMode}`).join(','),
          cellDuties.map((row) => `${row.post.id}:${row.post.name}:${row.teacherName}:${row.classNames.join(',')}`).join(','),
          free?.label ?? '',
        ].join('|');
        return <AnimatedScheduleSlot version={contentVersion}>
          <div className="schedule-slot-original" data-hidden={hasPreview || undefined} aria-hidden={hasPreview || undefined}>
            {slotContent(lessons)}
          </div>
          {hasPreview && <div className="schedule-cell-preview" aria-hidden="true">{slotContent(previewLessons, true)}</div>}
        </AnimatedScheduleSlot>;
      }} />;
  }

  function renderTeacher(id: string, linked = false) {
    if (!context) return null;
    const teacherItems = visibleItems.filter((row) => row.teacherId === id);
    const teacherStages = new Set([
      ...teacherItems.map((row) => row.stageId),
      ...context.data.assignments.filter((row) => row.teacherId === id).map((row) => context.stageForClass(row.classId)),
      ...context.data.visibleSupervision.filter((row) => row.teacherId === id).map((row) => row.position.stageId),
    ]);
    const relevant = stages.filter((row) => teacherStages.has(row.id));
    if (!relevant.length) return <p className="schedule-empty">当前教师没有任课或带班安排。</p>;
    const currentStage = linked ? mainStage : stageId;
    const current = relevant.find((row) => row.id === currentStage);
    const ordered = current ? [current, ...relevant.filter((row) => row.id !== current.id)] : relevant;
    return ordered.map((row) => <div key={row.id}>
      {ordered.length > 1 && <p className="schedule-feedback">{row.name}</p>}
      {grid(row.id, `${context.teachers.get(id)} · ${row.name}`, teacherItems, {
        mode: 'teacher', id, ghost: linked, active: !linked || !!movingItem && canMoveLessons && row.id === mainStage, dropOnly: linked,
      })}
    </div>);
  }

  const renderPool = () => <section className="schedule-panel schedule-pool-panel schedule-pool-dock" data-expanded={poolExpanded}
    data-drop-active={poolDragOver && canDropToPool}
    onDragOver={(event) => {
      if (canDropToPool) { event.preventDefault(); event.dataTransfer.dropEffect = 'move'; setPoolDragOver(true); }
    }}
    onDragLeave={(event) => {
      if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setPoolDragOver(false);
    }}
    onDrop={(event) => {
      if (canDropToPool) { event.preventDefault(); setPoolDragOver(false); void place(null, event.dataTransfer.getData('text/plain') || moving); }
    }}>
    <div className="schedule-panel-heading schedule-pool-heading">
      <h3>暂放区</h3>
      <div className="schedule-pool-heading-meta">
        <span className="schedule-pool-count" role="status" aria-atomic="true" aria-label={`暂放区有 ${pool.length} 节课程`}>{pool.length} 节</span>
        {poolDragOver && canDropToPool && <span className="schedule-pool-ready" role="status"><CheckCircle2 aria-hidden="true" />可放入</span>}
        {canDropToPool && <button type="button" className="schedule-pool-place-action" aria-label="将当前选中课程暂存"
          onClick={() => { setPoolDragOver(false); void place(null); }}>
          <ArrowDownToLine aria-hidden="true" />将当前课程放入暂存
        </button>}
        {poolExpanded && ((view === 'class' && hasUnplacedInSchool) || pool.length > 0) && <div className="schedule-toolbar-group">
          {view === 'class' && <Segment label="暂放范围" value={poolScope} options={[['class', '本班'], ['all', '全部']]} onChange={setPoolScope} />}
          {pool.length > 0 && !readOnly && <Button variant="ghost" size="sm" disabled={busy} onClick={() => openSolve(true)}>补排</Button>}
          {pool.length > 0 && <Button variant="ghost" size="sm" disabled={!report} onClick={() => setModal('report')}>未排报告</Button>}
        </div>}
        <Button type="button" variant="ghost" size="icon" className="h-8 w-8 shrink-0" aria-label={poolExpanded ? '收起暂放区' : '展开暂放区'}
          aria-expanded={poolExpanded} aria-controls="schedule-pool-content" onClick={() => setPoolExpanded((expanded) => !expanded)}>
          {poolExpanded ? <ChevronDown aria-hidden="true" /> : <ChevronUp aria-hidden="true" />}
        </Button>
      </div>
    </div>
    <div id="schedule-pool-content" hidden={!poolExpanded}>
      {pool.length ? <div className="schedule-pool">{pool.map((item) => <div key={item.id} className="min-w-0"
        title={report?.blockers[item.id]?.join('；')}>{renderLesson(item, 'both', !busy && !readOnly)}</div>)}</div>
        : <div role="group" aria-label="拖拽课程卡片到此处暂存" className="schedule-pool-dropzone">
          <Upload aria-hidden="true" className="h-6 w-6" />
          <span>{canDropToPool ? '拖拽课程卡片到此处，或点击“暂存当前课程”' : '拖拽课程卡片到此处暂存'}</span>
        </div>}
    </div>
  </section>;

  return <div ref={schedulePageRef} className="schedule-page" onKeyDown={(event) => {
    const target = event.target;
    const insideOverlay = target instanceof HTMLElement && target.closest('[role="dialog"], [role="listbox"], [role="menu"], input, textarea');
    if (event.key === 'Escape' && !insideOverlay && (selected || moving)) resetSelection();
  }}>
    <section
      ref={toolbarRef}
      className="schedule-panel schedule-sticky-toolbar sticky-glass-toolbar shadow-sm"
      aria-label="课表工具栏"
    >
      <div className="schedule-toolbar">
        <Segment label="课表版本" value={version} options={[['draft', '草稿版'], ['published', '正式版']]}
          onChange={(value) => { if (!busy) { setVersion(value); resetSelection(); setFeedback(''); } }} />
        {schedule && <Segment label="课表类型" value={view} options={viewOptions}
          onChange={(value) => { setView(value); resetSelection(); }} />}
        {schedule?.term.cycleMode === 'alternating' && <Segment label="周别" value={week}
          options={[['weekly', '合并'], ['odd', '单周'], ['even', '双周']]} onChange={(value) => { setWeek(value); resetSelection(); }} />}
        <div className="schedule-toolbar-group ml-auto">
          {version === 'draft' && <>
            <Button variant="ghost" size="sm" disabled={busy || readOnly || !assignedCount} onClick={() => setModal('publish')}>发布为正式版</Button>
            <Button size="sm" disabled={busy || readOnly || !draft.assignments.length} onClick={() => openSolve()}><Sparkles />自动排课</Button>
          </>}
        </div>
      </div>
      {schedule && <div className="schedule-toolbar border-t border-dashed">
        <div className="schedule-toolbar-group">
          {view === 'class' && <StageClassTreeSelect groups={classGroups} value={displayedClass?.id ?? ''}
            onChange={(id) => { setClassId(id); resetSelection(); }} />}
          {view === 'all' && <PickList label="总课表学段" value={overviewStage} options={[{ id: 'all', name: '全校' }, ...stages]} onChange={setOverviewStage} />}
          {view === 'teacher' && <PickList label="教师" value={displayedTeacher?.id ?? ''} options={schedule.teachers} searchable onChange={(id) => { setTeacherId(id); resetSelection(); }} />}
          {view === 'room' && <PickList label="场室" value={displayedRoom?.id ?? ''} options={schedule.rooms} searchable onChange={setRoomId} />}
          {view === 'all' && <Segment label="总课表布局" value={overview} options={[['grid', '周课表'], ['day', '按日对照']]} onChange={setOverview} />}
          {view === 'all' && overview === 'day' && <PickList label="星期" value={String(day)} options={[1, 2, 3, 4, 5, 6, 7].map((id) =>
            ({ id: String(id), name: weekdayName(id) }))} onChange={(value) => setDay(Number(value))} />}
        </div>
        {view === 'class' && <label className="inline-flex h-8 cursor-pointer select-none items-center gap-2 rounded-control px-1.5 text-[12px] font-medium text-ink-secondary hover:text-ink">
          <Checkbox checked={showTeacherView} onCheckedChange={(checked) => setShowTeacherView(checked === true)} />
          <span>联动教师视图</span>
        </label>}
        <div className="schedule-toolbar-group">
          {!readOnly && <>
            <Button variant="ghost" size="sm" disabled={busy || !history.undo.length} onClick={() => void undoRedo('undo')}><Undo2 />撤销</Button>
            <Button variant="ghost" size="sm" disabled={busy || !history.redo.length} onClick={() => void undoRedo('redo')}><Redo2 />重做</Button>
            {view !== 'room' && <Button variant="ghost" size="sm" disabled={busy || !canLock} onClick={changeLock}
              aria-pressed={locked} className={locked ? 'text-warning hover:text-warning' : undefined}>
              {locked ? <Lock /> : <LockOpen />}{locked ? '已锁定' : '锁定'}
            </Button>}
            <Button type="button" variant="ghost" size="sm"
              className="h-8 gap-1.5 px-2 text-destructive transition-colors hover:bg-destructive/10 hover:text-destructive active:bg-destructive/15"
              aria-label="清空课表草稿" title="清空课表草稿" disabled={busy || !assignedCount}
              onClick={() => { setError(''); setModal('clear'); }}>
              <Trash2 aria-hidden="true" className="h-4 w-4" />清空
            </Button>
          </>}
          {version === 'draft' && <Button variant="ghost" size="sm" disabled={busy} onClick={() => setModal('rules')}><SlidersHorizontal />规则</Button>}
          <Button variant="ghost" size="sm" disabled={busy || !!baseline && version === 'draft'} onClick={() => {
            setDetection(detectSchedule(context!.data)); setModal('detect');
          }}><CheckCircle2 />检测</Button>
          <Button variant="ghost" size="sm" disabled={busy || (!!baseline && version === 'draft') || (!assignedCount && !schedule.visibleSupervision.length)}
            onClick={() => { setExportTab('content'); setModal('export'); }}><ArrowDownToLine />导出</Button>
        </div>
      </div>}
    </section>

    {baseline && version === 'draft' && <div className="schedule-alert flex flex-wrap items-center justify-between gap-2" role="status">
      <span>排课资料已变更。当前显示变更前的课表，确认协调后可继续编辑。</span>
      <Button size="sm" variant="outline" disabled={busy} onClick={() => { setReconciliation(null); setModal('reconcile'); }}>查看协调</Button>
    </div>}
    {error && <div role="alert" className="schedule-error flex items-center justify-between gap-2">
      <span>{error}</span><Button variant="ghost" size="sm" disabled={busy} onClick={() => void perform(reload)}>刷新</Button>
    </div>}
    {progress && <section className="flex items-center gap-3.5 rounded-[16px] border border-brand-accent/25 bg-surface px-4 py-3 shadow-sm" role="status" aria-live="polite">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-selection text-brand-accent" aria-hidden="true">
        <Loader2 className="h-4 w-4 animate-spin" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="mb-1.5 flex items-center justify-between gap-2">
          <div className="flex min-w-0 items-baseline gap-2">
            <span className="text-[13.5px] font-semibold text-ink">正在自动排课</span>
            {solveClasses.length > 0 && <span className="truncate text-xs text-ink-secondary">共 {solveClasses.length} 个班级</span>}
          </div>
          <span className="shrink-0 text-[13px] font-semibold tabular-nums text-brand-accent">
            {progress.total ? `${Math.round(progress.done / progress.total * 100)}%` : '准备中…'}
          </span>
        </div>
        <Progress aria-label="排课进度" className="h-2 w-full" value={progress.total ? progress.done / progress.total * 100 : null} />
      </div>
      <Button variant="outline" size="sm" className="h-8 shrink-0 text-xs text-ink-secondary hover:border-destructive/40 hover:bg-destructive/5 hover:text-destructive" onClick={() => cancelSolve.current?.()}>取消排课</Button>
    </section>}
    {feedback && <div className="flex items-center justify-between gap-3 rounded-control border border-border bg-surface px-3 py-2 text-sm text-ink-secondary" role="status">
      <span>{feedback}</span>
      <Button type="button" variant="ghost" size="icon" className="h-7 w-7 shrink-0" aria-label="关闭提示" onClick={() => setFeedback('')}>
        <X aria-hidden="true" />
      </Button>
    </div>}

    {!context ? <section className="schedule-panel schedule-empty">
      <p className="font-semibold text-ink">尚未发布正式课表</p>
      <Button variant="ghost" onClick={() => setVersion('draft')}>前往草稿排课</Button>
    </section> : view === 'class' ? <div className="schedule-split" data-layout={split ? 'side' : 'single'}>
      <div className="schedule-secondary">
        <section className="schedule-panel schedule-timetable-panel">
          <div className="schedule-timetable-heading">
            <h2>课表安排</h2>
            <span className="schedule-timetable-label">
              班级课程表 · {displayWeek === 'weekly' && schedule?.term.cycleMode === 'alternating' ? '单双周合并' : weekLabels[displayWeek]}
            </span>
            <span className="schedule-timetable-count">{visibleItems.filter((row) => row.classId === targetClass && row.weekday !== null).length} 节课</span>
            {selectedItem && <Button variant="ghost" size="sm" onClick={resetSelection}>取消选中</Button>}
            {movingItem && <Button variant="ghost" size="sm" onClick={finishMove}>取消移动</Button>}
          </div>
          {grid(mainStage, '班级课表', visibleItems.filter((row) => row.classId === targetClass),
            { mode: 'class', id: targetClass, active: true })}
        </section>
      </div>
      {split && <div className="schedule-secondary">
        <section className="schedule-panel schedule-timetable-panel schedule-teacher-panel">
          <div className="schedule-timetable-heading"><h2>任课教师课表</h2><span className="text-sm text-ink-secondary">
            {linkedTeacherId ? context.teachers.get(linkedTeacherId) : selectedItem ? '未分配教师' : ''}
          </span></div>
          {linkedTeacherId ? renderTeacher(linkedTeacherId, true) : <div className="schedule-teacher-empty" role="status">
            <div className="schedule-teacher-empty-art" aria-hidden="true">
              <CalendarDays />
              <span><MousePointerClick /></span>
            </div>
            <strong>{selectedItem ? '这节课还没有安排任课教师' : '先选一节班级课程'}</strong>
            <p>{selectedItem ? '为课程安排教师后，这里就会显示对应课表。' : '点击左侧任一课程卡片，即可查看对应任课教师课表。'}</p>
          </div>}
        </section>
      </div>}
    </div> : view === 'teacher' ? <div className="schedule-secondary">
      <section className="schedule-panel schedule-timetable-panel">
        <div className="schedule-timetable-heading">
          <h2>{displayedTeacher?.name ?? '教师课表'}</h2>
          {selectedItem && <Button variant="ghost" size="sm" onClick={resetSelection}>取消选中</Button>}
          {movingItem && <Button variant="ghost" size="sm" onClick={finishMove}>取消移动</Button>}
        </div>
        {displayedTeacher ? renderTeacher(displayedTeacher.id) : <p className="schedule-empty">暂无教师。</p>}
      </section>
    </div> : view === 'room' ? <section className="schedule-panel schedule-timetable-panel">
      <div className="schedule-timetable-heading"><h2>{displayedRoom?.name ?? '场室课表'}</h2></div>
      {displayedRoom ? stages.map((row) => <div key={row.id}><p className="schedule-feedback">{row.name}</p>{grid(row.id, row.name,
        visibleItems.filter((item) => roomFor(context, item) === displayedRoom.id), { mode: 'room' })}</div>)
        : <p className="schedule-empty">暂无公共场室。</p>}
    </section> : <div className="schedule-secondary">
      {overviewStages.map((schoolStage) => {
        const stageClasses = context.data.classes.filter((row) => context.stageForClass(row.id) === schoolStage.id)
          .sort((a, b) => (context.grades.get(a.gradeId)?.sortOrder ?? 0) - (context.grades.get(b.gradeId)?.sortOrder ?? 0) || a.sortOrder - b.sortOrder);
        const daySlots = (context.slotsByStage.get(schoolStage.id) ?? []).filter((slot) => slot.weekday === day);
        return <section className="schedule-panel schedule-timetable-panel" key={schoolStage.id}>
          <div className="schedule-timetable-heading"><h2>{schoolStage.name}{overview === 'day' ? ` · ${weekdayName(day)}` : ''}</h2></div>
          {overview === 'grid' ? grid(schoolStage.id, `${schoolStage.name}总课表`, visibleItems, { mode: 'all' }) : daySlots.length ?
            <div className="schedule-table-scroll">
              <table className="schedule-grid schedule-grid-cards" aria-label={`${schoolStage.name}按日对照`} style={{ minWidth: Math.max(420, daySlots.length * 76 + 84) }}>
                <thead><tr><th scope="col">班级</th>{daySlots.map((slot) => <th key={slotKey(slot)} scope="col" title={clockLabel(slot.startMinute, slot.endMinute)}>{slot.periodName} {slot.label}</th>)}</tr></thead>
                <tbody>{stageClasses.map((row) => <tr key={row.id}>
                  <th scope="row">{row.name}</th>{daySlots.map((slot) => <td key={slotKey(slot)}>
                    {(context.itemsByClass.get(row.id) ?? []).filter((item) => occursInWeek(item.weekMode, displayWeek) &&
                      positionOf(context, item) === slot).map((item) => renderLesson(item, 'class'))}
                    {context.data.visibleSupervision.filter((item) => item.post.classIds.includes(row.id) && slotKey(item.position) === slotKey(slot)).map((item) =>
                      <div className="schedule-lesson" key={item.post.id}>{item.post.name}<small>{item.teacherName}</small></div>)}
                  </td>)}
                </tr>)}</tbody>
              </table>
            </div> : <p className="schedule-empty">当天没有已配置的上课节次。</p>}
        </section>;
      })}
    </div>}

    {context && version === 'draft' && (view === 'class' || view === 'teacher' && !!displayedTeacher) && renderPool()}


    {modal === 'rules' && <ScheduleRulesDialog data={draft} onClose={closeModal} onSave={async (rules, preferences, locks) => {
      await schoolRepository.saveScheduleConfiguration(draft, rules, preferences, locks);
      await reload();
      setReconciliation(null);
      setHistory({ undo: [], redo: [] });
      resetSelection();
      setModal(null);
      setFeedback('已保存排课偏好与规则');
    }} />}
    {modal === 'publish' && <ModalFrame title="发布为正式版" description="发布后，正式版将使用当前草稿中已安排的课节。"
      onClose={closeModal} actions={<><Button variant="ghost" disabled={busy} onClick={closeModal}>取消</Button>
        <Button disabled={busy} onClick={() => void perform(async () => {
          setPublished(await schoolRepository.publishSchedule(draft)); setModal(null); setFeedback('正式课表已发布');
        })}>确认发布</Button></>}>
      <p className="text-sm">将发布 {assignedCount} 节课。{draft.items.some((row) => row.weekday === null) ? `另有 ${draft.items.filter((row) => row.weekday === null).length} 节仍在暂放区。` : ''}</p>
      {error && <p className="schedule-error" role="alert">{error}</p>}
    </ModalFrame>}
    {modal === 'clear' && <ModalFrame title="清空课表草稿" description="将当前草稿中所有已安排课程移入暂放区。"
      onClose={closeModal} actions={<><Button variant="ghost" disabled={busy} onClick={closeModal}>取消</Button>
        <Button variant="destructive" disabled={busy} onClick={() => {
          const unplaced = draft.items.map((item) => ({
            ...item, stageId: null, weekday: null, periodTypeId: null, lessonIndex: null,
          }));
          void saveItems(unplaced, '已清空课表草稿').then((saved) => {
            if (!saved) return;
            resetSelection();
            setModal(null);
          });
        }}>确认清空</Button></>}>
      <p className="text-sm text-ink-secondary">
        {assignedCount} 节已安排课程将移入暂放区；课程、排课规则和正式版不受影响。完成后可以通过“撤销”恢复。
      </p>
      {error && <p className="schedule-error" role="alert">{error}</p>}
    </ModalFrame>}
    {modal === 'solve' && <ModalFrame title={supplement ? '补排暂放课节' : '自动排课'} description={supplement && keepPlacements
      ? '优先使用空课位，必要时腾挪所选班级内未锁定的课节。' : '选择参与排课的班级。已锁定的课节保留原位置。'}
      onClose={closeModal} wide actions={<><Button variant="ghost" onClick={closeModal}>取消</Button>
        <Button disabled={!solveClasses.length || !!solveIssues.length || !!seed && !/^[0-9]{1,10}$/.test(seed) || !draft.assignments.some((row) => solveClasses.includes(row.classId))}
          onClick={runSolver}>{supplement ? '开始补排' : '开始自动排课'}</Button></>}>
      <div className="flex flex-wrap items-center gap-3 text-sm">
        <Button variant="outline" size="sm" onClick={() => setSolveClasses(draft.classes.map((row) => row.id))}>全选</Button>
        <Button variant="ghost" size="sm" onClick={() => setSolveClasses([])}>清空</Button>
        <label className="inline-flex items-center gap-2"><Checkbox checked={keepPlacements} onCheckedChange={(checked) => setKeepPlacements(checked === true)} />{supplement ? '优先保留已有排课' : '保留已有排课'}</label>
        <label className="flex items-center gap-2">排课强度 <SelectField ariaLabel="排课强度" className="h-8 w-auto min-w-[7rem]"
          value={strength} onValueChange={setStrength} options={[
            { value: 'fast', label: '快速' }, { value: 'normal', label: '标准' }, { value: 'high', label: '高强度' },
          ]} /></label>
        <label className="flex items-center gap-2">求解种子 <Input className="h-8 w-28" inputMode="numeric"
          placeholder="自动生成" value={seed} onChange={(event) => setSeed(event.target.value)} /></label>
        <Input aria-label="搜索班级" className="h-8 w-48" placeholder="搜索班级" value={solveClassQuery}
          onChange={(event) => setSolveClassQuery(event.target.value)} />
      </div>
      {draft.stages.map((row) => {
        const query = solveClassQuery.trim().toLocaleLowerCase();
        const ids = draft.classes.filter((schoolClass) => draft.grades.some((grade) => grade.id === schoolClass.gradeId && grade.stageId === row.id) &&
          (!query || schoolClass.name.toLocaleLowerCase().includes(query)));
        if (query && ids.length === 0) return null;
        const selectedCount = ids.filter((item) => solveClasses.includes(item.id)).length;
        return <fieldset key={row.id} className="rounded-control border border-border px-3 pb-2">
          <legend className="px-1 text-sm font-semibold"><label>
            <Checkbox checked={ids.length > 0 && selectedCount === ids.length ? true : selectedCount > 0 ? 'indeterminate' : false}
              onCheckedChange={(checked) => setSolveClasses((current) => checked === true
                ? [...new Set([...current, ...ids.map((item) => item.id)])] : current.filter((id) => !ids.some((item) => item.id === id)))} />{row.name}
          </label></legend>
          <div className="flex flex-wrap gap-3 text-sm">{ids.map((item) => <label key={item.id} className="inline-flex items-center gap-1.5">
            <Checkbox checked={solveClasses.includes(item.id)}
              onCheckedChange={(checked) => setSolveClasses((current) => checked === true ? [...new Set([...current, item.id])] : current.filter((id) => id !== item.id))} />{item.name}
          </label>)}</div>
        </fieldset>;
      })}
      {solveClassQuery.trim() && !draft.classes.some((item) => item.name.toLocaleLowerCase().includes(solveClassQuery.trim().toLocaleLowerCase())) &&
        <p className="py-2 text-sm text-ink-secondary">没有匹配的班级。</p>}
      {solveIssues.length > 0 && <div className="schedule-alert"><strong>排课前检查</strong><ul className="ml-5 list-disc">
        {solveIssues.map((issue) => <li key={issue}>{issue}</li>)}</ul></div>}
    </ModalFrame>}
    {modal === 'detect' && <ModalFrame title="课表检测结果" description={detection.length ? `发现 ${detection.length} 项约束问题` : '当前课表未发现硬约束冲突。'}
      onClose={closeModal} actions={<><Button variant="ghost" disabled={!detection.length} onClick={() =>
        void navigator.clipboard.writeText(detection.join('\n')).catch((reason) => setError(String(reason)))}>复制全部</Button><Button onClick={closeModal}>完成</Button></>}>
      {!!detection.length && <ul className="ml-5 list-disc space-y-1 text-sm">{detection.map((issue) => <li key={issue}>{issue}</li>)}</ul>}
    </ModalFrame>}
    {modal === 'report' && report && <ModalFrame title="未排课程报告" description={`上次自动排课检查了 ${report.candidateChecks} 个候选位置。`} onClose={closeModal}>
      {Object.entries(report.blockers).filter(([id]) => draft.items.some((row) => row.id === id && row.weekday === null)).map(([id, reasons]) => {
        const item = draft.items.find((row) => row.id === id)!;
        return <div className="text-sm" key={id}><strong>{itemLabel(item)}</strong>
          <p className="text-ink-secondary">{reasons.join('；') || '暂无阻断详情'}</p></div>;
      })}
      {report.issues.length > 0 && <ul className="ml-5 list-disc text-sm">{report.issues.map((issue) => <li key={issue}>{issue}</li>)}</ul>}
      {Object.keys(report.blockers).length === 0 && report.issues.length === 0 && <p className="text-sm">上次排课没有未排课程。</p>}
    </ModalFrame>}
    {modal === 'reconcile' && baseline && <ModalFrame title="协调草稿课表" description="保留可继续使用的课节，为受影响的课程寻找新位置。确认后写入草稿。"
      onClose={closeModal} wide actions={<><Button variant="ghost" disabled={busy} onClick={closeModal}>暂不协调</Button>
        <Button disabled={busy} onClick={() => {
          if (!reconciliation) { setReconciliation(reconcileSchedule(draft, baseline)); return; }
          void perform(async () => {
            await schoolRepository.saveScheduleDraft(draft, reconciliation.items, { baseline, locks: reconciliation.locks });
            setDraft({ ...draft, items: reconciliation.items, locks: reconciliation.locks }); setBaseline(null);
            setModal(null); setHistory({ undo: [], redo: [] }); resetSelection(); setFeedback('草稿课表已协调'); refreshSummary();
          });
        }}>{reconciliation ? '确认协调并写入' : '生成协调预览'}</Button></>}>
      {error && <p className="schedule-error" role="alert">{error}</p>}
      {reconciliation && baselineContext && (() => {
        const nextContext = createScheduleContext({ ...draft, items: reconciliation.items });
        const old = new Map(baseline.items.map((row) => [row.id, row]));
        const next = new Map(reconciliation.items.map((row) => [row.id, row]));
        const diff = [...new Set([...old.keys(), ...next.keys()])].flatMap((id) => {
          const before = old.get(id); const after = next.get(id);
          const label = (row: ScheduleItem | undefined, ctx: ScheduleContext) => {
            if (!row) return '无';
            const slot = positionOf(ctx, row);
            return `${ctx.teachers.get(row.teacherId ?? '') ?? '未分配教师'} · ${slot ? slotName(slot) : '暂放'}`;
          };
          const left = label(before, baselineContext); const right = label(after, nextContext);
          return left === right ? [] : [{ id, name: before ? itemLabel(before, baselineContext) : itemLabel(after!, nextContext), left, right }];
        });
        return <>
          <p className="text-sm">{diff.length} 节变更，{draft.locks.length - reconciliation.locks.length} 项锁定解除。</p>
          {diff.length > 0 && <div className="max-h-[42vh] overflow-auto">
            <table className="w-full text-left text-sm"><thead><tr><th>课程</th><th>变更前</th><th>变更后</th></tr></thead>
              <tbody>{diff.map((row) => <tr key={row.id} className="border-t border-border">
                <td className="py-2 pr-3">{row.name}</td><td className="pr-3">{row.left}</td><td>{row.right}</td>
              </tr>)}</tbody></table>
          </div>}
        </>;
      })()}
    </ModalFrame>}
    {modal === 'export' && schedule && <Dialog open onOpenChange={(open) => { if (!open && !busy) closeModal(); }}>
      <DialogContent className="max-w-[560px] gap-0 p-0 overflow-hidden">
        <DialogHeader className="border-b-0 px-5 pt-5 pb-3">
          <DialogTitle className="text-[16px] font-semibold">导出课表</DialogTitle>
          <DialogDescription className="text-[11px] text-ink-secondary">班级、教师和学校总课表 · Excel 压缩包</DialogDescription>
        </DialogHeader>
        <Tabs value={exportTab} onValueChange={(next) => setExportTab(next as 'content' | 'print' | 'split')} className="w-full">
          <div className="px-5 pb-3.5">
            <TabsList aria-label="导出选项分类" className="grid h-9 w-full grid-cols-3 rounded-control bg-table-header p-[3px]">
              <TabsTrigger value="content" className="h-7 text-[12px]">内容与字号</TabsTrigger>
              <TabsTrigger value="print" className="h-7 text-[12px]">打印设置</TabsTrigger>
              <TabsTrigger value="split" className="h-7 text-[12px]">分表方式</TabsTrigger>
            </TabsList>
          </div>
          <div className="border-t border-border px-5 pt-4 pb-5 min-h-[296px]">
            <TabsContent value="content" className="mt-0 space-y-3.5">
              <div>
                <div className="flex items-center justify-between">
                  <span className="text-[12px] font-semibold text-ink-secondary">课位格文字样式</span>
                  <span className="text-[11px] text-ink-secondary">分别设置科目、教师、班级的字号、字重与颜色</span>
                </div>
                <div className="mt-1.5 space-y-2">
                  {([
                    ['subjectStyle', '科目', '班级课表 · 教师课表 · 总课表'],
                    ['teacherStyle', '教师', '班级课表 · 总课表'],
                    ['classStyle', '班级', '教师课表'],
                  ] as const).map(([styleKey, title, scopeHint]) => {
                    const currentStyle = exportOptions[styleKey];
                    const updateStyle = (patch: Partial<typeof currentStyle>) => {
                      const nextStyle = { ...currentStyle, ...patch };
                      setExportOptions({
                        ...exportOptions,
                        [styleKey]: nextStyle,
                        ...(styleKey === 'teacherStyle' && patch.fontSize !== undefined
                          ? { fontSize: patch.fontSize }
                          : {}),
                      });
                    };
                    const presets = [
                      ['#000000', '墨黑'],
                      ['#5E6B80', '深灰'],
                      ['#2864DC', '晴空蓝'],
                      ['#087D89', '海盐青'],
                      ['#1F765E', '松石绿'],
                      ['#B74752', '绛红'],
                    ] as const;
                    return (
                      <div
                        key={styleKey}
                        className="flex flex-wrap items-center justify-between gap-2 rounded-control border border-border px-3 py-2"
                      >
                        <div className="min-w-[116px]">
                          <div className="text-[12.5px] font-semibold text-ink">{title}</div>
                          <div className="text-[10.5px] text-ink-secondary">{scopeHint}</div>
                        </div>
                        <div className="flex flex-wrap items-center gap-2">
                          <SelectField
                            ariaLabel={`${title}字号`}
                            className="h-7 w-[5.25rem] text-[12px]"
                            value={String(currentStyle.fontSize)}
                            onValueChange={(val) => updateStyle({ fontSize: Number(val) })}
                            options={[8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20].map((sz) => ({
                              value: String(sz),
                              label: `${sz} 磅`,
                            }))}
                          />
                          <div
                            role="group"
                            aria-label={`${title}字重`}
                            className="inline-flex h-7 items-center rounded-md border border-border p-0.5 text-[11.5px]"
                          >
                            {([
                              [false, '常规'],
                              [true, '加粗'],
                            ] as const).map(([isBold, weightLabel]) => {
                              const active = currentStyle.bold === isBold;
                              return (
                                <button
                                  key={weightLabel}
                                  type="button"
                                  aria-pressed={active}
                                  onClick={() => updateStyle({ bold: isBold })}
                                  className={`h-5 rounded px-2 transition-colors ${
                                    active
                                      ? 'bg-primary text-on-accent font-semibold'
                                      : 'text-ink-secondary hover:text-ink'
                                  }`}
                                >
                                  {weightLabel}
                                </button>
                              );
                            })}
                          </div>
                          <div className="flex items-center gap-1" role="group" aria-label={`${title}颜色`}>
                            {presets.map(([hex, colorName]) => {
                              const selectedColor = currentStyle.color.toUpperCase() === hex;
                              return (
                                <button
                                  key={hex}
                                  type="button"
                                  title={`${title}颜色：${colorName}`}
                                  aria-label={`${title}颜色：${colorName}`}
                                  aria-pressed={selectedColor}
                                  onClick={() => updateStyle({ color: hex })}
                                  className={`h-4 w-4 rounded-full border transition-transform ${
                                    selectedColor
                                      ? 'scale-110 border-brand-accent ring-2 ring-ring/40'
                                      : 'border-border hover:scale-105'
                                  }`}
                                  style={{ backgroundColor: hex }}
                                />
                              );
                            })}
                            <label
                              title={`自定义${title}颜色`}
                              className="relative ml-0.5 inline-flex h-5 w-5 cursor-pointer items-center justify-center rounded border border-border text-[10px] text-ink-secondary hover:border-brand-accent"
                            >
                              <input
                                type="color"
                                aria-label={`自定义${title}颜色`}
                                value={currentStyle.color}
                                onChange={(event) => updateStyle({ color: event.target.value.toUpperCase() })}
                                className="sr-only"
                              />
                              <span
                                className="h-3 w-3 rounded-sm border border-border/60"
                                style={{ backgroundColor: currentStyle.color }}
                              />
                            </label>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              <div>
                <div className="text-[12px] font-semibold text-ink-secondary">课位格预览</div>
                <div className="mt-1.5 grid grid-cols-3 gap-2">
                  <div className="rounded-control border border-border px-2.5 py-2 text-center">
                    <div className="text-[10.5px] text-ink-secondary">班级课表（科目 / 教师）</div>
                    <div className="mt-1.5 rounded border border-border/80">
                      <div
                        className="px-1.5 py-1 leading-tight truncate"
                        style={{
                          fontSize: `${exportOptions.subjectStyle.fontSize}px`,
                          fontWeight: exportOptions.subjectStyle.bold ? 700 : 400,
                          color: exportOptions.subjectStyle.color,
                        }}
                      >
                        语文
                      </div>
                      <div
                        className="border-t border-dotted border-border px-1.5 py-1 leading-tight truncate"
                        style={{
                          fontSize: `${exportOptions.teacherStyle.fontSize}px`,
                          fontWeight: exportOptions.teacherStyle.bold ? 700 : 400,
                          color: exportOptions.showTeacher ? exportOptions.teacherStyle.color : 'var(--color-ink-secondary)',
                          opacity: exportOptions.showTeacher ? 1 : 0.4,
                        }}
                      >
                        {exportOptions.showTeacher ? '张老师' : '（不显示教师）'}
                      </div>
                    </div>
                  </div>
                  <div className="rounded-control border border-border px-2.5 py-2 text-center">
                    <div className="text-[10.5px] text-ink-secondary">教师课表（科目 / 班级）</div>
                    <div className="mt-1.5 rounded border border-border/80">
                      <div
                        className="px-1.5 pt-1 pb-0.5 leading-tight truncate"
                        style={{
                          fontSize: `${exportOptions.subjectStyle.fontSize}px`,
                          fontWeight: exportOptions.subjectStyle.bold ? 700 : 400,
                          color: exportOptions.subjectStyle.color,
                        }}
                      >
                        语文
                      </div>
                      <div
                        className="px-1.5 pb-1 pt-0.5 leading-tight truncate"
                        style={{
                          fontSize: `${exportOptions.classStyle.fontSize}px`,
                          fontWeight: exportOptions.classStyle.bold ? 700 : 400,
                          color: exportOptions.showClass ? exportOptions.classStyle.color : 'var(--color-ink-secondary)',
                          opacity: exportOptions.showClass ? 1 : 0.4,
                        }}
                      >
                        {exportOptions.showClass ? '一年级 1 班' : '（不显示班级）'}
                      </div>
                    </div>
                  </div>
                  <div className="rounded-control border border-border px-2.5 py-2 text-center">
                    <div className="text-[10.5px] text-ink-secondary">总课表（科目 / 教师）</div>
                    <div className="mt-1.5 rounded border border-border/80 px-1.5 py-1">
                      <div
                        className="leading-tight truncate"
                        style={{
                          fontSize: `${exportOptions.subjectStyle.fontSize}px`,
                          fontWeight: exportOptions.subjectStyle.bold ? 700 : 400,
                          color: exportOptions.subjectStyle.color,
                        }}
                      >
                        语文
                      </div>
                      <div
                        className="mt-0.5 leading-tight truncate"
                        style={{
                          fontSize: `${exportOptions.teacherStyle.fontSize}px`,
                          fontWeight: exportOptions.teacherStyle.bold ? 700 : 400,
                          color: exportOptions.showTeacher ? exportOptions.teacherStyle.color : 'var(--color-ink-secondary)',
                          opacity: exportOptions.showTeacher ? 1 : 0.4,
                        }}
                      >
                        {exportOptions.showTeacher ? '张老师' : '（不显示教师）'}
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div>
                <div className="text-[12px] font-semibold text-ink-secondary">课节字段</div>
                <p className="mt-0.5 text-[11px] text-ink-secondary">科目、带班活动和课表表头始终保留。</p>
                <div className="mt-2 grid grid-cols-2 gap-2">
                  {([
                    ['showTeacher', '任课及带班教师'],
                    ['showClass', '课节内的班级'],
                    ['showTime', '课节起止时间'],
                    ['showWeek', '单双周标记'],
                  ] as const).map(([key, label]) => (
                    <label key={key} className="flex cursor-pointer items-center gap-2 rounded-control border border-border px-2.5 py-2 text-[12px] font-medium text-ink select-none">
                      <Checkbox
                        checked={exportOptions[key]}
                        onCheckedChange={(checked) => setExportOptions({ ...exportOptions, [key]: checked === true })}
                      />
                      <span className="truncate">{label}</span>
                    </label>
                  ))}
                </div>
              </div>
            </TabsContent>
            <TabsContent value="print" className="mt-0 space-y-3">
              <div className="rounded-control border border-border p-3">
                <div className="text-[13px] font-semibold text-ink">打印缩放</div>
                <div className="mt-2">
                  <SelectField
                    ariaLabel="打印缩放"
                    className="h-9 w-full"
                    value={exportOptions.printFit}
                    onValueChange={(value) => setExportOptions({ ...exportOptions, printFit: value as ExportOptions['printFit'] })}
                    options={[
                      { value: 'original', label: '原始比例（Excel 默认）' },
                      { value: 'width', label: '一页宽，高度自动分页' },
                      { value: 'page', label: '每张表缩放至一页' },
                    ]}
                  />
                </div>
                <p className="mt-1.5 text-[11px] text-ink-secondary">总课表较长时，选一页宽可保留纵向分页。</p>
              </div>
              <div className={exportOptions.printFit === 'original' ? 'opacity-55' : undefined}>
                <div className="flex items-center justify-between gap-3 rounded-control border border-border px-3 py-2.5">
                  <div className="min-w-0">
                    <div className="text-[13px] font-medium text-ink">横向打印</div>
                    <p className="mt-0.5 text-[11px] text-ink-secondary">
                      {exportOptions.printFit === 'original'
                        ? '选择自适应缩放后可调整 A4 纸张方向。'
                        : exportOptions.landscape
                          ? 'A4 横向'
                          : 'A4 纵向'}
                    </p>
                  </div>
                  <Switch
                    aria-label="横向打印"
                    disabled={exportOptions.printFit === 'original'}
                    checked={exportOptions.landscape}
                    onCheckedChange={(checked) => setExportOptions({ ...exportOptions, landscape: checked })}
                  />
                </div>
              </div>
              {(() => {
                const isOriginal = exportOptions.printFit === 'original';
                const isWidth = exportOptions.printFit === 'width';
                const isPage = exportOptions.printFit === 'page';
                const effectiveLandscape = isOriginal ? true : exportOptions.landscape;
                const renderMiniGrid = (rowsCount: number, colsCount: number, compact = false) => (
                  <div className="flex flex-col gap-[2px]">
                    <div className="h-[4px] w-3/5 self-center rounded-[1px] bg-ink opacity-70" />
                    <div
                      className="grid border border-control-border"
                      style={{
                        gridTemplateColumns: `1.1fr repeat(${colsCount}, 1fr)`,
                      }}
                    >
                      <div className="h-[6px] border-b border-r border-border" style={{ backgroundColor: '#DCEBD2' }} />
                      {Array.from({ length: colsCount }).map((_, c) => (
                        <div
                          key={`h-${c}`}
                          className="h-[6px] border-b border-r last:border-r-0 border-border"
                          style={{ backgroundColor: '#DCEBD2' }}
                        />
                      ))}
                      {Array.from({ length: rowsCount }).map((_, r) => {
                        const isCommon = r === 1 && rowsCount >= 4;
                        return (
                          <div key={`r-${r}`} className="contents">
                            <div
                              className={`${compact ? 'h-[6px]' : 'h-[8px]'} border-b last:border-b-0 border-r border-border`}
                              style={{ backgroundColor: '#F3F4EF' }}
                            />
                            {isCommon ? (
                              <div
                                className={`${compact ? 'h-[6px]' : 'h-[8px]'} border-b border-border`}
                                style={{
                                  gridColumn: `span ${colsCount} / span ${colsCount}`,
                                  backgroundColor: '#F3EEDB',
                                }}
                              />
                            ) : (
                              Array.from({ length: colsCount }).map((__, c) => (
                                <div
                                  key={`c-${r}-${c}`}
                                  className={`${compact ? 'h-[6px]' : 'h-[8px]'} flex flex-col items-center justify-center gap-[1px] border-b last:border-b-0 border-r last:border-r-0 border-border px-[1px]`}
                                >
                                  <span
                                    className="block h-[2px] w-3/4 rounded-[1px]"
                                    style={{ backgroundColor: exportOptions.subjectStyle.color, opacity: 0.75 }}
                                  />
                                  <span
                                    className="block h-[1.5px] w-1/2 rounded-[1px]"
                                    style={{ backgroundColor: exportOptions.teacherStyle.color, opacity: 0.45 }}
                                  />
                                </div>
                              ))
                            )}
                          </div>
                        );
                      })}
                    </div>
                  </div>
                );

                return (
                  <div className="rounded-control border border-border px-3 py-2.5">
                    <div className="flex items-center justify-between">
                      <span className="text-[12px] font-semibold text-ink-secondary">打印预览效果</span>
                      <span className="text-[11px] font-medium text-brand-accent">
                        {isOriginal
                          ? '原始比例 · 自然分页'
                          : isWidth
                            ? `${effectiveLandscape ? 'A4 横向' : 'A4 纵向'} · 一页宽纵向分页`
                            : `${effectiveLandscape ? 'A4 横向' : 'A4 纵向'} · 单页完整缩放`}
                      </span>
                    </div>
                    <div className="mt-2 grid grid-cols-2 gap-2.5">
                      <div className="flex flex-col items-center justify-between rounded-md border border-border px-2.5 py-2">
                        <div className="flex w-full items-center justify-between text-[10.5px] text-ink-secondary">
                          <span>班级 / 教师课表</span>
                          <span>{isOriginal ? '100% 比例' : '1 / 1 页'}</span>
                        </div>
                        <div className="my-1.5 flex h-[96px] items-center justify-center">
                          <div
                            className={`relative flex flex-col justify-between rounded-[3px] border border-control-border bg-surface p-1.5 shadow-sm transition-all ${
                              effectiveLandscape ? 'h-[76px] w-[108px]' : 'h-[92px] w-[66px]'
                            }`}
                          >
                            {renderMiniGrid(effectiveLandscape ? 4 : 5, 5, !effectiveLandscape)}
                            {isOriginal && (
                              <>
                                <div
                                  title="Excel 默认分页线"
                                  className="pointer-events-none absolute inset-y-0 right-[22px] border-r border-dashed border-brand-accent"
                                />
                                <span className="pointer-events-none absolute bottom-0.5 right-1 rounded bg-surface px-1 text-[8px] font-medium text-brand-accent">
                                  分页线
                                </span>
                              </>
                            )}
                            {!isOriginal && (
                              <span className="text-right text-[8px] text-ink-secondary leading-none">
                                {effectiveLandscape ? 'A4 横向' : 'A4 纵向'}
                              </span>
                            )}
                          </div>
                        </div>
                        <div className="text-[10px] text-ink-secondary">
                          {isOriginal ? '按列宽原始尺寸输出' : '单张 A4 完整容纳整周课表'}
                        </div>
                      </div>

                      <div className="flex flex-col items-center justify-between rounded-md border border-border px-2.5 py-2">
                        <div className="flex w-full items-center justify-between text-[10.5px] text-ink-secondary">
                          <span>学校总课表（长表）</span>
                          <span>
                            {isPage ? '缩至 1 页' : isWidth ? '第 1~N 页' : '横纵自然分页'}
                          </span>
                        </div>
                        <div className="my-1.5 flex h-[96px] items-center justify-center">
                          {isWidth ? (
                            <div className="flex flex-col items-center gap-1">
                              <div
                                className={`relative flex flex-col justify-between rounded-t-[3px] border border-b-0 border-control-border bg-surface px-1.5 pt-1.5 pb-1 shadow-sm transition-all ${
                                  effectiveLandscape ? 'h-[50px] w-[108px]' : 'h-[54px] w-[68px]'
                                }`}
                              >
                                {renderMiniGrid(2, 6, true)}
                                <span className="text-right text-[8px] text-ink-secondary leading-none">第 1 页</span>
                              </div>
                              <div
                                className={`border-t border-dashed border-brand-accent ${
                                  effectiveLandscape ? 'w-[114px]' : 'w-[74px]'
                                }`}
                              />
                              <div
                                className={`relative flex flex-col justify-between rounded-b-[3px] border border-t-0 border-control-border bg-surface px-1.5 pt-1 pb-1 shadow-sm transition-all ${
                                  effectiveLandscape ? 'h-[36px] w-[108px]' : 'h-[34px] w-[68px]'
                                }`}
                              >
                                {renderMiniGrid(1, 6, true)}
                                <span className="text-right text-[8px] text-brand-accent leading-none">第 2 页（自动续页）</span>
                              </div>
                            </div>
                          ) : (
                            <div
                              className={`relative flex flex-col justify-between rounded-[3px] border border-control-border bg-surface p-1.5 shadow-sm transition-all ${
                                effectiveLandscape ? 'h-[76px] w-[108px]' : 'h-[92px] w-[66px]'
                              }`}
                            >
                              {renderMiniGrid(effectiveLandscape ? 5 : 6, 6, true)}
                              {isOriginal ? (
                                <>
                                  <div className="pointer-events-none absolute inset-y-0 right-[26px] border-r border-dashed border-brand-accent" />
                                  <div className="pointer-events-none absolute inset-x-0 bottom-[22px] border-b border-dashed border-brand-accent" />
                                  <span className="pointer-events-none absolute bottom-0.5 right-1 rounded bg-surface px-1 text-[8px] font-medium text-brand-accent">
                                    多页拆分
                                  </span>
                                </>
                              ) : (
                                <span className="text-right text-[8px] text-ink-secondary leading-none">
                                  全表缩至 1 页
                                </span>
                              )}
                            </div>
                          )}
                        </div>
                        <div className="text-[10px] text-ink-secondary">
                          {isWidth
                            ? '列宽锁在一页内，纵向跨页不裁列'
                            : isPage
                              ? '整张总课表压缩进单页 A4'
                              : '超出纸张边界时向右侧和下方分页'}
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })()}
            </TabsContent>
            <TabsContent value="split" className="mt-0 space-y-3.5">
              <div>
                <div className="text-[12px] font-semibold text-ink-secondary">教师课表</div>
                <div className="mt-1.5 grid grid-cols-2 gap-2">
                  {([
                    [true, '统一时间轴（推荐）', '起止时间相同的课节合并为一行。'],
                    [false, '按学段分别展示', '保留各学段原有的作息行。'],
                  ] as const).map(([unified, label, desc]) => {
                    const selectedOption = exportOptions.teacherUnified === unified;
                    return (
                      <button
                        key={label}
                        type="button"
                        onClick={() => setExportOptions({ ...exportOptions, teacherUnified: unified })}
                        className={`flex items-start gap-2 rounded-control border px-2.5 py-2 text-left transition-colors ${
                          selectedOption
                            ? 'border-brand-accent'
                            : 'border-border'
                        }`}
                      >
                        <span
                          aria-hidden="true"
                          className={`mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded-full border ${
                            selectedOption ? 'border-brand-accent' : 'border-control-border'
                          }`}
                        >
                          {selectedOption && <span className="h-2 w-2 rounded-full bg-brand-accent" />}
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="block text-[12px] font-semibold text-ink">{label}</span>
                          <span className="mt-0.5 block text-[11px] text-ink-secondary leading-snug">{desc}</span>
                        </span>
                      </button>
                    );
                  })}
                </div>
                <div className={`mt-2 ${!exportOptions.showClass ? 'opacity-55' : ''}`}>
                  <label className={`flex items-center gap-2 rounded-control border border-border px-2.5 py-2 text-[12px] select-none ${exportOptions.showClass ? 'cursor-pointer' : 'cursor-not-allowed'}`}>
                    <Checkbox
                      disabled={!exportOptions.showClass}
                      checked={exportOptions.showTeacherStage && exportOptions.showClass}
                      onCheckedChange={(checked) => setExportOptions({ ...exportOptions, showTeacherStage: checked === true })}
                    />
                    <div className="min-w-0 flex-1">
                      <div className="font-medium text-ink">跨学段课程显示学段</div>
                      {!exportOptions.showClass && (
                        <div className="text-[11px] text-ink-secondary">请先启用课节内的班级。</div>
                      )}
                    </div>
                  </label>
                </div>
              </div>
              <div>
                <div className="text-[12px] font-semibold text-ink-secondary">学校总课表</div>
                <div className="mt-1.5 flex items-center justify-between gap-3 rounded-control border border-border px-3 py-2.5">
                  <div className="min-w-0">
                    <div className="text-[13px] font-medium text-ink">学校总课表按学段汇总整周</div>
                    <p className="mt-0.5 text-[11px] text-ink-secondary">关闭后按星期分别生成。</p>
                  </div>
                  <Switch
                    aria-label="学校总课表按学段汇总整周"
                    checked={exportOptions.schoolWeekly}
                    onCheckedChange={(checked) => setExportOptions({ ...exportOptions, schoolWeekly: checked })}
                  />
                </div>
              </div>
            </TabsContent>
            {error && <p className="schedule-error mt-3" role="alert">{error}</p>}
          </div>
        </Tabs>
        <DialogFooter className="border-t border-border px-5 py-3">
          <Button variant="ghost" disabled={busy} onClick={closeModal}>取消</Button>
          <Button
            disabled={busy}
            onClick={() => void perform(async () => {
              const { exportSchedule } = await import('./scheduleExport');
              if (await exportSchedule(schedule, exportOptions, schoolName)) {
                setModal(null);
                setFeedback('课表已导出');
              }
            })}
          >
            {busy ? '正在导出课表，请稍候…' : '确认导出'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>}
  </div>;
}
