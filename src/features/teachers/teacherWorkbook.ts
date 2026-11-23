import type { ClassGroup, GradeGroup, SchoolStage, Subject, Teacher, TeacherAssignment, TeacherGroup, TeacherGroupMember, WeekMode } from '@/domain/models';

export interface ImportedTeacher { name: string; shortName: string; groups: string[]; subjects: string[] }
export interface ImportedAssignment { stage: string; grade: string; schoolClass: string; subject: string; teacher: string; weekMode: WeekMode; lessonCount: number }
const modeByLabel: Record<string, WeekMode> = { 每周: 'weekly', 单周: 'odd', 双周: 'even' };
const modeLabel: Record<WeekMode, string> = { weekly: '每周', odd: '单周', even: '双周' };

async function rowsFromWorkbook(bytes: Uint8Array, sheetName: string, headers: string[]): Promise<string[][]> {
  const { read, utils } = await import('xlsx');
  const book = read(bytes, { type: 'array' });
  const sheet = book.Sheets[sheetName] ?? book.Sheets[book.SheetNames[0]];
  if (!sheet) throw new Error('工作表为空');
  const rows = utils.sheet_to_json<unknown[]>(sheet, { header: 1, raw: false, defval: '' }).map((row) => row.map((cell) => String(cell ?? '').trim()));
  if (!rows.length || headers.some((header) => !rows[0].includes(header))) throw new Error(`表头须包含：${headers.join('、')}`);
  return rows;
}

export async function parseTeachersWorkbook(bytes: Uint8Array): Promise<ImportedTeacher[]> {
  const rows = await rowsFromWorkbook(bytes, '教师', ['教师', '简称']);
  const columns = rows[0];
  const at = (row: string[], name: string) => row[columns.indexOf(name)] ?? '';
  const split = (text: string) => [...new Set(text.split(/[,，]/).map((item) => item.trim()).filter(Boolean))];
  const result = rows.slice(1).filter((row) => row.some(Boolean)).map((row, index) => {
    const name = at(row, '教师'); if (!name) throw new Error(`第 ${index + 2} 行教师姓名不能为空`);
    return { name, shortName: at(row, '简称'), groups: split(at(row, '分组')), subjects: split(at(row, '任课科目')) };
  });
  if (!result.length) throw new Error('没有可导入的教师数据');
  if (new Set(result.map((item) => item.name)).size !== result.length) throw new Error('工作簿有重复的教师姓名，请先核对');
  return result;
}

export async function parseAssignmentsWorkbook(bytes: Uint8Array): Promise<ImportedAssignment[]> {
  const headers = ['学段', '年级', '班级', '科目', '教师', '周模式', '节数'];
  const rows = await rowsFromWorkbook(bytes, '任课分配', headers);
  const columns = rows[0];
  const result = rows.slice(1).filter((row) => row.some(Boolean)).map((row, index) => {
    const at = (name: string) => row[columns.indexOf(name)] ?? '';
    const weekMode = modeByLabel[at('周模式')];
    const lessonCount = Number(at('节数'));
    if (!weekMode || !Number.isInteger(lessonCount) || lessonCount <= 0) throw new Error(`第 ${index + 2} 行周模式或节数无效`);
    return { stage: at('学段'), grade: at('年级'), schoolClass: at('班级'), subject: at('科目'), teacher: at('教师'), weekMode, lessonCount };
  });
  if (!result.length) throw new Error('没有可导入的任课数据');
  return result;
}

export async function buildTeachersWorkbook(teachers: Teacher[], groups: TeacherGroup[], members: TeacherGroupMember[], subjects: Subject[]): Promise<Uint8Array> {
  const { utils, write } = await import('xlsx');
  const book = utils.book_new();
  utils.book_append_sheet(book, utils.aoa_to_sheet([
    ['教师导入说明'], ['表头', '教师、简称必填列；分组、任课科目为可选列'], ['填写', '多个分组或科目用英文逗号分隔'], ['导入', '导入后可预览，确认后追加或更新教师'],
  ]), '导入说明');
  utils.book_append_sheet(book, utils.aoa_to_sheet([
    ['教师', '简称', '分组', '任课科目'],
    ...teachers.map((teacher) => [teacher.name, teacher.shortName, members.filter((item) => item.teacherId === teacher.id).map((item) => groups.find((group) => group.id === item.groupId)?.name).filter(Boolean).join(','),
      subjects.filter((subject) => teacher.subjectIds?.includes(subject.id)).map((item) => item.name).join(',')]),
  ]), '教师');
  utils.book_append_sheet(book, utils.aoa_to_sheet([['科目'], ...subjects.map((item) => [item.name])]), '科目');
  return new Uint8Array(write(book, { bookType: 'xlsx', type: 'array' }) as ArrayBuffer);
}

export async function buildAssignmentsWorkbook(stages: SchoolStage[], grades: GradeGroup[], classes: ClassGroup[], subjects: Subject[], teachers: Teacher[], assignments: TeacherAssignment[]): Promise<Uint8Array> {
  const { utils, write } = await import('xlsx');
  const book = utils.book_new();
  utils.book_append_sheet(book, utils.aoa_to_sheet([['任课分配导入说明'], ['导入', '每行一项任课；确认后追加，不覆盖已有记录'], ['周模式', '填写每周、单周或双周'], ['节数', '必须为大于 0 的整数']]), '导入说明');
  utils.book_append_sheet(book, utils.aoa_to_sheet([['学段', '年级', '班级', '科目', '教师', '周模式', '节数'], ...assignments.map((item) => {
    const schoolClass = classes.find((row) => row.id === item.classId);
    const grade = grades.find((row) => row.id === schoolClass?.gradeId);
    return [stages.find((row) => row.id === grade?.stageId)?.name ?? '', grade?.name ?? '', schoolClass?.name ?? '', subjects.find((row) => row.id === item.subjectId)?.name ?? '', teachers.find((row) => row.id === item.teacherId)?.name ?? '', modeLabel[item.weekMode], item.lessonCount];
  })]), '任课分配');
  utils.book_append_sheet(book, utils.aoa_to_sheet([['学段', '年级', '班级', '科目', '教师'], ...classes.map((schoolClass) => {
    const grade = grades.find((row) => row.id === schoolClass.gradeId);
    return [stages.find((row) => row.id === grade?.stageId)?.name ?? '', grade?.name ?? '', schoolClass.name, subjects.map((item) => item.name).join('、'), teachers.map((item) => item.name).join('、')];
  })]), '数据源');
  return new Uint8Array(write(book, { bookType: 'xlsx', type: 'array' }) as ArrayBuffer);
}
