import { describe, expect, it } from 'vitest';
import type { ScheduleItem } from '@/domain/models';
import { buildTeacherWorkload, selectWorkloadDays } from '@/components/charts/teacherWorkload';

const teachers = [
  { id: 'a', name: '李老师', displayQualifier: '小学' },
  { id: 'b', name: '李老师', displayQualifier: '初中' },
  { id: 'c', name: '王老师', displayQualifier: null },
];
const lesson = (id: string, changes: Partial<ScheduleItem> = {}): ScheduleItem => ({
  id, termId: 'term', teacherId: 'a', subjectId: 'subject', assignmentId: 'assignment',
  classId: 'class-1', weekMode: 'weekly', combinedGroupId: null, meetingId: null,
  stageId: 'stage', weekday: 1, periodTypeId: 'morning', lessonIndex: 1,
  ...changes,
});
const items = [
  lesson('1', { combinedGroupId: 'group', meetingId: 'meeting' }),
  lesson('2', { combinedGroupId: 'group', meetingId: 'meeting', classId: 'class-2' }),
  lesson('3', { weekMode: 'odd', weekday: 7 }),
  lesson('4', { weekday: null, lessonIndex: null }),
  lesson('5', { teacherId: null }),
  lesson('6', { teacherId: 'removed-teacher' }),
];
const draft = {
  posts: [
    { id: 'covered', weekday: 6, lessonIndices: [1, 2, 3] },
    { id: 'unassigned', weekday: 2, lessonIndices: [1, 2] },
  ],
  assignments: { covered: 'b', removed: 'a' },
};

describe('teacher workload', () => {
  it('ranks teaching, supervision, and combined loads using each weekday’s lesson counts', () => {
    expect(buildTeacherWorkload(teachers, items, draft, 'teaching', 'odd')).toMatchObject([
      { teacherId: 'a', teacherName: '李老师 · 小学', total: 2, day1: 1, day7: 1 },
      { teacherId: 'b', total: 0 },
      { teacherId: 'c', total: 0 },
    ]);
    expect(buildTeacherWorkload(teachers, items, draft, 'supervision', 'odd')).toMatchObject([
      { teacherId: 'b', teacherName: '李老师 · 初中', total: 3, day6: 3 },
      { teacherId: 'a', total: 0 },
      { teacherId: 'c', total: 0 },
    ]);
    expect(buildTeacherWorkload(teachers, items, draft, 'combined', 'even')).toMatchObject([
      { teacherId: 'b', total: 3, day6: 3 },
      { teacherId: 'a', total: 1, day1: 1, day7: 0 },
      { teacherId: 'c', total: 0 },
    ]);
  });

  it('adds both kinds on a shared weekday using the selected supervision assignments', () => {
    const selectedDraft = { posts: [{ id: 'other', weekday: 1, lessonIndices: [2, 3] }], assignments: { other: 'a' } };
    expect(buildTeacherWorkload(teachers, items, selectedDraft, 'combined', 'odd')[0])
      .toMatchObject({ teacherId: 'a', total: 4, day1: 3, day7: 1 });
  });

  it('ranks by visible weekdays and keeps the full-week counts available when restoring a day', () => {
    const rows = buildTeacherWorkload(teachers, items, draft, 'combined', 'odd');
    expect(selectWorkloadDays(rows, ['day1', 'day7'])).toMatchObject([
      { teacherId: 'a', total: 2, topDay: 'day7' },
      { teacherId: 'b', total: 0, topDay: null },
      { teacherId: 'c', total: 0, topDay: null },
    ]);
    expect(selectWorkloadDays(rows, ['day1', 'day6', 'day7'])[0])
      .toMatchObject({ teacherId: 'b', total: 3, topDay: 'day6' });
    expect(selectWorkloadDays(rows, []).every((row) => row.total === 0)).toBe(true);
  });
});
