import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useStickyToolbar } from '@/hooks/useStickyToolbar';
import { ChevronDown, ChevronRight, MoreHorizontal, Plus, Search, Users } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { EmptyState } from '@/components/ui/empty-state';
import { Input } from '@/components/ui/input';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { SearchableSelect } from '@/components/ui/searchable-select';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import * as DropdownMenu from '@radix-ui/react-dropdown-menu';
import type { Teacher, TeacherAssignment, TeacherGroup, TeacherGroupMember, ClassGroup, WeekMode } from '@/domain/models';
import { createId } from '@/domain/id';
import { schoolRepository } from '@/repository/schoolRepository';
import { useAppStore } from '@/store/useAppStore';
import { assignmentError, remainingCourses, teacherWeeklyLoad } from './teacherLogic';
import { TeacherPresetPage } from './TeacherPresetPage';
import { buildAssignmentsWorkbook, buildTeachersWorkbook, parseAssignmentsWorkbook, parseTeachersWorkbook } from './teacherWorkbook';
import { AssignmentCellPopover, AssignmentEditorDialog, type AssignmentDraft } from './AssignmentCellPopover';
import { CombinedLessonWorkspace } from './CombinedLessonWorkspace';
import { valuesForClass } from '@/features/subjects/subjectLogic';
import { getSubjectColor } from '@/styles/subjectColors';

const modeLabels: Record<WeekMode, string> = { weekly: '每周', odd: '单周', even: '双周' };
const byOrder = <T extends { sortOrder: number }>(rows: T[]) => [...rows].sort((a, b) => a.sortOrder - b.sortOrder);
const newId = createId;
const presetOwnerFromRoute = (): { kind: 'teacher' | 'group'; id?: string } | null => {
  const [, section, page, kind, id] = window.location.hash.split('/');
  return section === 'teachers' && page === 'preset' && (kind === 'teacher' || kind === 'group')
    ? { kind, id: id ? decodeURIComponent(id) : undefined } : null;
};

export const TeachersPage: React.FC = () => {
  const { activeTermId, classes, grades, stages, subjects, subjectRequirements, teachers: storedTeachers, refreshTermData, resolvedDark, setSelectedSection } = useAppStore();
  const toolbarRef = useStickyToolbar<HTMLDivElement>();
  const [view, setView] = useState<'class' | 'teacher' | 'group'>('class');
  const [teachers, setTeachers] = useState<Teacher[]>(storedTeachers);
  const [assignments, setAssignments] = useState<TeacherAssignment[]>([]);
  const [groups, setGroups] = useState<TeacherGroup[]>([]);
  const [members, setMembers] = useState<TeacherGroupMember[]>([]);
  const [loading, setLoading] = useState(true);
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
  const classMatrixRef = useRef<HTMLDivElement | null>(null);
  const [classScrollLeft, setClassScrollLeft] = useState(false);
  const [scopeStageId, setScopeStageId] = useState<string>('all');
  const [scopeGradeId, setScopeGradeId] = useState<string>('all');
  const [visibleClassIds, setVisibleClassIds] = useState<string[] | null>(null);
  const [dragOverTeacherId, setDragOverTeacherId] = useState<string | null>(null);
  const [dragOverUnassigned, setDragOverUnassigned] = useState(false);
  const [courseEditor, setCourseEditor] = useState<{ classId: string; subjectId: string; initialDrafts: AssignmentDraft[] } | null>(null);
  const [activeDrag, setActiveDrag] = useState<
    | { kind: 'course'; courseIndex: number; label: string; x: number; y: number }
    | { kind: 'assignment'; assignmentId: string; label: string; x: number; y: number }
    | null
  >(null);
  const pendingDragRef = useRef<
    | { kind: 'course'; courseIndex: number; label: string; startX: number; startY: number }
    | { kind: 'assignment'; assignmentId: string; label: string; startX: number; startY: number }
    | null
  >(null);
  const suppressCourseClickRef = useRef(false);
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
  useEffect(() => {
    let current = true;
    setLoading(true);
    void reload()
      .catch((cause) => { if (current) setError(String(cause)); })
      .finally(() => { if (current) setLoading(false); });
    return () => { current = false; };
  }, [reload]);
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
  const assignmentsByTeacher = useMemo(() => {
    const grouped = new Map<string, TeacherAssignment[]>();
    for (const assignment of assignments) {
      if (!assignment.teacherId) continue;
      const rows = grouped.get(assignment.teacherId);
      if (rows) rows.push(assignment);
      else grouped.set(assignment.teacherId, [assignment]);
    }
    return grouped;
  }, [assignments]);
  const assignmentsByClassSubject = useMemo(() => {
    const grouped = new Map<string, TeacherAssignment[]>();
    for (const assignment of assignments) {
      const key = `${assignment.classId}:${assignment.subjectId}`;
      const rows = grouped.get(key);
      if (rows) rows.push(assignment);
      else grouped.set(key, [assignment]);
    }
    return grouped;
  }, [assignments]);
  const className = (schoolClass: ClassGroup) => {
    const gradeName = gradeById.get(schoolClass.gradeId)?.name ?? '';
    return gradeName && !schoolClass.name.startsWith(gradeName) ? `${gradeName}${schoolClass.name}` : schoolClass.name;
  };
  const teacherName = (teacher: Teacher) => `${teacher.name}${teacher.displayQualifier ? ` · ${teacher.displayQualifier}` : ''}`;
  const courses = useMemo(() => remainingCourses(classes, subjects, subjectRequirements, assignments), [classes, subjects, subjectRequirements, assignments]);
  const coursesByClass = useMemo(() => {
    const grouped = new Map<string, typeof courses>();
    for (const course of courses) {
      const rows = grouped.get(course.classId);
      if (rows) rows.push(course);
      else grouped.set(course.classId, [course]);
    }
    return grouped;
  }, [courses]);
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
  const shownClasses = useMemo(() => sortedClasses.filter((item) => {
    const grade = gradeById.get(item.gradeId);
    if (scopeStageId !== 'all' && grade?.stageId !== scopeStageId) return false;
    if (scopeGradeId !== 'all' && item.gradeId !== scopeGradeId) return false;
    if (visibleClassIds !== null && !visibleClassIds.includes(item.id)) return false;
    return true;
  }), [sortedClasses, gradeById, scopeStageId, scopeGradeId, visibleClassIds]);
  const sortedTeachers = useMemo(() => byOrder(teachers).filter((item) => teacherName(item).toLowerCase().includes(query.toLowerCase())), [teachers, query]);
  const teacherOptions = useMemo(() => byOrder(teachers).map((item) => ({
    value: item.id,
    label: teacherName(item),
    keywords: `${item.shortName} ${item.displayQualifier}`,
  })), [teachers]);
  const subjectOptions = useMemo(() => byOrder(subjects).map((item) => ({
    value: item.id,
    label: item.name,
    keywords: item.shortName,
  })), [subjects]);
  const updateClassScrollShadow = useCallback(() => {
    const el = classMatrixRef.current;
    if (!el) return;
    const scrolled = el.scrollLeft > 1;
    setClassScrollLeft((prev) => (prev === scrolled ? prev : scrolled));
  }, []);
  useEffect(() => {
    if (view !== 'class') return;
    updateClassScrollShadow();
    const el = classMatrixRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(updateClassScrollShadow);
    observer.observe(el);
    return () => observer.disconnect();
  }, [view, shownClasses.length, subjects.length, updateClassScrollShadow]);
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
  const assignCourse = useCallback((teacherId: string, course: (typeof courses)[number]) => void run(async () => {
    if (!activeTermId) return;
    const item: TeacherAssignment = { id: newId(), termId: activeTermId, teacherId, classId: course.classId, subjectId: course.subjectId,
      weekMode: course.weekMode, lessonCount: course.remainingLessons, sortOrder: assignments.length, combinedLessonGroupId: null };
    const message = assignmentError([item], classes, subjects, subjectRequirements, assignments); if (message) throw new Error(message);
    await schoolRepository.addTeacherAssignments(activeTermId, [item]);
  }), [activeTermId, classes, subjects, subjectRequirements, assignments]);
  const transfer = useCallback((assignment: TeacherAssignment, teacherId: string | null) => void run(async () => {
    if (!activeTermId) return;
    const all = assignments.filter((item) => item.classId === assignment.classId && item.subjectId === assignment.subjectId);
    await schoolRepository.replaceTeacherAssignments({ termId: activeTermId, classId: assignment.classId, subjectId: assignment.subjectId,
      assignments: all.map((item) => item.id === assignment.id ? { ...item, teacherId } : item) });
  }), [activeTermId, assignments]);
  const openCourseAssignmentEditor = (classId: string, subjectId: string, prefill?: { weekMode: WeekMode; lessonCount: number }) => {
    const existing = assignments
      .filter((item) => item.classId === classId && item.subjectId === subjectId && item.teacherId)
      .map<AssignmentDraft>((item) => ({
        id: item.id,
        teacherId: item.teacherId ?? '',
        weekMode: item.weekMode,
        lessonCount: item.lessonCount,
        combinedLessonGroupId: item.combinedLessonGroupId,
      }));
    const initialDrafts = prefill
      ? [...existing, { teacherId: '', weekMode: prefill.weekMode, lessonCount: prefill.lessonCount }]
      : existing;
    setError('');
    setCourseEditor({ classId, subjectId, initialDrafts });
  };
  useEffect(() => {
    if (view !== 'teacher') return;
    const hitTest = (x: number, y: number) => {
      const el = document.elementFromPoint(x, y);
      const teacherEl = el?.closest<HTMLElement>('[data-teacher-drop-id]');
      if (teacherEl?.dataset.teacherDropId) return { teacherId: teacherEl.dataset.teacherDropId, unassigned: false };
      if (el?.closest('[data-unassigned-drop]')) return { teacherId: null, unassigned: true };
      return { teacherId: null, unassigned: false };
    };
    const onPointerMove = (event: PointerEvent) => {
      const pending = pendingDragRef.current;
      if (!pending) return;
      if (!suppressCourseClickRef.current) {
        if (Math.hypot(event.clientX - pending.startX, event.clientY - pending.startY) < 6) return;
        suppressCourseClickRef.current = true;
      }
      const nextDrag = pending.kind === 'course'
        ? { kind: 'course' as const, courseIndex: pending.courseIndex, label: pending.label, x: event.clientX, y: event.clientY }
        : { kind: 'assignment' as const, assignmentId: pending.assignmentId, label: pending.label, x: event.clientX, y: event.clientY };
      setActiveDrag(nextDrag);
      const hit = hitTest(event.clientX, event.clientY);
      setDragOverTeacherId(hit.teacherId);
      setDragOverUnassigned(pending.kind === 'assignment' && hit.unassigned);
    };
    const onPointerUp = (event: PointerEvent) => {
      const pending = pendingDragRef.current;
      if (!pending) return;
      pendingDragRef.current = null;
      const didDrag = suppressCourseClickRef.current;
      setActiveDrag(null);
      setDragOverTeacherId(null);
      setDragOverUnassigned(false);
      if (didDrag) {
        window.setTimeout(() => { suppressCourseClickRef.current = false; }, 0);
        const hit = hitTest(event.clientX, event.clientY);
        if (hit.teacherId) {
          if (pending.kind === 'course') {
            const course = courses[pending.courseIndex];
            if (course) assignCourse(hit.teacherId, course);
          } else {
            const assignment = assignments.find((item) => item.id === pending.assignmentId);
            if (assignment && assignment.teacherId !== hit.teacherId) transfer(assignment, hit.teacherId);
          }
        } else if (hit.unassigned && pending.kind === 'assignment' && activeTermId) {
          void run(async () => { await schoolRepository.deleteTeacherAssignments(activeTermId, [pending.assignmentId]); });
        }
      }
    };
    window.addEventListener('pointermove', onPointerMove);
    window.addEventListener('pointerup', onPointerUp);
    window.addEventListener('pointercancel', onPointerUp);
    return () => {
      window.removeEventListener('pointermove', onPointerMove);
      window.removeEventListener('pointerup', onPointerUp);
      window.removeEventListener('pointercancel', onPointerUp);
    };
  }, [view, courses, assignments, activeTermId, assignCourse, transfer]);
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
  if (!activeTermId) return <div className="rounded-card bg-surface"><EmptyState variant="terms" title="还没有创建学期" description="先到「学期与日历」建好本学期，再来安排教师任课吧。" action={<Button variant="outline" size="sm" onClick={() => setSelectedSection('terms')}>前往学期与日历</Button>} /></div>;
  if (presetOwner) return <TeacherPresetPage key={`${presetOwner.kind}:${presetOwner.id ?? ''}`} termId={activeTermId} owner={presetOwner} teachers={teachers} groups={groups} members={members}
    onBack={() => { window.location.hash = '#/teachers'; setPresetOwner(null); }} />;

  const currentScopeStage = stages.find((item) => item.id === scopeStageId);
  const currentScopeGrade = grades.find((item) => item.id === scopeGradeId);
  const stageClassTotal = sortedClasses.filter((item) => gradeById.get(item.gradeId)?.stageId === scopeStageId).length;
  const gradeClassTotal = sortedClasses.filter((item) => item.gradeId === scopeGradeId).length;
  const scopeFilterLabel = scopeStageId === 'all'
    ? `全校 (${sortedClasses.length})`
    : scopeGradeId === 'all'
      ? `${currentScopeStage?.name ?? '学段'} (${stageClassTotal})`
      : visibleClassIds === null || shownClasses.length === gradeClassTotal
        ? `${currentScopeStage?.name ?? ''} · ${currentScopeGrade?.name ?? '年级'} (${gradeClassTotal})`
        : `${currentScopeGrade?.name ?? '年级'} · ${shownClasses.length}/${gradeClassTotal} 班`;
  const menuItem = 'block w-full cursor-pointer rounded-md px-3 py-2 text-left text-[13px] text-ink outline-none hover:bg-selection focus:bg-selection';
  const leftStickyShadow = `after:pointer-events-none after:absolute after:inset-y-0 after:left-full after:w-2.5 after:bg-gradient-to-r after:from-slate-900/[0.07] after:to-transparent after:transition-opacity after:duration-150 ${classScrollLeft ? 'after:opacity-100' : 'after:opacity-0'}`;
  return <div className="flex h-[calc(100dvh-88px)] min-h-[420px] flex-col gap-4">
    <div
      ref={toolbarRef}
      className="sticky-glass-toolbar sticky top-0 z-30 flex shrink-0 flex-wrap items-center gap-3 rounded-card bg-surface px-5 py-3 shadow-sm"
    >
      {/* <strong className="mr-auto text-[16px] text-ink">教师任课</strong> */}
      <Tabs value={view} onValueChange={(next) => setView(next as 'class' | 'teacher' | 'group')}>
        <TabsList aria-label="教师任课视图">
          <TabsTrigger value="class">班级</TabsTrigger>
          <TabsTrigger value="teacher">教师</TabsTrigger>
          <TabsTrigger value="group">分组</TabsTrigger>
        </TabsList>
      </Tabs>
      {view === 'class' && <Popover>
        <PopoverTrigger asChild>
          <button
            type="button"
            aria-label="筛选学段、年级与班级"
            className="inline-flex h-8 items-center gap-1.5 rounded-control border border-border bg-surface px-2.5 text-[12px] font-medium text-ink transition-colors hover:border-control-border hover:bg-table-header focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <span className="text-ink-secondary">范围</span>
            <span className="whitespace-nowrap">{scopeFilterLabel}</span>
            <ChevronDown aria-hidden="true" className="h-3.5 w-3.5 text-ink-secondary" />
          </button>
        </PopoverTrigger>
        <PopoverContent align="start" className="max-h-[70vh] w-64 overflow-y-auto p-2">
          <p className="mb-1.5 px-2.5 py-1 text-[11px] font-semibold text-ink-secondary">学段、年级与班级</p>
          <button
            type="button"
            className={`flex w-full items-center justify-between rounded-[9px] px-2.5 py-1.5 text-left text-[12.5px] transition-colors ${scopeStageId === 'all' ? 'bg-selection font-semibold text-primary' : 'text-ink hover:bg-table-header'}`}
            onClick={() => { setScopeStageId('all'); setScopeGradeId('all'); setVisibleClassIds(null); }}
          >
            <span>全校</span>
            <span className="text-[11.5px] text-ink-secondary tabular-nums">{sortedClasses.length}</span>
          </button>
          {byOrder(stages).map((stage) => {
            const stageGrades = byOrder(grades.filter((grade) => grade.stageId === stage.id));
            const stageCount = sortedClasses.filter((item) => gradeById.get(item.gradeId)?.stageId === stage.id).length;
            const stageSelected = scopeStageId === stage.id;
            return <div key={stage.id} className="mt-0.5">
              <button
                type="button"
                className={`flex w-full items-center gap-1.5 rounded-[9px] px-2.5 py-1.5 text-left text-[12.5px] transition-colors ${stageSelected && scopeGradeId === 'all' ? 'bg-selection font-semibold text-primary' : stageSelected ? 'font-semibold text-ink hover:bg-table-header' : 'text-ink hover:bg-table-header'}`}
                onClick={() => { setScopeStageId(stage.id); setScopeGradeId('all'); setVisibleClassIds(null); }}
              >
                {stageSelected ? <ChevronDown className="h-3.5 w-3.5 shrink-0" /> : <ChevronRight className="h-3.5 w-3.5 shrink-0" />}
                <span className="flex-1 truncate">{stage.name}</span>
                <span className="text-[11.5px] text-ink-secondary tabular-nums">{stageCount}</span>
              </button>
              {stageSelected && stageGrades.length > 0 && <div className="ml-5 mt-0.5 space-y-0.5 border-l border-border pl-2">
                {stageGrades.map((grade) => {
                  const gradeClasses = sortedClasses.filter((item) => item.gradeId === grade.id);
                  const gradeSelected = scopeGradeId === grade.id;
                  return <div key={grade.id}>
                    <button
                      type="button"
                      className={`flex w-full items-center gap-1.5 rounded-[7px] px-2 py-1 text-left text-[12px] transition-colors ${gradeSelected ? 'bg-selection font-semibold text-primary' : 'text-ink-secondary hover:bg-table-header hover:text-ink'}`}
                      onClick={() => { setScopeStageId(stage.id); setScopeGradeId(grade.id); setVisibleClassIds(null); }}
                    >
                      {gradeSelected ? <ChevronDown className="h-3 w-3 shrink-0" /> : <ChevronRight className="h-3 w-3 shrink-0" />}
                      <span className="flex-1 truncate">{grade.name}</span>
                      <span className="text-[11px] text-ink-secondary tabular-nums">{gradeClasses.length}</span>
                    </button>
                    {gradeSelected && gradeClasses.length > 0 && <div className="ml-4 mt-0.5 space-y-0.5 border-l border-border pl-2">
                      {gradeClasses.map((schoolClass) => <label key={schoolClass.id} className="flex cursor-pointer items-center gap-2 rounded-[7px] px-2 py-1 text-[12px] text-ink-secondary hover:bg-table-header hover:text-ink">
                        <Checkbox
                          checked={visibleClassIds === null || visibleClassIds.includes(schoolClass.id)}
                          onCheckedChange={() => setVisibleClassIds((ids) => {
                            const current = ids ?? gradeClasses.map((item) => item.id);
                            return current.includes(schoolClass.id) ? current.filter((id) => id !== schoolClass.id) : [...current, schoolClass.id];
                          })}
                        />
                        <span className="truncate">{schoolClass.name}</span>
                      </label>)}
                    </div>}
                  </div>;
                })}
              </div>}
            </div>;
          })}
        </PopoverContent>
      </Popover>}
      <div className="mr-auto" />
      {view === 'teacher' && <label className="relative w-48"><Search className="absolute left-2.5 top-2.5 h-4 w-4 text-ink-secondary"/><Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="按姓名查找教师" className="pl-8" /></label>}
      <Button variant="ghost" className="text-primary" onClick={() => { if (view === 'group') { openGroup('new'); } else { setBatchTeacherId(''); setBatchSubjectId(''); setBatchClassIds([]); setBatchMode('weekly'); setBatchCount(1); setBatchOpen(true); } }}><Plus className="mr-1.5 h-4 w-4"/>{view === 'group' ? '新增分组' : '添加任课'}</Button>
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
    </div>
    <input ref={teacherFileRef} type="file" accept=".xlsx" className="hidden" onChange={(event) => { const file = event.target.files?.[0]; if (file) importTeachers(file); event.target.value = ''; }}/>
    <input ref={assignmentFileRef} type="file" accept=".xlsx" className="hidden" onChange={(event) => { const file = event.target.files?.[0]; if (file) importAssignments(file); event.target.value = ''; }}/>
    {error && <div role="alert" className="shrink-0 rounded-control bg-destructive-surface px-4 py-2 text-[13px] text-destructive">{error}</div>}
    {view === 'teacher' && (() => { const combined = new Map<string, TeacherAssignment[]>(); for (const row of assignments) if (row.combinedLessonGroupId) combined.set(row.combinedLessonGroupId, [...(combined.get(row.combinedLessonGroupId) ?? []), row]); const groupRows = [...combined.values()]; return groupRows.length ? <div className="flex shrink-0 flex-wrap items-center gap-3 rounded-control border border-primary bg-selection px-4 py-2 text-[12px] text-ink"><Users className="h-4 w-4 text-primary"/><span>已设置 {groupRows.length} 组合班课 · 涉及 {groupRows.reduce((sum, rows) => sum + new Set(rows.map((item) => item.classId)).size, 0)} 个班级、{new Set(groupRows.map((rows) => rows[0].teacherId)).size} 位教师</span><Button variant="outline" size="sm" onClick={() => { setCombineTeacherId(null); setCombineTab('all'); setCombineOpen(true); }}>查看全部</Button></div> : null; })()}
    {loading && <div className="flex min-h-0 flex-1 items-center justify-center rounded-card bg-surface" role="status" aria-live="polite"><div className="flex items-center gap-3 text-[13px] text-ink-secondary"><span aria-hidden="true" className="h-4 w-4 animate-spin rounded-full border-2 border-border border-t-primary motion-reduce:animate-none" />正在加载教师任课数据…</div></div>}
    {!loading && view === 'class' && <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-card bg-surface">{!subjects.length ? <EmptyState variant="assignments" title="还没有可分配的科目" description="先在「科目节数」中添加科目并设置节数，再回来安排任课教师。" className="flex-1" /> : !shownClasses.length ? <EmptyState variant="assignments" title="当前范围没有匹配的班级" description="换个学段、年级或勾选其他班级试试看。" className="flex-1" /> : <div className="min-h-0 flex-1 overflow-auto" ref={classMatrixRef} onScroll={updateClassScrollShadow}><table className="w-full table-fixed border-separate border-spacing-0 text-[13px]" style={{ minWidth: 160 + shownClasses.length * 190 }}><thead className="sticky top-0 z-20 bg-surface"><tr className="text-ink-secondary"><th className={`sticky left-0 top-0 z-30 w-[160px] min-w-[160px] border-b border-border bg-surface px-4 py-4 text-left text-[12px] font-semibold ${leftStickyShadow}`}>科目</th>{shownClasses.map((item) => { const gradeName = gradeById.get(item.gradeId)?.name; return <th key={item.id} className="min-w-[190px] border-b border-border bg-surface px-2 py-4 text-center text-[12px] font-semibold text-primary"><div className="inline-flex max-w-full items-center justify-center gap-1.5">{gradeName && <span className="shrink-0 rounded bg-selection px-1.5 py-0.5 text-[10.5px] font-medium text-ink-secondary">{gradeName}</span>}<span className="truncate" title={item.name}>{item.name}</span></div></th>; })}</tr></thead><tbody>{byOrder(subjects).map((subject) => {
      const modes = (['odd', 'even'] as const).filter((mode) => shownClasses.some((item) => valuesForClass(subjectRequirements, subject.id, item)[mode] > 0));
      return <tr key={subject.id} className="group h-[46px] hover:bg-table-header"><th className={`sticky left-0 z-10 w-[160px] min-w-[160px] border-b border-table-divider bg-surface px-4 text-left font-normal group-hover:bg-table-header ${leftStickyShadow}`}><div className="flex items-center gap-2"><span aria-hidden="true" className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: getSubjectColor(subject.id, resolvedDark).foreground }}/><span className="min-w-0 flex-1 truncate font-semibold text-ink" title={subject.name}>{subject.name}</span>{modes.map((mode) => <span key={mode} className="shrink-0 rounded bg-selection px-1 text-[10px] font-normal text-ink-secondary">{modeLabels[mode]}</span>)}</div></th>{shownClasses.map((schoolClass) => {
        const required = valuesForClass(subjectRequirements, subject.id, schoolClass);
        const rows = (assignmentsByClassSubject.get(`${schoolClass.id}:${subject.id}`) ?? []).filter((item) => item.teacherId);
        return <td key={schoolClass.id} className="h-[46px] min-w-[190px] border-b border-table-divider p-0 text-center"><AssignmentCellPopover className={className(schoolClass)} subjectName={subject.name} assignments={rows} teachers={teachers} required={required} error={error} disabled={!Object.values(required).some((value) => value > 0)} onSave={(drafts) => saveCell(schoolClass.id, subject.id, drafts)}/></td>;
      })}</tr>;
    })}</tbody></table></div>}</div>}
    {!loading && view === 'teacher' && <div className={`grid min-h-0 flex-1 gap-4 xl:grid-cols-[minmax(0,1fr)_300px] ${activeDrag ? 'select-none' : ''}`}><div className="min-h-0 overflow-y-auto rounded-card bg-surface"><div className="sticky top-0 z-10 grid grid-cols-[minmax(120px,1fr)_minmax(240px,2.2fr)_90px_48px] border-b border-border bg-surface px-5 py-3 text-[12px] text-ink-secondary"><span>教师</span><span>任课安排</span><span>周均节数</span><span>操作</span></div>{sortedTeachers.map((teacher) => {
      const rows = assignmentsByTeacher.get(teacher.id) ?? [];
      const expanded = expandedTeachers.includes(teacher.id);
      const combinedCount = new Set(rows.map((item) => item.combinedLessonGroupId).filter(Boolean)).size;
      const isDragOver = dragOverTeacherId === teacher.id;
      return <div key={teacher.id}
        data-teacher-drop-id={teacher.id}
        className={`border-b border-table-divider transition-colors last:border-0 ${isDragOver ? 'bg-selection' : ''}`}>
        <div className="grid grid-cols-[minmax(120px,1fr)_minmax(240px,2.2fr)_90px_48px] items-start gap-2 px-5 py-3.5 text-[13px] text-ink">
          <strong className="pt-0.5 font-semibold text-ink">{teacherName(teacher)}</strong>
          <div className="min-w-0">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                {rows.length > 0 ? <>
                  <div className="font-semibold text-ink">{rows.length} 项任课</div>
                  <div className="mt-0.5 truncate text-[12px] text-ink-secondary">{[...new Set(rows.map((item) => subjectById.get(item.subjectId)?.name))].filter(Boolean).join('、')}{combinedCount > 0 ? ` · ${combinedCount} 组合班` : ''}</div>
                </> : <div className="pt-0.5 text-ink-secondary">暂无任课</div>}
              </div>
              {rows.length > 0 && <button type="button" onClick={() => setExpandedTeachers(expanded ? expandedTeachers.filter((id) => id !== teacher.id) : [...expandedTeachers, teacher.id])} className="inline-flex shrink-0 items-center gap-1 rounded-md px-1.5 py-0.5 text-[12px] text-ink-secondary transition-colors hover:bg-table-header hover:text-ink">
                <span>{expanded ? '收起' : '展开'}</span>
                <ChevronDown className={`h-3.5 w-3.5 transition-transform ${expanded ? 'rotate-180' : ''}`} />
              </button>}
            </div>
            {expanded && rows.length > 0 && <div className="mt-2.5 space-y-1 border-t border-table-divider pt-2.5">{rows.map((item) => {
              const subjectLabel = subjectById.get(item.subjectId)?.name ?? '未知科目';
              const classLabel = classById.get(item.classId) ? className(classById.get(item.classId)!) : '未知班级';
              const itemText = `${subjectLabel} · ${classLabel} · ${item.lessonCount} 节${item.weekMode !== 'weekly' ? `（${modeLabels[item.weekMode]}）` : ''}${item.combinedLessonGroupId ? ' · 合班' : ''}`;
              return <div key={item.id}
                role="button"
                tabIndex={0}
                onPointerDown={(event) => {
                  if (event.button !== 0 || (event.target instanceof Element && event.target.closest('button'))) return;
                  pendingDragRef.current = { kind: 'assignment', assignmentId: item.id, label: itemText, startX: event.clientX, startY: event.clientY };
                }}
                onClick={() => {
                  if (suppressCourseClickRef.current) return;
                  openCourseAssignmentEditor(item.classId, item.subjectId);
                }}
                onKeyDown={(event) => {
                  if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault();
                    openCourseAssignmentEditor(item.classId, item.subjectId);
                  }
                }}
                title="点击重新分配任课，或拖拽至其他教师/未分配课程列表"
                className="group/item flex cursor-grab items-center gap-2 rounded-md px-2 py-1 text-[12.5px] text-ink transition-colors hover:bg-selection active:cursor-grabbing">
                <span aria-hidden="true" className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: getSubjectColor(item.subjectId, resolvedDark).foreground }} />
                <span className="min-w-0 flex-1 truncate">{itemText}</span>
                <button type="button" aria-label="移出任课" onClick={(event) => { event.stopPropagation(); void run(async () => { await schoolRepository.deleteTeacherAssignments(activeTermId, [item.id]); }); }} className="rounded px-1 text-[11px] text-ink-secondary opacity-0 transition-opacity hover:text-destructive group-hover/item:opacity-100 focus:opacity-100">移出</button>
              </div>;
            })}</div>}
          </div>
          <span className="pt-0.5 tabular-nums font-medium text-ink">{teacherWeeklyLoad(rows)} 节</span>
          <div className="pt-0.5">
            <DropdownMenu.Root><DropdownMenu.Trigger asChild><button aria-label={`${teacher.name}操作`}><MoreHorizontal className="h-5 w-5"/></button></DropdownMenu.Trigger><DropdownMenu.Portal><DropdownMenu.Content className="z-50 min-w-36 rounded-control border border-border bg-surface p-1 shadow-md"><DropdownMenu.Item className={menuItem} onSelect={() => openTeacher(teacher)}>编辑教师</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => { setBatchTeacherId(teacher.id); setBatchSubjectId(''); setBatchClassIds([]); setBatchMode('weekly'); setBatchCount(1); setBatchOpen(true); }}>添加任课</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => { setCombineTeacherId(teacher.id); setCombineTab('create'); setCombineOpen(true); }}>合班</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => openPreset('teacher', teacher.id)}>教师预排</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => void run(async () => { if (window.confirm(`删除${teacher.name}？全部学期的任课将退回未分配。`)) await schoolRepository.deleteTeacher(teacher.id); })}>删除教师</DropdownMenu.Item></DropdownMenu.Content></DropdownMenu.Portal></DropdownMenu.Root>
          </div>
        </div>
      </div>;
    })}{!sortedTeachers.length && <EmptyState variant="teachers" title={query.trim() ? '没有找到匹配的教师' : '还没有教师名单'} description={query.trim() ? '换个姓名关键词试试，或清空搜索查看全部教师。' : '先添加几位任课教师，就能拖拽或点选排课啦。'} action={!query.trim() ? <Button variant="outline" size="sm" onClick={() => openTeacher('new')}><Plus className="h-4 w-4" />新增教师</Button> : undefined} />}</div>
    <aside
      data-unassigned-drop="true"
      className={`flex min-h-0 flex-col rounded-card border bg-surface p-4 transition-colors ${dragOverUnassigned ? 'border-primary bg-selection' : 'border-transparent'}`}
    >
      <div className="mb-3 flex shrink-0 items-center justify-between">
        <span className="text-[14px] font-semibold text-ink">未分配课程</span>
        <span className="rounded-full bg-warning-surface px-2 py-0.5 text-[11.5px] font-medium text-warning tabular-nums">{courses.length} 门</span>
      </div>
      <div className="min-h-0 flex-1 divide-y divide-table-divider overflow-y-auto">{sortedClasses.map((schoolClass) => {
        const own = coursesByClass.get(schoolClass.id) ?? [];
        if (!own.length) return null;
        const expanded = expandedCourseClasses.includes(schoolClass.id);
        return <div key={schoolClass.id} className="py-1 first:pt-0">
          <button type="button" className="flex w-full items-center justify-between py-2 text-left text-[13px] text-ink" onClick={() => setExpandedCourseClasses(expanded ? expandedCourseClasses.filter((id) => id !== schoolClass.id) : [...expandedCourseClasses, schoolClass.id])}>
            <strong>{className(schoolClass)}</strong>
            <span className="flex items-center gap-1 text-[12px] text-ink-secondary">{own.length} 门 <ChevronDown className={`h-3.5 w-3.5 transition-transform ${expanded ? 'rotate-180' : ''}`} /></span>
          </button>
          {expanded && <div className="space-y-0.5 pb-2">{own.map((course) => {
            const label = `${subjectById.get(course.subjectId)?.name ?? ''}${course.weekMode !== 'weekly' ? `（${modeLabels[course.weekMode]}）` : ''} · ${course.remainingLessons} 节`;
            const courseIndex = courses.indexOf(course);
            return <button key={`${course.subjectId}-${course.weekMode}`} type="button"
              onPointerDown={(event) => {
                if (event.button !== 0) return;
                pendingDragRef.current = { kind: 'course', courseIndex, label: `${className(schoolClass)} · ${label}`, startX: event.clientX, startY: event.clientY };
              }}
              onClick={() => {
                if (suppressCourseClickRef.current) return;
                openCourseAssignmentEditor(course.classId, course.subjectId, { weekMode: course.weekMode, lessonCount: course.remainingLessons });
              }}
              title="点击分配任课教师，或拖拽至左侧教师行"
              className="flex w-full cursor-grab items-center justify-between gap-2 rounded-control px-2.5 py-2 text-left text-[12.5px] text-ink transition-colors hover:bg-selection active:cursor-grabbing">
              <span className="truncate">{label}</span>
              <span className="shrink-0 text-ink-secondary">⠿</span>
            </button>;
          })}</div>}
        </div>;
      })}{!courses.length && <div className="py-12 text-center text-[12px] text-ink-secondary">课程已全部分配</div>}</div>
    </aside></div>}
    {!loading && view === 'group' && <div className="min-h-0 flex-1 overflow-y-auto rounded-card bg-surface"><div className="sticky top-0 z-10 grid grid-cols-[minmax(160px,2fr)_minmax(150px,1fr)_auto] border-b border-border bg-surface px-5 py-3 text-[12px] text-ink-secondary"><span>分组信息</span><span>分组成员</span><span>操作</span></div>{byOrder(groups).map((group) => { const groupMembers = members.filter((item) => item.groupId === group.id); return <div key={group.id} className="grid grid-cols-[minmax(160px,2fr)_minmax(150px,1fr)_auto] items-start gap-4 border-b border-table-divider px-5 py-5 text-[13px]"><div><strong className="text-ink">{group.name}</strong><p className="mt-1 text-ink-secondary">{group.description || '暂无说明'}</p></div><div><strong>{groupMembers.length} 名教师</strong><p className="mt-1 text-ink-secondary">{groupMembers.map((item) => teacherById.get(item.teacherId)?.name).filter(Boolean).join('、') || '尚未添加成员'}</p></div><div className="flex flex-wrap items-center gap-3"><button onClick={() => openMembers(group)} className="inline-flex items-center gap-1 text-primary"><Users className="h-4 w-4"/>维护成员</button><button onClick={() => openPreset('group', group.id)} className="text-primary">分组预排</button><DropdownMenu.Root><DropdownMenu.Trigger asChild><button aria-label={`${group.name}操作`}><MoreHorizontal className="h-5 w-5"/></button></DropdownMenu.Trigger><DropdownMenu.Portal><DropdownMenu.Content className="z-50 rounded-control border border-border bg-surface p-1 shadow-md"><DropdownMenu.Item className={menuItem} onSelect={() => openGroup(group)}>编辑分组</DropdownMenu.Item><DropdownMenu.Item className={menuItem} onSelect={() => void run(async () => { if (window.confirm(`删除「${group.name}」及成员和预排规则？`)) await schoolRepository.deleteTeacherGroup(group.id); })}>删除分组</DropdownMenu.Item></DropdownMenu.Content></DropdownMenu.Portal></DropdownMenu.Root></div></div>; })}{!groups.length && <EmptyState variant="groups" title="还没有教师分组" description="把同教研组或需要统一预排的教师放进分组，规则一次设置就能共用。" action={<Button variant="outline" size="sm" onClick={() => openGroup('new')}><Plus className="h-4 w-4" />新增分组</Button>} />}</div>}

    <Dialog open={teacherEditor !== null} onOpenChange={(open) => !open && setTeacherEditor(null)}><DialogContent><DialogHeader><DialogTitle>{teacherEditor === 'new' ? '新增教师' : '编辑教师'}</DialogTitle><DialogDescription>教师在不同学期共用；科目标签用于筛选。</DialogDescription></DialogHeader><div className="space-y-3 text-[13px] text-ink"><label className="block">姓名<Input value={teacherForm.name} onChange={(event) => setTeacherForm({ ...teacherForm, name: event.target.value })} autoFocus /></label><label className="block">简称<Input value={teacherForm.shortName} onChange={(event) => setTeacherForm({ ...teacherForm, shortName: event.target.value })}/></label><label className="block">区分说明<Input value={teacherForm.displayQualifier} onChange={(event) => setTeacherForm({ ...teacherForm, displayQualifier: event.target.value })}/></label><div>任教学科<div className="mt-2 flex max-h-40 flex-wrap gap-2 overflow-auto">{subjects.map((subject) => <label key={subject.id} className="inline-flex cursor-pointer items-center gap-2 rounded-control border border-border px-2.5 py-1.5 hover:bg-selection"><Checkbox checked={teacherForm.subjectIds.includes(subject.id)} onCheckedChange={(checked) => setTeacherForm({ ...teacherForm, subjectIds: checked === true ? [...teacherForm.subjectIds, subject.id] : teacherForm.subjectIds.filter((id) => id !== subject.id) })}/><span>{subject.name}</span></label>)}</div></div></div><DialogFooter><Button variant="outline" onClick={() => setTeacherEditor(null)}>取消</Button><Button onClick={saveTeacher} disabled={busy}>保存教师</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={groupEditor !== null} onOpenChange={(open) => !open && setGroupEditor(null)}><DialogContent><DialogHeader><DialogTitle>{groupEditor === 'new' ? '新增分组' : '编辑分组'}</DialogTitle></DialogHeader><div className="space-y-3 text-[13px]"><label className="block">分组名称<Input value={groupForm.name} onChange={(event) => setGroupForm({ ...groupForm, name: event.target.value })} autoFocus/></label><label className="block">说明<Input value={groupForm.description} onChange={(event) => setGroupForm({ ...groupForm, description: event.target.value })}/></label></div><DialogFooter><Button variant="outline" onClick={() => setGroupEditor(null)}>取消</Button><Button onClick={saveGroup} disabled={busy}>保存分组</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={memberEditor !== null} onOpenChange={(open) => !open && setMemberEditor(null)}><DialogContent><DialogHeader><DialogTitle>维护「{memberEditor?.name}」成员</DialogTitle><DialogDescription>一位教师可以加入多个分组。</DialogDescription></DialogHeader><div className="max-h-[50vh] space-y-1 overflow-y-auto">{byOrder(teachers).map((teacher) => <label key={teacher.id} className="flex cursor-pointer items-center gap-2.5 rounded-control px-2 py-2 text-[13px] hover:bg-selection"><Checkbox checked={memberIds.includes(teacher.id)} onCheckedChange={(checked) => setMemberIds(checked === true ? [...memberIds, teacher.id] : memberIds.filter((id) => id !== teacher.id))}/><span>{teacher.name}</span></label>)}</div><DialogFooter><Button variant="outline" onClick={() => setMemberEditor(null)}>取消</Button><Button disabled={busy} onClick={() => void run(async () => { if (!memberEditor) return; await schoolRepository.replaceTeacherGroupMembers(memberEditor.id, memberIds.map((teacherId) => ({ groupId: memberEditor.id, teacherId }))); setMemberEditor(null); })}>保存成员</Button></DialogFooter></DialogContent></Dialog>
    <Dialog open={batchOpen} onOpenChange={setBatchOpen}><DialogContent className="max-w-2xl"><DialogHeader><DialogTitle>添加任课</DialogTitle><DialogDescription>选择教师、科目和班级；每个班级将按相同节数添加一项任课。</DialogDescription></DialogHeader><div className="grid gap-3 text-[13px] sm:grid-cols-2"><div className="space-y-1"><span>教师</span><SearchableSelect ariaLabel="教师" value={batchTeacherId} onValueChange={setBatchTeacherId} options={teacherOptions} placeholder="选择教师" searchPlaceholder="搜索教师…" emptyText="未找到匹配教师" /></div><div className="space-y-1"><span>科目</span><SearchableSelect ariaLabel="科目" value={batchSubjectId} onValueChange={(value) => { setBatchSubjectId(value); setBatchClassIds([]); }} options={subjectOptions} placeholder="选择科目" searchPlaceholder="搜索科目…" emptyText="未找到匹配科目" /></div><div className="space-y-1"><span>周期</span><Select value={batchMode} onValueChange={(value) => { setBatchMode(value as WeekMode); setBatchClassIds([]); }}><SelectTrigger><SelectValue/></SelectTrigger><SelectContent>{(['weekly','odd','even'] as const).map((mode) => <SelectItem key={mode} value={mode}>{modeLabels[mode]}</SelectItem>)}</SelectContent></Select></div><label className="space-y-1"><span>每班节数</span><Input type="number" min={1} value={batchCount} onChange={(event) => setBatchCount(Number(event.target.value))}/></label></div>{(() => { if (!batchSubjectId) return null; const matchingClasses = sortedClasses.filter((schoolClass) => subjectRequirements.some((item) => item.subjectId === batchSubjectId && item.gradeId === schoolClass.gradeId && (item.classId === null || item.classId === schoolClass.id) && item.weekMode === batchMode && item.lessonCount > 0)); return <div className="space-y-1.5 text-[13px]"><div className="flex items-center justify-between"><span>选择班级</span>{matchingClasses.length > 0 && <span className="text-[12px] text-ink-secondary">已选 {batchClassIds.length} / {matchingClasses.length}</span>}</div>{matchingClasses.length > 0 ? <div className="max-h-52 overflow-y-auto rounded-control border border-border p-2">{matchingClasses.map((schoolClass) => <label key={schoolClass.id} className="flex cursor-pointer items-center gap-2.5 rounded-md px-2 py-1.5 hover:bg-selection"><Checkbox checked={batchClassIds.includes(schoolClass.id)} onCheckedChange={(checked) => setBatchClassIds(checked === true ? [...batchClassIds, schoolClass.id] : batchClassIds.filter((id) => id !== schoolClass.id))}/><span>{className(schoolClass)}</span></label>)}</div> : <div className="rounded-control border border-dashed border-border bg-table-header px-3 py-5 text-center text-[12px] text-ink-secondary">当前科目在「{modeLabels[batchMode]}」下暂无已配置节数的班级</div>}</div>; })()}<DialogFooter><Button variant="outline" onClick={() => setBatchOpen(false)}>取消</Button><Button disabled={busy} onClick={saveBatch}>添加任课</Button></DialogFooter></DialogContent></Dialog>
    <CombinedLessonWorkspace open={combineOpen} onOpenChange={setCombineOpen} initialTeacherId={combineTeacherId} initialTab={combineTab} error={error} assignments={assignments} teachers={teachers} classes={classes} subjects={subjects}
      onCombine={async (ids) => { try { await schoolRepository.setCombinedTeacherAssignments(activeTermId, ids, newId()); await reload(); return true; } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); return false; } }}
      onSplit={async (groupId) => { try { const ids = assignments.filter((item) => item.combinedLessonGroupId === groupId).map((item) => item.id); await schoolRepository.setCombinedTeacherAssignments(activeTermId, ids, null); await reload(); return true; } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); return false; } }}/>
    {courseEditor && (() => {
      const targetClass = classById.get(courseEditor.classId);
      const targetSubject = subjectById.get(courseEditor.subjectId);
      if (!targetClass || !targetSubject) return null;
      return (
        <AssignmentEditorDialog
          open
          onOpenChange={(open) => { if (!open) setCourseEditor(null); }}
          className={className(targetClass)}
          subjectName={targetSubject.name}
          initialDrafts={courseEditor.initialDrafts}
          teachers={teachers}
          required={valuesForClass(subjectRequirements, targetSubject.id, targetClass)}
          error={error}
          onSave={(drafts) => saveCell(courseEditor.classId, courseEditor.subjectId, drafts)}
        />
      );
    })()}
    {activeDrag && createPortal(
      <div
        className="pointer-events-none fixed z-[120] rounded-control border border-primary bg-surface px-3 py-1.5 text-[12.5px] font-medium text-ink shadow-lg"
        style={{ left: activeDrag.x + 12, top: activeDrag.y + 12 }}
      >
        {activeDrag.label}
      </div>,
      document.body,
    )}
  </div>;
};
