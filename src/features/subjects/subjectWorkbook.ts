import type { ClassGroup, GradeGroup, SchoolStage, Subject } from '@/domain/models';
import { EMPTY_LESSONS, formatLessonValues, parseSubjectImportText, requirementKey,
  type LessonValues } from './subjectLogic';

const HEADERS = ['学段', '年级', '科目', '节数'];

export async function buildSubjectWorkbook(params: {
  stages: SchoolStage[]; grades: GradeGroup[]; classes: ClassGroup[];
  subjects: Subject[]; values: Record<string, LessonValues>; includeExisting: boolean;
}): Promise<Uint8Array> {
  const { utils, write } = await import('xlsx');
  const book = utils.book_new();
  utils.book_append_sheet(book, utils.aoa_to_sheet([
    ['科目节数导入说明'],
    ['填写位置', '请在“科目节数”工作表填写，名称参照“基础数据”。'],
    ['范围', '每行填写一个年级的一门科目；同一年级同一科目只能填写一次。'],
    ['统一节数', '填写 3 表示年级所有班级每周 3 节；填写 0 可以清零。'],
    ['按班区分', '用英文逗号按“基础数据”的班级顺序填写，例如 3,2。'],
    ['单双周', '按“每周|单周|双周”填写，例如 2|1|1。'],
    ['导入方式', '仅更新表中填写的年级和科目；导入后还需在页面保存。'],
  ]), '导入说明');
  const references = [['学段', '年级', '班级顺序（逗号对应顺序）', '科目（独立列表）']];
  for (let index = 0; index < Math.max(params.grades.length, params.subjects.length); index++) {
    const grade = params.grades[index];
    references.push([
      params.stages.find((item) => item.id === grade?.stageId)?.name ?? '',
      grade?.name ?? '',
      params.classes.filter((item) => item.gradeId === grade?.id)
        .sort((a, b) => a.sortOrder - b.sortOrder).map((item) => item.name).join('、'),
      params.subjects[index]?.name ?? '',
    ]);
  }
  utils.book_append_sheet(book, utils.aoa_to_sheet(references), '基础数据');
  const rows: string[][] = [HEADERS];
  if (params.includeExisting) {
    for (const grade of params.grades) {
      const group = params.classes.filter((item) => item.gradeId === grade.id)
        .sort((a, b) => a.sortOrder - b.sortOrder);
      if (!group.length) continue;
      for (const subject of params.subjects) {
        const values = group.map((item) => params.values[requirementKey(subject.id, item.id)] ?? EMPTY_LESSONS);
        if (values.every((item) => item.weekly === 0 && item.odd === 0 && item.even === 0)) continue;
        const first = formatLessonValues(values[0]);
        const text = values.every((item) => formatLessonValues(item) === first)
          ? first : values.map(formatLessonValues).join(',');
        rows.push([params.stages.find((item) => item.id === grade.stageId)?.name ?? '',
          grade.name, subject.name, text]);
      }
    }
  }
  utils.book_append_sheet(book, utils.aoa_to_sheet(rows), '科目节数');
  return new Uint8Array(write(book, { bookType: 'xlsx', type: 'array' }) as ArrayBuffer);
}

export async function parseSubjectWorkbook(
  bytes: Uint8Array, stages: SchoolStage[], grades: GradeGroup[],
  classes: ClassGroup[], subjects: Subject[], alternating: boolean
): Promise<{ values: Record<string, LessonValues>; errors: string[] }> {
  try {
    const { read, utils } = await import('xlsx');
    const book = read(bytes, { type: 'array' });
    const sheet = book.Sheets['科目节数'];
    if (!sheet) return { values: {}, errors: ['缺少“科目节数”工作表，请使用导入模板'] };
    const rows = utils.sheet_to_json<unknown[]>(sheet, { header: 1, raw: false, defval: '' });
    const text = rows.map((row) => row.map((cell) => String(cell ?? '')).join('\t')).join('\n');
    return parseSubjectImportText(text, stages, grades, classes, subjects, alternating);
  } catch {
    return { values: {}, errors: ['无法读取 Excel，请选择有效的 .xlsx 文件'] };
  }
}
