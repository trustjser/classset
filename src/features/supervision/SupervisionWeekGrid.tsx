import { hasTouchInput, useSelectionPress } from '@/lib/pointerSelection';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { MoreHorizontal, Settings2, Trash2, UserPlus } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import type { ScheduleData } from '@/domain/scheduling';
import type {
  SupervisionDraft,
  SupervisionPost,
} from '@/domain/supervision';
import type { SupervisionAllocator } from '@/domain/supervisionAllocator';
import type { SupervisionMatching } from '@/domain/supervisionMatching';

interface SupervisionWeekGridProps {
  snapshot: ScheduleData;
  draft: SupervisionDraft;
  posts: SupervisionPost[];
  classMap: ReadonlyMap<string, string>;
  teacherMap: ReadonlyMap<string, string>;
  matching: SupervisionMatching | null;
  allocator: SupervisionAllocator;
  isHistorical: boolean;
  selectedPostIds: Set<string>;
  onTogglePostSelection: (postId: string) => void;
  onSetPostSelection: (postIds: Set<string>) => void;
  onEditRules: (post: SupervisionPost) => void;
  onDeletePost: (postId: string) => void;
  onSelectTeacher: (post: SupervisionPost) => void;
};

interface WeekRow {
  key: string;
  stageId: string;
  stageName: string;
  periodName: string;
  periodTypeId: string;
  lessonIndices: number[];
  stageOrder: number;
  sortOrder: number;
  timeLabel: string;
}

interface Point {
  x: number;
  y: number;
}

interface MarqueeDrag {
  pointerId: number;
  startClient: Point;
  anchorContent: Point;
  currentLocal: Point;
  baseSelection: Set<string>;
  lastSelection: Set<string>;
  initialSelection: Set<string>;
  started: boolean;
}

interface MarqueeRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

const WEEKDAY_LABELS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

const formatMinute = (minute: number): string =>
  `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;

const sortedLessonIndices = (indices: number[]): number[] =>
  Array.from(new Set(indices)).sort((a, b) => a - b);

const areSetsEqual = (first: Set<string>, second: Set<string>): boolean =>
  first.size === second.size && [...first].every((value) => second.has(value));

const localPoint = (viewport: HTMLDivElement, clientX: number, clientY: number): Point => {
  const bounds = viewport.getBoundingClientRect();
  return {
    x: Math.max(0, Math.min(viewport.clientWidth, clientX - bounds.left - viewport.clientLeft)),
    y: Math.max(0, Math.min(viewport.clientHeight, clientY - bounds.top - viewport.clientTop)),
  };
};

const slotKey = (stageId: string, periodTypeId: string, lessonIndices: number[]): string =>
  `${stageId}:${periodTypeId}:${sortedLessonIndices(lessonIndices).join(',')}`;

export const SupervisionWeekGrid: React.FC<SupervisionWeekGridProps> = ({
  snapshot,
  draft,
  posts,
  classMap,
  teacherMap,
  matching,
  allocator,
  isHistorical,
  selectedPostIds,
  onTogglePostSelection,
  onSetPostSelection,
  onEditRules,
  onDeletePost,
  onSelectTeacher,
}) => {
  const weekdays = useMemo(
    () => Array.from(new Set(draft.posts.map((post) => post.weekday))).sort((a, b) => a - b),
    [draft.posts]
  );

  const rows = useMemo(() => {
    const stageOrder = new Map(snapshot.stages.map((stage, index) => [stage.id, index]));
    const stageNames = new Map(snapshot.stages.map((stage) => [stage.id, stage.name]));
    const routines = new Map(snapshot.routines.map((routine) => [routine.stageId, routine]));
    const rowsByKey = new Map<string, WeekRow>();

    for (const post of posts) {
      const lessonIndices = sortedLessonIndices(post.lessonIndices);
      if (lessonIndices.length === 0) continue;
      const key = slotKey(post.stageId, post.periodTypeId, lessonIndices);
      if (rowsByKey.has(key)) continue;

      const routine = routines.get(post.stageId);
      const period = routine?.periodTypes.find((item) => item.id === post.periodTypeId);
      const lessonTimes = lessonIndices
        .map((lessonIndex) =>
          routine?.lessonTimes.find(
            (item) => item.periodTypeId === post.periodTypeId && item.lessonIndex === lessonIndex
          )
        )
        .filter((time) => time != null);
      const firstTime = lessonTimes[0];
      const lastTime = lessonTimes[lessonTimes.length - 1];
      const timeLabel =
        firstTime?.startMinute != null && lastTime?.endMinute != null
          ? `${formatMinute(firstTime.startMinute)}–${formatMinute(lastTime.endMinute)}`
          : lessonTimes.length > 1
            ? lessonTimes.map((time) => time.label).filter(Boolean).join(' · ')
            : firstTime?.label ?? '';

      rowsByKey.set(key, {
        key,
        stageId: post.stageId,
        stageName: stageNames.get(post.stageId) ?? '',
        periodName: period?.name ?? '课节',
        periodTypeId: post.periodTypeId,
        lessonIndices,
        stageOrder: stageOrder.get(post.stageId) ?? 0,
        sortOrder: period?.sortOrder ?? Number.MAX_SAFE_INTEGER,
        timeLabel,
      });
    }

    return Array.from(rowsByKey.values()).sort((a, b) => {
      if (a.stageOrder !== b.stageOrder) return a.stageOrder - b.stageOrder;
      if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
      return a.lessonIndices[0] - b.lessonIndices[0];
    });
  }, [posts, snapshot.routines, snapshot.stages]);

  const postsByCell = useMemo(() => {
    const cells = new Map<string, SupervisionPost[]>();
    for (const post of posts) {
      const key = `${slotKey(post.stageId, post.periodTypeId, post.lessonIndices)}:${post.weekday}`;
      const cell = cells.get(key) ?? [];
      cell.push(post);
      cells.set(key, cell);
    }
    return cells;
  }, [posts]);

  const gridTemplateColumns = `minmax(210px, 240px) repeat(${Math.max(weekdays.length, 1)}, minmax(180px, 1fr))`;
  const touchInput = hasTouchInput();
  const withSelectionPress = useSelectionPress();
  const viewportRef = useRef<HTMLDivElement>(null);
  const dragRef = useRef<MarqueeDrag | null>(null);
  const autoScrollTimerRef = useRef<number | null>(null);
  const suppressClickRef = useRef(false);
  const selectedPostIdsRef = useRef(selectedPostIds);
  const onSetPostSelectionRef = useRef(onSetPostSelection);
  const [marqueeRect, setMarqueeRect] = useState<MarqueeRect | null>(null);
  const [isMarqueeDragging, setIsMarqueeDragging] = useState(false);
  selectedPostIdsRef.current = selectedPostIds;
  onSetPostSelectionRef.current = onSetPostSelection;

  const handlePointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (event.isPrimary) suppressClickRef.current = false;
    if (isHistorical) return;
    if (event.pointerType !== 'mouse') {
      const target = event.target;
      if (!(target instanceof Element) || !target.closest('[data-selectable-post]') ||
          target.closest('button')) return;
    }
    withSelectionPress(event, () => {
      const viewport = viewportRef.current;
      if (!viewport) return;
      const point = localPoint(viewport, event.clientX, event.clientY);
      const additive = event.shiftKey || event.ctrlKey || event.metaKey;
      const selected = selectedPostIdsRef.current;
      const card = event.target instanceof Element
        ? event.target.closest<HTMLElement>('[data-selectable-post]')
        : null;
      const initialPostId = event.pointerType === 'touch' ? card?.dataset.postId : undefined;
      const lastSelection = initialPostId ? new Set([initialPostId]) : new Set(selected);
      dragRef.current = {
        pointerId: event.pointerId,
        startClient: { x: event.clientX, y: event.clientY },
        anchorContent: {
          x: point.x + viewport.scrollLeft,
          y: point.y + viewport.scrollTop,
        },
        currentLocal: point,
        baseSelection: additive ? new Set(selected) : new Set(),
        lastSelection,
        initialSelection: new Set(selected),
        started: false,
      };
      if (initialPostId) onSetPostSelectionRef.current(lastSelection);
    });
  };

  const handleClickCapture = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!suppressClickRef.current || event.detail === 0) return;
    suppressClickRef.current = false;
    event.preventDefault();
    event.stopPropagation();
  };

  useEffect(() => {
    const stopAutoScroll = () => {
      if (autoScrollTimerRef.current == null) return;
      window.clearInterval(autoScrollTimerRef.current);
      autoScrollTimerRef.current = null;
    };

    const updateSelection = (drag: MarqueeDrag, clientX: number, clientY: number) => {
      const viewport = viewportRef.current;
      if (!viewport) return;
      const bounds = viewport.getBoundingClientRect();
      const point = localPoint(viewport, clientX, clientY);
      drag.currentLocal = point;
      const currentContent = {
        x: point.x + viewport.scrollLeft,
        y: point.y + viewport.scrollTop,
      };
      const left = Math.min(drag.anchorContent.x, currentContent.x);
      const right = Math.max(drag.anchorContent.x, currentContent.x);
      const top = Math.min(drag.anchorContent.y, currentContent.y);
      const bottom = Math.max(drag.anchorContent.y, currentContent.y);
      const contentLeft = bounds.left + viewport.clientLeft;
      const contentTop = bounds.top + viewport.clientTop;
      const next = new Set(drag.baseSelection);

      for (const card of viewport.querySelectorAll<HTMLElement>('[data-selectable-post]')) {
        const postId = card.dataset.postId;
        if (!postId) continue;
        const cardBounds = card.getBoundingClientRect();
        const cardLeft = cardBounds.left - contentLeft + viewport.scrollLeft;
        const cardRight = cardBounds.right - contentLeft + viewport.scrollLeft;
        const cardTop = cardBounds.top - contentTop + viewport.scrollTop;
        const cardBottom = cardBounds.bottom - contentTop + viewport.scrollTop;
        if (cardRight >= left && cardLeft <= right && cardBottom >= top && cardTop <= bottom) {
          next.add(postId);
        }
      }

      if (!areSetsEqual(next, drag.lastSelection)) {
        drag.lastSelection = next;
        onSetPostSelectionRef.current(next);
      }
      setMarqueeRect({
        left,
        top,
        width: Math.abs(drag.anchorContent.x - currentContent.x),
        height: Math.abs(drag.anchorContent.y - currentContent.y),
      });
    };

    const beginAutoScroll = () => {
      if (autoScrollTimerRef.current != null) return;
      autoScrollTimerRef.current = window.setInterval(() => {
        const drag = dragRef.current;
        const viewport = viewportRef.current;
        if (!drag?.started || !viewport) return;
        const edge = 40;
        const speed = (position: number, extent: number) => {
          if (position < edge) return -Math.ceil(((edge - position) / edge) * 16);
          if (position > extent - edge) {
            return Math.ceil(((position - extent + edge) / edge) * 16);
          }
          return 0;
        };
        const nextLeft = Math.max(
          0,
          Math.min(
            viewport.scrollWidth - viewport.clientWidth,
            viewport.scrollLeft + speed(drag.currentLocal.x, viewport.clientWidth)
          )
        );
        const nextTop = Math.max(
          0,
          Math.min(
            viewport.scrollHeight - viewport.clientHeight,
            viewport.scrollTop + speed(drag.currentLocal.y, viewport.clientHeight)
          )
        );
        if (nextLeft === viewport.scrollLeft && nextTop === viewport.scrollTop) return;
        viewport.scrollLeft = nextLeft;
        viewport.scrollTop = nextTop;
        const bounds = viewport.getBoundingClientRect();
        updateSelection(
          drag,
          bounds.left + viewport.clientLeft + drag.currentLocal.x,
          bounds.top + viewport.clientTop + drag.currentLocal.y
        );
      }, 16);
    };

    const handlePointerMove = (event: PointerEvent) => {
      const drag = dragRef.current;
      if (!drag || event.pointerId !== drag.pointerId) return;
      if (!drag.started) {
        const dx = event.clientX - drag.startClient.x;
        const dy = event.clientY - drag.startClient.y;
        if (dx * dx + dy * dy < 16) return;
        drag.started = true;
        setIsMarqueeDragging(true);
        viewportRef.current?.focus({ preventScroll: true });
        beginAutoScroll();
      }
      event.preventDefault();
      updateSelection(drag, event.clientX, event.clientY);
    };

    const finishPointer = (event: PointerEvent) => {
      const drag = dragRef.current;
      if (!drag || event.pointerId !== drag.pointerId) return;
      if (drag.started) {
        updateSelection(drag, event.clientX, event.clientY);
        setIsMarqueeDragging(false);
        setMarqueeRect(null);
        suppressClickRef.current = true;
      }
      dragRef.current = null;
      stopAutoScroll();
    };

    const cancelPointer = (event: PointerEvent) => {
      const drag = dragRef.current;
      if (!drag || event.pointerId !== drag.pointerId) return;
      dragRef.current = null;
      stopAutoScroll();
      if (!drag.started && areSetsEqual(drag.initialSelection, drag.lastSelection)) return;
      setIsMarqueeDragging(false);
      setMarqueeRect(null);
      onSetPostSelectionRef.current(drag.initialSelection);
    };

    window.addEventListener('pointermove', handlePointerMove, { passive: false });
    window.addEventListener('pointerup', finishPointer);
    window.addEventListener('pointercancel', cancelPointer);
    return () => {
      window.removeEventListener('pointermove', handlePointerMove);
      window.removeEventListener('pointerup', finishPointer);
      window.removeEventListener('pointercancel', cancelPointer);
      stopAutoScroll();
    };
  }, []);

  return (
    <div className="space-y-3">
      {touchInput && !isHistorical && posts.length > 0 && (
        <p className="text-xs text-ink-secondary">长按岗位卡片后拖动可多选</p>
      )}
      {posts.length === 0 ? (
        <div className="rounded-xl border border-dashed border-border bg-surface px-4 py-10 text-center text-sm text-ink-secondary">
          当前筛选下没有带班岗位
        </div>
      ) : (
        <div
          ref={viewportRef}
          tabIndex={-1}
          onPointerDown={handlePointerDown}
          onClickCapture={handleClickCapture}
          onKeyDown={(event) => {
            if (
              event.key !== 'Escape' ||
              (selectedPostIds.size === 0 && !isMarqueeDragging)
            ) {
              return;
            }
            event.preventDefault();
            event.stopPropagation();
            dragRef.current = null;
            if (autoScrollTimerRef.current != null) {
              window.clearInterval(autoScrollTimerRef.current);
              autoScrollTimerRef.current = null;
            }
            setIsMarqueeDragging(false);
            setMarqueeRect(null);
            onSetPostSelection(new Set());
          }}
          className="relative max-h-[70vh] overflow-auto rounded-xl border border-border bg-surface select-none focus:outline-none"
        >
          <div className="grid min-w-full" style={{ gridTemplateColumns }}>
            <div className="sticky left-0 top-0 z-30 border-b border-r border-border bg-table-header px-4 py-3 text-xs font-semibold text-ink-secondary">
              节次 / 时间
            </div>
            {weekdays.map((weekday) => (
              <div
                key={weekday}
                className="sticky top-0 z-20 border-b border-r border-border bg-table-header px-4 py-3 text-center text-sm font-semibold text-ink"
              >
                {WEEKDAY_LABELS[weekday - 1] ?? `周${weekday}`}
              </div>
            ))}

            {rows.map((row) => {
              const contiguous = row.lessonIndices.every(
                (lessonIndex, index) => index === 0 || lessonIndex === row.lessonIndices[index - 1] + 1
              );
              const firstLesson = row.lessonIndices[0];
              const lastLesson = row.lessonIndices[row.lessonIndices.length - 1];
              const lessonLabel = contiguous
                ? firstLesson === lastLesson
                  ? `第 ${firstLesson} 节`
                  : `第 ${firstLesson}–${lastLesson} 节`
                : `第 ${row.lessonIndices.join('、')} 节`;
              return (
                <React.Fragment key={row.key}>
                  <div className="sticky left-0 z-10 border-b border-r border-border bg-surface p-2.5">
                    <div className="relative flex h-full min-h-[108px] flex-col items-center justify-center gap-1.5 overflow-hidden rounded-xl bg-canvas px-3 py-3 text-center">
                      <span className="absolute inset-y-3 left-0 w-1 rounded-r bg-primary" aria-hidden="true" />
                      <span className="font-semibold text-sm text-ink">
                        {row.periodName} · {lessonLabel}
                      </span>
                      <span className="font-mono text-xs tabular-nums text-ink-secondary">
                        {row.timeLabel || '时间未设置'}
                      </span>
                      <Badge variant="outline" className="h-5 px-2 text-[10px] font-normal">
                        {row.stageName || '未分类学段'}
                      </Badge>
                    </div>
                  </div>

                  {weekdays.map((weekday) => {
                    const cellKey = `${row.key}:${weekday}`;
                    const cellPosts = postsByCell.get(cellKey) ?? [];
                    return (
                      <div
                        key={`${row.key}:${weekday}`}
                        className="min-w-0 border-b border-r border-border p-2"
                      >
                        <div className="flex min-h-[108px] flex-col gap-2">
                          {cellPosts.map((post) => {
                        const isSelected = selectedPostIds.has(post.id);
                        const classNames = post.classIds
                          .map((id) => classMap.get(id) ?? id)
                          .join('、');
                        const teacherId = draft.assignments[post.id];
                        const teacherName = teacherId
                          ? teacherMap.get(teacherId) ?? teacherId
                          : null;
                        const blockers = teacherId
                          ? allocator.teacherBlockers(snapshot, draft, post, teacherId, matching ?? undefined)
                          : [];
                        const reason = teacherId && matching
                          ? matching.reasons(post, teacherId)[0]
                          : undefined;

                        return (
                          <div
                            key={`${row.key}:${post.id}`}
                            data-selectable-post=""
                            data-post-id={post.id}
                            onClick={(event) => {
                              if (isHistorical || (!touchInput && selectedPostIds.size === 0)) return;
                              if ((event.target as HTMLElement).closest('button,[role="checkbox"]')) return;
                              onTogglePostSelection(post.id);
                            }}
                            className={`group relative rounded-xl border p-3 text-xs transition-colors ${isHistorical ? '' : '[-webkit-touch-callout:none]'} ${
                              isSelected
                                ? 'cursor-pointer border-primary bg-selection/70 shadow-sm'
                                : 'cursor-default border-border bg-surface hover:border-primary/40 hover:bg-canvas/40'
                            }`}
                            title={`${post.name} · ${classNames}`}
                          >
                            <div className="flex items-start justify-between gap-2 pr-0.5">
                              <div className="min-w-0 flex-1">
                                <div className="truncate pr-1 font-semibold text-sm text-ink">
                                  {classNames}
                                </div>
                                <div className="mt-1 truncate text-[11px] text-ink-secondary">
                                  {post.groupName || post.name}
                                </div>
                              </div>
                              {!isHistorical && (
                                <div className="flex shrink-0 items-center gap-1">
                                  <div
                                    className={`transition-opacity ${isSelected || touchInput
                                      ? 'opacity-100'
                                      : 'pointer-events-none opacity-0 group-hover:pointer-events-auto group-hover:opacity-100 group-focus-within:pointer-events-auto group-focus-within:opacity-100'
                                    }`}
                                  >
                                    <Checkbox
                                      checked={isSelected}
                                      onCheckedChange={() => onTogglePostSelection(post.id)}
                                      aria-label={`选择岗位：${classNames}，${post.name}`}
                                    />
                                  </div>
                                  <DropdownMenu>
                                    <DropdownMenuTrigger asChild>
                                      <button
                                        type="button"
                                        aria-label="岗位操作"
                                        className="flex h-7 w-7 items-center justify-center rounded text-ink-secondary hover:bg-table-header hover:text-ink"
                                      >
                                        <MoreHorizontal className="h-4 w-4" />
                                      </button>
                                    </DropdownMenuTrigger>
                                    <DropdownMenuContent align="end" className="text-xs">
                                      <DropdownMenuItem onClick={() => onEditRules(post)}>
                                        <Settings2 className="mr-1.5 h-3.5 w-3.5" />
                                        规则
                                      </DropdownMenuItem>
                                      <DropdownMenuSeparator />
                                      <DropdownMenuItem
                                        onClick={() => onDeletePost(post.id)}
                                        className="text-destructive focus:text-destructive"
                                      >
                                        <Trash2 className="mr-1.5 h-3.5 w-3.5" />
                                        移除岗位
                                      </DropdownMenuItem>
                                    </DropdownMenuContent>
                                  </DropdownMenu>
                                </div>
                              )}
                            </div>

                            <button
                              type="button"
                              disabled={isHistorical}
                              onClick={() => onSelectTeacher(post)}
                              className={`mt-2 flex w-full items-center gap-1.5 truncate rounded-md px-1 py-1 text-left transition-colors disabled:cursor-default ${
                                teacherName
                                  ? blockers.length > 0
                                    ? 'bg-destructive/10 text-destructive'
                                    : 'text-ink-secondary hover:bg-selection/50 hover:text-primary'
                                  : 'border border-dashed border-amber-400/70 bg-amber-50/50 text-amber-700 hover:bg-amber-100/60 dark:bg-amber-950/20 dark:text-amber-300'
                              }`}
                            >
                              {teacherName ? (
                                <>
                                  <span className="truncate font-medium">{teacherName}</span>
                                  {reason && <span className="truncate text-[10px]">· {reason}</span>}
                                  {blockers.length > 0 && (
                                    <span className="ml-auto shrink-0 text-[10px]">有冲突</span>
                                  )}
                                </>
                              ) : (
                                <>
                                  <UserPlus className="h-3.5 w-3.5 shrink-0" />
                                  <span>待安排 · 指派教师</span>
                                </>
                              )}
                            </button>
                            {post.location && (
                              <div className="mt-1 truncate text-[10px] text-ink-secondary">
                                {post.location}
                              </div>
                            )}
                          </div>
                        );
                          })}
                        </div>
                      </div>
                    );
                  })}
                </React.Fragment>
              );
            })}
          </div>
          {isMarqueeDragging && marqueeRect && (
            <div
              aria-hidden="true"
              className="pointer-events-none absolute z-40 rounded-sm border border-primary bg-primary/10"
              style={marqueeRect}
            />
          )}
        </div>
      )}
    </div>
  );
};
