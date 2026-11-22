/**
 * 课集 (ClassSet) 主题与科目色散列引擎
 * 100% 对齐 lib/core/theme/app_theme.dart 与 lib/core/theme/subject_colors.dart
 */

export type AppPalette = 'sky' | 'teal' | 'cloud';
export type AppAppearanceMode = 'system' | 'light' | 'dark';

export interface AppAppearance {
  palette: AppPalette;
  mode: AppAppearanceMode;
}

export interface PaletteMeta {
  id: AppPalette;
  label: string;
  description: string;
  lightPreview: { accent: string; canvas: string; surface: string };
  darkPreview: { accent: string; canvas: string; surface: string };
}

export const PALETTE_OPTIONS: PaletteMeta[] = [
  {
    id: 'sky',
    label: '晴空蓝',
    description: '清透的冷白画布与清晰蓝色交互（默认）',
    lightPreview: { accent: '#2864DC', canvas: '#F4F7FC', surface: '#FFFFFF' },
    darkPreview: { accent: '#97BAFF', canvas: '#111722', surface: '#1B2433' },
  },
  {
    id: 'teal',
    label: '海盐青',
    description: '舒缓的青绿调日程画布，适合长时间排课审阅',
    lightPreview: { accent: '#087D89', canvas: '#F2F9F9', surface: '#FFFFFF' },
    darkPreview: { accent: '#78D7D6', canvas: '#101C20', surface: '#1B2A30' },
  },
  {
    id: 'cloud',
    label: '云白墨灰',
    description: '低饱和中性灰蓝，让十种科目色标更加突出',
    lightPreview: { accent: '#3E4F6D', canvas: '#F6F7F9', surface: '#FFFFFF' },
    darkPreview: { accent: '#BDCEE9', canvas: '#15181E', surface: '#21262F' },
  },
];

export interface SubjectColorPair {
  name: string;
  lightFg: string;
  darkFg: string;
  lightBgAlpha: string;
  darkBgAlpha: string;
}

/**
 * 十种科目色板：严格对齐 DESIGN.md 第 7 节色表
 */
export const SUBJECT_COLOR_PALETTE: SubjectColorPair[] = [
  { name: '蔷薇', lightFg: '#A1396D', darkFg: '#F3ACCE', lightBgAlpha: 'rgba(161, 57, 109, 0.08)', darkBgAlpha: 'rgba(243, 172, 206, 0.12)' },
  { name: '杏橙', lightFg: '#9B521E', darkFg: '#F1BC92', lightBgAlpha: 'rgba(155, 82, 30, 0.08)', darkBgAlpha: 'rgba(241, 188, 146, 0.12)' },
  { name: '琥珀', lightFg: '#806314', darkFg: '#E6D18D', lightBgAlpha: 'rgba(128, 99, 20, 0.08)', darkBgAlpha: 'rgba(230, 209, 141, 0.12)' },
  { name: '青柠', lightFg: '#4F7029', darkFg: '#B8D98D', lightBgAlpha: 'rgba(79, 112, 41, 0.08)', darkBgAlpha: 'rgba(184, 217, 141, 0.12)' },
  { name: '薄荷', lightFg: '#1F7457', darkFg: '#91DABB', lightBgAlpha: 'rgba(31, 116, 87, 0.08)', darkBgAlpha: 'rgba(145, 218, 187, 0.12)' },
  { name: '湖青', lightFg: '#117783', darkFg: '#88D7DE', lightBgAlpha: 'rgba(17, 119, 131, 0.08)', darkBgAlpha: 'rgba(136, 215, 222, 0.12)' },
  { name: '晴蓝', lightFg: '#326CAB', darkFg: '#A1C8FA', lightBgAlpha: 'rgba(50, 108, 171, 0.08)', darkBgAlpha: 'rgba(161, 200, 250, 0.12)' },
  { name: '鸢尾', lightFg: '#5C56AC', darkFg: '#B9B3FA', lightBgAlpha: 'rgba(92, 86, 172, 0.08)', darkBgAlpha: 'rgba(185, 179, 250, 0.12)' },
  { name: '丁香', lightFg: '#8253A3', darkFg: '#D2AEED', lightBgAlpha: 'rgba(130, 83, 163, 0.08)', darkBgAlpha: 'rgba(210, 174, 237, 0.12)' },
  { name: '莓粉', lightFg: '#9C477D', darkFg: '#E5ABD3', lightBgAlpha: 'rgba(156, 71, 125, 0.08)', darkBgAlpha: 'rgba(229, 171, 211, 0.12)' },
];

/**
 * 与 Flutter 端 SubjectColors.indexOf 完全一致的 FNV-1a 32 位散列算法，
 * 确保同一科目 ID 在老 Flutter 库与新 Tauri/Web 端呈现完全一致的颜色。
 */
export function getSubjectColorIndex(subjectId: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < subjectId.length; i++) {
    hash ^= subjectId.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  hash = (hash ^ (hash >>> 15)) >>> 0;
  hash = Math.imul(hash, 0x2545f491) >>> 0;
  hash = (hash ^ (hash >>> 13)) >>> 0;
  return hash % SUBJECT_COLOR_PALETTE.length;
}

export function getSubjectColor(subjectId: string, isDark: boolean) {
  const entry = SUBJECT_COLOR_PALETTE[getSubjectColorIndex(subjectId)];
  return {
    name: entry.name,
    foreground: isDark ? entry.darkFg : entry.lightFg,
    background: isDark ? entry.darkBgAlpha : entry.lightBgAlpha,
  };
}
