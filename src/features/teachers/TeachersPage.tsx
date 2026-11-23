import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ChevronDown, MoreHorizontal, Plus, Search, Users } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import * as DropdownMenu from '@radix-ui/react-dropdown-menu';
import type { Teacher, TeacherAssignment, TeacherGroup, TeacherGroupMember, ClassGroup, WeekMode } from '@/domain/models';
import { schoolRepository } from '@/repository/schoolRepository';
import { useAppStore } from '@/store/useAppStore';
import { assignmentError, remainingCourses, teacherWeeklyLoad } from './teacherLogic';
import { TeacherPresetPage } from './TeacherPresetPage';
import { buildAssignmentsWorkbook, buildTeachersWorkbook, parseAssignmentsWorkbook, parseTeachersWorkbook } from './teacherWorkbook';
import { AssignmentCellPopover, type AssignmentDraft } from './AssignmentCellPopover';
import { CombinedLessonWorkspace } from './CombinedLessonWorkspace';
import { valuesForClass } from '@/features/subjects/subjectLogic';
import { getSubjectColor } from '@/styles/subjectColors';

const modeLabels: Record<WeekMode, string> = { weekly: '每周', odd: '单周', even: '双周' };
const byOrder = <T extends { sortOrder: number }>(rows: T[]) => [...rows].sort((a, b) => a.sortOrder - b.sortOrder);
const newId = () => crypto.randomUUID();
const presetOwnerFromRoute = (): { kind: 'teacher' | 'group'; id?: string } | null => {
  const [, section, page, kind, id] = window.location.hash.split('/');
  return section === 'teachers' && page === 'preset' && (kind === 'teacher' || kind === 'group')
    ? { kind, id: id ? decodeURIComponent(id) : undefined } : null;
};

export const TeachersPage: React.FC = () => {
  const { activeTermId, classes, grades, stages, subjects, subjectRequirements, teachers: storedTeachers, refreshTermData, resolvedDark } = useAppStore();
  const [view, setView] = useState<'class' | 'teacher' | 'group'>('class');
  const [teachers, setTeachers] = useState<Teacher[]>(storedTeachers);
  const [assignments, setAssignments] = useState<TeacherAssignment[]>([]);
  const [groups, setGroups] = useState<TeacherGroup[]>([]);
  const [members, setMembers] = useState<TeacherGroupMember[]>([]);
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [teacherEditor, setTeacherEditor] = useState<Teacher | 'new' | null>(null);
  const [teacherForm, setTeacherForm] = useState({ name: '', shortName: '', displayQualifier: '', subjectIds: [] as string[] });
  const [groupEditor, setGroupEditor] = useState<TeacherGroup | 'new' | null>(null);
  const [groupForm, setGroupForm] = useState({ name: '', description: '' });
  const [memberEditor, setMemberEditor] = useState<TeacherGroup | null>(null);
  const [memberIds, setMemberIds] = useState<string[]>([]);
  const [batchOpen, setBatchOpen] = useState(false);
  const [batchTeacherId, setBatchTeacherId] = useState('');
  const [batchSubjectId, setBatchSubjectId] = useState('');
  const [batchClassIds, setBatchClassIds] = useState<string[]>([]);
  const [batchMode, setBatchMode] = useState<WeekMode>('weekly');
  const [batchCount, setBatchCount] = useState(1);
  const [expandedTeachers, setExpandedTeachers] = useState<string[]>([]);
  const [expandedCourseClasses, setExpandedCourseClasses] = useState<string[]>([]);
  const [presetOwner, setPresetOwner] = useState<{ kind: 'teacher' | 'group'; id?: string } | null>(presetOwnerFromRoute);
  const [combineOpen, setCombineOpen] = useState(false);
  const [combineTeacherId, setCombineTeacherId] = useState<string | null>(null);
  const [combineTab, setCombineTab] = useState<'create' | 'all'>('create');
  const teacherFileRef = useRef<HTMLInputElement>(null);
  const assignmentFileRef = useRef<HTMLInputElement>(null);
  const courseExpansionInitialized = useRef(false);

  const reload = useCallback(async () => {
    if (!activeTermId) return;
    const [nextTeachers, nextAssignments, nextGroups, nextMembers] = await Promise.all([
      schoolRepository.loadTeachers(), schoolRepository.loadTeacherAssignments(activeTermId),
      schoolRepository.loadTeacherGroups(activeTermId), schoolRepository.loadTeacherGroupMembers(activeTermId),
    ]);
    setTeachers(nextTeachers); setAssignments(nextAssignments); setGroups(nextGroups); setMembers(nextMembers);
    useAppStore.setState({ teachers: nextTeachers });
    await refreshTermData(activeTermId);
  }, [activeTermId, refreshTermData]);
  useEffect(() => { void reload().catch((cause) => setError(String(cause))); }, [reload]);
  useEffect(() => {
    const sync = () => setPresetOwner(presetOwnerFromRoute());
    window.addEventListener('hashchange', sync);
    return () => window.removeEventListener('hashchange', sync);
  }, []);
  const openPreset = (kind: 'teacher' | 'group', id?: string) => {
    window.location.hash = `#/teachers/preset/${kind}${id ? `/${encodeURIComponent(id)}` : ''}`;
    setPresetOwner({ kind, id });
  };

  const gradeById = useMemo(() => new Map(grades.map((item) => [item.id, item])), [grades]);
  const classById = useMemo(() => new Map(classes.map((item) => [item.id, item])), [classes]);
  const subjectById = useMemo(() => new Map(subjects.map((item) => [item.id, item])), [subjects]);
  const teacherById = useMemo(() => new Map(teachers.map((item) => [item.id, item])), [teachers]);
  const className = (schoolClass: ClassGroup) => `${gradeById.get(schoolClass.gradeId)?.name ?? ''}${schoolClass.name}`;
  const teacherName = (teacher: Teacher) => `${teacher.name}${teacher.displayQualifier ? ` · ${teacher.displayQualifier}` : ''}`;
  const courses = useMemo(() => remainingCourses(classes, subjects, subjectRequirements, assignments), [classes, subjects, subjectRequirements, assignments]);
  useEffect(() => {
    if (!courseExpansionInitialized.current && courses.length) {
      setExpandedCourseClasses([courses[0].classId]);
      courseExpansionInitialized.current = true;
    }
  }, [courses]);
  const sortedClasses = useMemo(() => byOrder(classes).sort((a, b) => {
    const gradeA = gradeById.get(a.gradeId), gradeB = gradeById.get(b.gradeId);
    const stageA = stages.find((item) => item.id === gradeA?.stageId), stageB = stages.find((item) => item.id === gradeB?.stageId);
    return (stageA?.sortOrder ?? 0) - (stageB?.sortOrder ?? 0) || (gradeA?.sortOrder ?? 0) - (gradeB?.sortOrder ?? 0) || a.sortOrder - b.sortOrder;
  }), [classes, gradeById, stages]);
  const sortedTeachers = useMemo(() => byOrder(teachers).filter((item) => teacherName(item).toLowerCase().includes(query.toLowerCase())), [teachers, query]);
  const run = async (operation: () => Promise<void>) => {
    setBusy(true); setError('');
    try { await operation(); await reload(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
    finally { setBusy(false); }
  };
  const openTeacher = (teacher: Teacher | 'new') => {
    setTeacherEditor(teacher);
    setTeacherForm(teacher === 'new' ? { name: '', shortName: '', displayQualifier: '', subjectIds: [] } : {
      name: teacher.name, shortName: teacher.shortName, displayQualifier: teacher.displayQualifier, subjectIds: teacher.subjectIds ?? [],
    });
  };
  const saveTeacher = () => void run(async () => {
    const name = teacherForm.name.trim(); if (!name) throw new Error('请填写教师姓名');
    await schoolRepository.saveTeachers([{ id: teacherEditor === 'new' ? newId() : teacherEditor!.id,
      name, shortName: teacherForm.shortName.trim(), displayQualifier: teacherForm.displayQualifier.trim(),
      sortOrder: teacherEditor === 'new' ? teachers.length : teacherEditor!.sortOrder, subjectIds: teacherForm.subjectIds }]);
    setTeacherEditor(null);
  });
  const openGroup = (group: TeacherGroup | 'new') => { setGroupEditor(group); setGroupForm(group === 'new' ? { name: '', description: '' } : { name: group.name, description: group.description }); };
  const saveGroup = () => void run(async () => {
    if (!activeTermId) return;
    const name = groupForm.name.trim(); if (!name) throw new Error('请填写分组名称');
    await schoolRepository.saveTeacherGroup({ id: groupEditor === 'new' ? newId() : groupEditor!.id,
      termId: activeTermId, name, description: groupForm.description.trim(), sortOrder: groupEditor === 'new' ? groups.length : groupEditor!.sortOrder });
    setGroupEditor(null);
  });
  const openMembers = (group: TeacherGroup) => { setMemberEditor(group); setMemberIds(members.filter((item) => item.groupId === group.id).map((item) => item.teacherId)); };
  const saveCell = async (classId: string, subjectId: string, drafts: AssignmentDraft[]): Promise<boolean> => {
    if (!activeTermId) return false;
    setBusy(true); setError('');
    const next: TeacherAssignment[] = drafts.map((item, index) => ({
      id: item.id ?? newId(), termId: activeTermId, teacherId: item.teacherId,
      classId, subjectId, weekMode: item.weekMode, lessonCount: item.lessonCount,
      sortOrder: index, combinedLessonGroupId: item.combinedLessonGroupId ?? null,
    }));
    try {
      const message = assignmentError(next, classes, subjects, subjectRequirements, assignments.filter((item) => item.classId !== classId || item.subjectId !== subjectId));
      if (message) throw new Error(message);
      await schoolRepository.replaceTeacherAssignments({ termId: activeTermId, classId, subjectId, assignments: next });
      await reload();
      return true;
    } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); return false; }
    finally { setBusy(false); }
  };
  const saveBatch = () => void run(async () => {
    if (!activeTermId) return;
    const next: TeacherAssignment[] = batchClassIds.map((classId, index) => ({
      id: newId(), termId: activeTermId, teacherId: batchTeacherId, classId, subjectId: batchSubjectId,
      weekMode: batchMode, lessonCount: batchCount, sortOrder: assignments.length + index, combinedLessonGroupId: null,
    }));
    if (!next.length) throw new Error('请选择至少一个班级');
    const message = assignmentError(next, classes, subjects, subjectRequirements, assignments);
    if (message) throw new Error(message);
    await schoolRepository.addTeacherAssignments(activeTermId, next); setBatchOpen(false);
  });
  const assignCourse = (teacherId: string, course: (typeof courses)[number]) => void run(async () => {
    if (!activeTermId) return;
    const item: TeacherAssignment = { id: newId(), termId: activeTermId, teacherId, classId: course.classId, subjectId: course.subjectId,
      weekMode: course.weekMode, lessonCount: course.remainingLessons, sortOrder: assignments.length, combinedLessonGroupId: null };
    const message = assignmentError([item], classes, subjects, subjectRequirements, assignments); if (message) throw new Error(message);
    await schoolRepository.addTeacherAssignments(activeTermId, [item]);
  });
  const transfer = (assignment: TeacherAssignment, teacherId: string | null) => void run(async () => {
    if (!activeTermId) return;
    const all = assignments.filter((item) => item.classId === assignment.classId && item.subjectId === assignment.subjectId);
    await schoolRepository.replaceTeacherAssignments({ termId: activeTermId, classId: assignment.classId, subjectId: assignment.subjectId,
      assignments: all.map((item) => item.id === assignment.id ? { ...item, teacherId } : item) });
  });
  const downloadWorkbook = async (kind: 'teachers' | 'assignments') => {
    try {
      const bytes = kind === 'teachers' ? await buildTeachersWorkbook(teachers, groups, members, subjects)
        : await buildAssignmentsWorkbook(stages, grades, classes, subjects, teachers, assignments);
      const blob = new Blob([new Uint8Array(bytes)], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a'); anchor.href = url; anchor.download = kind === 'teachers' ? '教师导入模板.xlsx' : '任课分配导入模板.xlsx'; anchor.click();
      URL.revokeObjectURL(url);
    } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); }
  };
  const importTeachers = (file: File) => void run(async () => {
    if (!activeTermId) return;
    const rows = await parseTeachersWorkbook(new Uint8Array(await file.arrayBuffer()));
    for (const row of rows) {
      for (const name of row.subjects) if (!subjects.some((item) => item.name === name)) throw new Error(`科目「${name}」不存在`);
    }
    if (!window.confirm(`即将导入或更新 ${rows.length} 名教师，是否继续？`)) return;
    const nextGroups: TeacherGroup[] = [];
    for (const row of rows) for (const name of row.groups) {
      if (!groups.some((item) => item.name === name) && !nextGroups.some((item) => item.name === name)) {
        nextGroups.push({ id: newId(), termId: activeTermId, name, description: '', sortOrder: groups.length + nextGroups.length });
      }
    }
    const imported = rows.map((row, index) => {
      const current = teachers.find((item) => item.name === row.name);
      return { id: current?.id ?? newId(), name: row.name, shortName: row.shortName || current?.shortName || '', displayQualifier: current?.displayQualifier ?? '', sortOrder: current?.sortOrder ?? teachers.length + index,
        subjectIds: row.subjects.length ? [...new Set([...(current?.subjectIds ?? []).filter((id) => !subjects.some((subject) => subject.id === id)), ...row.subjects.map((name) => subjects.find((item) => item.name === name)!.id)])] : current?.subjectIds ?? [] };
    });
    await schoolRepository.saveTeachers(imported);
    for (const group of nextGroups) await schoolRepository.saveTeacherGroup(group);
    for (const group of [...groups, ...nextGroups]) {
      const toAdd = rows.filter((row) => row.groups.includes(group.name)).map((row) => imported.find((teacher) => teacher.name === row.name)!.id);
      if (!toAdd.length) continue;
      await schoolRepository.replaceTeacherGroupMembers(group.id, [...new Set([...members.filter((item) => item.groupId === group.id).map((item) => item.teacherId), ...toAdd])].map((teacherId) => ({ groupId: group.id, teacherId })));
    }
  });
  const importAssignments = (file: File) => void run(async () => {
    if (!activeTermId) return;
    const rows = await parseAssignmentsWorkbook(new Uint8Array(await file.arrayBuffer()));
    const next: TeacherAssignment[] = rows.map((row, index) => {
      const matchingGrades = grades.filter((item) => item.name === row.grade && stages.some((stage) => stage.id === item.stageId && stage.name === row.stage));
      const matchingClasses = classes.filter((item) => item.name === row.schoolClass && matchingGrades.some((grade) => grade.id === item.gradeId));
      const matchingSubjects = subjects.filter((item) => item.name === row.subject);
      const matchingTeachers = teachers.filter((item) => item.name === row.teacher);
      if (matchingClasses.length !== 1 || matchingSubjects.length !== 1 || matchingTeachers.length !== 1) throw new Error(`第 ${index + 2} 行班级、科目或教师不存在或有重名`);
      return { id: newId(), termId: activeTermId, classId: matchingClasses[0].id, subjectId: matchingSubjects[0].id, teacherId: matchingTeachers[0].id,
        weekMode: row.weekMode, lessonCount: row.lessonCount, sortOrder: assignments.length + index, combinedLessonGroupId: null };
    });
    const message = assignmentError(next, classes, subjects, subjectRequirements, assignments); if (message) throw new Error(message);
    if (!window.confirm(`校验通过，即将追加 ${next.length} 项任课，是否继续？`)) return;
    await schoolRepository.addTeacherAssignments(activeTermId, next);
  });
  if (!activeTermId) return <div className="rounded-card bg-surface p-8 text-ink-secondary">请先创建学期，再设置教师任课。</div>;
  if (presetOwner) return <TeacherPresetPage key={`${presetOwner.kind}:${presetOwner.id ?? ''}`} termId={activeTermId} owner={presetOwner} teachers={teachers} groups={groups} members={members}
    onBack={() => { window.location.hash = '#/teachers'; setPresetOwner(null); }} />;

  const menuItem = 'block w-full cursor-pointer rounded-md px-3 py-2 text-left text-[13px] text-ink outline-none hover:bg-selection focus:bg-selection';
  return <div className="space-y-4">
    <div className="flex flex-wrap items-center gap-3 rounded-card bg-surface px-5 py-3">
      <strong className="mr-auto text-[16px] text-ink">教师任课</strong>
      {view === 'teacher' && <label className="relative w-48"><Search className="absolute left-2.5 top-2.5 h-4 w-4 text-ink-secondary"/><Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="按姓名查找教师" className="pl-8" /></label>}
      <Button variant="ghost" className="text-primary" onClick={() => view === 'group' ? openGroup('new') : setBatchOpen(true)}><Plus className="mr-1.5 h-4 w-4"/>{view === 'group' ? '新增分组' : '添加任课'}</Button>
      <DropdownMenu.Root><DropdownMenu.Trigger asChild><Button variant="ghost">更多 <ChevronDown className="ml-1 h-4 w-4"/></Button></DropdownMenu.Trigger>
        <DropdownMenu.Portal><DropdownMenu.Content align="end" className="z-50 min-w-44 rounded-control border border-border bg-surface p-1 shadow-md">
          <DropdownMenu.Item className={menuItem} onSelect={() => openPreset('teacher')}>教师预排</DropdownMenu.Item>
          <DropdownMenu.Item className={menuItem} onSelect={() => openTeacher('new')}>新增教师</DropdownMenu.Item>
          <DropdownMenu.Item className={menuItem} onSelect={() => openGroup('new')}>新增分组</DropdownMenu.Item>
          <DropdownMenu.Item className={menuItem} onSelect={() => teacherFileRef.current?.click()}>Excel 导入教师</DropdownMenu.Item>
          <DropdownMenu.Item className={menuItem} onSelect={() => assignmentFileRef.current?.click()}>Excel 导入任课分配</DropdownMenu.Item>
          <DropdownMenu.Item className={menuItem} onSelect={() => void downloadWorkbook('teachers')}>下载教师模板</DropdownMenu.Item>
          <DropdownMenu.Item className={menuItem} onSelect={() => void downloadWorkbook('assignments')}>下载任课模板</DropdownMenu.Item>
        </DropdownMenu.Content></DropdownMenu.Portal></DropdownMenu.Root>
      <div className="flex rounded-control bg-selection p-0.5" role="tablist" aria-label="教师任课视图">{(['class','teacher','group'] as const).map((item) =>
        <button key={item} role="tab" aria-selected={view === item} onClick={() => setView(item)} className={`rounded-md px-5 py-1.5 text-[13px] ${view === item ? 'bg-surface text-ink shadow-sm' : 'text-ink-secondary'}`}>{{class:'班级',teacher:'教师',group:'分组'}[item]}</button>)}</div>
    </div>
    <input ref={teacherFileRef} type="file" accept=".xlsx" className="hidden" onChange={(event) => { const file = event.target.files?.[0]; if (file) importTeachers(file); event.target.value = ''; }}/>
    <input ref={assignmentFileRef} type="file" accept=".xlsx" className="hidden" onChange={(event) => { const file = event.target.files?.[0]; if (file) importAssignments(file); event.target.value = ''; }}/>
    {error && <div role="alert" className="rounded-control bg-destructive-surface px-4 py-2 text-[13px] text-destructive">{error}</div>}
    {view === 'teacher' && (() => { const combined = new Map<string, TeacherAssignment[]>(); for (const row of assignments) if (row.combinedLessonGroupId) combined.set(row.combinedLessonGroupId, [...(combined.get(row.combinedLessonGroupId) ?? []), row]); const groupRows = [...combined.values()]; return groupRows.length ? <div className="flex flex-wrap items-center gap-3 rounded-control border border-primary bg-selection px-4 py-2 text-[12px] text-ink"><Users className="h-4 w-4 text-primary"/><span>已设置 {groupRows.length} 组合班课 · 涉及 {groupRows.reduce((sum, rows) => sum + new Set(rows.map((item) => item.classId)).size, 0)} 个班级、{new Set(groupRows.map((rows) => rows[0].teacherId)).size} 位教师</span><Button variant="outline" size="sm" onClick={() => { setCombineTeacherId(null); setCombineTab('all'); setCombineOpen(true); }}>查看全部</Button></div> : null; })()}
    {view === 'class' && <div className="overflow-x-auto rounded-card bg-surface"><table className="w-full table-fixed border-collapse text-[12px]" style={{ minWidth: 184 + sortedClasses.length * 190 }}><thead><tr className="h-10 border-b border-border text-ink-secondary"><th className="sticky left-0 z-10 w-[184px] min-w-[184px] bg-surface px-[18px] text-left">科目</th>{sortedClasses.map((item) => <th key={item.id} className="min-w-[190px] px-2 text-center text-primary">{className(item)}</th>)}</tr></thead><tbody>{byOrder(subjects).map((subject) => {
      const modes = (['odd', 'even'] as const).filter((mode) => sortedClasses.some((item) => valuesForClass(subjectRequirements, subject.id, item)[mode] > 0));
      return <tr key={subject.id} className="h-12 border-b border-table-divider last:border-0"><th className="sticky left-0 bg-surface px-[18px] text-left font-semibold text-ink"><span className="flex min-w-0 items-center gap-1.5"><span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: getSubjectColor(subject.id, resolvedDark).foreground }}/><span className="min-w-0 truncate">{subject.name}</span>{modes.map((mode) => <span key={mode} className="shrink-0 rounded bg-selection px-1 text-[10px] font-normal text-ink-secondary">{modeLabels[mode]}</span>)}</span></th>{sortedClasses.map((schoolClass) => {
        const required = valuesForClass(subjectRequirements, subject.id, schoolClass);
        const rows = assignments.filter((item) => item.classId === schoolClass.id && item.subjectId === subject.id && item.teacherId);
        return <td key={schoolClass.id} className="h-12 min-w-[190px] p-0 text-center"><AssignmentCellPopover className={className(schoolClass)} subjectName={subject.name} assignments={rows} teachers={teachers} required={required} error={error} disabled={!Object.values(required).some((value) => value > 0)} onSave={(drafts) => saveCell(schoolClass.id, subject.id, drafts)}/></td>;
      })}</tr>;
    })}</tbody></table>{!subjects.length && <div className="p-8 text-center text-ink-secondary">请先设置科目节数。</div>}</div>}
    {view === 'teacher' && <div className="grid gap-4 xl:grid-cols-[minmax(0,1fr)_280px]"><div className="overflow-hidden rounded-card bg-surface"><div className="grid grid-cols-[minmax(100px,1fr)_minmax(180px,2fr)_90px_48px] border-b border-border px-5 py-3 text-[12px] text-ink-secondary"><span>教师</span><span>任课安排</span><span>周均节数</span><span>操作</span></div>{sortedTeachers.map((teacher) => {
      const rows = assignments.filter((item) => item.teacherId === teacher.id); const expanded = expandedTeachers.includes(teacher.id);
      return <div key={teacher.id} onDragOver={(event) => event.preventDefault()} onDrop={(event) => { event.preventDefault(); const payload = event.dataTransfer.getData('text/plain'); if (payload.startsWith('assignment:')) { const assignment = assignments.find((item) => item.id === payload.slice(11)); if (assignment) transfer(assignment, teacher.id); } else if (payload.startsWith('course:')) { const course = courses[Number(payload.slice(7))]; if (course) assignCourse(teacher.id, course); } }} className="border-b border-table-divider last:border-0"><div className="grid grid-cols-[minmax(100px,1fr)_minmax(180px,2fr)_90px_48px] items-center gap-2 px-5 py-3 text-[13px] text-ink"><strong>{teacherName(teacher)}</strong><button className="text-left" onClick={() => setExpandedTeachers(expanded ? expandedTeachers.filter((id) => id !== teacher.id) : [...expandedTeachers, teacher.id])}>{rows.length} 项任课 · {[...new Set(rows.map((item) => subjectById.get(item.subjectId)?.name))].filter(Boolean).join('、') || '暂无任课'} {new Set(rows.map((item) => item.combinedLessonGroupId).filter(Boolean)).size > 0 && `· ${new Set(rows.map((item) => item.combinedLessonGroupId).filter(Boolean)).size} 组合班`} <ChevronDown className={`inline h-3.5 w-3.5 ${expanded ? 'rotate-180' : ''}`}/></button><span>{teacherWeeklyLoad(rows)} 节</span><DropdownMenu.Root><DropdownMenu.Trigger asChild><button aria-label={`${teacher.name}操作`}><MoreHorizontal className="h-5 w-5"/></button></DropdownMenu.Trigger><DropdownMenu.Portal><DropdownMenu.Content className="z-50 min-w-36 rounded-control border border-border bg-surface p-1 shadow-md"><DropdownMenu.Item className={menuItem} onSelect={() => openTeacher(teacher)}>编辑教师</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => { setBatchTeacherId(teacher.id); setBatchOpen(true); }}>添加任课</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => { setCombineTeacherId(teacher.id); setCombineTab('create'); setCombineOpen(true); }}>合班</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => openPreset('teacher', teacher.id)}>教师预排</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => void run(async () => { if (window.confirm(`删除${teacher.name}？全部学期的任课将退回未分配。`)) await schoolRepository.deleteTeacher(teacher.id); })}>删除教师</DropdownMenu.Item></DropdownMenu.Content></DropdownMenu.Portal></DropdownMenu.Root></div>{expanded && <div className="space-y-1 bg-table-header px-5 py-2">{rows.map((item) => <div key={item.id} draggable onDragStart={(event) => event.dataTransfer.setData('text/plain', `assignment:${item.id}`)} className="flex flex-wrap items-center gap-2 rounded-control bg-surface px-3 py-2 text-[12px] text-ink"><span>{classById.get(item.classId) ? className(classById.get(item.classId)!) : '未知班级'} · {subjectById.get(item.subjectId)?.name ?? '未知科目'} · {modeLabels[item.weekMode]} {item.lessonCount} 节{item.combinedLessonGroupId ? ' · 合班' : ''}</span><select aria-label="调整任课教师" className="ml-auto rounded-control border border-border bg-surface px-2 py-1" value={item.teacherId ?? ''} onChange={(event) => transfer(item, event.target.value || null)}><option value="">未分配</option>{teachers.map((person) => <option key={person.id} value={person.id}>{person.name}</option>)}</select><button className="text-destructive" onClick={() => void run(async () => { if (window.confirm('删除这项任课？')) await schoolRepository.deleteTeacherAssignments(activeTermId, [item.id]); })}>删除</button></div>)}</div>}</div>;
    })}{!sortedTeachers.length && <div className="p-8 text-center text-ink-secondary">还没有教师。点击“更多 → 新增教师”开始。</div>}</div><aside className="rounded-card bg-surface p-4"><div className="mb-3 flex items-center justify-between text-[13px] font-semibold text-ink"><span>未分配课程</span><span className="text-ink-secondary">{courses.length} 门</span></div><div className="max-h-[70vh] divide-y divide-table-divider overflow-y-auto">{sortedClasses.map((schoolClass) => { const own = courses.filter((course) => course.classId === schoolClass.id); if (!own.length) return null; const expanded = expandedCourseClasses.includes(schoolClass.id); return <div key={schoolClass.id}><button className="flex w-full items-center justify-between py-2 text-left text-[12px] text-ink" onClick={() => setExpandedCourseClasses(expanded ? expandedCourseClasses.filter((id) => id !== schoolClass.id) : [...expandedCourseClasses, schoolClass.id])}><strong>{className(schoolClass)}</strong><span className="flex items-center gap-1 text-ink-secondary">{own.length} 门 <ChevronDown className={`h-3.5 w-3.5 ${expanded ? 'rotate-180' : ''}`}/></span></button>{expanded && <div className="space-y-1 pb-2">{own.map((course) => <div key={`${course.subjectId}-${course.weekMode}`} draggable onDragStart={(event) => event.dataTransfer.setData('text/plain', `course:${courses.indexOf(course)}`)} className="rounded-control px-2 py-1.5 text-[12px] text-ink-secondary hover:bg-selection"><div className="flex items-center justify-between gap-2"><span>{subjectById.get(course.subjectId)?.name}（{modeLabels[course.weekMode]}） · {course.remainingLessons} 节</span><span className="cursor-grab text-ink-secondary">⠿</span></div><select aria-label="分配未分配课程" className="mt-1 w-full rounded-control border border-border bg-surface px-2 py-1" value="" onChange={(event) => event.target.value && assignCourse(event.target.value, course)}><option value="">分配给教师…</option>{teachers.map((teacher) => <option key={teacher.id} value={teacher.id}>{teacher.name}</option>)}</select></div>)}</div>}</div>; })}{!courses.length && <div className="py-12 text-center text-[12px] text-ink-secondary">课程已全部分配</div>}</div></aside></div>}
    {view === 'group' && <div className="overflow-hidden rounded-card bg-surface"><div className="grid grid-cols-[minmax(160px,2fr)_minmax(150px,1fr)_auto] border-b border-border px-5 py-3 text-[12px] text-ink-secondary"><span>分组信息</span><span>分组成员</span><span>操作</span></div>{byOrder(groups).map((group) => { const groupMembers = members.filter((item) => item.groupId === group.id); return <div key={group.id} className="grid grid-cols-[minmax(160px,2fr)_minmax(150px,1fr)_auto] items-start gap-4 border-b border-table-divider px-5 py-5 text-[13px]"><div><strong className="text-ink">{group.name}</strong><p className="mt-1 text-ink-secondary">{group.description || '暂无说明'}</p></div><div><strong>{groupMembers.length} 名教师</strong><p className="mt-1 text-ink-secondary">{groupMembers.map((item) => teacherById.get(item.teacherId)?.name).filter(Boolean).join('、') || '尚未添加成员'}</p></div><div className="flex flex-wrap items-center gap-3"><button onClick={() => openMembers(group)} className="inline-flex items-center gap-1 text-primary"><Users className="h-4 w-4"/>维护成员</button><button onClick={() => openPreset('group', group.id)} className="text-primary">分组预排</button><DropdownMenu.Root><DropdownMenu.Trigger asChild><button aria-label={`${group.name}操作`}><MoreHorizontal className="h-5 w-5"/></button></DropdownMenu.Trigger><DropdownMenu.Portal><DropdownMenu.Content className="z-50 rounded-control border border-border bg-surface p-1 shadow-md"><DropdownMenu.Item className={menuItem} onSelect={() => openGroup(group)}>编辑分组</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => void run(async () => { if (window.confirm(`删除「${group.name}」及成员和预排规则？`)) await schoolRepository.deleteTeacherGroup(group.id); })}>删除分组</DropdownMenu.Item></DropdownMenu.Content></DropdownMenu.Portal></DropdownMenu.Root></div></div>; })}{!groups.length && <div className="p-8 text-center text-ink-secondary">还没有教师分组。点击“新增分组”开始。</div>}</div>}

    <Dialog open={teacherEditor !== null} onOpenChange={(open) => !open && setTeacherEditor(null)}><DialogContent><DialogHeader><DialogTitle>{teacherEditor === 'new' ? '新增教师' : '编辑教师'}</DialogTitle><DialogDescription>教师在不同学期共用；科目标签用于筛选。</DialogDescription></DialogHeader><div className="space-y-3 text-[13px] text-ink"><label className="block">姓名<Input value={teacherForm.name} onChange={(event) => setTeacherForm({ ...teacherForm, name: event.target.value })} autoFocus /></label><label className="block">简称<Input value={teacherForm.shortName} onChange={(event) => setTeacherForm({ ...teacherForm, shortName: event.target.value })}/></label><label className="block">区分说明<Input value={teacherForm.displayQualifier} onChange={(event) => setTeacherForm({ ...teacherForm, displayQualifier: event.target.value })}/></label><div>任教学科<div className="mt-2 flex max-h-40 flex-wrap gap-2 overflow-auto">{subjects.map((subject) => <label key={subject.id} className="rounded-control border border-border px-2 py-1"><input type="checkbox" checked={teacherForm.subjectIds.includes(subject.id)} onChange={(event) => setTeacherForm({ ...teacherForm, subjectIds: event.target.checked ? [...teacherForm.subjectIds, subject.id] : teacherForm.subjectIds.filter((id) => id !== subject.id) })}/> {subject.name}</label>)}</div></div></div><DialogFooter><Button variant="outline" onClick={() => setTeacherEditor(null)}>取消</Button><Button onClick={saveTeacher} disabled={busy}>保存教师</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={groupEditor !== null} onOpenChange={(open) => !open && setGroupEditor(null)}><DialogContent><DialogHeader><DialogTitle>{groupEditor === 'new' ? '新增分组' : '编辑分组'}</DialogTitle></DialogHeader><div className="space-y-3 text-[13px]"><label className="block">分组名称<Input value={groupForm.name} onChange={(event) => setGroupForm({ ...groupForm, name: event.target.value })} autoFocus/></label><label className="block">说明<Input value={groupForm.description} onChange={(event) => setGroupForm({ ...groupForm, description: event.target.value })}/></label></div><DialogFooter><Button variant="outline" onClick={() => setGroupEditor(null)}>取消</Button><Button onClick={saveGroup} disabled={busy}>保存分组</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={memberEditor !== null} onOpenChange={(open) => !open && setMemberEditor(null)}><DialogContent><DialogHeader><DialogTitle>维护「{memberEditor?.name}」成员</DialogTitle><DialogDescription>一位教师可以加入多个分组。</DialogDescription></DialogHeader><div className="max-h-[50vh] space-y-1 overflow-y-auto">{byOrder(teachers).map((teacher) => <label key={teacher.id} className="flex items-center gap-2 rounded-control px-2 py-2 text-[13px] hover:bg-selection"><input type="checkbox" checked={memberIds.includes(teacher.id)} onChange={(event) => setMemberIds(event.target.checked ? [...memberIds, teacher.id] : memberIds.filter((id) => id !== teacher.id))}/>{teacher.name}</label>)}</div><DialogFooter><Button variant="outline" onClick={() => setMemberEditor(null)}>取消</Button><Button disabled={busy} onClick={() => void run(async () => { if (!memberEditor) return; await schoolRepository.replaceTeacherGroupMembers(memberEditor.id, memberIds.map((teacherId) => ({ groupId: memberEditor.id, teacherId }))); setMemberEditor(null); })}>保存成员</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={batchOpen} onOpenChange={setBatchOpen}><DialogContent className="max-w-2xl"><DialogHeader><DialogTitle>添加任课</DialogTitle><DialogDescription>选择教师、科目和班级；每个班级将按相同节数添加一项任课。</DialogDescription></DialogHeader><div className="grid gap-3 text-[13px] sm:grid-cols-2"><label>教师<select aria-label="教师" className="mt-1 h-9 w-full rounded-control border border-border bg-surface px-2" value={batchTeacherId} onChange={(event) => setBatchTeacherId(event.target.value)}><option value="">选择教师</option>{teachers.map((teacher) => <option key={teacher.id} value={teacher.id}>{teacher.name}</option>)}</select></label><label>科目<select aria-label="科目" className="mt-1 h-9 w-full rounded-control border border-border bg-surface px-2" value={batchSubjectId} onChange={(event) => { setBatchSubjectId(event.target.value); setBatchClassIds([]); }}><option value="">选择科目</option>{subjects.map((subject) => <option key={subject.id} value={subject.id}>{subject.name}</option>)}</select></label><label>周期<Select value={batchMode} onValueChange={(value) => setBatchMode(value as WeekMode)}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent>{(['weekly','odd','even'] as const).map((mode) => <SelectItem key={mode} value={mode}>{modeLabels[mode]}</SelectItem>)}</SelectContent></Select></label><label>每班节数<Input type="number" min={1} value={batchCount} onChange={(event) => setBatchCount(Number(event.target.value))}/></label></div><div className="max-h-52 overflow-y-auto rounded-control border border-border p-2 text-[13px]">{sortedClasses.filter((schoolClass) => subjectRequirements.some((item) => item.subjectId === batchSubjectId && item.gradeId === schoolClass.gradeId && (item.classId === null || item.classId === schoolClass.id) && item.weekMode === batchMode && item.lessonCount > 0)).map((schoolClass) => <label key={schoolClass.id} className="flex gap-2 rounded-md px-2 py-1.5 hover:bg-selection"><input type="checkbox" checked={batchClassIds.includes(schoolClass.id)} onChange={(event) => setBatchClassIds(event.target.checked ? [...batchClassIds, schoolClass.id] : batchClassIds.filter((id) => id !== schoolClass.id))}/>{className(schoolClass)}</label>)}</div><DialogFooter><Button variant="outline" onClick={() => setBatchOpen(false)}>取消</Button><Button disabled={busy} onClick={saveBatch}>添加任课</Button></DialogFooter></DialogContent></Dialog>
    <CombinedLessonWorkspace open={combineOpen} onOpenChange={setCombineOpen} initialTeacherId={combineTeacherId} initialTab={combineTab} error={error} assignments={assignments} teachers={teachers} classes={classes} subjects={subjects}
      onCombine={async (ids) => { try { await schoolRepository.setCombinedTeacherAssignments(activeTermId, ids, newId()); await reload(); return true; } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); return false; } }}
      onSplit={async (groupId) => { try { const ids = assignments.filter((item) => item.combinedLessonGroupId === groupId).map((item) => item.id); await schoolRepository.setCombinedTeacherAssignments(activeTermId, ids, null); await reload(); return true; } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); return false; } }}/>
  </div>;
};
