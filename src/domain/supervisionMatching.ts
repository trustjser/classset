import type { ScheduleData } from './scheduling.ts';
import type {
  SupervisionDraft,
  SupervisionPost,
  SupervisionPreference,
} from './supervision.ts';
import { preferencesForPost } from './supervision.ts';

export class SupervisionMatching {
  private readonly snapshot: ScheduleData;
  private readonly classes = new Map<string, Set<string>>();
  private readonly grades = new Map<string, Set<string>>();
  private readonly subjects = new Map<string, Set<string>>();
  private readonly classToGrade = new Map<string, string>();

  constructor(snapshot: ScheduleData) {
    this.snapshot = snapshot;
    for (const schoolClass of snapshot.classes) {
      this.classToGrade.set(schoolClass.id, schoolClass.gradeId);
    }

    for (const assignment of snapshot.assignments) {
      if (
        assignment.termId !== snapshot.term.id ||
        assignment.lessonCount <= 0 ||
        !assignment.teacherId
      ) {
        continue;
      }
      const teacherId = assignment.teacherId;
      if (!this.classes.has(teacherId)) {
        this.classes.set(teacherId, new Set());
      }
      this.classes.get(teacherId)!.add(assignment.classId);

      const gradeId = this.classToGrade.get(assignment.classId);
      if (gradeId) {
        if (!this.grades.has(teacherId)) {
          this.grades.set(teacherId, new Set());
        }
        this.grades.get(teacherId)!.add(gradeId);
      }

      if (!this.subjects.has(teacherId)) {
        this.subjects.set(teacherId, new Set());
      }
      this.subjects.get(teacherId)!.add(assignment.subjectId);
    }
  }

  activePreferences(draft: SupervisionDraft, post: SupervisionPost): SupervisionPreference[] {
    const prefs = preferencesForPost(draft, post);
    const enabledSet = new Set(prefs.enabled);
    return prefs.order.filter((preference) => {
      if (!enabledSet.has(preference)) return false;
      if (
        preference === 'subjectTeacher' &&
        (!post.targetSubjectIds || post.targetSubjectIds.length === 0)
      ) {
        return false;
      }
      return true;
    });
  }

  count(preference: SupervisionPreference, post: SupervisionPost, teacher: string): number {
    switch (preference) {
      case 'classTeacher': {
        const teacherClasses = this.classes.get(teacher);
        if (!teacherClasses) return 0;
        return post.classIds.filter((id) => teacherClasses.has(id)).length;
      }
      case 'gradeTeacher': {
        const teacherGrades = this.grades.get(teacher);
        if (!teacherGrades) return 0;
        return post.classIds.filter((id) => {
          const g = this.classToGrade.get(id);
          return g ? teacherGrades.has(g) : false;
        }).length;
      }
      case 'subjectTeacher': {
        const teacherSubjects = this.subjects.get(teacher);
        if (!teacherSubjects || !post.targetSubjectIds) return 0;
        return post.targetSubjectIds.some((id) => teacherSubjects.has(id)) ? 1 : 0;
      }
    }
  }

  complete(preference: SupervisionPreference, post: SupervisionPost, teacher: string): boolean {
    const expected = preference === 'subjectTeacher' ? 1 : post.classIds.length;
    return this.count(preference, post, teacher) === expected;
  }

  ranks(draft: SupervisionDraft, post: SupervisionPost, teacher: string): number[] {
    return this.activePreferences(draft, post).map((preference) =>
      this.count(preference, post, teacher)
    );
  }

  meetsRequirement(draft: SupervisionDraft, post: SupervisionPost, teacher: string): boolean {
    const active = this.activePreferences(draft, post);
    if (active.length === 0) return true;
    const req = preferencesForPost(draft, post).requirement;
    switch (req) {
      case 'none':
        return true;
      case 'any':
        return active.some((item) => this.complete(item, post, teacher));
      case 'all':
        return active.every((item) => this.complete(item, post, teacher));
    }
  }

  hasUnmetPreferences(draft: SupervisionDraft, post: SupervisionPost, teacher: string): boolean {
    return this.activePreferences(draft, post).some((item) => !this.complete(item, post, teacher));
  }

  reasons(post: SupervisionPost, teacher: string): string[] {
    const list: string[] = [];
    const classCount = this.count('classTeacher', post, teacher);
    if (classCount > 0) {
      list.push(
        post.classIds.length === 1 ? '任教本班' : `任教 ${classCount}/${post.classIds.length} 个班`
      );
    }

    const gradeCount = this.count('gradeTeacher', post, teacher);
    if (gradeCount > 0) {
      list.push(
        this.complete('gradeTeacher', post, teacher) ? '任教本年级' : '任教部分年级'
      );
    }

    if (post.targetSubjectIds && post.targetSubjectIds.length > 0) {
      const teacherSubjects = this.subjects.get(teacher);
      if (teacherSubjects) {
        for (const subject of this.snapshot.subjects) {
          if (post.targetSubjectIds.includes(subject.id) && teacherSubjects.has(subject.id)) {
            list.push(`任教${subject.name}`);
          }
        }
      }
    }

    return list;
  }

  lessons(draft: SupervisionDraft, teacher: string, excludingPostId?: string): number {
    let sum = 0;
    for (const post of draft.posts) {
      if (post.id !== excludingPostId && draft.assignments[post.id] === teacher) {
        sum += post.lessonIndices.length;
      }
    }
    return sum;
  }

  days(draft: SupervisionDraft, teacher: string, excludingPostId?: string): Set<number> {
    const daysSet = new Set<number>();
    for (const post of draft.posts) {
      if (post.id !== excludingPostId && draft.assignments[post.id] === teacher) {
        daysSet.add(post.weekday);
      }
    }
    return daysSet;
  }

  compare(draft: SupervisionDraft, post: SupervisionPost, a: string, b: string): number {
    const preferenceOrder = (): number => {
      const first = this.ranks(draft, post, a);
      const second = this.ranks(draft, post, b);
      for (let i = 0; i < first.length; i++) {
        const order = second[i] - first[i];
        if (order !== 0) return order;
      }
      return 0;
    };

    const loadOrder = this.lessons(draft, a) - this.lessons(draft, b);
    const mode = preferencesForPost(draft, post).mode;
    if (mode === 'balanceFirst' && loadOrder !== 0) {
      return loadOrder;
    }

    const pref = preferenceOrder();
    if (pref !== 0) return pref;
    return loadOrder === 0 ? a.localeCompare(b) : loadOrder;
  }
}
