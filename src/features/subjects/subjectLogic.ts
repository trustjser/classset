import type {
  ClassGroup, FreeSlot, GradeGroup, SchoolStage, StageRoutine, Subject, SubjectRequirement, WeekMode,
} from '@/domain/models';

export interface LessonValues { weekly: number; odd: number; even: number }
export const EMPTY_LESSONS: LessonValues = { weekly: 0, odd: 0, even: 0 };

export function requirementKey(subjectId: string, classId: string): string {
  return `${subjectId}:${classId}`;
}

export function valuesForClass(
  requirements: SubjectRequirement[], subjectId: string, schoolClass: ClassGroup
): LessonValues {
  const values = { ...EMPTY_LESSONS };
  for (const row of requirements) {
    if (row.subjectId === subjectId && row.gradeId === schoolClass.gradeId && row.classId === null) {
      values[row.weekMode] = row.lessonCount;
    }
  }
  for (const row of requirements) {
    if (row.subjectId === subjectId && row.classId === schoolClass.id) {
      values[row.weekMode] = row.lessonCount;
    }
  }
  return values;
}

export function parseLessonInput(input: string, alternating: boolean): LessonValues[] | null {
  if (!input.trim()) return [];
  const groups = input.split(',');
  const values: LessonValues[] = [];
  for (const group of groups) {
    const parts = group.trim().split('|');
    if (parts.length !== 1 && !(alternating && parts.length === 3)) return null;
    const numbers = parts.map((part) => Number(part.trim()));
    if (parts.some((part) => !/^\d+$/.test(part.trim())) ||
        numbers.some((number) => !Number.isSafeInteger(number) || number < 0)) return null;
    values.push({ weekly: numbers[0], odd: numbers[1] ?? 0, even: numbers[2] ?? 0 });
  }
  return values;
}

export function formatLessonValues(values: LessonValues): string {
  return values.odd || values.even
    ? `${values.weekly}|${values.odd}|${values.even}`
    : String(values.weekly);
}

export function formatGradeCell(values: LessonValues[]): string {
  if (!values.length) return '—';
  const first = formatLessonValues(values[0]);
  return values.every((value) => formatLessonValues(value) === first) ? first : '各班不同';
}

export function applyGradeInput(
  current: Record<string, LessonValues>,
  subjectId: string,
  classes: ClassGroup[],
  input: string,
  alternating: boolean
): Record<string, LessonValues> | null {
  const parsed = parseLessonInput(input, alternating);
  if (parsed === null || (parsed.length > 1 && parsed.length !== classes.length)) return null;
  const next = { ...current };
  classes.forEach((schoolClass, index) => {
    next[requirementKey(subjectId, schoolClass.id)] = parsed.length
      ? { ...parsed[Math.min(index, parsed.length - 1)] }
      : { ...EMPTY_LESSONS };
  });
  return next;
}

export function makeRequirementRows(
  subjects: string[], classes: ClassGroup[], values: Record<string, LessonValues>,
  existing: SubjectRequirement[]
): SubjectRequirement[] {
  const existingIds = new Map(existing.map((row) => [`${row.subjectId}:${row.classId}:${row.weekMode}`, row.id]));
  const rows: SubjectRequirement[] = [];
  for (const schoolClass of classes) {
    for (const subjectId of subjects) {
      const cell = values[requirementKey(subjectId, schoolClass.id)] ?? EMPTY_LESSONS;
      for (const mode of ['weekly', 'odd', 'even'] as WeekMode[]) {
        if (cell[mode] <= 0) continue;
        rows.push({
          id: existingIds.get(`${subjectId}:${schoolClass.id}:${mode}`) ?? crypto.randomUUID(),
          subjectId, gradeId: schoolClass.gradeId, classId: schoolClass.id,
          weekMode: mode, lessonCount: cell[mode],
        });
      }
    }
  }
  return rows;
}

export function capacityForClass(
  routine: StageRoutine, freeSlots: FreeSlot[], termId: string,
  grade: GradeGroup, schoolClass: ClassGroup
): number {
  let total = 0;
  const teachingDays = routine.teachingDays.filter((day) => day.isTeachingDay);
  for (const day of teachingDays) {
    for (const period of routine.periodTypes) {
      const override = routine.dailyOverrides.find(
        (item) => item.periodTypeId === period.id && item.weekday === day.weekday
      );
      total += override?.lessonCount ?? period.defaultLessonCount;
    }
  }
  const occupied = new Set<string>();
  for (const slot of freeSlots) {
    if (slot.stageId !== grade.stageId) continue;
    const matches = slot.scopeType === 'school' && slot.scopeId === termId ||
      slot.scopeType === 'stage' && slot.scopeId === grade.stageId ||
      slot.scopeType === 'grade' && slot.scopeId === grade.id ||
      slot.scopeType === 'class' && slot.scopeId === schoolClass.id;
    if (matches) occupied.add(`${slot.weekday}:${slot.periodTypeId}:${slot.lessonIndex}`);
  }
  return Math.max(0, total - occupied.size);
}

export interface GradeCapacity {
  className: string;
  weekly: number;
  odd: number;
  even: number;
  available: number;
  excess: number;
}

export function summarizeGradeCapacity(
  grade: GradeGroup, classes: ClassGroup[], subjectIds: string[],
  values: Record<string, LessonValues>, routine: StageRoutine | undefined,
  freeSlots: FreeSlot[], termId: string
): GradeCapacity | null {
  if (!classes.length || !routine) return null;
  let mostPressed: GradeCapacity | null = null;
  for (const schoolClass of classes) {
    const available = capacityForClass(routine, freeSlots, termId, grade, schoolClass);
    let weekly = 0, odd = 0, even = 0;
    for (const subjectId of subjectIds) {
      const value = values[requirementKey(subjectId, schoolClass.id)] ?? EMPTY_LESSONS;
      weekly += value.weekly;
      odd += value.odd;
      even += value.even;
    }
    const item = { className: schoolClass.name, weekly, odd, even, available,
      excess: Math.max(0, weekly + Math.max(odd, even) - available) };
    if (!mostPressed || item.excess > mostPressed.excess ||
        item.excess === mostPressed.excess && weekly + Math.max(odd, even) - available >
        mostPressed.weekly + Math.max(mostPressed.odd, mostPressed.even) - mostPressed.available) {
      mostPressed = item;
    }
  }
  return mostPressed;
}

export function parseSubjectImportText(
  text: string, stages: SchoolStage[], grades: GradeGroup[], classes: ClassGroup[],
  subjects: Subject[], alternating: boolean
): { values: Record<string, LessonValues>; errors: string[] } {
  const lines = text.replace(/^\uFEFF/, '').trim().split(/\r?\n/);
  const headers = lines[0]?.split('\t').map((item) => item.trim()) ?? [];
  if (['学段', '年级', '科目', '节数'].some((header) =>
    headers.filter((item) => item === header).length !== 1)) {
    return { values: {}, errors: ['表头需要包含“学段、年级、科目、节数”，请直接从 Excel 复制这四列'] };
  }
  const values: Record<string, LessonValues> = {};
  const errors: string[] = [];
  for (let index = 1; index < lines.length; index++) {
    const cells = lines[index].split('\t');
    if (cells.every((item) => !item.trim())) continue;
    const at = (header: string) => (cells[headers.indexOf(header)] ?? '').trim();
    const stageMatches = stages.filter((item) => item.name.trim() === at('学段'));
    const gradeMatches = grades.filter((item) => item.stageId === stageMatches[0]?.id && item.name.trim() === at('年级'));
    const subjectMatches = subjects.filter((item) => item.name.trim() === at('科目'));
    const group = classes.filter((item) => item.gradeId === gradeMatches[0]?.id)
      .sort((a, b) => a.sortOrder - b.sortOrder);
    const parsed = parseLessonInput(at('节数'), alternating);
    const row = index + 1;
    if (stageMatches.length !== 1) errors.push(`第 ${row} 行：学段不存在或名称不唯一`);
    else if (gradeMatches.length !== 1) errors.push(`第 ${row} 行：年级不存在或名称不唯一`);
    else if (subjectMatches.length !== 1) errors.push(`第 ${row} 行：科目不存在或名称不唯一`);
    else if (!group.length) errors.push(`第 ${row} 行：该年级没有班级`);
    else if (!parsed?.length || parsed.length > 1 && parsed.length !== group.length) errors.push(`第 ${row} 行：节数格式或班级数量不匹配`);
    else {
      group.forEach((schoolClass, classIndex) => {
        const key = requirementKey(subjectMatches[0].id, schoolClass.id);
        if (values[key]) errors.push(`第 ${row} 行：${schoolClass.name} 的 ${subjectMatches[0].name} 重复`);
        else values[key] = parsed[Math.min(classIndex, parsed.length - 1)];
      });
    }
  }
  if (!Object.keys(values).length && !errors.length) errors.push('没有可导入的数据');
  return { values: errors.length ? {} : values, errors };
}
