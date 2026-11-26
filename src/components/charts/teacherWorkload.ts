import type { ScheduleItem, Teacher, WeekMode } from '@/domain/models';
import { occursInWeek, teachingMeetingKey } from '@/domain/scheduling';
import type { SupervisionDraft, SupervisionPost } from '@/domain/supervision';

export type TeacherWorkloadMode = 'teaching' | 'supervision' | 'combined';
export type WorkloadTeacher = Pick<Teacher, 'id' | 'name' | 'displayQualifier'>;
export type WorkloadSupervisionPlan = Pick<SupervisionDraft, 'assignments'> & {
  posts: readonly Pick<SupervisionPost, 'id' | 'weekday' | 'lessonIndices'>[];
};

const emptyDays = { day1: 0, day2: 0, day3: 0, day4: 0, day5: 0, day6: 0, day7: 0 };
export type WorkloadDay = keyof typeof emptyDays;

export function buildTeacherWorkload(
  teachers: readonly WorkloadTeacher[],
  items: readonly ScheduleItem[],
  plan: WorkloadSupervisionPlan | undefined,
  mode: TeacherWorkloadMode,
  week: WeekMode,
) {
  const rows = new Map(teachers.map((teacher) => [teacher.id, {
    teacherId: teacher.id,
    teacherName: [teacher.name, teacher.displayQualifier].filter(Boolean).join(' · '),
    total: 0,
    ...emptyDays,
  }]));

  const addLessons = (teacherId: string, weekday: number, count: number) => {
    const row = rows.get(teacherId);
    const day = `day${weekday}` as WorkloadDay;
    if (!row || !(day in emptyDays)) return;
    row[day] += count;
    row.total += count;
  };

  if (mode !== 'supervision') {
    const counted = new Set<string>();
    for (const item of items) {
      if (!item.teacherId || item.weekday == null || item.lessonIndex == null ||
          !occursInWeek(item.weekMode, week)) continue;
      const key = JSON.stringify([item.teacherId, teachingMeetingKey(item)]);
      if (counted.has(key)) continue;
      counted.add(key);
      addLessons(item.teacherId, item.weekday, 1);
    }
  }

  if (mode !== 'teaching' && plan) {
    for (const post of plan.posts) {
      const teacherId = plan.assignments[post.id];
      if (teacherId) addLessons(teacherId, post.weekday, post.lessonIndices.length);
    }
  }

  return [...rows.values()].sort((a, b) => b.total - a.total);
}

export function selectWorkloadDays(
  rows: ReturnType<typeof buildTeacherWorkload>,
  visibleDays: readonly WorkloadDay[],
) {
  return rows.map((row) => {
    let total = 0;
    let topDay: WorkloadDay | null = null;
    for (const day of visibleDays) {
      total += row[day];
      if (row[day] > 0) topDay = day;
    }
    return { ...row, total, topDay };
  }).sort((a, b) => b.total - a.total);
}
