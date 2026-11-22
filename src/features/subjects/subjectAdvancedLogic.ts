import type { ClassGroup, GradeGroup, ScopeType, SchoolStage, SubjectLessonConstraint } from '@/domain/models';

export type ConstraintField = 'minimumDailyLessons' | 'maximumDailyLessons' |
  'minimumDailyConsecutivePairs' | 'maximumDailyConsecutivePairs' |
  'minimumWeeklyConsecutivePairs' | 'maximumWeeklyConsecutivePairs';

export function resolveConstraintField(
  rows: SubjectLessonConstraint[], classes: ClassGroup[], termId: string,
  scopeType: ScopeType, scopeId: string, stageId: string,
  weekday: number | null, field: ConstraintField,
): number | null {
  const chain: Array<[ScopeType, string]> = [[scopeType, scopeId]];
  if (scopeType === 'class') {
    const gradeId = classes.find((item) => item.id === scopeId)?.gradeId;
    if (gradeId) chain.push(['grade', gradeId]);
  }
  if (scopeType !== 'stage') chain.push(['stage', stageId]);
  chain.push(['school', termId]);
  for (const [type, id] of chain) {
    for (const day of weekday === null ? [null] : [weekday, null]) {
      const row = rows.find((item) => item.scopeType === type && item.scopeId === id &&
        item.stageId === stageId && item.weekday === day);
      if (row?.[field] !== null && row?.[field] !== undefined) return row[field];
    }
  }
  return null;
}

export function validateConstraintRanges(
  rows: SubjectLessonConstraint[], stages: SchoolStage[], grades: GradeGroup[],
  classes: ClassGroup[], teachingDaysByStage: Record<string, number[]>, termId: string,
): string | null {
  const scopes: Array<{ type: ScopeType; id: string; stageId: string; label: string }> = [
    ...stages.map((stage) => ({ type: 'stage' as const, id: stage.id, stageId: stage.id, label: stage.name })),
    ...grades.map((grade) => ({ type: 'grade' as const, id: grade.id, stageId: grade.stageId, label: grade.name })),
    ...classes.map((schoolClass) => ({ type: 'class' as const, id: schoolClass.id,
      stageId: grades.find((grade) => grade.id === schoolClass.gradeId)?.stageId ?? '', label: schoolClass.name })),
  ];
  for (const scope of scopes) {
    for (const day of [null, ...(teachingDaysByStage[scope.stageId] ?? [])]) {
      const values = (field: ConstraintField) => resolveConstraintField(rows, classes, termId,
        scope.type, scope.id, scope.stageId, day, field);
      for (const [minimum, maximum, label] of [
        ['minimumDailyLessons', 'maximumDailyLessons', '每日课节'],
        ['minimumDailyConsecutivePairs', 'maximumDailyConsecutivePairs', '每日连堂'],
      ] as Array<[ConstraintField, ConstraintField, string]>) {
        const min = values(minimum), max = values(maximum);
        if (min !== null && max !== null && min > max) {
          return scope.label + (day === null ? '每天' : '周' + day) + '的' + label + '上下限冲突';
        }
      }
    }
    const minWeekly = resolveConstraintField(rows, classes, termId, scope.type, scope.id,
      scope.stageId, null, 'minimumWeeklyConsecutivePairs');
    const maxWeekly = resolveConstraintField(rows, classes, termId, scope.type, scope.id,
      scope.stageId, null, 'maximumWeeklyConsecutivePairs');
    if (minWeekly !== null && maxWeekly !== null && minWeekly > maxWeekly) {
      return scope.label + '的每周连堂上下限冲突';
    }
  }
  return null;
}
