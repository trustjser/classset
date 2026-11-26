import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  Calendar as CalendarIcon,
  Check,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Download,
  Lock,
  Search,
  UserPlus,
  X,
} from 'lucide-react';
import type { CommonPeriod } from '@/domain/models';
import type { SchedulePosition } from '@/domain/supervision';
import {
  type ActualChangePreview,
  type ActualLesson,
  type ActualSupervision,
  SUPERVISION_SUBSTITUTION_KIND,
  type TemporaryAdjustmentRecord,
  type TemporaryTimetableState,
} from '@/domain/actualTimetable';
import {
  type AdjustmentKind,
  type AdjustmentRecordStatus,
  adjustmentKindLabel,
  adjustmentStatusLabels,
  buildTeacherGridRows,
  type CandidateMoveSlot,
  clampWeekIndex,
  defaultWeekIndex,
  describeRecordSummary,
  effectiveLessonCountOnDay,
  filterAdjustmentRecords,
  findActiveRecordForLesson,
  findActiveRecordForSupervision,
  formatChineseMdWeekday,
  formatShortMd,
  formatTimestampTime,
  getClassDisplayName,
  getPeriodLessonLabel,
  getScheduleWeekdayForDate,
  getSubjectDisplayName,
  getTeacherNameById,
  getTermEndDate,
  getVisibleScheduleDates,
  getWeekStartDate,
  recordClassIds,
  recordTeacherIds,
  sameMoveSlot,
  weekdayShortLabel,
} from '@/features/temporaryAdjustments/temporaryAdjustmentsHelpers';
import {
  CancelRecordDialog,
  PreviewAdjustmentDialog,
  RecordDetailDialog,
  SubstituteTeacherDialog,
  SupervisionSubstituteDialog,
} from '@/features/temporaryAdjustments/TemporaryAdjustmentsDialogs';
import { temporaryAdjustmentsWorkerClient } from '@/features/temporaryAdjustments/temporaryAdjustmentsWorkerClient';
import {
  formatDateYmd,
  getIsoWeekday,
  parseLocalDate,
} from '@/features/terms/calendarUtils';
import { clockLabel } from '@/features/scheduling/TimetableGrid';
import '@/features/scheduling/scheduling.css';
import { useStickyToolbar } from '@/hooks/useStickyToolbar';
import { schoolRepository } from '@/repository/schoolRepository';
import { useAppStore } from '@/store/useAppStore';
import { getSubjectColor } from '@/styles/subjectColors';
import { Button } from '@/components/ui/button';
import { DatePicker } from '@/components/ui/date-picker';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';
import { SearchableSelect } from '@/components/ui/searchable-select';
import { SelectField } from '@/components/ui/select-field';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';

interface StageClassGroup {
  id: string;
  name: string;
  classes: Array<{ id: string; name: string }>;
}

function StageClassTreeSelect({
  groups,
  value,
  onChange,
}: {
  groups: StageClassGroup[];
  value: string;
  onChange: (id: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set());
  const selected = groups
    .flatMap((stage) =>
      stage.classes.map((schoolClass) => ({ stage, schoolClass }))
    )
    .find((row) => row.schoolClass.id === value);
  const normalizedQuery = query.trim().toLocaleLowerCase();
  const filteredGroups = groups
    .map((stage) => {
      const stageMatches = stage.name
        .toLocaleLowerCase()
        .includes(normalizedQuery);
      const classes =
        normalizedQuery && !stageMatches
          ? stage.classes.filter((schoolClass) =>
              schoolClass.name.toLocaleLowerCase().includes(normalizedQuery)
            )
          : stage.classes;
      return { ...stage, classes, stageMatches };
    })
    .filter(
      (stage) =>
        !normalizedQuery || stage.stageMatches || stage.classes.length > 0
    );

  return (
    <Popover
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (!next) setQuery('');
      }}
    >
      <PopoverTrigger asChild>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          aria-label={
            selected
              ? `学段与班级：${selected.stage.name}，${selected.schoolClass.name}`
              : '学段与班级'
          }
          className="h-8 justify-between gap-2"
        >
          <span className="flex min-w-0 flex-1 items-center gap-1.5 text-left">
            {selected ? (
              <>
                <span className="max-w-[4rem] shrink-0 truncate text-xs font-medium text-ink-secondary">
                  {selected.stage.name}
                </span>
                <span className="shrink-0 text-ink-secondary">·</span>
                <span className="min-w-0 truncate font-semibold text-ink">
                  {selected.schoolClass.name}
                </span>
              </>
            ) : (
              <span className="truncate">选择班级</span>
            )}
          </span>
          <ChevronDown aria-hidden="true" className="h-4 w-4 shrink-0" />
        </Button>
      </PopoverTrigger>
      <PopoverContent
        align="start"
        side="bottom"
        collisionPadding={12}
        className="w-[min(15rem,calc(100vw-24px))] p-1.5"
      >
        <div
          role="group"
          aria-label="学段与班级"
          className="max-h-[min(22rem,60vh)] overflow-y-auto"
        >
          <div className="sticky top-0 z-10 border-b border-border bg-surface px-1 pb-2 pt-1">
            <div className="relative">
              <Search
                aria-hidden="true"
                className="pointer-events-none absolute left-2 top-2 h-4 w-4 text-ink-secondary"
              />
              <Input
                autoFocus
                aria-label="搜索学段或班级"
                className="h-8 pl-8 text-sm"
                placeholder="搜索学段或班级"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
              />
            </div>
          </div>
          {filteredGroups.map((stage) => {
            const expanded = !!normalizedQuery || !collapsed.has(stage.id);
            return (
              <div key={stage.id}>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  aria-expanded={expanded}
                  className="h-8 w-full justify-start gap-2 px-2 font-semibold"
                  onClick={() =>
                    setCollapsed((current) => {
                      const next = new Set(current);
                      if (next.has(stage.id)) next.delete(stage.id);
                      else next.add(stage.id);
                      return next;
                    })
                  }
                >
                  <ChevronRight
                    aria-hidden="true"
                    className={`h-3.5 w-3.5 ${expanded ? 'rotate-90' : ''}`}
                  />
                  <span className="truncate">{stage.name}</span>
                </Button>
                {expanded && (
                  <div
                    role="group"
                    aria-label={stage.name}
                    className="ml-3 border-l border-border pl-2"
                  >
                    {stage.classes.length ? (
                      stage.classes.map((schoolClass) => {
                        const isSelected = schoolClass.id === value;
                        return (
                          <Button
                            key={schoolClass.id}
                            type="button"
                            variant="ghost"
                            size="sm"
                            aria-pressed={isSelected}
                            className={`h-8 w-full justify-between gap-2 px-2 text-left ${
                              isSelected
                                ? 'border border-brand-accent bg-selection font-semibold text-ink hover:bg-selection'
                                : 'text-ink'
                            }`}
                            style={
                              isSelected
                                ? { color: 'var(--color-ink)' }
                                : undefined
                            }
                            onClick={() => {
                              onChange(schoolClass.id);
                              setOpen(false);
                            }}
                          >
                            <span className="truncate">{schoolClass.name}</span>
                            <Check
                              aria-hidden="true"
                              className={`h-3.5 w-3.5 shrink-0 ${
                                isSelected ? 'text-brand-accent' : 'opacity-0'
                              }`}
                            />
                          </Button>
                        );
                      })
                    ) : (
                      <p className="px-2 py-1 text-xs text-ink-secondary">
                        暂无班级
                      </p>
                    )}
                  </div>
                )}
              </div>
            );
          })}
          {normalizedQuery && filteredGroups.length === 0 && (
            <p className="px-2 py-3 text-center text-xs text-ink-secondary">
              没有匹配的学段或班级
            </p>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}

interface TemporaryAdjustmentsPageProps {
  termId: string | null;
}

export const TemporaryAdjustmentsPage: React.FC<
  TemporaryAdjustmentsPageProps
> = ({ termId }) => {
  const toolbarRef = useStickyToolbar<HTMLElement>();
  const { resolvedDark, schoolName, setSelectedSection, refreshTermData } = useAppStore();

  const [state, setState] = useState<TemporaryTimetableState | null>(null);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  // Tab & View filter state
  const [recordsTab, setRecordsTab] = useState(false);
  const [teacherView, setTeacherView] = useState(false);
  const [classId, setClassId] = useState<string | null>(null);
  const [teacherId, setTeacherId] = useState<string | null>(null);
  const [weekIndex, setWeekIndex] = useState<number>(0);

  // Adjustment creation state
  const [source, setSource] = useState<ActualLesson | null>(null);
  const [kind, setKind] = useState<AdjustmentKind | null>(null);
  const [swapKey, setSwapKey] = useState<string | null>(null);
  const [moveDate, setMoveDate] = useState<string | null>(null);
  const [movePosition, setMovePosition] = useState<SchedulePosition | null>(
    null
  );
  const [substituteTeacherId, setSubstituteTeacherId] = useState<string | null>(
    null
  );
  const [substituteSubjectId, setSubstituteSubjectId] = useState<string | null>(
    null
  );
  const [reason, setReason] = useState('');
  const [draggingLessonKey, setDraggingLessonKey] = useState<string | null>(
    null
  );

  // Dialogs state
  const [substituteDialogOpen, setSubstituteDialogOpen] = useState(false);
  const [previewDialogOpen, setPreviewDialogOpen] = useState(false);
  const [activeSupervision, setActiveSupervision] =
    useState<ActualSupervision | null>(null);
  const [detailRecord, setDetailRecord] =
    useState<TemporaryAdjustmentRecord | null>(null);
  const [cancelRecord, setCancelRecord] =
    useState<TemporaryAdjustmentRecord | null>(null);

  // Records Tab filters
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);
  const [filterKind, setFilterKind] = useState<string>('all');
  const [filterStatus, setFilterStatus] = useState<AdjustmentRecordStatus | 'all'>('all');
  const [filterClassId, setFilterClassId] = useState<string>('all');
  const [filterTeacherId, setFilterTeacherId] = useState<string>('all');
  const [filterStartDate, setFilterStartDate] = useState<string | null>(null);
  const [filterEndDate, setFilterEndDate] = useState<string | null>(null);
  const [datePopoverOpen, setDatePopoverOpen] = useState(false);
  const [draftStartDate, setDraftStartDate] = useState<string | null>(null);
  const [draftEndDate, setDraftEndDate] = useState<string | null>(null);

  const reloadTimetable = useCallback(
    async (preserveWeek = true) => {
      if (!termId) {
        setState(null);
        return;
      }
      setLoading(true);
      setLoadError(null);
      try {
        const nextState = await schoolRepository.loadTemporaryTimetable(termId);
        setState(nextState);
        setClassId((prev) =>
          prev && nextState.snapshot.classes.some((c) => c.id === prev)
            ? prev
            : nextState.snapshot.classes[0]?.id ?? null
        );
        setTeacherId((prev) =>
          prev && nextState.snapshot.teachers.some((t) => t.id === prev)
            ? prev
            : nextState.snapshot.teachers[0]?.id ?? null
        );
        setWeekIndex((prev) =>
          preserveWeek
            ? clampWeekIndex(prev, nextState.snapshot.term)
            : defaultWeekIndex(nextState.snapshot.term)
        );
      } catch (e) {
        setLoadError(e instanceof Error ? e.message : String(e));
      } finally {
        setLoading(false);
      }
    },
    [termId]
  );

  useEffect(() => {
    setSource(null);
    setKind(null);
    reloadTimetable(false);
  }, [termId, reloadTimetable]);

  const clearAdjustmentDraft = useCallback(() => {
    setSource(null);
    setKind(null);
    setSwapKey(null);
    setMoveDate(null);
    setMovePosition(null);
    setSubstituteTeacherId(null);
    setSubstituteSubjectId(null);
    setReason('');
  }, []);

  const selectLessonForAdjustment = useCallback(
    (lesson: ActualLesson, initialKind: AdjustmentKind = 'swap') => {
      if (state?.reconciliationPending) return;
      setSource(lesson);
      setKind(initialKind);
      setSwapKey(null);
      setMoveDate(null);
      setMovePosition(null);
      setSubstituteTeacherId(null);
      setSubstituteSubjectId(lesson.item.subjectId);
      setReason('');
    },
    [state?.reconciliationPending]
  );

  const switchAdjustmentKind = (nextKind: AdjustmentKind) => {
    setKind(nextKind);
    setSwapKey(null);
    setMoveDate(null);
    setMovePosition(null);
    if (nextKind === 'substitute' && source) {
      setSubstituteSubjectId(source.item.subjectId);
    }
  };

  // Sync current source lesson reference after state reloads
  useEffect(() => {
    if (!state || !source) return;
    const updated = state.lessons.find((l) => l.key === source.key);
    if (!updated) {
      clearAdjustmentDraft();
    } else if (updated !== source) {
      setSource(updated);
    }
  }, [state, source, clearAdjustmentDraft]);

  const classGroups = useMemo<StageClassGroup[]>(() => {
    if (!state) return [];
    const stages = [...state.snapshot.stages].sort(
      (a, b) => a.sortOrder - b.sortOrder
    );
    const gradeById = new Map(state.snapshot.grades.map((g) => [g.id, g]));
    return stages.map((st) => ({
      id: st.id,
      name: st.name,
      classes: [...state.snapshot.classes]
        .filter((cls) => gradeById.get(cls.gradeId)?.stageId === st.id)
        .sort(
          (a, b) =>
            (gradeById.get(a.gradeId)?.sortOrder ?? 0) -
              (gradeById.get(b.gradeId)?.sortOrder ?? 0) ||
            a.sortOrder - b.sortOrder
        )
        .map((cls) => ({
          id: cls.id,
          name: getClassDisplayName(
            cls.id,
            state.snapshot.classes,
            state.snapshot.grades
          ),
        })),
    }));
  }, [state]);

  const selectedClassId =
    classId ??
    classGroups.find((g) => g.classes.length > 0)?.classes[0]?.id ??
    state?.snapshot.classes[0]?.id ??
    null;
  const selectedTeacherId =
    teacherId ?? state?.snapshot.teachers[0]?.id ?? null;

  const activeStageId = useMemo(() => {
    if (!state || !selectedClassId) return undefined;
    return state.stageIdForClass(selectedClassId);
  }, [state, selectedClassId]);

  const activeRoutine = useMemo(() => {
    if (!state) return undefined;
    if (activeStageId) {
      return state.snapshot.routines.find((r) => r.stageId === activeStageId);
    }
    return state.snapshot.routines[0];
  }, [state, activeStageId]);

  const weekStartYmd = useMemo(() => {
    if (!state) return formatDateYmd(new Date());
    return getWeekStartDate(state.snapshot.term, weekIndex);
  }, [state, weekIndex]);

  const weekEndYmd = useMemo(() => {
    const d = parseLocalDate(weekStartYmd);
    d.setDate(d.getDate() + 6);
    return formatDateYmd(d);
  }, [weekStartYmd]);

  const visibleDates = useMemo(() => {
    if (!state) return [];
    return getVisibleScheduleDates(
      state,
      teacherView ? undefined : activeRoutine,
      weekStartYmd
    );
  }, [state, teacherView, activeRoutine, weekStartYmd]);

  // Pre-warm Web Worker state when state changes
  useEffect(() => {
    if (!state) return;
    temporaryAdjustmentsWorkerClient.ensureSynced(state).catch(() => {});
  }, [state]);

  const [swapCandidates, setSwapCandidates] = useState<
    Map<string, ActualChangePreview>
  >(() => new Map());
  const [moveCandidates, setMoveCandidates] = useState<
    Map<string, CandidateMoveSlot>
  >(() => new Map());
  const [candidatesComputing, setCandidatesComputing] = useState(false);

  useEffect(() => {
    if (!state || !source || (kind !== 'swap' && kind !== 'move')) {
      setSwapCandidates(new Map());
      setMoveCandidates(new Map());
      setCandidatesComputing(false);
      return;
    }
    let cancelled = false;
    setCandidatesComputing(true);
    temporaryAdjustmentsWorkerClient
      .computeWeekCandidates({
        state,
        sourceKey: source.key,
        kind,
        stageId: activeRoutine?.stageId,
        visibleDates,
      })
      .then((res) => {
        if (cancelled) return;
        setSwapCandidates(res.swapCandidates);
        setMoveCandidates(res.moveCandidates);
        setCandidatesComputing(false);
      })
      .catch(() => {
        if (!cancelled) setCandidatesComputing(false);
      });
    return () => {
      cancelled = true;
    };
  }, [state, source, kind, activeRoutine?.stageId, visibleDates]);

  const [panelReady, setPanelReady] = useState(false);

  useEffect(() => {
    if (!source || !kind || !state) {
      setPanelReady(false);
      return;
    }
    if (kind === 'swap') {
      if (!swapKey) {
        setPanelReady(false);
        return;
      }
      const cached = swapCandidates.get(swapKey);
      if (cached) {
        setPanelReady(cached.errors.length === 0 && cached.changes.length > 0);
        return;
      }
      let cancelled = false;
      temporaryAdjustmentsWorkerClient
        .computeAdjustmentPreview({
          state,
          kind: 'swap',
          sourceKey: source.key,
          swapKey,
        })
        .then((preview) => {
          if (!cancelled) {
            setPanelReady(
              preview.errors.length === 0 && preview.changes.length > 0
            );
          }
        })
        .catch(() => {
          if (!cancelled) setPanelReady(false);
        });
      return () => {
        cancelled = true;
      };
    }
    if (kind === 'move') {
      if (!moveDate || !movePosition) {
        setPanelReady(false);
        return;
      }
      const key = `${moveDate}:${movePosition.periodTypeId}:${movePosition.lessonIndex}`;
      const cached = moveCandidates.get(key)?.preview;
      if (cached) {
        setPanelReady(cached.errors.length === 0 && cached.changes.length > 0);
        return;
      }
      let cancelled = false;
      temporaryAdjustmentsWorkerClient
        .computeAdjustmentPreview({
          state,
          kind: 'move',
          sourceKey: source.key,
          moveDate,
          movePosition,
        })
        .then((preview) => {
          if (!cancelled) {
            setPanelReady(
              preview.errors.length === 0 && preview.changes.length > 0
            );
          }
        })
        .catch(() => {
          if (!cancelled) setPanelReady(false);
        });
      return () => {
        cancelled = true;
      };
    }
    if (kind === 'substitute') {
      if (!substituteTeacherId) {
        setPanelReady(false);
        return;
      }
      let cancelled = false;
      temporaryAdjustmentsWorkerClient
        .computeAdjustmentPreview({
          state,
          kind: 'substitute',
          sourceKey: source.key,
          substituteTeacherId,
          substituteSubjectId: substituteSubjectId ?? source.item.subjectId,
        })
        .then((preview) => {
          if (!cancelled) {
            setPanelReady(
              preview.errors.length === 0 && preview.changes.length > 0
            );
          }
        })
        .catch(() => {
          if (!cancelled) setPanelReady(false);
        });
      return () => {
        cancelled = true;
      };
    }
    setPanelReady(false);
  }, [
    source,
    kind,
    state,
    swapKey,
    swapCandidates,
    moveDate,
    movePosition,
    moveCandidates,
    substituteTeacherId,
    substituteSubjectId,
  ]);

  const filteredRecords = useMemo(() => filterAdjustmentRecords(state?.records ?? [], {
    kind: filterKind,
    status: filterStatus,
    classId: filterClassId,
    teacherId: filterTeacherId,
    startDate: filterStartDate,
    endDate: filterEndDate,
  }), [state, filterKind, filterStatus, filterClassId, filterTeacherId, filterStartDate, filterEndDate]);

  // Pre-checks
  if (!termId) {
    return <p className="schedule-empty">请先创建或选择学期。</p>;
  }

  if (loading && !state) {
    return (
      <p className="schedule-empty" role="status">
        正在读取实际课表与调代课数据…
      </p>
    );
  }

  if (loadError && !state) {
    return (
      <div className="schedule-panel schedule-empty">
        <p role="alert">{loadError}</p>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="mt-2"
          onClick={() => reloadTimetable(true)}
        >
          重试
        </Button>
      </div>
    );
  }

  if (!state) return null;

  const { term } = state.snapshot;
  if (!term.firstTeachingWeekStart) {
    return (
      <section className="schedule-panel schedule-empty">
        <p className="font-semibold text-ink">
          请先在「学期与日历」中设置第 1 教学周起始日期
        </p>
        <Button
          variant="ghost"
          size="sm"
          className="mt-2"
          onClick={() => setSelectedSection('terms')}
        >
          前往学期与日历
        </Button>
      </section>
    );
  }

  if (state.snapshot.classes.length === 0) {
    return (
      <section className="schedule-panel schedule-empty">
        <p className="font-semibold text-ink">请先在「班级与学段」中添加班级</p>
        <Button
          variant="ghost"
          size="sm"
          className="mt-2"
          onClick={() => setSelectedSection('classes')}
        >
          前往班级与学段
        </Button>
      </section>
    );
  }

  const todayYmd = formatDateYmd(new Date());
  const weekCycleLabel =
    term.cycleMode === 'alternating'
      ? (weekIndex + 1) % 2 === 1
        ? '单周'
        : '双周'
      : '每周';
  const termStart = getWeekStartDate(term, 0);
  const termEnd = getTermEndDate(term);

  const classOptions = state.snapshot.classes.map((c) => ({
    value: c.id,
    label: getClassDisplayName(
      c.id,
      state.snapshot.classes,
      state.snapshot.grades
    ),
  }));

  const teacherOptions = state.snapshot.teachers.map((t) => ({
    value: t.id,
    label: getTeacherNameById(t.id, state.snapshot.teachers),
  }));

  const handleExportRecords = async () => {
    if (exporting || loading || filteredRecords.length === 0) return;
    setExporting(true);
    setExportError(null);
    const filterLabel = [
      filterKind === 'all' ? '全部类型' : adjustmentKindLabel(filterKind),
      filterStatus === 'all' ? '全部状态' : adjustmentStatusLabels[filterStatus],
      classOptions.find((option) => option.value === filterClassId)?.label ?? '全部班级',
      teacherOptions.find((option) => option.value === filterTeacherId)?.label ?? '全部教师',
      filterStartDate || filterEndDate
        ? `${filterStartDate ?? '不限'} 至 ${filterEndDate ?? '不限'}`
        : '全部日期',
    ].join(' · ');
    try {
      const { exportTemporaryAdjustments } = await import('./temporaryAdjustmentWorkbook');
      await exportTemporaryAdjustments(state, filteredRecords, {
        schoolName,
        filterLabel,
        startDate: filterStartDate,
        endDate: filterEndDate,
      });
    } catch (error) {
      setExportError(`导出 Excel 失败，${error instanceof Error ? error.message : String(error)}`);
    } finally {
      setExporting(false);
    }
  };

  const selectedClassName = selectedClassId
    ? getClassDisplayName(
        selectedClassId,
        state.snapshot.classes,
        state.snapshot.grades
      )
    : '班级课表';
  const selectedTeacherName = selectedTeacherId
    ? getTeacherNameById(selectedTeacherId, state.snapshot.teachers)
    : '教师课表';

  const gridFootNote = () => {
    if (teacherView) {
      return '点击任意课次可切换至对应班级发起调整';
    }
    if (!source) {
      return '点击任意课格发起调整；';
    }
    if (kind === 'swap') {
      return '选择标有高亮的课次；';
    }
    if (kind === 'move') {
      return '选择标有“＋ 移入此位”的空课位；';
    }
    return '在右侧面板选择代课教师';
  };

  const handleCommitAdjustment = async (params: {
    rangeMode: boolean;
    rangeStart: string | null;
    rangeEnd: string | null;
    excludedDates: Set<string>;
  }) => {
    if (!source || !kind) return;
    if (kind === 'swap' && swapKey) {
      await schoolRepository.commitTemporarySwap({
        termId: term.id,
        expectedRevision: state.revision,
        request: {
          firstKey: source.key,
          secondKey: swapKey,
          reason,
          rangeStart: params.rangeStart,
          rangeEnd: params.rangeEnd,
          excludedDates: params.excludedDates,
        },
      });
    } else if (kind === 'move' && moveDate && movePosition) {
      await schoolRepository.commitTemporaryMove({
        termId: term.id,
        expectedRevision: state.revision,
        request: {
          sourceKey: source.key,
          targetDate: moveDate,
          targetPosition: movePosition,
          reason,
          rangeStart: params.rangeStart,
          rangeEnd: params.rangeEnd,
          excludedDates: params.excludedDates,
        },
      });
    } else if (kind === 'substitute' && substituteTeacherId) {
      await schoolRepository.commitTemporarySubstitute({
        termId: term.id,
        expectedRevision: state.revision,
        request: {
          sourceKey: source.key,
          teacherId: substituteTeacherId,
          subjectId: substituteSubjectId ?? source.item.subjectId,
          reason,
          rangeStart: params.rangeStart,
          rangeEnd: params.rangeEnd,
          excludedDates: params.excludedDates,
        },
      });
    }
    clearAdjustmentDraft();
    await reloadTimetable(true);
    await refreshTermData(term.id);
  };

  const handleCommitSupervisionSubstitute = async (params: {
    date: string;
    postId: string;
    teacherId: string;
    reason: string;
  }) => {
    await schoolRepository.commitTemporarySupervisionSubstitute({
      termId: term.id,
      expectedRevision: state.revision,
      request: params,
    });
    await reloadTimetable(true);
    await refreshTermData(term.id);
  };

  const handleConfirmCancelRecord = async (
    record: TemporaryAdjustmentRecord
  ) => {
    await schoolRepository.cancelTemporaryAdjustment({
      termId: term.id,
      adjustmentId: record.id,
      expectedRevision: state.revision,
    });
    await reloadTimetable(true);
    await refreshTermData(term.id);
  };

  const sourceLocked =
    source != null &&
    state.snapshot.locks.some(
      (l) =>
        (l.scope === 'class' && l.targetId === source.item.classId) ||
        (l.scope === 'teacher' && l.targetId === source.item.teacherId)
    );

  const sourceActiveRecord =
    source != null ? findActiveRecordForLesson(state, source) : null;

  const selectedSwapTargetLesson =
    swapKey != null
      ? state.lessons.find((l) => l.key === swapKey) ?? null
      : null;

  const visibleClassLessonsCount = !teacherView
    ? state.lessons.filter(
        (l) =>
          l.item.classId === selectedClassId && visibleDates.includes(l.date)
      ).length
    : state.lessons.filter(
        (l) =>
          l.item.teacherId === selectedTeacherId &&
          visibleDates.includes(l.date)
      ).length;

  return (
    <TooltipProvider delayDuration={120}>
      <div
        className="schedule-page"
        onKeyDown={(event) => {
          const target = event.target;
          const insideOverlay =
            target instanceof HTMLElement &&
            target.closest(
              '[role="dialog"], [role="listbox"], [role="menu"], input, textarea'
            );
          if (event.key === 'Escape' && !insideOverlay && source) {
            clearAdjustmentDraft();
          }
        }}
      >
        {/* 1. 顶部吸顶玻璃工具栏（与「排课与课表」风格完全一致） */}
        <section
          ref={toolbarRef}
          className="schedule-panel schedule-sticky-toolbar sticky-glass-toolbar shadow-sm"
          aria-label="调代课工具栏"
        >
          <div className="schedule-toolbar">
            <Tabs
              value={recordsTab ? 'records' : 'timetable'}
              onValueChange={(val) => setRecordsTab(val === 'records')}
            >
              <TabsList
                aria-label="调代课视图模式"
                className="h-8 rounded-control bg-table-header p-0.5"
              >
                <TabsTrigger
                  value="timetable"
                  className="h-7 px-2.5 py-0.5 text-[12px]"
                >
                  实际课表
                </TabsTrigger>
                <TabsTrigger
                  value="records"
                  className="h-7 px-2.5 py-0.5 text-[12px] gap-1.5"
                >
                  <span>调整记录</span>
                  <span
                    className={`rounded-full px-1.5 py-0.2 text-[10.5px] font-semibold tabular-nums ${
                      recordsTab
                        ? 'bg-selection text-primary'
                        : 'bg-surface/80 text-ink-secondary'
                    }`}
                  >
                    {filteredRecords.length}
                  </span>
                </TabsTrigger>
              </TabsList>
            </Tabs>

            {!recordsTab && (
              <Tabs
                value={teacherView ? 'teacher' : 'class'}
                onValueChange={(val) => {
                  const isTeacher = val === 'teacher';
                  setTeacherView(isTeacher);
                  if (isTeacher) clearAdjustmentDraft();
                }}
              >
                <TabsList
                  aria-label="课表类型"
                  className="h-8 rounded-control bg-table-header p-0.5"
                >
                  <TabsTrigger
                    value="class"
                    className="h-7 px-2.5 py-0.5 text-[12px]"
                  >
                    班级课表
                  </TabsTrigger>
                  <TabsTrigger
                    value="teacher"
                    className="h-7 px-2.5 py-0.5 text-[12px]"
                  >
                    教师课表
                  </TabsTrigger>
                </TabsList>
              </Tabs>
            )}

            <div className="schedule-toolbar-group ml-auto">
              {!recordsTab ? (
                <>
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    disabled={weekIndex <= 0}
                    onClick={() =>
                      setWeekIndex((w) => clampWeekIndex(w - 1, term))
                    }
                    title="上一周"
                    className="h-8 w-8"
                  >
                    <ChevronLeft className="h-4 w-4" />
                  </Button>

                  <div className="px-1.5 text-[12.5px] text-ink flex items-center gap-1.5">
                    <span className="font-semibold">
                      第{weekIndex + 1}教学周 · {weekCycleLabel}
                    </span>
                    <span className="text-ink-secondary tabular-nums">
                      {formatShortMd(weekStartYmd)}–{formatShortMd(weekEndYmd)}
                    </span>
                  </div>

                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    disabled={weekIndex + 1 >= term.teachingWeekCount}
                    onClick={() =>
                      setWeekIndex((w) => clampWeekIndex(w + 1, term))
                    }
                    title="下一周"
                    className="h-8 w-8"
                  >
                    <ChevronRight className="h-4 w-4" />
                  </Button>

                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => setWeekIndex(defaultWeekIndex(term))}
                    className="h-8 px-2.5 text-[12px]"
                  >
                    本周
                  </Button>
                </>
              ) : (
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  disabled={loading || exporting || filteredRecords.length === 0}
                  aria-busy={exporting}
                  onClick={handleExportRecords}
                >
                  <Download aria-hidden="true" />
                  {exporting ? '正在导出…' : '导出Excel'}
                </Button>
              )}
            </div>
          </div>

          <div className="schedule-toolbar border-t border-dashed">
            {!recordsTab ? (
              <>
                <div className="schedule-toolbar-group">
                  {!teacherView ? (
                    <StageClassTreeSelect
                      groups={classGroups}
                      value={selectedClassId ?? ''}
                      onChange={(val) => {
                        setClassId(val);
                        clearAdjustmentDraft();
                      }}
                    />
                  ) : (
                    <SearchableSelect
                      ariaLabel="教师"
                      className="h-8 w-auto min-w-[9rem] max-w-[15rem]"
                      value={selectedTeacherId ?? ''}
                      onValueChange={(val) => setTeacherId(val)}
                      options={teacherOptions}
                      placeholder="选择教师"
                      searchPlaceholder="搜索教师"
                    />
                  )}
                </div>

                {source && (
                  <div className="schedule-toolbar-group ml-auto text-xs">
                    <div className="inline-flex items-center gap-1.5">
                      <span className="w-[18px] h-[18px] rounded-full bg-success-surface border border-success text-success flex items-center justify-center">
                        <Check className="w-3 h-3" />
                      </span>
                      <span className="font-medium text-ink">选择课次</span>
                    </div>

                    <span className="w-3 h-px bg-border" />

                    <div className="inline-flex items-center gap-1.5">
                      {panelReady ? (
                        <span className="w-[18px] h-[18px] rounded-full bg-success-surface border border-success text-success flex items-center justify-center">
                          <Check className="w-3 h-3" />
                        </span>
                      ) : (
                        <span className="w-[18px] h-[18px] rounded-full bg-primary text-white text-[11px] font-bold flex items-center justify-center">
                          2
                        </span>
                      )}
                      <span
                        className={
                          panelReady
                            ? 'font-medium text-ink'
                            : 'font-bold text-primary'
                        }
                      >
                        选择目标
                      </span>
                    </div>

                    <span className="w-3 h-px bg-border" />

                    <div className="inline-flex items-center gap-1.5">
                      <span
                        className={`w-[18px] h-[18px] rounded-full text-[11px] font-bold flex items-center justify-center ${
                          panelReady
                            ? 'bg-primary text-white'
                            : 'bg-table-header border border-border text-ink-secondary'
                        }`}
                      >
                        3
                      </span>
                      <span
                        className={
                          panelReady
                            ? 'font-bold text-primary'
                            : 'font-medium text-ink-secondary'
                        }
                      >
                        确认生效
                      </span>
                    </div>

                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      onClick={clearAdjustmentDraft}
                      className="h-7 px-2 text-xs"
                    >
                      取消调整
                    </Button>
                  </div>
                )}
              </>
            ) : (
              /* 调整记录 Tab 筛选栏 */
              <div className="schedule-toolbar-group">
                <SelectField
                  ariaLabel="调整类型"
                  className="h-8 w-auto min-w-[7.5rem]"
                  value={filterKind}
                  onValueChange={setFilterKind}
                  options={[
                    { value: 'all', label: '全部类型' },
                    { value: 'swap', label: '换课' },
                    { value: 'move', label: '移课' },
                    { value: 'substitute', label: '代课' },
                    {
                      value: SUPERVISION_SUBSTITUTION_KIND,
                      label: '带班替班',
                    },
                  ]}
                />

                <SelectField
                  ariaLabel="调整状态"
                  className="h-8 w-auto min-w-[7.5rem]"
                  value={filterStatus}
                  onValueChange={(value) => setFilterStatus(value as typeof filterStatus)}
                  options={[
                    { value: 'all', label: '全部状态' },
                    ...Object.entries(adjustmentStatusLabels).map(([value, label]) => ({ value, label })),
                  ]}
                />

                <SearchableSelect
                  ariaLabel="筛选班级"
                  className="h-8 w-auto min-w-[8.5rem] max-w-[14rem]"
                  value={filterClassId}
                  onValueChange={setFilterClassId}
                  options={[
                    { value: 'all', label: '全部班级' },
                    ...classOptions,
                  ]}
                  placeholder="全部班级"
                  searchPlaceholder="搜索班级"
                />

                <SearchableSelect
                  ariaLabel="筛选教师"
                  className="h-8 w-auto min-w-[8.5rem] max-w-[14rem]"
                  value={filterTeacherId}
                  onValueChange={setFilterTeacherId}
                  options={[
                    { value: 'all', label: '全部教师' },
                    ...teacherOptions,
                  ]}
                  placeholder="全部教师"
                  searchPlaceholder="搜索教师"
                />

                <Popover
                  open={datePopoverOpen}
                  onOpenChange={(open) => {
                    if (open) {
                      setDraftStartDate(filterStartDate ?? termStart);
                      setDraftEndDate(filterEndDate ?? termEnd);
                    }
                    setDatePopoverOpen(open);
                  }}
                >
                  <PopoverTrigger asChild>
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      className="h-8 gap-1.5 px-2.5 text-xs"
                    >
                      <CalendarIcon className="w-3.5 h-3.5 text-ink-secondary" />
                      <span>
                        {filterStartDate && filterEndDate
                          ? `${filterStartDate} 至 ${filterEndDate}`
                          : '全部日期'}
                      </span>
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-72 p-3 space-y-3" align="start">
                    <div className="text-xs font-semibold text-ink">
                      按日期范围筛选
                    </div>
                    <div className="space-y-2">
                      <div className="space-y-1">
                        <Label className="text-xs text-ink-secondary">
                          开始日期
                        </Label>
                        <DatePicker
                          value={draftStartDate ?? termStart}
                          min={termStart}
                          max={draftEndDate ?? termEnd}
                          onChange={(val) => setDraftStartDate(val)}
                        />
                      </div>
                      <div className="space-y-1">
                        <Label className="text-xs text-ink-secondary">
                          结束日期
                        </Label>
                        <DatePicker
                          value={draftEndDate ?? termEnd}
                          min={draftStartDate ?? termStart}
                          max={termEnd}
                          onChange={(val) => setDraftEndDate(val)}
                        />
                      </div>
                    </div>
                    <div className="flex items-center justify-end gap-2 pt-1">
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => {
                          setFilterStartDate(null);
                          setFilterEndDate(null);
                          setDatePopoverOpen(false);
                        }}
                      >
                        清除
                      </Button>
                      <Button
                        type="button"
                        size="sm"
                        onClick={() => {
                          setFilterStartDate(draftStartDate);
                          setFilterEndDate(draftEndDate);
                          setDatePopoverOpen(false);
                        }}
                      >
                        确定
                      </Button>
                    </div>
                  </PopoverContent>
                </Popover>

                {(filterStartDate || filterEndDate) && (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => {
                      setFilterStartDate(null);
                      setFilterEndDate(null);
                    }}
                    className="h-8 px-2 text-xs text-primary"
                  >
                    清除日期
                  </Button>
                )}
              </div>
            )}
          </div>
        </section>

        {/* 2. 待协调提示条 */}
        {state.reconciliationPending && (
          <div
            className="schedule-alert flex flex-wrap items-center gap-2"
            role="status"
          >
            <AlertTriangle className="w-4 h-4 shrink-0" />
            <span>
              {state.hasSupervisionCalendar
                ? '课表待协调。可取消有冲突的已有调整，完成协调后可新增调整。'
                : '课表待协调，完成协调后才能进行临时调整。'}
            </span>
          </div>
        )}

        {recordsTab && exportError && (
          <p className="schedule-alert" role="alert">{exportError}</p>
        )}

        {/* 3. 主内容区 */}
        {recordsTab ? (
          /* ==================== 调整记录列表视图 ==================== */
          <section className="schedule-panel overflow-hidden">
            <div className="hidden lg:grid lg:grid-cols-12 h-10 px-4 bg-table-header border-b border-border items-center text-xs font-semibold text-ink-secondary gap-3">
              <div className="col-span-2">调整时间</div>
              <div className="col-span-1">类型</div>
              <div className="col-span-2">班级</div>
              <div className="col-span-3">调整内容</div>
              <div className="col-span-1">涉及教师</div>
              <div className="col-span-1">原因</div>
              <div className="col-span-1">状态</div>
              <div className="col-span-1 text-right">操作</div>
            </div>

            {filteredRecords.length === 0 ? (
              <div className="py-12 text-center text-sm text-ink-secondary">
                暂无符合筛选条件的调整记录
              </div>
            ) : (
              <div className="divide-y divide-border">
                {filteredRecords.map((record) => {
                  const classLabels = recordClassIds(record).map((cid) =>
                    getClassDisplayName(
                      cid,
                      state.snapshot.classes,
                      state.snapshot.grades
                    )
                  );
                  const teacherLabels = recordTeacherIds(record).map((tid) =>
                    getTeacherNameById(tid, state.snapshot.teachers)
                  );
                  const canCancel =
                    record.cancelledAt == null &&
                    (!state.reconciliationPending || record.needsAttention);

                  return (
                    <div
                      key={record.id}
                      className="p-4 lg:py-3.5 lg:px-4 lg:grid lg:grid-cols-12 lg:items-center gap-3 text-xs hover:bg-table-header/40 transition-colors"
                    >
                      <div className="col-span-2 text-ink-secondary tabular-nums">
                        {formatTimestampTime(record.createdAt)}
                      </div>
                      <div className="col-span-1 mt-1 lg:mt-0">
                        <span className="inline-flex px-2 py-0.5 rounded-full bg-selection text-primary font-semibold text-[11px]">
                          {adjustmentKindLabel(record.kind)}
                        </span>
                      </div>
                      <div className="col-span-2 mt-1 lg:mt-0 font-medium text-ink truncate">
                        {classLabels.join('、') || '—'}
                      </div>
                      <div className="col-span-3 mt-1 lg:mt-0 text-ink">
                        {describeRecordSummary(state, record)}
                      </div>
                      <div className="col-span-1 mt-1 lg:mt-0 text-ink-secondary truncate">
                        {teacherLabels.join('、') || '—'}
                      </div>
                      <div className="col-span-1 mt-1 lg:mt-0 text-ink-secondary truncate">
                        {record.reason.trim() || '—'}
                      </div>
                      <div className="col-span-1 mt-1 lg:mt-0">
                        {record.cancelledAt != null ? (
                          <span className="inline-flex px-2 py-0.5 rounded-full bg-table-header text-ink-secondary font-medium text-[11px]">
                            已取消
                          </span>
                        ) : record.needsAttention ? (
                          <span className="inline-flex px-2 py-0.5 rounded-full bg-warning-surface text-warning font-semibold text-[11px]">
                            需处理
                          </span>
                        ) : (
                          <span className="inline-flex px-2 py-0.5 rounded-full bg-success-surface text-success font-semibold text-[11px]">
                            有效
                          </span>
                        )}
                      </div>
                      <div className="col-span-1 mt-2 lg:mt-0 flex items-center justify-end gap-2.5">
                        <button
                          type="button"
                          onClick={() => setDetailRecord(record)}
                          className="text-primary hover:underline font-medium"
                        >
                          详情
                        </button>
                        {canCancel && (
                          <button
                            type="button"
                            onClick={() => setCancelRecord(record)}
                            className="text-destructive hover:underline font-medium"
                          >
                            取消
                          </button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </section>
        ) : (
          /* ==================== 实际课表 + 右侧发起调整面板 ==================== */
          <div className="flex flex-col xl:flex-row items-start gap-3">
            {/* 左侧本周课表面板（与「排课与课表」.schedule-panel.schedule-timetable-panel 保持一致） */}
            <section className="schedule-panel schedule-timetable-panel flex-1 min-w-0 w-full">
              <div className="schedule-timetable-heading">
                <h2>{!teacherView ? '课表安排' : selectedTeacherName}</h2>
                <span className="schedule-timetable-label">
                  {!teacherView
                    ? `${selectedClassName} · 第${weekIndex + 1}教学周（${weekCycleLabel}）`
                    : `教师实际课表 · 第${weekIndex + 1}教学周（${weekCycleLabel}）`}
                  {' · '}
                  {gridFootNote()}
                </span>
                <span className="schedule-timetable-count">
                  {visibleClassLessonsCount} 节课
                </span>
              </div>

              {visibleDates.length === 0 ? (
                <p className="schedule-empty">本周没有安排上课日。</p>
              ) : !teacherView ? (
                /* ---------- 班级视图网格（与 TimetableGrid 统一表格结构） ---------- */
                !activeRoutine ? (
                  <p className="schedule-empty">
                    当前班级所属学段尚未配置作息。
                  </p>
                ) : (
                  (() => {
                    const sortedPeriods = [
                      ...activeRoutine.periodTypes,
                    ].sort((a, b) => a.sortOrder - b.sortOrder);
                    const anchors = new Map(
                      activeRoutine.lessonTimes.map((row) => [
                        row.id,
                        `${row.periodTypeId}:${row.lessonIndex}`,
                      ])
                    );
                    const allRowKeys: string[] = [];
                    for (const p of sortedPeriods) {
                      const maxL = Math.max(
                        p.defaultLessonCount,
                        ...activeRoutine.dailyOverrides
                          .filter((o) => o.periodTypeId === p.id)
                          .map((o) => o.lessonCount),
                        0
                      );
                      for (let i = 1; i <= maxL; i++) {
                        allRowKeys.push(`${p.id}:${i}`);
                      }
                    }
                    const legacyAnchors = new Map(
                      allRowKeys.map((rk) => [rk.replace(':', '_'), rk])
                    );
                    const anchorFor = (row: CommonPeriod) =>
                      row.insertAfterLessonId &&
                      (anchors.get(row.insertAfterLessonId) ??
                        legacyAnchors.get(row.insertAfterLessonId) ??
                        row.insertAfterLessonId);
                    const insertedCommons = [
                      ...(activeRoutine.commonPeriods ?? []),
                    ].sort((a, b) => a.sortOrder - b.sortOrder);
                    const renderCommonRow = (row: CommonPeriod) => (
                      <tr key={`common_${row.id}`} className="schedule-common">
                        <td
                          colSpan={visibleDates.length + 1}
                          title={clockLabel(row.startMinute, row.endMinute)}
                        >
                          <div>{row.name}</div>
                        </td>
                      </tr>
                    );

                    return (
                      <div className="schedule-table-scroll">
                        <table
                          className="schedule-grid schedule-grid-cards schedule-grid-week"
                          aria-label={`${selectedClassName}本周实际课表`}
                        >
                          <thead>
                            <tr>
                              <th scope="col">节次</th>
                              {visibleDates.map((ymd) => {
                                const isoW = getIsoWeekday(ymd);
                                const isToday = ymd === todayYmd;
                                const ex = state.exceptions.find(
                                  (e) => e.date.slice(0, 10) === ymd
                                );
                                let exNote: string | null = null;
                                if (ex) {
                                  if (ex.kind === 'holiday') {
                                    exNote = ex.note.trim() || '休息日';
                                  } else {
                                    const mw = ex.makeupWeekday ?? isoW;
                                    exNote = `补 · 按${weekdayShortLabel(mw)}作息`;
                                  }
                                }
                                return (
                                  <th
                                    key={ymd}
                                    scope="col"
                                    data-axis-active={isToday || undefined}
                                  >
                                    <div className="inline-flex flex-wrap items-center justify-center gap-1">
                                      <span>{weekdayShortLabel(isoW)}</span>
                                      <span className="text-[11px] font-normal opacity-80 tabular-nums">
                                        {formatShortMd(ymd)}
                                      </span>
                                      {isToday && (
                                        <span className="rounded-full bg-selection px-1.5 py-0.2 text-[10px] font-bold text-primary">
                                          今天
                                        </span>
                                      )}
                                    </div>
                                    {exNote && (
                                      <small
                                        className={
                                          ex?.kind === 'holiday'
                                            ? 'text-ink-secondary'
                                            : 'text-warning font-semibold'
                                        }
                                      >
                                        {exNote}
                                      </small>
                                    )}
                                  </th>
                                );
                              })}
                            </tr>
                          </thead>
                          <tbody>
                            {insertedCommons
                              .filter((common) => !common.insertAfterLessonId)
                              .map(renderCommonRow)}
                            {sortedPeriods.flatMap((period) => {
                              const maxLessons = Math.max(
                                period.defaultLessonCount,
                                ...activeRoutine.dailyOverrides
                                  .filter((o) => o.periodTypeId === period.id)
                                  .map((o) => o.lessonCount),
                                0
                              );
                              const periodRows: React.ReactNode[] = [];

                              for (
                                let lessonIdx = 1;
                                lessonIdx <= maxLessons;
                                lessonIdx++
                              ) {
                                const rk = `${period.id}:${lessonIdx}`;
                                const lt = activeRoutine.lessonTimes.find(
                                  (t) =>
                                    t.periodTypeId === period.id &&
                                    t.lessonIndex === lessonIdx
                                );
                                const timeRange = clockLabel(
                                  lt?.startMinute ?? null,
                                  lt?.endMinute ?? null
                                );
                                const lessonLabel = `第${lessonIdx}节`;

                                periodRows.push(
                                  <tr key={rk}>
                                    <th scope="row">
                                      <div
                                        className="schedule-period-label"
                                        title={[
                                          period.name,
                                          lessonLabel,
                                          timeRange,
                                        ]
                                          .filter(Boolean)
                                          .join(' · ')}
                                      >
                                        <span>{period.name}</span>
                                        <small>
                                          {[lessonLabel, timeRange]
                                            .filter(Boolean)
                                            .join(' · ')}
                                        </small>
                                      </div>
                                    </th>

                                    {visibleDates.map((ymd) => {
                                      const scheduleW =
                                        getScheduleWeekdayForDate(
                                          state.exceptions,
                                          ymd
                                        );
                                      const isTeaching =
                                        scheduleW != null &&
                                        activeRoutine.teachingDays.some(
                                          (d) =>
                                            d.weekday === scheduleW &&
                                            d.isTeachingDay
                                        );
                                      const dayLessonCount =
                                        scheduleW != null
                                          ? effectiveLessonCountOnDay(
                                              activeRoutine,
                                              period.id,
                                              scheduleW
                                            )
                                          : 0;
                                      const slotAvailableOnDay =
                                        isTeaching &&
                                        lessonIdx <= dayLessonCount;

                                      const cellSupervisions =
                                        state.supervisions.filter(
                                          (sup) =>
                                            sup.date === ymd &&
                                            selectedClassId != null &&
                                            sup.classIds.includes(
                                              selectedClassId
                                            ) &&
                                            sup.occurrences.some(
                                              (occ) =>
                                                occ.position.stageId ===
                                                  activeRoutine.stageId &&
                                                occ.position.periodTypeId ===
                                                  period.id &&
                                                occ.position.lessonIndex ===
                                                  lessonIdx
                                            )
                                        );

                                      const lesson = state.lessons.find(
                                        (l) =>
                                          l.item.classId === selectedClassId &&
                                          l.date === ymd &&
                                          l.item.position?.periodTypeId ===
                                            period.id &&
                                          l.item.position?.lessonIndex ===
                                            lessonIdx
                                      );

                                      if (
                                        !lesson &&
                                        cellSupervisions.length === 0 &&
                                        !slotAvailableOnDay
                                      ) {
                                        return (
                                          <td
                                            key={ymd}
                                            className="schedule-no-slot"
                                            aria-label="未设课节"
                                          >
                                            —
                                          </td>
                                        );
                                      }

                                      if (!lesson) {
                                        const slotKey = `${ymd}:${period.id}:${lessonIdx}`;
                                        const moveCand =
                                          source && kind === 'move'
                                            ? moveCandidates.get(slotKey)
                                            : undefined;
                                        const targetPos: SchedulePosition =
                                          moveCand?.position ?? {
                                            stageId: activeRoutine.stageId,
                                            weekday: scheduleW ?? getIsoWeekday(ymd),
                                            periodTypeId: period.id,
                                            lessonIndex: lessonIdx,
                                            startMinute: lt?.startMinute ?? null,
                                            endMinute: lt?.endMinute ?? null,
                                          };
                                        const isChosenMoveTarget =
                                          source != null &&
                                          kind === 'move' &&
                                          sameMoveSlot(
                                            moveDate,
                                            movePosition,
                                            ymd,
                                            targetPos
                                          );
                                        const canMoveHere =
                                          moveCand != null &&
                                          moveCand.preview.errors.length === 0;
                                        const moveErrors =
                                          moveCand?.preview.errors ?? [];

                                        const emptySlotEl =
                                          source && kind === 'move' ? (
                                            <button
                                              type="button"
                                              disabled={
                                                !canMoveHere &&
                                                !isChosenMoveTarget
                                              }
                                              onClick={() => {
                                                if (canMoveHere) {
                                                  setMoveDate(ymd);
                                                  setMovePosition(targetPos);
                                                }
                                              }}
                                              className={`w-full min-h-[54px] h-full rounded-[8px] px-2.5 py-1.5 flex items-center justify-center text-xs transition-all duration-150 ${
                                                isChosenMoveTarget
                                                  ? 'border-2 border-success bg-success-surface text-success font-bold cursor-pointer shadow-sm'
                                                  : candidatesComputing &&
                                                    !moveCand
                                                  ? 'border-[1.5px] border-dashed border-border text-ink-secondary'
                                                  : canMoveHere
                                                  ? 'border-[1.5px] border-dashed border-primary bg-selection/40 text-primary font-semibold cursor-pointer hover:-translate-y-[1.5px] hover:bg-selection/80 hover:border-solid hover:shadow-[0_0_0_2px_var(--color-accent),0_6px_14px_color-mix(in_srgb,var(--color-accent)_16%,transparent)]'
                                                  : 'border-[1.5px] border-dashed border-border/70 bg-table-header/60 opacity-45 cursor-not-allowed'
                                              }`}
                                            >
                                              {isChosenMoveTarget
                                                ? '✓ 目标课位'
                                                : candidatesComputing &&
                                                  !moveCand
                                                ? ''
                                                : canMoveHere
                                                ? '＋ 移入此位'
                                                : ''}
                                            </button>
                                          ) : cellSupervisions.length === 0 ? (
                                            <span
                                              className="schedule-empty-slot"
                                              aria-hidden="true"
                                            />
                                          ) : null;

                                        return (
                                          <td
                                            key={ymd}
                                            onDragOver={(e) => {
                                              if (
                                                !state.reconciliationPending &&
                                                draggingLessonKey
                                              ) {
                                                e.preventDefault();
                                              }
                                            }}
                                            onDrop={(e) => {
                                              e.preventDefault();
                                              if (state.reconciliationPending) {
                                                return;
                                              }
                                              const droppedKey =
                                                e.dataTransfer.getData(
                                                  'text/plain'
                                                ) || draggingLessonKey;
                                              const dragged =
                                                state.lessons.find(
                                                  (l) => l.key === droppedKey
                                                );
                                              if (!dragged) return;
                                              setSource(dragged);
                                              setKind('move');
                                              setSwapKey(null);
                                              setMoveDate(ymd);
                                              setMovePosition(targetPos);
                                              setDraggingLessonKey(null);
                                            }}
                                          >
                                            <div className="schedule-slot">
                                              <div className="schedule-slot-content space-y-1">
                                                {cellSupervisions.map((sup) => {
                                                  const activeSupRec =
                                                    findActiveRecordForSupervision(
                                                      state,
                                                      sup
                                                    );
                                                  return (
                                                    <button
                                                      key={sup.key}
                                                      type="button"
                                                      disabled={
                                                        state.reconciliationPending
                                                      }
                                                      onClick={() =>
                                                        setActiveSupervision(sup)
                                                      }
                                                      className="schedule-lesson transition-all duration-150 hover:-translate-y-[1px] hover:border-primary/60 hover:shadow-sm"
                                                    >
                                                      <div className="flex items-center justify-between gap-1">
                                                        <strong>
                                                          {sup.post.name}
                                                        </strong>
                                                        <span className="rounded bg-selection px-1.5 py-0.2 text-[10px] font-semibold text-primary shrink-0">
                                                          {activeSupRec
                                                            ? '已替班'
                                                            : '带班'}
                                                        </span>
                                                      </div>
                                                      <small>
                                                        {sup.teacherName} · 带班
                                                      </small>
                                                    </button>
                                                  );
                                                })}
                                                {emptySlotEl &&
                                                source &&
                                                kind === 'move' &&
                                                !candidatesComputing &&
                                                !canMoveHere &&
                                                moveErrors.length > 0 ? (
                                                  <Tooltip>
                                                    <TooltipTrigger asChild>
                                                      {emptySlotEl}
                                                    </TooltipTrigger>
                                                    <TooltipContent className="max-w-xs text-xs">
                                                      {moveErrors.join('；')}
                                                    </TooltipContent>
                                                  </Tooltip>
                                                ) : (
                                                  emptySlotEl
                                                )}
                                              </div>
                                            </div>
                                          </td>
                                        );
                                      }

                                      // 有正课的课位格
                                      const subjectColor = getSubjectColor(
                                        lesson.item.subjectId,
                                        resolvedDark
                                      );
                                      const subjectName = getSubjectDisplayName(
                                        lesson.item.subjectId,
                                        state.snapshot.subjects
                                      );
                                      const teacherName = getTeacherNameById(
                                        lesson.item.teacherId,
                                        state.snapshot.teachers
                                      );
                                      const activeRec =
                                        findActiveRecordForLesson(
                                          state,
                                          lesson
                                        );

                                      const isSource =
                                        source?.key === lesson.key;
                                      const isChosenSwapTarget =
                                        source != null &&
                                        kind === 'swap' &&
                                        swapKey === lesson.key;
                                      const swapPreview =
                                        source && kind === 'swap' && !isSource
                                          ? swapCandidates.get(lesson.key)
                                          : undefined;
                                      const canSwapHere =
                                        swapPreview != null &&
                                        swapPreview.errors.length === 0;
                                      const swapErrors =
                                        swapPreview?.errors ?? [];
                                      const isSwapBlocked =
                                        source != null &&
                                        kind === 'swap' &&
                                        !isSource &&
                                        !isChosenSwapTarget &&
                                        !candidatesComputing &&
                                        !canSwapHere;

                                      const lessonBtn = (
                                        <button
                                          type="button"
                                          aria-pressed={isSource}
                                          aria-disabled={
                                            isSwapBlocked || undefined
                                          }
                                          draggable={
                                            !state.reconciliationPending
                                          }
                                          onDragStart={(e) => {
                                            setDraggingLessonKey(lesson.key);
                                            e.dataTransfer.setData(
                                              'text/plain',
                                              lesson.key
                                            );
                                          }}
                                          onDragEnd={() =>
                                            setDraggingLessonKey(null)
                                          }
                                          onClick={() => {
                                            if (state.reconciliationPending) {
                                              return;
                                            }
                                            if (!source) {
                                              selectLessonForAdjustment(
                                                lesson,
                                                'swap'
                                              );
                                              return;
                                            }
                                            if (isSource) {
                                              clearAdjustmentDraft();
                                              return;
                                            }
                                            if (kind === 'swap') {
                                              if (canSwapHere) {
                                                setSwapKey(lesson.key);
                                              }
                                              return;
                                            }
                                            selectLessonForAdjustment(
                                              lesson,
                                              kind ?? 'swap'
                                            );
                                          }}
                                          style={
                                            {
                                              '--lesson-bg': isSwapBlocked
                                                ? 'var(--color-table-header)'
                                                : subjectColor.background,
                                              '--lesson-ink': isSwapBlocked
                                                ? 'var(--color-ink-secondary)'
                                                : subjectColor.foreground,
                                              '--lesson-border': isSource
                                                ? 'var(--color-accent)'
                                                : isChosenSwapTarget
                                                ? 'var(--color-success)'
                                                : source &&
                                                  kind === 'swap' &&
                                                  !candidatesComputing
                                                ? canSwapHere
                                                  ? 'var(--color-accent)'
                                                  : 'var(--color-border)'
                                                : `${subjectColor.foreground}30`,
                                            } as React.CSSProperties
                                          }
                                          className={`schedule-lesson transition-all duration-150 ${
                                            isChosenSwapTarget
                                              ? 'ring-2 ring-success shadow-sm'
                                              : isSwapBlocked
                                              ? 'opacity-45 saturate-0 cursor-not-allowed'
                                              : source &&
                                                kind === 'swap' &&
                                                !isSource &&
                                                canSwapHere
                                              ? 'hover:-translate-y-[1.5px] hover:bg-selection/70 hover:shadow-[0_0_0_2px_var(--color-accent),0_6px_14px_color-mix(in_srgb,var(--color-accent)_18%,transparent)]'
                                              : !isSource
                                              ? 'hover:-translate-y-[1px] hover:border-primary/60 hover:shadow-sm'
                                              : ''
                                          }`}
                                        >
                                          <div className="flex items-start justify-between gap-1">
                                            <strong className="truncate">
                                              {subjectName}
                                            </strong>

                                            {isSource ? (
                                              <span className="px-1.5 py-0.2 rounded-full bg-primary text-white text-[10px] font-bold shrink-0">
                                                源课次
                                              </span>
                                            ) : isChosenSwapTarget ? (
                                              <span className="px-1.5 py-0.2 rounded-full bg-success text-white text-[10px] font-bold shrink-0">
                                                目标课次
                                              </span>
                                            ) : activeRec ? (
                                              <span className="px-1.5 py-0.2 rounded-full bg-surface/85 text-primary text-[10px] font-bold shrink-0">
                                                {adjustmentKindLabel(
                                                  activeRec.kind
                                                )}
                                              </span>
                                            ) : null}
                                          </div>

                                          <div className="mt-0.5 flex items-end justify-between gap-1">
                                            <small className="!mt-0 truncate">
                                              {teacherName}
                                            </small>
                                          </div>
                                        </button>
                                      );

                                      return (
                                        <td
                                          key={ymd}
                                          data-drag-source={
                                            isSource || undefined
                                          }
                                          onDragOver={(e) => {
                                            if (
                                              !state.reconciliationPending &&
                                              draggingLessonKey &&
                                              draggingLessonKey !== lesson.key
                                            ) {
                                              e.preventDefault();
                                            }
                                          }}
                                          onDrop={(e) => {
                                            e.preventDefault();
                                            if (state.reconciliationPending) {
                                              return;
                                            }
                                            const droppedKey =
                                              e.dataTransfer.getData(
                                                'text/plain'
                                              ) || draggingLessonKey;
                                            if (
                                              !droppedKey ||
                                              droppedKey === lesson.key
                                            ) {
                                              return;
                                            }
                                            const dragged = state.lessons.find(
                                              (l) => l.key === droppedKey
                                            );
                                            if (!dragged) return;
                                            setSource(dragged);
                                            setKind('swap');
                                            setMoveDate(null);
                                            setMovePosition(null);
                                            setSwapKey(lesson.key);
                                            setDraggingLessonKey(null);
                                          }}
                                        >
                                          <div className="schedule-slot">
                                            <div className="schedule-slot-content space-y-1">
                                              {cellSupervisions.map((sup) => {
                                                const activeSupRec =
                                                  findActiveRecordForSupervision(
                                                    state,
                                                    sup
                                                  );
                                                return (
                                                  <button
                                                    key={sup.key}
                                                    type="button"
                                                    disabled={
                                                      state.reconciliationPending
                                                    }
                                                    onClick={() =>
                                                      setActiveSupervision(sup)
                                                    }
                                                    className="schedule-lesson transition-all duration-150 hover:-translate-y-[1px] hover:border-primary/60 hover:shadow-sm"
                                                  >
                                                    <div className="flex items-center justify-between gap-1">
                                                      <strong>
                                                        {sup.post.name}
                                                      </strong>
                                                      <span className="rounded bg-selection px-1.5 py-0.2 text-[10px] font-semibold text-primary shrink-0">
                                                        {activeSupRec
                                                          ? '已替班'
                                                          : '带班'}
                                                      </span>
                                                    </div>
                                                    <small>
                                                      {sup.teacherName} · 带班
                                                    </small>
                                                  </button>
                                                );
                                              })}
                                              {isSwapBlocked &&
                                              swapErrors.length > 0 ? (
                                                <Tooltip>
                                                  <TooltipTrigger asChild>
                                                    {lessonBtn}
                                                  </TooltipTrigger>
                                                  <TooltipContent className="max-w-xs text-xs">
                                                    {swapErrors.join('；')}
                                                  </TooltipContent>
                                                </Tooltip>
                                              ) : (
                                                lessonBtn
                                              )}
                                            </div>
                                          </div>
                                        </td>
                                      );
                                    })}
                                  </tr>,
                                  ...insertedCommons
                                    .filter(
                                      (common) => anchorFor(common) === rk
                                    )
                                    .map(renderCommonRow)
                                );
                              }

                              return periodRows;
                            })}
                          </tbody>
                        </table>
                      </div>
                    );
                  })()
                )
              ) : (
                /* ---------- 教师视图网格（与 TimetableGrid 统一表格结构） ---------- */
                (() => {
                  const teacherLessons = state.lessons.filter(
                    (l) =>
                      l.item.teacherId === selectedTeacherId &&
                      visibleDates.includes(l.date)
                  );
                  const teacherRows = buildTeacherGridRows(
                    state,
                    teacherLessons
                  );
                  if (teacherRows.length === 0) {
                    return (
                      <p className="schedule-empty">
                        该教师本周暂无课表数据。
                      </p>
                    );
                  }
                  return (
                    <div className="schedule-table-scroll">
                      <table
                        className="schedule-grid schedule-grid-cards schedule-grid-week"
                        aria-label={`${selectedTeacherName}本周实际课表`}
                      >
                        <thead>
                          <tr>
                            <th scope="col">节次</th>
                            {visibleDates.map((ymd) => {
                              const isoW = getIsoWeekday(ymd);
                              const isToday = ymd === todayYmd;
                              return (
                                <th
                                  key={ymd}
                                  scope="col"
                                  data-axis-active={isToday || undefined}
                                >
                                  <div className="inline-flex flex-wrap items-center justify-center gap-1">
                                    <span>{weekdayShortLabel(isoW)}</span>
                                    <span className="text-[11px] font-normal opacity-80 tabular-nums">
                                      {formatShortMd(ymd)}
                                    </span>
                                    {isToday && (
                                      <span className="rounded-full bg-selection px-1.5 py-0.2 text-[10px] font-bold text-primary">
                                        今天
                                      </span>
                                    )}
                                  </div>
                                </th>
                              );
                            })}
                          </tr>
                        </thead>
                        <tbody>
                          {teacherRows.map((row) => (
                            <tr key={row.key}>
                              <th scope="row">
                                <div className="schedule-period-label">
                                  <span>{row.labelTop}</span>
                                  {row.labelBottom && (
                                    <small>{row.labelBottom}</small>
                                  )}
                                </div>
                              </th>

                              {visibleDates.map((ymd) => {
                                const matched = teacherLessons.filter(
                                  (l) =>
                                    l.date === ymd &&
                                    l.item.position != null &&
                                    row.matches(l.item.position)
                                );
                                if (matched.length === 0) {
                                  return (
                                    <td key={ymd}>
                                      <div className="schedule-slot">
                                        <div className="schedule-slot-content">
                                          <span
                                            className="schedule-empty-slot"
                                            aria-hidden="true"
                                          />
                                        </div>
                                      </div>
                                    </td>
                                  );
                                }
                                const first = matched[0];
                                const subjectColor = getSubjectColor(
                                  first.item.subjectId,
                                  resolvedDark
                                );
                                const subjectName = getSubjectDisplayName(
                                  first.item.subjectId,
                                  state.snapshot.subjects
                                );
                                const classLabel = matched
                                  .map((m) =>
                                    getClassDisplayName(
                                      m.item.classId,
                                      state.snapshot.classes,
                                      state.snapshot.grades
                                    )
                                  )
                                  .join('、');

                                return (
                                  <td key={ymd}>
                                    <div className="schedule-slot">
                                      <div className="schedule-slot-content">
                                        <button
                                          type="button"
                                          onClick={() => {
                                            setTeacherView(false);
                                            setClassId(first.item.classId);
                                            selectLessonForAdjustment(
                                              first,
                                              'swap'
                                            );
                                          }}
                                          style={
                                            {
                                              '--lesson-bg':
                                                subjectColor.background,
                                              '--lesson-ink':
                                                subjectColor.foreground,
                                              '--lesson-border': `${subjectColor.foreground}30`,
                                            } as React.CSSProperties
                                          }
                                          className="schedule-lesson"
                                        >
                                          <strong>{subjectName}</strong>
                                          <small>{classLabel}</small>
                                        </button>
                                      </div>
                                    </div>
                                  </td>
                                );
                              })}
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  );
                })()
              )}
            </section>

            {/* 右侧发起调整面板（当选中源课次且在班级视图时显示） */}
            {source && kind && (
              <aside className="schedule-panel w-full xl:w-[336px] shrink-0 flex flex-col">
                {/* 头部 */}
                <div className="schedule-panel-heading">
                  <div className="flex items-center gap-2">
                    <h2>发起调整</h2>
                    <span className="px-2 py-0.5 rounded-full bg-selection text-primary text-[11px] font-bold">
                      {panelReady ? '3 / 3' : '2 / 3'}
                    </span>
                  </div>
                  <button
                    type="button"
                    onClick={clearAdjustmentDraft}
                    className="w-7 h-7 rounded-md flex items-center justify-center text-ink-secondary hover:text-ink hover:bg-table-header"
                  >
                    <X className="w-4 h-4" />
                  </button>
                </div>

                {/* 内容区 */}
                <div className="p-3.5 space-y-4">
                  {/* 已选课次卡片 */}
                  <div className="space-y-1.5">
                    <div className="text-xs font-semibold text-ink-secondary">
                      已选课次
                    </div>
                    <div className="p-3 rounded-[10px] bg-selection/70 space-y-1">
                      <div className="flex items-center gap-2">
                        <span
                          style={{
                            backgroundColor: getSubjectColor(
                              source.item.subjectId,
                              resolvedDark
                            ).foreground,
                          }}
                          className="w-2 h-2 rounded-full shrink-0"
                        />
                        <span className="text-[13.5px] font-bold text-ink">
                          {getSubjectDisplayName(
                            source.item.subjectId,
                            state.snapshot.subjects
                          )}{' '}
                          · {formatChineseMdWeekday(source.date)}
                        </span>
                      </div>
                      <div className="text-xs text-ink-secondary pl-4">
                        {getPeriodLessonLabel(state, source.item.position)} ·{' '}
                        {getTeacherNameById(
                          source.item.teacherId,
                          state.snapshot.teachers
                        )}{' '}
                        ·{' '}
                        {getClassDisplayName(
                          source.item.classId,
                          state.snapshot.classes,
                          state.snapshot.grades
                        )}
                      </div>
                    </div>
                  </div>

                  {/* 锁定警告 */}
                  {sourceLocked && (
                    <div className="p-2.5 rounded-lg border border-warning/40 bg-warning-surface text-xs text-warning flex items-center justify-between gap-2">
                      <div className="flex items-center gap-1.5">
                        <Lock className="w-3.5 h-3.5 shrink-0" />
                        <span>该班级或教师课表已锁定</span>
                      </div>
                      <button
                        type="button"
                        onClick={() => setSelectedSection('scheduling')}
                        className="font-semibold underline shrink-0"
                      >
                        前往课表解锁
                      </button>
                    </div>
                  )}

                  {/* 关联已有调整提示 */}
                  {sourceActiveRecord && (
                    <div className="p-2.5 rounded-lg border border-primary/30 bg-selection/50 text-xs text-ink flex items-center justify-between gap-2">
                      <span>
                        该课次已有生效中的
                        {adjustmentKindLabel(sourceActiveRecord.kind)}
                      </span>
                      <button
                        type="button"
                        onClick={() => setDetailRecord(sourceActiveRecord)}
                        className="text-primary font-semibold hover:underline shrink-0"
                      >
                        查看关联记录
                      </button>
                    </div>
                  )}

                  {/* 调整方式 3 张单选卡片 */}
                  <div className="space-y-1.5">
                    <div className="text-xs font-semibold text-ink-secondary">
                      调整方式
                    </div>
                    <div className="space-y-2">
                      {(
                        [
                          {
                            id: 'swap',
                            title: '换课',
                            desc: '与本班另一实际课次互换时间，可跨日期、跨周',
                          },
                          {
                            id: 'move',
                            title: '移课',
                            desc: '移到本班空课位，原位置变为空位',
                          },
                          {
                            id: 'substitute',
                            title: '代课',
                            desc: '更换任课教师，时间和班级保持不变',
                          },
                        ] as const
                      ).map((opt) => {
                        const active = kind === opt.id;
                        return (
                          <button
                            key={opt.id}
                            type="button"
                            onClick={() => switchAdjustmentKind(opt.id)}
                            className={`w-full p-3 rounded-[10px] text-left border transition-all flex items-start gap-2.5 ${
                              active
                                ? 'border-[1.5px] border-primary bg-selection/40'
                                : 'border-border bg-surface hover:bg-table-header/40'
                            }`}
                          >
                            <span
                              className={`mt-0.5 w-4 h-4 rounded-full shrink-0 border ${
                                active
                                  ? 'border-[4.5px] border-primary'
                                  : 'border-border'
                              }`}
                            />
                            <div className="min-w-0">
                              <div className="text-[13px] font-bold text-ink">
                                {opt.title}
                              </div>
                              <div className="text-xs text-ink-secondary mt-0.5 leading-relaxed">
                                {opt.desc}
                              </div>
                            </div>
                          </button>
                        );
                      })}
                    </div>
                  </div>

                  {/* 目标课次 / 空课位 / 代课教师 */}
                  <div className="space-y-2">
                    <div className="text-xs font-semibold text-ink-secondary">
                      {kind === 'swap'
                        ? '目标课次'
                        : kind === 'move'
                        ? '目标空课位'
                        : '代课安排'}
                    </div>

                    {kind === 'swap' &&
                      (selectedSwapTargetLesson ? (
                        <div className="p-3 rounded-[10px] border border-success/50 bg-success-surface text-xs space-y-1">
                          <div className="flex items-center justify-between">
                            <span className="font-bold text-ink">
                              {getSubjectDisplayName(
                                selectedSwapTargetLesson.item.subjectId,
                                state.snapshot.subjects
                              )}{' '}
                              ·{' '}
                              {formatChineseMdWeekday(
                                selectedSwapTargetLesson.date
                              )}
                            </span>
                            <button
                              type="button"
                              onClick={() => setSwapKey(null)}
                              className="text-ink-secondary hover:text-ink"
                            >
                              重选
                            </button>
                          </div>
                          <div className="text-ink-secondary">
                            {getPeriodLessonLabel(
                              state,
                              selectedSwapTargetLesson.item.position
                            )}{' '}
                            ·{' '}
                            {getTeacherNameById(
                              selectedSwapTargetLesson.item.teacherId,
                              state.snapshot.teachers
                            )}
                          </div>
                        </div>
                      ) : (
                        <div className="p-3 rounded-[10px] border border-dashed border-primary/40 bg-selection/30 text-xs text-ink-secondary leading-relaxed">
                          尚未选择。请在左侧课表中{' '}
                          <span className="text-primary font-semibold">
                            选择要交换的课次
                          </span>
                        </div>
                      ))}

                    {kind === 'move' &&
                      (moveDate && movePosition ? (
                        <div className="p-3 rounded-[10px] border border-success/50 bg-success-surface text-xs space-y-1">
                          <div className="flex items-center justify-between">
                            <span className="font-bold text-ink">
                              {formatChineseMdWeekday(moveDate)} ·{' '}
                              {getPeriodLessonLabel(state, movePosition)}
                            </span>
                            <button
                              type="button"
                              onClick={() => {
                                setMoveDate(null);
                                setMovePosition(null);
                              }}
                              className="text-ink-secondary hover:text-ink"
                            >
                              重选
                            </button>
                          </div>
                          <div className="text-ink-secondary">
                            移入该空课位，原课位将变为空位
                          </div>
                        </div>
                      ) : (
                        <div className="p-3 rounded-[10px] border border-dashed border-primary/40 bg-selection/30 text-xs text-ink-secondary leading-relaxed">
                          尚未选择。请在左侧课表中点击标有{' '}
                          <span className="text-primary font-semibold">
                            ＋ 移入此位
                          </span>{' '}
                          的空课位
                        </div>
                      ))}

                    {kind === 'substitute' && (
                      <div className="space-y-2.5">
                        <Button
                          type="button"
                          variant="outline"
                          onClick={() => setSubstituteDialogOpen(true)}
                          className="w-full justify-between text-xs h-9"
                        >
                          <span className="inline-flex items-center gap-1.5">
                            <UserPlus className="w-3.5 h-3.5 text-primary" />
                            <span>
                              {substituteTeacherId
                                ? `代课教师：${getTeacherNameById(
                                    substituteTeacherId,
                                    state.snapshot.teachers
                                  )}`
                                : '选择代课教师…'}
                            </span>
                          </span>
                          <span className="text-primary">
                            {substituteTeacherId ? '更换' : '选择'}
                          </span>
                        </Button>

                        <div className="space-y-1">
                          <Label className="text-xs text-ink-secondary">
                            代课科目
                          </Label>
                          <SelectField
                            ariaLabel="代课科目"
                            className="h-9 w-full text-xs"
                            value={
                              substituteSubjectId ?? source.item.subjectId
                            }
                            onValueChange={setSubstituteSubjectId}
                            options={state.snapshot.subjects.map((s) => ({
                              value: s.id,
                              label: `${s.name}${
                                s.id === source.item.subjectId
                                  ? '（原科目）'
                                  : ''
                              }`,
                            }))}
                          />
                        </div>
                      </div>
                    )}
                  </div>

                  {/* 调整原因 */}
                  <div className="space-y-1.5">
                    <Label className="text-xs font-semibold text-ink-secondary">
                      调整原因（选填）
                    </Label>
                    <Input
                      value={reason}
                      onChange={(e) => setReason(e.target.value)}
                      placeholder="例如：外出培训、教研活动、事假…"
                      className="h-9 text-xs"
                    />
                  </div>
                </div>

                {/* 底部操作栏 */}
                <div className="p-3.5 border-t border-border bg-surface space-y-2.5">
                  {!panelReady && (
                    <div className="text-xs text-ink-secondary">
                      {kind === 'swap'
                        ? '请先在课表中选择要交换的目标课次'
                        : kind === 'move'
                        ? '请先在课表中选择要移入的目标空课位'
                        : '请先选择代课教师'}
                    </div>
                  )}
                  <div className="flex items-center justify-between gap-2">
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      onClick={clearAdjustmentDraft}
                    >
                      取消
                    </Button>
                    <Button
                      type="button"
                      size="sm"
                      disabled={!panelReady}
                      onClick={() => setPreviewDialogOpen(true)}
                      className="px-4"
                    >
                      下一步 · 预览
                    </Button>
                  </div>
                </div>
              </aside>
            )}
          </div>
        )}

        {/* 4. 弹窗集合 */}
        {source && (
          <SubstituteTeacherDialog
            open={substituteDialogOpen}
            onOpenChange={setSubstituteDialogOpen}
            state={state}
            source={source}
            selectedTeacherId={substituteTeacherId}
            subjectId={substituteSubjectId}
            weekIndex={weekIndex}
            onSelectTeacher={setSubstituteTeacherId}
          />
        )}

        {source && kind && (
          <PreviewAdjustmentDialog
            open={previewDialogOpen}
            onOpenChange={setPreviewDialogOpen}
            state={state}
            source={source}
            kind={kind}
            swapKey={swapKey}
            moveDate={moveDate}
            movePosition={movePosition}
            substituteTeacherId={substituteTeacherId}
            substituteSubjectId={substituteSubjectId}
            reason={reason}
            onConfirm={handleCommitAdjustment}
          />
        )}

        <SupervisionSubstituteDialog
          open={activeSupervision !== null}
          onOpenChange={(open) => {
            if (!open) setActiveSupervision(null);
          }}
          state={state}
          supervision={activeSupervision}
          onConfirm={handleCommitSupervisionSubstitute}
        />

        <RecordDetailDialog
          open={detailRecord !== null}
          onOpenChange={(open) => {
            if (!open) setDetailRecord(null);
          }}
          state={state}
          record={detailRecord}
          onRequestCancelRecord={(rec) => setCancelRecord(rec)}
        />

        <CancelRecordDialog
          open={cancelRecord !== null}
          onOpenChange={(open) => {
            if (!open) setCancelRecord(null);
          }}
          state={state}
          record={cancelRecord}
          onConfirmCancel={handleConfirmCancelRecord}
        />
      </div>
    </TooltipProvider>
  );
};
