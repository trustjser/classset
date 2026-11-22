import type { ClassGroup, GradeGroup, Subject } from '@/domain/models';
import {
  applyGradeInput, EMPTY_LESSONS, formatLessonValues, requirementKey,
  type LessonValues,
} from './subjectLogic';

export function matrixCellKey(subjectId: string, gradeId: string): string {
  return `${subjectId}:${gradeId}`;
}

export function rectangleKeys(
  subjects: Subject[], grades: GradeGroup[], anchor: { row: number; column: number },
  extent: { row: number; column: number }
): string[] {
  const keys: string[] = [];
  for (let row = Math.min(anchor.row, extent.row); row <= Math.max(anchor.row, extent.row); row++) {
    for (let column = Math.min(anchor.column, extent.column); column <= Math.max(anchor.column, extent.column); column++) {
      if (subjects[row] && grades[column]) keys.push(matrixCellKey(subjects[row].id, grades[column].id));
    }
  }
  return keys;
}

export interface MatrixChange {
  values: Record<string, LessonValues>;
  changedKeys: string[];
  cellCount: number;
  error: string | null;
}

export function applyMatrixCells(
  cellKeys: string[], text: string, classes: ClassGroup[],
  current: Record<string, LessonValues>, alternating: boolean
): MatrixChange {
  let values = { ...current };
  const changedKeys: string[] = [];
  for (const cellKey of cellKeys) {
    const [subjectId, gradeId] = cellKey.split(':');
    const group = classes.filter((item) => item.gradeId === gradeId)
      .sort((a, b) => a.sortOrder - b.sortOrder);
    if (!group.length) continue;
    const next = applyGradeInput(values, subjectId, group, text, alternating);
    if (!next) return { values: current, changedKeys: [], cellCount: 0, error: '节数格式无效或与班级数量不匹配' };
    values = next;
    changedKeys.push(...group.map((item) => requirementKey(subjectId, item.id)));
  }
  return { values, changedKeys, cellCount: cellKeys.length, error: null };
}

export function pasteMatrixGrid(
  text: string, anchorKey: string, selectedKeys: string[],
  subjects: Subject[], grades: GradeGroup[], classes: ClassGroup[],
  current: Record<string, LessonValues>, alternating: boolean
): MatrixChange {
  if (!text) return { values: current, changedKeys: [], cellCount: 0, error: '剪贴板没有合法的节数内容' };
  const rows = text.replace(/\r\n?/g, '\n').split('\n');
  if (rows.length > 1 && rows.at(-1) === '') rows.pop();
  const cells = rows.map((row) => row.split('\t'));
  if (cells.length === 1 && cells[0].length === 1 && selectedKeys.length > 1) {
    return applyMatrixCells(selectedKeys, cells[0][0], classes, current, alternating);
  }
  const [subjectId, gradeId] = anchorKey.split(':');
  const startRow = subjects.findIndex((item) => item.id === subjectId);
  const startColumn = grades.findIndex((item) => item.id === gradeId);
  if (startRow < 0 || startColumn < 0) return { values: current, changedKeys: [], cellCount: 0, error: '当前选中格不可用' };
  let values = { ...current };
  const changedKeys: string[] = [];
  let cellCount = 0;
  for (let row = 0; row < cells.length; row++) {
    for (let column = 0; column < cells[row].length; column++) {
      const subject = subjects[startRow + row], grade = grades[startColumn + column];
      if (!subject || !grade) continue;
      const result = applyMatrixCells([matrixCellKey(subject.id, grade.id)], cells[row][column], classes, values, alternating);
      if (result.error) return { values: current, changedKeys: [], cellCount: 0,
        error: `第 ${row + 1} 行第 ${column + 1} 列：${result.error}` };
      values = result.values;
      changedKeys.push(...result.changedKeys);
      cellCount++;
    }
  }
  return { values, changedKeys, cellCount, error: null };
}

export function copyMatrixText(
  selectedKeys: string[], subjects: Subject[], grades: GradeGroup[],
  classes: ClassGroup[], values: Record<string, LessonValues>
): string {
  const selected = new Set(selectedKeys);
  const rows = subjects.filter((item) => grades.some((grade) => selected.has(matrixCellKey(item.id, grade.id))));
  const columns = grades.filter((item) => subjects.some((subject) => selected.has(matrixCellKey(subject.id, item.id))));
  return rows.map((subject) => columns.map((grade) => {
    const group = classes.filter((item) => item.gradeId === grade.id)
      .sort((a, b) => a.sortOrder - b.sortOrder);
    const parts = group.map((item) => formatLessonValues(values[requirementKey(subject.id, item.id)] ?? EMPTY_LESSONS));
    return parts.every((part) => part === parts[0]) ? parts[0] ?? '' : parts.join(',');
  }).join('\t')).join('\n');
}
