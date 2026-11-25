import React, { useMemo, useState } from 'react';
import {
  Ban,
  Plus,
  Search,
  Settings2,
  Trash2,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import type { ScheduleData } from '@/domain/scheduling';
import type { StageRoutine } from '@/domain/models';
import type {
  SchedulePosition,
  SupervisionDraft,
  SupervisionMatchingPreferences,
  SupervisionMatchRequirement,
  SupervisionPreference,
  SupervisionTeacherPool,
  SupervisionTeacherRule,
} from '@/domain/supervision';
import {
  SUPERVISION_BASE_POOL_ID,
  SUPERVISION_PREFERENCE_LABELS,
  overlaps,
  sameCell,
} from '@/domain/supervision';
import {
  effectiveLessonCount,
  isSupervisionAllowedInSlot,
  resolveFreeSlotForClass,
  withRoutineClock,
} from '@/domain/supervisionValidation';

interface TeacherPoolDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  snapshot: ScheduleData;
  draft: SupervisionDraft;
  onSave: (updatedDraft: SupervisionDraft) => void;
}

const WEEKDAYS = [
  { value: 1, label: '周一' },
  { value: 2, label: '周二' },
  { value: 3, label: '周三' },
  { value: 4, label: '周四' },
  { value: 5, label: '周五' },
  { value: 6, label: '周六' },
  { value: 7, label: '周日' },
];

type RuleGridRow = {
  period: StageRoutine['periodTypes'][number];
  lessonIndex: number;
};

const ruleSlotKey = (weekday: number, periodTypeId: string, lessonIndex: number) =>
  `${weekday}|${periodTypeId}|${lessonIndex}`;

function schedulableRuleSlots(
  snapshot: ScheduleData,
  draft: SupervisionDraft,
  routine: StageRoutine
): Set<string> {
  const grades = new Map(snapshot.grades.map((grade) => [grade.id, grade]));
  const classes = snapshot.classes.filter(
    (schoolClass) => grades.get(schoolClass.gradeId)?.stageId === routine.stageId
  );

  const schedulable = new Set<string>();
  const teachingDays = routine.teachingDays
    .filter((day) => day.isTeachingDay)
    .map((day) => day.weekday);

  for (const weekday of teachingDays) {
    for (const period of routine.periodTypes) {
      const count = effectiveLessonCount(routine, period.id, weekday);
      for (let lessonIndex = 1; lessonIndex <= count; lessonIndex++) {
        const position = withRoutineClock(snapshot, {
          stageId: routine.stageId,
          weekday,
          periodTypeId: period.id,
          lessonIndex,
        });
        const hasAvailableClass = classes.some((schoolClass) => {
          const freeSlot = resolveFreeSlotForClass(
            snapshot.freeSlots,
            draft.termId,
            routine.stageId,
            schoolClass.gradeId,
            schoolClass.id,
            weekday,
            period.id,
            lessonIndex
          );
          if (freeSlot && !isSupervisionAllowedInSlot(freeSlot)) return false;

          const hasRegularLesson = snapshot.items.some((item) => {
            if (
              item.classId !== schoolClass.id ||
              item.weekday !== weekday ||
              item.periodTypeId == null ||
              item.lessonIndex == null
            ) {
              return false;
            }
            const itemPosition = withRoutineClock(snapshot, {
              stageId: item.stageId ?? routine.stageId,
              weekday,
              periodTypeId: item.periodTypeId,
              lessonIndex: item.lessonIndex,
            });
            return overlaps(position, itemPosition);
          });
          return !hasRegularLesson;
        });

        if (hasAvailableClass) {
          schedulable.add(ruleSlotKey(weekday, period.id, lessonIndex));
        }
      }
    }
  }

  return schedulable;
}

export const TeacherPoolDialog: React.FC<TeacherPoolDialogProps> = ({
  open,
  onOpenChange,
  snapshot,
  draft,
  onSave,
}) => {
  const [activeTab, setActiveTab] = useState<'pools' | 'rules' | 'matching'>('pools');

  // Pools state
  const [pools, setPools] = useState<SupervisionTeacherPool[]>(
    draft.teacherPools ?? []
  );
  const [defaultPoolId, setDefaultPoolId] = useState<string | null>(
    draft.defaultTeacherPoolId ?? null
  );
  const [selectedPoolId, setSelectedPoolId] = useState<string>(
    pools[0]?.id ?? SUPERVISION_BASE_POOL_ID
  );
  const [newPoolName, setNewPoolName] = useState('');
  const [poolTeacherSearch, setPoolTeacherSearch] = useState('');

  // Rules state
  const [rules, setRules] = useState<Record<string, SupervisionTeacherRule>>(
    draft.rules ?? {}
  );
  const [selectedTeacherId, setSelectedTeacherId] = useState<string>(
    snapshot.teachers[0]?.id ?? ''
  );
  const [ruleTeacherSearch, setRuleTeacherSearch] = useState('');
  const [selectedRuleStageId, setSelectedRuleStageId] = useState(
    snapshot.routines[0]?.stageId ?? ''
  );

  // Matching preferences state
  const [matchingPrefs, setMatchingPrefs] = useState<SupervisionMatchingPreferences>(
    draft.matchingPreferences
  );

  // Handlers for pools
  const handleAddPool = () => {
    if (!newPoolName.trim()) return;
    const newPool: SupervisionTeacherPool = {
      id: `pool_${Date.now()}`,
      name: newPoolName.trim(),
      teacherIds: snapshot.teachers.map((t) => t.id), // default to all
    };
    setPools([...pools, newPool]);
    setSelectedPoolId(newPool.id);
    setNewPoolName('');
  };

  const handleDeletePool = (id: string) => {
    setPools(pools.filter((p) => p.id !== id));
    if (defaultPoolId === id) setDefaultPoolId(null);
    if (selectedPoolId === id) setSelectedPoolId(SUPERVISION_BASE_POOL_ID);
  };

  const handleToggleTeacherInPool = (poolId: string, teacherId: string) => {
    setPools((current) =>
      current.map((pool) => {
        if (pool.id !== poolId) return pool;
        const exists = pool.teacherIds.includes(teacherId);
        return {
          ...pool,
          teacherIds: exists
            ? pool.teacherIds.filter((id) => id !== teacherId)
            : [...pool.teacherIds, teacherId],
        };
      })
    );
  };

  // Handlers for teacher rules
  const currentRule = rules[selectedTeacherId] ?? {};

  const handleUpdateRule = (partial: Partial<SupervisionTeacherRule>) => {
    setRules({
      ...rules,
      [selectedTeacherId]: {
        ...currentRule,
        ...partial,
      },
    });
  };

  const handleToggleUnavailableCell = (
    stageId: string,
    weekday: number,
    periodTypeId: string,
    lessonIndex: number
  ) => {
    const unav = currentRule.unavailable ?? [];
    const cell: SchedulePosition = { stageId, weekday, periodTypeId, lessonIndex };
    const exists = unav.some((u) => sameCell(u, cell));
    const nextUnav = exists
      ? unav.filter((u) => !sameCell(u, cell))
      : [...unav, cell];
    handleUpdateRule({ unavailable: nextUnav });
  };

  // Handlers for matching preferences
  const handleTogglePref = (pref: SupervisionPreference) => {
    const enabled = matchingPrefs.enabled.includes(pref)
      ? matchingPrefs.enabled.filter((p) => p !== pref)
      : [...matchingPrefs.enabled, pref];
    setMatchingPrefs({ ...matchingPrefs, enabled });
  };

  const handleSaveAll = () => {
    const updatedDraft: SupervisionDraft = {
      ...draft,
      teacherPools: pools,
      defaultTeacherPoolId: defaultPoolId,
      rules,
      matchingPreferences: matchingPrefs,
    };
    onSave(updatedDraft);
    onOpenChange(false);
  };

  const currentPool = pools.find((pool) => pool.id === selectedPoolId);
  const visiblePoolTeachers = snapshot.teachers.filter((teacher) =>
    teacher.name.toLocaleLowerCase().includes(poolTeacherSearch.trim().toLocaleLowerCase())
  );
  const selectedVisibleTeacherIds = new Set(currentPool?.teacherIds ?? []);
  const allVisiblePoolTeachersSelected =
    visiblePoolTeachers.length > 0 &&
    visiblePoolTeachers.every((teacher) => selectedVisibleTeacherIds.has(teacher.id));
  const visibleRuleTeachers = snapshot.teachers.filter((teacher) =>
    teacher.name.toLocaleLowerCase().includes(ruleTeacherSearch.trim().toLocaleLowerCase())
  );
  const activeRuleRoutine =
    snapshot.routines.find((routine) => routine.stageId === selectedRuleStageId) ??
    snapshot.routines[0];
  const ruleGrid = useMemo(() => {
    if (!activeRuleRoutine) {
      return {
        slotKeys: new Set<string>(),
        weekdays: [] as number[],
        rows: [] as RuleGridRow[],
      };
    }

    const slotKeys = schedulableRuleSlots(snapshot, draft, activeRuleRoutine);
    const weekdays = activeRuleRoutine.teachingDays
      .filter((day) => day.isTeachingDay)
      .map((day) => day.weekday)
      .sort((a, b) => a - b)
      .filter((weekday) =>
        [...slotKeys].some((key) => key.startsWith(`${weekday}|`))
      );
    const rows = [...activeRuleRoutine.periodTypes]
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .flatMap((period) => {
        const maxCount = Math.max(
          0,
          ...weekdays.map((weekday) => effectiveLessonCount(activeRuleRoutine, period.id, weekday))
        );
        return Array.from({ length: maxCount }, (_, index) => ({
          period,
          lessonIndex: index + 1,
        })).filter((row) =>
          weekdays.some((weekday) =>
            slotKeys.has(ruleSlotKey(weekday, period.id, row.lessonIndex))
          )
        );
      });

    return { slotKeys, weekdays, rows };
  }, [activeRuleRoutine, draft, snapshot]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] flex flex-col p-6 overflow-hidden">
        <DialogHeader className="pb-3 border-b border-border">
          <DialogTitle className="text-lg font-semibold text-ink flex items-center gap-2">
            <Settings2 className="h-5 w-5 text-primary" />
            候选池与人员规则
          </DialogTitle>
          <DialogDescription className="text-xs text-ink-secondary">
            设置教师候选池、带班上限、禁排时段以及智能匹配排序偏好。
          </DialogDescription>
        </DialogHeader>

        {/* Tab switcher */}
        <div className="pt-2">
          <Tabs
            value={activeTab}
            onValueChange={(v) => setActiveTab(v as 'pools' | 'rules' | 'matching')}
          >
            <TabsList className="grid grid-cols-3 w-full">
              <TabsTrigger value="pools" className="text-xs">
                候选池分组 ({pools.length + 1})
              </TabsTrigger>
              <TabsTrigger value="rules" className="text-xs">
                带班上限与禁排
              </TabsTrigger>
              <TabsTrigger value="matching" className="text-xs">
                匹配偏好规则
              </TabsTrigger>
            </TabsList>
          </Tabs>
        </div>

        <div className="flex-1 overflow-y-auto py-3 space-y-4 text-xs">
          {/* TAB 1: 候选池 */}
          {activeTab === 'pools' && (
            <div className="grid grid-cols-3 gap-4 h-full min-h-[380px]">
              {/* Left: Pool list */}
              <div className="border border-border rounded-lg p-2.5 space-y-2 bg-canvas/30 flex flex-col">
                <span className="font-semibold text-ink-secondary text-[11px] uppercase tracking-wider block">
                  候选池列表
                </span>

                <div className="flex-1 overflow-y-auto space-y-1">
                  <div
                    onClick={() => setSelectedPoolId(SUPERVISION_BASE_POOL_ID)}
                    className={`p-2 rounded-md flex items-center justify-between cursor-pointer transition-colors ${
                      selectedPoolId === SUPERVISION_BASE_POOL_ID
                        ? 'bg-selection text-primary font-medium'
                        : 'hover:bg-canvas text-ink'
                    }`}
                  >
                    <div>
                      <div className="font-medium">基础候选池 (全校)</div>
                      <div className="text-[10px] text-ink-secondary">
                        {snapshot.teachers.length} 位教师
                      </div>
                    </div>
                    {defaultPoolId === null && (
                      <Badge variant="outline" className="text-[10px] h-4">
                        默认
                      </Badge>
                    )}
                  </div>

                  {pools.map((pool) => (
                    <div
                      key={pool.id}
                      onClick={() => setSelectedPoolId(pool.id)}
                      className={`p-2 rounded-md flex items-center justify-between cursor-pointer transition-colors ${
                        selectedPoolId === pool.id
                          ? 'bg-selection text-primary font-medium'
                          : 'hover:bg-canvas text-ink'
                      }`}
                    >
                      <div className="min-w-0 pr-2">
                        <div className="font-medium truncate">{pool.name}</div>
                        <div className="text-[10px] text-ink-secondary">
                          {pool.teacherIds.length} 位教师
                        </div>
                      </div>
                      <div className="flex items-center gap-1">
                        {defaultPoolId === pool.id && (
                          <Badge variant="outline" className="text-[10px] h-4">
                            默认
                          </Badge>
                        )}
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            handleDeletePool(pool.id);
                          }}
                          className="text-ink-secondary hover:text-destructive p-1 rounded"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </button>
                      </div>
                    </div>
                  ))}
                </div>

                <div className="pt-2 border-t border-border flex gap-1.5">
                  <Input
                    value={newPoolName}
                    onChange={(e) => setNewPoolName(e.target.value)}
                    placeholder="新增池名称..."
                    className="h-7 text-xs"
                  />
                  <Button
                    type="button"
                    size="sm"
                    onClick={handleAddPool}
                    className="h-7 px-2"
                  >
                    <Plus className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>

              {/* Right: Pool teachers selection */}
              <div className="col-span-2 border border-border rounded-lg p-3 space-y-3 flex flex-col bg-surface">
                <div className="flex items-center justify-between pb-2 border-b border-border">
                  <div>
                    <h4 className="font-semibold text-ink text-sm">
                      {selectedPoolId === SUPERVISION_BASE_POOL_ID
                        ? '基础候选池'
                        : pools.find((p) => p.id === selectedPoolId)?.name ?? ''}
                    </h4>
                    <span className="text-ink-secondary text-[11px]">
                      {selectedPoolId === SUPERVISION_BASE_POOL_ID
                        ? '包含全校所有已注册的任课教师'
                        : '勾选属于此候选池的教师，岗位指派时仅从该池内匹配。'}
                    </span>
                  </div>

                  {selectedPoolId !== SUPERVISION_BASE_POOL_ID && (
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() =>
                        setDefaultPoolId(
                          defaultPoolId === selectedPoolId ? null : selectedPoolId
                        )
                      }
                      className="h-7 text-xs"
                    >
                      {defaultPoolId === selectedPoolId ? '取消设为默认' : '设为默认池'}
                    </Button>
                  )}
                </div>

                {selectedPoolId === SUPERVISION_BASE_POOL_ID ? (
                  <div className="flex-1 flex items-center justify-center text-ink-secondary text-xs">
                    基础候选池默认包含全校全部教师，无需手动配置。
                  </div>
                ) : (
                  <div className="flex min-h-0 flex-1 flex-col gap-2">
                    <div className="flex items-center gap-2">
                      <div className="relative min-w-0 flex-1">
                        <Search className="absolute left-2.5 top-2 h-3.5 w-3.5 text-ink-secondary" />
                        <Input
                          value={poolTeacherSearch}
                          onChange={(event) => setPoolTeacherSearch(event.target.value)}
                          placeholder="搜索候选池教师..."
                          aria-label="搜索候选池教师"
                          className="h-7 pl-8 text-xs"
                        />
                      </div>
                      <span className="shrink-0 text-[11px] text-ink-secondary">
                        已选 {currentPool?.teacherIds.length ?? 0} / {snapshot.teachers.length} 人
                      </span>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        disabled={visiblePoolTeachers.length === 0}
                        onClick={() => {
                          const visibleIds = new Set(visiblePoolTeachers.map((teacher) => teacher.id));
                          setPools((current) =>
                            current.map((pool) =>
                              pool.id !== selectedPoolId
                                ? pool
                                : {
                                    ...pool,
                                    teacherIds: allVisiblePoolTeachersSelected
                                      ? pool.teacherIds.filter((id) => !visibleIds.has(id))
                                      : [...new Set([...pool.teacherIds, ...visibleIds])],
                                  }
                            )
                          );
                        }}
                        className="h-7 shrink-0 px-2 text-xs"
                      >
                        {allVisiblePoolTeachersSelected ? '取消全选' : '全选'}
                      </Button>
                    </div>
                    <div className="min-h-0 flex-1 overflow-y-auto">
                      {visiblePoolTeachers.length > 0 ? (
                        <div className="grid grid-cols-3 gap-2 pr-1">
                          {visiblePoolTeachers.map((teacher) => {
                            const isChecked = currentPool?.teacherIds.includes(teacher.id) ?? false;
                            return (
                              <label
                                key={teacher.id}
                                className={`flex items-center gap-2 p-2 rounded border cursor-pointer transition-colors ${
                                  isChecked
                                    ? 'bg-selection/60 border-primary/40 text-primary font-medium'
                                    : 'border-border/60 hover:bg-canvas text-ink'
                                }`}
                              >
                                <Checkbox
                                  checked={isChecked}
                                  onCheckedChange={() =>
                                    handleToggleTeacherInPool(selectedPoolId, teacher.id)
                                  }
                                />
                                <span className="truncate">{teacher.name}</span>
                              </label>
                            );
                          })}
                        </div>
                      ) : (
                        <div className="py-8 text-center text-xs text-ink-secondary">
                          没有匹配的教师
                        </div>
                      )}
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* TAB 2: 带班上限与禁排 */}
          {activeTab === 'rules' && (
            <div className="grid grid-cols-4 gap-4 h-full min-h-[380px]">
              {/* Teacher list selector */}
              <div className="border border-border rounded-lg p-2.5 space-y-1.5 flex min-h-0 max-h-[420px] flex-col bg-canvas/30">
                <span className="font-semibold text-ink-secondary text-[11px] uppercase tracking-wider block mb-2">
                  选择教师
                </span>
                <div className="relative mb-2 shrink-0">
                  <Search className="absolute left-2.5 top-2 h-3.5 w-3.5 text-ink-secondary" />
                  <Input
                    value={ruleTeacherSearch}
                    onChange={(event) => setRuleTeacherSearch(event.target.value)}
                    placeholder="搜索教师姓名..."
                    aria-label="搜索规则教师"
                    className="h-7 pl-8 text-xs"
                  />
                </div>
                <div className="min-h-0 flex-1 overflow-y-auto space-y-1.5">
                  {visibleRuleTeachers.map((teacher) => {
                    const rule = rules[teacher.id];
                    const hasRule =
                      rule &&
                      (rule.maxLessons != null ||
                        rule.maxDays != null ||
                        (rule.unavailable && rule.unavailable.length > 0));
                    return (
                      <div
                        key={teacher.id}
                        onClick={() => setSelectedTeacherId(teacher.id)}
                        className={`p-2 rounded-md flex items-center justify-between cursor-pointer transition-colors ${
                          selectedTeacherId === teacher.id
                            ? 'bg-selection text-primary font-medium'
                            : 'hover:bg-canvas text-ink'
                        }`}
                      >
                        <span className="truncate">{teacher.name}</span>
                        {hasRule && (
                          <span className="h-1.5 w-1.5 rounded-full bg-primary" />
                        )}
                      </div>
                    );
                  })}
                  {visibleRuleTeachers.length === 0 && (
                    <div className="py-6 text-center text-xs text-ink-secondary">
                      没有匹配的教师
                    </div>
                  )}
                </div>
              </div>

              {/* Teacher rule details & timetable grid */}
              <div className="col-span-3 border border-border rounded-lg p-3 space-y-4 bg-surface flex flex-col">
                <div className="flex items-center justify-between pb-2 border-b border-border">
                  <div>
                    <h4 className="font-semibold text-ink text-sm">
                      {snapshot.teachers.find((t) => t.id === selectedTeacherId)?.name ?? ''}{' '}
                      · 带班规则
                    </h4>
                    <span className="text-ink-secondary text-[11px]">
                      限制该教师每周最多带班节次与天数，或点击课节设置带班禁排。
                    </span>
                  </div>
                </div>

                {/* Limits */}
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="text-xs font-medium text-ink mb-1 block">
                      每周最多带班节次 (留空表示不限制)
                    </label>
                    <Input
                      type="number"
                      min={0}
                      value={currentRule.maxLessons ?? ''}
                      onChange={(e) => {
                        const val = e.target.value.trim() ? parseInt(e.target.value, 10) : null;
                        handleUpdateRule({ maxLessons: val });
                      }}
                      placeholder="无限制"
                      className="h-8 text-xs"
                    />
                  </div>

                  <div>
                    <label className="text-xs font-medium text-ink mb-1 block">
                      每周最多带班天数 (留空表示不限制，最多 7)
                    </label>
                    <Input
                      type="number"
                      min={0}
                      max={7}
                      value={currentRule.maxDays ?? ''}
                      onChange={(e) => {
                        const val = e.target.value.trim() ? parseInt(e.target.value, 10) : null;
                        handleUpdateRule({ maxDays: val });
                      }}
                      placeholder="无限制"
                      className="h-8 text-xs"
                    />
                  </div>
                </div>

                {/* Unavailable timetable grid */}
                <div className="space-y-1.5 flex-1 flex flex-col min-h-0">
                  <div className="flex items-center justify-between">
                    <label className="text-xs font-medium text-ink flex items-center gap-1.5">
                      <Ban className="h-3.5 w-3.5 text-destructive" />
                      带班禁排节次 (点击可切换禁排)
                    </label>
                    <div className="flex items-center gap-2">
                      {snapshot.routines.length > 1 && (
                        <Select
                          value={activeRuleRoutine?.stageId ?? ''}
                          onValueChange={setSelectedRuleStageId}
                        >
                          <SelectTrigger className="h-7 w-28 text-xs">
                            <SelectValue placeholder="选择学段" />
                          </SelectTrigger>
                          <SelectContent>
                            {snapshot.routines.map((routine) => (
                              <SelectItem key={routine.stageId} value={routine.stageId}>
                                {snapshot.stages.find((stage) => stage.id === routine.stageId)?.name ?? '未命名学段'}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      )}
                      {activeRuleRoutine &&
                        currentRule.unavailable?.some(
                          (position) => position.stageId === activeRuleRoutine.stageId
                        ) && (
                          <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            onClick={() =>
                              handleUpdateRule({
                                unavailable: (currentRule.unavailable ?? []).filter(
                                  (position) => position.stageId !== activeRuleRoutine.stageId
                                ),
                              })
                            }
                            className="h-6 text-[11px] text-destructive hover:text-destructive px-2"
                          >
                            清空禁排
                          </Button>
                        )}
                    </div>
                  </div>

                  {activeRuleRoutine ? (
                    <div className="border border-border rounded-lg overflow-auto p-2 bg-canvas/30 flex-1">
                      <table className="w-full text-center border-collapse">
                        <thead>
                          <tr className="border-b border-border/80">
                            <th className="p-1 text-[11px] font-medium text-ink-secondary w-16">
                              时段
                            </th>
                            {ruleGrid.weekdays.map((weekday) => {
                              const day = WEEKDAYS.find((item) => item.value === weekday);
                              return (
                                <th
                                  key={weekday}
                                  className="p-1 text-[11px] font-medium text-ink"
                                >
                                  {day?.label ?? `周${weekday}`}
                                </th>
                              );
                            })}
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-border/60">
                          {ruleGrid.rows.map(({ period, lessonIndex }) => (
                            <tr key={`${period.id}_${lessonIndex}`} className="h-7">
                              <td className="text-[10px] text-ink-secondary font-medium">
                                {period.name} {lessonIndex}
                              </td>
                              {ruleGrid.weekdays.map((weekday) => {
                                const isSchedulable = ruleGrid.slotKeys.has(
                                  ruleSlotKey(weekday, period.id, lessonIndex)
                                );
                                if (!isSchedulable) {
                                  return (
                                    <td
                                      key={weekday}
                                      className="p-0.5 text-[10px] text-ink-secondary/30"
                                    >
                                      —
                                    </td>
                                  );
                                }

                                const cell: SchedulePosition = {
                                  stageId: activeRuleRoutine.stageId,
                                  weekday,
                                  periodTypeId: period.id,
                                  lessonIndex,
                                };
                                const isBanned = (currentRule.unavailable ?? []).some((u) =>
                                  sameCell(u, cell)
                                );
                                const dayLabel =
                                  WEEKDAYS.find((item) => item.value === weekday)?.label ??
                                  `周${weekday}`;

                                return (
                                  <td key={weekday} className="p-0.5">
                                    <button
                                      type="button"
                                      aria-pressed={isBanned}
                                      aria-label={`${dayLabel} ${period.name} ${lessonIndex}节${isBanned ? '取消禁排' : '设为禁排'}`}
                                      onClick={() =>
                                        handleToggleUnavailableCell(
                                          activeRuleRoutine.stageId,
                                          weekday,
                                          period.id,
                                          lessonIndex
                                        )
                                      }
                                      className={`w-full h-6 rounded flex items-center justify-center transition-colors ${
                                        isBanned
                                          ? 'bg-destructive/20 text-destructive font-bold text-[10px] border border-destructive/30'
                                          : 'hover:bg-canvas text-ink-secondary/30 text-[10px]'
                                      }`}
                                    >
                                      {isBanned ? '禁' : '—'}
                                    </button>
                                  </td>
                                );
                              })}
                            </tr>
                          ))}
                        </tbody>
                      </table>
                      {ruleGrid.rows.length === 0 && (
                        <div className="py-8 text-center text-xs text-ink-secondary">
                          当前学段没有可排班的节次
                        </div>
                      )}
                    </div>
                  ) : (
                    <div className="flex flex-1 items-center justify-center rounded-lg border border-dashed border-border text-xs text-ink-secondary">
                      尚未设置学段作息
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* TAB 3: 匹配偏好 */}
          {activeTab === 'matching' && (
            <div className="space-y-5 max-w-xl mx-auto py-2">
              <div className="space-y-3">
                <h4 className="text-xs font-semibold text-ink uppercase tracking-wider">
                  匹配偏好优先级
                </h4>
                <div className="space-y-2 border border-border rounded-lg p-3 bg-surface">
                  {(['classTeacher', 'gradeTeacher', 'subjectTeacher'] as SupervisionPreference[]).map(
                    (pref) => {
                      const enabled = matchingPrefs.enabled.includes(pref);
                      return (
                        <div
                          key={pref}
                          className="flex items-center justify-between p-2.5 rounded-md border border-border/70 bg-canvas/30"
                        >
                          <div className="flex items-center gap-2.5">
                            <Checkbox
                              checked={enabled}
                              onCheckedChange={() => handleTogglePref(pref)}
                            />
                            <span className="font-medium text-ink text-xs">
                              {SUPERVISION_PREFERENCE_LABELS[pref]}
                            </span>
                          </div>
                          <span className="text-[11px] text-ink-secondary">
                            {pref === 'classTeacher'
                              ? '优先安排正在教该班级正课的任课老师'
                              : pref === 'gradeTeacher'
                              ? '优先安排正在该年级教学的任课老师'
                              : '若岗位指定了目标学科，优先安排该科老师'}
                          </span>
                        </div>
                      );
                    }
                  )}
                </div>
              </div>

              {/* Mode */}
              <div className="space-y-2">
                <h4 className="text-xs font-semibold text-ink uppercase tracking-wider">
                  智能分配策略
                </h4>
                <div className="grid grid-cols-2 gap-3">
                  <div
                    onClick={() =>
                      setMatchingPrefs({ ...matchingPrefs, mode: 'matchFirst' })
                    }
                    className={`p-3 rounded-lg border cursor-pointer transition-all ${
                      matchingPrefs.mode === 'matchFirst'
                        ? 'bg-selection border-primary text-primary font-medium'
                        : 'border-border hover:bg-canvas text-ink'
                    }`}
                  >
                    <div className="font-semibold text-xs mb-1">优先满足匹配条件</div>
                    <div className="text-[11px] text-ink-secondary">
                      最大化任教班级或年级吻合度，适合注重师生熟悉度的学校。
                    </div>
                  </div>

                  <div
                    onClick={() =>
                      setMatchingPrefs({ ...matchingPrefs, mode: 'balanceFirst' })
                    }
                    className={`p-3 rounded-lg border cursor-pointer transition-all ${
                      matchingPrefs.mode === 'balanceFirst'
                        ? 'bg-selection border-primary text-primary font-medium'
                        : 'border-border hover:bg-canvas text-ink'
                    }`}
                  >
                    <div className="font-semibold text-xs mb-1">兼顾工作量均衡</div>
                    <div className="text-[11px] text-ink-secondary">
                      优先将带班分配给当前带班较少的教师，平衡全体教师带班负荷。
                    </div>
                  </div>
                </div>
              </div>

              {/* Requirement */}
              <div className="space-y-2">
                <h4 className="text-xs font-semibold text-ink uppercase tracking-wider">
                  硬性匹配要求
                </h4>
                <Select
                  value={matchingPrefs.requirement}
                  onValueChange={(v) =>
                    setMatchingPrefs({
                      ...matchingPrefs,
                      requirement: v as SupervisionMatchRequirement,
                    })
                  }
                >
                  <SelectTrigger className="h-9 text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="none">无硬性要求 (尽量匹配，不满足亦可指派)</SelectItem>
                    <SelectItem value="any">至少满足一项启用的偏好 (不满足则不可指派)</SelectItem>
                    <SelectItem value="all">必须全部满足启用的偏好</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
          )}
        </div>

        <DialogFooter className="pt-3 border-t border-border flex items-center justify-between">
          <span className="text-xs text-ink-secondary">修改将保存在当前草稿中</span>
          <div className="flex items-center gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => onOpenChange(false)}
            >
              取消
            </Button>
            <Button type="button" size="sm" onClick={handleSaveAll}>
              保存设置
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
