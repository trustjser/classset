import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Check,
  Copy,
  Clock3,
  Minus,
  Plus,
  Redo2,
  RotateCcw,
  Save,
  Undo2,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { TimePicker } from '@/components/ui/time-picker';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import type {
  FreeSlot,
  LessonPeriodType,
  LessonTime,
  ScheduleItem,
  StageRoutine,
} from '@/domain/models';
import {
  completeRoutinePeriodTypes,
  formatRoutinePeriods,
  formatRoutineTeachingDays,
  getPeriodAccentColor,
  WEEKDAY_SHORT_NAMES,
} from '@/domain/routineUtils';
import { useAppStore } from '@/store/useAppStore';
import {
  FreeSlotScopeTree,
  FreeSlotEditor,
  type FreeSlotScopeSelection,
} from '@/features/routines/FreeSlotEditor';
import {
  captureRoutineDraftSnapshot,
  restoreRoutineDraftSnapshot,
  type RoutineDraftSnapshot,
} from '@/features/routines/routineDraftHistory';
import {
  ROUTINE_TEMPLATES,
  templateSummary,
  type RoutineTemplate,
} from '@/features/routines/routineTemplates';

const WEEKDAYS = [
  ...WEEKDAY_SHORT_NAMES.map((short, index) => ({
    weekday: index + 1,
    short,
    label: `周${short}`,
  })),
] as const;

function createDefaultRoutine(stageId: string): StageRoutine {
  return normalizeRoutine(
    {
      stageId,
      teachingDays: [],
      periodTypes: [],
      dailyOverrides: [],
      lessonTimes: [],
      commonPeriods: [],
    },
    stageId
  );
}

function normalizeRoutine(routine: StageRoutine, stageId: string): StageRoutine {
  const periodTypes = completeRoutinePeriodTypes(routine.periodTypes, stageId);
  const existingDays = new Map(routine.teachingDays.map((day) => [day.weekday, day]));
  const teachingDays = WEEKDAYS.map(({ weekday }) => {
    const existing = existingDays.get(weekday);
    return (
      existing ?? {
        id: `td_${stageId}_${weekday}`,
        stageId,
        weekday,
        isTeachingDay: weekday <= 5,
      }
    );
  });
  const validPeriodIds = new Set(periodTypes.map((period) => period.id));
  const existingTimes = new Map(
    routine.lessonTimes
      .filter((time) => validPeriodIds.has(time.periodTypeId))
      .map((time) => [`${time.periodTypeId}:${time.lessonIndex}`, time])
  );
  const lessonTimes = periodTypes.flatMap((period) => {
    const existingPeriodTimes = routine.lessonTimes
      .filter((time) => time.periodTypeId === period.id)
      .sort((a, b) => a.lessonIndex - b.lessonIndex);
    const maxLessonIndex = Math.max(
      period.defaultLessonCount,
      ...existingPeriodTimes.map((time) => time.lessonIndex)
    );
    return Array.from({ length: maxLessonIndex }, (_, index) => {
      const lessonIndex = index + 1;
      return (
        existingTimes.get(`${period.id}:${lessonIndex}`) ?? {
          id: `${period.id}_${lessonIndex}`,
          periodTypeId: period.id,
          lessonIndex,
          label: `第${lessonIndex}节`,
          startMinute: null,
          endMinute: null,
        }
      );
    });
  });

  return {
    stageId,
    teachingDays,
    periodTypes,
    dailyOverrides: routine.dailyOverrides
      .filter((item) => validPeriodIds.has(item.periodTypeId))
      .sort((a, b) => a.weekday - b.weekday || a.periodTypeId.localeCompare(b.periodTypeId)),
    lessonTimes,
    commonPeriods: (routine.commonPeriods ?? [])
      .filter((period) => period.stageId === stageId)
      .slice()
      .sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name)),
  };
}

function routineSignature(routine: StageRoutine): string {
  const normalized = normalizeRoutine(routine, routine.stageId);
  return JSON.stringify({
    teachingDays: normalized.teachingDays.map((day) => [day.weekday, day.isTeachingDay]),
    periodTypes: normalized.periodTypes.map((period) => [
      period.id,
      period.name,
      period.defaultLessonCount,
      period.sortOrder,
    ]),
    dailyOverrides: normalized.dailyOverrides.map((item) => [
      item.periodTypeId,
      item.weekday,
      item.lessonCount,
    ]),
    lessonTimes: normalized.lessonTimes.map((time) => [
      time.periodTypeId,
      time.lessonIndex,
      time.label,
      time.startMinute,
      time.endMinute,
    ]),
    commonPeriods: (normalized.commonPeriods ?? []).map((period) => [
      period.id,
      period.name,
      period.insertAfterLessonId,
      period.durationMinutes,
      period.sortOrder,
      period.startMinute,
      period.endMinute,
    ]),
  });
}

interface RoutineHistoryFrame {
  termId: string;
  stageIds: string[];
  selectedStageId: string;
  scope: FreeSlotScopeSelection;
  snapshot: RoutineDraftSnapshot;
}

interface RoutineHistoryEntry {
  label: string;
  before: RoutineHistoryFrame;
  after: RoutineHistoryFrame;
}

interface RoutineHistoryState {
  termId: string;
  undo: RoutineHistoryEntry[];
  redo: RoutineHistoryEntry[];
}

function minuteToTime(value: number | null): string {
  if (value === null) return '';
  const hours = Math.floor(value / 60);
  const minutes = value % 60;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

function timeToMinute(value: string): number | null {
  if (!value) return null;
  const [hours, minutes] = value.split(':').map(Number);
  return hours * 60 + minutes;
}

function applyTemplateToRoutine(
  routine: StageRoutine,
  template: RoutineTemplate
): StageRoutine {
  const templatePeriods = new Map(template.periods.map((period) => [period.name, period]));
  const periodNameAliases: Record<string, string> = {
    早读: '早上',
    上午时段: '上午',
    下午时段: '下午',
    晚自习: '晚上',
  };
  const periodTypes = routine.periodTypes.map((period) => ({
    ...period,
    name: periodNameAliases[period.name] ?? period.name,
  }));
  const order = ['早上', '上午', '下午', '晚上'];
  for (const name of order) {
    if (periodTypes.some((existing) => existing.name === name)) continue;
    periodTypes.push({
      id: 'pt_' + routine.stageId + '_' + name,
      stageId: routine.stageId,
      name,
      defaultLessonCount: 0,
      sortOrder: periodTypes.length,
    });
  }
  periodTypes.sort((a, b) => {
    const aOrder = order.indexOf(a.name);
    const bOrder = order.indexOf(b.name);
    return (aOrder < 0 ? order.length + a.sortOrder : aOrder) -
      (bOrder < 0 ? order.length + b.sortOrder : bOrder);
  });
  const nextPeriods = periodTypes.map((period, sortOrder) => ({
    ...period,
    defaultLessonCount: templatePeriods.get(period.name)?.times.length ?? 0,
    sortOrder,
  }));
  let lessonSequence = 0;
  const lessonTimes = nextPeriods.flatMap((period) =>
    (templatePeriods.get(period.name)?.times ?? []).map(([start, end], index) => {
      const lessonIndex = index + 1;
      const existing = routine.lessonTimes.find(
        (time) => time.periodTypeId === period.id && time.lessonIndex === lessonIndex
      );
      const label = period.name.includes('早')
        ? '早' + lessonIndex
        : period.name.includes('晚')
          ? '晚' + lessonIndex
          : '第 ' + ++lessonSequence + ' 节';
      return {
        id: existing?.id ?? period.id + '_' + lessonIndex,
        periodTypeId: period.id,
        lessonIndex,
        label,
        startMinute: timeToMinute(start),
        endMinute: timeToMinute(end),
      };
    })
  );
  return {
    ...routine,
    teachingDays: routine.teachingDays.map((day) => ({
      ...day,
      isTeachingDay: template.teachingWeekdays.includes(day.weekday),
    })),
    periodTypes: nextPeriods,
    lessonTimes,
  };
}

interface ScheduleImpact {
  item: ScheduleItem;
  reason: string;
}

function findScheduleImpacts(
  items: ScheduleItem[],
  routine: StageRoutine,
  stageIdByClass: Map<string, string | undefined>
): ScheduleImpact[] {
  const teachingDays = new Set(
    routine.teachingDays.filter((day) => day.isTeachingDay).map((day) => day.weekday)
  );
  const periods = new Map(routine.periodTypes.map((period) => [period.id, period]));
  return items.flatMap((item) => {
    const itemStageId = item.stageId ?? stageIdByClass.get(item.classId);
    if (itemStageId !== routine.stageId || item.weekday === null) return [];
    if (!teachingDays.has(item.weekday)) return [{ item, reason: '该日已设为休息日' }];
    const period = item.periodTypeId ? periods.get(item.periodTypeId) : undefined;
    if (!period) return [{ item, reason: '时段已不在作息中' }];
    if (item.lessonIndex === null) return [];
    return item.lessonIndex > period.defaultLessonCount
      ? [{ item, reason: `该时段仅设置 ${period.defaultLessonCount} 节` }]
      : [];
  });
}

function findFreeSlotScheduleImpacts(
  items: ScheduleItem[],
  slotsBefore: FreeSlot[],
  slotsAfter: FreeSlot[],
  termId: string,
  gradeIdByClass: Map<string, string>,
  stageIdByClass: Map<string, string | undefined>
): ScheduleImpact[] {
  const findMarker = (item: ScheduleItem, slots: FreeSlot[]) => {
    if (
      item.weekday === null ||
      item.lessonIndex === null ||
      item.periodTypeId === null
    ) {
      return undefined;
    }
    const stageId = item.stageId ?? stageIdByClass.get(item.classId);
    const gradeId = gradeIdByClass.get(item.classId);
    return slots
      .filter(
        (slot) =>
          slot.stageId === stageId &&
          slot.periodTypeId === item.periodTypeId &&
          slot.weekday === item.weekday &&
          slot.lessonIndex === item.lessonIndex &&
          ((slot.scopeType === 'school' && slot.scopeId === termId) ||
            (slot.scopeType === 'stage' && slot.scopeId === stageId) ||
            (slot.scopeType === 'grade' && slot.scopeId === gradeId) ||
            (slot.scopeType === 'class' && slot.scopeId === item.classId))
      )
      .sort((a, b) => {
        const priority = (slot: FreeSlot) =>
          slot.scopeType === 'class'
            ? 4
            : slot.scopeType === 'grade'
              ? 3
              : slot.scopeType === 'stage'
                ? 2
                : 1;
        return priority(b) - priority(a);
      })[0];
  };

  return items.flatMap((item) => {
    const markerBefore = findMarker(item, slotsBefore);
    const markerAfter = findMarker(item, slotsAfter);
    if (!markerAfter || markerBefore) return [];
    return [
      {
        item,
        reason: '新增免任课标记「' + markerAfter.label + '」与现有排课重合',
      },
    ];
  });
}

function PeriodCountControl({
  period,
  index,
  onChange,
}: {
  period: LessonPeriodType;
  index: number;
  onChange: (count: number) => void;
}) {
  const accent = getPeriodAccentColor(period.name, index);
  return (
    <div className="flex items-center gap-3 border-t border-table-divider py-3 first:border-0 first:pt-0 last:pb-0">
      <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ backgroundColor: accent }} />
      <div className="min-w-0 flex-1">
        <div className="whitespace-nowrap text-[13.5px] font-semibold text-ink">{period.name}</div>
      </div>
      <div className="flex h-9 items-center overflow-hidden rounded-control border border-border bg-surface">
        <button
          aria-label={`${period.name}减少一节`}
          className="flex h-9 w-9 items-center justify-center text-ink-secondary transition-colors hover:bg-table-header hover:text-ink disabled:opacity-40"
          disabled={period.defaultLessonCount <= 0}
          onClick={() => onChange(period.defaultLessonCount - 1)}
          type="button"
        >
          <Minus aria-hidden="true" className="h-3.5 w-3.5" />
        </button>
        <span className="min-w-12 border-x border-border px-2 text-center font-mono text-[13px] font-semibold tabular-nums text-ink">
          {period.defaultLessonCount}
          <span className="ml-1 text-[11px] font-normal text-ink-secondary">节</span>
        </span>
        <button
          aria-label={`${period.name}增加一节`}
          className="flex h-9 w-9 items-center justify-center text-ink-secondary transition-colors hover:bg-table-header hover:text-ink disabled:opacity-40"
          disabled={period.defaultLessonCount >= 9}
          onClick={() => onChange(period.defaultLessonCount + 1)}
          type="button"
        >
          <Plus aria-hidden="true" className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  );
}

export const RoutinesPage: React.FC<{ onOpenClasses: () => void }> = ({
  onOpenClasses,
}) => {
  const {
    stages,
    grades,
    classes,
    subjects,
    routinesByStage,
    routineDraftsByStage,
    freeSlotsByStage,
    freeSlotDraftsByTerm,
    summary,
    setRoutineDraft,
    discardRoutineDraft,
    discardTermDrafts,
    saveStageRoutine,
    loadScheduleItems,
  } = useAppStore();
  const [selectedStageId, setSelectedStageId] = useState('');
  const [scopeSelection, setScopeSelection] =
    useState<FreeSlotScopeSelection | null>(null);
  const [confirmSaveOpen, setConfirmSaveOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [loadingScheduleImpact, setLoadingScheduleImpact] = useState(false);
  const [scheduleImpacts, setScheduleImpacts] = useState<ScheduleImpact[]>([]);
  const [savedNotice, setSavedNotice] = useState(false);
  const [templateOpen, setTemplateOpen] = useState(false);
  const [selectedTemplateId, setSelectedTemplateId] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const historyRef = useRef<RoutineHistoryState>({ termId: '', undo: [], redo: [] });
  const [historyDepth, setHistoryDepth] = useState({ undo: 0, redo: 0 });

  const selectedStage =
    stages.find((stage) => stage.id === selectedStageId) ?? stages[0] ?? null;
  const activeStageId = selectedStage?.id ?? '';
  const termStages = useMemo(
    () => stages.filter((stage) => stage.termId === selectedStage?.termId),
    [selectedStage?.termId, stages]
  );
  useEffect(() => {
    for (const stage of termStages) {
      if (
        !routinesByStage[stage.id]?.periodTypes.length &&
        !routineDraftsByStage[stage.id]
      ) {
        const saved = routinesByStage[stage.id];
        setRoutineDraft(saved ? normalizeRoutine(saved, stage.id) : createDefaultRoutine(stage.id));
      }
    }
  }, [termStages, routinesByStage, routineDraftsByStage, setRoutineDraft]);
  const termFreeSlotDrafts = selectedStage
    ? freeSlotDraftsByTerm[selectedStage.termId] ?? {}
    : {};
  const hasFreeSlotDrafts = Object.keys(termFreeSlotDrafts).length > 0;
  const hasTermRoutineDrafts = termStages.some(
    (stage) => Boolean(routineDraftsByStage[stage.id])
  );
  const persistedRoutine = activeStageId ? routinesByStage[activeStageId] : undefined;
  const persistedBaseline = useMemo(
    () =>
      activeStageId
        ? normalizeRoutine(
            persistedRoutine ?? {
              stageId: activeStageId,
              teachingDays: [],
              periodTypes: [],
              dailyOverrides: [],
              lessonTimes: [],
              commonPeriods: [],
            },
            activeStageId
          )
        : null,
    [activeStageId, persistedRoutine]
  );
  const routine = activeStageId
    ? routineDraftsByStage[activeStageId] ??
      (persistedRoutine
        ? normalizeRoutine(persistedRoutine, activeStageId)
        : createDefaultRoutine(activeStageId))
    : null;
  const hasPersistedRoutine = Boolean(persistedRoutine?.periodTypes.length);
  const hasDraft = hasTermRoutineDrafts || hasFreeSlotDrafts;
  const isDirty = hasDraft;
  const activeScope =
    scopeSelection?.stageId === activeStageId
      ? scopeSelection
      : ({
          scopeType: 'stage',
          scopeId: activeStageId,
          stageId: activeStageId,
          parentGradeId: null,
        } satisfies FreeSlotScopeSelection);

  const clearHistory = () => {
    historyRef.current = {
      termId: selectedStage?.termId ?? '',
      undo: [],
      redo: [],
    };
    setHistoryDepth({ undo: 0, redo: 0 });
  };

  useEffect(() => {
    historyRef.current = {
      termId: selectedStage?.termId ?? '',
      undo: [],
      redo: [],
    };
    setHistoryDepth({ undo: 0, redo: 0 });
  }, [selectedStage?.termId]);

  const captureHistoryFrame = (): RoutineHistoryFrame | null => {
    if (!selectedStage) return null;
    const stageIds = termStages.map((stage) => stage.id);
    return {
      termId: selectedStage.termId,
      stageIds,
      selectedStageId: activeStageId,
      scope: activeScope,
      snapshot: captureRoutineDraftSnapshot(selectedStage.termId, stageIds),
    };
  };

  const syncHistoryDepth = () => {
    setHistoryDepth({
      undo: historyRef.current.undo.length,
      redo: historyRef.current.redo.length,
    });
  };

  const runHistory = (label: string, action: () => void) => {
    const before = captureHistoryFrame();
    if (!before) {
      action();
      return;
    }
    if (historyRef.current.termId !== before.termId) {
      historyRef.current = { termId: before.termId, undo: [], redo: [] };
    }
    action();
    const after = captureHistoryFrame();
    if (!after || JSON.stringify(before.snapshot) === JSON.stringify(after.snapshot)) return;
    historyRef.current.undo.push({ label, before, after });
    if (historyRef.current.undo.length > 100) historyRef.current.undo.shift();
    historyRef.current.redo = [];
    syncHistoryDepth();
  };

  const applyHistory = (direction: 'undo' | 'redo') => {
    const history = historyRef.current;
    const source = history[direction];
    const entry = source[source.length - 1];
    if (!entry || entry.before.termId !== selectedStage?.termId) return;
    source.pop();
    const target = direction === 'undo' ? entry.before : entry.after;
    restoreRoutineDraftSnapshot(target.termId, target.stageIds, target.snapshot);
    setSelectedStageId(target.selectedStageId);
    setScopeSelection(target.scope);
    history[direction === 'undo' ? 'redo' : 'undo'].push(entry);
    syncHistoryDepth();
    setSavedNotice(false);
    setErrorMessage(null);
  };

  useEffect(() => {
    const handleHistoryShortcut = (event: KeyboardEvent) => {
      if (!(event.metaKey || event.ctrlKey)) return;
      const key = event.key.toLowerCase();
      if (key !== 'z' && key !== 'y') return;
      const target = event.target;
      if (
        target instanceof HTMLElement &&
        target.closest('input, textarea, select, [contenteditable="true"]')
      ) {
        return;
      }
      event.preventDefault();
      const direction = key === 'y' || event.shiftKey ? 'redo' : 'undo';
      applyHistory(direction);
    };
    window.addEventListener('keydown', handleHistoryShortcut);
    return () => window.removeEventListener('keydown', handleHistoryShortcut);
  }, [applyHistory]);

  const termGrades = useMemo(
    () =>
      grades.filter((grade) =>
        termStages.some((stage) => stage.id === grade.stageId)
      ),
    [grades, termStages]
  );
  const termGradeIds = useMemo(
    () => new Set(termGrades.map((grade) => grade.id)),
    [termGrades]
  );
  const termClasses = useMemo(
    () => classes.filter((group) => termGradeIds.has(group.gradeId)),
    [classes, termGradeIds]
  );
  const activeTeachingDayCount =
    routine?.teachingDays.filter((day) => day.isTeachingDay).length ?? 0;
  const totalDailyLessons =
    routine?.periodTypes.reduce((total, period) => total + period.defaultLessonCount, 0) ?? 0;

  const updateRoutine = (
    updater: (current: StageRoutine) => StageRoutine,
    historyLabel = '修改作息'
  ) => {
    if (!routine || !activeStageId) return;
    setSavedNotice(false);
    setErrorMessage(null);
    runHistory(historyLabel, () => {
      const next = normalizeRoutine(updater(routine), activeStageId);
      if (
        persistedRoutine?.periodTypes.length &&
        routineSignature(next) === routineSignature(normalizeRoutine(persistedRoutine, activeStageId))
      ) {
        discardRoutineDraft(activeStageId);
      } else {
        setRoutineDraft(next);
      }
    });
  };

  const changePeriodCount = (periodTypeId: string, count: number) => {
    updateRoutine((current) => ({
      ...current,
      periodTypes: current.periodTypes.map((period) =>
        period.id === periodTypeId
          ? { ...period, defaultLessonCount: Math.max(0, Math.min(9, count)) }
          : period
      ),
    }));
  };

  const changeLessonTime = (
    periodTypeId: string,
    lessonIndex: number,
    field: 'startMinute' | 'endMinute',
    value: string
  ) => {
    updateRoutine((current) => ({
      ...current,
      lessonTimes: current.lessonTimes.map((time) =>
        time.periodTypeId === periodTypeId && time.lessonIndex === lessonIndex
          ? { ...time, [field]: timeToMinute(value) }
          : time
      ),
    }));
  };

  const saveNow = async () => {
    if (!routine || !isDirty) return;
    setSaving(true);
    setErrorMessage(null);
    try {
      const counts = new Map(
        routine.periodTypes.map((period) => [period.id, period.defaultLessonCount])
      );
      const routineToSave = {
        ...routine,
        lessonTimes: routine.lessonTimes.filter(
          (time) => time.lessonIndex <= (counts.get(time.periodTypeId) ?? -1)
        ),
      };
      const validLessonIds = new Set(routineToSave.lessonTimes.map((time) => time.id));
      routineToSave.commonPeriods = (routine.commonPeriods ?? []).map((period) => {
        const anchor = period.insertAfterLessonId;
        if (!anchor || validLessonIds.has(anchor)) return period;
        const previousPeriod = routine.periodTypes.find((item) =>
          anchor.startsWith(`${item.id}_`)
        );
        const lastLesson = previousPeriod
          ? routineToSave.lessonTimes
              .filter((time) => time.periodTypeId === previousPeriod.id)
              .sort((a, b) => b.lessonIndex - a.lessonIndex)[0]
          : undefined;
        return { ...period, insertAfterLessonId: lastLesson?.id ?? null };
      });
      await saveStageRoutine(routineToSave);
      setConfirmSaveOpen(false);
      setSavedNotice(true);
      clearHistory();
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : '作息保存失败，请重试。');
    } finally {
      setSaving(false);
    }
  };

  const requestSave = async () => {
    if (!routine || !isDirty) return;
    if (summary?.hasSchedule) {
      setLoadingScheduleImpact(true);
      setErrorMessage(null);
      setScheduleImpacts([]);
      setConfirmSaveOpen(true);
      try {
        const items = await loadScheduleItems(selectedStage.termId);
        const gradeById = new Map(grades.map((grade) => [grade.id, grade.stageId]));
        const gradeIdByClass = new Map(
          classes.map((group) => [group.id, group.gradeId])
        );
        const stageIdByClass = new Map(
          classes.map((group) => [group.id, gradeById.get(group.gradeId)])
        );
        const routineImpacts = termStages.flatMap((stage) => {
          const draft = routineDraftsByStage[stage.id];
          return draft ? findScheduleImpacts(items, draft, stageIdByClass) : [];
        });
        const persistedSlots = termStages.flatMap(
          (stage) => freeSlotsByStage[stage.id] ?? []
        );
        const slotsAfterById = new Map(
          persistedSlots.map((slot) => [slot.id, slot])
        );
        for (const [slotId, slot] of Object.entries(termFreeSlotDrafts)) {
          if (slot) slotsAfterById.set(slotId, slot);
          else slotsAfterById.delete(slotId);
        }
        const freeSlotImpacts = findFreeSlotScheduleImpacts(
          items,
          persistedSlots,
          [...slotsAfterById.values()],
          selectedStage.termId,
          gradeIdByClass,
          stageIdByClass
        );
        const combinedImpacts = new Map<string, ScheduleImpact>();
        for (const impact of [...routineImpacts, ...freeSlotImpacts]) {
          combinedImpacts.set(impact.item.id, impact);
        }
        setScheduleImpacts([...combinedImpacts.values()]);
      } catch (error) {
        setConfirmSaveOpen(false);
        setErrorMessage(
          error instanceof Error ? error.message : '读取现有课表失败，暂时无法确认作息修改。'
        );
      } finally {
        setLoadingScheduleImpact(false);
      }
    } else {
      void saveNow();
    }
  };

  if (stages.length === 0) {
    return (
      <Card className="p-8 text-center">
        <Clock3 aria-hidden="true" className="mx-auto h-6 w-6 text-ink-secondary" />
        <h2 className="mt-3 text-[15px] font-semibold text-ink">先建立学段</h2>
        <p className="mt-1 text-[13px] text-ink-secondary">
          创建学段后，就可以设置上课日和每天的课程节数。
        </p>
        <Button className="mt-4" onClick={onOpenClasses} type="button" variant="outline">
          前往班级与学段
        </Button>
      </Card>
    );
  }

  if (!routine || !selectedStage) return null;

  return (
    <div className="space-y-4">
      <div className="sticky top-0 z-30 flex min-w-0 flex-wrap items-center justify-between gap-3 rounded-card border border-border bg-surface/95 px-3 py-2.5 shadow-sm backdrop-blur sm:px-4">
        <div className="flex min-w-0 items-center gap-3">
          <div className="min-w-0">
            <div className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
              <h2 className="text-[13px] font-semibold text-ink">作息设置</h2>
              <span className="max-w-[240px] truncate text-[12px] text-ink-secondary">
                {selectedStage.name}
              </span>
            </div>
          </div>
          <div aria-live="polite" className="flex shrink-0 items-center gap-2">
            {isDirty ? (
              <Badge variant="warning">未保存</Badge>
            ) : savedNotice ? (
              <span className="inline-flex items-center gap-1.5 text-[12px] font-medium text-success">
                <Check aria-hidden="true" className="h-3.5 w-3.5" />
                已保存
              </span>
            ) : hasPersistedRoutine ? (
              <span className="text-[12px] text-ink-secondary">作息已保存</span>
            ) : (
              <Badge variant="secondary">待配置</Badge>
            )}
          </div>
        </div>
        <div className="flex w-full shrink-0 flex-wrap gap-2 sm:w-auto">
          <Button
            className="h-8 flex-1 gap-1.5 px-2.5 text-[11.5px] sm:flex-none"
            disabled={saving}
            onClick={() => {
              setSelectedTemplateId(null);
              setTemplateOpen(true);
            }}
            type="button"
            variant="outline"
          >
            <Copy aria-hidden="true" className="h-3.5 w-3.5" />
            选择模板
          </Button>
          <Button
            aria-label="撤销作息修改"
            className="h-8 flex-1 gap-1.5 px-2.5 text-[11.5px] sm:flex-none"
            disabled={!historyDepth.undo || saving}
            onClick={() => applyHistory('undo')}
            title={historyRef.current.undo[historyRef.current.undo.length - 1]?.label ?? '撤销'}
            type="button"
            variant="outline"
          >
            <Undo2 aria-hidden="true" className="h-3.5 w-3.5" />
            撤销
          </Button>
          <Button
            aria-label="重做作息修改"
            className="h-8 flex-1 gap-1.5 px-2.5 text-[11.5px] sm:flex-none"
            disabled={!historyDepth.redo || saving}
            onClick={() => applyHistory('redo')}
            title={historyRef.current.redo[historyRef.current.redo.length - 1]?.label ?? '重做'}
            type="button"
            variant="outline"
          >
            <Redo2 aria-hidden="true" className="h-3.5 w-3.5" />
            重做
          </Button>
          <Button
            className="h-8 flex-1 px-3 text-[11.5px] sm:flex-none"
            disabled={!isDirty || saving}
            onClick={() => {
              discardTermDrafts(selectedStage.termId);
              clearHistory();
              setErrorMessage(null);
              setSavedNotice(false);
            }}
            type="button"
            variant="outline"
          >
            <RotateCcw aria-hidden="true" className="h-3.5 w-3.5" />
            放弃修改
          </Button>
          <Button
            className="h-8 flex-1 px-3 text-[11.5px] sm:flex-none"
            disabled={!isDirty || saving}
            onClick={requestSave}
            type="button"
          >
            <Save aria-hidden="true" className="h-3.5 w-3.5" />
            {saving ? '正在保存…' : '保存作息'}
          </Button>
        </div>
      </div>

      {errorMessage && (
        <p
          className="rounded-control border border-destructive/25 bg-destructive-surface px-3.5 py-2.5 text-[12.5px] text-destructive"
          role="alert"
        >
          {errorMessage}
        </p>
      )}

      {summary?.hasSchedule && isDirty && (
        <div className="rounded-control border border-warning/25 bg-warning-surface px-3.5 py-2.5 text-[12px] leading-5 text-ink-secondary">
          学期已有课表。作息修改会保留现有课表内容，保存前请核对上课日和节数变化。
        </div>
      )}

      <div className="routines-layout-grid">
        <div className="routines-col-left space-y-4">
          <FreeSlotScopeTree
            stages={termStages}
            grades={termGrades}
            classes={termClasses}
            scope={activeScope}
            onChange={(nextScope) => {
              setScopeSelection(nextScope);
              setSelectedStageId(nextScope.stageId);
              setErrorMessage(null);
              setSavedNotice(false);
            }}
          />

          <Card className="p-4 sm:p-5">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-[15px] font-semibold text-ink">上课日</h2>
              </div>
              <Badge className="shrink-0 whitespace-nowrap" variant="secondary">
                学段
              </Badge>
            </div>
            <div className="mt-4 flex flex-wrap gap-1.5">
              {WEEKDAYS.map(({ weekday, short, label }) => {
                const day = routine.teachingDays.find((item) => item.weekday === weekday);
                const selected = Boolean(day?.isTeachingDay);
                return (
                  <button
                    key={weekday}
                    aria-label={`${label}${selected ? '，上课日' : '，休息日'}`}
                    aria-pressed={selected}
                    className={`flex h-9 min-w-[34px] flex-1 basis-[34px] items-center justify-center whitespace-nowrap rounded-control border px-1 text-[12px] font-medium transition-[background-color,border-color,color,transform] duration-feedback active:scale-[0.97] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${
                      selected
                        ? 'border-primary/25 bg-selection text-primary'
                        : 'border-border bg-surface text-ink-secondary hover:bg-table-header'
                    }`}
                    onClick={() =>
                      updateRoutine((current) => ({
                        ...current,
                        teachingDays: current.teachingDays.map((item) =>
                          item.weekday === weekday
                            ? { ...item, isTeachingDay: !item.isTeachingDay }
                            : item
                        ),
                      }))
                    }
                    type="button"
                  >
                    {short}
                  </button>
                );
              })}
            </div>
          </Card>

          <Card className="p-4 sm:p-5">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="text-[15px] font-semibold text-ink">每天节数</h2>
              </div>
              <Badge className="shrink-0 whitespace-nowrap" variant="secondary">
                学段
              </Badge>
            </div>
            <div className="mt-4">
              {routine.periodTypes.map((period, index) => (
                <PeriodCountControl
                  key={period.id}
                  period={period}
                  index={index}
                  onChange={(count) => changePeriodCount(period.id, count)}
                />
              ))}
            </div>
          </Card>
        </div>

        <FreeSlotEditor
          termId={selectedStage.termId}
          stages={termStages}
          grades={termGrades}
          classes={termClasses}
          routinesByStage={routinesByStage}
          routineDraftsByStage={routineDraftsByStage}
          routine={routine}
          scope={activeScope}
          runHistory={runHistory}
          onUpdateRoutine={updateRoutine}
          className="routines-col-center"
        />

        <Card className="routines-col-right p-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <h2 className="text-[15px] font-semibold text-ink">节次时间</h2>
              <p className="mt-1 text-[12px] text-ink-secondary">
                时间用于课表展示；暂不设置时可留空。
              </p>
            </div>
            <Clock3 aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-ink-secondary" />
          </div>

          <div className="mt-4 space-y-4">
            {routine.periodTypes.map((period, periodIndex) => {
              const times = routine.lessonTimes
                .filter((time) => time.periodTypeId === period.id)
                .sort((a, b) => a.lessonIndex - b.lessonIndex);
              const activeTimes = times.filter(
                (time) => time.lessonIndex <= period.defaultLessonCount
              );
              if (activeTimes.length === 0) return null;
              return (
                <section className="border-t border-table-divider pt-3 first:border-0 first:pt-0" key={period.id}>
                  <div className="mb-2 flex items-center gap-2 whitespace-nowrap text-[12.5px] font-semibold text-ink">
                    <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: getPeriodAccentColor(period.name, periodIndex) }} />
                    <span>{period.name}</span>
                    <span className="font-normal text-ink-secondary">
                      {activeTimes.length} 节
                    </span>
                  </div>
                  <div className="grid grid-cols-[44px_minmax(92px,1fr)_minmax(92px,1fr)] gap-x-1.5 pb-1 text-[10.5px] text-ink-secondary">
                    <span className="whitespace-nowrap">课次</span>
                    <span>开始</span>
                    <span>结束</span>
                  </div>
                  <div className="space-y-1.5">
                    {activeTimes.map((time) => (
                      <LessonTimeRow
                        key={`${period.id}:${time.lessonIndex}`}
                        period={period}
                        time={time}
                        onChange={changeLessonTime}
                      />
                    ))}
                  </div>
                </section>
              );
            })}
          </div>
        </Card>
      </div>

      <Dialog open={templateOpen} onOpenChange={setTemplateOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>应用作息模板</DialogTitle>
            <DialogDescription>
              模板会覆盖当前学段的上课日、节数和节次时间。应用后仍需点击“保存作息”。
            </DialogDescription>
          </DialogHeader>
          <div className="max-h-[55vh] space-y-2 overflow-y-auto">
            {ROUTINE_TEMPLATES.map((template) => (
              <button
                key={template.id}
                type="button"
                aria-pressed={selectedTemplateId === template.id}
                className={
                  'w-full rounded-control border p-3 text-left transition-colors ' +
                  (selectedTemplateId === template.id
                    ? 'border-primary bg-selection'
                    : 'border-border bg-surface hover:bg-table-header')
                }
                onClick={() => setSelectedTemplateId(template.id)}
              >
                <span className="flex items-center justify-between gap-2">
                  <span className="text-[13px] font-semibold text-ink">{template.name}</span>
                  <span className="text-[11px] text-primary">{templateSummary(template)}</span>
                </span>
                <span className="mt-1 block text-[11.5px] leading-5 text-ink-secondary">
                  {template.description}
                </span>
              </button>
            ))}
          </div>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => setTemplateOpen(false)}>
              取消
            </Button>
            <Button
              type="button"
              disabled={!selectedTemplateId}
              onClick={() => {
                const selected = ROUTINE_TEMPLATES.find(
                  (template) => template.id === selectedTemplateId
                );
                if (!selected) return;
                updateRoutine(
                  (current) => applyTemplateToRoutine(current, selected),
                  '应用作息模板「' + selected.name + '」'
                );
                setTemplateOpen(false);
              }}
            >
              应用到草稿
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={confirmSaveOpen} onOpenChange={setConfirmSaveOpen}>
        <DialogContent className="sm:max-w-[520px]">
          <DialogHeader>
            <DialogTitle>确认保存作息修改</DialogTitle>
            <DialogDescription>
              保存会写入本学期作息、公共时段与免任课设置。现有排课记录会保留；列表标出超出新作息或与新增免任课标记重合的位置。
            </DialogDescription>
          </DialogHeader>
          <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3 rounded-control bg-table-header px-4 py-3">
            <div className="min-w-0">
              <div className="text-[11px] font-medium text-ink-secondary">保存前</div>
              <div className="mt-1 text-[12px] font-semibold text-ink">
                {hasPersistedRoutine && persistedBaseline
                  ? `${formatRoutineTeachingDays(persistedBaseline)} · ${formatRoutinePeriods(persistedBaseline)}`
                  : '尚未配置'}
              </div>
            </div>
            <span aria-hidden="true" className="text-[13px] text-ink-secondary">→</span>
            <div className="min-w-0">
              <div className="text-[11px] font-medium text-ink-secondary">保存后</div>
              <div className="mt-1 text-[12px] font-semibold text-primary">
                {formatRoutineTeachingDays(routine)} · {formatRoutinePeriods(routine)}
              </div>
            </div>
          </div>
          {loadingScheduleImpact ? (
            <p aria-live="polite" className="text-[12px] text-ink-secondary">
              正在检查已有课表…
            </p>
          ) : scheduleImpacts.length === 0 ? (
            <p className="text-[12px] leading-5 text-success">
              按当前上课日、时段和节数计算，没有已有课表位置超出新作息范围。
            </p>
          ) : (
            <div className="max-h-56 space-y-2 overflow-y-auto rounded-control border border-warning/25 bg-warning-surface p-3">
              <p className="text-[12px] font-semibold text-ink">
                有 {scheduleImpacts.length} 条已有排课位置超出新作息
              </p>
              <ul className="space-y-1.5 text-[11.5px] leading-5 text-ink-secondary">
                {scheduleImpacts.slice(0, 8).map(({ item, reason }) => {
                  const className = classes.find((group) => group.id === item.classId)?.name ?? '未知班级';
                  const subjectName = subjects.find((subject) => subject.id === item.subjectId)?.name ?? '未知科目';
                  const periodName =
                    routine.periodTypes.find((period) => period.id === item.periodTypeId)?.name ??
                    '未知时段';
                  const weekDay = item.weekday
                    ? WEEKDAYS[item.weekday - 1]?.label ?? `星期${item.weekday}`
                    : '';
                  const weekMode =
                    item.weekMode === 'odd' ? '单周' : item.weekMode === 'even' ? '双周' : '';
                  return (
                    <li key={item.id}>
                      {weekDay} · {periodName}第{item.lessonIndex ?? '—'}节 · {className} · {subjectName}
                      {weekMode ? ` · ${weekMode}` : ''}：{reason}
                    </li>
                  );
                })}
              </ul>
              {scheduleImpacts.length > 8 && (
                <p className="text-[11px] text-ink-secondary">
                  另有 {scheduleImpacts.length - 8} 条未显示。
                </p>
              )}
              <p className="text-[11.5px] leading-5 text-ink-secondary">
                确认后这些记录会原样保留，但位置可能不符合新作息。排课页面尚未迁移，之后需要重新安排。
              </p>
            </div>
          )}
          <DialogFooter>
            <Button
              disabled={saving}
              onClick={() => setConfirmSaveOpen(false)}
              type="button"
              variant="outline"
            >
              继续编辑
            </Button>
            <Button
              disabled={saving || loadingScheduleImpact}
              onClick={() => void saveNow()}
              type="button"
            >
              {saving ? '正在保存…' : scheduleImpacts.length ? '仍然保存' : '确认保存'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

function LessonTimeRow({
  period,
  time,
  onChange,
}: {
  period: LessonPeriodType;
  time: LessonTime;
  onChange: (
    periodTypeId: string,
    lessonIndex: number,
    field: 'startMinute' | 'endMinute',
    value: string
  ) => void;
}) {
  return (
    <div className="grid grid-cols-[44px_minmax(92px,1fr)_minmax(92px,1fr)] items-center gap-x-1.5">
      <span className="whitespace-nowrap text-[12px] font-medium text-ink">
        {time.label || `第${time.lessonIndex}节`}
      </span>
      <TimePicker
        ariaLabel={`${period.name} ${time.label}开始时间`}
        allowClear
        className="h-8 gap-1 px-1.5 text-[12px] tabular-nums"
        onChange={(value) => onChange(period.id, time.lessonIndex, 'startMinute', value)}
        value={minuteToTime(time.startMinute)}
      />
      <TimePicker
        ariaLabel={`${period.name} ${time.label}结束时间`}
        allowClear
        className="h-8 gap-1 px-1.5 text-[12px] tabular-nums"
        onChange={(value) => onChange(period.id, time.lessonIndex, 'endMinute', value)}
        value={minuteToTime(time.endMinute)}
      />
    </div>
  );
}
