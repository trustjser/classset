import type { ClassGroup, Subject, SubjectRequirement, TeacherAssignment, TeacherGroupPreset, TeacherPreset, WeekMode, PresetValue } from '@/domain/models';
import { valuesForClass } from '@/features/subjects/subjectLogic';

export interface UnassignedCourse {
  classId: string;
  subjectId: string;
  weekMode: WeekMode;
  remainingLessons: number;
}

export interface CombinedLessonCandidate {
  key: string;
  subjectId: string;
  weekMode: WeekMode;
  lessonCount: number;
  rows: TeacherAssignment[];
}

export function combinedLessonCandidates(assignments: TeacherAssignment[], teacherId: string): CombinedLessonCandidate[] {
  const grouped = new Map<string, CombinedLessonCandidate>();
  for (const row of assignments) {
    if (row.teacherId !== teacherId || row.combinedLessonGroupId) continue;
    const key = `${row.subjectId}:${row.weekMode}:${row.lessonCount}`;
    const group = grouped.get(key) ?? { key, subjectId: row.subjectId, weekMode: row.weekMode, lessonCount: row.lessonCount, rows: [] };
    if (!group.rows.some((item) => item.classId === row.classId)) group.rows.push(row);
    grouped.set(key, group);
  }
  return [...grouped.values()].filter((item) => item.rows.length >= 2);
}

export function remainingCourses(classes: ClassGroup[], subjects: Subject[], requirements: SubjectRequirement[], assignments: TeacherAssignment[]): UnassignedCourse[] {
  const courses: UnassignedCourse[] = [];
  for (const schoolClass of classes) for (const subject of subjects) {
    const values = valuesForClass(requirements, subject.id, schoolClass);
    for (const weekMode of ['weekly', 'odd', 'even'] as const) {
      const required = values[weekMode];
      const assigned = assignments.filter((item) => item.classId === schoolClass.id && item.subjectId === subject.id && item.weekMode === weekMode && item.teacherId)
        .reduce((sum, item) => sum + item.lessonCount, 0);
      if (required > assigned) courses.push({ classId: schoolClass.id, subjectId: subject.id, weekMode, remainingLessons: required - assigned });
    }
  }
  return courses;
}

export function assignmentError(next: TeacherAssignment[], classes: ClassGroup[], subjects: Subject[], requirements: SubjectRequirement[], existing: TeacherAssignment[]): string | null {
  const validClasses = new Set(classes.map((item) => item.id));
  const validSubjects = new Set(subjects.map((item) => item.id));
  for (const item of next) {
    if (!validClasses.has(item.classId) || !validSubjects.has(item.subjectId) || !item.teacherId || !Number.isInteger(item.lessonCount) || item.lessonCount <= 0) return '请选择教师、班级、科目，并填写大于 0 的节数';
  }
  const all = [...existing, ...next];
  const touched = new Set(next.map((item) => JSON.stringify([item.classId, item.subjectId, item.weekMode])));
  for (const key of touched) {
      const [classId, subjectId, mode] = JSON.parse(key) as [string, string, WeekMode];
      const schoolClass = classes.find((item) => item.id === classId)!;
      const subject = subjects.find((item) => item.id === subjectId)!;
      const values = valuesForClass(requirements, subjectId, schoolClass);
      const count = all.filter((item) => item.classId === classId && item.subjectId === subjectId && item.weekMode === mode && item.teacherId)
        .reduce((sum, item) => sum + item.lessonCount, 0);
      if (count > values[mode]) return `${schoolClass.name} · ${subject.name} 的${mode === 'weekly' ? '每周' : mode === 'odd' ? '单周' : '双周'}任课超过科目节数需求`;
  }
  return null;
}

export function resolveTeacherPreset(personal: TeacherPreset | undefined, groups: TeacherGroupPreset[]): PresetValue | 'conflict' {
  if (personal && personal.value !== 'auto') return personal.value;
  const values = new Set(groups.filter((item) => item.value !== 'auto').map((item) => item.value));
  return values.size > 1 ? 'conflict' : values.values().next().value ?? 'auto';
}

export function teacherWeeklyLoad(assignments: TeacherAssignment[]): number {
  const countedGroups = new Set<string>();
  let doubled = 0;
  for (const item of assignments) {
    if (item.combinedLessonGroupId) {
      if (countedGroups.has(item.combinedLessonGroupId)) continue;
      countedGroups.add(item.combinedLessonGroupId);
    }
    doubled += item.lessonCount * (item.weekMode === 'weekly' ? 2 : 1);
  }
  return doubled / 2;
}
