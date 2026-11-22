/**
 * 年级与班级命名模板引擎
 * 100% 对齐 lib/features/classes/grade_name_templates.dart 与 classes_page.dart
 * - 年级占位符：{n} → 阿拉伯数字 (1, 2, 3...)；{N} → 中文数字 (一, 二, 三...)
 * - 班级批量填充模板：'{年级} {n} 班'、'{n} 班'（自动提取年级简称 + 括号序号，如 一(1)班）、自定义模板
 */

export const STAGE_PRESETS = ['小学部', '初中部', '高中部', '国际部'] as const;

export type GradeNamingMode = '中文数字' | '阿拉伯数字' | '自定义';

export const GRADE_NAMING_TEMPLATES: Record<Exclude<GradeNamingMode, '自定义'>, string> = {
  中文数字: '{N}年级',
  阿拉伯数字: '{n} 年级',
};

const CHINESE_DIGITS = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

export function toChineseNumeral(value: number): string {
  if (value < 10) return CHINESE_DIGITS[value] ?? String(value);
  if (value < 100) {
    const tens = Math.floor(value / 10);
    const units = value % 10;
    return `${tens === 1 ? '' : CHINESE_DIGITS[tens]}十${units === 0 ? '' : CHINESE_DIGITS[units]}`;
  }
  return String(value);
}

export function expandGradeTemplate(template: string, ordinal: number): string {
  return template
    .replaceAll('{n}', String(ordinal))
    .replaceAll('{N}', toChineseNumeral(ordinal));
}

/**
 * 为指定学段生成不与现有年级重名的连续模板名称
 */
export function generateGradeNames(params: {
  template: string;
  count: number;
  existingNames: Iterable<string>;
}): string[] {
  const { template, count, existingNames } = params;
  const clamped = Math.max(1, Math.min(9, count));
  if (!template.includes('{n}') && !template.includes('{N}')) {
    return [];
  }
  const used = new Set(Array.from(existingNames, (n) => n.trim()));
  const result: string[] = [];
  for (let ordinal = 1; result.length < clamped && ordinal < 100; ordinal++) {
    const candidate = expandGradeTemplate(template, ordinal).trim();
    if (!used.has(candidate)) {
      used.add(candidate);
      result.push(candidate);
    }
  }
  return result;
}

export const CLASS_BATCH_TEMPLATES = [
  '{年级}({n})班',
  '{年级} {n} 班',
  '{n} 班',
  '自定义…',
] as const;

export function getGradeShortName(gradeName: string): string {
  return gradeName.endsWith('年级')
    ? gradeName.slice(0, gradeName.length - 2)
    : gradeName;
}

/**
 * 根据选定的班级命名模板生成某年级下各班级的名称预览
 */
export function generateClassNamesForGrade(
  gradeName: string,
  classCount: number,
  templateMode: string,
  customTemplate: string
): string[] {
  const short = getGradeShortName(gradeName);
  return Array.from({ length: classCount }, (_, idx) => {
    const ordinal = idx + 1;
    switch (templateMode) {
      case '{年级}({n})班':
        return `${short}(${ordinal})班`;
      case '{n} 班':
        return `${short}（${ordinal}）班`;
      case '{年级} {n} 班':
        return `${gradeName} ${ordinal} 班`;
      default: {
        const raw = customTemplate.trim() || '{年级}({n})班';
        return raw
          .replaceAll('{n}', String(ordinal))
          .replaceAll('{N}', toChineseNumeral(ordinal))
          .replaceAll('{年级}', short);
      }
    }
  });
}
