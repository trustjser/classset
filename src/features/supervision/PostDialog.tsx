import React, { useMemo, useState } from 'react';
import {
  Check,
  ChevronDown,
  ChevronRight,
  Info,
  Search,
  X,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import {
  Dialog,
  DialogContent,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import type { ScheduleData } from '@/domain/scheduling.ts';
import type {
  SchedulePosition,
  SupervisionDraft,
  SupervisionKind,
  SupervisionMatchingPreferences,
  SupervisionPost,
} from '@/domain/supervision.ts';
import {
  SUPERVISION_BASE_POOL_ID,
  SUPERVISION_KIND_LABELS,
  overlaps,
} from '@/domain/supervision.ts';
import {
  effectiveLessonCount,
  isSupervisionAllowedInSlot,
  postErrors,
  resolveFreeSlotForClass,
  withRoutineClock,
} from '@/domain/supervisionValidation.ts';
import { SupervisionMatchingPreferencesEditor } from './SupervisionMatchingPreferencesEditor';

interface PostDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  snapshot: ScheduleData;
  draft: SupervisionDraft;
  onSave: (posts: SupervisionPost[]) => void;
}

interface PostSlot {
  weekday: number;
  periodId: string;
  index: number;
}

const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

const copyMatchingPreferences = (
  preferences: SupervisionMatchingPreferences
): SupervisionMatchingPreferences => ({
  ...preferences,
  order: [...preferences.order],
  enabled: [...preferences.enabled],
});

export const PostDialog: React.FC<PostDialogProps> = ({
  open,
  onOpenChange,
  snapshot,
  draft,
  onSave,
}) => {
  // Current active stage
  const defaultStageId = snapshot.stages[0]?.id || '';
  const [stageId, setStageId] = useState<string>(defaultStageId);

  // Selected classes
  const [selectedClasses, setSelectedClasses] = useState<Set<string>>(new Set());

  // Selected slots
  const [selectedSlots, setSelectedSlots] = useState<Set<string>>(new Set());

  // Expanded tree states
  const [expandedStages, setExpandedStages] = useState<Set<string>>(
    new Set([defaultStageId])
  );
  const [expandedGrades, setExpandedGrades] = useState<Set<string>>(
    new Set(
      snapshot.grades
        .filter((g) => g.stageId === defaultStageId)
        .map((g) => g.id)
    )
  );
  const [classSearch, setClassSearch] = useState<string>('');

  // Post attributes
  const [kind, setKind] = useState<SupervisionKind>('afterSchool');
  const [name, setName] = useState<string>(SUPERVISION_KIND_LABELS.afterSchool);
  const [merged, setMerged] = useState<boolean>(false);
  const [groupName, setGroupName] = useState<string>('');
  const [location, setLocation] = useState<string>('');
  const [continuous, setContinuous] = useState<boolean>(true);

  // Personnel settings
  const [poolId, setPoolId] = useState<string | null>(null);
  const [customPreferences, setCustomPreferences] = useState<SupervisionMatchingPreferences | null>(
    null
  );
  const [targetSubjectIds, setTargetSubjectIds] = useState<Set<string>>(new Set());
  const [personnelPopoverOpen, setPersonnelPopoverOpen] = useState(false);

  // Errors
  const [activityNameError, setActivityNameError] = useState<string | null>(null);
  const [groupNameError, setGroupNameError] = useState<string | null>(null);
  const [locationError, setLocationError] = useState<string | null>(null);
  const [scheduleErrors, setScheduleErrors] = useState<string[]>([]);

  // Current stage & routine
  const stage = snapshot.stages.find((s) => s.id === stageId) || snapshot.stages[0];
  const routine = snapshot.routines.find((r) => r.stageId === stageId);

  // Occupied positions by class from existing posts in draft
  const occupiedByClass = useMemo(() => {
    const map = new Map<string, SchedulePosition[]>();
    for (const post of draft.posts) {
      for (const idx of post.lessonIndices) {
        const pos = withRoutineClock(snapshot, {
          stageId: post.stageId,
          weekday: post.weekday,
          periodTypeId: post.periodTypeId,
          lessonIndex: idx,
        });
        for (const cid of post.classIds) {
          const list = map.get(cid) ?? [];
          list.push(pos);
          map.set(cid, list);
        }
      }
    }
    return map;
  }, [draft.posts, snapshot]);

  // Teaching weekdays for this routine
  const teachingWeekdays = useMemo(() => {
    if (!routine) return [1, 2, 3, 4, 5];
    return routine.teachingDays
      .filter((d) => d.isTeachingDay)
      .map((d) => d.weekday)
      .sort((a, b) => a - b);
  }, [routine]);

  // Ordered periods for this routine
  const periods = useMemo(() => {
    if (!routine) return [];
    return [...routine.periodTypes].sort((a, b) => a.sortOrder - b.sortOrder);
  }, [routine]);

  // Routine slots list
  const routineSlots = useMemo<PostSlot[]>(() => {
    if (!routine) return [];
    const list: PostSlot[] = [];
    for (const day of teachingWeekdays) {
      for (const period of periods) {
        const count = effectiveLessonCount(routine, period.id, day);
        for (let idx = 1; idx <= count; idx++) {
          list.push({ weekday: day, periodId: period.id, index: idx });
        }
      }
    }
    return list;
  }, [periods, routine, teachingWeekdays]);

  // Helper to determine slot eligibility and reason
  const getSlotReason = (slot: PostSlot): string | null => {
    if (!routine) return '—';
    if (!teachingWeekdays.includes(slot.weekday)) return '—';
    const period = periods.find((p) => p.id === slot.periodId);
    if (!period) return '—';
    const maxLesson = effectiveLessonCount(routine, slot.periodId, slot.weekday);
    if (slot.index < 1 || slot.index > maxLesson) return '—';

    // If no classes selected, disable slots with placeholder dash
    if (selectedClasses.size === 0) return '—';

    const classToGrade = new Map(snapshot.classes.map((c) => [c.id, c.gradeId]));
    const classToStage = new Map(
      snapshot.classes.map((c) => {
        const g = snapshot.grades.find((grade) => grade.id === c.gradeId);
        return [c.id, g?.stageId ?? ''];
      })
    );

    let regularCount = 0;
    const otherLabels = new Set<string>();

    for (const classId of selectedClasses) {
      const freeSlot = resolveFreeSlotForClass(
        snapshot.freeSlots,
        draft.termId,
        stageId,
        classToGrade.get(classId),
        classId,
        slot.weekday,
        slot.periodId,
        slot.index
      );

      if (!freeSlot) {
        // No free slot marker
      } else if (!isSupervisionAllowedInSlot(freeSlot)) {
        otherLabels.add(freeSlot.label);
      }

      // Check if class already has a regular course item in snapshot.items
      const pos = withRoutineClock(snapshot, {
        stageId,
        weekday: slot.weekday,
        periodTypeId: slot.periodId,
        lessonIndex: slot.index,
      });

      const conflictItem = snapshot.items.find((item) => {
        if (item.classId !== classId) return false;
        if (
          item.weekday === null ||
          item.periodTypeId === null ||
          item.lessonIndex === null
        ) {
          return false;
        }
        const itemPos = withRoutineClock(snapshot, {
          stageId: item.stageId ?? classToStage.get(classId) ?? stageId,
          weekday: item.weekday,
          periodTypeId: item.periodTypeId,
          lessonIndex: item.lessonIndex,
        });
        return overlaps(pos, itemPos);
      });

      if (conflictItem) {
        regularCount++;
      }
    }

    if (regularCount > 0) {
      return regularCount === selectedClasses.size ? '正课' : '含正课';
    }

    if (otherLabels.size > 0) {
      return Array.from(otherLabels).join(' / ');
    }

    // Check if class already has a supervision post in draft
    const pos = withRoutineClock(snapshot, {
      stageId,
      weekday: slot.weekday,
      periodTypeId: slot.periodId,
      lessonIndex: slot.index,
    });

    let occupiedCount = 0;
    for (const classId of selectedClasses) {
      const existing = occupiedByClass.get(classId);
      if (existing?.some((p) => overlaps(pos, p))) {
        occupiedCount++;
      }
    }

    if (occupiedCount > 0) {
      return occupiedCount === selectedClasses.size ? '已有岗位' : '含已有岗位';
    }

    return null;
  };

  // Available slots for selected classes
  const availableSlots = useMemo(() => {
    return routineSlots.filter((slot) => getSlotReason(slot) === null);
  }, [routineSlots, selectedClasses, occupiedByClass, snapshot]);

  // Prune slots that became invalid
  const pruneSlots = (slotsSet: Set<string>): Set<string> => {
    const next = new Set<string>();
    for (const key of slotsSet) {
      const [wStr, pId, iStr] = key.split(':');
      const slot: PostSlot = {
        weekday: Number(wStr),
        periodId: pId,
        index: Number(iStr),
      };
      if (getSlotReason(slot) === null) {
        next.add(key);
      }
    }
    return next;
  };

  // Switch stage scope
  const handleToggleScope = (newStageId: string, classIds: string[]) => {
    if (stageId !== newStageId) {
      setStageId(newStageId);
      setSelectedClasses(new Set(classIds));
      setSelectedSlots(new Set());
      setExpandedStages(new Set([newStageId]));
      setExpandedGrades(
        new Set(
          snapshot.grades
            .filter((g) => g.stageId === newStageId)
            .map((g) => g.id)
        )
      );
      setScheduleErrors([]);
      return;
    }

    const next = new Set(selectedClasses);
    const allIn = classIds.length > 0 && classIds.every((id) => next.has(id));
    if (allIn) {
      for (const id of classIds) next.delete(id);
    } else {
      for (const id of classIds) next.add(id);
    }
    setSelectedClasses(next);
    setSelectedSlots(pruneSlots(selectedSlots));
    setScheduleErrors([]);
  };

  // Batch toggle slots
  const handleToggleSlots = (slotsToToggle: PostSlot[]) => {
    const availableSet = new Set(
      availableSlots.map((s) => `${s.weekday}:${s.periodId}:${s.index}`)
    );
    const validKeys = slotsToToggle
      .map((s) => `${s.weekday}:${s.periodId}:${s.index}`)
      .filter((k) => availableSet.has(k));

    const next = new Set(selectedSlots);
    const allSelected = validKeys.length > 0 && validKeys.every((k) => next.has(k));

    if (allSelected) {
      for (const k of validKeys) next.delete(k);
    } else {
      for (const k of validKeys) next.add(k);
    }
    setSelectedSlots(next);
    setScheduleErrors([]);
  };

  // Check lunch gap
  const isLunchGap = (prevEnd: number | null, currStart: number | null): boolean => {
    return (
      prevEnd !== null &&
      currStart !== null &&
      prevEnd < 12 * 60 + 30 &&
      currStart >= 13 * 60 &&
      currStart - prevEnd >= 60
    );
  };

  // Blocks calculation for final posts count
  const parsedSelectedSlots = useMemo(() => {
    return Array.from(selectedSlots).map((k) => {
      const [wStr, pId, iStr] = k.split(':');
      return {
        weekday: Number(wStr),
        periodId: pId,
        index: Number(iStr),
      };
    });
  }, [selectedSlots]);

  const blocks = useMemo(() => {
    const list: { weekday: number; periodId: string; indices: number[] }[] = [];
    const days = Array.from(new Set(parsedSelectedSlots.map((s) => s.weekday))).sort(
      (a, b) => a - b
    );

    for (const day of days) {
      for (const period of periods) {
        const indices = parsedSelectedSlots
          .filter((s) => s.weekday === day && s.periodId === period.id)
          .map((s) => s.index)
          .sort((a, b) => a - b);

        for (const idx of indices) {
          if (
            continuous &&
            list.length > 0 &&
            list[list.length - 1].weekday === day &&
            list[list.length - 1].periodId === period.id &&
            list[list.length - 1].indices[list[list.length - 1].indices.length - 1] + 1 === idx
          ) {
            list[list.length - 1].indices.push(idx);
          } else {
            list.push({ weekday: day, periodId: period.id, indices: [idx] });
          }
        }
      }
    }
    return list;
  }, [continuous, parsedSelectedSlots, periods]);

  const totalCalculatedPostsCount =
    (merged ? (selectedClasses.size > 0 ? 1 : 0) : selectedClasses.size) *
    blocks.length;

  // Submit action
  const handleSubmit = () => {
    if (selectedClasses.size === 0 || selectedSlots.size === 0) {
      if (selectedClasses.size === 0) setScheduleErrors(['请选择适用班级']);
      if (selectedSlots.size === 0) setScheduleErrors(['请选择带班课节']);
      return;
    }

    const activityName = kind === 'custom' ? name.trim() : SUPERVISION_KIND_LABELS[kind];
    if (!activityName) {
      setActivityNameError('请填写活动名称');
      return;
    }

    if (merged && selectedClasses.size < 2) {
      setScheduleErrors(['实际合班至少需要选择 2 个班级']);
      return;
    }

    if (merged && (!groupName.trim() || !location.trim())) {
      if (!groupName.trim()) setGroupNameError('实际合班须填写组名');
      if (!location.trim()) setLocationError('实际合班须填写地点');
      return;
    }

    const classGroups: string[][] = merged
      ? [Array.from(selectedClasses)]
      : Array.from(selectedClasses).map((id) => [id]);

    const createdPosts: SupervisionPost[] = [];
    const timestamp = Date.now();
    let counter = 0;

    for (const block of blocks) {
      for (const group of classGroups) {
        counter++;
        const id = `post_${timestamp}_${counter}`;

        createdPosts.push({
          id,
          kind,
          name: activityName,
          groupName: merged ? groupName.trim() : '',
          location: merged ? location.trim() : '',
          stageId,
          weekday: block.weekday,
          periodTypeId: block.periodId,
          lessonIndices: block.indices,
          classIds: group,
          teacherPoolId: poolId,
          matchingPreferences: customPreferences,
          targetSubjectIds:
            targetSubjectIds.size > 0 ? Array.from(targetSubjectIds) : undefined,
        });
      }
    }

    const validation = postErrors(snapshot, {
      ...draft,
      posts: [...draft.posts, ...createdPosts],
    });

    if (validation.length > 0) {
      setScheduleErrors(validation);
      return;
    }

    onSave(createdPosts);
    onOpenChange(false);
  };

  // Personnel summary description
  const personnelSummary = useMemo(() => {
    const poolName =
      poolId === null
        ? '默认候选池'
        : poolId === SUPERVISION_BASE_POOL_ID
        ? '基础候选池'
        : draft.teacherPools.find((p) => p.id === poolId)?.name ?? '自定义候选池';
    const prefName = customPreferences ? '单独匹配偏好' : '跟随全局偏好';
    return `${poolName} · ${prefName}`;
  }, [customPreferences, draft.teacherPools, poolId]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        showCloseButton={false}
        className="w-[calc(100vw-2rem)] max-w-5xl h-[92vh] max-h-[92vh] min-h-0 flex flex-col gap-0 p-0 overflow-hidden bg-surface rounded-2xl shadow-2xl border border-border"
      >
        {/* ================= 1. Top Header ================= */}
        <div className="shrink-0 px-6 pt-5 pb-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <h2 className="text-lg font-bold text-ink">创建带班岗位</h2>
              {stage && (
                <span className="px-2.5 py-0.5 rounded-full text-xs font-semibold bg-selection text-primary border border-primary/20">
                  {stage.name}作息
                </span>
              )}
            </div>
            {/* Single clean close button */}
            <button
              type="button"
              onClick={() => onOpenChange(false)}
              className="p-1.5 rounded-md text-ink-secondary hover:text-ink hover:bg-table-header transition-colors"
              aria-label="关闭"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          <p className="text-xs text-ink-secondary mt-1">
            选择适用班级与带班课节，系统已自动过滤正课及不可带班时段。
          </p>

          {/* Activity kind & Personnel Rule Row */}
          <div className="mt-3 grid grid-cols-1 md:grid-cols-12 gap-3">
            {/* Box 1: Activity Kind */}
            <div className="md:col-span-4 h-10 px-3 rounded-lg border border-border bg-surface flex items-center gap-3">
              <span className="text-xs text-ink-secondary shrink-0 font-medium">活动类型</span>
              <div className="h-4 w-px bg-border shrink-0" />
              <Select
                value={kind}
                onValueChange={(val) => {
                  const k = val as SupervisionKind;
                  setKind(k);
                  if (k !== 'custom') {
                    setName(SUPERVISION_KIND_LABELS[k]);
                  } else {
                    setName('');
                  }
                  setActivityNameError(null);
                }}
              >
                <SelectTrigger className="border-0 shadow-none h-8 text-xs font-semibold text-ink px-1 focus:ring-0">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(SUPERVISION_KIND_LABELS).map(([k, lbl]) => (
                    <SelectItem key={k} value={k} className="text-xs">
                      {lbl}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Box 2: Personnel Rules */}
            <div className="md:col-span-8 h-10 px-3 rounded-lg border border-border bg-surface flex items-center justify-between gap-3">
              <div className="flex items-center gap-3 min-w-0">
                <span className="text-xs text-ink-secondary shrink-0 font-medium">人员规则</span>
                <div className="h-4 w-px bg-border shrink-0" />
                <span className="text-xs text-ink font-medium truncate">
                  {personnelSummary}
                </span>
              </div>

              {/* Modify link */}
              <Popover open={personnelPopoverOpen} onOpenChange={setPersonnelPopoverOpen}>
                <PopoverTrigger asChild>
                  <button
                    type="button"
                    className="text-xs font-semibold text-primary hover:underline shrink-0 flex items-center gap-1 ml-2"
                  >
                    修改
                    <ChevronDown className="h-3.5 w-3.5" />
                  </button>
                </PopoverTrigger>
                <PopoverContent align="end" className="w-80 max-w-[calc(100vw-2rem)] max-h-[80vh] overflow-y-auto overscroll-contain p-4 space-y-4 text-xs bg-surface border border-border shadow-lg">
                  <div className="font-semibold text-sm text-ink pb-2 border-b border-border">
                    岗位人员规则设置
                  </div>

                  <div>
                    <label className="text-xs font-medium text-ink mb-1 block">候选池</label>
                    <Select
                      value={poolId ?? '__inherit__'}
                      onValueChange={(v) => setPoolId(v === '__inherit__' ? null : v)}
                    >
                      <SelectTrigger className="h-8 text-xs">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__inherit__">跟随默认候选池</SelectItem>
                        <SelectItem value={SUPERVISION_BASE_POOL_ID}>基础候选池 (全部教师)</SelectItem>
                        {draft.teacherPools.map((p) => (
                          <SelectItem key={p.id} value={p.id}>
                            {p.name} ({p.teacherIds.length} 人)
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div>
                    <label className="text-xs font-medium text-ink mb-1 block">匹配偏好</label>
                    <Select
                      value={customPreferences ? 'custom' : 'inherit'}
                      onValueChange={(v) => {
                        setCustomPreferences(
                          v === 'custom'
                            ? customPreferences ??
                                copyMatchingPreferences(draft.matchingPreferences)
                            : null
                        );
                      }}
                    >
                      <SelectTrigger className="h-8 text-xs">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="inherit">跟随全局偏好</SelectItem>
                        <SelectItem value="custom">为本岗位单独指定偏好</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>

                  {customPreferences && (
                    <SupervisionMatchingPreferencesEditor
                      value={customPreferences}
                      onChange={setCustomPreferences}
                    />
                  )}

                  <div>
                    <label className="text-xs font-medium text-ink mb-1 block">
                      目标学科 (可选，指定学科优先)
                    </label>
                    <p className="mb-1 text-[10px] text-ink-secondary">
                      启用“指定学科优先”后，任教所选学科的教师会优先匹配。
                    </p>
                    <div className="flex flex-wrap gap-1.5 max-h-24 overflow-y-auto p-1.5 border border-border rounded-md bg-canvas/30">
                      {snapshot.subjects.map((sub) => {
                        const active = targetSubjectIds.has(sub.id);
                        return (
                          <button
                            key={sub.id}
                            type="button"
                            onClick={() => {
                              const next = new Set(targetSubjectIds);
                              if (active) next.delete(sub.id);
                              else next.add(sub.id);
                              setTargetSubjectIds(next);
                            }}
                            className={`px-2 py-0.5 rounded text-[11px] font-medium transition-colors ${
                              active
                                ? 'bg-primary text-primary-foreground font-semibold'
                                : 'bg-surface border border-border text-ink hover:border-primary'
                            }`}
                          >
                            {sub.name}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                </PopoverContent>
              </Popover>
            </div>
          </div>

          {/* Custom activity name if custom kind */}
          {kind === 'custom' && (
            <div className="mt-2.5">
              <Input
                value={name}
                onChange={(e) => {
                  setName(e.target.value);
                  setActivityNameError(null);
                }}
                placeholder="请输入自定义活动名称（如：早读特护、创客自习）"
                className="h-8 text-xs text-ink placeholder:text-ink-secondary"
              />
              {activityNameError && (
                <span className="text-[11px] text-destructive mt-1 block">
                  {activityNameError}
                </span>
              )}
            </div>
          )}
        </div>

        {/* Divider */}
        <div className="border-b border-border" />

        {/* ================= 2. Middle Split Layout ================= */}
        <div className="flex-1 min-h-0 flex overflow-hidden">
          {/* ----- Left Column: 班级范围 ----- */}
          <div className="w-72 min-h-0 bg-canvas border-r border-border flex flex-col shrink-0">
            {/* Header */}
            <div className="p-3 border-b border-border flex items-center justify-between bg-surface/50">
              <div className="flex items-center gap-1.5">
                <span className="text-xs font-bold text-ink">班级范围</span>
                <span className="px-2 py-0.5 rounded-full text-[11px] font-semibold bg-selection text-primary border border-primary/20">
                  已选 {selectedClasses.size} 班
                </span>
              </div>
              <div className="text-[11px] text-ink-secondary space-x-1.5">
                <button
                  type="button"
                  onClick={() => {
                    const allClassIds = snapshot.classes
                      .filter((c) => {
                        const g = snapshot.grades.find((grade) => grade.id === c.gradeId);
                        return g?.stageId === stageId;
                      })
                      .map((c) => c.id);
                    handleToggleScope(stageId, allClassIds);
                  }}
                  className="text-ink-secondary hover:text-primary font-medium transition-colors"
                >
                  全选
                </button>
                <span className="text-border">|</span>
                <button
                  type="button"
                  onClick={() => {
                    setSelectedClasses(new Set());
                    setSelectedSlots(new Set());
                  }}
                  className="text-ink-secondary hover:text-destructive font-medium transition-colors"
                >
                  清空
                </button>
              </div>
            </div>

            {/* Search */}
            <div className="p-2 border-b border-border/80">
              <div className="relative">
                <Search className="h-3.5 w-3.5 absolute left-2.5 top-2.5 text-ink-secondary" />
                <input
                  type="text"
                  value={classSearch}
                  onChange={(e) => setClassSearch(e.target.value)}
                  placeholder="搜索年级或班级..."
                  className="w-full pl-8 pr-2 py-1.5 bg-surface border border-border rounded-md text-xs text-ink placeholder:text-ink-secondary focus:outline-none focus:border-primary focus:ring-1 focus:ring-primary"
                />
              </div>
            </div>

            {/* Scope Tree */}
            <div className="flex-1 min-h-0 overflow-y-auto p-2 space-y-1">
              {snapshot.stages.map((st) => {
                const isCurrentStage = st.id === stageId;
                const stageGrades = snapshot.grades.filter((g) => g.stageId === st.id);
                const stageClassIds = snapshot.classes
                  .filter((c) => stageGrades.some((g) => g.id === c.gradeId))
                  .map((c) => c.id);

                const stageSelectedCount = isCurrentStage
                  ? stageClassIds.filter((id) => selectedClasses.has(id)).length
                  : 0;
                const stageAllChecked =
                  isCurrentStage &&
                  stageClassIds.length > 0 &&
                  stageSelectedCount === stageClassIds.length;
                const isStageExpanded =
                  expandedStages.has(st.id) || classSearch.trim().length > 0;

                return (
                  <div key={st.id} className="space-y-0.5">
                    {/* Stage Item */}
                    <div className="flex items-center justify-between p-1.5 rounded-md hover:bg-surface transition-colors group">
                      <div className="flex items-center gap-1.5 flex-1 min-w-0">
                        <button
                          type="button"
                          onClick={() => {
                            const next = new Set(expandedStages);
                            if (next.has(st.id)) next.delete(st.id);
                            else next.add(st.id);
                            setExpandedStages(next);
                          }}
                          className="p-0.5 text-ink-secondary hover:text-ink"
                        >
                          {isStageExpanded ? (
                            <ChevronDown className="h-3.5 w-3.5" />
                          ) : (
                            <ChevronRight className="h-3.5 w-3.5" />
                          )}
                        </button>
                        <Checkbox
                          checked={stageAllChecked}
                          onCheckedChange={() => handleToggleScope(st.id, stageClassIds)}
                        />
                        <span
                          onClick={() => handleToggleScope(st.id, stageClassIds)}
                          className={`text-xs truncate cursor-pointer ${
                            isCurrentStage ? 'font-bold text-ink' : 'text-ink-secondary'
                          }`}
                        >
                          {st.name}
                        </span>
                      </div>
                      <span className="text-[11px] text-ink-secondary tabular-nums font-mono">
                        {stageSelectedCount}/{stageClassIds.length}
                      </span>
                    </div>

                    {/* Grades in Stage */}
                    {isStageExpanded && (
                      <div className="pl-4 space-y-0.5 border-l border-border/80 ml-2">
                        {stageGrades.map((grade) => {
                          const gradeClasses = snapshot.classes.filter(
                            (c) => c.gradeId === grade.id
                          );
                          const gradeClassIds = gradeClasses.map((c) => c.id);
                          const gradeSelectedCount = isCurrentStage
                            ? gradeClassIds.filter((id) => selectedClasses.has(id)).length
                            : 0;
                          const gradeAllChecked =
                            isCurrentStage &&
                            gradeClassIds.length > 0 &&
                            gradeSelectedCount === gradeClassIds.length;
                          const isGradeExpanded =
                            expandedGrades.has(grade.id) || classSearch.trim().length > 0;

                          // Filter by search query
                          const query = classSearch.trim().toLowerCase();
                          const matchesQuery =
                            !query ||
                            grade.name.toLowerCase().includes(query) ||
                            gradeClasses.some((c) => c.name.toLowerCase().includes(query));

                          if (!matchesQuery) return null;

                          return (
                            <div key={grade.id} className="space-y-0.5">
                              {/* Grade Item */}
                              <div className="flex items-center justify-between p-1.5 rounded-md hover:bg-surface transition-colors">
                                <div className="flex items-center gap-1.5 flex-1 min-w-0">
                                  <button
                                    type="button"
                                    onClick={() => {
                                      const next = new Set(expandedGrades);
                                      if (next.has(grade.id)) next.delete(grade.id);
                                      else next.add(grade.id);
                                      setExpandedGrades(next);
                                    }}
                                    className="p-0.5 text-ink-secondary hover:text-ink"
                                  >
                                    {isGradeExpanded ? (
                                      <ChevronDown className="h-3.5 w-3.5" />
                                    ) : (
                                      <ChevronRight className="h-3.5 w-3.5" />
                                    )}
                                  </button>
                                  <Checkbox
                                    checked={gradeAllChecked}
                                    onCheckedChange={() =>
                                      handleToggleScope(st.id, gradeClassIds)
                                    }
                                  />
                                  <span
                                    onClick={() =>
                                      handleToggleScope(st.id, gradeClassIds)
                                    }
                                    className="text-xs text-ink font-medium truncate cursor-pointer"
                                  >
                                    {grade.name}
                                  </span>
                                </div>
                                <span className="text-[11px] text-ink-secondary tabular-nums font-mono">
                                  {gradeSelectedCount}/{gradeClassIds.length}
                                </span>
                              </div>

                              {/* Classes in Grade */}
                              {isGradeExpanded && (
                                <div className="pl-6 space-y-0.5">
                                  {gradeClasses.map((cls) => {
                                    if (
                                      query &&
                                      !cls.name.toLowerCase().includes(query) &&
                                      !grade.name.toLowerCase().includes(query)
                                    ) {
                                      return null;
                                    }
                                    const isClassChecked =
                                      isCurrentStage && selectedClasses.has(cls.id);
                                    return (
                                      <label
                                        key={cls.id}
                                        className="flex items-center gap-2 p-1.5 rounded hover:bg-surface cursor-pointer text-xs"
                                      >
                                        <Checkbox
                                          checked={isClassChecked}
                                          onCheckedChange={() =>
                                            handleToggleScope(st.id, [cls.id])
                                          }
                                        />
                                        <span
                                          className={`truncate ${
                                            isClassChecked
                                              ? 'text-primary font-bold'
                                              : 'text-ink'
                                          }`}
                                        >
                                          {cls.name}
                                        </span>
                                      </label>
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
          </div>

          {/* ----- Right Column: 作息课节 · [学段名] ----- */}
          <div className="flex-1 min-w-0 min-h-0 overflow-y-auto p-4 flex flex-col space-y-3 bg-surface">
            {/* Header */}
            <div className="flex items-center justify-between pb-1">
              <div className="flex items-center gap-2">
                <span className="text-xs font-bold text-ink">
                  作息课节 · {stage?.name ?? ''}
                </span>
                <span className="px-2 py-0.5 rounded-full text-xs font-semibold bg-selection text-primary border border-primary/20">
                  已选 {selectedSlots.size} 个课格
                </span>
              </div>
              <div className="text-[11px] text-ink-secondary space-x-1.5">
                <button
                  type="button"
                  disabled={availableSlots.length === 0}
                  onClick={() => handleToggleSlots(availableSlots)}
                  className="text-ink-secondary hover:text-primary font-medium transition-colors disabled:opacity-40"
                >
                  全选可用课节
                </button>
                <span className="text-border">|</span>
                <button
                  type="button"
                  disabled={selectedSlots.size === 0}
                  onClick={() => setSelectedSlots(new Set())}
                  className="text-ink-secondary hover:text-destructive font-medium transition-colors disabled:opacity-40"
                >
                  清空
                </button>
              </div>
            </div>

            {/* Hint alert when no class selected */}
            {selectedClasses.size === 0 && (
              <div className="p-2.5 rounded-lg bg-selection border border-primary/25 text-xs flex items-center gap-2">
                <Info className="h-4 w-4 shrink-0 text-primary" />
                <span className="font-medium text-ink">
                  请先在左侧勾选适用班级，即可查看并点选可安排带班的课节。
                </span>
              </div>
            )}

            {/* Schedule conflict alert */}
            {scheduleErrors.length > 0 && (
              <div className="p-2.5 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive text-xs space-y-0.5">
                {scheduleErrors.map((err, i) => (
                  <div key={i}>• {err}</div>
                ))}
              </div>
            )}

            {/* Timetable Grid */}
            <div className="max-h-[45vh] overflow-auto overscroll-contain rounded-xl border border-border bg-surface shadow-sm">
              <table className="w-full min-w-[640px] text-center border-collapse">
                <thead className="sticky top-0 z-10">
                  <tr className="bg-table-header border-b border-border">
                    <th className="py-2.5 px-3 text-[11px] font-semibold text-ink-secondary w-28 text-center border-r border-border">
                      点击表头批量选
                    </th>
                    {teachingWeekdays.map((day) => {
                      const daySlots = availableSlots.filter((s) => s.weekday === day);
                      return (
                        <th
                          key={day}
                          onClick={() => handleToggleSlots(daySlots)}
                          className="py-2.5 px-2 text-xs font-bold text-ink cursor-pointer hover:bg-canvas transition-colors border-r border-border last:border-r-0"
                          title="点击反选全天可用课节"
                        >
                          {WEEKDAYS[day - 1]}
                        </th>
                      );
                    })}
                  </tr>
                </thead>
                <tbody className="divide-y divide-border/70">
                  {(() => {
                    const rows: React.ReactNode[] = [];
                    let previousPeriod: (typeof periods)[0] | null = null;

                    for (const period of periods) {
                      const periodMaxLessons = teachingWeekdays.reduce(
                        (max, day) =>
                          Math.max(
                            max,
                            routine ? effectiveLessonCount(routine, period.id, day) : 0
                          ),
                        0
                      );

                      for (let index = 1; index <= periodMaxLessons; index++) {
                        // Check for lunch gap divider
                        let prevEnd: number | null = null;
                        if (index > 1) {
                          const prevTime = routine?.lessonTimes.find(
                            (t) => t.periodTypeId === period.id && t.lessonIndex === index - 1
                          );
                          prevEnd = prevTime?.endMinute ?? null;
                        } else if (previousPeriod) {
                          const prevPeriodTimes = routine?.lessonTimes.filter(
                            (t) => t.periodTypeId === previousPeriod!.id
                          ) ?? [];
                          for (const t of prevPeriodTimes) {
                            if (t.endMinute && (!prevEnd || t.endMinute > prevEnd)) {
                              prevEnd = t.endMinute;
                            }
                          }
                        }
                        const currTime = routine?.lessonTimes.find(
                          (t) => t.periodTypeId === period.id && t.lessonIndex === index
                        );
                        const currStart = currTime?.startMinute ?? null;

                        if (isLunchGap(prevEnd, currStart)) {
                          rows.push(
                            <tr key={`lunch_${period.id}_${index}`} className="bg-table-header border-y border-border">
                              <td
                                colSpan={teachingWeekdays.length + 1}
                                className="py-1 px-3 text-[10px] text-ink-secondary font-medium tracking-wider"
                              >
                                — 午休分隔 · 下午时段 —
                              </td>
                            </tr>
                          );
                        }

                        // Time label
                        const timeText =
                          currTime?.startMinute != null && currTime?.endMinute != null
                            ? `${String(Math.floor(currTime.startMinute / 60)).padStart(2, '0')}:${String(currTime.startMinute % 60).padStart(2, '0')}–${String(Math.floor(currTime.endMinute / 60)).padStart(2, '0')}:${String(currTime.endMinute % 60).padStart(2, '0')}`
                            : '';

                        const rowSlots = availableSlots.filter(
                          (s) => s.periodId === period.id && s.index === index
                        );

                        rows.push(
                          <tr key={`${period.id}_${index}`} className="h-12 hover:bg-canvas/30 transition-colors">
                            {/* Row Header */}
                            <td
                              onClick={() => handleToggleSlots(rowSlots)}
                              className="py-1.5 px-2 border-r border-border text-center cursor-pointer hover:bg-canvas transition-colors bg-surface"
                              title="点击反选整行可用课节"
                            >
                              <div className="font-semibold text-xs text-ink">
                                第 {index} 节
                              </div>
                              {timeText && (
                                <div className="text-[10px] text-ink-secondary tabular-nums font-mono">
                                  {timeText}
                                </div>
                              )}
                            </td>

                            {/* Slot Cells */}
                            {teachingWeekdays.map((day) => {
                              const slot: PostSlot = {
                                weekday: day,
                                periodId: period.id,
                                index,
                              };
                              const key = `${day}:${period.id}:${index}`;
                              const isSelected = selectedSlots.has(key);
                              const reason = getSlotReason(slot);
                              const isDisabled = reason !== null;

                              return (
                                <td
                                  key={day}
                                  className="p-1 border-r border-border last:border-r-0"
                                >
                                  <button
                                    type="button"
                                    disabled={isDisabled}
                                    onClick={() => handleToggleSlots([slot])}
                                    className={`w-full h-10 rounded-lg text-xs transition-all flex items-center justify-center relative overflow-hidden ${
                                      isSelected
                                        ? 'bg-primary text-primary-foreground font-semibold shadow-sm'
                                        : isDisabled
                                        ? 'bg-canvas text-ink-secondary/70 cursor-not-allowed border border-dashed border-border'
                                        : 'border border-emerald-500/50 bg-surface text-ink hover:border-primary hover:bg-selection/40 cursor-pointer'
                                    }`}
                                    style={
                                      isDisabled
                                        ? {
                                            backgroundImage:
                                              'repeating-linear-gradient(45deg, rgba(94,107,128,0.08), rgba(94,107,128,0.08) 4px, transparent 4px, transparent 8px)',
                                          }
                                        : undefined
                                    }
                                  >
                                    {isSelected ? (
                                      <Check className="h-4 w-4" />
                                    ) : (
                                      <span className="text-[11px] font-medium truncate px-1">
                                        {reason ?? ''}
                                      </span>
                                    )}
                                  </button>
                                </td>
                              );
                            })}
                          </tr>
                        );
                      }
                      previousPeriod = period;
                    }
                    return rows;
                  })()}
                </tbody>
              </table>
            </div>

            {/* Grid Legend & Tip */}
            <div className="flex flex-wrap items-center justify-between gap-3 text-xs pt-1">
              <div className="flex items-center gap-4">
                <div className="flex items-center gap-1.5">
                  <div
                    className="w-3.5 h-3.5 rounded border border-border"
                    style={{
                      backgroundImage:
                        'repeating-linear-gradient(45deg, rgba(94,107,128,0.18), rgba(94,107,128,0.18) 2px, transparent 2px, transparent 4px)',
                    }}
                  />
                  <span className="text-[11px] text-ink font-medium">正课 / 不可用</span>
                </div>

                <div className="flex items-center gap-1.5">
                  <div className="w-3.5 h-3.5 rounded border-2 border-emerald-500 bg-surface" />
                  <span className="text-[11px] text-ink font-medium">可安排带班</span>
                </div>

                <div className="flex items-center gap-1.5">
                  <div className="w-3.5 h-3.5 rounded bg-primary text-primary-foreground flex items-center justify-center">
                    <Check className="h-2.5 w-2.5" />
                  </div>
                  <span className="text-[11px] text-ink font-medium">已选课节</span>
                </div>
              </div>

              <span className="text-[11px] text-ink-secondary">
                提示：点击行首节次或列首星期可快速反选
              </span>
            </div>

            {/* 排班方式 Cards */}
            <div className="pt-2 space-y-2">
              <span className="text-xs font-bold text-ink block">排班方式</span>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {/* Continuous toggle card */}
                <div className="p-3 rounded-xl border border-border bg-surface flex items-start gap-3">
                  <Switch
                    checked={continuous}
                    onCheckedChange={setContinuous}
                    className="mt-0.5"
                  />
                  <div className="space-y-0.5 text-xs">
                    <span className="font-semibold text-ink block">
                      连续节次由同一老师负责
                    </span>
                    <span className="text-[11px] text-ink-secondary block">
                      合并同日同午相邻已选课节，减少频繁换人。
                    </span>
                  </div>
                </div>

                {/* Merged classes toggle card */}
                <div className="p-3 rounded-xl border border-border bg-surface space-y-2">
                  <div className="flex items-start gap-3">
                    <Switch
                      checked={merged}
                      onCheckedChange={(val) => {
                        setMerged(val);
                        setGroupNameError(null);
                        setLocationError(null);
                      }}
                      className="mt-0.5 data-[state=unchecked]:bg-control-border data-[state=unchecked]:ring-1 data-[state=unchecked]:ring-control-border"
                    />
                    <div className="space-y-0.5 text-xs">
                      <span className="font-semibold text-ink block">实际合班教学</span>
                      <span className="text-[11px] text-ink-secondary block">
                        将所选多个班级合并为一个共享带班岗位。
                      </span>
                    </div>
                  </div>

                  {merged && (
                    <div className="pt-2 border-t border-border grid grid-cols-2 gap-2 animate-in fade-in">
                      <div>
                        <Input
                          value={groupName}
                          onChange={(e) => {
                            setGroupName(e.target.value);
                            setGroupNameError(null);
                          }}
                          placeholder="活动组名称 (如合班自习)"
                          className="h-7 text-xs text-ink"
                        />
                        {groupNameError && (
                          <span className="text-[10px] text-destructive mt-0.5 block font-medium">
                            {groupNameError}
                          </span>
                        )}
                      </div>
                      <div>
                        <Input
                          value={location}
                          onChange={(e) => {
                            setLocation(e.target.value);
                            setLocationError(null);
                          }}
                          placeholder="活动地点 (如阶梯教室)"
                          className="h-7 text-xs text-ink"
                        />
                        {locationError && (
                          <span className="text-[10px] text-destructive mt-0.5 block font-medium">
                            {locationError}
                          </span>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* ================= 3. Bottom Footer ================= */}
        <div className="shrink-0 bg-canvas border-t border-border px-6 py-3 flex items-center justify-between gap-3">
          <div className="text-xs text-ink-secondary">
            已选 <span className="font-bold text-ink">{selectedClasses.size}</span> 个班级
            × <span className="font-bold text-ink">{selectedSlots.size}</span> 个课格 =
            将创建{' '}
            <span className="font-bold text-primary text-sm">
              {totalCalculatedPostsCount}
            </span>{' '}
            个带班岗位
          </div>

          <div className="flex items-center gap-2">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={() => onOpenChange(false)}
              className="text-ink-secondary hover:text-ink"
            >
              取消
            </Button>
            <Button
              type="button"
              size="sm"
              disabled={totalCalculatedPostsCount === 0}
              onClick={handleSubmit}
              className="bg-primary text-primary-foreground font-semibold px-4 hover:opacity-90"
            >
              添加岗位
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};
