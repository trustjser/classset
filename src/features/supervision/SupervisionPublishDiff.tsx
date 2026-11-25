import React, { useEffect, useMemo, useState } from 'react';
import { ArrowRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import type { ScheduleData } from '@/domain/scheduling';
import type {
  SupervisionDraft,
  SupervisionPost,
  SupervisionPreview,
} from '@/domain/supervision';
import { withRoutineClock } from '@/domain/supervisionValidation';

type ChangeKind = 'add' | 'update' | 'remove';
type ChangeFilter = 'all' | ChangeKind;

interface SupervisionChange {
  id: string;
  kind: ChangeKind;
  before: string | null;
  after: string | null;
  context: string;
}

const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

function formatMinute(minute: number): string {
  return `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
}

function describePost(
  snapshot: ScheduleData,
  post: SupervisionPost,
  draft: SupervisionDraft | null,
  teacherNames: Map<string, string>,
  classNames: Map<string, string>
): string {
  const teacherId = draft?.assignments[post.id] ?? null;
  const teacherName = teacherId ? teacherNames.get(teacherId) ?? teacherId : '待安排';
  const routine = snapshot.routines.find((item) => item.stageId === post.stageId);
  const period = routine?.periodTypes.find((item) => item.id === post.periodTypeId);
  const firstLesson = post.lessonIndices[0] ?? 1;
  const lastLesson = post.lessonIndices[post.lessonIndices.length - 1] ?? firstLesson;
  const position = withRoutineClock(snapshot, {
    stageId: post.stageId,
    weekday: post.weekday,
    periodTypeId: post.periodTypeId,
    lessonIndex: firstLesson,
  });
  const timeLabel =
    position.startMinute != null && position.endMinute != null
      ? `${formatMinute(position.startMinute)}-${formatMinute(position.endMinute)}`
      : '';
  const lessonLabel =
    firstLesson === lastLesson
      ? `第${firstLesson}节`
      : `第${firstLesson}-${lastLesson}节`;
  const classLabel = post.groupName || post.classIds.map((id) => classNames.get(id) ?? id).join('、');

  return [
    `${post.name} · ${teacherName}`,
    [
      WEEKDAYS[post.weekday - 1] ?? `周${post.weekday}`,
      [period?.name, lessonLabel, timeLabel].filter(Boolean).join(' '),
      classLabel,
      post.location,
    ]
      .filter(Boolean)
      .join(' · '),
  ].join('\n');
}

function buildChanges(snapshot: ScheduleData, preview: SupervisionPreview): SupervisionChange[] {
  const beforeDraft = preview.before?.draft ?? null;
  const oldPosts = new Map((beforeDraft?.posts ?? []).map((post) => [post.id, post]));
  const newPosts = new Map(preview.draft.posts.map((post) => [post.id, post]));
  const teacherNames = new Map(snapshot.teachers.map((teacher) => [teacher.id, teacher.name]));
  const classNames = new Map(snapshot.classes.map((schoolClass) => [schoolClass.id, schoolClass.name]));
  const changes: SupervisionChange[] = [];

  for (const id of new Set([...oldPosts.keys(), ...newPosts.keys()])) {
    const oldPost = oldPosts.get(id);
    const newPost = newPosts.get(id);
    const before = oldPost
      ? describePost(snapshot, oldPost, beforeDraft, teacherNames, classNames)
      : null;
    const after = newPost
      ? describePost(snapshot, newPost, preview.draft, teacherNames, classNames)
      : null;
    if (before === after) continue;

    const contextPost = newPost ?? oldPost;
    if (!contextPost) continue;
    changes.push({
      id,
      kind: before === null ? 'add' : after === null ? 'remove' : 'update',
      before,
      after,
      context: before === null ? after!.split('\n')[1] ?? '' : before.split('\n')[1] ?? '',
    });
  }

  return changes;
}

function getTeacherLoads(draft: SupervisionDraft | null | undefined): Map<string, number> {
  const loads = new Map<string, number>();
  if (!draft) return loads;
  for (const post of draft.posts) {
    const teacherId = draft.assignments[post.id];
    if (!teacherId) continue;
    loads.set(teacherId, (loads.get(teacherId) ?? 0) + post.lessonIndices.length);
  }
  return loads;
}

function changeTone(kind: ChangeKind): string {
  if (kind === 'add') return 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300';
  if (kind === 'remove') return 'bg-destructive/10 text-destructive';
  return 'bg-amber-500/10 text-amber-700 dark:text-amber-300';
}

function changeLabel(kind: ChangeKind): string {
  if (kind === 'add') return '新增';
  if (kind === 'remove') return '停排';
  return '调整';
}

function ChangeRow({ change }: { change: SupervisionChange }) {
  const field = (label: string, value: string | null) => (
    <div className="min-w-0 rounded-md bg-canvas/60 px-2 py-1.5">
      <div className="mb-0.5 text-[10px] text-ink-secondary">{label}</div>
      <div className="truncate text-xs font-medium text-ink" title={value?.split('\n')[0] ?? '—'}>
        {value?.split('\n')[0] ?? '—'}
      </div>
    </div>
  );

  return (
    <article className="grid grid-cols-[auto_minmax(0,1fr)] items-start gap-x-2 gap-y-1.5 border-t border-border/70 py-2 sm:grid-cols-[3.5rem_minmax(7rem,0.9fr)_minmax(0,1fr)_1rem_minmax(0,1fr)] sm:items-center">
      <span className={`mt-0.5 inline-flex h-5 items-center rounded-full px-2 text-[10px] font-medium sm:mt-0 ${changeTone(change.kind)}`}>
        {changeLabel(change.kind)}
      </span>
      <div className="whitespace-pre-line text-[11px] text-ink-secondary">{change.context}</div>
      <div className="col-span-2 grid grid-cols-[1fr_auto_1fr] items-center gap-1.5 sm:col-span-3">
        {field('变更前', change.before)}
        <ArrowRight aria-hidden="true" className="h-3.5 w-3.5 text-ink-secondary" />
        {field('变更后', change.after)}
      </div>
    </article>
  );
}

export const SupervisionPublishDiff: React.FC<{
  snapshot: ScheduleData;
  preview: SupervisionPreview;
}> = ({ snapshot, preview }) => {
  const [filter, setFilter] = useState<ChangeFilter>('all');
  const changes = useMemo(() => buildChanges(snapshot, preview), [snapshot, preview]);
  const oldLoads = useMemo(() => getTeacherLoads(preview.before?.draft), [preview]);
  const newLoads = useMemo(() => getTeacherLoads(preview.draft), [preview]);
  const teacherNames = useMemo(
    () => new Map(snapshot.teachers.map((teacher) => [teacher.id, teacher.name])),
    [snapshot.teachers]
  );

  useEffect(() => setFilter('all'), [preview]);

  const counts: Record<ChangeFilter, number> = {
    all: changes.length,
    add: changes.filter((change) => change.kind === 'add').length,
    update: changes.filter((change) => change.kind === 'update').length,
    remove: changes.filter((change) => change.kind === 'remove').length,
  };
  const visibleChanges = changes.filter((change) => filter === 'all' || change.kind === filter);
  const teacherLoadChanges = [...new Set([...oldLoads.keys(), ...newLoads.keys()])]
    .filter((id) => oldLoads.get(id) !== newLoads.get(id))
    .map((id) => ({
      id,
      name: teacherNames.get(id) ?? id,
      before: oldLoads.get(id) ?? 0,
      after: newLoads.get(id) ?? 0,
    }));

  const filters: { value: ChangeFilter; label: string }[] = [
    { value: 'all', label: '全部' },
    { value: 'add', label: '新增' },
    { value: 'update', label: '调整' },
    { value: 'remove', label: '停排' },
  ];

  return (
    <div className="space-y-3">
      {preview.replacedFutureDate && (
        <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-800 dark:text-amber-200">
          本次确认将替换原定 {preview.replacedFutureDate} 生效的带班方案。
        </div>
      )}

      <section className="space-y-1.5">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h4 className="text-xs font-semibold text-ink">岗位变更</h4>
          <div role="group" aria-label="筛选岗位变更" className="flex flex-wrap items-center gap-0.5">
            {filters.map((item) => (
              <Button
                key={item.value}
                type="button"
                size="sm"
                variant={filter === item.value ? 'secondary' : 'ghost'}
                className="h-7 px-2 text-[11px]"
                aria-pressed={filter === item.value}
                onClick={() => setFilter(item.value)}
              >
                {item.label} {counts[item.value]}
              </Button>
            ))}
          </div>
        </div>
        <div className="max-h-56 overflow-y-auto rounded-lg border border-border px-3">
          {visibleChanges.length === 0 ? (
            <div className="py-6 text-center text-xs text-ink-secondary">
              {changes.length === 0 ? '岗位安排无变化。' : '该类型暂无变更。'}
            </div>
          ) : (
            visibleChanges.map((change) => <ChangeRow key={change.id} change={change} />)
          )}
        </div>
      </section>

      {teacherLoadChanges.length > 0 && (
        <section className="space-y-1.5">
          <h4 className="text-xs font-semibold text-ink">教师周带班量变化</h4>
          <div className="flex flex-wrap gap-1.5">
            {teacherLoadChanges.map((teacher) => (
              <span key={teacher.id} className="rounded-md bg-canvas/70 px-2 py-1 text-[11px] text-ink-secondary">
                {teacher.name} · {teacher.before} → {teacher.after} 节 / 周
              </span>
            ))}
          </div>
        </section>
      )}

      {preview.scheduleChanges.length > 0 && (
        <section className="space-y-1.5">
          <h4 className="text-xs font-semibold text-ink">正课协调</h4>
          <ul className="divide-y divide-border/60 rounded-lg border border-border px-3 text-[11px] text-ink-secondary">
            {preview.scheduleChanges.map((change, index) => (
              <li key={`${index}-${change}`} className="py-1.5">
                {change}
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
};
