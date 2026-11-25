import React, { useEffect, useMemo, useState } from 'react';
import {
  AlertCircle,
  Check,
  Search,
  Sparkles,
  UserCheck,
  UserX,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import type { ScheduleData } from '@/domain/scheduling';
import type { SupervisionDraft, SupervisionPost } from '@/domain/supervision';
import { poolNameForPost, teachersForPost } from '@/domain/supervision';
import { SupervisionAllocator } from '@/domain/supervisionAllocator';
import { SupervisionMatching } from '@/domain/supervisionMatching';
import { withRoutineClock } from '@/domain/supervisionValidation';

interface TeacherPickerDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  snapshot: ScheduleData;
  draft: SupervisionDraft;
  post: SupervisionPost | null;
  onAssign: (postId: string, teacherId: string | null) => void;
}

const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

export const TeacherPickerDialog: React.FC<TeacherPickerDialogProps> = ({
  open,
  onOpenChange,
  snapshot,
  draft,
  post,
  onAssign,
}) => {
  const assignedTeacherId = post ? draft.assignments[post.id] ?? null : null;
  const [search, setSearch] = useState('');
  const [filterMode, setFilterMode] = useState<
    'pool' | 'all' | 'recommended' | 'available'
  >('pool');
  const [pendingTeacherId, setPendingTeacherId] = useState<string | null>(assignedTeacherId);

  const allocator = useMemo(() => new SupervisionAllocator(), []);
  const matching = useMemo(() => new SupervisionMatching(snapshot), [snapshot]);

  const isManual = post ? draft.manualPostIds.includes(post.id) : false;
  const poolTeacherIds = useMemo(
    () => (post ? teachersForPost(draft, post) : new Set<string>()),
    [draft, post]
  );

  useEffect(() => {
    if (!open) return;
    setSearch('');
    setFilterMode('pool');
    setPendingTeacherId(assignedTeacherId);
  }, [assignedTeacherId, open, post?.id]);

  const classes = useMemo(
    () => new Map(snapshot.classes.map((c) => [c.id, c.name])),
    [snapshot.classes]
  );

  const postTimeLabel = useMemo(() => {
    if (!post) return '';
    const routine = snapshot.routines.find((r) => r.stageId === post.stageId);
    const period = routine?.periodTypes.find((p) => p.id === post.periodTypeId);
    const firstLesson = post.lessonIndices[0];
    const lastLesson = post.lessonIndices[post.lessonIndices.length - 1];
    const lessonLabel =
      firstLesson === lastLesson
        ? `第${firstLesson}节`
        : `第${firstLesson}-${lastLesson}节`;

    const clock = withRoutineClock(snapshot, {
      stageId: post.stageId,
      weekday: post.weekday,
      periodTypeId: post.periodTypeId,
      lessonIndex: firstLesson,
    });

    const timeStr =
      clock.startMinute != null && clock.endMinute != null
        ? ` (${Math.floor(clock.startMinute / 60)}:${String(clock.startMinute % 60).padStart(2, '0')}-${Math.floor(clock.endMinute / 60)}:${String(clock.endMinute % 60).padStart(2, '0')})`
        : '';

    return `${WEEKDAYS[post.weekday - 1]} · ${period?.name ?? ''} ${lessonLabel}${timeStr}`;
  }, [post, snapshot]);

  // Evaluate each teacher
  const evaluatedTeachers = useMemo(() => {
    if (!post) return [];

    return snapshot.teachers.map((teacher) => {
      const blockers = allocator.teacherBlockers(
        snapshot,
        draft,
        post,
        teacher.id,
        matching
      );
      const reasons = matching.reasons(post, teacher.id);
      const isAssigned = assignedTeacherId === teacher.id;
      const weeklyLessons = matching.lessons(draft, teacher.id);
      const weeklyDays = matching.days(draft, teacher.id).size;
      const meetsReq = matching.meetsRequirement(draft, post, teacher.id);
      const hasUnmet = matching.hasUnmetPreferences(draft, post, teacher.id);

      return {
        teacher,
        blockers,
        reasons,
        isAssigned,
        weeklyLessons,
        weeklyDays,
        meetsReq,
        hasUnmet,
        isBlocked: blockers.length > 0,
        isInPool: poolTeacherIds.has(teacher.id),
      };
    });
  }, [allocator, assignedTeacherId, draft, matching, poolTeacherIds, post, snapshot]);

  // Filtered teachers
  const filteredTeachers = useMemo(() => {
    if (!post) return [];

    let list = evaluatedTeachers;

    if (search.trim()) {
      const q = search.trim().toLowerCase();
      list = list.filter((item) => item.teacher.name.toLowerCase().includes(q));
    }

    if (filterMode === 'pool') {
      list = list.filter(
        (item) =>
          item.isInPool ||
          item.teacher.id === assignedTeacherId ||
          item.teacher.id === pendingTeacherId
      );
    } else if (filterMode === 'recommended') {
      list = list.filter((item) => !item.isBlocked && item.reasons.length > 0);
    } else if (filterMode === 'available') {
      list = list.filter((item) => !item.isBlocked);
    }

    // Sort: assigned first, then unblocked before blocked, then matching score/load
    return [...list].sort((a, b) => {
      if (a.isAssigned) return -1;
      if (b.isAssigned) return 1;
      if (a.isBlocked !== b.isBlocked) {
        return a.isBlocked ? 1 : -1;
      }
      return matching.compare(draft, post, a.teacher.id, b.teacher.id);
    });
  }, [assignedTeacherId, draft, evaluatedTeachers, filterMode, matching, pendingTeacherId, post, search]);

  if (!post) return null;

  const poolName = poolNameForPost(draft, post);
  const poolTeacherCount = evaluatedTeachers.filter((item) => item.isInPool).length;
  const pendingTeacherName = evaluatedTeachers.find(
    (item) => item.teacher.id === pendingTeacherId
  )?.teacher.name;
  const classNames = post.classIds.map((id) => classes.get(id) ?? id).join('、');

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-xl max-h-[88vh] flex flex-col p-6 overflow-hidden">
        <DialogHeader className="gap-2 pb-3 border-b border-border">
          <DialogTitle className="pr-10 text-lg font-semibold text-ink flex items-center gap-2">
            <UserCheck className="h-5 w-5 text-primary" />
            指派带班教师
          </DialogTitle>
          <div className="flex flex-wrap items-center justify-between gap-2">
            <DialogDescription className="min-w-0 flex-1 text-xs leading-5 text-ink-secondary">
              <span className="font-medium text-ink">{post.groupName || post.name}</span> ·{' '}
              <span>{classNames}</span> · <span>{postTimeLabel}</span>
            </DialogDescription>
            <Badge variant="outline" className="max-w-[45%] shrink-0 truncate text-xs">
              候选池：{poolName}
            </Badge>
          </div>
        </DialogHeader>

        {/* Search & Filter pills */}
        <div className="pt-3 pb-2 space-y-2 border-b border-border">
          <div className="relative">
            <Search className="h-4 w-4 absolute left-3 top-2.5 text-ink-secondary" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="搜索教师姓名..."
              className="pl-9 h-9 text-xs"
            />
          </div>

          <div className="flex flex-wrap items-center justify-between gap-2 text-xs">
            <div className="flex min-w-0 flex-wrap items-center gap-1.5">
              <button
                type="button"
                aria-pressed={filterMode === 'pool'}
                onClick={() => setFilterMode('pool')}
                className={`px-2.5 py-1 rounded-md text-xs transition-colors ${
                  filterMode === 'pool'
                    ? 'bg-primary text-white font-medium'
                    : 'bg-canvas text-ink-secondary hover:text-ink'
                }`}
              >
                候选池 ({poolTeacherCount})
              </button>
              <button
                type="button"
                aria-pressed={filterMode === 'all'}
                onClick={() => setFilterMode('all')}
                className={`px-2.5 py-1 rounded-md text-xs transition-colors ${
                  filterMode === 'all'
                    ? 'bg-primary text-white font-medium'
                    : 'bg-canvas text-ink-secondary hover:text-ink'
                }`}
              >
                全部教师 ({evaluatedTeachers.length})
              </button>
              <button
                type="button"
                aria-pressed={filterMode === 'recommended'}
                onClick={() => setFilterMode('recommended')}
                className={`px-2.5 py-1 rounded-md text-xs transition-colors flex items-center gap-1 ${
                  filterMode === 'recommended'
                    ? 'bg-primary text-white font-medium'
                    : 'bg-canvas text-ink-secondary hover:text-ink'
                }`}
              >
                <Sparkles className="h-3 w-3" />
                推荐符合 ({evaluatedTeachers.filter((t) => !t.isBlocked && t.reasons.length > 0).length})
              </button>
              <button
                type="button"
                aria-pressed={filterMode === 'available'}
                onClick={() => setFilterMode('available')}
                className={`px-2.5 py-1 rounded-md text-xs transition-colors ${
                  filterMode === 'available'
                    ? 'bg-primary text-white font-medium'
                    : 'bg-canvas text-ink-secondary hover:text-ink'
                }`}
              >
                可用无冲突 ({evaluatedTeachers.filter((t) => !t.isBlocked).length})
              </button>
            </div>

            {(assignedTeacherId || pendingTeacherId) && (
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => {
                  setPendingTeacherId(null);
                }}
                className="h-7 text-xs text-destructive hover:text-destructive flex items-center gap-1"
              >
                <UserX className="h-3.5 w-3.5" />
                清除选择
              </Button>
            )}
          </div>
        </div>

        {/* Teacher list */}
        <div className="flex-1 overflow-y-auto py-2 space-y-2">
          {filteredTeachers.length === 0 ? (
            <div className="py-12 text-center text-xs text-ink-secondary">
              {filterMode === 'pool' && poolTeacherCount === 0
                ? '当前岗位关联的候选池暂无教师，可切换到全部教师查看'
                : '没有找到匹配的教师'}
            </div>
          ) : (
            filteredTeachers.map((item) => {
              const { teacher, blockers, reasons, isAssigned, weeklyLessons, weeklyDays, isBlocked } =
                item;
              const isSelected = pendingTeacherId === teacher.id;

              return (
                <button
                  type="button"
                  key={teacher.id}
                  aria-pressed={isSelected}
                  disabled={isBlocked && !isSelected}
                  onClick={() => {
                    if (!isBlocked || isSelected) setPendingTeacherId(teacher.id);
                  }}
                  className={`w-full p-3 rounded-lg border transition-colors text-left text-xs flex items-center justify-between ${
                    isSelected
                      ? 'bg-selection/80 border-primary text-ink shadow-sm'
                      : isBlocked
                      ? 'bg-canvas/40 border-border/60 opacity-60 cursor-not-allowed'
                      : 'border-border hover:border-primary/40 hover:bg-canvas/70 cursor-pointer'
                  }`}
                >
                  <div className="space-y-1.5 flex-1 min-w-0 pr-3">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-sm text-ink">{teacher.name}</span>
                      {isSelected && (
                        <Badge variant="default" className="text-[10px] h-4 px-1.5">
                          {isAssigned ? `当前指派 ${isManual ? '(手动)' : ''}` : '待确认'}
                        </Badge>
                      )}
                      <span className="text-[11px] text-ink-secondary">
                        周带班: <span className="font-medium text-ink">{weeklyLessons}</span> 节 /{' '}
                        <span className="font-medium text-ink">{weeklyDays}</span> 天
                      </span>
                    </div>

                    {/* Match reasons */}
                    {reasons.length > 0 && (
                      <div className="flex flex-wrap gap-1">
                        {reasons.map((r, idx) => (
                          <span
                            key={idx}
                            className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300 font-medium"
                          >
                            {r}
                          </span>
                        ))}
                      </div>
                    )}

                    {/* Blockers */}
                    {blockers.length > 0 && (
                      <div className="flex flex-wrap gap-1 text-[11px] text-destructive">
                        {blockers.map((b, idx) => (
                          <span
                            key={idx}
                            className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] bg-destructive/10 text-destructive font-medium"
                          >
                            <AlertCircle className="h-3 w-3" />
                            {b}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>

                  {isBlocked && !isSelected ? (
                    <span className="ml-2 shrink-0 text-[11px] font-medium text-destructive">
                      冲突
                    </span>
                  ) : (
                    <span
                      aria-hidden="true"
                      className={`ml-2 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border ${
                        isSelected
                          ? 'border-primary bg-primary text-primary-foreground'
                          : 'border-control-border bg-surface text-transparent'
                      }`}
                    >
                      <Check className="h-4 w-4" />
                    </span>
                  )}
                </button>
              );
            })
          )}
        </div>

        <DialogFooter className="pt-3 border-t border-border flex items-center justify-between">
          <div className="text-xs text-ink-secondary">
            {pendingTeacherId
              ? `确定后指派：${pendingTeacherName ?? '所选教师'}`
              : assignedTeacherId
                ? '确定后清除当前指派'
                : `共 ${filteredTeachers.length} 位教师`}
          </div>
          <Button
            type="button"
            variant="default"
            size="sm"
            onClick={() => {
              if (pendingTeacherId !== assignedTeacherId) {
                onAssign(post.id, pendingTeacherId);
              }
              onOpenChange(false);
            }}
          >
            确定
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
