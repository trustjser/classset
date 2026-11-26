import React, { lazy, memo, Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle,
  CalendarCheck,
  Check,
  Clock,
  GraduationCap,
  LoaderCircle,
  Plus,
  Redo2,
  RefreshCw,
  Save,
  Search,
  Settings2,
  Sparkles,
  Trash2,
  Undo2,
  Users,
  X,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import type { ScheduleData } from '@/domain/scheduling';
import type {
  SupervisionDraft,
  SupervisionMatchingPreferences,
  SupervisionPost,
  SupervisionVersion,
} from '@/domain/supervision';
import {
  SUPERVISION_BASE_POOL_ID,
  SUPERVISION_PREFERENCE_LABELS,
  defaultSupervisionMatchingPreferences,
  poolNameForPost,
  preferencesForPost,
} from '@/domain/supervision';
import { SupervisionAllocator } from '@/domain/supervisionAllocator';
import { SupervisionDraftHistory } from '@/domain/supervisionHistory';
import { SupervisionMatching } from '@/domain/supervisionMatching';
import { postErrors } from '@/domain/supervisionValidation';
import { schoolRepository } from '@/repository/schoolRepository';
import { useStickyToolbar } from '@/hooks/useStickyToolbar';
import { PostDialog } from './PostDialog';
import { PublishDialog } from './PublishDialog';
import { SupervisionWeekGrid } from './SupervisionWeekGrid';
import { TeacherPickerDialog } from './TeacherPickerDialog';
import { TeacherPoolDialog } from './TeacherPoolDialog';
import {
  MATCH_MODE_LABELS,
  MATCH_REQUIREMENT_LABELS,
  SupervisionMatchingPreferencesEditor,
} from './SupervisionMatchingPreferencesEditor';
import type { SupervisionMatchResponse } from './supervision-matching.worker';

interface SupervisionPageProps {
  termId: string | null;
}

const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const TeacherWorkloadChart = memo(lazy(() =>
  import('@/components/charts/TeacherWorkloadChart').then((module) => ({ default: module.TeacherWorkloadChart }))
));

interface SupervisionTeacherCardsProps {
  teachers: ScheduleData['teachers'];
  draft: SupervisionDraft | undefined;
  classMap: ReadonlyMap<string, string>;
}

const SupervisionTeacherCards = memo(function SupervisionTeacherCards({
  teachers, draft, classMap,
}: SupervisionTeacherCardsProps) {
  const postsByTeacher = new Map<string, SupervisionPost[]>();
  if (draft) {
    for (const post of draft.posts) {
      const teacherId = draft.assignments[post.id];
      if (!teacherId) continue;
      const posts = postsByTeacher.get(teacherId);
      if (posts) posts.push(post);
      else postsByTeacher.set(teacherId, [post]);
    }
  }

  return (
    <div className="grid grid-cols-3 gap-3">
      {teachers.map((teacher) => {
        const assignedPosts = postsByTeacher.get(teacher.id) ?? [];
        const weeklyLessons = assignedPosts.reduce(
          (sum, p) => sum + p.lessonIndices.length,
          0
        );
        const weeklyDays = new Set(assignedPosts.map((p) => p.weekday)).size;

        const rule = draft?.rules[teacher.id];
        const exceedsLessons = rule?.maxLessons != null && weeklyLessons > rule.maxLessons;
        const exceedsDays = rule?.maxDays != null && weeklyDays > rule.maxDays;

        return (
          <div
            key={teacher.id}
            className="rounded-xl bg-surface p-3 space-y-2.5 text-xs flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between mb-1.5">
                <span className="font-semibold text-sm text-ink">{teacher.name}</span>
                <div className="flex items-center gap-1.5">
                  <Badge
                    variant="secondary"
                    className={`text-[10px] h-5 px-1.5 ${
                      exceedsLessons || exceedsDays
                        ? 'bg-destructive/10 text-destructive'
                        : 'bg-canvas text-ink-secondary'
                    }`}
                  >
                    {weeklyLessons} 节 · {weeklyDays} 天
                  </Badge>
                </div>
              </div>

              {rule && (rule.maxLessons != null || rule.maxDays != null) && (
                <div className="text-[10px] text-ink-secondary mb-2">
                  上限: {rule.maxLessons != null ? `${rule.maxLessons}节` : '无限制'} /{' '}
                  {rule.maxDays != null ? `${rule.maxDays}天` : '无限制'}
                </div>
              )}

              {assignedPosts.length === 0 ? (
                <div className="text-ink-secondary/60 text-[11px] py-4 text-center">
                  本周无带班任务
                </div>
              ) : (
                <div className="space-y-1">
                  {assignedPosts.map((post) => {
                    const classNames = post.classIds
                      .map((id) => classMap.get(id) ?? id)
                      .join('、');
                    return (
                      <div
                        key={post.id}
                        className="p-1.5 rounded bg-canvas/50 border border-border/50 text-[11px] flex items-center justify-between"
                      >
                        <span className="text-ink">
                          {WEEKDAYS[post.weekday - 1]} · {post.name} ({classNames})
                        </span>
                        <span className="text-ink-secondary font-medium">
                          第{post.lessonIndices.join('、')}节
                        </span>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
});

const copyMatchingPreferences = (
  preferences: SupervisionMatchingPreferences
): SupervisionMatchingPreferences => ({
  ...preferences,
  order: [...preferences.order],
  enabled: [...preferences.enabled],
});

const sameMatchingPreferences = (
  left: SupervisionMatchingPreferences,
  right: SupervisionMatchingPreferences
): boolean =>
  left.mode === right.mode &&
  left.requirement === right.requirement &&
  left.order.length === right.order.length &&
  left.order.every((preference, index) => preference === right.order[index]) &&
  left.enabled.length === right.enabled.length &&
  left.enabled.every((preference, index) => preference === right.enabled[index]);

interface InitialSinglePostRules {
  poolId: string;
  preferenceMode: 'inherit' | 'custom';
  matchingPreferences: SupervisionMatchingPreferences;
}

export const SupervisionPage: React.FC<SupervisionPageProps> = ({ termId }) => {
  const toolbarRef = useStickyToolbar<HTMLDivElement>();
  const [loading, setLoading] = useState<boolean>(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [snapshot, setSnapshot] = useState<ScheduleData | null>(null);
  const [history, setHistory] = useState<SupervisionDraftHistory | null>(null);
  const [versions, setVersions] = useState<SupervisionVersion[]>([]);
  const [activeVersionDate, setActiveVersionDate] = useState<string | null>(null);

  // View & Filter states
  const [viewMode, setViewMode] = useState<'week' | 'class' | 'teacher'>('week');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [missingOnly, setMissingOnly] = useState<boolean>(false);
  const [unmetOnly, setUnmetOnly] = useState<boolean>(false);
  const [selectedPostIds, setSelectedPostIds] = useState<Set<string>>(new Set());

  // Dialogs
  const [postDialogOpen, setPostDialogOpen] = useState<boolean>(false);
  const [teacherPickerOpen, setTeacherPickerOpen] = useState<boolean>(false);
  const [activePostForTeacher, setActivePostForTeacher] = useState<SupervisionPost | null>(null);
  const [poolDialogOpen, setPoolDialogOpen] = useState<boolean>(false);
  const [publishDialogOpen, setPublishDialogOpen] = useState<boolean>(false);
  const [smartMatchDialogOpen, setSmartMatchDialogOpen] = useState<boolean>(false);
  const [smartMatching, setSmartMatching] = useState<boolean>(false);
  const smartMatchWorkerRef = useRef<Worker | null>(null);
  const resolveSmartMatchRef = useRef<((draft: SupervisionDraft | null) => void) | null>(null);
  const [bulkRulesDialogOpen, setBulkRulesDialogOpen] = useState<boolean>(false);
  const [bulkRulesTarget, setBulkRulesTarget] = useState<{
    postIds: string[];
    singlePost: boolean;
  } | null>(null);
  const [bulkRemoveDialogOpen, setBulkRemoveDialogOpen] = useState<boolean>(false);
  const [bulkPoolId, setBulkPoolId] = useState<string>('__keep__');
  const [bulkPreferenceMode, setBulkPreferenceMode] = useState<'keep' | 'inherit' | 'custom'>('keep');
  const [bulkMatchingPreferences, setBulkMatchingPreferences] = useState<SupervisionMatchingPreferences>(
    defaultSupervisionMatchingPreferences
  );
  const [initialSinglePostRules, setInitialSinglePostRules] =
    useState<InitialSinglePostRules | null>(null);
  const [keepManualAssignments, setKeepManualAssignments] = useState<boolean>(true);

  // Saving indicator
  const [saving, setSaving] = useState<boolean>(false);
  const [saveToast, setSaveToast] = useState<string | null>(null);

  const showToast = useCallback((msg: string) => {
    setSaveToast(msg);
    setTimeout(() => {
      setSaveToast(null);
    }, 2500);
  }, []);

  // Load initial data
  const loadData = useCallback(async () => {
    if (!termId) return;
    setLoading(true);
    setLoadError(null);
    try {
      const [snap, draftData, vers] = await Promise.all([
        schoolRepository.loadSchedulingData(termId),
        schoolRepository.loadSupervisionDraftData(termId),
        schoolRepository.loadSupervisionVersions(termId),
      ]);

      const initialDraft: SupervisionDraft =
        draftData ??
        (vers.length > 0
          ? { ...vers[vers.length - 1].draft, revision: 0 }
          : {
              termId,
              revision: 0,
              posts: [],
              teacherIds: snap.teachers.map((t) => t.id),
              teacherPools: [],
              defaultTeacherPoolId: null,
              matchingPreferences: defaultSupervisionMatchingPreferences,
              rules: {},
              assignments: {},
              manualPostIds: [],
            });

      setSnapshot(snap);
      setHistory(new SupervisionDraftHistory(initialDraft));
      setVersions(vers);
      setActiveVersionDate(null); // default to current draft
    } catch (err) {
      setLoadError(String(err));
    } finally {
      setLoading(false);
    }
  }, [termId]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  useEffect(
    () => () => {
      const worker = smartMatchWorkerRef.current;
      smartMatchWorkerRef.current = null;
      worker?.terminate();
      resolveSmartMatchRef.current?.(null);
      resolveSmartMatchRef.current = null;
    },
    []
  );

  const currentDraft = history?.current;
  const isHistorical = activeVersionDate !== null;
  const historicalVersion = versions.find((v) => v.effectiveDate === activeVersionDate);
  const activeDraft = isHistorical ? historicalVersion?.draft : currentDraft;
  const hasDraftPosts = (currentDraft?.posts.length ?? 0) > 0;
  const rulesDialogPost = bulkRulesTarget?.singlePost
    ? currentDraft?.posts.find((post) => post.id === bulkRulesTarget.postIds[0])
    : undefined;
  const rulesDialogPreferences =
    currentDraft && rulesDialogPost
      ? preferencesForPost(currentDraft, rulesDialogPost)
      : null;
  const hasRulesDialogChanges = bulkRulesTarget?.singlePost
    ? Boolean(
        initialSinglePostRules &&
          (bulkPoolId !== initialSinglePostRules.poolId ||
            bulkPreferenceMode !== initialSinglePostRules.preferenceMode ||
            (bulkPreferenceMode === 'custom' &&
              !sameMatchingPreferences(
                bulkMatchingPreferences,
                initialSinglePostRules.matchingPreferences
              )))
      )
    : bulkPoolId !== '__keep__' || bulkPreferenceMode !== 'keep';

  useEffect(() => {
    setSelectedPostIds((previous) => previous.size > 0 ? new Set() : previous);
  }, [activeVersionDate, missingOnly, searchQuery, unmetOnly, viewMode]);

  // Save draft
  const handleSaveDraft = useCallback(
    async (userInitiated = false) => {
      if (!currentDraft || !termId) return;
      setSaving(true);
      try {
        const saved = await schoolRepository.saveSupervisionDraftData(currentDraft);
        setHistory((current) => {
          if (!current) return current;
          const next = current.clone();
          next.markSaved(saved);
          return next;
        });
        if (userInitiated) {
          showToast('带班草稿已保存');
        }
      } catch (err) {
        showToast(`保存失败: ${err}`);
      } finally {
        setSaving(false);
      }
    },
    [currentDraft, showToast, termId]
  );

  // Undo / Redo
  const handleUndo = useCallback(() => {
    if (!history?.canUndo || isHistorical) return;
    const restored = history.undo();
    if (restored) {
      setHistory(history.clone());
    }
  }, [history, isHistorical]);

  const handleRedo = useCallback(() => {
    if (!history?.canRedo || isHistorical) return;
    const restored = history.redo();
    if (restored) {
      setHistory(history.clone());
    }
  }, [history, isHistorical]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }
      if ((e.metaKey || e.ctrlKey) && !e.shiftKey && e.key === 'z') {
        e.preventDefault();
        handleUndo();
      } else if (
        ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key === 'z') ||
        ((e.metaKey || e.ctrlKey) && e.key === 'y')
      ) {
        e.preventDefault();
        handleRedo();
      } else if ((e.metaKey || e.ctrlKey) && e.key === 's') {
        e.preventDefault();
        void handleSaveDraft(true);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleRedo, handleSaveDraft, handleUndo]);

  // Mutate draft helper
  const replaceDraft = useCallback(
    (next: SupervisionDraft, label: string) => {
      if (!history || isHistorical) return;
      if (history.replace(next, label)) {
        setHistory(history.clone());
      }
    },
    [history, isHistorical]
  );

  // Assign teacher
  const handleAssignTeacher = useCallback(
    (postId: string, teacherId: string | null) => {
      if (!currentDraft || !snapshot) return;
      const assignments = { ...currentDraft.assignments };
      const manualPostIds = new Set(currentDraft.manualPostIds);

      if (teacherId === null) {
        delete assignments[postId];
        manualPostIds.delete(postId);
      } else {
        assignments[postId] = teacherId;
        manualPostIds.add(postId);
      }

      replaceDraft(
        {
          ...currentDraft,
          assignments,
          manualPostIds: Array.from(manualPostIds),
        },
        teacherId ? '指派带班教师' : '清除指派'
      );
    },
    [currentDraft, replaceDraft, snapshot]
  );

  // Save new posts
  const handleSavePosts = useCallback(
    (posts: SupervisionPost[]) => {
      if (!currentDraft) return;
      replaceDraft(
        { ...currentDraft, posts: [...currentDraft.posts, ...posts] },
        `新建 ${posts.length} 个带班岗位`
      );
    },
    [currentDraft, replaceDraft]
  );

  // Delete post
  const handleDeletePost = useCallback(
    (postId: string) => {
      if (!currentDraft) return;
      const target = currentDraft.posts.find((p) => p.id === postId);
      setSelectedPostIds((selected) => {
        if (!selected.has(postId)) return selected;
        const next = new Set(selected);
        next.delete(postId);
        return next;
      });
      const assignments = { ...currentDraft.assignments };
      delete assignments[postId];
      const manual = currentDraft.manualPostIds.filter((id) => id !== postId);

      replaceDraft(
        {
          ...currentDraft,
          posts: currentDraft.posts.filter((p) => p.id !== postId),
          assignments,
          manualPostIds: manual,
        },
        `移除岗位「${target?.name ?? postId}」`
      );
    },
    [currentDraft, replaceDraft]
  );

  const togglePostSelection = (postId: string) => {
    setSelectedPostIds((current) => {
      const next = new Set(current);
      if (next.has(postId)) next.delete(postId);
      else next.add(postId);
      return next;
    });
  };

  const selectAllVisiblePosts = () => {
    const visibleIds = filteredPosts.map((post) => post.id);
    setSelectedPostIds((current) =>
      visibleIds.length > 0 && visibleIds.every((postId) => current.has(postId))
        ? new Set()
        : new Set(visibleIds)
    );
  };

  const openRulesDialog = (postIds: string[], singlePost: boolean) => {
    const firstPost = singlePost
      ? currentDraft?.posts.find((post) => post.id === postIds[0])
      : undefined;
    const nextPoolId =
      singlePost && firstPost ? firstPost.teacherPoolId ?? '__inherit__' : '__keep__';
    const nextPreferenceMode =
      singlePost && firstPost
        ? firstPost.matchingPreferences == null
          ? 'inherit'
          : 'custom'
        : 'keep';
    const nextMatchingPreferences = copyMatchingPreferences(
      firstPost?.matchingPreferences ??
        currentDraft?.matchingPreferences ??
        defaultSupervisionMatchingPreferences
    );
    setBulkPoolId(nextPoolId);
    setBulkPreferenceMode(nextPreferenceMode);
    setBulkMatchingPreferences(nextMatchingPreferences);
    setInitialSinglePostRules(
      singlePost && firstPost
        ? {
            poolId: nextPoolId,
            preferenceMode: nextPreferenceMode as 'inherit' | 'custom',
            matchingPreferences: copyMatchingPreferences(nextMatchingPreferences),
          }
        : null
    );
    setBulkRulesTarget({ postIds, singlePost });
    setBulkRulesDialogOpen(true);
  };

  const openBulkRulesDialog = () => {
    openRulesDialog(Array.from(selectedPostIds), false);
  };

  const openPostRulesDialog = (post: SupervisionPost) => {
    openRulesDialog([post.id], true);
  };

  const closeBulkRulesDialog = () => {
    setBulkRulesDialogOpen(false);
    setBulkRulesTarget(null);
    setInitialSinglePostRules(null);
  };

  const handleApplyBulkRules = () => {
    if (!currentDraft || !bulkRulesTarget) return;
    const targetPostIds = new Set(bulkRulesTarget.postIds);
    const selected = new Set(
      currentDraft.posts
        .filter((post) => targetPostIds.has(post.id))
        .map((post) => post.id)
    );
    if (selected.size === 0) {
      closeBulkRulesDialog();
      return;
    }
    const posts = currentDraft.posts.map((post) => {
      if (!selected.has(post.id)) return post;
      const next: SupervisionPost = { ...post };
      if (bulkPoolId !== '__keep__' && (post.teacherPoolId ?? '__inherit__') !== bulkPoolId) {
        next.teacherPoolId = bulkPoolId === '__inherit__' ? null : bulkPoolId;
      }
      if (bulkPreferenceMode === 'inherit' && post.matchingPreferences != null) {
        next.matchingPreferences = null;
      } else if (
        bulkPreferenceMode === 'custom' &&
        (post.matchingPreferences == null ||
          !sameMatchingPreferences(post.matchingPreferences, bulkMatchingPreferences))
      ) {
        next.matchingPreferences = copyMatchingPreferences(bulkMatchingPreferences);
      }
      return next;
    });

    replaceDraft(
      { ...currentDraft, posts },
      bulkRulesTarget.singlePost
        ? `设置岗位「${currentDraft.posts.find((post) => selected.has(post.id))?.name ?? ''}」人员规则`
        : `批量设置 ${selected.size} 个带班岗位人员规则`
    );
    if (!bulkRulesTarget.singlePost) setSelectedPostIds(new Set());
    closeBulkRulesDialog();
  };

  const handleRemoveSelectedPosts = () => {
    if (!currentDraft || selectedPostIds.size === 0) return;
    const selected = new Set(
      currentDraft.posts
        .filter((post) => selectedPostIds.has(post.id))
        .map((post) => post.id)
    );
    if (selected.size === 0) {
      setSelectedPostIds(new Set());
      setBulkRemoveDialogOpen(false);
      return;
    }
    const assignments = { ...currentDraft.assignments };
    for (const postId of selected) delete assignments[postId];

    replaceDraft(
      {
        ...currentDraft,
        posts: currentDraft.posts.filter((post) => !selected.has(post.id)),
        assignments,
        manualPostIds: currentDraft.manualPostIds.filter((postId) => !selected.has(postId)),
      },
      `批量移除 ${selected.size} 个带班岗位`
    );
    setSelectedPostIds(new Set());
    setBulkRemoveDialogOpen(false);
  };

  // Smart Fill
  const cancelSmartMatch = useCallback(() => {
    const worker = smartMatchWorkerRef.current;
    smartMatchWorkerRef.current = null;
    worker?.terminate();
    resolveSmartMatchRef.current?.(null);
    resolveSmartMatchRef.current = null;
    setSmartMatching(false);
    setSmartMatchDialogOpen(false);
  }, []);

  const handleSmartFill = useCallback(async () => {
    if (!currentDraft || !snapshot || smartMatching || smartMatchWorkerRef.current) return;
    const draftForFill = keepManualAssignments
      ? currentDraft
      : { ...currentDraft, manualPostIds: [] };
    let worker: Worker | null = null;
    setSmartMatching(true);

    try {
      worker = new Worker(new URL('./supervision-matching.worker.ts', import.meta.url), {
        type: 'module',
      });
      smartMatchWorkerRef.current = worker;
      const filled = await new Promise<SupervisionDraft | null>((resolve, reject) => {
        resolveSmartMatchRef.current = resolve;
        worker!.onmessage = ({ data }: MessageEvent<SupervisionMatchResponse>) => {
          if (data.type === 'complete') resolve(data.draft);
          else reject(new Error(data.message));
        };
        worker!.onerror = (event) => reject(new Error(event.message || '匹配线程运行失败'));
        worker!.postMessage({ snapshot, draft: draftForFill });
      });
      resolveSmartMatchRef.current = null;
      if (!filled || smartMatchWorkerRef.current !== worker) return;

      replaceDraft(filled, '智能匹配带班教师');
      setSmartMatchDialogOpen(false);
      showToast('智能匹配完成');
    } catch (error) {
      if (smartMatchWorkerRef.current === worker) {
        const message = error instanceof Error ? error.message : String(error);
        showToast(`智能匹配失败：${message}`);
      }
    } finally {
      worker?.terminate();
      if (smartMatchWorkerRef.current === worker) {
        smartMatchWorkerRef.current = null;
        resolveSmartMatchRef.current = null;
        setSmartMatching(false);
      }
    }
  }, [currentDraft, keepManualAssignments, replaceDraft, showToast, smartMatching, snapshot]);

  // Derived data
  const matching = useMemo(
    () => (snapshot ? new SupervisionMatching(snapshot) : null),
    [snapshot]
  );
  const allocator = useMemo(() => new SupervisionAllocator(), []);

  const classMap = useMemo(
    () => new Map(snapshot?.classes.map((c) => [c.id, c.name])),
    [snapshot?.classes]
  );

  const teacherMap = useMemo(
    () => new Map(snapshot?.teachers.map((t) => [t.id, t.name])),
    [snapshot?.teachers]
  );

  // Filtered posts
  const filteredPosts = useMemo(() => {
    if (!activeDraft || viewMode === 'teacher') return [];
    let list = activeDraft.posts;

    if (searchQuery.trim()) {
      const q = searchQuery.trim().toLowerCase();
      list = list.filter((post) => {
        const nameMatch = post.name.toLowerCase().includes(q) || post.groupName.toLowerCase().includes(q);
        const classMatch = post.classIds.some((id) =>
          (classMap.get(id) ?? '').toLowerCase().includes(q)
        );
        const assignedId = activeDraft.assignments[post.id];
        const teacherMatch = assignedId
          ? (teacherMap.get(assignedId) ?? '').toLowerCase().includes(q)
          : false;
        return nameMatch || classMatch || teacherMatch;
      });
    }

    if (missingOnly) {
      list = list.filter((post) => !activeDraft.assignments[post.id]);
    }

    if (unmetOnly && matching) {
      list = list.filter((post) => {
        const teacherId = activeDraft.assignments[post.id];
        if (!teacherId) return false;
        return matching.hasUnmetPreferences(activeDraft, post, teacherId);
      });
    }

    return list;
  }, [activeDraft, classMap, matching, missingOnly, searchQuery, teacherMap, unmetOnly, viewMode]);

  const filteredTeachers = useMemo(() => {
    const teachers = snapshot?.teachers ?? [];
    if (viewMode !== 'teacher') return teachers;
    const query = searchQuery.trim().toLowerCase();
    if (!query) return teachers;

    const matchingTeacherIds = new Set(
      teachers
        .filter((teacher) => teacher.name.toLowerCase().includes(query))
        .map((teacher) => teacher.id)
    );

    for (const post of activeDraft?.posts ?? []) {
      const teacherId = activeDraft?.assignments[post.id];
      if (!teacherId || matchingTeacherIds.has(teacherId)) continue;

      const postMatches =
        post.name.toLowerCase().includes(query) ||
        post.groupName.toLowerCase().includes(query) ||
        post.classIds.some((id) => (classMap.get(id) ?? '').toLowerCase().includes(query));
      if (postMatches) matchingTeacherIds.add(teacherId);
    }

    return teachers.filter((teacher) => matchingTeacherIds.has(teacher.id));
  }, [activeDraft, classMap, searchQuery, snapshot?.teachers, viewMode]);

  const allVisiblePostsSelected =
    filteredPosts.length > 0 && filteredPosts.every((post) => selectedPostIds.has(post.id));

  // Overall statistics
  const stats = useMemo(() => {
    if (!activeDraft) {
      return { total: 0, assigned: 0, missing: 0, teachers: 0, classes: 0 };
    }
    const total = activeDraft.posts.length;
    const assigned = activeDraft.posts.filter((p) => activeDraft.assignments[p.id]).length;
    const missing = total - assigned;
    const teacherSet = new Set(Object.values(activeDraft.assignments));
    const classSet = new Set(activeDraft.posts.flatMap((p) => p.classIds));
    return {
      total,
      assigned,
      missing,
      teachers: teacherSet.size,
      classes: classSet.size,
    };
  }, [activeDraft]);

  // Validation errors for current draft
  const currentValidationErrors = useMemo(() => {
    if (!snapshot || !activeDraft) return [];
    return postErrors(snapshot, activeDraft);
  }, [activeDraft, snapshot]);

  if (!termId) {
    return (
      <div className="p-8 text-center text-ink-secondary text-sm">
        请先选择学期后再进行带班安排。
      </div>
    );
  }

  if (loading) {
    return (
      <div className="p-16 flex flex-col items-center justify-center space-y-3">
        <Clock className="h-6 w-6 animate-spin text-primary" />
        <span className="text-sm text-ink-secondary">正在读取带班安排与排课数据...</span>
      </div>
    );
  }

  if (loadError || !snapshot || !currentDraft) {
    return (
      <div className="p-8 max-w-lg mx-auto text-center space-y-4">
        <AlertTriangle className="h-10 w-10 text-destructive mx-auto" />
        <div className="text-base font-semibold text-ink">读取带班安排失败</div>
        <div className="text-xs text-ink-secondary">{loadError}</div>
        <Button onClick={() => void loadData()} size="sm" variant="outline">
          <RefreshCw className="h-3.5 w-3.5 mr-1" />
          重试
        </Button>
      </div>
    );
  }

  return (
    <div className="flex min-h-[calc(100dvh-88px)] flex-col gap-3">
      {/* Toast notification */}
      {saveToast && (
        <div className="fixed top-16 right-8 z-50 bg-ink text-canvas text-xs px-4 py-2 rounded-lg shadow-lg flex items-center gap-2 animate-in fade-in">
          <Check className="h-4 w-4 text-emerald-400" />
          <span>{saveToast}</span>
        </div>
      )}

      {/* Top Action Bar */}
      <div
        ref={toolbarRef}
        role="toolbar"
        aria-label="带班安排工具栏"
        className="sticky-glass-toolbar sticky top-0 z-30 overflow-hidden rounded-xl bg-surface shadow-sm"
      >
        <div className="flex flex-wrap items-center justify-between gap-2 px-3 py-2">
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <Tabs
            value={isHistorical ? 'published' : 'draft'}
            onValueChange={(value) => {
              if (value === 'draft') {
                setActiveVersionDate(null);
              } else {
                setActiveVersionDate(versions[versions.length - 1]?.effectiveDate ?? null);
              }
            }}
          >
            <TabsList aria-label="带班方案版本">
              <TabsTrigger value="draft" className="h-7 px-2.5 py-0.5 text-xs">
                草稿版
                {history?.hasChanges && <span className="ml-1 text-primary" aria-label="有未保存更改">•</span>}
              </TabsTrigger>
              <TabsTrigger
                value="published"
                disabled={versions.length === 0}
                className="h-7 px-2.5 py-0.5 text-xs"
              >
                正式版
              </TabsTrigger>
            </TabsList>
          </Tabs>

          {isHistorical && versions.length > 1 && (
            <Select value={activeVersionDate ?? ''} onValueChange={setActiveVersionDate}>
              <SelectTrigger aria-label="选择正式版日期" className="h-8 w-32 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {versions.map((version) => (
                  <SelectItem key={version.effectiveDate} value={version.effectiveDate}>
                    {version.effectiveDate}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}

          {isHistorical && (
            <Badge variant="outline" className="h-6 border-amber-500/30 bg-amber-500/10 px-2 text-[11px] text-amber-600">
              {versions.length > 1 ? '只读' : `只读 · ${activeVersionDate ?? ''}`}
            </Badge>
          )}

          <div className="mx-1 h-5 w-px bg-border" />

          <Tabs value={viewMode} onValueChange={(value) => setViewMode(value as typeof viewMode)}>
            <TabsList aria-label="带班视图">
              <TabsTrigger value="week" className="h-7 px-2.5 py-0.5 text-xs">周视图</TabsTrigger>
              <TabsTrigger value="class" className="h-7 px-2.5 py-0.5 text-xs">班级视图</TabsTrigger>
              <TabsTrigger value="teacher" className="h-7 px-2.5 py-0.5 text-xs">教师视图</TabsTrigger>
            </TabsList>
          </Tabs>
        </div>

        {/* Right: Actions */}
        <div className="ml-auto flex items-center gap-1">
          {!isHistorical && (
            <>
              {/* Smart Match */}
              <Button
                type="button"
                variant="outline"
                size="sm"
                className="h-8 gap-1.5 px-2.5 text-xs"
                onClick={() => setSmartMatchDialogOpen(true)}
              >
                <Sparkles className="h-4 w-4 text-primary" />
                智能匹配
              </Button>

              {/* Add Post */}
              <Button
                type="button"
                variant="outline"
                size="sm"
                className="h-8 gap-1.5 px-2.5 text-xs"
                onClick={() => setPostDialogOpen(true)}
              >
                <Plus className="h-4 w-4" />
                添加岗位
              </Button>

              {/* Publish */}
              {hasDraftPosts && (
                <Button
                  type="button"
                  size="sm"
                  variant="default"
                  className="h-8 gap-1.5 px-2.5 text-xs"
                  onClick={() => setPublishDialogOpen(true)}
                >
                  <CalendarCheck className="h-4 w-4" />
                  预览并发布
                </Button>
              )}
            </>
          )}
        </div>
        </div>

        <div className="flex flex-wrap items-center gap-x-2 gap-y-1.5 border-t border-dashed px-3 py-1.5">
          <div className="flex min-w-[18rem] flex-1 flex-wrap items-center gap-2">
            <div className="relative w-[190px] max-w-full transition-[width] duration-200 focus-within:w-72">
              <Search className="absolute left-2.5 top-2 h-3.5 w-3.5 text-ink-secondary" />
              <Input
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="搜索班级、教师或岗位..."
                className="h-7 bg-canvas/40 pl-8 pr-7 text-xs"
              />
              {searchQuery && (
                <button
                  type="button"
                  aria-label="清除搜索"
                  onClick={() => setSearchQuery('')}
                  className="absolute right-2 top-2 text-ink-secondary hover:text-ink"
                >
                  <X aria-hidden="true" className="h-3.5 w-3.5" />
                </button>
              )}
            </div>

            <div className="flex h-7 items-center gap-1.5 px-1 text-xs text-ink-secondary">
              <Checkbox
                id="supervision-filter-missing"
                checked={missingOnly}
                onCheckedChange={(checked) => setMissingOnly(checked === true)}
                aria-label="仅看未安排"
              />
              <span>仅看未安排</span>
              {stats.missing > 0 && (
                <span className="flex h-4 items-center justify-center rounded-full bg-amber-500/20 px-1 text-[10px] font-bold text-amber-700 dark:text-amber-300">
                  {stats.missing}
                </span>
              )}
            </div>

            <div className="flex h-7 items-center gap-1.5 px-1 text-xs text-ink-secondary">
              <Checkbox
                id="supervision-filter-unmet"
                checked={unmetOnly}
                onCheckedChange={(checked) => setUnmetOnly(checked === true)}
                aria-label="仅看偏好未满足"
              />
              <span>仅看偏好未满足</span>
            </div>
          </div>

          {!isHistorical && (
            <div className="ml-auto flex flex-wrap items-center gap-1">
              <div className="mx-1 hidden h-5 w-px bg-border lg:block" />
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-7 gap-1.5 px-2 text-xs"
                disabled={!history?.canUndo}
                onClick={handleUndo}
                title="撤销 (Ctrl+Z)"
              >
                <Undo2 aria-hidden="true" className="h-4 w-4" />
                撤销
              </Button>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-7 gap-1.5 px-2 text-xs"
                disabled={!history?.canRedo}
                onClick={handleRedo}
                title="重做 (Ctrl+Shift+Z)"
              >
                <Redo2 aria-hidden="true" className="h-4 w-4" />
                重做
              </Button>
              <div className="mx-1 h-5 w-px bg-border" />
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-7 gap-1.5 px-2 text-xs"
                onClick={() => setPoolDialogOpen(true)}
              >
                <Settings2 aria-hidden="true" className="h-4 w-4" />
                候选池与规则
              </Button>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className={`h-7 gap-1.5 px-2 text-xs ${
                  history?.hasChanges ? 'border-primary text-primary font-medium' : ''
                }`}
                disabled={saving || !history?.hasChanges}
                onClick={() => void handleSaveDraft(true)}
              >
                {saving ? (
                  <LoaderCircle aria-hidden="true" className="h-4 w-4 animate-spin" />
                ) : (
                  <Save aria-hidden="true" className="h-4 w-4" />
                )}
                {saving ? '保存中...' : '保存草稿'}
              </Button>
            </div>
          )}
        </div>
      </div>

      {/* Validation Warnings Banner */}
      {currentValidationErrors.length > 0 && (
        <div className="p-3 rounded-lg bg-destructive/10 border border-destructive/20 text-destructive text-xs space-y-1">
          <div className="font-semibold flex items-center gap-1.5">
            <AlertTriangle className="h-4 w-4" />
            当前方案存在 {currentValidationErrors.length} 项排班冲突或设置错误：
          </div>
          <ul className="list-disc list-inside space-y-0.5 pl-2 max-h-24 overflow-y-auto">
            {currentValidationErrors.map((err, i) => (
              <li key={i}>{err}</li>
            ))}
          </ul>
        </div>
      )}

      {viewMode === 'teacher' && filteredTeachers.length > 0 && (
        <Suspense fallback={<p role="status" className="p-4 text-sm text-ink-secondary">正在加载教师任课负载…</p>}>
          <TeacherWorkloadChart
            key={snapshot.term.id}
            teachers={filteredTeachers}
            items={snapshot.items}
            supervisionPlan={activeDraft}
            cycleMode={snapshot.term.cycleMode}
          />
        </Suspense>
      )}

      {/* Main View Display */}
      {activeDraft?.posts.length === 0 && viewMode !== 'teacher' ? (
        <div className="p-16 border border-dashed border-border rounded-2xl bg-surface text-center space-y-3">
          <div className="h-12 w-12 rounded-full bg-primary/10 text-primary flex items-center justify-center mx-auto">
            <Users className="h-6 w-6" />
          </div>
          <div className="text-base font-semibold text-ink">尚无带班岗位</div>
          <p className="text-xs text-ink-secondary max-w-sm mx-auto">
            带班周表还是空的。新建带班岗位后，可按周次和节次为各班安排早自习、晚自习或课后服务教师。
          </p>
          {!isHistorical && (
            <Button
              type="button"
              size="sm"
              onClick={() => setPostDialogOpen(true)}
              className="mt-2"
            >
              <Plus className="h-4 w-4 mr-1" />
              新建首个带班岗位
            </Button>
          )}
        </div>
      ) : viewMode === 'week' ? (
        <SupervisionWeekGrid
          snapshot={snapshot}
          draft={activeDraft!}
          posts={filteredPosts}
          classMap={classMap}
          teacherMap={teacherMap}
          matching={matching}
          allocator={allocator}
          isHistorical={isHistorical}
          selectedPostIds={selectedPostIds}
          onTogglePostSelection={togglePostSelection}
          onSetPostSelection={(postIds) => setSelectedPostIds(postIds)}
          onEditRules={openPostRulesDialog}
          onDeletePost={handleDeletePost}
          onSelectTeacher={(post) => {
            setActivePostForTeacher(post);
            setTeacherPickerOpen(true);
          }}
        />
      ) : viewMode === 'class' ? (
        /* ================= 2. 班级视图 ================= */
        <div className="space-y-4">
          {snapshot.grades.map((grade) => {
            const gradeClasses = snapshot.classes.filter((c) => c.gradeId === grade.id);
            return (
              <div key={grade.id} className="rounded-xl bg-surface p-4 space-y-3">
                <h3 className="font-semibold text-sm text-ink flex items-center gap-2">
                  <GraduationCap className="h-4 w-4 text-primary" />
                  {grade.name} ({gradeClasses.length} 班)
                </h3>

                <div className="grid grid-cols-2 gap-3">
                  {gradeClasses.map((schoolClass) => {
                    const classPosts = filteredPosts
                      .filter((p) => p.classIds.includes(schoolClass.id))
                      .sort((a, b) => a.weekday - b.weekday || (a.lessonIndices[0] ?? 0) - (b.lessonIndices[0] ?? 0));

                    return (
                      <div
                        key={schoolClass.id}
                        className="rounded-lg border border-border/80 p-3 bg-canvas/30 space-y-2 text-xs"
                      >
                        <div className="flex items-center justify-between font-semibold text-ink">
                          <span>{schoolClass.name}</span>
                          <span className="text-ink-secondary text-[11px] font-normal">
                            共 {classPosts.length} 次带班
                          </span>
                        </div>

                        {classPosts.length === 0 ? (
                          <div className="text-ink-secondary/60 text-[11px] py-3 text-center">
                            该班暂无带班安排
                          </div>
                        ) : (
                          <div className="space-y-1.5">
                            {classPosts.map((post) => {
                              const teacherId = activeDraft?.assignments[post.id];
                              const teacherName = teacherId
                                ? teacherMap.get(teacherId) ?? teacherId
                                : null;
                              return (
                                <div
                                  key={post.id}
                                  className="flex items-center justify-between p-1.5 rounded bg-surface border border-border/60 text-[11px]"
                                >
                                  <div className="flex items-center gap-2">
                                    <span className="font-medium text-ink w-8">
                                      {WEEKDAYS[post.weekday - 1]}
                                    </span>
                                    <span className="text-ink-secondary">
                                      第{post.lessonIndices.join('、')}节
                                    </span>
                                    <span className="font-medium text-ink">{post.name}</span>
                                  </div>

                                  <div>
                                    {teacherName ? (
                                      <span className="font-medium text-primary">
                                        {teacherName}
                                      </span>
                                    ) : (
                                      <button
                                        type="button"
                                        disabled={isHistorical}
                                        onClick={() => {
                                          setActivePostForTeacher(post);
                                          setTeacherPickerOpen(true);
                                        }}
                                        className="text-amber-600 hover:underline"
                                      >
                                        + 指派教师
                                      </button>
                                    )}
                                  </div>
                                </div>
                              );
                            })}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        /* ================= 3. 教师视图 ================= */
        filteredTeachers.length > 0 ? (
          <SupervisionTeacherCards teachers={filteredTeachers} draft={activeDraft} classMap={classMap} />
        ) : (
          <div role="status" className="rounded-xl bg-surface p-10 text-center text-sm text-ink-secondary">
            {searchQuery.trim() ? '没有找到匹配的教师或岗位' : '暂无教师'}
          </div>
        )
      )}

      <div
        role="toolbar"
        aria-label="带班统计与岗位批量操作"
        className="sticky bottom-0 z-20 mt-auto flex flex-wrap items-center justify-between gap-x-4 gap-y-1 rounded-xl bg-surface px-3 py-1.5 shadow-sm"
      >
        <div className="flex flex-wrap items-center gap-x-4 gap-y-0.5 text-xs text-ink-secondary">
          <span>总岗位：<strong className="font-semibold text-ink">{stats.total}</strong></span>
          <span>已安排：<strong className="font-semibold text-emerald-600">{stats.assigned}</strong></span>
          <span>待安排：<strong className="font-semibold text-amber-600">{stats.missing}</strong></span>
          <span>带班教师：<strong className="font-semibold text-ink">{stats.teachers}</strong> 人</span>
          <span>覆盖班级：<strong className="font-semibold text-ink">{stats.classes}</strong> 个</span>
        </div>

        {viewMode === 'week' && !isHistorical && filteredPosts.length > 0 && (
          <div className="ml-auto flex flex-wrap items-center gap-1.5">
            <div className="mx-1 hidden h-5 w-px bg-border lg:block" />
            <Button
              type="button"
              size="sm"
              variant="ghost"
              disabled={selectedPostIds.size === 0}
              className="h-7 px-1.5 text-xs text-ink-secondary"
              title="按住鼠标拖过岗位卡片可涂抹多选，也可悬停后勾选"
              onClick={() => setSelectedPostIds(new Set())}
            >
              取消选择 {selectedPostIds.size} 个岗位
            </Button>
            <Button
              type="button"
              size="sm"
              variant="ghost"
              className="h-7 px-1.5 text-xs"
              onClick={selectAllVisiblePosts}
            >
              {allVisiblePostsSelected ? '取消全选' : '全选'}
            </Button>
            {selectedPostIds.size > 0 && (
              <>
                <Button
                  type="button"
                  size="icon"
                  variant="ghost"
                  className="h-7 w-7"
                  aria-label="设置所选岗位的候选池与匹配偏好"
                  title="设置候选池 / 匹配偏好"
                  onClick={openBulkRulesDialog}
                >
                  <Settings2 aria-hidden="true" className="h-4 w-4" />
                </Button>
                <Button
                  type="button"
                  size="icon"
                  variant="ghost"
                  className="h-7 w-7 text-destructive hover:bg-destructive/10 hover:text-destructive"
                  aria-label="批量移除所选岗位"
                  title="批量移除岗位"
                  onClick={() => setBulkRemoveDialogOpen(true)}
                >
                  <Trash2 aria-hidden="true" className="h-4 w-4" />
                </Button>
              </>
            )}
          </div>
        )}
      </div>

      {/* Dialog: Post Dialog */}
      <PostDialog
        open={postDialogOpen}
        onOpenChange={setPostDialogOpen}
        snapshot={snapshot}
        draft={activeDraft!}
        onSave={handleSavePosts}
      />

      <Dialog
        open={bulkRulesDialogOpen}
        onOpenChange={(open) => {
          if (open) setBulkRulesDialogOpen(true);
          else closeBulkRulesDialog();
        }}
      >
        <DialogContent className="max-w-lg max-h-[85vh] flex flex-col overflow-hidden p-6">
          <DialogHeader>
            <DialogTitle className="text-base font-semibold text-ink">
              {bulkRulesTarget?.singlePost ? '设置岗位人员规则' : '批量设置岗位人员规则'}
            </DialogTitle>
            <DialogDescription className="text-xs text-ink-secondary">
              {bulkRulesTarget?.singlePost
                ? '将设置应用到当前岗位。已指派教师会保留；规则可用于后续智能匹配。'
                : `将设置应用到 ${bulkRulesTarget?.postIds.length ?? selectedPostIds.size} 个所选岗位。已指派教师会保留；规则可用于后续智能匹配。`}
            </DialogDescription>
          </DialogHeader>

          <div className="min-h-0 space-y-4 overflow-y-auto px-1 py-3">
            {bulkRulesTarget?.singlePost &&
              rulesDialogPost &&
              currentDraft &&
              rulesDialogPreferences && (
                <div className="space-y-2 rounded-lg border border-border bg-canvas/60 p-3 text-xs">
                  <div className="font-semibold text-ink">该岗位当前生效的规则</div>
                  <div className="flex flex-wrap gap-x-2 gap-y-1">
                    <span className="text-ink-secondary">候选池</span>
                    <span className="font-medium text-ink">
                      {poolNameForPost(currentDraft, rulesDialogPost)}
                      {rulesDialogPost.teacherPoolId == null && '（跟随方案默认）'}
                    </span>
                  </div>
                  <div className="flex flex-wrap gap-x-2 gap-y-1">
                    <span className="text-ink-secondary">匹配偏好来源</span>
                    <span className="font-medium text-ink">
                      {rulesDialogPost.matchingPreferences == null ? '方案默认' : '岗位自定义'}
                    </span>
                  </div>
                  <div className="leading-relaxed">
                    <span className="text-ink-secondary">偏好顺序：</span>
                    <span className="text-ink">
                      {rulesDialogPreferences.order
                        .map(
                          (preference) =>
                            `${SUPERVISION_PREFERENCE_LABELS[preference]}（${
                              rulesDialogPreferences.enabled.includes(preference)
                                ? '启用'
                                : '关闭'
                            }）`
                        )
                        .join(' → ')}
                    </span>
                  </div>
                  <div className="leading-relaxed text-ink">
                    <span className="text-ink-secondary">匹配方式：</span>
                    {MATCH_MODE_LABELS[rulesDialogPreferences.mode]}
                    <span className="mx-1.5 text-ink-secondary">·</span>
                    {MATCH_REQUIREMENT_LABELS[rulesDialogPreferences.requirement]}
                  </div>
                </div>
              )}

            <div className="space-y-1.5">
              <label className="text-xs font-medium text-ink">候选池</label>
              <Select value={bulkPoolId} onValueChange={setBulkPoolId}>
                <SelectTrigger className="h-9 text-xs">
                  <SelectValue placeholder="选择候选池操作" />
                </SelectTrigger>
                <SelectContent>
                  {!bulkRulesTarget?.singlePost && (
                    <SelectItem value="__keep__">保留各岗位当前候选池</SelectItem>
                  )}
                  <SelectItem value="__inherit__">
                    {bulkRulesTarget?.singlePost && rulesDialogPost && currentDraft
                      ? `跟随方案默认候选池（当前生效：${poolNameForPost(currentDraft, rulesDialogPost)}）`
                      : '跟随方案默认候选池'}
                  </SelectItem>
                  <SelectItem value={SUPERVISION_BASE_POOL_ID}>基础候选池（全体教师）</SelectItem>
                  {activeDraft!.teacherPools.map((pool) => (
                    <SelectItem key={pool.id} value={pool.id}>
                      {pool.name}
                    </SelectItem>
                  ))}
                  {bulkRulesTarget?.singlePost &&
                    rulesDialogPost?.teacherPoolId &&
                    rulesDialogPost.teacherPoolId !== SUPERVISION_BASE_POOL_ID &&
                    !activeDraft!.teacherPools.some(
                      (pool) => pool.id === rulesDialogPost.teacherPoolId
                    ) && (
                      <SelectItem value={rulesDialogPost.teacherPoolId}>候选池已失效</SelectItem>
                    )}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-medium text-ink">匹配偏好</label>
              <Select
                value={bulkPreferenceMode}
                onValueChange={(value) =>
                  setBulkPreferenceMode(value as 'keep' | 'inherit' | 'custom')
                }
              >
                <SelectTrigger className="h-9 text-xs">
                  <SelectValue placeholder="选择匹配偏好操作" />
                </SelectTrigger>
                <SelectContent>
                  {!bulkRulesTarget?.singlePost && (
                    <SelectItem value="keep">保留各岗位当前偏好</SelectItem>
                  )}
                  <SelectItem value="inherit">跟随方案默认偏好</SelectItem>
                  <SelectItem value="custom">
                    {bulkRulesTarget?.singlePost ? '自定义匹配偏好' : '统一设置匹配偏好'}
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>

            {bulkPreferenceMode === 'custom' && (
              <SupervisionMatchingPreferencesEditor
                value={bulkMatchingPreferences}
                onChange={setBulkMatchingPreferences}
              />
            )}
          </div>

          <DialogFooter className="shrink-0">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={closeBulkRulesDialog}
            >
              取消
            </Button>
            <Button
              type="button"
              size="sm"
              onClick={handleApplyBulkRules}
              disabled={!hasRulesDialogChanges}
            >
              {bulkRulesTarget?.singlePost ? '应用到该岗位' : '应用到所选岗位'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={bulkRemoveDialogOpen} onOpenChange={setBulkRemoveDialogOpen}>
        <DialogContent className="max-w-md p-6">
          <DialogHeader>
            <DialogTitle className="text-base font-semibold text-ink">
              批量移除岗位？
            </DialogTitle>
            <DialogDescription className="text-xs text-ink-secondary">
              将移除 {selectedPostIds.size} 个所选岗位及其教师指派记录。此操作可以从草稿历史中撤销。
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => setBulkRemoveDialogOpen(false)}
            >
              取消
            </Button>
            <Button
              type="button"
              size="sm"
              className="bg-destructive text-white hover:bg-destructive/90"
              onClick={handleRemoveSelectedPosts}
            >
              移除所选岗位
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dialog: Teacher Picker */}
      <TeacherPickerDialog
        open={teacherPickerOpen}
        onOpenChange={setTeacherPickerOpen}
        snapshot={snapshot}
        draft={activeDraft!}
        post={activePostForTeacher}
        onAssign={handleAssignTeacher}
      />

      {/* Dialog: Candidate Pools & Rules */}
      <TeacherPoolDialog
        open={poolDialogOpen}
        onOpenChange={setPoolDialogOpen}
        snapshot={snapshot}
        draft={activeDraft!}
        onSave={(updated) => replaceDraft(updated, '更新候选池与带班规则')}
      />

      {/* Dialog: Publish Confirmation */}
      <PublishDialog
        open={publishDialogOpen}
        onOpenChange={setPublishDialogOpen}
        termId={termId}
        snapshot={snapshot}
        onPublishSuccess={() => {
          showToast('带班方案已成功确认生效！');
          void loadData();
        }}
      />

      {/* Dialog: Smart Match Confirmation */}
      <Dialog
        open={smartMatchDialogOpen}
        onOpenChange={(open) => {
          if (!open && smartMatchWorkerRef.current) cancelSmartMatch();
          else setSmartMatchDialogOpen(open);
        }}
      >
        <DialogContent className="max-w-md p-6">
          <DialogHeader>
            <DialogTitle className="text-base font-semibold text-ink flex items-center gap-2">
              <Sparkles className="h-5 w-5 text-primary" />
              智能匹配带班教师
            </DialogTitle>
            <DialogDescription className="text-xs text-ink-secondary mt-1">
              按候选池、带班上限、禁排规则和匹配偏好，自动为草稿中未完成分配的岗位指派最合适教师。
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-3 py-4 text-xs">
            <div className="flex items-start gap-2.5 rounded-lg border border-border p-3 hover:bg-canvas/40">
              <Checkbox
                id="keep-manual-supervision-assignments"
                checked={keepManualAssignments}
                disabled={smartMatching}
                onCheckedChange={(checked) => setKeepManualAssignments(checked === true)}
                className="mt-0.5"
              />
              <div className="min-w-0">
                <label
                  htmlFor="keep-manual-supervision-assignments"
                  className="block cursor-pointer font-medium text-ink"
                >
                  保留已手动指派的教师
                </label>
                <span className="text-ink-secondary text-[11px]">
                  勾选后仅为尚未指派的岗位自动补齐；取消勾选将全部重新匹配。
                </span>
              </div>
            </div>
          </div>

          {smartMatching && (
            <div role="status" className="flex items-center gap-2 text-xs text-ink-secondary">
              <LoaderCircle className="h-4 w-4 animate-spin text-primary" />
              正在后台匹配，界面仍可操作；需要时可以取消。
            </div>
          )}

          <DialogFooter className="flex items-center justify-end gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => (smartMatching ? cancelSmartMatch() : setSmartMatchDialogOpen(false))}
            >
              {smartMatching ? '取消匹配' : '取消'}
            </Button>
            <Button type="button" size="sm" onClick={handleSmartFill} disabled={smartMatching}>
              {smartMatching ? (
                <>
                  <LoaderCircle className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                  正在匹配
                </>
              ) : (
                '开始匹配'
              )}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};
