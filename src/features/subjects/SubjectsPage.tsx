import { hasTouchInput, useSelectionPress } from '@/lib/pointerSelection';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useStickyToolbar } from '@/hooks/useStickyToolbar';
import { AlertTriangle, Check, ChevronDown, ChevronRight, ClipboardPaste, Copy, Download, Eraser, Info, MoreHorizontal, Pencil, Plus, RotateCcw, Save, Trash2, Upload, X } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { EmptyState } from '@/components/ui/empty-state';
import { Input } from '@/components/ui/input';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import type {
  ClassGroup, ScopeType, Subject, SubjectLessonConstraint, SubjectPairing,
  SubjectParallelLimit, SubjectPreset, SubjectRequirement, SubjectRoomAssignment,
} from '@/domain/models';
import { createId } from '@/domain/id';
import { useAppStore } from '@/store/useAppStore';
import {
  applyGradeInput, EMPTY_LESSONS, formatGradeCell, formatLessonValues,
  makeRequirementRows, requirementKey, summarizeGradeCapacity, valuesForClass,
  parseSubjectImportText,
  type LessonValues,
} from './subjectLogic';
import { buildSubjectWorkbook, parseSubjectWorkbook } from './subjectWorkbook';
import { buildSubjectDraftInputs, COMMON_SUBJECTS, firstSubjectCharacter } from './commonSubjects';
import { applyMatrixCells, copyMatrixText, matrixCellKey, pasteMatrixGrid, rectangleKeys } from './subjectMatrixActions';
import { resolveConstraintField, validateConstraintRanges, type ConstraintField } from './subjectAdvancedLogic';

function sortByOrder<T extends { sortOrder: number }>(items: T[]): T[] {
  return [...items].sort((a, b) => a.sortOrder - b.sortOrder);
}
const WEEKDAY_NAMES = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const PRESET_VALUES = ['auto', 'prefer', 'must', 'forbid'] as const;
const PRESET_LABELS: Record<SubjectPreset['value'], string> = {
  auto: '自动', prefer: '尽量排', must: '一定排', forbid: '不排',
};
const DAILY_CONSTRAINT_ROWS: Array<[ConstraintField, string, string]> = [
  ['minimumDailyLessons', '最少', '节'], ['maximumDailyLessons', '最多', '节'],
  ['maximumDailyConsecutivePairs', '最多连堂', '次'], ['minimumDailyConsecutivePairs', '最少连堂', '次'],
];
const SUBJECT_COLORS = ['#a1396d', '#9b521e', '#806314', '#4f7029', '#1f7457', '#117783', '#326cab', '#5c56ac', '#8253a3', '#9c477d'];
function subjectColor(id: string): string {
  let hash = 0x811c9dc5;
  for (const char of id) hash = Math.imul(hash ^ char.charCodeAt(0), 0x01000193) >>> 0;
  hash = Math.imul(hash ^ (hash >>> 15), 0x2545f491) >>> 0;
  hash = (hash ^ (hash >>> 13)) >>> 0;
  return SUBJECT_COLORS[hash % SUBJECT_COLORS.length];
}
function presetScopeKey(subjectId: string, scopeType: ScopeType, scopeId: string, stageId: string): string {
  return JSON.stringify([subjectId, scopeType, scopeId, stageId]);
}

interface GradeEditor {
  subjectId: string;
  gradeId: string;
}

function matrixMenuAt(key: string, x: number, y: number) {
  return {
    key,
    x: Math.min(x, window.innerWidth - 196),
    y: Math.min(y, window.innerHeight - 216),
  };
}

export const SubjectsPage: React.FC = () => {
  const toolbarRef = useStickyToolbar<HTMLDivElement>();
  const {
    activeTermId, terms, stages, grades, classes, subjects: savedSubjects,
    subjectRequirements, subjectPairings, subjectPresets, subjectLessonConstraints,
    subjectRoomAssignments, subjectParallelLimits, publicRooms, routinesByStage, freeSlotsByStage,
    saveSubjectChanges, loadFreeSlotsForStages, setSelectedSection, setSubjectDraftDirty, setNavigationGuard,
  } = useAppStore();
  const term = terms.find((item) => item.id === activeTermId);
  const alternating = term?.cycleMode === 'alternating';
  const [scopeStageId, setScopeStageId] = useState<string>('all');
  const [visibleGradeIds, setVisibleGradeIds] = useState<string[] | null>(null);
  const [subjectDrafts, setSubjectDrafts] = useState<Record<string, Subject>>({});
  const [deletedIds, setDeletedIds] = useState<string[]>([]);
  const [lessonDrafts, setLessonDrafts] = useState<Record<string, LessonValues>>({});
  const [editedCells, setEditedCells] = useState<string[]>([]);
  const [pairingDrafts, setPairingDrafts] = useState<Record<string, SubjectPairing[]>>({});
  const [presetDrafts, setPresetDrafts] = useState<Record<string, SubjectPreset[]>>({});
  const [constraintDrafts, setConstraintDrafts] = useState<Record<string, SubjectLessonConstraint[]>>({});
  const [roomDrafts, setRoomDrafts] = useState<Record<string, { assignment: SubjectRoomAssignment | null; limit: SubjectParallelLimit | null }>>({});
  const [presetSubjectId, setPresetSubjectId] = useState<string | null>(null);
  const [advancedTab, setAdvancedTab] = useState<'presets' | 'constraints' | 'rooms'>('presets');
  const [expandedPresetStages, setExpandedPresetStages] = useState<string[]>([]);
  const [expandedPresetGrades, setExpandedPresetGrades] = useState<string[]>([]);
  const advancedSnapshot = useRef<{
    presets: Record<string, SubjectPreset[]>;
    constraints: Record<string, SubjectLessonConstraint[]>;
    rooms: Record<string, { assignment: SubjectRoomAssignment | null; limit: SubjectParallelLimit | null }>;
  } | null>(null);
  const [presetMenu, setPresetMenu] = useState<{ x: number; y: number; weekday: number; periodTypeId: string; lessonIndex: number } | null>(null);
  const [advancedError, setAdvancedError] = useState('');
  const [advancedWarnings, setAdvancedWarnings] = useState<string[]>([]);
  const [presetScopeType, setPresetScopeType] = useState<ScopeType>('stage');
  const [presetStageId, setPresetStageId] = useState('');
  const [presetScopeId, setPresetScopeId] = useState('');
  const [subjectDialog, setSubjectDialog] = useState<Subject | 'new' | null>(null);
  const [subjectName, setSubjectName] = useState('');
  const [subjectShortName, setSubjectShortName] = useState('');
  const [subjectShortNameEdited, setSubjectShortNameEdited] = useState(false);
  const [selectedCommonSubjects, setSelectedCommonSubjects] = useState<string[]>([]);
  const [gradeEditor, setGradeEditor] = useState<GradeEditor | null>(null);
  const [selectedMatrixCells, setSelectedMatrixCells] = useState<string[]>([]);
  const [activeMatrixCell, setActiveMatrixCell] = useState<string | null>(null);
  const selectionAnchorCell = useRef<string | null>(null);
  const clipboardCache = useRef('');
  const matrixCellRefs = useRef(new Map<string, HTMLButtonElement>());
  const touchInput = hasTouchInput();
  const withSelectionPress = useSelectionPress();
  const matrixScrollRef = useRef<HTMLDivElement | null>(null);
  const [scrollShadow, setScrollShadow] = useState({ left: false, right: false });
  const dragPointer = useRef<{ x: number; y: number } | null>(null);
  const [dragSelecting, setDragSelecting] = useState(false);
  const [inlineEditor, setInlineEditor] = useState<{ key: string; value: string } | null>(null);
  const cancelInlineBlur = useRef(false);
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number; key: string } | null>(null);
  const [subjectMenu, setSubjectMenu] = useState<{ x: number; y: number; subjectId: string } | null>(null);
  const dragAnchor = useRef<{ row: number; column: number; pointerId: number } | null>(null);
  const dragged = useRef(false);
  const dragSelection = useRef<{ key: string; count: number } | null>(null);
  const [batchOpen, setBatchOpen] = useState(false);
  const [batchValue, setBatchValue] = useState('');
  const [importOpen, setImportOpen] = useState(false);
  const [importText, setImportText] = useState('');
  const [importErrors, setImportErrors] = useState<string[]>([]);
  const [importWorkbookValues, setImportWorkbookValues] = useState<Record<string, LessonValues> | null>(null);
  const [importFileName, setImportFileName] = useState('');
  const [includeExisting, setIncludeExisting] = useState(true);
  const [importBusy, setImportBusy] = useState(false);
  const [gradeInput, setGradeInput] = useState('');
  const [classInputs, setClassInputs] = useState<Record<string, string>>({});
  const [pairingClassId, setPairingClassId] = useState<string | null>(null);
  const [oddSubjectId, setOddSubjectId] = useState('');
  const [evenSubjectId, setEvenSubjectId] = useState('');
  const [deleteTarget, setDeleteTarget] = useState<Subject | null>(null);
  const [capacityWarnings, setCapacityWarnings] = useState<string[] | null>(null);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [helpOpen, setHelpOpen] = useState(true);

  useEffect(() => {
    setScopeStageId('all');
    setVisibleGradeIds(null);
    setSubjectDrafts({}); setDeletedIds([]); setLessonDrafts({});
    setEditedCells([]); setPairingDrafts({}); setPresetDrafts({}); setConstraintDrafts({}); setRoomDrafts({}); setMessage('');
  }, [activeTermId]);
  useEffect(() => {
    if (stages.length) void loadFreeSlotsForStages(stages.map((stage) => stage.id));
  }, [activeTermId, stages, loadFreeSlotsForStages]);

  const activeSubjects = useMemo(() => sortByOrder([
    ...savedSubjects.filter((item) => !deletedIds.includes(item.id)).map((item) => subjectDrafts[item.id] ?? item),
    ...Object.values(subjectDrafts).filter((item) => !savedSubjects.some((saved) => saved.id === item.id)),
  ]), [savedSubjects, subjectDrafts, deletedIds]);
  const scopeGrades = useMemo(() => {
    const stageOrder = new Map(stages.map((stage) => [stage.id, stage.sortOrder]));
    return grades
      .filter((item) => scopeStageId === 'all' || item.stageId === scopeStageId)
      .slice()
      .sort((a, b) => (stageOrder.get(a.stageId) ?? 0) - (stageOrder.get(b.stageId) ?? 0) || a.sortOrder - b.sortOrder);
  }, [grades, stages, scopeStageId]);
  const shownGrades = useMemo(() => scopeGrades.filter((item) =>
    visibleGradeIds === null || visibleGradeIds.includes(item.id)
  ), [scopeGrades, visibleGradeIds]);
  const classesForGrade = (gradeId: string) => sortByOrder(classes.filter((item) => item.gradeId === gradeId));
  const valueFor = (subjectId: string, schoolClass: ClassGroup) =>
    lessonDrafts[requirementKey(subjectId, schoolClass.id)] ?? valuesForClass(subjectRequirements, subjectId, schoolClass);
  const savedValues = useMemo(() => {
    const values: Record<string, LessonValues> = {};
    for (const subject of activeSubjects) for (const schoolClass of classes) {
      values[requirementKey(subject.id, schoolClass.id)] = valuesForClass(subjectRequirements, subject.id, schoolClass);
    }
    return values;
  }, [activeSubjects, classes, subjectRequirements]);
  const allValues = useMemo(() => {
    const values: Record<string, LessonValues> = {};
    for (const subject of activeSubjects) for (const schoolClass of classes) {
      const key = requirementKey(subject.id, schoolClass.id);
      values[key] = lessonDrafts[key] ?? savedValues[key] ?? EMPTY_LESSONS;
    }
    return values;
  }, [activeSubjects, classes, lessonDrafts, savedValues]);
  const gradeCapacities = useMemo(() => Object.fromEntries(shownGrades.map((grade) => [grade.id,
    summarizeGradeCapacity(grade, sortByOrder(classes.filter((item) => item.gradeId === grade.id)),
      activeSubjects.map((item) => item.id), allValues, routinesByStage[grade.stageId],
      Object.values(freeSlotsByStage).flat(), activeTermId ?? '')
  ])), [shownGrades, classes, activeSubjects, allValues, routinesByStage, freeSlotsByStage, activeTermId]);
  const hasChanges = Object.keys(subjectDrafts).length > 0 || deletedIds.length > 0 ||
    editedCells.length > 0 || Object.keys(pairingDrafts).length > 0 ||
    Object.keys(presetDrafts).length > 0 || Object.keys(constraintDrafts).length > 0 ||
    Object.keys(roomDrafts).length > 0;
  function advancedSummary(subjectId: string): string {
    const scopeRows = <T extends { subjectId: string; scopeType: ScopeType; scopeId: string; stageId: string }>(saved: T[], drafts: Record<string, T[]>) => {
      const replaced = new Set(Object.keys(drafts));
      return saved.filter((row) => row.subjectId === subjectId &&
        !replaced.has(presetScopeKey(subjectId, row.scopeType, row.scopeId, row.stageId)))
        .concat(Object.entries(drafts).filter(([key]) => key.startsWith(`["${subjectId}",`))
          .flatMap(([, rows]) => rows));
    };
    const presets = scopeRows(subjectPresets, presetDrafts).filter((row) => row.value !== 'auto').length;
    const constraints = scopeRows(subjectLessonConstraints, constraintDrafts).length;
    const roomKeys = Object.keys(roomDrafts).filter((key) => key.startsWith(`["${subjectId}",`));
    const assignments = subjectRoomAssignments.filter((row) => row.subjectId === subjectId &&
      !roomKeys.includes(presetScopeKey(subjectId, row.scopeType, row.scopeId, row.stageId))).length +
      roomKeys.filter((key) => roomDrafts[key].assignment !== null).length;
    const limits = subjectParallelLimits.filter((row) => row.subjectId === subjectId &&
      !roomKeys.includes(presetScopeKey(subjectId, row.scopeType, row.scopeId, row.stageId))).length +
      roomKeys.filter((key) => roomDrafts[key].limit !== null).length;
    return [presets ? `预设 ${presets}` : '', constraints ? `限制 ${constraints}` : '',
      assignments ? `场室 ${assignments}` : '', limits ? `并行 ${limits}` : ''].filter(Boolean).join(' · ');
  }

  useEffect(() => {
    setSubjectDraftDirty(hasChanges);
    return () => setSubjectDraftDirty(false);
  }, [hasChanges, setSubjectDraftDirty]);

  const subjectGuardRef = useRef({ hasChanges, save, discard });
  subjectGuardRef.current = { hasChanges, save, discard };
  useEffect(() => {
    setNavigationGuard({
      label: '科目节数',
      isDirty: () => subjectGuardRef.current.hasChanges,
      save: async () => await subjectGuardRef.current.save(),
      discard: () => subjectGuardRef.current.discard(),
    });
    return () => setNavigationGuard(null);
  }, [setNavigationGuard]);
  function openBatchEditor() {
    setBatchValue('');
    setMessage('');
    setBatchOpen(true);
  }

  useEffect(() => {
    if (!contextMenu) return;
    const closeOutside = (event: PointerEvent) => {
      if (!(event.target instanceof Element) || !event.target.closest('[data-subject-matrix-menu]')) setContextMenu(null);
    };
    const closeEscape = (event: KeyboardEvent) => { if (event.key === 'Escape') setContextMenu(null); };
    const closeOnScroll = () => setContextMenu(null);
    window.addEventListener('pointerdown', closeOutside);
    window.addEventListener('keydown', closeEscape);
    window.addEventListener('scroll', closeOnScroll, true);
    return () => {
      window.removeEventListener('pointerdown', closeOutside);
      window.removeEventListener('keydown', closeEscape);
      window.removeEventListener('scroll', closeOnScroll, true);
    };
  }, [contextMenu]);

  useEffect(() => {
    if (!subjectMenu) return;
    const closeOutside = (event: PointerEvent) => {
      if (!(event.target instanceof Element) || !event.target.closest('[data-subject-name-menu]')) setSubjectMenu(null);
    };
    const closeEscape = (event: KeyboardEvent) => { if (event.key === 'Escape') setSubjectMenu(null); };
    const closeOnScroll = () => setSubjectMenu(null);
    window.addEventListener('pointerdown', closeOutside);
    window.addEventListener('keydown', closeEscape);
    window.addEventListener('scroll', closeOnScroll, true);
    return () => {
      window.removeEventListener('pointerdown', closeOutside);
      window.removeEventListener('keydown', closeEscape);
      window.removeEventListener('scroll', closeOnScroll, true);
    };
  }, [subjectMenu]);
  useEffect(() => {
    if (!presetMenu) return;
    const close = (event: PointerEvent) => {
      if (!(event.target instanceof Element) || !event.target.closest('[data-preset-menu]')) setPresetMenu(null);
    };
    const escape = (event: KeyboardEvent) => { if (event.key === 'Escape') setPresetMenu(null); };
    window.addEventListener('pointerdown', close);
    window.addEventListener('keydown', escape);
    return () => { window.removeEventListener('pointerdown', close); window.removeEventListener('keydown', escape); };
  }, [presetMenu]);

  function updateScrollShadow() {
    const el = matrixScrollRef.current;
    if (!el) return;
    const left = el.scrollLeft > 1;
    const right = el.scrollLeft + el.clientWidth < el.scrollWidth - 1;
    setScrollShadow((prev) => (prev.left === left && prev.right === right ? prev : { left, right }));
  }

  useEffect(() => {
    updateScrollShadow();
    const el = matrixScrollRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(updateScrollShadow);
    observer.observe(el);
    return () => observer.disconnect();
  }, [shownGrades.length, activeSubjects.length]);

  useEffect(() => {
    setSelectedMatrixCells([]);
    setActiveMatrixCell(null);
    selectionAnchorCell.current = null;
    setInlineEditor(null);
  }, [scopeStageId, visibleGradeIds]);

  useEffect(() => {
    const updateSelection = (autoScroll: boolean) => {
      const pointer = dragPointer.current;
      const wrapper = matrixScrollRef.current;
      const anchor = dragAnchor.current;
      if (!pointer || !wrapper || !anchor) return;
      const rect = wrapper.getBoundingClientRect();
      if (autoScroll) {
        const edge = 36;
        if (pointer.x < rect.left + edge) wrapper.scrollLeft -= 12;
        else if (pointer.x > rect.right - edge) wrapper.scrollLeft += 12;
        if (pointer.y < rect.top + 56) wrapper.scrollTop -= 12;
        else if (pointer.y > rect.bottom - 96) wrapper.scrollTop += 12;
      }
      const x = Math.max(rect.left + 2, Math.min(rect.right - 2, pointer.x));
      const y = Math.max(rect.top + 2, Math.min(rect.bottom - 2, pointer.y));
      const element = document.elementFromPoint(x, y)?.closest<HTMLButtonElement>('[data-matrix-row]');
      if (!element) return;
      const row = Number(element.dataset.matrixRow), column = Number(element.dataset.matrixColumn);
      if (!Number.isInteger(row) || !Number.isInteger(column) || !activeSubjects[row] || !shownGrades[column]) return;
      if (row !== anchor.row || column !== anchor.column) dragged.current = true;
      const next = rectangleKeys(activeSubjects, shownGrades, anchor, { row, column });
      const key = matrixCellKey(activeSubjects[row].id, shownGrades[column].id);
      dragSelection.current = { key, count: next.length };
      setSelectedMatrixCells((current) =>
        current.length === next.length && current.every((key, index) => key === next[index]) ? current : next
      );
      setActiveMatrixCell(key);
    };
    const updatePointer = (event: PointerEvent) => {
      if (dragAnchor.current?.pointerId !== event.pointerId) return;
      dragPointer.current = { x: event.clientX, y: event.clientY };
      updateSelection(false);
    };
    const endDrag = (event: PointerEvent) => {
      if (dragAnchor.current?.pointerId !== event.pointerId) return;
      if (event.type === 'pointerup') {
        updatePointer(event);
        const selection = dragSelection.current;
        if (selection && selection.count > 1) {
          setContextMenu(matrixMenuAt(selection.key, event.clientX, event.clientY));
        }
      }
      dragAnchor.current = null;
      dragPointer.current = null;
      dragSelection.current = null;
      setDragSelecting(false);
    };
    window.addEventListener('pointermove', updatePointer);
    window.addEventListener('pointerup', endDrag);
    window.addEventListener('pointercancel', endDrag);
    const timer = dragSelecting ? window.setInterval(() => updateSelection(true), 30) : undefined;
    return () => {
      window.removeEventListener('pointermove', updatePointer);
      window.removeEventListener('pointerup', endDrag);
      window.removeEventListener('pointercancel', endDrag);
      window.clearInterval(timer);
    };
  }, [dragSelecting, activeSubjects, shownGrades]);

  function stageLessonChanges(nextValues: Record<string, LessonValues>, candidateKeys: string[]): string[] {
    const nextDrafts = { ...nextValues };
    const nextEdited = new Set(editedCells);
    const changed: string[] = [];
    for (const key of candidateKeys) {
      const nextVal = nextDrafts[key] ?? EMPTY_LESSONS;
      const baseVal = savedValues[key] ?? EMPTY_LESSONS;
      if (nextVal.weekly === baseVal.weekly && nextVal.odd === baseVal.odd && nextVal.even === baseVal.even) {
        delete nextDrafts[key];
        nextEdited.delete(key);
      } else {
        nextEdited.add(key);
        changed.push(key);
      }
    }
    setLessonDrafts(nextDrafts);
    setEditedCells([...nextEdited]);
    return changed;
  }
  function applyBatch(input: string) {
    const result = applyMatrixCells(selectedMatrixCells, input, classes, lessonDrafts, alternating);
    if (result.error) { setMessage(result.error); return false; }
    const changed = stageLessonChanges(result.values, result.changedKeys);
    setBatchOpen(false);
    setMessage(changed.length ? `已暂存 ${result.cellCount} 个格子的节数` : '');
    return true;
  }
  function pasteMatrix(text: string) {
    if (!selectedMatrixCells.length) return;
    const result = pasteMatrixGrid(text, selectionAnchorCell.current ?? selectedMatrixCells[0],
      selectedMatrixCells, activeSubjects, shownGrades, classes, lessonDrafts, alternating);
    if (result.error) { setMessage(result.error); return; }
    const changed = stageLessonChanges(result.values, result.changedKeys);
    if (changed.length) setMessage(`已粘贴 ${result.cellCount} 个格子`);
  }
  function copyMatrix() {
    const text = copyMatrixText(selectedMatrixCells, activeSubjects, shownGrades, classes, allValues);
    clipboardCache.current = text;
    if (!navigator.clipboard?.writeText) {
      setMessage(`已复制 ${selectedMatrixCells.length} 个单元格（仅应用内）`);
      return;
    }
    void navigator.clipboard.writeText(text)
      .then(() => setMessage(`已复制 ${selectedMatrixCells.length} 个单元格`))
      .catch(() => setMessage('系统剪贴板不可用，已保留应用内副本'));
  }
  async function pasteFromClipboard() {
    try {
      const text = await navigator.clipboard?.readText() || clipboardCache.current;
      pasteMatrix(text);
    } catch {
      pasteMatrix(clipboardCache.current);
    }
  }
  function focusMatrixCell(key: string) {
    requestAnimationFrame(() => {
      const cell = matrixCellRefs.current.get(key);
      cell?.focus({ preventScroll: true });
      cell?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    });
  }
  function moveMatrixSelection(rowDelta: number, columnDelta: number, extend: boolean) {
    const key = activeMatrixCell ?? selectedMatrixCells[0];
    if (!key) return;
    const [subjectId, gradeId] = key.split(':');
    const row = activeSubjects.findIndex((item) => item.id === subjectId);
    const column = shownGrades.findIndex((item) => item.id === gradeId);
    if (row < 0 || column < 0) return;
    const nextRow = Math.max(0, Math.min(activeSubjects.length - 1, row + rowDelta));
    const nextColumn = Math.max(0, Math.min(shownGrades.length - 1, column + columnDelta));
    const nextKey = matrixCellKey(activeSubjects[nextRow].id, shownGrades[nextColumn].id);
    if (extend) {
      const [anchorSubjectId, anchorGradeId] = (selectionAnchorCell.current ?? key).split(':');
      const anchor = { row: activeSubjects.findIndex((item) => item.id === anchorSubjectId),
        column: shownGrades.findIndex((item) => item.id === anchorGradeId) };
      if (anchor.row >= 0 && anchor.column >= 0) {
        setSelectedMatrixCells(rectangleKeys(activeSubjects, shownGrades, anchor,
          { row: nextRow, column: nextColumn }));
      }
    } else {
      selectionAnchorCell.current = nextKey;
      setSelectedMatrixCells([nextKey]);
    }
    setActiveMatrixCell(nextKey);
    focusMatrixCell(nextKey);
  }
  function startInlineEdit(key: string) {
    const [subjectId, gradeId] = key.split(':');
    const group = classesForGrade(gradeId);
    if (!group.length) return;
    const parts = group.map((schoolClass) =>
      formatLessonValues(allValues[requirementKey(subjectId, schoolClass.id)] ?? EMPTY_LESSONS));
    setSelectedMatrixCells([key]);
    cancelInlineBlur.current = false;
    selectionAnchorCell.current = key;
    setActiveMatrixCell(key);
    setInlineEditor({ key, value: parts.every((part) => part === parts[0]) ? parts[0] : parts.join(',') });
  }
  function commitInlineEdit() {
    if (!inlineEditor) return;
    const key = inlineEditor.key;
    const result = applyMatrixCells([key], inlineEditor.value, classes, lessonDrafts, alternating);
    setInlineEditor(null);
    if (result.error) setMessage(result.error);
    else {
      const changed = stageLessonChanges(result.values, result.changedKeys);
      if (changed.length) setMessage('节数已暂存，点击保存后生效');
    }
    focusMatrixCell(key);
  }
  function clearMatrixSelection() {
    if (!selectedMatrixCells.length) return;
    const result = applyMatrixCells(selectedMatrixCells, '', classes, lessonDrafts, alternating);
    const changed = stageLessonChanges(result.values, result.changedKeys);
    if (changed.length) setMessage(`已清空 ${result.cellCount} 个格子，点击保存后生效`);
  }
  function handleMatrixKey(event: React.KeyboardEvent<HTMLDivElement>) {
    const target = event.target as HTMLElement;
    if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || inlineEditor) return;
    if (!activeMatrixCell) return;
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'c') {
      event.preventDefault(); copyMatrix(); return;
    }
    if (event.key === 'Enter') { event.preventDefault(); startInlineEdit(activeMatrixCell); return; }
    if (event.key === 'Delete' || event.key === 'Backspace') {
      event.preventDefault(); clearMatrixSelection(); return;
    }
    const direction: Record<string, [number, number]> = {
      ArrowUp: [-1, 0], ArrowDown: [1, 0], ArrowLeft: [0, -1], ArrowRight: [0, 1],
    };
    if (direction[event.key]) {
      event.preventDefault();
      moveMatrixSelection(...direction[event.key], event.shiftKey);
    }
  }
  function openMatrixContextMenu(event: React.MouseEvent, key: string) {
    event.preventDefault();
    if (!selectedMatrixCells.includes(key)) {
      setSelectedMatrixCells([key]);
      selectionAnchorCell.current = key;
      setActiveMatrixCell(key);
    }
    setContextMenu(matrixMenuAt(key, event.clientX, event.clientY));
  }
  function downloadImportTemplate() {
    const header = '学段\t年级\t科目\t节数';
    const rows = !includeExisting ? [] : grades.flatMap((grade) => activeSubjects.flatMap((subject) => {
      const group = classesForGrade(grade.id);
      if (!group.length) return [];
      const values = group.map((schoolClass) => allValues[requirementKey(subject.id, schoolClass.id)] ?? EMPTY_LESSONS);
      if (values.every((value) => value.weekly === 0 && value.odd === 0 && value.even === 0)) return [];
      const first = formatLessonValues(values[0]);
      const input = values.every((value) => formatLessonValues(value) === first)
        ? first : values.map(formatLessonValues).join(',');
      return [[stages.find((stage) => stage.id === grade.stageId)?.name ?? '', grade.name, subject.name, input].join('\t')];
    }));
    const blob = new Blob(['\uFEFF', header, '\n', ...rows.map((row) => `${row}\n`)], { type: 'text/tab-separated-values;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url; anchor.download = '科目节数导入模板.tsv'; anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  async function downloadExcelTemplate() {
    setImportBusy(true); setImportErrors([]);
    try {
      const bytes = await buildSubjectWorkbook({ stages, grades, classes, subjects: activeSubjects,
        values: allValues, includeExisting });
      const blob = new Blob([bytes as BlobPart], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url; anchor.download = '科目节数导入模板.xlsx'; anchor.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (error) {
      setImportErrors([`生成 Excel 模板失败：${error instanceof Error ? error.message : String(error)}`]);
    } finally { setImportBusy(false); }
  }
  async function readImportFile(file: File) {
    setImportBusy(true); setImportErrors([]); setImportFileName(file.name);
    try {
      if (/\.xlsx$/i.test(file.name)) {
        const plan = await parseSubjectWorkbook(new Uint8Array(await file.arrayBuffer()),
          stages, grades, classes, activeSubjects, alternating);
        setImportWorkbookValues(plan.errors.length ? null : plan.values);
        setImportText(''); setImportErrors(plan.errors);
      } else {
        setImportText(await file.text()); setImportWorkbookValues(null);
      }
    } catch (error) {
      setImportErrors([`读取文件失败：${error instanceof Error ? error.message : String(error)}`]);
      setImportWorkbookValues(null);
    } finally { setImportBusy(false); }
  }
  function applyImport() {
    const plan = importWorkbookValues
      ? { values: importWorkbookValues, errors: [] }
      : parseSubjectImportText(importText, stages, grades, classes, activeSubjects, alternating);
    if (plan.errors.length) { setImportErrors(plan.errors); return; }
    setLessonDrafts((drafts) => ({ ...drafts, ...plan.values }));
    setEditedCells((keys) => [...new Set([...keys, ...Object.keys(plan.values)])]);
    setImportOpen(false); setImportErrors([]); setImportText('');
    setImportWorkbookValues(null); setImportFileName('');
    setMessage(`已暂存 ${Object.keys(plan.values).length} 个班级科目节数，点击保存后生效`);
  }

  function beginSubjectDialog(subject: Subject | 'new') {
    setSubjectDialog(subject);
    setSubjectName(subject === 'new' ? '' : subject.name);
    setSubjectShortName(subject === 'new' ? '' : subject.shortName);
    setSubjectShortNameEdited(subject !== 'new');
    setSelectedCommonSubjects([]);
    setMessage('');
  }
  function commitSubject() {
    if (!subjectDialog) return;
    const plan = buildSubjectDraftInputs({
      isNew: subjectDialog === 'new', name: subjectName, shortName: subjectShortName,
      selectedCommonSubjects,
      existingNames: activeSubjects.filter((item) => subjectDialog === 'new' || item.id !== subjectDialog.id)
        .map((item) => item.name),
    });
    if (plan.error) { setMessage(plan.error); return; }
    if (subjectDialog === 'new') {
      const startOrder = Math.max(-1, ...activeSubjects.map((item) => item.sortOrder)) + 1;
      const additions = plan.subjects.map((item, index): Subject => ({
        id: createId(), termId: activeTermId, name: item.name,
        shortName: item.shortName, sortOrder: startOrder + index,
      }));
      setSubjectDrafts((items) => ({ ...items,
        ...Object.fromEntries(additions.map((item) => [item.id, item])) }));
    } else {
      const item = plan.subjects[0];
      const subject = { ...subjectDialog, name: item.name, shortName: item.shortName };
      const baseline = savedSubjects.find((saved) => saved.id === subject.id);
      setSubjectDrafts((items) => {
        const next = { ...items };
        if (baseline?.name === subject.name && baseline.shortName === subject.shortName) {
          delete next[subject.id];
        } else next[subject.id] = subject;
        return next;
      });
    }
    setSubjectDialog(null); setMessage('');
  }
  function openGradeEditor(subjectId: string, gradeId: string) {
    const group = classesForGrade(gradeId);
    const values = group.map((schoolClass) => valueFor(subjectId, schoolClass));
    setGradeEditor({ subjectId, gradeId });
    setGradeInput(values.length && values.every((item) => formatLessonValues(item) === formatLessonValues(values[0]))
      ? formatLessonValues(values[0]) : values.map(formatLessonValues).join(','));
    setClassInputs(Object.fromEntries(group.map((schoolClass) => [schoolClass.id, formatLessonValues(valueFor(subjectId, schoolClass))])));
    setMessage('');
  }
  function commitGradeEditor() {
    if (!gradeEditor) return;
    const group = classesForGrade(gradeEditor.gradeId);
    const next = applyGradeInput(lessonDrafts, gradeEditor.subjectId, group, gradeInput, alternating);
    if (next === null) {
      setMessage(alternating
        ? '请输入每周节数，或“每周|单周|双周”；多班可用逗号分隔'
        : '请输入非负整数；多班可用逗号分隔，数量须与班级一致');
      return;
    }
    setLessonDrafts(next);
    setEditedCells((keys) => [...new Set([...keys, ...group.map((item) => requirementKey(gradeEditor.subjectId, item.id))])]);
    setGradeEditor(null); setMessage('');
  }
  function commitClassInputs() {
    if (!gradeEditor) return;
    const group = classesForGrade(gradeEditor.gradeId);
    const next = { ...lessonDrafts };
    for (const schoolClass of group) {
      const parsed = applyGradeInput({}, gradeEditor.subjectId, [schoolClass], classInputs[schoolClass.id] ?? '', alternating);
      if (!parsed) { setMessage(`「${schoolClass.name}」节数格式无效`); return; }
      Object.assign(next, parsed);
    }
    setLessonDrafts(next);
    setEditedCells((keys) => [...new Set([...keys, ...group.map((item) => requirementKey(gradeEditor.subjectId, item.id))])]);
    setGradeEditor(null); setMessage('');
  }
  function discard() {
    setSubjectDrafts({}); setDeletedIds([]); setLessonDrafts({});
    setEditedCells([]); setPairingDrafts({}); setPresetDrafts({});
    setConstraintDrafts({}); setRoomDrafts({}); setMessage('已放弃未保存的修改');
  }
  function buildChanges() {
    const edited = new Set(editedCells);
    const requirementsByGrade: Record<string, SubjectRequirement[]> = {};
    for (const grade of grades) {
      const gradeClasses = classesForGrade(grade.id);
      const editedSubjectIds = new Set(activeSubjects.filter((subject) =>
        gradeClasses.some((schoolClass) => edited.has(requirementKey(subject.id, schoolClass.id)))
      ).map((subject) => subject.id));
      if (!editedSubjectIds.size) continue;
      requirementsByGrade[grade.id] = [
        ...subjectRequirements.filter((row) => row.gradeId === grade.id &&
          !editedSubjectIds.has(row.subjectId) && !deletedIds.includes(row.subjectId)),
        ...makeRequirementRows([...editedSubjectIds], gradeClasses, allValues, subjectRequirements),
      ];
    }
    const presetScopes = Object.entries(presetDrafts).map(([key, rows]) => {
      const [subjectId, scopeType, scopeId, stageId] = JSON.parse(key) as [string, ScopeType, string, string];
      return { subjectId, scopeType, scopeId, stageId, rows };
    });
    const constraintScopes = Object.entries(constraintDrafts).map(([key, rows]) => {
      const [subjectId, scopeType, scopeId, stageId] = JSON.parse(key) as [string, ScopeType, string, string];
      return { subjectId, scopeType, scopeId, stageId, rows };
    });
    const roomScopes = Object.entries(roomDrafts).map(([key, settings]) => {
      const [subjectId, scopeType, scopeId, stageId] = JSON.parse(key) as [string, ScopeType, string, string];
      return { subjectId, scopeType, scopeId, stageId, ...settings };
    });
    return { upserts: Object.values(subjectDrafts), deletedIds, requirementsByGrade,
      pairingsByClass: pairingDrafts, presetScopes, constraintScopes, roomScopes };
  }
  async function save(confirmed = false): Promise<boolean> {
    if (!activeTermId || saving || !hasChanges) return !hasChanges;
    const invalidPair = classes.flatMap((schoolClass) =>
      pairingDrafts[schoolClass.id] ?? subjectPairings.filter((pair) => pair.classId === schoolClass.id))
      .find((pair) => {
        if (deletedIds.includes(pair.oddSubjectId) || deletedIds.includes(pair.evenSubjectId)) return false;
        const odd = allValues[requirementKey(pair.oddSubjectId, pair.classId)]?.odd ?? 0;
        const even = allValues[requirementKey(pair.evenSubjectId, pair.classId)]?.even ?? 0;
        return odd === 0 || odd !== even;
      });
    if (invalidPair) {
      setMessage(`${classes.find((item) => item.id === invalidPair.classId)?.name ?? '班级'}的配对课程节数不一致，请先调整或解除配对`);
      return false;
    }
    for (const rows of Object.values(constraintDrafts)) for (const row of rows) {
      const ordered = [
        [row.minimumDailyLessons, row.maximumDailyLessons, '单日节数'],
        [row.minimumDailyConsecutivePairs, row.maximumDailyConsecutivePairs, '单日连堂'],
        [row.minimumWeeklyConsecutivePairs, row.maximumWeeklyConsecutivePairs, '每周连堂'],
      ] as const;
      for (const [minimum, maximum, label] of ordered) {
        if (minimum !== null && maximum !== null && minimum > maximum) {
          setMessage(`${label}的最少值不能大于最多值`); return false;
        }
      }
    }
    const roomIds = new Set(publicRooms.map((room) => room.id));
    if (Object.values(roomDrafts).some((settings) =>
      settings.assignment?.roomId && !roomIds.has(settings.assignment.roomId))) {
      setMessage('有科目引用了已删除的公共场室，请重新选择'); return false;
    }
    try {
      await loadFreeSlotsForStages(stages.map((stage) => stage.id));
    } catch (error) {
      setMessage(`读取可排容量失败：${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
    const freeSlots = Object.values(useAppStore.getState().freeSlotsByStage)
      .flat().filter((slot) => stages.some((stage) => stage.id === slot.stageId));
    const warnings = grades.flatMap((grade) => {
      const summary = summarizeGradeCapacity(grade, classesForGrade(grade.id),
        activeSubjects.map((item) => item.id), allValues, routinesByStage[grade.stageId], freeSlots, activeTermId);
      return summary && summary.excess > 0 ? [`${grade.name} · ${summary.className}超出 ${summary.excess} 节`] : [];
    });
    if (warnings.length && !confirmed) { setCapacityWarnings(warnings); return false; }
    setSaving(true); setMessage('');
    try {
      await saveSubjectChanges(buildChanges());
      setSubjectDrafts({}); setDeletedIds([]); setLessonDrafts({});
      setEditedCells([]); setPairingDrafts({}); setPresetDrafts({});
      setConstraintDrafts({}); setRoomDrafts({}); setCapacityWarnings(null);
      setMessage('科目设置已保存');
      return true;
    } catch (error) {
      setMessage(`保存失败：${error instanceof Error ? error.message : String(error)}`);
      return false;
    } finally { setSaving(false); }
  }
  function addPairing() {
    if (!pairingClassId || !oddSubjectId || !evenSubjectId || oddSubjectId === evenSubjectId) {
      setMessage('请选择不同的单周与双周科目'); return;
    }
    const targets = selectedPairingClasses();
    if (!targets.length) { setMessage('请先选择年级或班级'); return; }
    const invalid = targets.filter((schoolClass) => {
      const odd = allValues[requirementKey(oddSubjectId, schoolClass.id)]?.odd ?? 0;
      const even = allValues[requirementKey(evenSubjectId, schoolClass.id)]?.even ?? 0;
      return odd === 0 || odd !== even;
    });
    if (invalid.length) {
      setMessage(`${invalid.map((item) => item.name).join('、')}的单周与双周节数须相同且大于 0`);
      return;
    }
    const conflicts = targets.filter((schoolClass) =>
      (pairingDrafts[schoolClass.id] ?? subjectPairings.filter((item) => item.classId === schoolClass.id))
        .some((pair) => (pair.oddSubjectId === oddSubjectId || pair.evenSubjectId === evenSubjectId) &&
          (pair.oddSubjectId !== oddSubjectId || pair.evenSubjectId !== evenSubjectId)));
    if (conflicts.length) { setMessage(`${conflicts.map((item) => item.name).join('、')}已有占用所选科目的配对`); return; }
    const next = { ...pairingDrafts };
    let added = 0;
    for (const schoolClass of targets) {
      const current = next[schoolClass.id] ?? subjectPairings.filter((item) => item.classId === schoolClass.id);
      if (current.some((pair) => pair.oddSubjectId === oddSubjectId && pair.evenSubjectId === evenSubjectId)) continue;
      next[schoolClass.id] = [...current, { id: createId(), classId: schoolClass.id, oddSubjectId, evenSubjectId }];
      added++;
    }
    if (!added) { setMessage('所选范围已存在相同配对'); return; }
    setPairingDrafts(next);
    setOddSubjectId(''); setEvenSubjectId(''); setMessage('');
  }
  function selectedPairingClasses(): ClassGroup[] {
    if (!pairingClassId) return [];
    return pairingClassId.startsWith('grade:')
      ? classesForGrade(pairingClassId.slice(6))
      : classes.filter((item) => item.id === pairingClassId);
  }
  const pairingClasses = selectedPairingClasses();
  const visiblePairings = pairingClasses.flatMap((schoolClass) =>
    pairingDrafts[schoolClass.id] ?? subjectPairings.filter((item) => item.classId === schoolClass.id));
  const eligibleOddSubjects = activeSubjects.filter((subject) => pairingClasses.length > 0 &&
    pairingClasses.every((schoolClass) =>
      (allValues[requirementKey(subject.id, schoolClass.id)]?.odd ?? 0) > 0));
  const eligibleEvenSubjects = activeSubjects.filter((subject) => pairingClasses.length > 0 &&
    pairingClasses.every((schoolClass) =>
      (allValues[requirementKey(subject.id, schoolClass.id)]?.even ?? 0) > 0));
  function openPreset(subjectId: string) {
    const stageId = shownGrades[0]?.stageId ?? stages[0]?.id ?? '';
    advancedSnapshot.current = { presets: presetDrafts, constraints: constraintDrafts, rooms: roomDrafts };
    setPresetSubjectId(subjectId); setPresetStageId(stageId);
    setPresetScopeType('stage'); setPresetScopeId(stageId);
    setExpandedPresetStages([stageId]); setExpandedPresetGrades([]);
    setAdvancedTab('presets');
    setAdvancedError('');
    setAdvancedWarnings([]);
    setMessage('');
  }
  function closePreset(saveDraft: boolean) {
    if (!saveDraft && advancedSnapshot.current) {
      setPresetDrafts(advancedSnapshot.current.presets);
      setConstraintDrafts(advancedSnapshot.current.constraints);
      setRoomDrafts(advancedSnapshot.current.rooms);
    }
    advancedSnapshot.current = null;
    setPresetMenu(null);
    setPresetSubjectId(null);
    setAdvancedWarnings([]);
    if (saveDraft) setMessage('科目高级设置已暂存，点击页面顶部“保存”后生效');
  }
  function validateAndClosePreset() {
    for (const constraint of allSubjectConstraints) {
      const pairs: Array<[number | null, number | null, string]> = [
        [constraint.minimumDailyLessons, constraint.maximumDailyLessons, '每日课节'],
        [constraint.minimumDailyConsecutivePairs, constraint.maximumDailyConsecutivePairs, '每日连堂'],
        [constraint.minimumWeeklyConsecutivePairs, constraint.maximumWeeklyConsecutivePairs, '每周连堂'],
      ];
      for (const [minimum, maximum, label] of pairs) {
        if (minimum !== null && maximum !== null && minimum > maximum) {
          setAdvancedError(scopeLabel(constraint.scopeType, constraint.scopeId, constraint.stageId) +
            '的' + label + '最少值不能大于最多值');
          return;
        }
      }
    }
    const conflict = validateConstraintRanges(allSubjectConstraints, stages, grades, classes,
      Object.fromEntries(Object.entries(routinesByStage).map(([stageId, routine]) =>
        [stageId, routine.teachingDays.filter((day) => day.isTeachingDay).map((day) => day.weekday)])),
      activeTermId ?? '');
    if (conflict) { setAdvancedError(conflict); return; }
    for (const draft of Object.values(roomDrafts)) {
      if (draft.assignment?.roomId && !publicRooms.some((room) => room.id === draft.assignment?.roomId)) {
        setAdvancedError('所选场室已删除，请重新选择或重置为继承'); return;
      }
      if (draft.limit && draft.limit.maxParallelLessons < 1) {
        setAdvancedError('同科目同时上课上限须为正整数'); return;
      }
    }
    if (presetSubjectId && presetDrafts !== advancedSnapshot.current?.presets && !advancedWarnings.length) {
      const warnings: string[] = [];
      for (const schoolClass of classes) {
        const grade = grades.find((item) => item.id === schoolClass.gradeId);
        const routine = grade && routinesByStage[grade.stageId];
        if (!grade || !routine) continue;
        let mustCount = 0;
        for (const day of routine.teachingDays.filter((item) => item.isTeachingDay)) {
          for (const period of routine.periodTypes) {
            const count = routine.dailyOverrides.find((item) => item.periodTypeId === period.id && item.weekday === day.weekday)?.lessonCount ?? period.defaultLessonCount;
            for (let lesson = 1; lesson <= count; lesson++) {
              const blocked = (freeSlotsByStage[grade.stageId] ?? []).some((slot) =>
                slot.weekday === day.weekday && slot.periodTypeId === period.id && slot.lessonIndex === lesson &&
                (slot.scopeType === 'school' || slot.scopeType === 'stage' || slot.scopeType === 'grade' && slot.scopeId === grade.id ||
                  slot.scopeType === 'class' && slot.scopeId === schoolClass.id));
              if (blocked) continue;
              const chain: Array<[ScopeType, string]> = [['class', schoolClass.id], ['grade', grade.id], ['stage', grade.stageId], ['school', activeTermId ?? '']];
              const preset = chain.map(([type, id]) => allSubjectPresets.find((row) => row.scopeType === type && row.scopeId === id &&
                row.stageId === grade.stageId && row.weekday === day.weekday && row.periodTypeId === period.id && row.lessonIndex === lesson)).find(Boolean);
              if (preset?.value === 'must') mustCount++;
            }
          }
        }
        const demand = allValues[requirementKey(presetSubjectId, schoolClass.id)] ?? EMPTY_LESSONS;
        if (mustCount > demand.weekly + demand.odd || mustCount > demand.weekly + demand.even) {
          warnings.push(schoolClass.name + '：一定排 ' + mustCount + ' 格，单周需求 ' +
            (demand.weekly + demand.odd) + ' 节，双周需求 ' + (demand.weekly + demand.even) + ' 节');
        }
      }
      if (warnings.length) { setAdvancedWarnings(warnings); return; }
    }
    setAdvancedError('');
    closePreset(true);
  }
  function setPresetScope(type: ScopeType, stageId: string, scopeId: string) {
    setPresetScopeType(type); setPresetStageId(stageId); setPresetScopeId(scopeId);
  }
  const currentPresetKey = presetSubjectId && presetScopeId
    ? presetScopeKey(presetSubjectId, presetScopeType, presetScopeId, presetStageId) : '';
  const currentPresets = presetDrafts[currentPresetKey] ?? subjectPresets.filter((row) =>
    row.subjectId === presetSubjectId && row.scopeType === presetScopeType &&
    row.scopeId === presetScopeId && row.stageId === presetStageId);
  function presetAt(weekday: number, periodTypeId: string, lessonIndex: number):
    { value: SubjectPreset['value']; inherited: boolean } {
    if (!presetSubjectId) return { value: 'auto', inherited: false };
    const chain: Array<[ScopeType, string]> = [[presetScopeType, presetScopeId]];
    if (presetScopeType === 'class') {
      const gradeId = classes.find((item) => item.id === presetScopeId)?.gradeId;
      if (gradeId) chain.push(['grade', gradeId]);
    }
    if (presetScopeType === 'class' || presetScopeType === 'grade') chain.push(['stage', presetStageId]);
    if (presetScopeType !== 'school') chain.push(['school', activeTermId ?? '']);
    for (const [index, [scopeType, scopeId]] of chain.entries()) {
      const key = presetScopeKey(presetSubjectId, scopeType, scopeId, presetStageId);
      const rows = presetDrafts[key] ?? subjectPresets.filter((row) =>
        row.subjectId === presetSubjectId && row.scopeType === scopeType &&
        row.scopeId === scopeId && row.stageId === presetStageId);
      const match = rows.find((row) => row.weekday === weekday &&
        row.periodTypeId === periodTypeId && row.lessonIndex === lessonIndex);
      if (match) return { value: match.value, inherited: index > 0 };
    }
    return { value: 'auto', inherited: false };
  }
  const currentConstraints = constraintDrafts[currentPresetKey] ?? subjectLessonConstraints.filter((row) =>
    row.subjectId === presetSubjectId && row.scopeType === presetScopeType &&
    row.scopeId === presetScopeId && row.stageId === presetStageId);
  const currentRoomSettings = roomDrafts[currentPresetKey] ?? {
    assignment: subjectRoomAssignments.find((row) => row.subjectId === presetSubjectId &&
      row.scopeType === presetScopeType && row.scopeId === presetScopeId && row.stageId === presetStageId) ?? null,
    limit: subjectParallelLimits.find((row) => row.subjectId === presetSubjectId &&
      row.scopeType === presetScopeType && row.scopeId === presetScopeId && row.stageId === presetStageId) ?? null,
  };
  function updateConstraint(weekday: number | null, field: keyof Pick<SubjectLessonConstraint,
    'minimumDailyLessons' | 'maximumDailyLessons' | 'minimumDailyConsecutivePairs' |
    'maximumDailyConsecutivePairs' | 'minimumWeeklyConsecutivePairs' | 'maximumWeeklyConsecutivePairs'>,
    raw: string) {
    if (!presetSubjectId || !presetScopeId || (raw && !/^\d+$/.test(raw))) return;
    const value = raw === '' ? null : Number(raw);
    const row: SubjectLessonConstraint = currentConstraints.find((item) => item.weekday === weekday) ?? {
      id: createId(), subjectId: presetSubjectId, scopeType: presetScopeType,
      scopeId: presetScopeId, stageId: presetStageId, weekday,
      minimumDailyLessons: null, maximumDailyLessons: null,
      minimumDailyConsecutivePairs: null, maximumDailyConsecutivePairs: null,
      minimumWeeklyConsecutivePairs: null, maximumWeeklyConsecutivePairs: null,
    };
    const updated = { ...row, [field]: value };
    const rows = currentConstraints.filter((item) => item.weekday !== weekday);
    if ([updated.minimumDailyLessons, updated.maximumDailyLessons,
      updated.minimumDailyConsecutivePairs, updated.maximumDailyConsecutivePairs,
      updated.minimumWeeklyConsecutivePairs, updated.maximumWeeklyConsecutivePairs]
      .some((item) => item !== null)) rows.push(updated);
    setConstraintDrafts((drafts) => ({ ...drafts, [currentPresetKey]: rows }));
  }
  function updateRoom(roomValue: string) {
    if (!presetSubjectId || !presetScopeId || !activeTermId) return;
    const assignment = roomValue === 'inherit' ? null : {
      id: currentRoomSettings.assignment?.id ?? createId(), subjectId: presetSubjectId,
      termId: activeTermId, stageId: presetStageId, scopeType: presetScopeType,
      scopeId: presetScopeId, roomId: roomValue === 'none' ? null : roomValue,
    };
    setRoomDrafts((drafts) => ({ ...drafts, [currentPresetKey]:
      { ...currentRoomSettings, assignment } }));
  }
  function updateParallel(raw: string) {
    if (!presetSubjectId || !presetScopeId || !activeTermId || (raw && !/^\d+$/.test(raw))) return;
    const count = raw === '' ? null : Number(raw);
    if (count !== null && count < 1) return;
    const limit: SubjectParallelLimit | null = count === null ? null : {
      id: currentRoomSettings.limit?.id ?? createId(), subjectId: presetSubjectId,
      termId: activeTermId, stageId: presetStageId, scopeType: presetScopeType,
      scopeId: presetScopeId, maxParallelLessons: count,
    };
    setRoomDrafts((drafts) => ({ ...drafts, [currentPresetKey]:
      { ...currentRoomSettings, limit } }));
  }
  function setPresetValue(weekday: number, periodTypeId: string, lessonIndex: number, value: SubjectPreset['value'] | null) {
    if (!presetSubjectId || !presetScopeId) return;
    const previous = currentPresets.find((row) => row.weekday === weekday &&
      row.periodTypeId === periodTypeId && row.lessonIndex === lessonIndex);
    const rows = currentPresets.filter((row) => !(row.weekday === weekday && row.periodTypeId === periodTypeId && row.lessonIndex === lessonIndex));
    if (value !== null) rows.push({ id: previous?.id ?? createId(), subjectId: presetSubjectId,
      scopeType: presetScopeType, scopeId: presetScopeId, stageId: presetStageId,
      weekday, periodTypeId, lessonIndex, value });
    setPresetDrafts((drafts) => ({ ...drafts, [currentPresetKey]: rows }));
    setAdvancedWarnings([]);
  }
  function cyclePreset(weekday: number, periodTypeId: string, lessonIndex: number) {
    const next = PRESET_VALUES[(PRESET_VALUES.indexOf(presetAt(weekday, periodTypeId, lessonIndex).value) + 1) % PRESET_VALUES.length];
    setPresetValue(weekday, periodTypeId, lessonIndex, next);
  }
  function presetBlocked(weekday: number, periodTypeId: string, lessonIndex: number): boolean {
    return (freeSlotsByStage[presetStageId] ?? []).some((slot) =>
      slot.weekday === weekday && slot.periodTypeId === periodTypeId && slot.lessonIndex === lessonIndex &&
      (slot.scopeType === 'school' || slot.scopeType === 'stage' ||
        slot.scopeType === 'grade' && (slot.scopeId === presetScopeId || presetScopeType === 'class' &&
          classes.find((item) => item.id === presetScopeId)?.gradeId === slot.scopeId) ||
        slot.scopeType === 'class' && slot.scopeId === presetScopeId));
  }
  const allSubjectPresets = presetSubjectId ? (() => {
    const replaced = new Set(Object.keys(presetDrafts));
    return [...subjectPresets.filter((row) => row.subjectId === presetSubjectId &&
      !replaced.has(presetScopeKey(row.subjectId, row.scopeType, row.scopeId, row.stageId))),
      ...Object.entries(presetDrafts).filter(([key]) => key.startsWith(`["${presetSubjectId}",`)).flatMap(([, rows]) => rows)];
  })() : [];
  const allSubjectConstraints = presetSubjectId ? (() => {
    const replaced = new Set(Object.keys(constraintDrafts));
    return [...subjectLessonConstraints.filter((row) => row.subjectId === presetSubjectId &&
      !replaced.has(presetScopeKey(row.subjectId, row.scopeType, row.scopeId, row.stageId))),
      ...Object.entries(constraintDrafts).filter(([key]) => key.startsWith(`["${presetSubjectId}",`)).flatMap(([, rows]) => rows)];
  })() : [];
  const removedSubjectPresets = subjectPresets.filter((row) => row.subjectId === presetSubjectId &&
    presetDrafts[presetScopeKey(row.subjectId, row.scopeType, row.scopeId, row.stageId)]?.every((item) => item.id !== row.id));
  const removedSubjectConstraints = subjectLessonConstraints.filter((row) => row.subjectId === presetSubjectId &&
    constraintDrafts[presetScopeKey(row.subjectId, row.scopeType, row.scopeId, row.stageId)]?.every((item) => item.id !== row.id));
  function inheritedConstraint(weekday: number | null, field: ConstraintField): number | null {
    return resolveConstraintField(allSubjectConstraints, classes, activeTermId ?? '',
      presetScopeType, presetScopeId, presetStageId, weekday, field);
  }
  function scopeLabel(scopeType: ScopeType, scopeId: string, stageId: string): string {
    const stage = stages.find((item) => item.id === stageId)?.name ?? stageId;
    if (scopeType === 'stage' || scopeType === 'school') return stage;
    const gradeId = scopeType === 'class' ? classes.find((item) => item.id === scopeId)?.gradeId : scopeId;
    const grade = grades.find((item) => item.id === gradeId)?.name ?? gradeId;
    return scopeType === 'class' ? `${stage} · ${grade} · ${classes.find((item) => item.id === scopeId)?.name ?? scopeId}` : `${stage} · ${grade}`;
  }
  function removePreset(row: SubjectPreset) {
    const key = presetScopeKey(row.subjectId, row.scopeType, row.scopeId, row.stageId);
    const original = presetDrafts[key] ?? subjectPresets.filter((item) =>
      item.subjectId === row.subjectId && item.scopeType === row.scopeType &&
      item.scopeId === row.scopeId && item.stageId === row.stageId);
    setPresetDrafts((drafts) => ({ ...drafts, [key]: original.filter((item) => item.id !== row.id) }));
    setAdvancedWarnings([]);
  }
  function restorePreset(row: SubjectPreset) {
    const key = presetScopeKey(row.subjectId, row.scopeType, row.scopeId, row.stageId);
    setPresetDrafts((drafts) => ({ ...drafts, [key]: [...(drafts[key] ?? []), row] }));
    setAdvancedWarnings([]);
  }
  function removeConstraint(row: SubjectLessonConstraint) {
    const key = presetScopeKey(row.subjectId, row.scopeType, row.scopeId, row.stageId);
    const original = constraintDrafts[key] ?? subjectLessonConstraints.filter((item) =>
      item.subjectId === row.subjectId && item.scopeType === row.scopeType &&
      item.scopeId === row.scopeId && item.stageId === row.stageId);
    setConstraintDrafts((drafts) => ({ ...drafts, [key]: original.filter((item) => item.id !== row.id) }));
  }
  function restoreConstraint(row: SubjectLessonConstraint) {
    const key = presetScopeKey(row.subjectId, row.scopeType, row.scopeId, row.stageId);
    setConstraintDrafts((drafts) => ({ ...drafts, [key]: [...(drafts[key] ?? []), row] }));
  }

  if (!activeTermId) return <div className="rounded-card bg-surface"><EmptyState variant="terms" title="还没有创建学期" description="先到「学期与日历」建好本学期，就能回来配置科目与每周节数啦。" action={<Button variant="outline" size="sm" onClick={() => setSelectedSection('terms')}>前往学期与日历</Button>} /></div>;
  if (!stages.length) return <div className="rounded-card bg-surface p-8">
    <p className="font-medium text-ink">请先设置学段和班级</p>
    <Button className="mt-4" onClick={() => setSelectedSection('classes')}>前往班级与学段</Button>
  </div>;

  const currentScopeStage = stages.find((stage) => stage.id === scopeStageId);
  const scopeFilterLabel = scopeStageId === 'all'
    ? `全校 (${grades.length})`
    : visibleGradeIds === null || shownGrades.length === scopeGrades.length
      ? `${currentScopeStage?.name ?? '学段'} (${scopeGrades.length})`
      : `${currentScopeStage?.name ?? '学段'} · ${shownGrades.length}/${scopeGrades.length} 年级`;

  return <section className="flex h-[calc(100dvh-88px)] min-h-[420px] flex-col gap-4">
    <div
      ref={toolbarRef}
      className="sticky-glass-toolbar sticky top-0 z-30 flex shrink-0 flex-wrap items-center justify-between gap-3 rounded-card bg-surface px-4 py-3 shadow-sm"
    >
      <div className="flex min-w-0 flex-wrap items-center gap-2.5">
        <Popover>
          <PopoverTrigger asChild>
            <button
              type="button"
              aria-label="筛选学段与年级"
              className="inline-flex h-8 items-center gap-1.5 rounded-control border border-border bg-surface px-2.5 text-[12px] font-medium text-ink transition-colors hover:border-control-border hover:bg-table-header focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <span className="text-ink-secondary">范围</span>
              <span className="whitespace-nowrap">{scopeFilterLabel}</span>
              <ChevronDown aria-hidden="true" className="h-3.5 w-3.5 text-ink-secondary" />
            </button>
          </PopoverTrigger>
          <PopoverContent align="start" className="w-64 p-2">
            <p className="mb-1.5 px-2.5 py-1 text-[11px] font-semibold text-ink-secondary">学段与年级</p>
            <button
              type="button"
              className={`flex w-full items-center justify-between rounded-[9px] px-2.5 py-1.5 text-left text-[12.5px] transition-colors ${scopeStageId === 'all' ? 'bg-selection font-semibold text-primary' : 'text-ink hover:bg-table-header'}`}
              onClick={() => { setScopeStageId('all'); setVisibleGradeIds(null); }}
            >
              <span>全校</span>
              <span className="text-[11.5px] text-ink-secondary tabular-nums">{grades.length}</span>
            </button>
            {sortByOrder(stages).map((stage) => {
              const group = sortByOrder(grades.filter((grade) => grade.stageId === stage.id));
              const selected = scopeStageId === stage.id;
              return <div key={stage.id} className="mt-0.5">
                <button
                  type="button"
                  className={`flex w-full items-center gap-1.5 rounded-[9px] px-2.5 py-1.5 text-left text-[12.5px] transition-colors ${selected ? 'bg-selection font-semibold text-primary' : 'text-ink hover:bg-table-header'}`}
                  onClick={() => { setScopeStageId(stage.id); setVisibleGradeIds(null); }}
                >
                  {selected ? <ChevronDown className="h-3.5 w-3.5 shrink-0" /> : <ChevronRight className="h-3.5 w-3.5 shrink-0" />}
                  <span className="flex-1 truncate">{stage.name}</span>
                  <span className="text-[11.5px] text-ink-secondary tabular-nums">{group.length}</span>
                </button>
                {selected && group.length > 0 && <div className="ml-5 mt-0.5 space-y-0.5 border-l border-border pl-2">
                  {group.map((grade) => <label key={grade.id} className="flex cursor-pointer items-center gap-2 rounded-[7px] px-2 py-1 text-[12px] text-ink-secondary hover:bg-table-header hover:text-ink">
                    <Checkbox
                      checked={visibleGradeIds === null || visibleGradeIds.includes(grade.id)}
                      onCheckedChange={() => setVisibleGradeIds((ids) => {
                        const current = ids ?? group.map((item) => item.id);
                        return current.includes(grade.id) ? current.filter((id) => id !== grade.id) : [...current, grade.id];
                      })}
                    />
                    <span className="truncate">{grade.name}</span>
                  </label>)}
                </div>}
              </div>;
            })}
          </PopoverContent>
        </Popover>
        {hasChanges && <Badge variant="warning">未保存</Badge>}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {alternating && <Button variant="outline" size="sm" onClick={() => { setMessage(''); setPairingClassId(grades[0] ? `grade:${grades[0].id}` : null); }}>配对课程</Button>}
        <Button variant="outline" size="sm" onClick={() => { setImportOpen(true); setImportErrors([]); }}><Upload className="h-4 w-4" />导入表格</Button>
        <Button variant="outline" size="sm" onClick={() => beginSubjectDialog('new')}><Plus className="h-4 w-4" />添加科目</Button>
        {hasChanges && <Button variant="ghost" size="sm" onClick={discard}><RotateCcw className="h-4 w-4" />放弃修改</Button>}
        <Button size="sm" disabled={!hasChanges || saving} onClick={() => void save()}><Save className="h-4 w-4" />{saving ? '保存中' : '保存'}</Button>
      </div>
    </div>
    {helpOpen && (
      <Alert variant="info" className="shrink-0 pr-10">
        <Info className="h-4 w-4" />
        <AlertTitle className="text-[13px]">填写说明</AlertTitle>
        <AlertDescription className="flex flex-wrap gap-x-5 gap-y-1">
          <span><strong className="font-medium text-ink">全年级统一：</strong>直接填整数（如 <code className="rounded bg-surface/80 px-1 py-0.5 font-mono text-[11px]">5</code>）。</span>
          <span><strong className="font-medium text-ink">单双周：</strong>按 <code className="rounded bg-surface/80 px-1 py-0.5 font-mono text-[11px]">每周|单周|双周</code> 填写（如 <code className="rounded bg-surface/80 px-1 py-0.5 font-mono text-[11px]">0|4|0</code> 或 <code className="rounded bg-surface/80 px-1 py-0.5 font-mono text-[11px]">3|1|1</code>）。</span>
          <span><strong className="font-medium text-ink">单个班级：</strong>英文逗号按班序分隔（如 <code className="rounded bg-surface/80 px-1 py-0.5 font-mono text-[11px]">5,5,4</code>），或右键选「逐班编辑」。</span>
          <span><strong className="font-medium text-ink">快捷操作：</strong>{touchInput ? '长按格子后拖动多选，松手打开快捷菜单。' : '拖动框选多格，松手打开快捷菜单。'}</span>
        </AlertDescription>
        <button
          type="button"
          aria-label="关闭填写帮助说明"
          onClick={() => setHelpOpen(false)}
          className="absolute right-3 top-3 rounded-md p-1 text-ink-secondary transition-colors hover:bg-surface/80 hover:text-ink"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </Alert>
    )}
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-card bg-surface">
        {activeSubjects.length === 0 ? <EmptyState variant="subjects" title="科目节数还是空的" description="先添加几门科目，就可以在这里批量设置各年级每周节数啦。" action={<Button variant="outline" size="sm" onClick={() => beginSubjectDialog('new')}><Plus className="h-4 w-4" />添加科目</Button>} className="flex-1" /> :
          <>
          <div className="min-h-0 flex-1 select-none overflow-auto" ref={matrixScrollRef}
            onScroll={updateScrollShadow}
            onKeyDown={handleMatrixKey}
            onPaste={(event) => {
            if (event.target instanceof HTMLInputElement || event.target instanceof HTMLTextAreaElement) return;
            if (!selectedMatrixCells.length) return;
            event.preventDefault(); pasteMatrix(event.clipboardData.getData('text/plain'));
          }}>
            <table className="h-full w-full table-fixed border-separate border-spacing-0 text-[13px]" style={{ minWidth: 160 + shownGrades.length * 112 + 120 }}>
              <colgroup><col style={{ width: 160 }} />{shownGrades.map((grade) => <col key={grade.id} />)}<col style={{ width: 120 }} /></colgroup>
              <thead className="sticky top-0 z-20 bg-surface"><tr className="text-ink-secondary">
                <th className={`sticky left-0 top-0 z-30 border-b border-border bg-surface px-4 py-4 text-left text-[12px] font-semibold after:pointer-events-none after:absolute after:inset-y-0 after:left-full after:w-2.5 after:bg-gradient-to-r after:from-slate-900/[0.07] after:to-transparent after:transition-opacity after:duration-150 ${scrollShadow.left ? 'after:opacity-100' : 'after:opacity-0'}`}>科目</th>
                {shownGrades.map((grade) => <th key={grade.id} className="border-b border-border bg-surface px-2 py-4 text-center text-[12px] font-semibold text-primary">{grade.name}</th>)}
                <th className={`sticky right-0 top-0 z-30 border-b border-border bg-surface px-3 py-4 text-left text-[12px] font-semibold before:pointer-events-none before:absolute before:inset-y-0 before:right-full before:w-2.5 before:bg-gradient-to-l before:from-slate-900/[0.07] before:to-transparent before:transition-opacity before:duration-150 ${scrollShadow.right ? 'before:opacity-100' : 'before:opacity-0'}`}>科目高级设置</th>
              </tr></thead>
              <tbody>{activeSubjects.map((subject, rowIndex) => <tr key={subject.id} className="group h-[46px] hover:bg-table-header/50">
                <th className={`sticky left-0 z-10 align-top bg-surface px-4 text-left font-normal group-hover:bg-table-header after:pointer-events-none after:absolute after:inset-y-0 after:left-full after:w-2.5 after:bg-gradient-to-r after:from-slate-900/[0.07] after:to-transparent after:transition-opacity after:duration-150 ${scrollShadow.left ? 'after:opacity-100' : 'after:opacity-0'}`}
                  onContextMenu={(event) => {
                    event.preventDefault();
                    setContextMenu(null);
                    setSubjectMenu({ x: Math.min(event.clientX, window.innerWidth - 172),
                      y: Math.min(event.clientY, window.innerHeight - 100), subjectId: subject.id });
                  }}>
                  <div className="flex items-center gap-2"><span aria-hidden="true" className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: subjectColor(subject.id) }} /><span className="min-w-0 flex-1 truncate font-semibold text-ink" title={subject.name}>{subject.name}</span>
                    <button title="编辑科目" aria-label={`编辑${subject.name}`} className="rounded p-1 text-ink-secondary opacity-0 hover:bg-table-header group-hover:opacity-100 focus:opacity-100" onClick={() => beginSubjectDialog(subject)}><MoreHorizontal className="h-4 w-4" /></button></div>
                </th>
                {shownGrades.map((grade, columnIndex) => {
                  const group = classesForGrade(grade.id);
                  const values = group.map((schoolClass) => allValues[requirementKey(subject.id, schoolClass.id)] ?? EMPTY_LESSONS);
                  const text = formatGradeCell(values);
                  const changed = group.some((schoolClass) => editedCells.includes(requirementKey(subject.id, schoolClass.id)));
                  const selected = selectedMatrixCells.includes(matrixCellKey(subject.id, grade.id));
                  return <td key={grade.id} className="align-top px-1 py-1 text-center">
                    {inlineEditor?.key === matrixCellKey(subject.id, grade.id) ?
                      <input autoFocus value={inlineEditor.value}
                        onFocus={(event) => event.currentTarget.select()}
                        onChange={(event) => setInlineEditor((editor) => editor ? { ...editor, value: event.target.value } : null)}
                        onKeyDown={(event) => {
                          event.stopPropagation();
                          if (event.key === 'Enter') { event.preventDefault(); cancelInlineBlur.current = true; commitInlineEdit(); }
                          if (event.key === 'Escape') { cancelInlineBlur.current = true; setInlineEditor(null); focusMatrixCell(matrixCellKey(subject.id, grade.id)); }
                        }}
                        onBlur={() => {
                          if (cancelInlineBlur.current) { cancelInlineBlur.current = false; return; }
                          commitInlineEdit();
                        }}
                        aria-label={`编辑${subject.name}${grade.name}节数`}
                        className="min-h-10 w-full select-text rounded-[8px] border border-primary bg-selection px-2 text-center text-[13px] tabular-nums text-ink outline-none" /> :
                    <button type="button" disabled={!group.length}
                      data-matrix-row={rowIndex} data-matrix-column={columnIndex}
                      ref={(element) => { const key = matrixCellKey(subject.id, grade.id); if (element) matrixCellRefs.current.set(key, element); else matrixCellRefs.current.delete(key); }}
                      onFocus={(event) => {
                        if (!event.currentTarget.matches(':focus-visible')) return;
                        const key = matrixCellKey(subject.id, grade.id);
                        if (activeMatrixCell === key) return;
                        selectionAnchorCell.current = key;
                        setActiveMatrixCell(key);
                        setSelectedMatrixCells([key]);
                      }}
                      onPointerDown={(event) => {
                        if (event.isPrimary) dragged.current = false;
                        withSelectionPress(event, () => {
                          dragAnchor.current = { row: rowIndex, column: columnIndex, pointerId: event.pointerId };
                          dragPointer.current = { x: event.clientX, y: event.clientY };
                          setDragSelecting(true);
                          dragged.current = false;
                          dragSelection.current = null;
                          const key = matrixCellKey(subject.id, grade.id);
                          selectionAnchorCell.current = key;
                          setActiveMatrixCell(key);
                          setSelectedMatrixCells([key]);
                        });
                      }}
                      onClick={(event) => { if (!dragged.current || event.detail === 0) startInlineEdit(matrixCellKey(subject.id, grade.id)); }}
                      onContextMenu={(event) => openMatrixContextMenu(event, matrixCellKey(subject.id, grade.id))}
                      aria-label={`${subject.name} ${grade.name} 节数 ${text}`}
                      className={`min-h-10 w-full select-none rounded-[8px] [-webkit-touch-callout:none] border px-2 text-center tabular-nums transition-colors ${selected ? 'border-primary bg-selection text-primary' : changed ? 'border-transparent bg-selection/50 text-primary hover:border-border' : 'border-transparent text-ink hover:border-border hover:bg-table-header'} ${text === '各班不同' ? 'text-[12px]' : 'font-medium'}`}>
                      {!group.length || text === '0'
                        ? <span className={selected || changed ? '' : 'text-ink-secondary opacity-45'}>—</span>
                        : text}</button>}</td>;
                })}
                <td className={`sticky right-0 z-10 align-top bg-surface px-3 text-left group-hover:bg-table-header before:pointer-events-none before:absolute before:inset-y-0 before:right-full before:w-2.5 before:bg-gradient-to-l before:from-slate-900/[0.07] before:to-transparent before:transition-opacity before:duration-150 ${scrollShadow.right ? 'before:opacity-100' : 'before:opacity-0'}`}><button type="button" onClick={() => openPreset(subject.id)}
                  className="min-h-10 w-full rounded-[7px] px-1 text-left text-[12px] text-ink-secondary hover:bg-selection hover:text-primary"
                  title="编辑科目预设、课节限制与行课场室">{advancedSummary(subject.id) || '—'}</button></td>
              </tr>)}</tbody>
              <tfoot className="sticky bottom-0 z-20 bg-surface text-[12px] shadow-[0_-1px_0_var(--color-border)]"><tr><th className={`sticky left-0 z-30 border-b border-border bg-surface px-4 py-2 text-left font-semibold text-ink-secondary after:pointer-events-none after:absolute after:inset-y-0 after:left-full after:w-2.5 after:bg-gradient-to-r after:from-slate-900/[0.07] after:to-transparent after:transition-opacity after:duration-150 ${scrollShadow.left ? 'after:opacity-100' : 'after:opacity-0'}`}>容量校验</th>
                {shownGrades.map((grade) => { const capacity = gradeCapacities[grade.id]; return <td key={grade.id} className="border-b border-border bg-surface px-2 py-2 text-center">
                  <span title={capacity ? `${capacity.className}：需求 ${capacity.weekly + Math.max(capacity.odd, capacity.even)} 节，课位 ${capacity.available}` : '尚无班级或作息，暂不能校验'}
                    className={`inline-flex items-center gap-1 font-medium ${capacity?.excess ? 'text-destructive' : capacity ? 'text-emerald-700' : 'text-ink-secondary'}`}>
                    <span className="h-1.5 w-1.5 rounded-full bg-current" />{capacity?.excess ? `超 ${capacity.excess} 节` : capacity ? '通过' : '待校验'}</span></td>; })}
                <td className={`sticky right-0 z-30 border-b border-border bg-surface before:pointer-events-none before:absolute before:inset-y-0 before:right-full before:w-2.5 before:bg-gradient-to-l before:from-slate-900/[0.07] before:to-transparent before:transition-opacity before:duration-150 ${scrollShadow.right ? 'before:opacity-100' : 'before:opacity-0'}`} /></tr>
                <tr><th className={`sticky left-0 z-30 bg-surface px-4 py-2 text-left font-semibold text-ink-secondary after:pointer-events-none after:absolute after:inset-y-0 after:left-full after:w-2.5 after:bg-gradient-to-r after:from-slate-900/[0.07] after:to-transparent after:transition-opacity after:duration-150 ${scrollShadow.left ? 'after:opacity-100' : 'after:opacity-0'}`}>班级周课时</th>
                  {shownGrades.map((grade) => { const capacity = gradeCapacities[grade.id]; return <td key={grade.id} className="bg-surface px-2 py-2 text-center tabular-nums">
                    {capacity ? <span title={`${capacity.className}：每周 ${capacity.weekly} 节，课位 ${capacity.available}`} className="inline-flex min-w-14 flex-col items-center leading-tight">
                      <strong className="text-[13px] text-ink">{capacity.weekly}{alternating && (capacity.odd || capacity.even) ? <small className="ml-1 font-normal text-ink-secondary">单{capacity.odd} 双{capacity.even}</small> : null}</strong>
                      <span className="my-1 h-px w-full bg-border" /><span className="text-ink-secondary">{capacity.available}</span></span> : '—'}</td>; })}
                  <td className={`sticky right-0 z-30 bg-surface before:pointer-events-none before:absolute before:inset-y-0 before:right-full before:w-2.5 before:bg-gradient-to-l before:from-slate-900/[0.07] before:to-transparent before:transition-opacity before:duration-150 ${scrollShadow.right ? 'before:opacity-100' : 'before:opacity-0'}`} /></tr></tfoot>
            </table>
          </div></>}
      </div>

    <Dialog open={subjectDialog !== null} onOpenChange={(open) => !open && setSubjectDialog(null)}><DialogContent className="max-h-[90vh] max-w-[560px] overflow-y-auto">
      <DialogHeader><DialogTitle>{subjectDialog === 'new' ? '添加科目' : '编辑科目'}</DialogTitle><DialogDescription>名称用于课表，简称用于紧凑视图。新科目节数默认为 0。</DialogDescription></DialogHeader>
      <label className="space-y-1.5 text-[13px] text-ink">科目全称<Input autoFocus value={subjectName} maxLength={40} onChange={(event) => {
        const value = event.target.value;
        setSubjectName(value);
        if (!subjectShortNameEdited) setSubjectShortName(firstSubjectCharacter(value));
      }} /></label>
      <label className="space-y-1.5 text-[13px] text-ink">简称<Input value={subjectShortName} maxLength={20} onChange={(event) => {
        setSubjectShortName(event.target.value);
        setSubjectShortNameEdited(true);
      }} placeholder="自动取科目全称首字，可修改" onKeyDown={(event) => event.key === 'Enter' && commitSubject()} /></label>
      {subjectDialog === 'new' && <div className="border-t border-border pt-3">
        <p className="mb-2 text-[12px] font-medium text-ink-secondary">从常用科目快速添加（可多选）</p>
        <div className="flex flex-wrap gap-2">
          {COMMON_SUBJECTS.map((name) => {
            const selected = selectedCommonSubjects.includes(name);
            const exists = activeSubjects.some((subject) => subject.name === name);
            return <button key={name} type="button" disabled={exists} aria-pressed={selected}
              onClick={() => setSelectedCommonSubjects((items) => selected
                ? items.filter((item) => item !== name) : [...items, name])}
              className={`inline-flex min-h-8 items-center gap-1 rounded-[9px] border px-2.5 py-1 text-[12px] transition-colors ${exists
                ? 'cursor-not-allowed border-border bg-table-header text-ink-secondary opacity-50'
                : selected ? 'border-primary bg-selection font-medium text-primary'
                : 'border-border bg-surface text-ink-secondary hover:border-primary/50 hover:text-ink'}`}>
              {selected && <Check aria-hidden="true" className="h-3.5 w-3.5" />}{name}
            </button>;
          })}
        </div>
      </div>}
      {message && <p role="alert" className="text-[12px] text-destructive">{message}</p>}
      <DialogFooter><Button variant="outline" onClick={() => setSubjectDialog(null)}>取消</Button><Button onClick={commitSubject}>{subjectDialog === 'new' ? '添加' : '保存'}</Button></DialogFooter>
    </DialogContent></Dialog>

    <Dialog open={gradeEditor !== null} onOpenChange={(open) => !open && setGradeEditor(null)}><DialogContent className="max-w-[560px]">
      <DialogHeader><DialogTitle>{activeSubjects.find((item) => item.id === gradeEditor?.subjectId)?.name} · {grades.find((item) => item.id === gradeEditor?.gradeId)?.name}</DialogTitle>
        <DialogDescription>统一设置会应用到该年级全部班级；逐班设置可保留差异。</DialogDescription></DialogHeader>
      <div className="space-y-2"><label className="text-[12px] font-medium text-ink-secondary">统一设置</label><div className="flex gap-2"><Input autoFocus value={gradeInput} onChange={(event) => setGradeInput(event.target.value)} placeholder={alternating ? '每周|单周|双周，如 3|1|1' : '每周节数，如 4'} onKeyDown={(event) => event.key === 'Enter' && commitGradeEditor()} /><Button className="shrink-0" onClick={commitGradeEditor}>应用全部</Button></div></div>
      <div className="max-h-[36vh] space-y-2 overflow-y-auto border-t border-border pt-3"><p className="text-[12px] font-medium text-ink-secondary">逐班设置</p>
        {classesForGrade(gradeEditor?.gradeId ?? '').map((schoolClass) => <label key={schoolClass.id} className="flex items-center gap-3 text-[13px] text-ink"><span className="w-28 shrink-0 truncate">{schoolClass.name}</span><Input value={classInputs[schoolClass.id] ?? ''} onChange={(event) => setClassInputs((items) => ({ ...items, [schoolClass.id]: event.target.value }))} /></label>)}</div>
      {message && <p role="alert" className="text-[12px] text-destructive">{message}</p>}
      <DialogFooter><Button variant="outline" onClick={() => setGradeEditor(null)}>取消</Button><Button onClick={commitClassInputs}>应用逐班设置</Button></DialogFooter>
    </DialogContent></Dialog>

    <Dialog open={batchOpen} onOpenChange={setBatchOpen}><DialogContent>
      <DialogHeader><DialogTitle>统一设置 {selectedMatrixCells.length} 个格子</DialogTitle>
        <DialogDescription>同一节数应用到框选的每个科目与年级。空白将清除这些格子的节数。</DialogDescription></DialogHeader>
      <Input autoFocus value={batchValue} onChange={(event) => setBatchValue(event.target.value)}
        placeholder={alternating ? '例如 4 或 3|1|1' : '例如 4'}
        onKeyDown={(event) => event.key === 'Enter' && applyBatch(batchValue)} />
      {message && <p role="alert" className="text-[12px] text-destructive">{message}</p>}
      <DialogFooter><Button variant="outline" onClick={() => setBatchOpen(false)}>取消</Button>
        <Button onClick={() => applyBatch(batchValue)}>应用</Button></DialogFooter>
    </DialogContent></Dialog>

    <Dialog open={importOpen} onOpenChange={setImportOpen}><DialogContent className="max-w-[720px]">
      <DialogHeader><DialogTitle>导入科目节数</DialogTitle><DialogDescription>下载 Excel 模板，填写“科目节数”工作表后选择 .xlsx 文件；也可以从 Excel 复制四列粘贴。导入结果先暂存，仍需点击页面保存。</DialogDescription></DialogHeader>
      <div className="flex flex-wrap items-center gap-3"><Button variant="outline" size="sm" disabled={importBusy} onClick={() => void downloadExcelTemplate()}><Download className="h-4 w-4" />下载 Excel 模板</Button>
        <Button variant="ghost" size="sm" onClick={downloadImportTemplate}>TSV 模板</Button>
        <label className="flex items-center gap-1.5 text-[12px] text-ink-secondary"><input type="checkbox" checked={includeExisting} onChange={(event) => setIncludeExisting(event.target.checked)} />模板包含现有数据</label></div>
      <input aria-label="选择 Excel 或 TSV 文件" type="file" accept=".xlsx,.tsv,.txt,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/tab-separated-values" className="w-full text-[12px] text-ink-secondary file:mr-2 file:rounded-[6px] file:border-0 file:bg-table-header file:px-2 file:py-1.5 file:text-ink" onChange={(event) => {
        const file = event.target.files?.[0];
        if (file) void readImportFile(file);
      }} />
      {importWorkbookValues && <p className="rounded-[8px] bg-selection px-3 py-2 text-[12px] text-primary">已解析 {importFileName}，共 {Object.keys(importWorkbookValues).length} 个班级科目节数，确认后暂存。</p>}
      <textarea value={importText} onChange={(event) => { setImportText(event.target.value); setImportErrors([]); setImportWorkbookValues(null); setImportFileName(''); }} rows={9}
        placeholder={'学段\t年级\t科目\t节数\n小学部\t一年级\t语文\t5'}
        className="w-full resize-y rounded-[9px] border border-border bg-surface px-3 py-2 font-mono text-[12px] leading-6 text-ink outline-none focus:border-primary" />
      {importErrors.length > 0 && <div role="alert" className="max-h-28 overflow-y-auto rounded-[8px] bg-destructive/10 px-3 py-2 text-[12px] text-destructive">{importErrors.map((error) => <p key={error}>{error}</p>)}</div>}
      <DialogFooter><Button variant="outline" onClick={() => setImportOpen(false)}>取消</Button><Button disabled={importBusy} onClick={applyImport}>检查并暂存</Button></DialogFooter>
    </DialogContent></Dialog>

    <Dialog open={deleteTarget !== null} onOpenChange={(open) => !open && setDeleteTarget(null)}><DialogContent>
      <DialogHeader><DialogTitle>删除「{deleteTarget?.name}」？</DialogTitle><DialogDescription>保存后，该科目的节数、预设和任课关联将一并删除。</DialogDescription></DialogHeader>
      <DialogFooter><Button variant="outline" onClick={() => setDeleteTarget(null)}>取消</Button><Button variant="destructive" onClick={() => {
        if (!deleteTarget) return;
        if (savedSubjects.some((item) => item.id === deleteTarget.id)) setDeletedIds((ids) => [...ids, deleteTarget.id]);
        else setSubjectDrafts((items) => { const next = { ...items }; delete next[deleteTarget.id]; return next; });
        setPairingDrafts((drafts) => Object.fromEntries(Object.entries(drafts).map(([classId, rows]) =>
          [classId, rows.filter((row) => row.oddSubjectId !== deleteTarget.id && row.evenSubjectId !== deleteTarget.id)])));
        setDeleteTarget(null);
      }}>删除科目</Button></DialogFooter>
    </DialogContent></Dialog>

    <Dialog open={capacityWarnings !== null} onOpenChange={(open) => !open && setCapacityWarnings(null)}><DialogContent>
      <DialogHeader><DialogTitle className="flex items-center gap-2"><AlertTriangle className="h-4 w-4 text-destructive" />容量超限预警</DialogTitle><DialogDescription>以下班级的需求超过可排课位，自动排课可能无法全部排入。</DialogDescription></DialogHeader>
      <ul className="space-y-1 text-[13px] text-destructive">{capacityWarnings?.map((item) => <li key={item}>· {item}</li>)}</ul>
      <DialogFooter><Button variant="outline" onClick={() => setCapacityWarnings(null)}>返回调整</Button><Button onClick={() => void save(true)}>继续保存</Button></DialogFooter>
    </DialogContent></Dialog>

    <Dialog open={pairingClassId !== null} onOpenChange={(open) => !open && setPairingClassId(null)}><DialogContent className="max-w-[600px]">
      <DialogHeader><DialogTitle>配对课程</DialogTitle><DialogDescription>同一班级的两门科目分别安排在单周和双周。</DialogDescription></DialogHeader>
      <Select value={pairingClassId ?? ''} onValueChange={(value) => { setPairingClassId(value); setOddSubjectId(''); setEvenSubjectId(''); setMessage(''); }}><SelectTrigger><SelectValue placeholder="选择年级或班级" /></SelectTrigger><SelectContent>{sortByOrder(grades).map((grade) => <React.Fragment key={grade.id}><SelectItem value={`grade:${grade.id}`}>{grade.name} · 全部班级</SelectItem>{classesForGrade(grade.id).map((schoolClass) => <SelectItem key={schoolClass.id} value={schoolClass.id}>　{schoolClass.name}</SelectItem>)}</React.Fragment>)}</SelectContent></Select>
      <div className="flex gap-2"><Select value={oddSubjectId} onValueChange={setOddSubjectId}><SelectTrigger className="min-w-0 flex-1"><SelectValue placeholder="单周科目" /></SelectTrigger><SelectContent>{eligibleOddSubjects.map((item) => <SelectItem key={item.id} value={item.id}>{item.name}</SelectItem>)}</SelectContent></Select>
        <Select value={evenSubjectId} onValueChange={setEvenSubjectId}><SelectTrigger className="min-w-0 flex-1"><SelectValue placeholder="双周科目" /></SelectTrigger><SelectContent>{eligibleEvenSubjects.map((item) => <SelectItem key={item.id} value={item.id}>{item.name}</SelectItem>)}</SelectContent></Select><Button variant="outline" onClick={addPairing}><Plus className="h-4 w-4" /></Button></div>
      <div className="max-h-[30vh] overflow-y-auto">{visiblePairings.map((pair) => <div key={pair.id} className="flex items-center gap-2 border-b border-border py-2 text-[13px]"><span className="flex-1">{classes.find((item) => item.id === pair.classId)?.name} · 单周 {activeSubjects.find((item) => item.id === pair.oddSubjectId)?.name} · 双周 {activeSubjects.find((item) => item.id === pair.evenSubjectId)?.name}</span><button aria-label="删除配对" onClick={() => setPairingDrafts((drafts) => ({ ...drafts, [pair.classId]: (drafts[pair.classId] ?? subjectPairings.filter((item) => item.classId === pair.classId)).filter((item) => item.id !== pair.id) }))}><Trash2 className="h-4 w-4 text-ink-secondary" /></button></div>)}</div>
      {message && <p role="alert" className="text-[12px] text-destructive">{message}</p>}
      <DialogFooter><Button onClick={() => setPairingClassId(null)}><Check className="h-4 w-4" />完成</Button></DialogFooter>
    </DialogContent></Dialog>

    <Dialog open={presetSubjectId !== null} onOpenChange={(open) => { if (!open) closePreset(false); }}>
      <DialogContent onInteractOutside={(event) => {
        if (event.target instanceof Element && event.target.closest('[data-preset-menu]')) event.preventDefault();
      }} className="flex h-[min(720px,92vh)] w-[calc(100vw-32px)] max-w-[1080px] flex-col gap-0 overflow-hidden p-0">
        <DialogHeader className="shrink-0 border-0 px-6 pb-2 pt-5">
          <DialogTitle className="text-[17px]">科目高级设置 · {activeSubjects.find((item) => item.id === presetSubjectId)?.name}</DialogTitle>
          <DialogDescription className="sr-only">选择应用范围，编辑科目预设、课节限制和行课场室。</DialogDescription>
        </DialogHeader>
        <div className="grid min-h-0 flex-1 grid-cols-1 gap-4 overflow-y-auto px-6 py-3 lg:grid-cols-[236px_minmax(0,1fr)] lg:overflow-hidden">
          <aside className="min-h-0 lg:overflow-y-auto">
            <h3 className="mb-3 px-2 text-[13px] font-semibold text-ink">应用范围</h3>
            <div className="space-y-0.5 text-[12.5px]">
              {sortByOrder(stages).map((stage) => {
                const stageOpen = expandedPresetStages.includes(stage.id);
                return <div key={stage.id}>
                  <div className={'flex items-center rounded-[7px] ' + (presetScopeType === 'stage' && presetScopeId === stage.id ? 'bg-selection' : '')}>
                    <button type="button" aria-label={(stageOpen ? '收起' : '展开') + stage.name} onClick={() => setExpandedPresetStages((ids) =>
                      stageOpen ? ids.filter((id) => id !== stage.id) : [...ids, stage.id])} className="rounded p-1.5 text-ink-secondary hover:text-ink">
                      {stageOpen ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                    </button>
                    <button type="button" onClick={() => { setPresetScope('stage', stage.id, stage.id); setExpandedPresetStages((ids) => ids.includes(stage.id) ? ids : [...ids, stage.id]); }}
                      className="min-w-0 flex-1 truncate py-1.5 pr-2 text-left font-medium text-ink">{stage.name}</button>
                  </div>
                  {stageOpen && sortByOrder(grades.filter((grade) => grade.stageId === stage.id)).map((grade) => {
                    const gradeOpen = expandedPresetGrades.includes(grade.id);
                    return <div key={grade.id} className="pl-4">
                      <div className={'flex items-center rounded-[7px] ' + (presetScopeType === 'grade' && presetScopeId === grade.id ? 'bg-selection' : '')}>
                        <button type="button" aria-label={(gradeOpen ? '收起' : '展开') + grade.name} onClick={() => setExpandedPresetGrades((ids) =>
                          gradeOpen ? ids.filter((id) => id !== grade.id) : [...ids, grade.id])} className="rounded p-1.5 text-ink-secondary hover:text-ink">
                          {gradeOpen ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                        </button>
                        <button type="button" onClick={() => { setPresetScope('grade', stage.id, grade.id); setExpandedPresetGrades((ids) => ids.includes(grade.id) ? ids : [...ids, grade.id]); }}
                          className="min-w-0 flex-1 truncate py-1.5 pr-2 text-left text-ink">{grade.name}</button>
                      </div>
                      {gradeOpen && classesForGrade(grade.id).map((schoolClass) =>
                        <button key={schoolClass.id} type="button" onClick={() => setPresetScope('class', stage.id, schoolClass.id)}
                          className={'block w-full truncate rounded-[7px] py-1.5 pl-8 pr-2 text-left ' +
                            (presetScopeType === 'class' && presetScopeId === schoolClass.id ? 'bg-selection text-primary' : 'text-ink-secondary hover:bg-table-header')}>
                          {schoolClass.name}
                        </button>)}
                    </div>;
                  })}
                </div>;
              })}
            </div>
          </aside>
          <div className="flex min-h-0 min-w-0 flex-col">
            <div className="flex shrink-0 items-center gap-1 overflow-x-auto border-b border-border pb-2" role="tablist" aria-label="高级设置类型">
              {([['presets', '科目预设'], ['constraints', '课节限制'], ['rooms', '行课场室']] as const).map(([value, label]) =>
                <button key={value} type="button" role="tab" aria-selected={advancedTab === value} onClick={() => setAdvancedTab(value)}
                  className={'whitespace-nowrap rounded-[7px] px-3 py-2 text-[13px] ' +
                    (advancedTab === value ? 'bg-surface font-semibold text-primary shadow-sm' : 'text-ink-secondary hover:bg-table-header')}>
                  {label}</button>)}
            </div>
            <div className="min-h-0 flex-1 space-y-3 overflow-y-auto pt-3">
              {advancedTab === 'presets' && (() => {
                const routine = routinesByStage[presetStageId];
                if (!routine?.periodTypes.length) return <p className="py-8 text-center text-[13px] text-ink-secondary">请先完成该学段的作息设置。</p>;
                const weekdays = routine.teachingDays.filter((day) => day.isTeachingDay).map((day) => day.weekday).sort();
                const countFor = (periodId: string, weekday: number) => routine.dailyOverrides.find((item) =>
                  item.periodTypeId === periodId && item.weekday === weekday)?.lessonCount ??
                  routine.periodTypes.find((item) => item.id === periodId)?.defaultLessonCount ?? 0;
                const rows = sortByOrder(routine.periodTypes).flatMap((period) =>
                  Array.from({ length: Math.max(0, ...weekdays.map((day) => countFor(period.id, day))) },
                    (_, index) => ({ period, lessonIndex: index + 1 })));
                return <>
                  <p className="text-[12px] leading-5 text-ink-secondary">单击格子依次切换自动、尽量排、一定排、不排；右键可直接选择。浅色值继承上级范围，免任课时段不可设置。</p>
                  <div className="overflow-x-auto">
                    <table className="w-full min-w-[560px] table-fixed border-collapse text-[12px]">
                      <thead><tr className="bg-table-header text-ink-secondary"><th className="w-24 border border-table-divider px-2 py-2 text-left font-medium">课节</th>
                        {weekdays.map((day) => <th key={day} className="border border-table-divider px-1 py-2 font-medium">{WEEKDAY_NAMES[day - 1]}</th>)}</tr></thead>
                      <tbody>{rows.map(({ period, lessonIndex }) => <tr key={period.id + ':' + lessonIndex}>
                        <th className="border border-table-divider px-2 py-1.5 text-left font-medium text-ink-secondary">{period.name} 第{lessonIndex}节</th>
                        {weekdays.map((day) => {
                          if (lessonIndex > countFor(period.id, day)) return <td key={day} className="border border-table-divider bg-table-header" />;
                          const preset = presetAt(day, period.id, lessonIndex);
                          const blocked = presetBlocked(day, period.id, lessonIndex);
                          return <td key={day} className="border border-table-divider p-1">
                            <button type="button" disabled={blocked} onClick={() => cyclePreset(day, period.id, lessonIndex)}
                              onContextMenu={(event) => { if (blocked) return; event.preventDefault(); setPresetMenu({ x: Math.min(event.clientX, window.innerWidth - 155),
                                y: Math.min(event.clientY, window.innerHeight - 205), weekday: day, periodTypeId: period.id, lessonIndex }); }}
                              title={blocked ? '此时段已设为免任课' : preset.inherited ? '继承上级范围；右键可直接设置' : '单击切换，右键直接设置'}
                              aria-label={WEEKDAY_NAMES[day - 1] + period.name + '第' + lessonIndex + '节 ' + (blocked ? '免任课' : PRESET_LABELS[preset.value])}
                              className={'h-8 w-full rounded-[5px] text-[11px] transition-colors ' +
                                (blocked ? 'cursor-not-allowed bg-table-header text-ink-secondary' : preset.value === 'auto' ?
                                  'text-ink-secondary hover:bg-selection' : preset.value === 'prefer' ?
                                  'bg-selection text-primary' : preset.value === 'must' ?
                                  'bg-primary text-white' : 'bg-destructive/10 text-destructive') +
                                (preset.inherited ? ' opacity-60' : '')}>
                              {blocked ? '免任课' : PRESET_LABELS[preset.value]}</button>
                          </td>;
                        })}</tr>)}</tbody>
                    </table>
                  </div>
                  <div className="border-t border-border pt-3">
                    <div className="mb-2 flex justify-between text-[12px] font-semibold text-ink-secondary"><span>当前学科全部预设</span><span>{allSubjectPresets.length + removedSubjectPresets.length} 项</span></div>
                    {allSubjectPresets.length + removedSubjectPresets.length ? [...allSubjectPresets, ...removedSubjectPresets].map((row) => {
                      const deleted = removedSubjectPresets.some((item) => item.id === row.id);
                      return <div key={row.id} className="flex items-center gap-2 border-b border-border py-1.5 text-[12px]">
                      <div className="min-w-0 flex-1"><p className={"truncate font-medium text-ink " + (deleted ? "line-through" : "")}>{scopeLabel(row.scopeType, row.scopeId, row.stageId)}{deleted && <span className="ml-2 text-destructive">待删除</span>}</p>
                        <p className="truncate text-ink-secondary">{WEEKDAY_NAMES[row.weekday - 1]} · {routinesByStage[row.stageId]?.periodTypes.find((period) => period.id === row.periodTypeId)?.name ?? '课节'} 第{row.lessonIndex}节 · {PRESET_LABELS[row.value]}</p></div>
                      <button type="button" aria-label={deleted ? '撤销删除预设' : '删除预设'} onClick={() => deleted ? restorePreset(row) : removePreset(row)}
                        className="rounded p-1.5 text-ink-secondary hover:bg-table-header hover:text-destructive">{deleted ? <RotateCcw className="h-4 w-4" /> : <Trash2 className="h-4 w-4" />}</button>
                    </div>; }) : <p className="py-4 text-center text-[12px] text-ink-secondary">暂无预设</p>}
                  </div>
                </>;
              })()}
              {advancedTab === 'constraints' && (() => {
                const weekdays = routinesByStage[presetStageId]?.teachingDays.filter((day) => day.isTeachingDay).map((day) => day.weekday).sort() ?? [];
                const constraintInput = (day: number | null, field: ConstraintField, compact = false) => {
                  const local = currentConstraints.find((row) => row.weekday === day)?.[field];
                  const effective = inheritedConstraint(day, field);
                  return <Input key={presetScopeId + ':' + day + ':' + field} inputMode="numeric" pattern="[0-9]*"
                    aria-label={(day === null ? '每天' : WEEKDAY_NAMES[day - 1]) + field}
                    value={local ?? ''} placeholder={effective === null ? '' : String(effective)}
                    onChange={(event) => updateConstraint(day, field, event.target.value)}
                    className={'h-8 min-w-0 rounded-[5px] px-1 text-center border-none text-[12px] ' + (compact ? 'w-7 shrink-0 border-0 bg-transparent' : 'bg-transparent')} />;
                };
                return <>
                  <p className="text-[12px] leading-5 text-ink-secondary">左侧“每天”值应用于所有上课日；星期输入覆盖该日对应字段。每日连堂按同一天、同一时段内的相邻双节组数计算，连续 3 节计 2 次。每周连堂上下限为全周总量，单双周共用。空白继承上级范围或“每天”设置，0 表示不设下限 / 不允许上限。</p>
                  <div className="overflow-x-auto">
                    <table className="w-full min-w-[570px] table-fixed border-collapse text-[12px]">
                      <thead><tr className="bg-table-header"><th className="w-[88px] border border-table-divider px-2 py-2 text-left text-ink-secondary">每天</th>
                        {weekdays.map((day) => <th key={day} className="border border-table-divider py-2 text-ink-secondary">{WEEKDAY_NAMES[day - 1]}</th>)}</tr></thead>
                      <tbody>{DAILY_CONSTRAINT_ROWS.map(([field, label, unit]) => <tr key={field} className="">
                        <th className="border border-table-divider px-1 text-left text-[11px] font-medium text-ink-secondary">
                          <div className="flex items-center gap-0.5"><span className="w-9 shrink-0 whitespace-nowrap text-[10px]">{label}</span>{constraintInput(null, field, true)}<span className="shrink-0">{unit}</span></div>
                        </th>
                        {weekdays.map((day) => <td key={day} className="border border-table-divider p-1">{constraintInput(day, field)}</td>)}
                      </tr>)}</tbody>
                    </table>
                  </div>
                  <div className="flex flex-wrap items-center gap-2 border-y border-border py-2 text-[12px]"><span className="font-semibold text-ink-secondary">每周连堂组数</span>
                    <span>最少</span><div className="w-20">{constraintInput(null, 'minimumWeeklyConsecutivePairs')}</div>
                    <span>最多</span><div className="w-20">{constraintInput(null, 'maximumWeeklyConsecutivePairs')}</div>
                    <span className="text-ink-secondary">同一天、同一时段的相邻双节数</span></div>
                  <div>
                    <div className="mb-2 flex justify-between text-[12px] font-semibold text-ink-secondary"><span>当前科目全部课节限制</span><span>{allSubjectConstraints.length + removedSubjectConstraints.length} 项</span></div>
                    {allSubjectConstraints.length + removedSubjectConstraints.length ? [...allSubjectConstraints, ...removedSubjectConstraints].map((row) => {
                      const deleted = removedSubjectConstraints.some((item) => item.id === row.id);
                      return <div key={row.id} className="flex items-center gap-2 border-b border-border py-1.5 text-[12px]">
                      <div className="min-w-0 flex-1"><p className={"truncate font-medium text-ink " + (deleted ? "line-through" : "")}>{scopeLabel(row.scopeType, row.scopeId, row.stageId)}{deleted && <span className="ml-2 text-destructive">待删除</span>}</p>
                        <p className="truncate text-ink-secondary">{row.weekday ? WEEKDAY_NAMES[row.weekday - 1] : '每天'} · {[
                          row.minimumDailyLessons !== null ? '最少' + row.minimumDailyLessons + '节' : '',
                          row.maximumDailyLessons !== null ? '最多' + row.maximumDailyLessons + '节' : '',
                          row.minimumDailyConsecutivePairs !== null ? '最少连堂' + row.minimumDailyConsecutivePairs : '',
                          row.maximumDailyConsecutivePairs !== null ? '最多连堂' + row.maximumDailyConsecutivePairs : '',
                          row.minimumWeeklyConsecutivePairs !== null ? '每周最少' + row.minimumWeeklyConsecutivePairs : '',
                          row.maximumWeeklyConsecutivePairs !== null ? '每周最多' + row.maximumWeeklyConsecutivePairs : '',
                        ].filter(Boolean).join(' · ')}</p></div>
                      <button type="button" aria-label={deleted ? '撤销删除课节限制' : '删除课节限制'} onClick={() => deleted ? restoreConstraint(row) : removeConstraint(row)}
                        className="rounded p-1.5 text-ink-secondary hover:bg-table-header hover:text-destructive">{deleted ? <RotateCcw className="h-4 w-4" /> : <Trash2 className="h-4 w-4" />}</button>
                    </div>; }) : <p className="py-4 text-center text-[12px] text-ink-secondary">暂无课节限制</p>}
                  </div>
                </>;
              })()}
              {advancedTab === 'rooms' && (() => {
                const chain: Array<[ScopeType, string]> = [[presetScopeType, presetScopeId]];
                if (presetScopeType === 'class') {
                  const gradeId = classes.find((item) => item.id === presetScopeId)?.gradeId;
                  if (gradeId) chain.push(['grade', gradeId]);
                }
                if (presetScopeType !== 'stage') chain.push(['stage', presetStageId]);
                const effectiveRoom = chain.map(([type, id]) => {
                  const key = presetScopeKey(presetSubjectId ?? '', type, id, presetStageId);
                  return roomDrafts[key] ? roomDrafts[key].assignment : subjectRoomAssignments.find((row) =>
                    row.subjectId === presetSubjectId && row.scopeType === type && row.scopeId === id && row.stageId === presetStageId);
                }).find((item) => item != null);
                const effectiveLimit = chain.map(([type, id]) => {
                  const key = presetScopeKey(presetSubjectId ?? '', type, id, presetStageId);
                  return roomDrafts[key] ? roomDrafts[key].limit : subjectParallelLimits.find((row) =>
                    row.subjectId === presetSubjectId && row.scopeType === type && row.scopeId === id && row.stageId === presetStageId);
                }).find((item) => item != null);
                return <>
                  <p className="text-[12px] leading-5 text-ink-secondary">行课场室按学段、年级、班级逐级生效；可在当前范围覆盖上级设置。修改后点击“保存设置”暂存。</p>
                  <div className="space-y-3 rounded-[10px] border border-border p-4">
                    <div className="flex flex-wrap items-start justify-between gap-2"><div><h3 className="font-semibold text-ink">行课场室</h3>
                      <p className="mt-1 text-[12px] text-ink-secondary">指定该范围上课使用的场室；选择“不设场室”可覆盖上级设置。</p></div>
                      <button type="button" onClick={() => { closePreset(true); setSelectedSection('publicRooms'); }} className="text-[12px] text-primary hover:underline">管理公共场室</button></div>
                    <div className="flex flex-wrap items-center gap-2"><span className="w-24 text-[12px] font-medium text-ink">选择场室</span>
                      <div className="min-w-[180px] max-w-[360px] flex-1"><Select value={currentRoomSettings.assignment === null ? 'inherit' : currentRoomSettings.assignment.roomId ?? 'none'} onValueChange={updateRoom}>
                        <SelectTrigger><SelectValue /></SelectTrigger><SelectContent><SelectItem value="inherit">继承上级场室</SelectItem><SelectItem value="none">不设场室</SelectItem>
                          {publicRooms.map((room) => <SelectItem key={room.id} value={room.id}>{room.name}</SelectItem>)}</SelectContent></Select></div>
                      <Button variant="ghost" size="sm" disabled={currentRoomSettings.assignment === null} onClick={() => updateRoom('inherit')}>重置为继承上级</Button>
                    </div>
                    <div className="rounded-[8px] bg-table-header px-3 py-2 text-[12px] text-ink-secondary">当前生效场室　<strong className="text-ink">{effectiveRoom?.roomId == null ? '不设场室' : publicRooms.find((item) => item.id === effectiveRoom.roomId)?.name ?? '场室已删除，请重置'}</strong>
                      <span className="ml-2">来源：{effectiveRoom ? scopeLabel(effectiveRoom.scopeType, effectiveRoom.scopeId, effectiveRoom.stageId) : '默认设置'}</span></div>
                  </div>
                  <div className="space-y-3 rounded-[10px] border border-border p-4">
                    <h3 className="font-semibold text-ink">同科目同时上课上限</h3>
                    <p className="text-[12px] text-ink-secondary">限制同一时段可安排该科目的班级数；年级设置会覆盖学段设置。</p>
                    {presetScopeType === 'class' ? <div className="rounded-[8px] bg-table-header px-3 py-2 text-[12px]">当前班级生效上限：{effectiveLimit?.maxParallelLessons ?? '不限'} 班</div> :
                      <div className="flex flex-wrap items-center gap-2"><label htmlFor="subject-parallel-limit" className="w-36 text-[12px] font-medium text-ink">最多同时上课班级数</label>
                        <Input id="subject-parallel-limit" inputMode="numeric" pattern="[0-9]*" value={currentRoomSettings.limit?.maxParallelLessons ?? ''} onChange={(event) => updateParallel(event.target.value)}
                          placeholder={effectiveLimit ? String(effectiveLimit.maxParallelLessons) : '不限'} className="w-32" />
                        <span className="text-[12px] text-ink-secondary">班</span>
                        <Button variant="ghost" size="sm" disabled={currentRoomSettings.limit === null} onClick={() => updateParallel('')}>重置为继承上级</Button>
                      </div>}
                    <p className="text-[12px] text-ink-secondary">当前生效：{effectiveLimit?.maxParallelLessons ?? '不限'} 班；来源：{effectiveLimit ? scopeLabel(effectiveLimit.scopeType, effectiveLimit.scopeId, effectiveLimit.stageId) : '默认不限'}</p>
                  </div>
                </>;
              })()}
            </div>
          </div>
        </div>
        {advancedError && <p role="alert" className="mx-6 rounded-[7px] bg-destructive/10 px-3 py-2 text-[12px] text-destructive">{advancedError}</p>}
        {advancedWarnings.length > 0 && <div role="alert" className="mx-6 max-h-24 overflow-y-auto rounded-[7px] bg-warning-surface px-3 py-2 text-[12px] text-warning">
          <p className="font-semibold">一定排超出需求节数，请核对后继续保存</p>
          {advancedWarnings.map((warning) => <p key={warning}>· {warning}</p>)}
        </div>}
        <DialogFooter className="shrink-0 px-6 pb-5 pt-3"><Button variant="ghost" onClick={() => closePreset(false)}>取消</Button>
          <Button onClick={validateAndClosePreset}>{advancedWarnings.length ? '继续保存' : '保存设置'}</Button></DialogFooter>
      </DialogContent>
    </Dialog>
    {presetMenu && createPortal(<div data-preset-menu role="menu" aria-label="课节预设快捷设置" style={{ left: Math.max(8, presetMenu.x), top: Math.max(8, presetMenu.y) }}
      className="pointer-events-auto fixed z-[70] w-[146px] rounded-[8px] border border-border bg-surface p-1 shadow-lg">
      {[...PRESET_VALUES, null].map((value) => <button key={value ?? 'clear'} type="button" role="menuitem"
        onClick={() => { setPresetValue(presetMenu.weekday, presetMenu.periodTypeId, presetMenu.lessonIndex, value); setPresetMenu(null); }}
        className="block w-full rounded-[5px] px-2 py-1.5 text-left text-[12px] hover:bg-table-header">
        {value === null ? '清除本级预设' : PRESET_LABELS[value]}</button>)}
    </div>, document.body)}
    {contextMenu && createPortal(<div data-subject-matrix-menu role="menu" aria-label="科目节数快捷操作"
      style={{ left: Math.max(8, contextMenu.x), top: Math.max(8, contextMenu.y) }}
      className="fixed z-[80] w-[188px] rounded-[10px] border border-border bg-surface p-1 shadow-lg">
      {[
        { label: '复制', icon: Copy, action: () => copyMatrix() },
        { label: '粘贴', icon: ClipboardPaste, action: () => void pasteFromClipboard() },
        { label: '逐班编辑', icon: Pencil, action: () => {
          const [subjectId, gradeId] = contextMenu.key.split(':');
          openGradeEditor(subjectId, gradeId);
        } },
        { label: `统一设置${selectedMatrixCells.length > 1 ? ` ${selectedMatrixCells.length} 格` : ''}`,
          icon: Check, action: openBatchEditor },
        { label: '清空所选格', icon: Eraser, action: () => clearMatrixSelection() },
      ].map((item, index) => <button key={item.label} type="button" role="menuitem" autoFocus={index === 0}
        onClick={() => { setContextMenu(null); item.action(); }}
        className="flex w-full items-center gap-2 rounded-[7px] px-2.5 py-2 text-left text-[12.5px] text-ink hover:bg-table-header">
        <item.icon aria-hidden="true" className="h-4 w-4 text-ink-secondary" />{item.label}</button>)}
    </div>, document.body)}
    {subjectMenu && createPortal(<div data-subject-name-menu role="menu" aria-label="科目快捷操作"
      style={{ left: Math.max(8, subjectMenu.x), top: Math.max(8, subjectMenu.y) }}
      className="fixed z-[80] w-[164px] rounded-[10px] border border-border bg-surface p-1 shadow-lg">
      {[
        { label: '编辑科目', icon: Pencil, action: () => {
          const subject = activeSubjects.find((item) => item.id === subjectMenu.subjectId);
          if (subject) beginSubjectDialog(subject);
        } },
        { label: '删除科目', icon: Trash2, action: () => {
          const subject = activeSubjects.find((item) => item.id === subjectMenu.subjectId);
          if (subject) setDeleteTarget(subject);
        } },
      ].map((item, index) => <button key={item.label} type="button" role="menuitem" autoFocus={index === 0}
        onClick={() => { setSubjectMenu(null); item.action(); }}
        className={`flex w-full items-center gap-2 rounded-[7px] px-2.5 py-2 text-left text-[12.5px] hover:bg-table-header ${index === 1 ? 'text-destructive' : 'text-ink'}`}>
        <item.icon aria-hidden="true" className="h-4 w-4" />{item.label}</button>)}
    </div>, document.body)}
  </section>;
};
