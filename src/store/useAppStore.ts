/**
 * 课集 (ClassSet) 全局应用状态与主题持久化 Store (阶段 3 扩充版)
 * 支持：
 * 1. 学期新建、编辑、复制 (cloneTerm)、删除及教学日历例外 (calendarExceptions) 事务保存
 * 2. 学段新增、改名、删除；年级批量新增、改名/跨学段移动、上下排序、删除
 * 3. 班级新增、内联改名、上下排序、批量模板填充与一键撤销上次填充 (undoLastClassFill)
 */

import { create } from 'zustand';
import {
  AcademicTerm,
  AppSection,
  CalendarException,
  ClassGroup,
  FreeSlot,
  GradeGroup,
  PublicRoom,
  SchoolStage,
  ScheduleItem,
  StageRoutine,
  Subject,
  SubjectPairing,
  SubjectPreset,
  SubjectLessonConstraint,
  SubjectRoomAssignment,
  SubjectParallelLimit,
  SubjectRequirement,
  ScopeType,
  Teacher,
  TemporaryCourseAdjustment,
  WorkbenchSummary,
} from '../domain/models';
import { schoolRepository } from '../repository/schoolRepository';
import { AppAppearanceMode, AppPalette } from '../styles/subjectColors';

const APPEARANCE_STORAGE_KEY = 'classset_appearance_v1';
const APP_SECTIONS: readonly AppSection[] = [
  'workbench',
  'terms',
  'classes',
  'routines',
  'publicRooms',
  'subjects',
  'teachers',
  'scheduling',
  'supervision',
  'temporaryAdjustments',
];

function getSectionFromLocation(): AppSection {
  if (typeof window === 'undefined') return 'workbench';
  const route = window.location.hash.slice(1).split('/').filter(Boolean)[0];
  return APP_SECTIONS.find((section) => section === route) ?? 'workbench';
}

export interface ClassFillUndoEntry {
  before: ClassGroup;
  afterName: string;
}

interface AppState {
  initialized: boolean;
  runtimeMode: 'tauri-desktop' | 'web-browser';
  palette: AppPalette;
  mode: AppAppearanceMode;
  resolvedDark: boolean;
  sidebarExpanded: boolean;
  selectedSection: AppSection;
  schoolName: string;
  activeTermId: string | null;
  terms: AcademicTerm[];
  stages: SchoolStage[];
  grades: GradeGroup[];
  classes: ClassGroup[];
  routinesByStage: Record<string, StageRoutine>;
  routineDraftsByStage: Record<string, StageRoutine>;
  freeSlotsByStage: Record<string, FreeSlot[]>;
  freeSlotDraftsByTerm: Record<string, Record<string, FreeSlot | null>>;
  freeSlotBaselinesByTerm: Record<string, Record<string, FreeSlot | null>>;
  calendarExceptions: CalendarException[];
  subjects: Subject[];
  subjectRequirements: SubjectRequirement[];
  subjectPairings: SubjectPairing[];
  subjectPresets: SubjectPreset[];
  subjectLessonConstraints: SubjectLessonConstraint[];
  subjectRoomAssignments: SubjectRoomAssignment[];
  subjectParallelLimits: SubjectParallelLimit[];
  subjectDraftDirty: boolean;
  teachers: Teacher[];
  publicRooms: PublicRoom[];
  adjustments: TemporaryCourseAdjustment[];
  summary: WorkbenchSummary | null;
  lastPersistedAt: Date | null;
  lastClassFillUndo: ClassFillUndoEntry[] | null;

  bootstrap: () => Promise<void>;
  refreshTermData: (termId: string) => Promise<void>;
  setPalette: (palette: AppPalette) => void;
  setMode: (mode: AppAppearanceMode) => void;
  cycleThemeMode: () => void;
  setSidebarExpanded: (expanded: boolean) => void;
  toggleSidebar: () => void;
  setSelectedSection: (section: AppSection) => void;
  setSubjectDraftDirty: (dirty: boolean) => void;
  selectTerm: (termId: string) => Promise<void>;
  updateSchoolName: (name: string) => Promise<void>;

  /* 初始设置与学期日历操作 */
  completeInitialSetup: (schoolName: string, term: AcademicTerm) => Promise<void>;
  saveOrCloneTerm: (term: AcademicTerm, cloneSourceTermId?: string | null) => Promise<void>;
  removeTerm: (termId: string) => Promise<void>;
  saveWeekCalendarExceptions: (
    upserts: CalendarException[],
    deleteIds: string[]
  ) => Promise<void>;
  loadCalendarExceptionsForTerm: (termId: string) => Promise<CalendarException[]>;

  /* 班级与学段操作 */
  addOrUpdateStage: (stage: SchoolStage) => Promise<void>;
  removeStage: (stageId: string) => Promise<void>;
  addOrUpdateGrades: (grades: GradeGroup[]) => Promise<void>;
  removeGrade: (gradeId: string) => Promise<void>;
  addOrUpdateClasses: (classes: ClassGroup[]) => Promise<void>;
  removeClass: (classId: string) => Promise<void>;
  setRoutineDraft: (routine: StageRoutine) => void;
  discardRoutineDraft: (stageId: string) => void;
  discardTermDrafts: (termId: string) => void;
  restoreTermDraftSnapshot: (
    termId: string,
    stageIds: string[],
    routineDrafts: Record<string, StageRoutine>,
    freeSlotDrafts: Record<string, FreeSlot | null>,
    freeSlotBaselines: Record<string, FreeSlot | null>
  ) => void;
  saveStageRoutine: (routine: StageRoutine) => Promise<void>;
  loadFreeSlotsForStages: (stageIds: string[]) => Promise<void>;
  setFreeSlotDraft: (
    termId: string,
    slotId: string,
    slot: FreeSlot | null
  ) => void;
  loadScheduleItems: (termId: string) => Promise<ScheduleItem[]>;
  applyBatchClassFill: (
    renames: Array<{ target: ClassGroup; newName: string }>
  ) => Promise<{ updatedCount: number; skippedCount: number }>;
  undoBatchClassFill: () => Promise<number>;

  saveSubjectChanges: (changes: {
    upserts: Subject[];
    deletedIds: string[];
    requirementsByGrade: Record<string, SubjectRequirement[]>;
    pairingsByClass: Record<string, SubjectPairing[]>;
    presetScopes: Array<{ subjectId: string; scopeType: ScopeType; scopeId: string; stageId: string; rows: SubjectPreset[] }>;
    constraintScopes: Array<{ subjectId: string; scopeType: ScopeType; scopeId: string; stageId: string; rows: SubjectLessonConstraint[] }>;
    roomScopes: Array<{ subjectId: string; scopeType: ScopeType; scopeId: string; stageId: string; assignment: SubjectRoomAssignment | null; limit: SubjectParallelLimit | null }>;
  }) => Promise<void>;

  /* 公共场室操作 */
  savePublicRooms: (rooms: PublicRoom[]) => Promise<void>;
  deletePublicRoom: (roomId: string) => Promise<void>;

  /* 级联门控调试开关 */
  toggleCascadeStep: (
    flag: 'routineDone' | 'subjectLessonsReady' | 'teacherAssignmentsReady' | 'hasSchedule'
  ) => Promise<void>;
}

function loadSavedAppearance(): { palette: AppPalette; mode: AppAppearanceMode } {
  try {
    const raw = localStorage.getItem(APPEARANCE_STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      const palette: AppPalette =
        parsed.palette === 'sky' || parsed.palette === 'teal' || parsed.palette === 'cloud'
          ? parsed.palette
          : 'sky';
      const mode: AppAppearanceMode =
        parsed.mode === 'system' || parsed.mode === 'light' || parsed.mode === 'dark'
          ? parsed.mode
          : 'system';
      return { palette, mode };
    }
  } catch {
    // 安全回退到默认晴空蓝 + 跟随系统
  }
  return { palette: 'sky', mode: 'system' };
}

function resolveIsDark(mode: AppAppearanceMode): boolean {
  if (mode === 'dark') return true;
  if (mode === 'light') return false;
  if (typeof window !== 'undefined' && window.matchMedia) {
    return window.matchMedia('(prefers-color-scheme: dark)').matches;
  }
  return false;
}

function sameFreeSlot(a: FreeSlot | null | undefined, b: FreeSlot | null | undefined): boolean {
  if (!a || !b) return a === b;
  return (
    a.id === b.id &&
    a.scopeType === b.scopeType &&
    a.scopeId === b.scopeId &&
    a.stageId === b.stageId &&
    a.periodTypeId === b.periodTypeId &&
    a.weekday === b.weekday &&
    a.lessonIndex === b.lessonIndex &&
    a.label === b.label
  );
}

function routineForPersistence(routine: StageRoutine): StageRoutine {
  const lessonCounts = new Map(
    routine.periodTypes.map((period) => [period.id, period.defaultLessonCount])
  );
  const lessonTimes = routine.lessonTimes.filter(
    (time) => time.lessonIndex <= (lessonCounts.get(time.periodTypeId) ?? -1)
  );
  const lessonIds = new Set(lessonTimes.map((time) => time.id));
  return {
    ...routine,
    lessonTimes,
    commonPeriods: routine.commonPeriods?.map((period) => {
      const anchor = period.insertAfterLessonId;
      if (!anchor || lessonIds.has(anchor)) return period;
      const periodType = routine.periodTypes.find((item) => anchor.startsWith(`${item.id}_`));
      const lastLesson = periodType
        ? lessonTimes
            .filter((time) => time.periodTypeId === periodType.id)
            .sort((a, b) => b.lessonIndex - a.lessonIndex)[0]
        : undefined;
      return { ...period, insertAfterLessonId: lastLesson?.id ?? null };
    }),
  };
}

export function applyAppearanceToDom(palette: AppPalette, mode: AppAppearanceMode): boolean {
  const isDark = resolveIsDark(mode);
  if (typeof document !== 'undefined') {
    const root = document.documentElement;
    root.setAttribute('data-palette', palette);
    root.setAttribute('data-theme-mode', isDark ? 'dark' : 'light');
  }
  try {
    localStorage.setItem(APPEARANCE_STORAGE_KEY, JSON.stringify({ palette, mode }));
  } catch {
    // ignore
  }
  return isDark;
}

const initialAppearance = loadSavedAppearance();
const initialDark = applyAppearanceToDom(initialAppearance.palette, initialAppearance.mode);

export const useAppStore = create<AppState>((set, get) => ({
  initialized: false,
  runtimeMode: schoolRepository.runtimeMode,
  palette: initialAppearance.palette,
  mode: initialAppearance.mode,
  resolvedDark: initialDark,
  sidebarExpanded: typeof window !== 'undefined' ? window.innerWidth >= 1080 : true,
  selectedSection: getSectionFromLocation(),
  schoolName: '',
  activeTermId: null,
  terms: [],
  stages: [],
  grades: [],
  classes: [],
  routinesByStage: {},
  routineDraftsByStage: {},
  freeSlotsByStage: {},
  freeSlotDraftsByTerm: {},
  freeSlotBaselinesByTerm: {},
  calendarExceptions: [],
  subjects: [],
  subjectRequirements: [],
  subjectPairings: [],
  subjectPresets: [],
  subjectLessonConstraints: [],
  subjectRoomAssignments: [],
  subjectParallelLimits: [],
  subjectDraftDirty: false,
  teachers: [],
  publicRooms: [],
  adjustments: [],
  summary: null,
  lastPersistedAt: null,
  lastClassFillUndo: null,

  refreshTermData: async (termId: string) => {
    const [
      stages,
      grades,
      classes,
      calendarExceptions,
      subjects,
      subjectRequirements,
      subjectPairings,
      subjectPresets,
      subjectLessonConstraints,
      roomSettings,
      adjustments,
      summary,
    ] = await Promise.all([
      schoolRepository.loadStages(termId),
      schoolRepository.loadGradesForTerm(termId),
      schoolRepository.loadClassesForTerm(termId),
      schoolRepository.loadCalendarExceptions(termId),
      schoolRepository.loadSubjects(termId),
      schoolRepository.loadSubjectRequirements(termId),
      schoolRepository.loadSubjectPairings(termId),
      schoolRepository.loadSubjectPresets(termId),
      schoolRepository.loadSubjectLessonConstraints(termId),
      schoolRepository.loadSubjectRoomSettings(termId),
      schoolRepository.loadTemporaryAdjustments(termId),
      schoolRepository.loadWorkbenchSummary(termId),
    ]);

    const routinesByStage: Record<string, StageRoutine> = {};
    await Promise.all(
      stages.map(async (st) => {
        routinesByStage[st.id] = await schoolRepository.loadStageRoutine(st.id);
      })
    );

    set({
      stages,
      grades,
      classes,
      routinesByStage,
      calendarExceptions,
      subjects,
      subjectRequirements,
      subjectPairings,
      subjectPresets,
      subjectLessonConstraints,
      subjectRoomAssignments: roomSettings.assignments,
      subjectParallelLimits: roomSettings.limits,
      adjustments,
      summary,
      lastPersistedAt: new Date(),
    });
  },

  bootstrap: async () => {
    await schoolRepository.initialize();
    const [schoolName, terms, savedTermId, teachers, publicRooms] = await Promise.all([
      schoolRepository.loadSchoolName(),
      schoolRepository.loadTerms(),
      schoolRepository.loadActiveTermId(),
      schoolRepository.loadTeachers(),
      schoolRepository.loadPublicRooms(),
    ]);

    const activeTermId =
      terms.find((t) => t.id === savedTermId)?.id ?? terms[0]?.id ?? null;

    set({
      initialized: true,
      runtimeMode: schoolRepository.runtimeMode,
      schoolName,
      terms,
      activeTermId,
      teachers,
      publicRooms,
    });

    if (activeTermId) {
      await get().refreshTermData(activeTermId);
    }
  },

  setPalette: (palette) => {
    const isDark = applyAppearanceToDom(palette, get().mode);
    set({ palette, resolvedDark: isDark });
  },

  setMode: (mode) => {
    const isDark = applyAppearanceToDom(get().palette, mode);
    set({ mode, resolvedDark: isDark });
  },

  cycleThemeMode: () => {
    const current = get().mode;
    const next: AppAppearanceMode =
      current === 'light' ? 'dark' : current === 'dark' ? 'system' : 'light';
    get().setMode(next);
  },

  setSidebarExpanded: (expanded) => set({ sidebarExpanded: expanded }),
  toggleSidebar: () => set((s) => ({ sidebarExpanded: !s.sidebarExpanded })),

  setSelectedSection: (section) => {
    if (get().selectedSection === 'subjects' && section !== 'subjects' && get().subjectDraftDirty) {
      if (!window.confirm('科目节数有未保存的修改，确定离开并放弃修改吗？')) {
        window.location.hash = '#/subjects';
        return;
      }
      set({ subjectDraftDirty: false });
    }
    if (typeof window !== 'undefined') {
      const nextHash = `#/${section}`;
      if (window.location.hash !== nextHash) window.location.hash = nextHash;
    }
    set({ selectedSection: section });
  },

  setSubjectDraftDirty: (dirty) => set({ subjectDraftDirty: dirty }),

  selectTerm: async (termId) => {
    await schoolRepository.saveActiveTermId(termId);
    set({ activeTermId: termId, lastClassFillUndo: null });
    await get().refreshTermData(termId);
  },

  updateSchoolName: async (name) => {
    await schoolRepository.saveSchoolName(name);
    set({ schoolName: name.trim(), lastPersistedAt: new Date() });
  },

  completeInitialSetup: async (schoolName, term) => {
    const trimmedSchoolName = schoolName.trim();
    await schoolRepository.saveSchoolName(trimmedSchoolName);
    await schoolRepository.saveTerm(term);
    await schoolRepository.saveActiveTermId(term.id);
    const terms = await schoolRepository.loadTerms();
    if (typeof window !== 'undefined' && window.location.hash !== '#/workbench') {
      window.location.hash = '#/workbench';
    }
    set({
      schoolName: trimmedSchoolName,
      terms,
      activeTermId: term.id,
      selectedSection: 'workbench',
      lastClassFillUndo: null,
    });
    await get().refreshTermData(term.id);
  },

  saveOrCloneTerm: async (term, cloneSourceTermId) => {
    if (cloneSourceTermId) {
      await schoolRepository.cloneTerm(cloneSourceTermId, term);
    } else {
      await schoolRepository.saveTerm(term);
    }
    await schoolRepository.saveActiveTermId(term.id);
    const terms = await schoolRepository.loadTerms();
    set({ terms, activeTermId: term.id, lastClassFillUndo: null });
    await get().refreshTermData(term.id);
  },

  removeTerm: async (termId) => {
    const { activeTermId } = get();
    if (termId === activeTermId) return;
    await schoolRepository.deleteTerm(termId);
    const terms = await schoolRepository.loadTerms();
    set({ terms, lastPersistedAt: new Date() });
  },

  saveWeekCalendarExceptions: async (upserts, deleteIds) => {
    const { activeTermId } = get();
    if (!activeTermId) return;
    await schoolRepository.saveCalendarExceptions({
      termId: activeTermId,
      upserts,
      deleteIds,
    });
    const calendarExceptions = await schoolRepository.loadCalendarExceptions(activeTermId);
    set({ calendarExceptions, lastPersistedAt: new Date() });
  },

  loadCalendarExceptionsForTerm: (termId) =>
    schoolRepository.loadCalendarExceptions(termId),

  addOrUpdateStage: async (stage) => {
    const { activeTermId } = get();
    if (!activeTermId) return;
    await schoolRepository.saveStage(stage);
    await get().refreshTermData(activeTermId);
  },

  removeStage: async (stageId) => {
    const { activeTermId } = get();
    if (!activeTermId) return;
    await schoolRepository.deleteStage(stageId);
    await get().refreshTermData(activeTermId);
  },

  addOrUpdateGrades: async (grades) => {
    const { activeTermId } = get();
    if (!activeTermId) return;
    await schoolRepository.saveGrades(grades);
    await get().refreshTermData(activeTermId);
  },

  removeGrade: async (gradeId) => {
    const { activeTermId } = get();
    if (!activeTermId) return;
    await schoolRepository.deleteGrade(gradeId);
    await get().refreshTermData(activeTermId);
  },

  addOrUpdateClasses: async (classes) => {
    const { activeTermId } = get();
    if (!activeTermId) return;
    await schoolRepository.saveClasses(classes);
    await get().refreshTermData(activeTermId);
  },

  removeClass: async (classId) => {
    const { activeTermId } = get();
    if (!activeTermId) return;
    await schoolRepository.deleteClass(classId);
    await get().refreshTermData(activeTermId);
  },

  setRoutineDraft: (routine) =>
    set((state) => ({
      routineDraftsByStage: {
        ...state.routineDraftsByStage,
        [routine.stageId]: routine,
      },
    })),

  discardRoutineDraft: (stageId) =>
    set((state) => {
      const routineDraftsByStage = { ...state.routineDraftsByStage };
      delete routineDraftsByStage[stageId];
      return { routineDraftsByStage };
    }),

  discardTermDrafts: (termId) =>
    set((state) => {
      const routineDraftsByStage = { ...state.routineDraftsByStage };
      for (const stage of state.stages.filter((item) => item.termId === termId)) {
        delete routineDraftsByStage[stage.id];
      }
      const freeSlotDraftsByTerm = { ...state.freeSlotDraftsByTerm };
      const freeSlotBaselinesByTerm = { ...state.freeSlotBaselinesByTerm };
      delete freeSlotDraftsByTerm[termId];
      delete freeSlotBaselinesByTerm[termId];
      return { routineDraftsByStage, freeSlotDraftsByTerm, freeSlotBaselinesByTerm };
    }),

  restoreTermDraftSnapshot: (
    termId,
    stageIds,
    routineDrafts,
    freeSlotDrafts,
    freeSlotBaselines
  ) =>
    set((state) => {
      const routineDraftsByStage = { ...state.routineDraftsByStage };
      for (const stageId of stageIds) delete routineDraftsByStage[stageId];
      Object.assign(routineDraftsByStage, routineDrafts);

      const freeSlotDraftsByTerm = { ...state.freeSlotDraftsByTerm };
      const freeSlotBaselinesByTerm = { ...state.freeSlotBaselinesByTerm };
      if (Object.keys(freeSlotDrafts).length) freeSlotDraftsByTerm[termId] = freeSlotDrafts;
      else delete freeSlotDraftsByTerm[termId];
      if (Object.keys(freeSlotBaselines).length) {
        freeSlotBaselinesByTerm[termId] = freeSlotBaselines;
      } else {
        delete freeSlotBaselinesByTerm[termId];
      }
      return { routineDraftsByStage, freeSlotDraftsByTerm, freeSlotBaselinesByTerm };
    }),

  saveStageRoutine: async (routine) => {
    const initialState = get();
    const termId = initialState.stages.find((stage) => stage.id === routine.stageId)?.termId;
    const routinesToSave = new Map<string, StageRoutine>();
    if (termId) {
      for (const [stageId, draft] of Object.entries(initialState.routineDraftsByStage)) {
        if (initialState.stages.some((stage) => stage.id === stageId && stage.termId === termId)) {
          routinesToSave.set(stageId, draft);
        }
      }
    }
    routinesToSave.set(routine.stageId, routine);
    const persistedRoutines = [...routinesToSave.values()].map(routineForPersistence);
    for (const item of persistedRoutines) {
      await schoolRepository.saveStageRoutine(item);
    }
    const slotDrafts = termId ? initialState.freeSlotDraftsByTerm[termId] ?? {} : {};
    const slotBaselines = termId ? initialState.freeSlotBaselinesByTerm[termId] ?? {} : {};
    const slotUpserts = Object.values(slotDrafts).filter(
      (slot): slot is FreeSlot => slot !== null
    );
    const slotDeletes = Object.entries(slotDrafts)
      .filter(([slotId, slot]) => slot === null && slotBaselines[slotId] !== null)
      .map(([slotId]) => slotId);
    await schoolRepository.saveFreeSlotChanges(slotUpserts, slotDeletes);
    set((state) => {
      const routineDraftsByStage = { ...state.routineDraftsByStage };
      for (const item of persistedRoutines) delete routineDraftsByStage[item.stageId];
      const freeSlotsByStage = { ...state.freeSlotsByStage };
      for (const slotId of slotDeletes) {
        const stageId = slotBaselines[slotId]?.stageId;
        if (stageId) {
          freeSlotsByStage[stageId] = (freeSlotsByStage[stageId] ?? []).filter(
            (slot) => slot.id !== slotId
          );
        }
      }
      for (const slot of slotUpserts) {
        freeSlotsByStage[slot.stageId] = [
          ...(freeSlotsByStage[slot.stageId] ?? []).filter((item) => item.id !== slot.id),
          slot,
        ];
      }
      const routinesByStage = { ...state.routinesByStage };
      for (const item of persistedRoutines) routinesByStage[item.stageId] = item;
      const freeSlotDraftsByTerm = { ...state.freeSlotDraftsByTerm };
      const freeSlotBaselinesByTerm = { ...state.freeSlotBaselinesByTerm };
      if (termId) {
        delete freeSlotDraftsByTerm[termId];
        delete freeSlotBaselinesByTerm[termId];
      }
      return {
        routinesByStage,
        routineDraftsByStage,
        freeSlotsByStage,
        freeSlotDraftsByTerm,
        freeSlotBaselinesByTerm,
        lastPersistedAt: new Date(),
      };
    });
    if (termId) {
      try {
        const summary = await schoolRepository.loadWorkbenchSummary(termId);
        set({ summary });
      } catch {
        // 作息写入已成功；汇总刷新失败时保留现有汇总，避免误报保存失败。
      }
    }
  },

  loadFreeSlotsForStages: async (stageIds) => {
    const uniqueStageIds = [...new Set(stageIds)];
    const entries = await Promise.all(
      uniqueStageIds.map(async (stageId) => [
        stageId,
        await schoolRepository.loadFreeSlots(stageId),
      ] as const)
    );
    set((state) => ({
      freeSlotsByStage: {
        ...state.freeSlotsByStage,
        ...Object.fromEntries(entries),
      },
    }));
  },

  setFreeSlotDraft: (termId, slotId, slot) =>
    set((state) => {
      const freeSlotBaselinesByTerm = { ...state.freeSlotBaselinesByTerm };
      const freeSlotDraftsByTerm = { ...state.freeSlotDraftsByTerm };
      const baselines = { ...(freeSlotBaselinesByTerm[termId] ?? {}) };
      const drafts = { ...(freeSlotDraftsByTerm[termId] ?? {}) };
      if (!Object.prototype.hasOwnProperty.call(baselines, slotId)) {
        baselines[slotId] =
          Object.values(state.freeSlotsByStage)
            .flat()
            .find((item) => item.id === slotId) ?? null;
      }
      if (sameFreeSlot(baselines[slotId], slot)) {
        delete baselines[slotId];
        delete drafts[slotId];
      } else {
        drafts[slotId] = slot;
      }
      freeSlotBaselinesByTerm[termId] = baselines;
      freeSlotDraftsByTerm[termId] = drafts;
      return { freeSlotBaselinesByTerm, freeSlotDraftsByTerm };
    }),

  loadScheduleItems: (termId) => schoolRepository.loadScheduleItems(termId),

  applyBatchClassFill: async (renames) => {
    const { activeTermId, classes } = get();
    if (!activeTermId) return { updatedCount: 0, skippedCount: 0 };

    const existingByGrade = new Map<string, Set<string>>();
    const appliedByGrade = new Map<string, Set<string>>();
    for (const c of classes) {
      if (!existingByGrade.has(c.gradeId)) existingByGrade.set(c.gradeId, new Set());
    }

    const undoSnapshot: ClassFillUndoEntry[] = [];
    const updates: ClassGroup[] = [];
    let skippedCount = 0;

    for (const item of renames) {
      const name = item.newName.trim();
      if (name === item.target.name) continue;
      if (!appliedByGrade.has(item.target.gradeId)) {
        appliedByGrade.set(item.target.gradeId, new Set());
      }
      const gradeApplied = appliedByGrade.get(item.target.gradeId)!;
      if (!name || gradeApplied.has(name)) {
        skippedCount++;
        continue;
      }
      gradeApplied.add(name);
      undoSnapshot.push({ before: item.target, afterName: name });
      updates.push({
        ...item.target,
        name,
      });
    }

    if (updates.length > 0) {
      await schoolRepository.saveClasses(updates);
      await get().refreshTermData(activeTermId);
      set({ lastClassFillUndo: undoSnapshot });
    }
    return { updatedCount: updates.length, skippedCount };
  },

  undoBatchClassFill: async () => {
    const { activeTermId, lastClassFillUndo, classes } = get();
    if (!activeTermId || !lastClassFillUndo || lastClassFillUndo.length === 0) return 0;

    const currentById = new Map(classes.map((c) => [c.id, c]));
    const restores: ClassGroup[] = [];
    for (const entry of lastClassFillUndo) {
      const current = currentById.get(entry.before.id);
      if (current && current.name === entry.afterName) {
        restores.push(entry.before);
      }
    }

    if (restores.length > 0) {
      await schoolRepository.saveClasses(restores);
      await get().refreshTermData(activeTermId);
    }
    set({ lastClassFillUndo: null });
    return restores.length;
  },

  saveSubjectChanges: async (changes) => {
    const termId = get().activeTermId;
    if (!termId) throw new Error('请先选择学期');
    await schoolRepository.saveSubjectChanges(changes);
    await get().refreshTermData(termId);
  },

  savePublicRooms: async (rooms) => {
    await schoolRepository.savePublicRooms(rooms);
    const publicRooms = await schoolRepository.loadPublicRooms();
    set({ publicRooms, lastPersistedAt: new Date() });
    const { activeTermId } = get();
    if (activeTermId) {
      await get().refreshTermData(activeTermId);
    }
  },

  deletePublicRoom: async (roomId) => {
    await schoolRepository.deletePublicRoom(roomId);
    const publicRooms = await schoolRepository.loadPublicRooms();
    set({ publicRooms, lastPersistedAt: new Date() });
    const { activeTermId } = get();
    if (activeTermId) {
      await get().refreshTermData(activeTermId);
    }
  },

  toggleCascadeStep: async (flag) => {
    const { activeTermId, summary } = get();
    if (!activeTermId || !summary) return;
    const nextVal = !summary[flag];
    await schoolRepository.updateCascadeStageFlag(activeTermId, flag, nextVal);
    const updatedSummary = await schoolRepository.loadWorkbenchSummary(activeTermId);
    set({ summary: updatedSummary, lastPersistedAt: new Date() });
  },
}));
