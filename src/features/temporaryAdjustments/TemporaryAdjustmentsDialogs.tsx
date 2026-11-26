import React, { useEffect, useMemo, useState } from 'react';
import { Check, ChevronDown, ChevronUp, Search } from 'lucide-react';
import { sameCell, type SchedulePosition } from '@/domain/supervision';
import {
  type ActualChangePreview,
  type ActualLesson,
  type ActualSupervision,
  getTeacherDisplayName,
  type TemporaryAdjustmentRecord,
  type TemporarySupervisionSubstituteRequest,
  type TemporaryTimetableState,
} from '@/domain/actualTimetable';
import {
  type AdjustmentKind,
  adjustmentKindLabel,
  describeLessonChange,
  describeRecordSummary,
  formatChineseMdWeekday,
  formatShortMd,
  formatTimestampTime,
  getClassDisplayName,
  getPeriodLessonLabel,
  getSubjectDisplayName,
  getTermEndDate,
  weekdayShortLabel,
} from '@/features/temporaryAdjustments/temporaryAdjustmentsHelpers';
import { temporaryAdjustmentsWorkerClient } from '@/features/temporaryAdjustments/temporaryAdjustmentsWorkerClient';
import { getTeachingWeekOfDate } from '@/features/terms/calendarUtils';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { DatePicker } from '@/components/ui/date-picker';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { SearchableSelect } from '@/components/ui/searchable-select';

// ==================== 1. 选择代课教师弹窗 ====================

interface SubstituteTeacherDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  state: TemporaryTimetableState;
  source: ActualLesson;
  selectedTeacherId: string | null;
  subjectId: string | null;
  weekIndex: number;
  onSelectTeacher: (teacherId: string) => void;
}

export const SubstituteTeacherDialog: React.FC<SubstituteTeacherDialogProps> = ({
  open,
  onOpenChange,
  state,
  source,
  selectedTeacherId,
  subjectId,
  weekIndex,
  onSelectTeacher,
}) => {
  const [query, setQuery] = useState('');
  const [sameSubjectOnly, setSameSubjectOnly] = useState(false);
  const [sameGradeOnly, setSameGradeOnly] = useState(false);
  const [sameClassFirst, setSameClassFirst] = useState(true);
  const [expandedTeacherIds, setExpandedTeacherIds] = useState<Set<string>>(
    new Set()
  );
  const [previewsByTeacherId, setPreviewsByTeacherId] = useState<
    Record<string, ActualChangePreview>
  >({});
  const [computing, setComputing] = useState(false);

  useEffect(() => {
    if (open) {
      setQuery('');
      setExpandedTeacherIds(new Set());
    }
  }, [open]);

  const targetSubjectId = subjectId ?? source.item.subjectId;
  const sourceGradeId = state.gradeIdForClass(source.item.classId);

  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    setComputing(true);
    temporaryAdjustmentsWorkerClient
      .computeSubstituteCandidates({
        state,
        sourceKey: source.key,
        targetSubjectId,
      })
      .then((res) => {
        if (!cancelled) setPreviewsByTeacherId(res);
      })
      .catch(() => {
        if (!cancelled) setPreviewsByTeacherId({});
      })
      .finally(() => {
        if (!cancelled) setComputing(false);
      });
    return () => {
      cancelled = true;
    };
  }, [open, state, source.key, targetSubjectId]);

  const candidates = useMemo(() => {
    const q = query.trim().toLowerCase();
    const weekNumber = weekIndex + 1;
    const weekLessonsByTeacher = new Map<string, ActualLesson[]>();
    for (const lesson of state.lessons) {
      const w = getTeachingWeekOfDate(state.snapshot.term, lesson.date);
      if (w !== weekNumber) continue;
      const list = weekLessonsByTeacher.get(lesson.item.teacherId) ?? [];
      list.push(lesson);
      weekLessonsByTeacher.set(lesson.item.teacherId, list);
    }

    const items = state.snapshot.teachers
      .filter((t) => t.id !== source.item.teacherId)
      .map((teacher) => {
        const displayName = getTeacherDisplayName(teacher);
        const teacherSubjectIds = new Set<string>([
          ...(teacher.subjectIds ?? []),
          ...state.snapshot.assignments
            .filter((a) => a.teacherId === teacher.id)
            .map((a) => a.subjectId),
        ]);
        const teachesSubject = teacherSubjectIds.has(targetSubjectId);
        const teachesClass = state.snapshot.assignments.some(
          (a) =>
            a.teacherId === teacher.id && a.classId === source.item.classId
        );
        const teachesGrade = state.snapshot.assignments.some(
          (a) =>
            a.teacherId === teacher.id &&
            state.gradeIdForClass(a.classId) === sourceGradeId
        );
        const preview = previewsByTeacherId[teacher.id];
        const available = preview != null && preview.errors.length === 0;
        const errors = preview?.errors ?? (computing ? ['正在检查冲突…'] : []);
        const weekLessons = (weekLessonsByTeacher.get(teacher.id) ?? []).sort(
          (a, b) =>
            a.date.localeCompare(b.date) ||
            (a.item.position?.lessonIndex ?? 0) -
              (b.item.position?.lessonIndex ?? 0)
        );
        const subjectNames = Array.from(teacherSubjectIds)
          .map((sid) => getSubjectDisplayName(sid, state.snapshot.subjects))
          .filter(Boolean);

        return {
          teacher,
          displayName,
          teachesSubject,
          teachesClass,
          teachesGrade,
          available,
          errors,
          weekLessons,
          subjectNames,
        };
      })
      .filter((item) => {
        if (sameSubjectOnly && !item.teachesSubject) return false;
        if (sameGradeOnly && !item.teachesGrade) return false;
        if (q) {
          const hay = `${item.displayName} ${item.teacher.shortName} ${item.subjectNames.join(
            ' '
          )}`.toLowerCase();
          if (!hay.includes(q)) return false;
        }
        return true;
      });

    items.sort((a, b) => {
      if (a.available !== b.available) return a.available ? -1 : 1;
      if (sameClassFirst && a.teachesClass !== b.teachesClass) {
        return a.teachesClass ? -1 : 1;
      }
      if (a.teachesSubject !== b.teachesSubject) {
        return a.teachesSubject ? -1 : 1;
      }
      if (a.teachesGrade !== b.teachesGrade) {
        return a.teachesGrade ? -1 : 1;
      }
      if (a.weekLessons.length !== b.weekLessons.length) {
        return a.weekLessons.length - b.weekLessons.length;
      }
      return a.teacher.sortOrder - b.teacher.sortOrder;
    });

    return items;
  }, [
    state,
    source,
    targetSubjectId,
    sourceGradeId,
    weekIndex,
    query,
    sameSubjectOnly,
    sameGradeOnly,
    sameClassFirst,
    previewsByTeacherId,
    computing,
  ]);

  const toggleExpand = (teacherId: string) => {
    setExpandedTeacherIds((prev) => {
      const next = new Set(prev);
      if (next.has(teacherId)) next.delete(teacherId);
      else next.add(teacherId);
      return next;
    });
  };

  const classLabel = getClassDisplayName(
    source.item.classId,
    state.snapshot.classes,
    state.snapshot.grades
  );
  const subjectLabel = getSubjectDisplayName(
    targetSubjectId,
    state.snapshot.subjects
  );
  const slotLabel = getPeriodLessonLabel(state, source.item.position);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[580px] max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>选择代课教师</DialogTitle>
          <DialogDescription>
            为 {formatChineseMdWeekday(source.date)} {slotLabel} · {classLabel}{' '}
            {subjectLabel} 选择代课教师
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-1">
          <div className="relative">
            <Search className="w-4 h-4 text-ink-secondary absolute left-3 top-1/2 -translate-y-1/2" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="搜索教师姓名、简称或任教学科…"
              className="pl-9 h-9"
            />
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => setSameSubjectOnly((v) => !v)}
              className={`px-2.5 py-1 rounded-full text-xs font-medium border transition-colors ${
                sameSubjectOnly
                  ? 'bg-selection text-primary border-primary/40'
                  : 'bg-surface text-ink-secondary border-border hover:text-ink'
              }`}
            >
              同科目
            </button>
            <button
              type="button"
              onClick={() => setSameGradeOnly((v) => !v)}
              className={`px-2.5 py-1 rounded-full text-xs font-medium border transition-colors ${
                sameGradeOnly
                  ? 'bg-selection text-primary border-primary/40'
                  : 'bg-surface text-ink-secondary border-border hover:text-ink'
              }`}
            >
              同年级
            </button>
            <button
              type="button"
              onClick={() => setSameClassFirst((v) => !v)}
              className={`px-2.5 py-1 rounded-full text-xs font-medium border transition-colors ${
                sameClassFirst
                  ? 'bg-selection text-primary border-primary/40'
                  : 'bg-surface text-ink-secondary border-border hover:text-ink'
              }`}
            >
              本班优先
            </button>
            <span className="ml-auto text-xs text-ink-secondary">
              {computing
                ? '正在后台计算可用教师…'
                : `共 ${candidates.length} 位候选教师`}
            </span>
          </div>
        </div>

        <div className="flex-1 min-h-0 overflow-y-auto divide-y divide-border rounded-lg border border-border bg-surface">
          {candidates.length === 0 ? (
            <div className="py-10 text-center text-sm text-ink-secondary">
              没有符合筛选条件的教师
            </div>
          ) : (
            candidates.map((item) => {
              const isSelected = selectedTeacherId === item.teacher.id;
              const isExpanded = expandedTeacherIds.has(item.teacher.id);
              return (
                <div
                  key={item.teacher.id}
                  className={`p-3 transition-colors ${
                    isSelected ? 'bg-selection/50' : 'hover:bg-table-header/40'
                  }`}
                >
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0 space-y-1">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <span className="text-sm font-semibold text-ink">
                          {item.displayName}
                        </span>
                        {item.teachesClass && (
                          <span className="px-1.5 py-0.5 rounded bg-selection text-primary text-[11px] font-medium">
                            本班任课
                          </span>
                        )}
                        {item.teachesSubject && (
                          <span className="px-1.5 py-0.5 rounded bg-table-header text-ink-secondary text-[11px]">
                            同科
                          </span>
                        )}
                        <span className="text-xs text-ink-secondary">
                          · 本周 {item.weekLessons.length} 节
                        </span>
                      </div>
                      <div className="text-xs text-ink-secondary">
                        {item.subjectNames.length > 0
                          ? `任教：${item.subjectNames.join('、')}`
                          : '暂无任教标签'}
                      </div>
                      <div>
                        {computing ? (
                          <span className="inline-flex items-center px-2 py-0.5 rounded-full bg-table-header text-ink-secondary text-[11px]">
                            正在校验…
                          </span>
                        ) : item.available ? (
                          <span className="inline-flex items-center px-2 py-0.5 rounded-full bg-success-surface text-success text-[11px] font-medium">
                            本节空闲 · 可代课
                          </span>
                        ) : (
                          <span className="inline-flex items-center px-2 py-0.5 rounded-full bg-warning-surface text-warning text-[11px] font-medium">
                            不可选：{item.errors.join('；')}
                          </span>
                        )}
                      </div>
                    </div>

                    <div className="flex items-center gap-2 shrink-0">
                      <button
                        type="button"
                        onClick={() => toggleExpand(item.teacher.id)}
                        className="px-2 py-1 rounded text-xs text-ink-secondary hover:text-ink hover:bg-table-header inline-flex items-center gap-1"
                      >
                        <span>查看课表</span>
                        {isExpanded ? (
                          <ChevronUp className="w-3.5 h-3.5" />
                        ) : (
                          <ChevronDown className="w-3.5 h-3.5" />
                        )}
                      </button>
                      <Button
                        type="button"
                        size="sm"
                        variant={isSelected ? 'default' : 'outline'}
                        disabled={computing || !item.available}
                        onClick={() => {
                          onSelectTeacher(item.teacher.id);
                          onOpenChange(false);
                        }}
                      >
                        {isSelected ? (
                          <>
                            <Check className="w-3.5 h-3.5 mr-1" />
                            已选
                          </>
                        ) : (
                          '选择'
                        )}
                      </Button>
                    </div>
                  </div>

                  {isExpanded && (
                    <div className="mt-2.5 pt-2.5 border-t border-border/70 text-xs space-y-1">
                      {item.weekLessons.length === 0 ? (
                        <div className="text-ink-secondary">本周暂无排课</div>
                      ) : (
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                          {item.weekLessons.map((l) => (
                            <div
                              key={l.key}
                              className="px-2 py-1 rounded bg-table-header/60 text-ink flex items-center justify-between gap-2"
                            >
                              <span>
                                {formatShortMd(l.date)}（
                                {weekdayShortLabel(
                                  l.item.position?.weekday ?? 1
                                )}
                                ）{getPeriodLessonLabel(state, l.item.position)}
                              </span>
                              <span className="text-ink-secondary truncate">
                                {getClassDisplayName(
                                  l.item.classId,
                                  state.snapshot.classes,
                                  state.snapshot.grades
                                )}
                                ·
                                {getSubjectDisplayName(
                                  l.item.subjectId,
                                  state.snapshot.subjects
                                )}
                              </span>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })
          )}
        </div>

        <DialogFooter>
          <Button
            type="button"
            variant="outline"
            onClick={() => onOpenChange(false)}
          >
            关闭
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

// ==================== 2. 预览调整弹窗 ====================

interface PreviewAdjustmentDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  state: TemporaryTimetableState;
  source: ActualLesson;
  kind: AdjustmentKind;
  swapKey: string | null;
  moveDate: string | null;
  movePosition: SchedulePosition | null;
  substituteTeacherId: string | null;
  substituteSubjectId: string | null;
  reason: string;
  onConfirm: (params: {
    rangeMode: boolean;
    rangeStart: string | null;
    rangeEnd: string | null;
    excludedDates: Set<string>;
  }) => Promise<void>;
}

export const PreviewAdjustmentDialog: React.FC<PreviewAdjustmentDialogProps> = ({
  open,
  onOpenChange,
  state,
  source,
  kind,
  swapKey,
  moveDate,
  movePosition,
  substituteTeacherId,
  substituteSubjectId,
  reason,
  onConfirm,
}) => {
  const termStart =
    state.snapshot.term.firstTeachingWeekStart?.slice(0, 10) ?? source.date;
  const termEnd = getTermEndDate(state.snapshot.term);

  const [rangeMode, setRangeMode] = useState(false);
  const [rangeStart, setRangeStart] = useState(source.date);
  const [rangeEnd, setRangeEnd] = useState(termEnd);
  const [excludedDates, setExcludedDates] = useState<Set<string>>(new Set());
  const [preview, setPreview] = useState<ActualChangePreview>({
    changes: [],
    errors: [],
    skippedDates: [],
  });
  const [computing, setComputing] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setRangeMode(false);
      setRangeStart(source.date);
      setRangeEnd(termEnd);
      setExcludedDates(new Set());
      setSubmitError(null);
    }
  }, [open, source.date, termEnd]);

  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    setComputing(true);
    temporaryAdjustmentsWorkerClient
      .computeAdjustmentPreview({
        state,
        kind,
        sourceKey: source.key,
        swapKey,
        moveDate,
        movePosition,
        substituteTeacherId,
        substituteSubjectId: substituteSubjectId ?? source.item.subjectId,
        reason,
        rangeStart: rangeMode ? rangeStart : null,
        rangeEnd: rangeMode ? rangeEnd : null,
        excludedDates,
      })
      .then((res) => {
        if (!cancelled) setPreview(res);
      })
      .catch((err) => {
        if (!cancelled) {
          setPreview({
            changes: [],
            errors: [err instanceof Error ? err.message : String(err)],
            skippedDates: [],
          });
        }
      })
      .finally(() => {
        if (!cancelled) setComputing(false);
      });
    return () => {
      cancelled = true;
    };
  }, [
    open,
    state,
    source.key,
    source.item.subjectId,
    kind,
    swapKey,
    moveDate,
    movePosition,
    substituteTeacherId,
    substituteSubjectId,
    reason,
    rangeMode,
    rangeStart,
    rangeEnd,
    excludedDates,
  ]);

  const effectiveGroupsCount =
    kind === 'swap'
      ? Math.max(1, Math.floor(preview.changes.length / 2))
      : preview.changes.length;

  const canConfirm =
    !computing && preview.errors.length === 0 && preview.changes.length > 0;

  const extractDatePrefix = (err: string): string | null => {
    const m = /^(\d{4}-\d{2}-\d{2})：/.exec(err);
    return m ? m[1] : null;
  };

  const handleExcludeDate = (ymd: string) => {
    setExcludedDates((prev) => {
      const next = new Set(prev);
      next.add(ymd);
      return next;
    });
  };

  const handleConfirm = async () => {
    if (!canConfirm) return;
    setSubmitting(true);
    setSubmitError(null);
    try {
      await onConfirm({
        rangeMode,
        rangeStart: rangeMode ? rangeStart : null,
        rangeEnd: rangeMode ? rangeEnd : null,
        excludedDates,
      });
      onOpenChange(false);
    } catch (e) {
      setSubmitError(e instanceof Error ? e.message : String(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[560px] max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>预览{adjustmentKindLabel(kind)}</DialogTitle>
          <DialogDescription>
            核对生效范围与课次变更明细，确认无误后生效。
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-1 flex-1 min-h-0 overflow-y-auto">
          {/* Scope Selector */}
          <div className="p-3 rounded-lg border border-border bg-table-header/40 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-ink-secondary">
                生效范围
              </span>
              <div className="inline-flex rounded-lg border border-border bg-surface p-0.5">
                <button
                  type="button"
                  onClick={() => {
                    setRangeMode(false);
                    setExcludedDates(new Set());
                  }}
                  className={`px-3 py-1 rounded-md text-xs font-medium transition-colors ${
                    !rangeMode
                      ? 'bg-selection text-primary font-semibold'
                      : 'text-ink-secondary hover:text-ink'
                  }`}
                >
                  仅本次
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setRangeMode(true);
                    setExcludedDates(new Set());
                  }}
                  className={`px-3 py-1 rounded-md text-xs font-medium transition-colors ${
                    rangeMode
                      ? 'bg-selection text-primary font-semibold'
                      : 'text-ink-secondary hover:text-ink'
                  }`}
                >
                  日期范围
                </button>
              </div>
            </div>

            {rangeMode && (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
                <div className="space-y-1">
                  <Label className="text-xs text-ink-secondary">开始日期</Label>
                  <DatePicker
                    value={rangeStart}
                    min={termStart}
                    max={rangeEnd || termEnd}
                    onChange={(val) => {
                      if (val) {
                        setRangeStart(val);
                        setExcludedDates(new Set());
                      }
                    }}
                  />
                </div>
                <div className="space-y-1">
                  <Label className="text-xs text-ink-secondary">结束日期</Label>
                  <DatePicker
                    value={rangeEnd}
                    min={rangeStart || termStart}
                    max={termEnd}
                    onChange={(val) => {
                      if (val) {
                        setRangeEnd(val);
                        setExcludedDates(new Set());
                      }
                    }}
                  />
                </div>
              </div>
            )}
          </div>

          {/* Valid Changes */}
          <div className="space-y-2">
            <div className="text-xs font-semibold text-ink-secondary">
              {computing
                ? '正在后台计算变更预览…'
                : `将生效的变更（${preview.changes.length} 条课次明细）`}
            </div>
            {computing ? (
              <div className="p-4 rounded-lg border border-border bg-surface text-xs text-ink-secondary text-center">
                正在校验课表与约束条件…
              </div>
            ) : preview.changes.length === 0 ? (
              <div className="p-3 rounded-lg border border-border bg-surface text-xs text-ink-secondary">
                当前无可生效的课次变更
              </div>
            ) : (
              <div className="space-y-1.5 max-h-[210px] overflow-y-auto pr-1">
                {preview.changes.map((change, idx) => (
                  <div
                    key={`${change.before.key}_${idx}`}
                    className="p-2.5 rounded-lg border border-border bg-surface text-xs text-ink flex items-start justify-between gap-2"
                  >
                    <div>
                      <span className="font-semibold">
                        {getClassDisplayName(
                          change.before.item.classId,
                          state.snapshot.classes,
                          state.snapshot.grades
                        )}
                      </span>
                      <span className="mx-1.5 text-ink-secondary">·</span>
                      <span>{describeLessonChange(state, change, kind)}</span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Errors */}
          {!computing && preview.errors.length > 0 && (
            <div className="space-y-2">
              <div className="text-xs font-semibold text-destructive">
                冲突提示（{preview.errors.length}）
              </div>
              <div className="space-y-1.5">
                {preview.errors.map((err, idx) => {
                  const errDate = rangeMode ? extractDatePrefix(err) : null;
                  return (
                    <div
                      key={`${err}_${idx}`}
                      className="p-2.5 rounded-lg border border-destructive/30 bg-destructive-surface text-xs text-destructive flex items-center justify-between gap-2"
                    >
                      <span>{err}</span>
                      {errDate && (
                        <button
                          type="button"
                          onClick={() => handleExcludeDate(errDate)}
                          className="shrink-0 px-2 py-0.5 rounded bg-surface border border-destructive/30 text-[11px] font-medium hover:bg-destructive/10"
                        >
                          移除此日期
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Skipped Dates */}
          {!computing && preview.skippedDates.length > 0 && (
            <div className="p-2.5 rounded-lg border border-border bg-table-header/50 text-xs text-ink-secondary">
              已跳过无对应原课次的日期：
              {preview.skippedDates.map(formatShortMd).join('、')}
            </div>
          )}

          {reason.trim() && (
            <div className="text-xs text-ink-secondary">
              调整原因：<span className="text-ink">{reason.trim()}</span>
            </div>
          )}

          {submitError && (
            <div className="p-2.5 rounded-lg bg-destructive-surface text-xs text-destructive">
              {submitError}
            </div>
          )}
        </div>

        <DialogFooter>
          <Button
            type="button"
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={submitting}
          >
            返回修改
          </Button>
          <Button
            type="button"
            disabled={!canConfirm || submitting}
            onClick={handleConfirm}
          >
            确认调整{canConfirm ? `（${effectiveGroupsCount}次）` : ''}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

// ==================== 3. 安排带班替班弹窗 ====================

interface SupervisionSubstituteDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  state: TemporaryTimetableState;
  supervision: ActualSupervision;
  initialPosition: SchedulePosition;
  onConfirm: (request: TemporarySupervisionSubstituteRequest) => Promise<void>;
}

export const SupervisionSubstituteDialog: React.FC<
  SupervisionSubstituteDialogProps
> = ({ open, onOpenChange, state, supervision, initialPosition, onConfirm }) => {
  const [positions, setPositions] = useState([initialPosition]);
  const [teacherId, setTeacherId] = useState<string>('');
  const [reason, setReason] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const candidates = useMemo(() => {
    if (positions.length === 0) return [];
    return state.snapshot.teachers
      .filter(
        (t) =>
          t.id !== supervision.teacherId &&
          (supervision.eligibleTeacherIds.size === 0 ||
            supervision.eligibleTeacherIds.has(t.id))
      )
      .map((t) => {
        const preview = state.previewSupervisionSubstitute({
          date: supervision.date,
          postId: supervision.postId,
          teacherId: t.id,
          positions,
        });
        return {
          teacher: t,
          displayName: getTeacherDisplayName(t),
          available: preview.errors.length === 0,
          errors: preview.errors,
        };
      });
  }, [state, supervision, positions]);

  const selectedCandidate = candidates.find((c) => c.teacher.id === teacherId);
  const canConfirm = Boolean(selectedCandidate?.available);

  const handleConfirm = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canConfirm || submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await onConfirm({
        date: supervision.date,
        postId: supervision.postId,
        teacherId,
        positions,
        reason,
      });
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(next) => !submitting && onOpenChange(next)}>
      <DialogContent className="sm:max-w-[460px]">
        <DialogHeader>
          <DialogTitle>安排带班替班</DialogTitle>
          <DialogDescription>
            {formatChineseMdWeekday(supervision.date)} · {supervision.post.name}
            （原带班：{supervision.teacherName}）
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleConfirm} className="space-y-4 py-1">
          <div className="p-3 rounded-lg bg-table-header/50 border border-border text-xs space-y-1">
            <div>
              <span className="text-ink-secondary">覆盖班级：</span>
              <span className="text-ink font-medium">
                {supervision.classNames.join('、') || '无'}
              </span>
            </div>
          </div>

          <fieldset className="space-y-1.5" disabled={submitting}>
            <legend className="text-sm font-medium">替班节次</legend>
            <div className="flex flex-wrap gap-x-4">
              {supervision.occurrences.map(({ position }) => (
                <Label
                  key={`${position.stageId}:${position.weekday}:${position.periodTypeId}:${position.lessonIndex}`}
                  className="flex min-h-9 items-center gap-2"
                >
                  <Checkbox
                    type="button"
                    checked={positions.some((selected) => sameCell(selected, position))}
                    onCheckedChange={(checked) => {
                      setError(null);
                      setPositions((current) => checked === true
                        ? [...current, position]
                        : current.filter((selected) => !sameCell(selected, position))
                      );
                    }}
                  />
                  {getPeriodLessonLabel(state, position)}
                </Label>
              ))}
            </div>
          </fieldset>

          <div className="space-y-1.5">
            <div className="text-sm font-medium">替班教师</div>
            <SearchableSelect
              ariaLabel="替班教师"
              value={teacherId}
              onValueChange={(id) => {
                setTeacherId(id);
                setError(null);
              }}
              options={candidates.map((candidate) => ({
                value: candidate.teacher.id,
                label: candidate.available
                  ? candidate.displayName
                  : `${candidate.displayName}（不可替班）`,
                keywords: candidate.teacher.name,
              }))}
              placeholder={positions.length === 0
                ? '请先选择替班节次'
                : candidates.length === 0 ? '暂无候选替班教师' : '请选择教师'}
              searchPlaceholder="搜索教师姓名…"
              disabled={submitting || candidates.length === 0}
              className="w-full"
            />
            {selectedCandidate && !selectedCandidate.available && (
              <p className="text-xs text-destructive">
                {selectedCandidate.errors.join('；')}
              </p>
            )}
          </div>

          <div className="space-y-1.5">
            <Label>替班原因（选填）</Label>
            <Input
              disabled={submitting}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="例如：公务外出、临时调休…"
            />
          </div>

          {error && <p className="text-xs text-destructive">{error}</p>}

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={submitting}
            >
              取消
            </Button>
            <Button type="submit" disabled={!canConfirm || submitting}>
              确认替班
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};

// ==================== 4. 调整记录详情与取消调整弹窗 ====================

interface RecordDetailDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  state: TemporaryTimetableState;
  record: TemporaryAdjustmentRecord | null;
  onRequestCancelRecord?: (record: TemporaryAdjustmentRecord) => void;
}

export const RecordDetailDialog: React.FC<RecordDetailDialogProps> = ({
  open,
  onOpenChange,
  state,
  record,
  onRequestCancelRecord,
}) => {
  if (!record) return null;

  const canCancel =
    record.cancelledAt == null &&
    (!state.reconciliationPending || record.needsAttention);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[520px]">
        <DialogHeader>
          <DialogTitle>
            {adjustmentKindLabel(record.kind)}详情
          </DialogTitle>
          <DialogDescription>
            创建于 {formatTimestampTime(record.createdAt)}
            {record.cancelledAt != null
              ? ` · 已于 ${formatTimestampTime(record.cancelledAt)} 取消`
              : ''}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-1 text-xs">
          <div className="flex items-center gap-2">
            <span className="text-ink-secondary">当前状态：</span>
            {record.cancelledAt != null ? (
              <span className="px-2 py-0.5 rounded-full bg-table-header text-ink-secondary font-medium">
                已取消
              </span>
            ) : record.needsAttention ? (
              <span className="px-2 py-0.5 rounded-full bg-warning-surface text-warning font-medium">
                需处理（与最新课表或前置调整存在冲突）
              </span>
            ) : (
              <span className="px-2 py-0.5 rounded-full bg-success-surface text-success font-medium">
                有效
              </span>
            )}
          </div>

          {record.reason.trim() && (
            <div>
              <span className="text-ink-secondary">调整原因：</span>
              <span className="text-ink font-medium">{record.reason}</span>
            </div>
          )}

          <div className="space-y-1.5">
            <div className="font-semibold text-ink-secondary">变更明细</div>
            <div className="max-h-[240px] overflow-y-auto space-y-1.5 rounded-lg border border-border bg-table-header/40 p-2.5">
              {record.supervisionChange ? (
                <div className="text-ink">
                  {describeRecordSummary(state, record)}
                </div>
              ) : (
                record.changes.map((c, idx) => (
                  <div
                    key={`${c.before.key}_${idx}`}
                    className="p-2 rounded bg-surface border border-border text-ink"
                  >
                    <div className="font-semibold mb-0.5">
                      {getClassDisplayName(
                        c.before.item.classId,
                        state.snapshot.classes,
                        state.snapshot.grades
                      )}
                    </div>
                    <div className="text-ink-secondary">
                      {describeLessonChange(state, c, record.kind)}
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>

        <DialogFooter>
          {canCancel && onRequestCancelRecord && (
            <Button
              type="button"
              variant="destructive"
              onClick={() => {
                onOpenChange(false);
                onRequestCancelRecord(record);
              }}
            >
              取消此调整
            </Button>
          )}
          <Button
            type="button"
            variant="outline"
            onClick={() => onOpenChange(false)}
          >
            关闭
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

interface CancelRecordDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  state: TemporaryTimetableState;
  record: TemporaryAdjustmentRecord | null;
  onConfirmCancel: (record: TemporaryAdjustmentRecord) => Promise<void>;
}

export const CancelRecordDialog: React.FC<CancelRecordDialogProps> = ({
  open,
  onOpenChange,
  state,
  record,
  onConfirmCancel,
}) => {
  const [checking, setChecking] = useState(false);
  const [blocker, setBlocker] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !record) {
      setBlocker(null);
      setChecking(false);
      setSubmitError(null);
      return;
    }
    let cancelled = false;
    setChecking(true);
    setSubmitError(null);
    temporaryAdjustmentsWorkerClient
      .validateCancellation({
        state,
        recordId: record.id,
      })
      .then((res) => {
        if (!cancelled) setBlocker(res);
      })
      .catch((err) => {
        if (!cancelled) {
          setBlocker(err instanceof Error ? err.message : String(err));
        }
      })
      .finally(() => {
        if (!cancelled) setChecking(false);
      });
    return () => {
      cancelled = true;
    };
  }, [open, state, record]);

  if (!record) return null;

  const handleConfirm = async () => {
    if (checking || blocker) return;
    setSubmitting(true);
    setSubmitError(null);
    try {
      await onConfirmCancel(record);
      onOpenChange(false);
    } catch (e) {
      setSubmitError(e instanceof Error ? e.message : String(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[460px]">
        <DialogHeader>
          <DialogTitle>
            取消{adjustmentKindLabel(record.kind)}？
          </DialogTitle>
          <DialogDescription>
            取消后将恢复原课次或原带班安排，该记录将保留在“已取消”列表中。
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 py-1 text-xs">
          <div className="p-3 rounded-lg border border-border bg-table-header/40 text-ink">
            {describeRecordSummary(state, record)}
          </div>

          {checking && (
            <div className="text-ink-secondary">
              正在检查恢复原课次是否存在冲突…
            </div>
          )}

          {!checking && blocker && (
            <div className="p-3 rounded-lg border border-destructive/30 bg-destructive-surface text-destructive">
              无法直接取消：{blocker}
            </div>
          )}

          {submitError && (
            <div className="p-3 rounded-lg border border-destructive/30 bg-destructive-surface text-destructive">
              {submitError}
            </div>
          )}
        </div>

        <DialogFooter>
          <Button
            type="button"
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={submitting}
          >
            返回
          </Button>
          <Button
            type="button"
            variant="destructive"
            disabled={checking || Boolean(blocker) || submitting}
            onClick={handleConfirm}
          >
            确认取消调整
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
