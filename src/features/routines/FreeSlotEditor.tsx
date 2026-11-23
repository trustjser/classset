import { useEffect, useMemo, useRef, useState } from 'react';
import type { PointerEvent } from 'react';
import { createPortal } from 'react-dom';
import {
  Check,
  ChevronDown,
  ChevronRight,
  GripVertical,
  MoreHorizontal,
  Plus,
  RotateCcw,
  Trash2,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import type {
  ClassGroup,
  CommonPeriod,
  FreeSlot,
  GradeGroup,
  LessonPeriodType,
  SchoolStage,
  ScopeType,
  StageRoutine,
} from '@/domain/models';
import { getPeriodAccentColor, WEEKDAY_SHORT_NAMES } from '@/domain/routineUtils';
import { useAppStore } from '@/store/useAppStore';

const FREE_SLOT_LABELS = [
  '不上课',
  '无课',
  '自习',
  '课后服务',
  '劳动',
  '教研活动',
  '党团活动',
] as const;

export interface FreeSlotScopeSelection {
  scopeType: Exclude<ScopeType, 'school'>;
  scopeId: string;
  stageId: string;
  parentGradeId: string | null;
}

interface FreeSlotEditorProps {
  termId: string;
  stages: SchoolStage[];
  grades: GradeGroup[];
  classes: ClassGroup[];
  routinesByStage: Record<string, StageRoutine>;
  routineDraftsByStage: Record<string, StageRoutine>;
  routine: StageRoutine;
  scope: FreeSlotScopeSelection;
  runHistory: (label: string, action: () => void) => void;
  onUpdateRoutine: (
    updater: (current: StageRoutine) => StageRoutine,
    historyLabel?: string
  ) => void;
  className?: string;
}

interface GridCell {
  period: LessonPeriodType;
  weekday: number;
  lessonIndex: number;
}

type RoutineMatrixRow =
  | {
      type: 'lesson';
      period: LessonPeriodType;
      lessonIndex: number;
      dayLessonNumber: number;
      periodIndex: number;
    }
  | { type: 'common'; commonPeriod: CommonPeriod };

interface MatrixPoint {
  row: number;
  col: number;
}

interface CommonDropTarget {
  kind: 'first' | 'lesson' | 'common';
  id: string | null;
  edge: 'before' | 'after';
}

function CommonPeriodMatrixRow({
  period,
  dayCount,
  insertionEdge,
  onPointerDown,
}: {
  period: CommonPeriod;
  dayCount: number;
  insertionEdge: CommonDropTarget['edge'] | null;
  onPointerDown: (event: PointerEvent<HTMLButtonElement>, period: CommonPeriod) => void;
}) {
  return (
    <tr
      data-common-drop-anchor={period.insertAfterLessonId ?? '__first__'}
      data-common-drop-period={period.id}
      className="border-b border-table-divider bg-warning-surface/70"
    >
      <th className={'sticky left-0 z-[1] min-w-[108px] border-b border-table-divider bg-warning-surface px-2 py-1.5 text-left text-[10.5px] font-semibold text-warning ' + (insertionEdge === 'before' ? 'border-t-2 border-t-primary' : insertionEdge === 'after' ? 'border-b-2 border-b-primary' : '')}>
        <div className="flex items-center gap-1.5">
          <button
            aria-label={`拖动调整公共时段「${period.name}」的位置`}
            className="flex h-6 w-5 shrink-0 cursor-grab touch-none items-center justify-center rounded text-ink-secondary hover:bg-surface active:cursor-grabbing"
            onPointerDown={(event) => onPointerDown(event, period)}
            title="拖动调整顺序"
            type="button"
          >
            <GripVertical aria-hidden="true" className="h-3.5 w-3.5" />
          </button>
          <span className="whitespace-nowrap">公共时段</span>
        </div>
      </th>
      <td className={'border-b border-l border-table-divider px-2 py-1.5 ' + (insertionEdge === 'before' ? 'border-t-2 border-t-primary' : insertionEdge === 'after' ? 'border-b-2 border-b-primary' : '')} colSpan={dayCount}>
        <div className="flex min-h-6 items-center px-1 text-[11.5px] font-medium text-warning">
          {period.name}
        </div>
      </td>
    </tr>
  );
}

function slotIdentity(
  stageId: string,
  periodTypeId: string,
  weekday: number,
  lessonIndex: number,
  scopeType: FreeSlotScopeSelection['scopeType'],
  scopeId: string
): string {
  const base = stageId + '_free_' + periodTypeId + '_' + weekday + '_' + lessonIndex;
  return base + '_' + scopeType + '_' + scopeId;
}

function scopePriority(
  slot: FreeSlot,
  scope: FreeSlotScopeSelection,
  termId: string
): number {
  if (
    slot.scopeType === scope.scopeType &&
    slot.scopeId === scope.scopeId
  ) {
    return 4;
  }
  if (
    scope.scopeType === 'class' &&
    slot.scopeType === 'grade' &&
    slot.scopeId === scope.parentGradeId
  ) {
    return 3;
  }
  if (
    slot.scopeType === 'stage' &&
    slot.scopeId === scope.stageId
  ) {
    return 2;
  }
  if (
    slot.scopeType === 'school' &&
    slot.scopeId === termId
  ) {
    return 1;
  }
  return -1;
}

function getSlotScopeName(
  slot: FreeSlot,
  stages: SchoolStage[],
  grades: GradeGroup[],
  classes: ClassGroup[]
): string {
  if (slot.scopeType === 'school') return '全校';
  if (slot.scopeType === 'stage') {
    return stages.find((stage) => stage.id === slot.scopeId)?.name ?? '学段';
  }
  if (slot.scopeType === 'grade') {
    return grades.find((grade) => grade.id === slot.scopeId)?.name ?? '年级';
  }
  return classes.find((group) => group.id === slot.scopeId)?.name ?? '班级';
}

export function FreeSlotEditor({
  termId,
  stages,
  grades,
  classes,
  routinesByStage,
  routineDraftsByStage,
  routine,
  scope,
  runHistory,
  onUpdateRoutine,
  className = '',
}: FreeSlotEditorProps) {
  const freeSlotsByStage = useAppStore((state) => state.freeSlotsByStage);
  const freeSlotDraftsByTerm = useAppStore(
    (state) => state.freeSlotDraftsByTerm
  );
  const loadFreeSlotsForStages = useAppStore(
    (state) => state.loadFreeSlotsForStages
  );
  const setFreeSlotDraft = useAppStore((state) => state.setFreeSlotDraft);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [openMenuKey, setOpenMenuKey] = useState<string | null>(null);
  const [customCell, setCustomCell] = useState<{
    cells: GridCell[];
    scope: FreeSlotScopeSelection;
  } | null>(null);
  const [contextTarget, setContextTarget] = useState<{
    cells: GridCell[];
    scope: FreeSlotScopeSelection;
  } | null>(null);
  const [contextMenuCell, setContextMenuCell] = useState<GridCell | null>(null);
  const [contextMenuPosition, setContextMenuPosition] = useState<{ x: number; y: number } | null>(null);
  const [customLabel, setCustomLabel] = useState('');
  const [selectedRange, setSelectedRange] = useState<{ start: MatrixPoint; end: MatrixPoint } | null>(null);
  const [selectionPreview, setSelectionPreview] = useState<{ start: MatrixPoint; end: MatrixPoint } | null>(null);
  const selectionStartRef = useRef<MatrixPoint | null>(null);
  const selectionEndRef = useRef<MatrixPoint | null>(null);
  const selectionMovedRef = useRef(false);
  const suppressNextClickRef = useRef(false);
  const commonDragRef = useRef<{ id: string; pointerId: number } | null>(null);
  const [dropTarget, setDropTarget] = useState<CommonDropTarget | null>(null);
  const [addCommonPeriodOpen, setAddCommonPeriodOpen] = useState(false);
  const [newCommonPeriodName, setNewCommonPeriodName] = useState('');
  const [newCommonPeriodAnchor, setNewCommonPeriodAnchor] = useState('__first__');

  useEffect(() => {
    let active = true;
    if (!stages.length) {
      setLoading(false);
      return () => {
        active = false;
      };
    }
    setLoading(true);
    setLoadError(null);
    void loadFreeSlotsForStages(stages.map((stage) => stage.id))
      .then(() => {
        if (active) setLoading(false);
      })
      .catch((error) => {
        if (!active) return;
        setLoadError(error instanceof Error ? error.message : '读取免任课设置失败。');
        setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [loadFreeSlotsForStages, stages]);

  const termDrafts = freeSlotDraftsByTerm[termId] ?? {};
  const allSlots = useMemo(() => {
    const byId = new Map<string, FreeSlot>();
    for (const stage of stages) {
      for (const slot of freeSlotsByStage[stage.id] ?? []) byId.set(slot.id, slot);
    }
    for (const [slotId, slot] of Object.entries(termDrafts)) {
      if (slot) byId.set(slotId, slot);
      else byId.delete(slotId);
    }
    return [...byId.values()];
  }, [freeSlotsByStage, stages, termDrafts]);

  const teachingDays = routine.teachingDays
    .filter((day) => day.isTeachingDay)
    .map((day) => day.weekday)
    .sort((a, b) => a - b);
  const sortedPeriods = routine.periodTypes
    .slice()
    .sort((a, b) => a.sortOrder - b.sortOrder);
  let dayLessonCursor = 0;
  const lessonRows = sortedPeriods.flatMap((period, periodIndex) =>
    Array.from({ length: period.defaultLessonCount }, (_, index) => {
      dayLessonCursor += 1;
      return {
        period,
        lessonIndex: index + 1,
        dayLessonNumber: dayLessonCursor,
        periodIndex,
      };
    })
  );
  const commonPeriods = (routine.commonPeriods ?? [])
    .filter((period) => period.stageId === routine.stageId)
    .slice()
    .sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name));
  const matrixRows: RoutineMatrixRow[] = [];
  const insertedCommonPeriodIds = new Set<string>();
  for (const period of commonPeriods.filter((item) => item.insertAfterLessonId === null)) {
    matrixRows.push({ type: 'common', commonPeriod: period });
    insertedCommonPeriodIds.add(period.id);
  }
  for (const row of lessonRows) {
    matrixRows.push({
      type: 'lesson',
      period: row.period,
      lessonIndex: row.lessonIndex,
      dayLessonNumber: row.dayLessonNumber,
      periodIndex: row.periodIndex,
    });
    const lessonId = `${row.period.id}_${row.lessonIndex}`;
    for (const period of commonPeriods.filter((item) => item.insertAfterLessonId === lessonId)) {
      matrixRows.push({ type: 'common', commonPeriod: period });
      insertedCommonPeriodIds.add(period.id);
    }
  }
  for (const period of commonPeriods) {
    if (!insertedCommonPeriodIds.has(period.id)) {
      matrixRows.push({ type: 'common', commonPeriod: period });
    }
  }

  const pointInsideRange = (
    point: MatrixPoint,
    range: { start: MatrixPoint; end: MatrixPoint }
  ) => point.row >= Math.min(range.start.row, range.end.row) &&
    point.row <= Math.max(range.start.row, range.end.row) &&
    point.col >= Math.min(range.start.col, range.end.col) &&
    point.col <= Math.max(range.start.col, range.end.col);

  const cellsInRange = (range: { start: MatrixPoint; end: MatrixPoint }): GridCell[] => {
    const cells: GridCell[] = [];
    for (
      let rowIndex = Math.min(range.start.row, range.end.row);
      rowIndex <= Math.max(range.start.row, range.end.row);
      rowIndex++
    ) {
      const row = matrixRows[rowIndex];
      if (!row || row.type !== 'lesson') continue;
      for (
        let colIndex = Math.min(range.start.col, range.end.col);
        colIndex <= Math.max(range.start.col, range.end.col);
        colIndex++
      ) {
        const weekday = teachingDays[colIndex];
        if (weekday) cells.push({ period: row.period, weekday, lessonIndex: row.lessonIndex });
      }
    }
    return cells;
  };

  const contextCellsFor = (point: MatrixPoint, cell: GridCell): GridCell[] =>
    selectedRange && pointInsideRange(point, selectedRange)
      ? cellsInRange(selectedRange)
      : [cell];

  const directSlotFor = (
    cell: GridCell,
    selectedScope: FreeSlotScopeSelection
  ): FreeSlot | undefined =>
    allSlots.find(
      (slot) =>
        slot.stageId === selectedScope.stageId &&
        slot.scopeType === selectedScope.scopeType &&
        slot.scopeId === selectedScope.scopeId &&
        slot.periodTypeId === cell.period.id &&
        slot.weekday === cell.weekday &&
        slot.lessonIndex === cell.lessonIndex
    );

  const markerFor = (cell: GridCell): FreeSlot | undefined => {
    let best: FreeSlot | undefined;
    let bestPriority = -1;
    for (const slot of allSlots) {
      if (
        slot.stageId !== scope.stageId ||
        slot.periodTypeId !== cell.period.id ||
        slot.weekday !== cell.weekday ||
        slot.lessonIndex !== cell.lessonIndex
      ) {
        continue;
      }
      const priority = scopePriority(slot, scope, termId);
      if (priority > bestPriority) {
        best = slot;
        bestPriority = priority;
      }
    }
    return best;
  };

  const stageSlotRoutine = (stage: SchoolStage): StageRoutine | undefined =>
    stage.id === routine.stageId
      ? routine
      : routineDraftsByStage[stage.id] ?? routinesByStage[stage.id];

  const applyLabel = (
    cell: GridCell,
    selectedScope: FreeSlotScopeSelection,
    label: string
  ) => {
    const targets = stages.filter((stage) => stage.id === selectedScope.stageId);
    for (const stage of targets) {
      const targetRoutine = stageSlotRoutine(stage);
      if (!targetRoutine?.periodTypes.length) continue;
      const targetPeriod = targetRoutine.periodTypes.find(
        (period) => period.name === cell.period.name
      );
      if (!targetPeriod) continue;
      const day = targetRoutine.teachingDays.find(
        (item) => item.weekday === cell.weekday
      );
      if (
        !day?.isTeachingDay ||
        cell.lessonIndex > targetPeriod.defaultLessonCount
      ) continue;
      const scopeId = selectedScope.scopeId;
      const existing = allSlots.find(
        (slot) =>
          slot.stageId === stage.id &&
          slot.scopeType === selectedScope.scopeType &&
          slot.scopeId === scopeId &&
          slot.periodTypeId === targetPeriod.id &&
          slot.weekday === cell.weekday &&
          slot.lessonIndex === cell.lessonIndex
      );
      const id =
        existing?.id ??
        slotIdentity(
          stage.id,
          targetPeriod.id,
          cell.weekday,
          cell.lessonIndex,
          selectedScope.scopeType,
          scopeId
        );
      setFreeSlotDraft(termId, id, {
        id,
        scopeType: selectedScope.scopeType,
        scopeId,
        stageId: stage.id,
        periodTypeId: targetPeriod.id,
        weekday: cell.weekday,
        lessonIndex: cell.lessonIndex,
        label,
      });
    }
  };

  const clearDirectMarker = (
    cell: GridCell,
    selectedScope: FreeSlotScopeSelection
  ) => {
    const direct = directSlotFor(cell, selectedScope);
    if (direct) setFreeSlotDraft(termId, direct.id, null);
  };

  const toggleCell = (cell: GridCell) => {
    const direct = directSlotFor(cell, scope);
    if (direct) clearDirectMarker(cell, scope);
    else applyLabel(cell, scope, '无课');
  };

  const closeContextMenu = () => {
    setOpenMenuKey(null);
    setContextTarget(null);
    setContextMenuCell(null);
    setContextMenuPosition(null);
  };

  const menuPositionFor = (x: number, y: number) => {
    const maxMenuHeight = Math.min(360, window.innerHeight - 16);
    return {
      x: Math.max(8, Math.min(x, window.innerWidth - 200)),
      y: Math.max(8, Math.min(y, window.innerHeight - maxMenuHeight - 8)),
    };
  };

  const openCellContextMenu = (
    key: string,
    cell: GridCell,
    cells: GridCell[],
    selectedScope: FreeSlotScopeSelection,
    x: number,
    y: number
  ) => {
    setContextTarget({ cells, scope: selectedScope });
    setContextMenuCell(cell);
    setContextMenuPosition(menuPositionFor(x, y));
    setOpenMenuKey(key);
  };

  const selectPreset = (cell: GridCell, label: string) => {
    const target = contextTarget ?? { cells: [cell], scope };
    runHistory(`设置免任课「${label}」`, () => {
      for (const targetCell of target.cells) {
        const direct = directSlotFor(targetCell, target.scope);
        if (target.cells.length === 1 && direct?.label === label) {
          clearDirectMarker(targetCell, target.scope);
        } else {
          applyLabel(targetCell, target.scope, label);
        }
      }
    });
    setSelectedRange(null);
    closeContextMenu();
  };

  const moveCommonPeriod = (
    periodId: string,
    anchor: string | null,
    placement: { beforeId?: string; afterId?: string } = {}
  ) => {
    onUpdateRoutine((current) => {
      const all = current.commonPeriods ?? [];
      const moving = all.find((period) => period.id === periodId);
      if (!moving) return current;
      const group = all
        .filter((period) => period.id !== periodId && period.insertAfterLessonId === anchor)
        .slice()
        .sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name));
      const beforeIndex = placement.beforeId
        ? group.findIndex((period) => period.id === placement.beforeId)
        : -1;
      const afterIndex = placement.afterId
        ? group.findIndex((period) => period.id === placement.afterId)
        : -1;
      const index = beforeIndex >= 0
        ? beforeIndex
        : afterIndex >= 0
          ? afterIndex + 1
          : group.length;
      group.splice(index, 0, { ...moving, insertAfterLessonId: anchor });
      const ordered = new Map(
        group.map((period, sortOrder) => [period.id, { ...period, sortOrder }])
      );
      return {
        ...current,
        commonPeriods: all.map((period) => ordered.get(period.id) ?? period),
      };
    }, `移动公共时段「${commonPeriods.find((period) => period.id === periodId)?.name ?? ''}」`);
  };

  const beginAddCommonPeriod = (afterLessonId: string | null = null) => {
    setNewCommonPeriodName('');
    setNewCommonPeriodAnchor(afterLessonId ?? '__first__');
    setAddCommonPeriodOpen(true);
  };

  const addCommonPeriod = () => {
    const name = newCommonPeriodName.trim();
    if (!name) return;
    const insertAfterLessonId = newCommonPeriodAnchor === '__first__'
      ? null
      : newCommonPeriodAnchor;
    const existing = commonPeriods.filter(
      (period) => period.insertAfterLessonId === insertAfterLessonId
    );
    const id = globalThis.crypto?.randomUUID?.() ?? `cp_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    onUpdateRoutine((current) => ({
      ...current,
      commonPeriods: [
        ...(current.commonPeriods ?? []),
        {
          id,
          stageId: current.stageId,
          name,
          insertAfterLessonId,
          durationMinutes: 10,
          sortOrder: existing.length,
          startMinute: null,
          endMinute: null,
        },
      ],
    }), `新增公共时段「${name}」`);
    setAddCommonPeriodOpen(false);
  };

  const startCommonPeriodDrag = (
    event: PointerEvent<HTMLButtonElement>,
    period: CommonPeriod
  ) => {
    if (event.button !== 0) return;
    event.preventDefault();
    selectionStartRef.current = null;
    selectionEndRef.current = null;
    setSelectionPreview(null);
    commonDragRef.current = { id: period.id, pointerId: event.pointerId };
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const dropTargetAt = (clientX: number, clientY: number) =>
    document
      .elementFromPoint(clientX, clientY)
      ?.closest<HTMLElement>('[data-common-drop-anchor]') ?? null;

  const updateCommonDropPreview = (event: PointerEvent<HTMLDivElement>) => {
    const target = dropTargetAt(event.clientX, event.clientY);
    if (!target) {
      setDropTarget(null);
      return;
    }
    const periodId = target.dataset.commonDropPeriod;
    const anchor = target.dataset.commonDropAnchor;
    if (periodId) {
      const bounds = target.getBoundingClientRect();
      setDropTarget({
        kind: 'common',
        id: periodId,
        edge: event.clientY < bounds.top + bounds.height / 2 ? 'before' : 'after',
      });
      return;
    }
    if (!anchor) {
      setDropTarget(null);
      return;
    }
    setDropTarget(
      anchor === '__first__'
        ? { kind: 'first', id: null, edge: 'after' }
        : { kind: 'lesson', id: anchor, edge: 'after' }
    );
  };

  const finishCommonPeriodDrag = (event: PointerEvent<HTMLDivElement>) => {
    const drag = commonDragRef.current;
    if (!drag) return false;
    const target = dropTargetAt(event.clientX, event.clientY);
    const targetPeriodId = target?.dataset.commonDropPeriod;
    const anchorValue = target?.dataset.commonDropAnchor;
    const anchor = anchorValue && anchorValue !== '__first__' ? anchorValue : null;
    if (target && targetPeriodId !== drag.id) {
      if (targetPeriodId) {
        const bounds = target.getBoundingClientRect();
        const before = event.clientY < bounds.top + bounds.height / 2;
        moveCommonPeriod(
          drag.id,
          anchor,
          before ? { beforeId: targetPeriodId } : { afterId: targetPeriodId }
        );
      } else {
        moveCommonPeriod(drag.id, anchor);
      }
    }
    commonDragRef.current = null;
    setDropTarget(null);
    return true;
  };

  const pointFromElement = (element: Element | null): MatrixPoint | null => {
    const cell = element?.closest<HTMLElement>('[data-matrix-cell="true"]');
    if (!cell) return null;
    const row = Number(cell.dataset.rowIndex);
    const col = Number(cell.dataset.colIndex);
    return Number.isInteger(row) && Number.isInteger(col) ? { row, col } : null;
  };

  const beginSelection = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0 || event.pointerType === 'touch') return;
    const point = pointFromElement(event.target instanceof Element ? event.target : null);
    if (!point) return;
    suppressNextClickRef.current = false;
    selectionMovedRef.current = false;
    selectionStartRef.current = point;
    selectionEndRef.current = point;
    setSelectionPreview({ start: point, end: point });
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const continueSelection = (event: PointerEvent<HTMLDivElement>) => {
    if (commonDragRef.current) {
      if (event.pointerId !== commonDragRef.current.pointerId) return;
      updateCommonDropPreview(event);
      return;
    }
    const start = selectionStartRef.current;
    if (!start) return;
    const point = pointFromElement(document.elementFromPoint(event.clientX, event.clientY));
    if (!point) return;
    if (point.row !== start.row || point.col !== start.col) selectionMovedRef.current = true;
    selectionEndRef.current = point;
    setSelectionPreview({ start, end: point });
  };

  const finishSelection = (event: PointerEvent<HTMLDivElement>) => {
    if (commonDragRef.current && event.pointerId !== commonDragRef.current.pointerId) return;
    if (finishCommonPeriodDrag(event)) return;
    const start = selectionStartRef.current;
    if (!start) return;
    const end = pointFromElement(document.elementFromPoint(event.clientX, event.clientY)) ??
      selectionEndRef.current ?? start;
    if (selectionMovedRef.current) {
      setSelectedRange({ start, end });
      suppressNextClickRef.current = true;
      window.setTimeout(() => {
        suppressNextClickRef.current = false;
      }, 0);
    } else {
      setSelectedRange(null);
    }
    selectionStartRef.current = null;
    selectionEndRef.current = null;
    setSelectionPreview(null);
  };

  const cancelSelection = () => {
    commonDragRef.current = null;
    setDropTarget(null);
    selectionStartRef.current = null;
    selectionEndRef.current = null;
    selectionMovedRef.current = false;
    setSelectionPreview(null);
  };

  const isInSelectionRange = (row: number, col: number): boolean => {
    const range = selectionPreview ?? selectedRange;
    return Boolean(range && pointInsideRange({ row, col }, range));
  };

  const isDirectMarker = (
    cell: GridCell,
    selectedScope: FreeSlotScopeSelection
  ) => Boolean(directSlotFor(cell, selectedScope));

  const sortedSummarySlots = allSlots.slice().sort((a, b) => {
    const stageOrder =
      (stages.find((stage) => stage.id === a.stageId)?.sortOrder ?? 0) -
      (stages.find((stage) => stage.id === b.stageId)?.sortOrder ?? 0);
    return (
      stageOrder ||
      a.weekday - b.weekday ||
      a.periodTypeId.localeCompare(b.periodTypeId) ||
      a.lessonIndex - b.lessonIndex
    );
  });
  const contextMenuMarker = contextMenuCell ? markerFor(contextMenuCell) : undefined;
  const contextMenuHasDirectMarker = Boolean(
    contextTarget?.cells.some((cell) => directSlotFor(cell, contextTarget.scope))
  );
  const contextMenuLessonId = contextMenuCell
    ? `${contextMenuCell.period.id}_${contextMenuCell.lessonIndex}`
    : null;

  return (
    <>
      <Card className={'min-w-0 p-4 sm:p-5 ' + className}>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <h2 className="text-[15px] font-semibold text-ink">免任课与公共时段</h2>
          </div>
          <Badge variant="secondary">{allSlots.length}</Badge>
        </div>

        <div className="mt-4 min-w-0">
            {loading ? (
              <div className="flex min-h-44 items-center justify-center rounded-control border border-border bg-table-header text-[12px] text-ink-secondary">
                正在读取免任课…
              </div>
            ) : loadError ? (
              <div className="flex min-h-44 flex-col items-center justify-center gap-2 rounded-control border border-destructive/20 bg-destructive-surface p-4 text-center">
                <p className="text-[12px] text-destructive">{loadError}</p>
                <Button
                  className="h-8"
                  onClick={() => {
                    setLoadError(null);
                    setLoading(true);
                    void loadFreeSlotsForStages(stages.map((stage) => stage.id))
                      .then(() => setLoading(false))
                      .catch((error) => {
                        setLoadError(
                          error instanceof Error ? error.message : '读取免任课设置失败。'
                        );
                        setLoading(false);
                      });
                  }}
                  type="button"
                  variant="outline"
                >
                  重新读取
                </Button>
              </div>
            ) : teachingDays.length === 0 ? (
              <div className="flex min-h-44 items-center justify-center rounded-control border border-dashed border-border px-4 text-center text-[12px] leading-5 text-ink-secondary">
                先在左侧选择上课日，免任课矩阵会显示对应星期。
              </div>
            ) : lessonRows.length === 0 && commonPeriods.length === 0 ? (
              <div className="flex min-h-44 items-center justify-center rounded-control border border-dashed border-border px-4 text-center text-[12px] leading-5 text-ink-secondary">
                当前学段尚未设置节数；设置各时段节数后，这里会显示免任课格子。
              </div>
            ) : (
              <div
                className="max-w-full overflow-x-auto overscroll-x-contain rounded-control border border-border"
                onPointerCancel={cancelSelection}
                onPointerDown={beginSelection}
                onPointerMove={continueSelection}
                onPointerUp={finishSelection}
              >
                <table className="w-full border-collapse text-left">
                  <thead className="bg-table-header text-[11.5px] font-medium text-ink-secondary">
                    <tr
                      data-common-drop-anchor="__first__"
                    >
                      <th className={'sticky left-0 z-[1] w-[74px] border-b border-table-divider bg-table-header px-2.5 py-2.5 font-medium ' + (dropTarget?.kind === 'first' ? 'border-b-2 border-b-primary' : '')}>
                        节次
                      </th>
                      {teachingDays.map((weekday) => (
                        <th className={'min-w-[54px] border-b border-l border-table-divider px-1.5 py-2.5 text-center font-medium ' + (dropTarget?.kind === 'first' ? 'border-b-2 border-b-primary' : '')} key={weekday}>
                          周{WEEKDAY_SHORT_NAMES[weekday - 1]}
                        </th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-table-divider">
                    {matrixRows.map((row, rowIndex) => {
                      if (row.type === 'common') {
                        return (
                          <CommonPeriodMatrixRow
                            dayCount={teachingDays.length}
                            insertionEdge={dropTarget?.kind === 'common' && dropTarget.id === row.commonPeriod.id ? dropTarget.edge : null}
                            key={`common:${row.commonPeriod.id}`}
                            onPointerDown={startCommonPeriodDrag}
                            period={row.commonPeriod}
                          />
                        );
                      }

                      const { period, lessonIndex, dayLessonNumber, periodIndex } = row;
                      const periodAccent = getPeriodAccentColor(period.name, periodIndex);
                      const lessonId = `${period.id}_${lessonIndex}`;
                      const showLessonDropLine = dropTarget?.kind === 'lesson' && dropTarget.id === lessonId;
                      return (
                        <tr
                          data-common-drop-anchor={lessonId}
                          key={period.id + ':' + lessonIndex}
                        >
                          <th
                            className={'sticky left-0 z-[1] whitespace-nowrap border-b border-table-divider bg-surface px-3 py-2 text-[11.5px] font-semibold tabular-nums ' + (showLessonDropLine ? 'border-b-2 border-b-primary' : '')}
                            style={{ color: periodAccent }}
                            title={`${period.name} 第${lessonIndex}节`}
                          >
                            第{dayLessonNumber}节
                          </th>
                          {teachingDays.map((weekday, colIndex) => {
                            const cell: GridCell = { period, weekday, lessonIndex };
                            const marker = markerFor(cell);
                            const direct = isDirectMarker(cell, scope);
                            const cellKey = period.id + ':' + weekday + ':' + lessonIndex;
                            const menuOpen = openMenuKey === cellKey;
                            const matrixPoint = { row: rowIndex, col: colIndex };
                            return (
                              <td className={'border-b border-l border-table-divider p-1 ' + (showLessonDropLine ? 'border-b-2 border-b-primary' : '')} key={weekday}>
                                <div
                                  className="group relative h-10"
                                  onContextMenu={(event) => {
                                    event.preventDefault();
                                    openCellContextMenu(
                                      cellKey,
                                      cell,
                                      contextCellsFor(matrixPoint, cell),
                                      scope,
                                      event.clientX,
                                      event.clientY
                                    );
                                  }}
                                >
                                  <button
                                    aria-label={
                                      '周' + WEEKDAY_SHORT_NAMES[weekday - 1] + ' ' + period.name + '第' + lessonIndex + '节 ' +
                                      (marker?.label ? marker.label + (direct ? '，当前范围' : '，继承') : '设为无课')
                                    }
                                    className={
                                      'flex h-10 w-full items-center justify-center rounded-md border px-2 text-center text-[10px] font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ' +
                                      (isInSelectionRange(rowIndex, colIndex)
                                        ? 'border-primary bg-selection text-primary ring-1 ring-primary'
                                        : marker
                                          ? marker.label === '不上课'
                                            ? 'border-border bg-table-header text-ink-secondary hover:border-control-border hover:bg-selection'
                                            : 'border-table-divider bg-destructive-surface text-destructive hover:border-destructive hover:brightness-95'
                                          : 'border-border bg-surface text-ink hover:border-primary hover:bg-selection')
                                    }
                                    data-col-index={colIndex}
                                    data-matrix-cell="true"
                                    data-row-index={rowIndex}
                                    onClick={() => {
                                      if (suppressNextClickRef.current) {
                                        suppressNextClickRef.current = false;
                                        return;
                                      }
                                      runHistory('修改免任课格子', () => toggleCell(cell));
                                      setSelectedRange(null);
                                    }}
                                    type="button"
                                  >
                                    {marker?.label ?? ''}
                                    {marker && !direct && (
                                      <span className="ml-1 text-[9px] font-normal opacity-70">继承</span>
                                    )}
                                  </button>
                                  <button
                                    aria-label="更多免任课设置"
                                    className="absolute right-0.5 top-0.5 flex h-6 w-6 items-center justify-center rounded bg-surface/95 text-ink-secondary opacity-60 shadow-sm transition-opacity hover:text-ink focus-visible:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:opacity-0 sm:group-hover:opacity-100"
                                    onClick={(event) => {
                                      if (menuOpen) {
                                        closeContextMenu();
                                      } else {
                                        const bounds = event.currentTarget.getBoundingClientRect();
                                        openCellContextMenu(
                                          cellKey,
                                          cell,
                                          contextCellsFor(matrixPoint, cell),
                                          scope,
                                          bounds.left,
                                          bounds.bottom + 4
                                        );
                                      }
                                    }}
                                    type="button"
                                  >
                                    <MoreHorizontal aria-hidden="true" className="h-3.5 w-3.5" />
                                  </button>
                                </div>
                              </td>
                            );
                          })}
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
        </div>

        <div className="mt-4 border-t border-table-divider pt-4">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h3 className="text-[12.5px] font-semibold text-ink">本学期免任课</h3>
              <p className="mt-0.5 text-[11px] text-ink-secondary">
                学段、年级与班级的标记会按范围继承，并可在此统一清理。
              </p>
            </div>
            <Badge variant="secondary">{allSlots.length}</Badge>
          </div>
          {sortedSummarySlots.length === 0 ? (
            <p className="mt-3 rounded-control bg-table-header px-3 py-3 text-[11.5px] text-ink-secondary">
              暂无免任课标记
            </p>
          ) : (
            <ul className="mt-3 max-h-52 divide-y divide-table-divider overflow-y-auto rounded-control border border-border">
              {sortedSummarySlots.map((slot) => {
                const stage = stages.find((item) => item.id === slot.stageId);
                const slotRoutine = stage ? stageSlotRoutine(stage) : undefined;
                const periodName =
                  slotRoutine?.periodTypes.find(
                    (period) => period.id === slot.periodTypeId
                  )?.name ?? '时段';
                return (
                  <li
                    className="flex min-w-0 items-center gap-2 px-3 py-2"
                    key={slot.id}
                  >
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[11.5px] font-medium text-ink">
                        {stage?.name ?? '学段'} · {getSlotScopeName(slot, stages, grades, classes)}
                      </p>
                      <p className="truncate text-[10.5px] text-ink-secondary">
                        周{WEEKDAY_SHORT_NAMES[slot.weekday - 1]} · {periodName}第{slot.lessonIndex}节
                      </p>
                    </div>
                    <Badge variant="outline">{slot.label}</Badge>
                    <button
                      aria-label={'删除 ' + slot.label + ' 标记'}
                      className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-ink-secondary transition-colors hover:bg-destructive-surface hover:text-destructive focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      onClick={() => runHistory('删除免任课标记', () => setFreeSlotDraft(termId, slot.id, null))}
                      type="button"
                    >
                      <Trash2 aria-hidden="true" className="h-3.5 w-3.5" />
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </Card>

      {openMenuKey && contextTarget && contextMenuCell && contextMenuPosition && createPortal(
        <>
          <button
            aria-label="关闭免任课菜单"
            className="fixed inset-0 z-[99] cursor-default bg-transparent"
            onClick={closeContextMenu}
            type="button"
          />
          <div
            className="fixed z-[100] max-h-[calc(100vh-1rem)] w-48 max-w-[calc(100vw-1rem)] overflow-y-auto rounded-control border border-border bg-surface p-1.5 shadow-popover"
            onKeyDown={(event) => {
              if (event.key === 'Escape') closeContextMenu();
            }}
            role="menu"
            style={{ left: contextMenuPosition.x, top: contextMenuPosition.y }}
          >
            {contextTarget.cells.length > 1 && (
              <div className="px-2.5 py-1 text-[10.5px] text-ink-secondary">
                统一设置 {contextTarget.cells.length} 个格子
              </div>
            )}
            {FREE_SLOT_LABELS.map((label) => (
              <button
                className="flex w-full items-center justify-between rounded-md px-2.5 py-1.5 text-left text-[11.5px] text-ink transition-colors hover:bg-table-header focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                key={label}
                onClick={() => selectPreset(contextMenuCell, label)}
                role="menuitem"
                type="button"
              >
                {label}
                {contextMenuMarker?.label === label && <Check aria-hidden="true" className="h-3.5 w-3.5 text-primary" />}
              </button>
            ))}
            <div className="my-1 border-t border-table-divider" />
            <button
              className="w-full rounded-md px-2.5 py-1.5 text-left text-[11.5px] text-primary transition-colors hover:bg-selection focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              onClick={() => {
                setCustomCell(contextTarget);
                setCustomLabel(contextMenuMarker?.label ?? '');
                closeContextMenu();
              }}
              role="menuitem"
              type="button"
            >
              自定义名称…
            </button>
            <button
              className="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-[11.5px] text-warning transition-colors hover:bg-warning-surface focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              onClick={() => {
                if (contextMenuLessonId) beginAddCommonPeriod(contextMenuLessonId);
                closeContextMenu();
              }}
              role="menuitem"
              type="button"
            >
              <Plus aria-hidden="true" className="h-3.5 w-3.5" />
              添加公共时段
            </button>
            {contextMenuHasDirectMarker && (
              <button
                className="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-[11.5px] text-ink-secondary transition-colors hover:bg-table-header focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                onClick={() => {
                  runHistory('恢复上级免任课设置', () => {
                    contextTarget.cells.forEach((targetCell) =>
                      clearDirectMarker(targetCell, contextTarget.scope)
                    );
                  });
                  setSelectedRange(null);
                  closeContextMenu();
                }}
                role="menuitem"
                type="button"
              >
                <RotateCcw aria-hidden="true" className="h-3 w-3" />
                恢复上级设置
              </button>
            )}
          </div>
        </>,
        document.body
      )}

      <Dialog
        open={Boolean(customCell)}
        onOpenChange={(open) => {
          if (!open) setCustomCell(null);
        }}
      >
        <DialogContent className="sm:max-w-[400px]">
          <DialogHeader>
            <DialogTitle>自定义免任课名称</DialogTitle>
            <DialogDescription>
              输入显示在课表里的文字，限制为 20 个字符。
            </DialogDescription>
          </DialogHeader>
          <Input
            autoFocus
            maxLength={20}
            onChange={(event) => setCustomLabel(event.currentTarget.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && customLabel.trim() && customCell) {
                runHistory('设置自定义免任课', () => {
                  customCell.cells.forEach((cell) =>
                    applyLabel(cell, customCell.scope, customLabel.trim())
                  );
                });
                setSelectedRange(null);
                setCustomCell(null);
              }
            }}
            placeholder="例如：社团活动"
            value={customLabel}
          />
          <DialogFooter>
            <Button
              onClick={() => setCustomCell(null)}
              type="button"
              variant="outline"
            >
              取消
            </Button>
            <Button
              disabled={!customLabel.trim()}
              onClick={() => {
                if (!customCell) return;
                runHistory('设置自定义免任课', () => {
                  customCell.cells.forEach((cell) =>
                    applyLabel(cell, customCell.scope, customLabel.trim())
                  );
                });
                setSelectedRange(null);
                setCustomCell(null);
              }}
              type="button"
            >
              应用
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={addCommonPeriodOpen}
        onOpenChange={setAddCommonPeriodOpen}
      >
        <DialogContent className="sm:max-w-[420px]">
          <DialogHeader>
            <DialogTitle>添加公共时段</DialogTitle>
            <DialogDescription>
              公共时段会作为整行显示在作息矩阵中，可在创建后拖动到其他节次位置。
            </DialogDescription>
          </DialogHeader>
          <label className="space-y-1.5 text-[12px] font-medium text-ink">
            时段名称
            <Input
              autoFocus
              maxLength={30}
              onChange={(event) => setNewCommonPeriodName(event.currentTarget.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter' && newCommonPeriodName.trim()) addCommonPeriod();
              }}
              placeholder="例如：阳光大课间"
              value={newCommonPeriodName}
            />
          </label>
          <label className="space-y-1.5 text-[12px] font-medium text-ink">
            插入位置
            <select
              className="h-9 w-full rounded-control border border-border bg-surface px-3 text-[12px] font-normal text-ink outline-none focus-visible:ring-2 focus-visible:ring-ring"
              onChange={(event) => setNewCommonPeriodAnchor(event.currentTarget.value)}
              value={newCommonPeriodAnchor}
            >
              <option value="__first__">所有节次之前</option>
              {lessonRows.map(({ period, lessonIndex }) => (
                <option key={`${period.id}_${lessonIndex}`} value={`${period.id}_${lessonIndex}`}>
                  {period.name}第{lessonIndex}节之后
                </option>
              ))}
            </select>
          </label>
          <DialogFooter>
            <Button onClick={() => setAddCommonPeriodOpen(false)} type="button" variant="outline">
              取消
            </Button>
            <Button
              disabled={!newCommonPeriodName.trim()}
              onClick={addCommonPeriod}
              type="button"
            >
              添加时段
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

export function FreeSlotScopeTree({
  stages,
  grades,
  classes,
  scope,
  onChange,
}: {
  stages: SchoolStage[];
  grades: GradeGroup[];
  classes: ClassGroup[];
  scope: FreeSlotScopeSelection;
  onChange: (scope: FreeSlotScopeSelection) => void;
}) {
  const [expandedStages, setExpandedStages] = useState(
    () => new Set([scope.stageId])
  );
  const [expandedGrades, setExpandedGrades] = useState<Set<string>>(() => new Set());

  useEffect(() => {
    setExpandedStages((current) => new Set([...current, scope.stageId]));
  }, [scope.stageId]);

  return (
    <Card className="min-w-0 p-3 sm:p-4">
      <p className="px-1.5 pb-2 text-[10.5px] font-semibold tracking-wide text-ink-secondary">
        范围
      </p>
      <div className="space-y-0.5">
        {stages.map((stage) => {
          const stageGrades = grades
            .filter((grade) => grade.stageId === stage.id)
            .sort((a, b) => a.sortOrder - b.sortOrder);
          const isExpanded = expandedStages.has(stage.id);
          const stageSelected =
            scope.scopeType === 'stage' && scope.scopeId === stage.id;
          return (
            <div key={stage.id}>
              <div className="flex items-center gap-0.5">
                <button
                  aria-label={(isExpanded ? '收起' : '展开') + stage.name}
                  aria-expanded={isExpanded}
                  className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-ink-secondary hover:bg-surface"
                  onClick={() =>
                    setExpandedStages((current) => {
                      const next = new Set(current);
                      if (next.has(stage.id)) next.delete(stage.id);
                      else next.add(stage.id);
                      return next;
                    })
                  }
                  type="button"
                >
                  {isExpanded ? (
                    <ChevronDown aria-hidden="true" className="h-3.5 w-3.5" />
                  ) : (
                    <ChevronRight aria-hidden="true" className="h-3.5 w-3.5" />
                  )}
                </button>
                <button
                  aria-current={stageSelected ? 'true' : undefined}
                  className={
                    'min-h-8 min-w-0 flex-1 truncate rounded-md px-2 text-left text-[11.5px] font-medium transition-colors ' +
                    (stageSelected
                      ? 'bg-selection text-primary'
                      : 'text-ink hover:bg-surface')
                  }
                  onClick={() =>
                    onChange({
                      scopeType: 'stage',
                      scopeId: stage.id,
                      stageId: stage.id,
                      parentGradeId: null,
                    })
                  }
                  type="button"
                >
                  {stage.name}
                </button>
              </div>

              {isExpanded && stageGrades.length > 0 && (
                <div className="ml-3 border-l border-border pl-1.5">
                  {stageGrades.map((grade) => {
                    const gradeClasses = classes
                      .filter((group) => group.gradeId === grade.id)
                      .sort((a, b) => a.sortOrder - b.sortOrder);
                    const gradeExpanded = expandedGrades.has(grade.id);
                    const gradeSelected =
                      scope.scopeType === 'grade' && scope.scopeId === grade.id;
                    return (
                      <div key={grade.id}>
                        <div className="flex items-center gap-0.5">
                          <button
                            aria-label={(gradeExpanded ? '收起' : '展开') + grade.name}
                            aria-expanded={gradeExpanded}
                            className="flex h-7 w-7 shrink-0 items-center justify-center rounded text-ink-secondary hover:bg-surface"
                            onClick={() =>
                              setExpandedGrades((current) => {
                                const next = new Set(current);
                                if (next.has(grade.id)) next.delete(grade.id);
                                else next.add(grade.id);
                                return next;
                              })
                            }
                            type="button"
                          >
                            {gradeExpanded ? (
                              <ChevronDown aria-hidden="true" className="h-3 w-3" />
                            ) : (
                              <ChevronRight aria-hidden="true" className="h-3 w-3" />
                            )}
                          </button>
                          <button
                            aria-current={gradeSelected ? 'true' : undefined}
                            className={
                              'min-h-8 min-w-0 flex-1 truncate rounded-md px-2 text-left text-[11px] transition-colors ' +
                              (gradeSelected
                                ? 'bg-selection text-primary'
                                : 'text-ink-secondary hover:bg-surface hover:text-ink')
                            }
                            onClick={() =>
                              onChange({
                                scopeType: 'grade',
                                scopeId: grade.id,
                                stageId: stage.id,
                                parentGradeId: null,
                              })
                            }
                            type="button"
                          >
                            {grade.name}
                          </button>
                        </div>
                        {gradeExpanded && gradeClasses.length > 0 && (
                          <div className="ml-3 border-l border-border pl-1.5">
                            {gradeClasses.map((group) => {
                              const classSelected =
                                scope.scopeType === 'class' &&
                                scope.scopeId === group.id;
                              return (
                                <button
                                  aria-current={classSelected ? 'true' : undefined}
                                  className={
                                    'min-h-8 w-full truncate rounded-md px-2 text-left text-[10.5px] transition-colors ' +
                                    (classSelected
                                      ? 'bg-selection text-primary'
                                      : 'text-ink-secondary hover:bg-surface hover:text-ink')
                                  }
                                  key={group.id}
                                  onClick={() =>
                                    onChange({
                                      scopeType: 'class',
                                      scopeId: group.id,
                                      stageId: stage.id,
                                      parentGradeId: grade.id,
                                    })
                                  }
                                  type="button"
                                >
                                  {group.name}
                                </button>
                              );
                            })}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </Card>
  );
}
