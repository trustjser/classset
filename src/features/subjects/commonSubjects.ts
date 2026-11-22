export const COMMON_SUBJECTS = [
  '语文', '数学', '外语', '物理', '化学', '生物', '历史', '地理', '政治',
  '科学', '道德与法治', '信息科技', '体育与健康', '艺术', '劳动',
  '综合实践活动', '音乐', '美术',
] as const;

export interface SubjectDraftInput { name: string; shortName: string }

export function firstSubjectCharacter(name: string): string {
  return Array.from(name.trim())[0] ?? '';
}

export function buildSubjectDraftInputs(params: {
  isNew: boolean;
  name: string;
  shortName: string;
  selectedCommonSubjects: string[];
  existingNames: string[];
}): { subjects: SubjectDraftInput[]; error: string | null } {
  const name = params.name.trim();
  const shortName = params.shortName.trim();
  const selected = new Set(params.isNew ? params.selectedCommonSubjects : []);
  const existing = new Set(params.existingNames);
  const needsManual = !params.isNew || selected.size === 0 || name !== '' || shortName !== '';

  if (needsManual && !name) return { subjects: [], error: '请输入科目全称' };
  if (needsManual && !shortName) return { subjects: [], error: '请输入简称' };
  if (needsManual && existing.has(name)) return { subjects: [], error: '已存在同名科目' };
  if (needsManual && selected.has(name)) return { subjects: [], error: '该科目已在常用科目中选中' };
  if ([...selected].some((item) => existing.has(item))) {
    return { subjects: [], error: '选中的常用科目已存在' };
  }

  return {
    subjects: [
      ...(needsManual ? [{ name, shortName }] : []),
      ...COMMON_SUBJECTS.filter((item) => selected.has(item)).map((item) => ({
        name: item, shortName: firstSubjectCharacter(item),
      })),
    ],
    error: null,
  };
}
