import React, { useEffect, useMemo, useState } from 'react';
import { Search } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import type { ClassGroup, Subject, Teacher, TeacherAssignment, WeekMode } from '@/domain/models';
import { combinedLessonCandidates } from './teacherLogic';

const modeLabels: Record<WeekMode, string> = { weekly: '每周', odd: '单周', even: '双周' };

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  initialTeacherId: string | null;
  initialTab: 'create' | 'all';
  assignments: TeacherAssignment[];
  teachers: Teacher[];
  classes: ClassGroup[];
  subjects: Subject[];
  error?: string;
  onCombine: (ids: string[]) => Promise<boolean>;
  onSplit: (groupId: string) => Promise<boolean>;
};

export const CombinedLessonWorkspace: React.FC<Props> = ({ open, onOpenChange, initialTeacherId, initialTab, assignments, teachers, classes, subjects, error, onCombine, onSplit }) => {
  const [teacherId, setTeacherId] = useState(initialTeacherId ?? '');
  const [tab, setTab] = useState<'create' | 'existing' | 'all'>('create');
  const [groupKey, setGroupKey] = useState('');
  const [selected, setSelected] = useState<string[]>([]);
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (!open) return;
    setTeacherId(initialTeacherId ?? teachers.find((item) => assignments.some((row) => row.teacherId === item.id))?.id ?? teachers[0]?.id ?? '');
    setTab(initialTab); setSelected([]); setGroupKey(''); setQuery('');
  }, [open, initialTeacherId, initialTab]);
  const className = (id: string) => classes.find((item) => item.id === id)?.name ?? id;
  const subjectName = (id: string) => subjects.find((item) => item.id === id)?.name ?? id;
  const teacherName = (id: string) => teachers.find((item) => item.id === id)?.name ?? id;
  const allGroups = useMemo(() => {
    const groups = new Map<string, TeacherAssignment[]>();
    for (const item of assignments) if (item.combinedLessonGroupId) groups.set(item.combinedLessonGroupId, [...(groups.get(item.combinedLessonGroupId) ?? []), item]);
    return [...groups].map(([id, rows]) => ({ id, rows }));
  }, [assignments]);
  const candidates = useMemo(() => combinedLessonCandidates(assignments, teacherId), [assignments, teacherId]);
  const active = candidates.find((item) => item.key === groupKey) ?? candidates[0];
  const existing = allGroups.filter((item) => item.rows[0]?.teacherId === teacherId);
  const visible = active?.rows.filter((item) => className(item.classId).includes(query)) ?? [];
  const reset = (next: boolean) => onOpenChange(next);
  const performCombine = async () => {
    if (selected.length < 2) return;
    setBusy(true);
    try { if (await onCombine(selected)) { setSelected([]); setTab('existing'); } }
    finally { setBusy(false); }
  };
  const performSplit = async (id: string) => {
    if (!window.confirm('拆分合班后，这些班级会恢复为独立课程。确认拆分？')) return;
    setBusy(true);
    try { await onSplit(id); }
    finally { setBusy(false); }
  };

  return <Dialog open={open} onOpenChange={reset}><DialogContent className="!left-auto !right-0 !top-0 !h-screen !w-[min(720px,100vw)] !max-w-none !translate-x-0 !translate-y-0 !gap-0 !rounded-none !rounded-l-card !p-0 grid-rows-[auto_auto_auto_minmax(0,1fr)_auto]">
    <div className="border-b border-border px-6 pb-3 pt-5"><DialogTitle>{tab === 'all' ? '全部合班课' : `合班 · ${teacherName(teacherId)}`}</DialogTitle><DialogDescription className="mt-1">同一教师、科目、周模式和节数的不同班级可合班。</DialogDescription></div>
    <div className="grid grid-cols-2 gap-3 border-b border-border bg-table-header px-6 py-3 text-[12px] sm:grid-cols-4"><label>任课教师<select className="mt-1 h-9 w-full rounded-control border border-border bg-surface px-2" value={teacherId} onChange={(event) => { setTeacherId(event.target.value); setSelected([]); setGroupKey(''); }}><option value="">选择教师</option>{teachers.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><div>科目<div className="mt-2 truncate font-medium">{active ? subjectName(active.subjectId) : '—'}</div></div><div>周模式<div className="mt-2 font-medium">{active ? modeLabels[active.weekMode] : '—'}</div></div><div>节数<div className="mt-2 font-medium text-primary">{active ? `${active.lessonCount} 节` : '—'}</div></div></div>
    <div className="flex gap-5 border-b border-border px-6 pt-3 text-[13px]">{([['create','新建合班'],['existing',`已有合班组 ${existing.length}`],['all',`全部合班课 ${allGroups.length}`]] as const).map(([value,label]) => <button key={value} role="tab" aria-selected={tab === value} className={`border-b-2 pb-2 ${tab === value ? 'border-primary text-primary' : 'border-transparent text-ink-secondary'}`} onClick={() => setTab(value)}>{label}</button>)}</div>
    <div className="min-h-0 overflow-y-auto p-6 text-[13px]">
      {error && <div role="alert" className="mb-3 rounded-control bg-destructive-surface px-3 py-2 text-destructive">{error}</div>}
      {tab === 'create' && <><div className="mb-3 flex flex-wrap gap-2">{candidates.map((item) => <button key={item.key} onClick={() => { setGroupKey(item.key); setSelected([]); }} className={`rounded-control border px-3 py-1.5 ${item.key === active?.key ? 'border-primary bg-selection text-primary' : 'border-border'}`}>{subjectName(item.subjectId)} · {modeLabels[item.weekMode]} {item.lessonCount} 节 · {item.rows.length} 班</button>)}</div>{active ? <div className="grid gap-5 sm:grid-cols-2"><div><div className="mb-2 flex items-center justify-between"><strong>可合并的班级 · {visible.length}</strong><button className="text-primary" onClick={() => setSelected(visible.every((item) => selected.includes(item.id)) ? [] : visible.map((item) => item.id))}>全选</button></div><label className="relative block"><Search className="absolute left-2.5 top-2.5 h-4 w-4 text-ink-secondary"/><Input placeholder="搜索班级" value={query} onChange={(event) => setQuery(event.target.value)} className="pl-8"/></label><div className="mt-2 divide-y divide-table-divider rounded-control border border-border">{visible.map((item) => <label key={item.id} className="flex cursor-pointer gap-2 px-3 py-2.5 hover:bg-selection"><input type="checkbox" checked={selected.includes(item.id)} onChange={(event) => setSelected(event.target.checked ? [...selected, item.id] : selected.filter((id) => id !== item.id))}/>{className(item.classId)}</label>)}</div></div><div><strong>合班预览</strong><div className="mt-3 rounded-control border border-border bg-table-header p-4">{selected.length >= 2 ? <><strong>{selected.map((id) => className(active.rows.find((item) => item.id === id)!.classId)).join('、')} 合班</strong><p className="mt-2 text-ink-secondary">{subjectName(active.subjectId)} · {modeLabels[active.weekMode]} · {active.lessonCount} 节</p><p className="mt-1 text-ink-secondary">{selected.length} 个班共用同一位教师的课节。</p></> : '选择至少 2 个班级后预览合班。'}</div></div></div> : <div className="py-12 text-center text-ink-secondary">这位教师暂无条件一致的可合并班级。</div>}</>}
      {tab === 'existing' && (existing.length ? <div className="space-y-2">{existing.map((group) => <div key={group.id} className="flex items-center gap-3 rounded-control border border-border p-3"><div className="min-w-0 flex-1"><strong>{group.rows.map((item) => className(item.classId)).join('、')} 合班</strong><p className="mt-1 text-ink-secondary">{subjectName(group.rows[0].subjectId)} · {modeLabels[group.rows[0].weekMode]} · {group.rows[0].lessonCount} 节</p></div><Button variant="outline" size="sm" disabled={busy} onClick={() => void performSplit(group.id)}>拆分</Button></div>)}</div> : <div className="py-12 text-center text-ink-secondary">这位教师还没有合班课。</div>)}
      {tab === 'all' && (allGroups.length ? <div className="space-y-2">{allGroups.map((group) => <div key={group.id} className="flex items-center gap-3 rounded-control border border-border p-3"><div className="min-w-0 flex-1"><strong>{group.rows.map((item) => className(item.classId)).join('、')} 合班</strong><p className="mt-1 text-ink-secondary">{teacherName(group.rows[0].teacherId ?? '')} · {subjectName(group.rows[0].subjectId)} · {modeLabels[group.rows[0].weekMode]} · {group.rows[0].lessonCount} 节</p></div><Button variant="outline" size="sm" disabled={busy} onClick={() => void performSplit(group.id)}>拆分</Button></div>)}</div> : <div className="py-12 text-center text-ink-secondary">本学期还没有合班课。</div>)}
    </div>
    <div className="flex items-center justify-between border-t border-border px-6 py-3 text-[12px] text-ink-secondary"><span>本学期共 {allGroups.length} 组合班课</span>{tab === 'create' && <Button disabled={busy || selected.length < 2} onClick={() => void performCombine()}>确认合班 · {selected.length} 班</Button>}</div>
  </DialogContent></Dialog>;
};
