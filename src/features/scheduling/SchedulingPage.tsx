import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type DragEvent, type ReactNode } from 'react';
import { ArrowDownToLine, Check, CheckCircle2, ChevronDown, ChevronRight, Columns2, Lock, LockOpen, Redo2, Rows2, Search, SlidersHorizontal, Sparkles, Undo2, Upload, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Progress } from '@/components/ui/progress';
import { SearchableSelect } from '@/components/ui/searchable-select';
import { SelectField } from '@/components/ui/select-field';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import type { ScheduleItem, ScheduleLock, WeekMode } from '@/domain/models';
import {
  createScheduleContext, detectSchedule, freeSlotFor, groupBy, isLessonLocked, occursInWeek, positionOf, prepareDemand,
  preflightSchedule, previewPlacement, reconcileSchedule, roomFor, slotKey, timesOverlap,
  type ScheduleContext, type ScheduleData, type ScheduleSlot,
} from '@/domain/scheduling';
import { schoolRepository } from '@/repository/schoolRepository';
import type { ScheduleRunReport } from '@/repository/scheduleStorage';
import { useAppStore } from '@/store/useAppStore';
import { getSubjectColor } from '@/styles/subjectColors';
import { TimetableGrid, clockLabel, slotName, weekdayName } from './TimetableGrid';
import { ScheduleRulesDialog } from './ScheduleRulesDialog';
import type { SolveRequest, SolveResponse } from './schedule.worker';
import type { ExportOptions } from './scheduleExport';
import './scheduling.css';

type View = 'class' | 'teacher' | 'all' | 'room';
type Layout = 'side' | 'stack';
type Modal = 'solve' | 'rules' | 'publish' | 'detect' | 'report' | 'export' | 'reconcile' | null;
type Reconciliation = ReturnType<typeof reconcileSchedule>;
type Edit = { before: ScheduleItem[]; after: ScheduleItem[] };
type StageClassGroup = { id: string; name: string; classes: Array<{ id: string; name: string }> };

const weekLabels: Record<WeekMode, string> = { weekly: '每周', odd: '单周', even: '双周' };
const viewOptions = [['class', '班级课表'], ['teacher', '教师课表'], ['all', '总课表'], ['room', '场室课表']] as const;
const layouts: Record<Layout, string> = { side: '左右分屏', stack: '上下分屏' };

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
      <Button type="button" variant="outline" size="sm"
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
                  className={`h-8 w-full justify-between gap-2 px-2 text-left ${isSelected ? 'border border-accent bg-selection font-semibold text-ink hover:bg-selection' : 'text-ink'}`}
                  style={isSelected ? { color: 'var(--color-ink)' } : undefined}
                  onClick={() => { onChange(schoolClass.id); setOpen(false); }}>
                  <span className="truncate">{schoolClass.name}</span>
                  <Check aria-hidden="true" className={`h-3.5 w-3.5 shrink-0 ${isSelected ? 'text-accent' : 'opacity-0'}`} />
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
    <DialogContent className={`max-h-[86vh] overflow-auto ${wide ? 'max-w-[730px]' : ''}`}>
      <DialogHeader><DialogTitle>{title}</DialogTitle><DialogDescription>{description}</DialogDescription></DialogHeader>
      {children}
      <DialogFooter>{actions ?? <Button onClick={onClose}>完成</Button>}</DialogFooter>
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
  const dark = useAppStore((state) => state.resolvedDark);
  const [draft, setDraft] = useState<ScheduleData | null>(null);
  const [published, setPublished] = useState<ScheduleData | null>(null);
  const [baseline, setBaseline] = useState<ScheduleData | null>(null);
  const [report, setReport] = useState<ScheduleRunReport | null>(null);
  const [version, setVersion] = useState<'draft' | 'published'>('draft');
  const [view, setView] = useState<View>('class');
  const [layout, setLayout] = useState<Layout>('side');
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
  const [exportOptions, setExportOptions] = useState<ExportOptions>({
    classes: true, teachers: true, school: true, rooms: false, showTeacher: true, showClass: true,
    showTime: true, showWeek: true, fontSize: 10, printFit: 'original', landscape: false,
  });
  const worker = useRef<Worker | null>(null);
  const cancelSolve = useRef<(() => void) | null>(null);
  const running = useRef(false);

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
  const split = view === 'class';
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
      onDragEnd={() => setHovered(null)}>{contents}</button>
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

  const renderPool = () => <section className="schedule-panel schedule-pool-panel" onDragOver={(event) => {
    if (!readOnly && movingItem?.weekday != null) { event.preventDefault(); event.dataTransfer.dropEffect = 'move'; }
  }} onDrop={(event) => {
    if (!readOnly) { event.preventDefault(); void place(null, event.dataTransfer.getData('text/plain') || moving); }
  }}>
    <div className="schedule-panel-heading schedule-pool-heading">
      <h3>暂放区</h3>
      <div className="schedule-pool-heading-meta">
        <span className="schedule-pool-count">{pool.length} 节</span>
        {pool.length > 0 && <div className="schedule-toolbar-group">
          {view === 'class' && <Segment label="暂放范围" value={poolScope} options={[['class', '本班'], ['all', '全部']]} onChange={setPoolScope} />}
          {!readOnly && <Button variant="ghost" size="sm" disabled={busy} onClick={() => openSolve(true)}>补排</Button>}
          <Button variant="ghost" size="sm" disabled={!report} onClick={() => setModal('report')}>未排报告</Button>
        </div>}
      </div>
    </div>
    {pool.length ? <div className="schedule-pool">{pool.map((item) => <div key={item.id} className="min-w-0"
      title={report?.blockers[item.id]?.join('；')}>{renderLesson(item, 'both', !busy && !readOnly)}</div>)}</div>
      : <div role="group" aria-label="拖拽课程卡片到此处暂存" className="schedule-pool-dropzone">
        <Upload aria-hidden="true" className="h-6 w-6" />
        <span>拖拽课程卡片到此处暂存</span>
      </div>}
    {!readOnly && movingItem?.weekday != null && <div className="schedule-feedback">
      <Button variant="outline" size="sm" disabled={busy} onClick={() => void place(null)}>移入暂放区</Button>
    </div>}
  </section>;

  return <div className="schedule-page" onKeyDown={(event) => {
    const target = event.target;
    const insideOverlay = target instanceof HTMLElement && target.closest('[role="dialog"], [role="listbox"], [role="menu"], input, textarea');
    if (event.key === 'Escape' && !insideOverlay && (selected || moving)) resetSelection();
  }}>
    <section className="schedule-panel schedule-sticky-toolbar" aria-label="课表工具栏">
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
      {schedule && <div className="schedule-toolbar border-t border-border">
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
        {view === 'class' && <Segment label="分屏布局" value={layout} options={[
          ['side', <span className="inline-flex items-center gap-1"><Columns2 size={13} />{layouts.side}</span>],
          ['stack', <span className="inline-flex items-center gap-1"><Rows2 size={13} />{layouts.stack}</span>],
        ]} onChange={setLayout} />}
        <div className="schedule-toolbar-group">
          {!readOnly && <>
            <Button variant="ghost" size="sm" disabled={busy || !history.undo.length} onClick={() => void undoRedo('undo')}><Undo2 />撤销</Button>
            <Button variant="ghost" size="sm" disabled={busy || !history.redo.length} onClick={() => void undoRedo('redo')}><Redo2 />重做</Button>
            {view !== 'room' && <Button variant="ghost" size="sm" disabled={busy || !canLock} onClick={changeLock}
              aria-pressed={locked} className={locked ? 'text-warning hover:text-warning' : undefined}>
              {locked ? <Lock /> : <LockOpen />}{locked ? '已锁定' : '锁定'}
            </Button>}
          </>}
          {version === 'draft' && <Button variant="ghost" size="sm" disabled={busy} onClick={() => setModal('rules')}><SlidersHorizontal />规则</Button>}
          <Button variant="ghost" size="sm" disabled={busy || !!baseline && version === 'draft'} onClick={() => {
            setDetection(detectSchedule(context!.data)); setModal('detect');
          }}><CheckCircle2 />检测</Button>
          <Button variant="ghost" size="sm" disabled={busy || (!!baseline && version === 'draft') || (!assignedCount && !schedule.visibleSupervision.length)}
            onClick={() => setModal('export')}><ArrowDownToLine />导出</Button>
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
    {progress && <div className="schedule-alert flex flex-wrap items-center gap-3" role="status">
      <span>正在自动排课</span><Progress aria-label="排课进度" className="min-w-[12rem] max-w-[20rem] flex-1" value={progress.total ? progress.done / progress.total * 100 : null} />
      <span>{progress.total ? `${Math.round(progress.done / progress.total * 100)}%` : '准备中…'}</span>
      <Button variant="outline" size="sm" onClick={() => cancelSolve.current?.()}>取消排课</Button>
    </div>}
    {feedback && <div className="flex items-center justify-between gap-3 rounded-control border border-border bg-surface px-3 py-2 text-sm text-ink-secondary" role="status">
      <span>{feedback}</span>
      <Button type="button" variant="ghost" size="icon" className="h-7 w-7 shrink-0" aria-label="关闭提示" onClick={() => setFeedback('')}>
        <X aria-hidden="true" />
      </Button>
    </div>}

    {!context ? <section className="schedule-panel schedule-empty">
      <p className="font-semibold text-ink">尚未发布正式课表</p>
      <Button variant="ghost" onClick={() => setVersion('draft')}>前往草稿排课</Button>
    </section> : view === 'class' ? <div className="schedule-split" data-layout={layout}>
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
        {!split && version === 'draft' && renderPool()}
      </div>
      {split && <div className="schedule-secondary">
        <section className="schedule-panel schedule-timetable-panel">
          <div className="schedule-timetable-heading"><h2>任课教师课表</h2><span className="text-sm text-ink-secondary">
            {linkedTeacherId ? context.teachers.get(linkedTeacherId) : selectedItem ? '未分配教师' : ''}
          </span></div>
          {linkedTeacherId ? renderTeacher(linkedTeacherId, true) : <p className="schedule-empty">选择班级课节即可查看任课教师课表。</p>}
        </section>
        {version === 'draft' && renderPool()}
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
      {displayedTeacher && version === 'draft' && renderPool()}
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
    {modal === 'export' && schedule && <ModalFrame title="导出课表" description="将选定课表保存为 Excel 压缩包。" onClose={closeModal}
      actions={<><Button variant="ghost" disabled={busy} onClick={closeModal}>取消</Button>
        <Button disabled={busy || !['classes', 'teachers', 'school', 'rooms'].some((key) => exportOptions[key as keyof ExportOptions])}
          onClick={() => void perform(async () => {
            const { exportSchedule } = await import('./scheduleExport');
            if (await exportSchedule(schedule, exportOptions)) { setModal(null); setFeedback('课表压缩包已导出'); }
          })}>{busy ? '正在导出…' : '导出压缩包'}</Button></>}>
      <div className="grid grid-cols-2 gap-3 text-sm">
        {([['classes', '班级课表'], ['teachers', '教师课表'], ['school', '学校总课表'], ['rooms', '场室课表'],
          ['showTeacher', '显示任课和带班教师'], ['showClass', '显示课节所在班级'], ['showTime', '显示起止时间'], ['showWeek', '显示单双周标记']] as const)
          .map(([key, label]) => <label key={key} className="inline-flex items-center gap-2"><Checkbox checked={exportOptions[key]}
            onCheckedChange={(checked) => setExportOptions({ ...exportOptions, [key]: checked === true })} />{label}</label>)}
        <label className="flex flex-wrap items-center gap-2">正文基准字号
          <SelectField ariaLabel="正文基准字号" className="h-8 w-[6rem]" value={String(exportOptions.fontSize)}
            onValueChange={(value) => setExportOptions({ ...exportOptions, fontSize: Number(value) })}
            options={Array.from({ length: 11 }, (_, index) => ({ value: String(index + 8), label: `${index + 8} 磅` }))} />
        </label>
        <label className="col-span-2 flex items-center gap-2">打印缩放 <SelectField ariaLabel="打印缩放" className="h-8 w-auto min-w-[9rem]"
          value={exportOptions.printFit} onValueChange={(value) => setExportOptions({ ...exportOptions, printFit: value as ExportOptions['printFit'] })}
          options={[{ value: 'original', label: 'Excel 默认' }, { value: 'width', label: '一页宽' }, { value: 'page', label: '缩放至一页' }]} />
        </label>
        <label className="inline-flex items-center gap-2"><Checkbox disabled={exportOptions.printFit === 'original'} checked={exportOptions.landscape}
          onCheckedChange={(checked) => setExportOptions({ ...exportOptions, landscape: checked === true })} />A4 横向</label>
      </div>
      {error && <p className="schedule-error" role="alert">{error}</p>}
    </ModalFrame>}
  </div>;
}
