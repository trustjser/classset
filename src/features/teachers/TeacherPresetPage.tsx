import React, { useEffect, useMemo, useState } from 'react';
import { createPortal } from 'react-dom';
import { ArrowLeft, ChevronDown, ChevronRight, Search, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import type { ScopeType, Teacher, TeacherGroup, TeacherGroupMember, TeacherGroupPreset, TeacherPreset, PresetValue } from '@/domain/models';
import { schoolRepository } from '@/repository/schoolRepository';
import { useAppStore } from '@/store/useAppStore';
import { resolveTeacherPreset } from './teacherLogic';

const dayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const valueLabels: Record<PresetValue, string> = { auto: '自动', prefer: '尽量排', must: '一定排', forbid: '不排' };
type Owner = { kind: 'teacher' | 'group'; id?: string };
type Scope = { type: ScopeType; id: string; stageId: string; label: string };
type Slot = { weekday: number; periodTypeId: string; lessonIndex: number; label: string };
const cellKey = (scope: Scope, slot: Slot) => JSON.stringify([scope.type, scope.id, scope.stageId, slot.weekday, slot.periodTypeId, slot.lessonIndex]);

export const TeacherPresetPage: React.FC<{ termId: string; owner: Owner; teachers: Teacher[]; groups: TeacherGroup[]; members: TeacherGroupMember[]; onBack: () => void }> = ({ termId, owner, teachers, groups, members, onBack }) => {
  const { stages, grades, classes, routinesByStage, freeSlotsByStage, loadFreeSlotsForStages } = useAppStore();
  const [ownerKind, setOwnerKind] = useState<Owner['kind']>(owner.kind);
  const [ownerId, setOwnerId] = useState(owner.id ?? '');
  const [scope, setScope] = useState<Scope | null>(null);
  const [expanded, setExpanded] = useState<string[]>(stages.map((item) => item.id));
  const [query, setQuery] = useState('');
  const [personal, setPersonal] = useState<TeacherPreset[]>([]);
  const [groupPresets, setGroupPresets] = useState<TeacherGroupPreset[]>([]);
  const [draft, setDraft] = useState<Partial<Record<string, PresetValue>>>({});
  const [dirty, setDirty] = useState(false);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const [cellMenu, setCellMenu] = useState<{ key: string; x: number; y: number; value: PresetValue } | null>(null);
  useEffect(() => {
    if (!cellMenu) return;
    const close = () => setCellMenu(null);
    const keyDown = (event: KeyboardEvent) => { if (event.key === 'Escape') close(); };
    window.addEventListener('pointerdown', close);
    window.addEventListener('scroll', close, true);
    window.addEventListener('keydown', keyDown);
    return () => { window.removeEventListener('pointerdown', close); window.removeEventListener('scroll', close, true); window.removeEventListener('keydown', keyDown); };
  }, [cellMenu]);
  useEffect(() => {
    if (!ownerId) setOwnerId(ownerKind === 'teacher' ? teachers[0]?.id ?? '' : groups[0]?.id ?? '');
  }, [ownerId, ownerKind, teachers, groups]);
  useEffect(() => {
    void Promise.all([schoolRepository.loadTeacherPresets(termId), schoolRepository.loadTeacherGroupPresets(termId)]).then(([a, b]) => { setPersonal(a); setGroupPresets(b); }).catch((cause) => setError(String(cause)));
  }, [termId]);
  useEffect(() => { if (stages.length) void loadFreeSlotsForStages(stages.map((item) => item.id)); }, [stages, loadFreeSlotsForStages]);
  const scopes = useMemo(() => {
    const result: Scope[] = [];
    for (const stage of stages) {
      if (!routinesByStage[stage.id]?.periodTypes.length) continue;
      result.push({ type: 'stage', id: stage.id, stageId: stage.id, label: stage.name });
      for (const grade of grades.filter((item) => item.stageId === stage.id).sort((a, b) => a.sortOrder - b.sortOrder)) {
        result.push({ type: 'grade', id: grade.id, stageId: stage.id, label: grade.name });
        for (const schoolClass of classes.filter((item) => item.gradeId === grade.id).sort((a, b) => a.sortOrder - b.sortOrder)) {
          result.push({ type: 'class', id: schoolClass.id, stageId: stage.id, label: schoolClass.name });
        }
      }
    }
    return result;
  }, [stages, grades, classes, routinesByStage]);
  const activeScope = scope ?? scopes[0] ?? null;
  const routine = activeScope ? routinesByStage[activeScope.stageId] : null;
  const days = routine?.teachingDays.filter((item) => item.isTeachingDay).map((item) => item.weekday).sort((a, b) => a - b) ?? [];
  const rows = useMemo(() => routine ? [...routine.periodTypes].sort((a, b) => a.sortOrder - b.sortOrder).flatMap((period) => {
    const max = Math.max(...days.map((day) => routine.dailyOverrides.find((item) => item.periodTypeId === period.id && item.weekday === day)?.lessonCount ?? period.defaultLessonCount), 0);
    return Array.from({ length: max }, (_, at) => ({ periodTypeId: period.id, lessonIndex: at + 1, label: `${period.name} 第${at + 1}节` }));
  }) : [], [routine, days.join(',')]);
  const slots = useMemo(() => rows.flatMap((row) => days.map((weekday) => ({ ...row, weekday }))), [rows, days.join(',')]);
  const ownedRows = ownerKind === 'teacher' ? personal.filter((item) => item.teacherId === ownerId) : groupPresets.filter((item) => item.groupId === ownerId);
  const ownedValues = useMemo(() => Object.fromEntries(ownedRows.map((item) => [JSON.stringify([item.scopeType, item.scopeId, item.stageId, item.weekday, item.periodTypeId, item.lessonIndex]), item.value])) as Partial<Record<string, PresetValue>>, [ownedRows]);
  const inheritedValue = (slot: Slot): PresetValue | 'conflict' => {
    if (ownerKind !== 'teacher' || !activeScope) return 'auto';
    const ownGroupIds = new Set(members.filter((item) => item.teacherId === ownerId).map((item) => item.groupId));
    return resolveTeacherPreset(undefined, groupPresets.filter((item) => ownGroupIds.has(item.groupId) &&
      item.scopeType === activeScope.type && item.scopeId === activeScope.id && item.stageId === activeScope.stageId &&
      item.weekday === slot.weekday && item.periodTypeId === slot.periodTypeId && item.lessonIndex === slot.lessonIndex));
  };
  const selectedOwnerName = ownerKind === 'teacher' ? teachers.find((item) => item.id === ownerId)?.name : groups.find((item) => item.id === ownerId)?.name;
  function switchOwner(kind: Owner['kind'], id: string) {
    setCellMenu(null);
    if (dirty && !window.confirm('预排有未保存的修改，确定放弃吗？')) return;
    setOwnerKind(kind); setOwnerId(id); setDraft({}); setDirty(false); setError('');
  }
  function switchScope(next: Scope) {
    setCellMenu(null);
    if (dirty && !window.confirm('预排有未保存的修改，确定放弃吗？')) return;
    setScope(next); setDraft({}); setDirty(false); setError('');
  }
  async function save() {
    if (!ownerId || !activeScope) return;
    setSaving(true); setError('');
    try {
      const isCurrent = (item: { scopeType: ScopeType; scopeId: string; stageId: string }) => item.scopeType === activeScope.type && item.scopeId === activeScope.id && item.stageId === activeScope.stageId;
      const nextSlots = slots.filter((slot) => (draft[cellKey(activeScope, slot)] ?? ownedValues[cellKey(activeScope, slot)] ?? 'auto') !== 'auto');
      if (ownerKind === 'teacher') {
        const preserved = personal.filter((item) => item.teacherId === ownerId && !isCurrent(item));
        const next: TeacherPreset[] = [...preserved, ...nextSlots.map((slot) => ({ id: crypto.randomUUID(), termId, teacherId: ownerId, scopeType: activeScope.type,
          scopeId: activeScope.id, stageId: activeScope.stageId, weekday: slot.weekday, periodTypeId: slot.periodTypeId, lessonIndex: slot.lessonIndex,
          weekMode: 'weekly' as const, value: (draft[cellKey(activeScope, slot)] ?? ownedValues[cellKey(activeScope, slot)])! }))];
        await schoolRepository.replaceTeacherPresets(termId, ownerId, next);
        setPersonal([...personal.filter((item) => item.teacherId !== ownerId), ...next]);
      } else {
        const preserved = groupPresets.filter((item) => item.groupId === ownerId && !isCurrent(item));
        const next: TeacherGroupPreset[] = [...preserved, ...nextSlots.map((slot) => ({ id: crypto.randomUUID(), groupId: ownerId, scopeType: activeScope.type,
          scopeId: activeScope.id, stageId: activeScope.stageId, weekday: slot.weekday, periodTypeId: slot.periodTypeId, lessonIndex: slot.lessonIndex,
          weekMode: 'weekly' as const, value: (draft[cellKey(activeScope, slot)] ?? ownedValues[cellKey(activeScope, slot)])! }))];
        const affectedTeachers = members.filter((item) => item.groupId === ownerId).map((item) => item.teacherId);
        for (const teacherId of affectedTeachers) {
          const ownGroups = new Set(members.filter((item) => item.teacherId === teacherId).map((item) => item.groupId));
          const relevant = [...groupPresets.filter((item) => item.groupId !== ownerId), ...next].filter((item) => ownGroups.has(item.groupId));
          for (const slot of slots) {
            const matching = relevant.filter((item) => isCurrent(item) && item.weekday === slot.weekday && item.periodTypeId === slot.periodTypeId && item.lessonIndex === slot.lessonIndex);
            if (resolveTeacherPreset(undefined, matching) === 'conflict') throw new Error(`${teachers.find((item) => item.id === teacherId)?.name ?? '教师'}所属分组的预排规则冲突`);
          }
        }
        await schoolRepository.replaceTeacherGroupPresets(ownerId, next);
        setGroupPresets([...groupPresets.filter((item) => item.groupId !== ownerId), ...next]);
      }
      setDraft({}); setDirty(false);
    } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
    finally { setSaving(false); }
  }
  const goBack = () => { if (!dirty || window.confirm('预排有未保存的修改，确定返回吗？')) onBack(); };
  const freeStatus = (slot: Slot): 'all' | 'partial' | null => {
    if (!activeScope) return null;
    const relevantClasses = activeScope.type === 'class' ? classes.filter((item) => item.id === activeScope.id)
      : activeScope.type === 'grade' ? classes.filter((item) => item.gradeId === activeScope.id)
      : classes.filter((item) => grades.find((grade) => grade.id === item.gradeId)?.stageId === activeScope.stageId);
    if (!relevantClasses.length) return null;
    const count = relevantClasses.filter((schoolClass) => (freeSlotsByStage[activeScope.stageId] ?? []).some((free) => free.weekday === slot.weekday && free.periodTypeId === slot.periodTypeId && free.lessonIndex === slot.lessonIndex && (
      free.scopeType === 'stage' && free.scopeId === activeScope.stageId || free.scopeType === 'grade' && free.scopeId === schoolClass.gradeId || free.scopeType === 'class' && free.scopeId === schoolClass.id || free.scopeType === 'school' && free.scopeId === termId
    ))).length;
    return count === relevantClasses.length ? 'all' : count ? 'partial' : null;
  };
  const setPresetCell = (key: string, value: PresetValue) => { setDraft((current) => ({ ...current, [key]: value })); setDirty(true); setCellMenu(null); };
  return <div className="space-y-4"><div className="flex items-center gap-3 rounded-card bg-surface px-5 py-3"><Button variant="ghost" onClick={goBack} aria-label="返回教师任课"><ArrowLeft className="h-4 w-4"/></Button><strong className="text-[16px] text-ink">教师预排</strong><span className="text-[13px] text-ink-secondary">{selectedOwnerName ?? '请选择教师或分组'}</span><div className="ml-auto">{dirty && <span className="mr-3 text-[12px] text-warning">未保存</span>}<Button disabled={!dirty || saving} onClick={() => void save()}>保存设置</Button></div></div>
    {error && <div role="alert" className="rounded-control bg-destructive-surface p-3 text-[13px] text-destructive">{error}</div>}
    {!scopes.length && <div className="rounded-card bg-surface p-8 text-ink-secondary">请先完成至少一个学段的作息设置。</div>}
    {!!scopes.length && <div className="grid gap-4 lg:grid-cols-[220px_220px_minmax(0,1fr)]"><aside className="rounded-card bg-surface p-3"><div className="mb-3 flex rounded-control bg-selection p-0.5">{(['teacher','group'] as const).map((kind) => <button key={kind} onClick={() => switchOwner(kind, '')} className={`flex-1 rounded-md py-1.5 text-[12px] ${ownerKind === kind ? 'bg-surface text-ink' : 'text-ink-secondary'}`}>{kind === 'teacher' ? '按教师' : '按教师分组'}</button>)}</div><label className="relative block"><Search className="absolute left-2 top-2 h-4 w-4 text-ink-secondary"/><Input className="pl-8" value={query} onChange={(event) => setQuery(event.target.value)} placeholder={ownerKind === 'teacher' ? '搜索教师' : '搜索分组'}/></label><div className="mt-2 max-h-[65vh] overflow-y-auto">{(ownerKind === 'teacher' ? teachers : groups).filter((item) => item.name.includes(query)).map((item) => <button key={item.id} onClick={() => switchOwner(ownerKind, item.id)} className={`block w-full rounded-control px-3 py-2 text-left text-[13px] ${ownerId === item.id ? 'bg-selection text-primary' : 'text-ink hover:bg-table-header'}`}>{item.name}</button>)}</div></aside><aside className="rounded-card bg-surface p-3"><strong className="mb-3 block px-2 text-[13px]">应用范围</strong><div className="max-h-[70vh] overflow-y-auto text-[13px]">{stages.filter((stage) => scopes.some((item) => item.type === 'stage' && item.id === stage.id)).map((stage) => <div key={stage.id}><div className="flex items-center"><button aria-label={`展开${stage.name}`} onClick={() => setExpanded(expanded.includes(stage.id) ? expanded.filter((id) => id !== stage.id) : [...expanded, stage.id])}>{expanded.includes(stage.id) ? <ChevronDown className="h-4 w-4"/> : <ChevronRight className="h-4 w-4"/>}</button><button onClick={() => switchScope(scopes.find((item) => item.id === stage.id)!)} className={`flex-1 rounded-control px-2 py-2 text-left ${activeScope?.id === stage.id ? 'bg-selection text-primary' : 'hover:bg-table-header'}`}>{stage.name}</button></div>{expanded.includes(stage.id) && grades.filter((grade) => grade.stageId === stage.id).map((grade) => <div key={grade.id} className="ml-4"><div className="flex items-center"><button aria-label={`展开${grade.name}`} onClick={() => setExpanded(expanded.includes(grade.id) ? expanded.filter((id) => id !== grade.id) : [...expanded, grade.id])}>{expanded.includes(grade.id) ? <ChevronDown className="h-4 w-4"/> : <ChevronRight className="h-4 w-4"/>}</button><button onClick={() => switchScope(scopes.find((item) => item.id === grade.id)!)} className={`flex-1 rounded-control px-2 py-2 text-left ${activeScope?.id === grade.id ? 'bg-selection text-primary' : 'hover:bg-table-header'}`}>{grade.name}</button></div>{expanded.includes(grade.id) && classes.filter((item) => item.gradeId === grade.id).map((item) => <button key={item.id} onClick={() => switchScope(scopes.find((scopeItem) => scopeItem.id === item.id)!)} className={`ml-5 block w-[calc(100%-20px)] rounded-control px-2 py-2 text-left ${activeScope?.id === item.id ? 'bg-selection text-primary' : 'hover:bg-table-header'}`}>{item.name}</button>)}</div>)}</div>)}</div></aside>
    <div className="min-w-0 space-y-4"><section className="overflow-hidden rounded-card bg-surface p-4"><div className="mb-3 text-[13px]"><strong>{selectedOwnerName ? `${selectedOwnerName} · ${activeScope?.label}` : '请选择教师或分组'}</strong><p className="mt-1 text-ink-secondary">空白格为自动；红底为免任课，不可编辑；黄字表示部分班级免任课。</p></div><div className="overflow-x-auto"><table className="w-full min-w-[550px] border-collapse text-[12px]"><thead><tr className="bg-table-header text-ink-secondary"><th className="w-28 border border-table-divider p-2">节次</th>{days.map((day) => <th key={day} className="border border-table-divider p-2">{dayLabels[day - 1]}</th>)}</tr></thead><tbody>{rows.map((row) => <tr key={`${row.periodTypeId}:${row.lessonIndex}`}><th className="border border-table-divider bg-table-header px-2 py-3 text-left">{row.label}</th>{days.map((weekday) => { const slot = { ...row, weekday }; const count = routine?.dailyOverrides.find((item) => item.periodTypeId === row.periodTypeId && item.weekday === weekday)?.lessonCount ?? routine?.periodTypes.find((item) => item.id === row.periodTypeId)?.defaultLessonCount ?? 0; const key = activeScope ? cellKey(activeScope, slot) : ''; const free = freeStatus(slot); const inherited = inheritedValue(slot); const value = draft[key] ?? ownedValues[key] ?? inherited; return <td key={weekday} className="border border-table-divider p-1" onContextMenu={(event) => { if (!ownerId || row.lessonIndex > count || free === 'all' || value === 'conflict') return; event.preventDefault(); setCellMenu({ key, x: Math.max(8, Math.min(event.clientX, window.innerWidth - 174)), y: Math.max(8, Math.min(event.clientY, window.innerHeight - 190)), value }); }}><select aria-label={`${dayLabels[weekday - 1]}${row.label}预排`} value={value} disabled={!ownerId || row.lessonIndex > count || free === 'all' || value === 'conflict'} onChange={(event) => setPresetCell(key, event.target.value as PresetValue)} className={`h-10 w-full rounded-control px-1 text-center outline-none focus:ring-2 focus:ring-primary ${free === 'all' ? 'bg-destructive-surface text-destructive' : free === 'partial' ? 'bg-warning-surface text-warning' : value === 'auto' ? 'bg-surface text-muted' : value === 'forbid' || value === 'conflict' ? 'bg-destructive-surface text-destructive' : 'bg-selection text-primary'}`}><option value="auto">{free === 'all' ? '免任课' : '自动'}</option>{value === 'conflict' && <option value="conflict">分组冲突</option>}<option value="prefer">尽量排</option><option value="must">一定排</option><option value="forbid">不排</option></select></td>; })}</tr>)}</tbody></table></div></section><section className="rounded-card bg-surface p-4"><div className="mb-3 flex justify-between text-[13px]"><strong>全部预排信息</strong><span className="text-ink-secondary">{ownedRows.length} 条</span></div>{ownedRows.length ? <div className="max-h-52 divide-y divide-table-divider overflow-y-auto">{ownedRows.map((item) => <div key={item.id} className="flex items-center gap-2 py-2 text-[12px]"><span className="min-w-0 flex-1">{scopes.find((option) => option.type === item.scopeType && option.id === item.scopeId)?.label ?? item.scopeId} · {dayLabels[item.weekday - 1]} · {routine?.periodTypes.find((period) => period.id === item.periodTypeId)?.name ?? '节次'} 第{item.lessonIndex}节 · {valueLabels[item.value]}</span><button aria-label="删除规则" onClick={() => { if (dirty && !window.confirm('请先保存当前修改，再删除其他规则。')) return; const next = ownedRows.filter((row) => row.id !== item.id); void (ownerKind === 'teacher' ? schoolRepository.replaceTeacherPresets(termId, ownerId, next as TeacherPreset[]) : schoolRepository.replaceTeacherGroupPresets(ownerId, next as TeacherGroupPreset[])).then(() => { if (ownerKind === 'teacher') setPersonal([...personal.filter((row) => row.teacherId !== ownerId), ...(next as TeacherPreset[])]); else setGroupPresets([...groupPresets.filter((row) => row.groupId !== ownerId), ...(next as TeacherGroupPreset[])]); }).catch((cause) => setError(String(cause))); }}><Trash2 className="h-4 w-4 text-ink-secondary"/></button></div>)}</div> : <div className="py-8 text-center text-[12px] text-ink-secondary">暂无预排规则，矩阵中的空白表示自动安排。</div>}</section></div></div>}
    {cellMenu && createPortal(<div role="menu" aria-label="课节预排设置" className="fixed z-[100] w-40 rounded-control border border-border bg-surface p-1 text-[13px] text-ink shadow-popover" style={{ left: cellMenu.x, top: cellMenu.y }} onPointerDown={(event) => event.stopPropagation()}>{(['auto', 'prefer', 'must', 'forbid'] as const).map((option) => <button key={option} role="menuitemradio" aria-checked={cellMenu.value === option} className={`block w-full rounded-md px-3 py-2 text-left hover:bg-selection ${cellMenu.value === option ? 'bg-selection text-primary' : ''}`} onClick={() => setPresetCell(cellMenu.key, option)}>{valueLabels[option]}</button>)}</div>, document.body)}
  </div>;
};
