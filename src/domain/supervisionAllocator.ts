import type { ScheduleData } from './scheduling.ts';
import type {
  SchedulePosition,
  SupervisionDraft,
  SupervisionPost,
} from './supervision.ts';
import {
  allTeacherIdsInDraft,
  hasClockTime,
  overlaps,
  preferencesForPost,
  sameCell,
  teachersForPost,
} from './supervision.ts';
import { SupervisionMatching } from './supervisionMatching.ts';
import { positions, withRoutineClock } from './supervisionValidation.ts';

export class SupervisionAllocator {
  teacherBlockers(
    snapshot: ScheduleData,
    draft: SupervisionDraft,
    post: SupervisionPost,
    teacherId: string,
    matching?: SupervisionMatching
  ): string[] {
    const postPositions = positions(snapshot, post);
    const rule = draft.rules[teacherId] ?? {};
    const others = draft.posts.filter(
      (other) => other.id !== post.id && draft.assignments[other.id] === teacherId
    );

    const errors: string[] = [];

    const allowedTeachers = teachersForPost(draft, post);
    if (!allowedTeachers.has(teacherId) || !snapshot.teachers.some((t) => t.id === teacherId)) {
      errors.push('教师不在岗位候选池中');
    }

    const m = matching ?? new SupervisionMatching(snapshot);
    if (!m.meetsRequirement(draft, post, teacherId)) {
      errors.push('未满足岗位必须符合的匹配条件');
    }

    if (rule.unavailable && rule.unavailable.length > 0) {
      if (postPositions.some((p) => rule.unavailable!.some((u) => sameCell(p, u)))) {
        errors.push('教师在该节次禁排');
      }
    }

    // Existing regular courses of teacher
    const courses: SchedulePosition[] = snapshot.items
      .filter((item) => item.teacherId === teacherId && item.weekday !== null && item.periodTypeId !== null && item.lessonIndex !== null)
      .map((item) =>
        withRoutineClock(snapshot, {
          stageId: item.stageId ?? post.stageId,
          weekday: item.weekday!,
          periodTypeId: item.periodTypeId!,
          lessonIndex: item.lessonIndex!,
        })
      );

    if (postPositions.some((p) => courses.some((c) => overlaps(p, c)))) {
      errors.push('教师已有正课');
    }

    // Other supervision posts assigned to teacher
    const otherPositions: SchedulePosition[] = others.flatMap((other) =>
      positions(snapshot, other)
    );

    if (postPositions.some((p) => otherPositions.some((o) => overlaps(p, o)))) {
      errors.push('教师已有带班');
    }

    // Cross-stage time check
    const allTeacherSlots = [...courses, ...otherPositions];
    if (
      postPositions.some((p) =>
        allTeacherSlots.some(
          (o) =>
            o.weekday === p.weekday &&
            o.stageId !== p.stageId &&
            (!hasClockTime(o) || !hasClockTime(p))
        )
      )
    ) {
      errors.push('跨学段排班需要补全节次时间');
    }

    // Max lessons check
    const totalLessons =
      post.lessonIndices.length +
      others.reduce((count, other) => count + other.lessonIndices.length, 0);

    if (rule.maxLessons != null && totalLessons > rule.maxLessons) {
      errors.push('超过每周带班节次上限');
    }

    // Max days check
    const days = new Set<number>([post.weekday, ...others.map((other) => other.weekday)]);
    if (rule.maxDays != null && days.size > rule.maxDays) {
      errors.push('超过每周带班天数上限');
    }

    return errors;
  }

  fill(snapshot: ScheduleData, draft: SupervisionDraft): SupervisionDraft {
    const teacherIds = [...allTeacherIdsInDraft(draft)].sort();
    const matching = new SupervisionMatching(snapshot);

    const manualSet = new Set(draft.manualPostIds);
    const initialAssignments: Record<string, string> = {};
    for (const post of draft.posts) {
      if (manualSet.has(post.id) && draft.assignments[post.id]) {
        initialAssignments[post.id] = draft.assignments[post.id];
      }
    }

    const state: SupervisionDraft = {
      ...draft,
      assignments: { ...initialAssignments },
    };

    const unassignedPosts = draft.posts.filter((post) => !initialAssignments[post.id]);

    const candidates = new Map<string, string[]>();
    for (const post of unassignedPosts) {
      const valid = teacherIds.filter(
        (id) => this.teacherBlockers(snapshot, state, post, id, matching).length === 0
      );
      candidates.set(post.id, valid);
    }

    // Sort posts with fewer candidates first (MRV heuristic)
    const sortedPosts = [...unassignedPosts].sort((a, b) => {
      const lenA = candidates.get(a.id)?.length ?? 0;
      const lenB = candidates.get(b.id)?.length ?? 0;
      if (lenA !== lenB) return lenA - lenB;
      return a.id.localeCompare(b.id);
    });

    const loads = new Map<string, number>();
    for (const id of teacherIds) {
      loads.set(id, 0);
    }
    for (const [postId, teacherId] of Object.entries(initialAssignments)) {
      const p = draft.posts.find((item) => item.id === postId);
      if (p && loads.has(teacherId)) {
        loads.set(teacherId, loads.get(teacherId)! + p.lessonIndices.length);
      }
    }

    const currentAssignments: Record<string, string> = { ...initialAssignments };
    let bestAssignments: Record<string, string> = { ...initialAssignments };
    let maxCoverage = 0;
    let budget = 12000;

    const ranksCache = new Map<string, Map<string, number[]>>();
    for (const post of sortedPosts) {
      const map = new Map<string, number[]>();
      for (const t of teacherIds) {
        map.set(t, matching.ranks(draft, post, t));
      }
      ranksCache.set(post.id, map);
    }

    const visit = (index: number, coverage: number): void => {
      if (coverage > maxCoverage) {
        maxCoverage = coverage;
        bestAssignments = { ...currentAssignments };
      }
      if (index >= sortedPosts.length || budget <= 0) return;
      budget--;

      const post = sortedPosts[index];
      const postCandidates = candidates.get(post.id) ?? [];
      const mode = preferencesForPost(draft, post).mode;

      const ranked = [...postCandidates].sort((a, b) => {
        const loadA = loads.get(a) ?? 0;
        const loadB = loads.get(b) ?? 0;
        const loadOrder = loadA - loadB;

        if (mode === 'balanceFirst' && loadOrder !== 0) {
          return loadOrder;
        }

        const rankA = ranksCache.get(post.id)?.get(a) ?? [];
        const rankB = ranksCache.get(post.id)?.get(b) ?? [];
        for (let i = 0; i < rankA.length; i++) {
          const ord = (rankB[i] ?? 0) - (rankA[i] ?? 0);
          if (ord !== 0) return ord;
        }
        return loadOrder === 0 ? a.localeCompare(b) : loadOrder;
      });

      const size = post.lessonIndices.length;

      for (const teacher of ranked) {
        if (budget <= 0) break;
        state.assignments = currentAssignments;
        if (this.teacherBlockers(snapshot, state, post, teacher, matching).length > 0) {
          continue;
        }

        currentAssignments[post.id] = teacher;
        loads.set(teacher, (loads.get(teacher) ?? 0) + size);

        visit(index + 1, coverage + size);

        delete currentAssignments[post.id];
        loads.set(teacher, (loads.get(teacher) ?? 0) - size);
      }

      // Option to skip this post if cannot be assigned
      visit(index + 1, coverage);
    };

    visit(0, Object.keys(initialAssignments).length);

    return {
      ...draft,
      assignments: bestAssignments,
    };
  }
}
