import { isTauriDesktop } from '@/adapter/db/databaseAdapter';
import type { AcademicTerm, CommonPeriod, FreeSlot, ScheduleItem } from '@/domain/models';
import type { DutyOccurrence, ScheduleData } from '@/domain/scheduling';
import { timetableZip } from './timetableZip';

export type TimetablePrintFit = 'original' | 'width' | 'page';

export interface CellTextStyle {
  fontSize: number;
  bold: boolean;
  color: string;
}

export interface ExportOptions {
  teacherUnified: boolean;
  showTeacherStage: boolean;
  schoolWeekly: boolean;
  fontSize: number;
  subjectStyle: CellTextStyle;
  teacherStyle: CellTextStyle;
  classStyle: CellTextStyle;
  showTeacher: boolean;
  showClass: boolean;
  showTime: boolean;
  showWeek: boolean;
  printFit: TimetablePrintFit;
  landscape: boolean;
}

export const defaultExportOptions: ExportOptions = {
  teacherUnified: true,
  showTeacherStage: true,
  schoolWeekly: true,
  fontSize: 10,
  subjectStyle: {
    fontSize: 12,
    bold: true,
    color: '#000000',
  },
  teacherStyle: {
    fontSize: 10,
    bold: false,
    color: '#000000',
  },
  classStyle: {
    fontSize: 10,
    bold: false,
    color: '#000000',
  },
  showTeacher: true,
  showClass: true,
  showTime: true,
  showWeek: true,
  printFit: 'original',
  landscape: true,
};

export interface TimetableWorkbooks {
  classWorkbook: Uint8Array;
  teacherWorkbook: Uint8Array;
  schoolWorkbook: Uint8Array;
}

type CellStyleKey =
  | 'header'
  | 'slot'
  | 'common'
  | 'body'
  | 'title'
  | 'gridHeader'
  | 'gridSlot'
  | 'gridTitle'
  | 'gridCommon'
  | 'classSubject'
  | 'classDetail'
  | 'teacherSubject'
  | 'teacherDetail';

const STYLE_INDEX: Record<CellStyleKey, number> = {
  header: 1,
  slot: 2,
  common: 3,
  body: 4,
  title: 5,
  gridHeader: 6,
  gridSlot: 7,
  gridTitle: 8,
  gridCommon: 9,
  classSubject: 10,
  classDetail: 11,
  teacherSubject: 12,
  teacherDetail: 13,
};

interface ExportSlot {
  stageId: string;
  label: string;
  periodId: string | null;
  lessonIndex: number | null;
  start: number | null;
  end: number | null;
  common?: CommonPeriod;
  time: string;
  header: (showTime: boolean) => string;
}

interface RichTextLine {
  text: string;
  style: CellTextStyle;
}

interface SheetCell {
  value: string;
  style: CellStyleKey;
  richLines?: RichTextLine[];
}

interface MergeRange {
  s: { r: number; c: number };
  e: { r: number; c: number };
}

class SheetModel {
  readonly name: string;
  readonly rows = new Map<number, Map<number, SheetCell>>();
  readonly rowHeights = new Map<number, number>();
  readonly colWidths = new Map<number, number>();
  readonly merges: MergeRange[] = [];
  private readonly mergeKeys = new Set<string>();
  maxRow = 0;
  maxCol = 0;

  constructor(name: string) {
    this.name = name;
  }

  put(row: number, col: number, value: string, style: CellStyleKey, richLines?: RichTextLine[]): void {
    let r = this.rows.get(row);
    if (!r) {
      r = new Map();
      this.rows.set(row, r);
    }
    r.set(col, { value, style, richLines });
    if (row > this.maxRow) this.maxRow = row;
    if (col > this.maxCol) this.maxCol = col;
  }

  merge(startRow: number, startCol: number, endRow: number, endCol: number): void {
    const sR = Math.min(startRow, endRow);
    const eR = Math.max(startRow, endRow);
    const sC = Math.min(startCol, endCol);
    const eC = Math.max(startCol, endCol);
    const key = `${sR}:${sC}:${eR}:${eC}`;
    if (this.mergeKeys.has(key)) return;
    this.mergeKeys.add(key);
    this.merges.push({ s: { r: sR, c: sC }, e: { r: eR, c: eC } });
    if (eR > this.maxRow) this.maxRow = eR;
    if (eC > this.maxCol) this.maxCol = eC;
  }

  setMergedCellStyle(startRow: number, startCol: number, style: CellStyleKey): void {
    const found = this.merges.find((m) => m.s.r === startRow && m.s.c === startCol);
    if (!found) return;
    for (let r = found.s.r; r <= found.e.r; r++) {
      for (let c = found.s.c; c <= found.e.c; c++) {
        const existing = this.rows.get(r)?.get(c);
        this.put(r, c, existing?.value ?? '', style, existing?.richLines);
      }
    }
  }

  setRowHeight(row: number, height: number): void {
    this.rowHeights.set(row, height);
    if (row > this.maxRow) this.maxRow = row;
  }

  setColumnWidth(col: number, width: number): void {
    this.colWidths.set(col, width);
    if (col > this.maxCol) this.maxCol = col;
  }
}

class WorkbookBuilder {
  readonly sheets: SheetModel[] = [];
  private readonly usedNames = new Set<string>(['sheet1']);

  newSheet(requested: string): SheetModel {
    let name = requested
      .replace(/[\[\]:*?/\\]/g, ' ')
      .trim()
      .replace(/^'+|'+$/g, '');
    if (!name) name = '课表';
    if (name.length > 31) name = name.slice(0, 31);
    const base = name;
    let suffix = 2;
    while (this.usedNames.has(name.toLowerCase())) {
      const part = `(${suffix})`;
      const maxLen = Math.max(0, 31 - part.length);
      name = `${base.slice(0, maxLen)}${part}`;
      suffix++;
    }
    this.usedNames.add(name.toLowerCase());
    const sheet = new SheetModel(name);
    this.sheets.push(sheet);
    return sheet;
  }
}

function weekdayLabel(value: number): string {
  switch (value) {
    case 1: return '一';
    case 2: return '二';
    case 3: return '三';
    case 4: return '四';
    case 5: return '五';
    case 6: return '六';
    default: return '日';
  }
}

function formatClock(minute: number | null | undefined): string {
  if (minute == null) return '';
  const h = Math.floor(minute / 60).toString().padStart(2, '0');
  const m = (minute % 60).toString().padStart(2, '0');
  return `${h}:${m}`;
}

function createExportSlot(params: {
  stageId: string;
  label: string;
  periodId: string | null;
  lessonIndex: number | null;
  start: number | null;
  end: number | null;
  common?: CommonPeriod;
}): ExportSlot {
  const time = params.start == null || params.end == null
    ? '—'
    : `${formatClock(params.start)}-${formatClock(params.end)}`;
  return {
    ...params,
    time,
    header(showTime: boolean) {
      return showTime ? `${params.label}\n${time}` : params.label;
    },
  };
}

function encodeCol(col: number): string {
  let c = col + 1;
  let s = '';
  while (c > 0) {
    s = String.fromCharCode(((c - 1) % 26) + 65) + s;
    c = Math.floor((c - 1) / 26);
  }
  return s;
}

function encodeCellRef(row: number, col: number): string {
  return `${encodeCol(col)}${row + 1}`;
}

function escapeXml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function clampFontSize(size: number | undefined, fallback: number): number {
  if (typeof size !== 'number' || !Number.isFinite(size)) return fallback;
  return Math.min(22, Math.max(8, Math.round(size)));
}

function normalizeOoxmlColor(raw: string | undefined, fallback = 'FF000000'): string {
  if (!raw) return fallback;
  const cleaned = raw.trim().replace(/^#/, '').toUpperCase();
  if (/^[0-9A-F]{6}$/.test(cleaned)) return `FF${cleaned}`;
  if (/^[0-9A-F]{8}$/.test(cleaned)) return cleaned;
  if (/^[0-9A-F]{3}$/.test(cleaned)) {
    const r = cleaned[0];
    const g = cleaned[1];
    const b = cleaned[2];
    return `FF${r}${r}${g}${g}${b}${b}`;
  }
  return fallback;
}

function normalizeStyle(style: CellTextStyle | undefined, fallback: CellTextStyle): CellTextStyle {
  return {
    fontSize: clampFontSize(style?.fontSize, fallback.fontSize),
    bold: typeof style?.bold === 'boolean' ? style.bold : fallback.bold,
    color: style?.color || fallback.color,
  };
}

/** 计算单行文本的半角宽度单位（中文/全角字符计 2，英文数字空格计 1） */
function measureLineUnits(line: string): number {
  let units = 0;
  for (const ch of line) {
    const code = ch.codePointAt(0) ?? 0;
    units += code > 0xff ? 2 : 1;
  }
  return units;
}

/** 计算给定字号与列宽下，一段文本（可能包含 \n）在单元格内实际占用的视觉行数 */
function countVisualLines(text: string, colWidth: number, fontSize: number): number {
  if (!text) return 1;
  const scale = fontSize / 10;
  const lineCapacityUnits = Math.max(4, Math.floor((colWidth - 2.5) / (scale * 1.08)));
  const rawLines = text.split('\n');
  let total = 0;
  for (const line of rawLines) {
    const units = measureLineUnits(line);
    total += Math.max(1, Math.ceil(units / lineCapacityUnits));
  }
  return Math.max(1, total);
}

/** 根据文本最长行和字号估算单行不折行所需的 Excel 列宽 */
function estimateRequiredColWidth(text: string, fontSize: number): number {
  if (!text) return 0;
  const scale = fontSize / 10;
  let maxUnits = 0;
  for (const line of text.split('\n')) {
    const u = measureLineUnits(line);
    if (u > maxUnits) maxUnits = u;
  }
  return maxUnits * scale * 1.12 + 3.5;
}

function buildStylesXml(
  baseFontSize: number,
  subjectStyle: CellTextStyle,
  teacherStyle: CellTextStyle,
  classStyle: CellTextStyle,
): string {
  const fBase = clampFontSize(baseFontSize, 10);
  const fTitle = Math.max(fBase + 4, subjectStyle.fontSize + 2);

  const fontXml = (size: number, bold: boolean, colorHex = 'FF000000') =>
    `<font>${bold ? '<b/>' : ''}<sz val="${size}"/><color rgb="${colorHex}"/><name val="宋体"/><family val="2"/></font>`;

  const borderEdge = (style: string, color?: string) =>
    style === 'none'
      ? ''
      : `<color rgb="${color ?? 'FF000000'}"/>`;

  const sideXml = (side: 'left' | 'right' | 'top' | 'bottom', style: 'none' | 'thin' | 'dotted', color?: string) =>
    style === 'none'
      ? `<${side}/>`
      : `<${side} style="${style}">${borderEdge(style, color)}</${side}>`;

  const borderXml = (
    left: 'none' | 'thin' | 'dotted',
    right: 'none' | 'thin' | 'dotted',
    top: 'none' | 'thin' | 'dotted',
    bottom: 'none' | 'thin' | 'dotted',
    color = 'FF000000',
  ) =>
    `<border>${sideXml('left', left, color)}${sideXml('right', right, color)}${sideXml('top', top, color)}${sideXml('bottom', bottom, color)}<diagonal/></border>`;

  const xfXml = (fontId: number, fillId: number, borderId: number) =>
    `<xf numFmtId="0" fontId="${fontId}" fillId="${fillId}" borderId="${borderId}" xfId="0" applyFont="1" applyFill="${fillId > 0 ? 1 : 0}" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>`;

  const subjectColor = normalizeOoxmlColor(subjectStyle.color);
  const teacherColor = normalizeOoxmlColor(teacherStyle.color);
  const classColor = normalizeOoxmlColor(classStyle.color);

  return [
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    '<fonts count="6">',
    fontXml(fBase, false, 'FF000000'),                             // 0: base normal (slot / common)
    fontXml(fBase, true, 'FF000000'),                              // 1: base bold (header)
    fontXml(subjectStyle.fontSize, subjectStyle.bold, subjectColor), // 2: subjectStyle
    fontXml(fTitle, true, 'FF000000'),                             // 3: title bold
    fontXml(teacherStyle.fontSize, teacherStyle.bold, teacherColor), // 4: teacherStyle
    fontXml(classStyle.fontSize, classStyle.bold, classColor),     // 5: classStyle
    '</fonts>',
    '<fills count="5">',
    '<fill><patternFill patternType="none"/></fill>',
    '<fill><patternFill patternType="gray125"/></fill>',
    '<fill><patternFill patternType="solid"><fgColor rgb="FFDCEBD2"/><bgColor indexed="64"/></patternFill></fill>', // 2: #DCEBD2
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF3F4EF"/><bgColor indexed="64"/></patternFill></fill>', // 3: #F3F4EF
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF3EEDB"/><bgColor indexed="64"/></patternFill></fill>', // 4: #F3EEDB
    '</fills>',
    '<borders count="8">',
    '<border><left/><right/><top/><bottom/><diagonal/></border>', // 0: default none
    borderXml('thin', 'thin', 'thin', 'thin', 'FFD8D8D8'),        // 1: grey thin all
    borderXml('thin', 'thin', 'thin', 'thin', 'FF000000'),        // 2: black thin all
    borderXml('thin', 'thin', 'thin', 'dotted', 'FF000000'),      // 3: classSubject (bottom dotted)
    borderXml('thin', 'thin', 'dotted', 'thin', 'FF000000'),      // 4: classDetail (top dotted)
    borderXml('thin', 'thin', 'thin', 'none', 'FF000000'),        // 5: teacherSubject (bottom none)
    borderXml('thin', 'thin', 'none', 'thin', 'FF000000'),        // 6: teacherDetail (top none)
    borderXml('none', 'none', 'none', 'none'),                    // 7: explicit none
    '</borders>',
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>',
    '<cellXfs count="14">',
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>', // 0: default
    xfXml(1, 2, 1), // 1: headerStyle (#DCEBD2, bold, grey border)
    xfXml(0, 3, 1), // 2: slotStyle (#F3F4EF, normal, grey border)
    xfXml(0, 4, 1), // 3: commonStyle (#F3EEDB, normal, grey border)
    xfXml(2, 0, 1), // 4: bodyStyle (none, subjectStyle base font, grey border)
    xfXml(3, 0, 1), // 5: titleStyle (none, title bold, grey border)
    xfXml(1, 2, 2), // 6: gridHeaderStyle (#DCEBD2, bold, black border)
    xfXml(0, 3, 2), // 7: gridSlotStyle (#F3F4EF, normal, black border)
    xfXml(3, 0, 2), // 8: gridTitleStyle (none, title bold, black border)
    xfXml(0, 4, 2), // 9: gridCommonStyle (#F3EEDB, normal, black border)
    xfXml(2, 0, 3), // 10: classSubjectStyle (subjectStyle font, black L/R/T, dotted B)
    xfXml(4, 0, 4), // 11: classDetailStyle (teacherStyle font, black L/R/B, dotted T)
    xfXml(2, 0, 5), // 12: teacherSubjectStyle (subjectStyle font, black L/R/T, none B)
    xfXml(5, 0, 6), // 13: teacherDetailStyle (classStyle font, black L/R/B, none T)
    '</cellXfs>',
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>',
    '<dxfs count="0"/>',
    '<tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleMedium4"/>',
    '</styleSheet>',
  ].join('');
}

function buildSstEntryXml(cell: SheetCell): string {
  if (cell.richLines && cell.richLines.length > 0) {
    const runs = cell.richLines.map((line, index) => {
      const text = index === 0 ? line.text : `\n${line.text}`;
      const preserve = /^\s|\s$|\n/.test(text) ? ' xml:space="preserve"' : '';
      const color = normalizeOoxmlColor(line.style.color);
      const size = clampFontSize(line.style.fontSize, 10);
      const boldTag = line.style.bold ? '<b/>' : '';
      return `<r><rPr>${boldTag}<sz val="${size}"/><color rgb="${color}"/><rFont val="宋体"/><family val="2"/></rPr><t${preserve}>${escapeXml(text)}</t></r>`;
    });
    return `<si>${runs.join('')}</si>`;
  }
  const str = cell.value;
  const preserve = /^\s|\s$|\n/.test(str) ? ' xml:space="preserve"' : '';
  return `<si><t${preserve}>${escapeXml(str)}</t></si>`;
}

function buildWorksheetXml(
  sheet: SheetModel,
  sstIndex: (cell: SheetCell) => number,
  options: ExportOptions,
): string {
  const parts: string[] = [
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
  ];

  if (options.printFit !== 'original') {
    parts.push('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
  }

  const ref = sheet.rows.size === 0
    ? 'A1'
    : `A1:${encodeCellRef(sheet.maxRow, sheet.maxCol)}`;
  parts.push(`<dimension ref="${ref}"/>`);
  parts.push('<sheetViews><sheetView workbookViewId="0"/></sheetViews>');
  parts.push('<sheetFormatPr defaultRowHeight="16"/>');

  if (sheet.colWidths.size > 0) {
    parts.push('<cols>');
    const sortedCols = [...sheet.colWidths.entries()].sort((a, b) => a[0] - b[0]);
    for (const [col, width] of sortedCols) {
      const colNum = col + 1;
      parts.push(`<col min="${colNum}" max="${colNum}" width="${Number(width.toFixed(4))}" customWidth="1"/>`);
    }
    parts.push('</cols>');
  }

  const allRowIndices = new Set<number>([...sheet.rows.keys(), ...sheet.rowHeights.keys()]);
  const sortedRows = [...allRowIndices].sort((a, b) => a - b);

  if (sortedRows.length === 0) {
    parts.push('<sheetData/>');
  } else {
    parts.push('<sheetData>');
    for (const r of sortedRows) {
      const rowNum = r + 1;
      const height = sheet.rowHeights.get(r);
      const htAttr = height != null ? ` ht="${Number(height.toFixed(2))}" customHeight="1"` : '';
      const rowCells = sheet.rows.get(r);
      if (!rowCells || rowCells.size === 0) {
        parts.push(`<row r="${rowNum}"${htAttr}/>`);
        continue;
      }
      parts.push(`<row r="${rowNum}"${htAttr}>`);
      const sortedCols = [...rowCells.entries()].sort((a, b) => a[0] - b[0]);
      for (const [c, cell] of sortedCols) {
        const cellRef = encodeCellRef(r, c);
        const sIdx = STYLE_INDEX[cell.style];
        const strId = sstIndex(cell);
        parts.push(`<c r="${cellRef}" s="${sIdx}" t="s"><v>${strId}</v></c>`);
      }
      parts.push('</row>');
    }
    parts.push('</sheetData>');
  }

  if (sheet.merges.length > 0) {
    parts.push(`<mergeCells count="${sheet.merges.length}">`);
    for (const m of sheet.merges) {
      parts.push(`<mergeCell ref="${encodeCellRef(m.s.r, m.s.c)}:${encodeCellRef(m.e.r, m.e.c)}"/>`);
    }
    parts.push('</mergeCells>');
  }

  if (options.printFit !== 'original') {
    const height = options.printFit === 'page' ? 1 : 0;
    const orientation = options.landscape ? 'landscape' : 'portrait';
    parts.push('<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.2" footer="0.2"/>');
    parts.push(`<pageSetup paperSize="9" orientation="${orientation}" fitToWidth="1" fitToHeight="${height}"/>`);
  }

  parts.push('</worksheet>');
  return parts.join('');
}

async function encodeWorkbook(
  XLSX: typeof import('xlsx'),
  builder: WorkbookBuilder,
  options: ExportOptions,
): Promise<Uint8Array> {
  const sheets = builder.sheets.length > 0 ? builder.sheets : [new SheetModel('暂无课表')];
  const baseFontSize = clampFontSize(options.fontSize, 10);
  const subjectStyle = normalizeStyle(options.subjectStyle, {
    fontSize: baseFontSize + 2,
    bold: true,
    color: '#000000',
  });
  const teacherStyle = normalizeStyle(options.teacherStyle, {
    fontSize: baseFontSize,
    bold: false,
    color: '#000000',
  });
  const classStyle = normalizeStyle(options.classStyle, {
    fontSize: baseFontSize,
    bold: false,
    color: '#000000',
  });

  const sstEntries: string[] = [];
  const sstMap = new Map<string, number>();
  let sstTotalCount = 0;
  const getSstIndex = (cell: SheetCell): number => {
    sstTotalCount++;
    const entryXml = buildSstEntryXml(cell);
    const existing = sstMap.get(entryXml);
    if (existing !== undefined) return existing;
    const idx = sstEntries.length;
    sstEntries.push(entryXml);
    sstMap.set(entryXml, idx);
    return idx;
  };

  const wb = XLSX.utils.book_new();
  for (const s of sheets) {
    const ws = XLSX.utils.aoa_to_sheet([['']]);
    XLSX.utils.book_append_sheet(wb, ws, s.name);
  }

  const rawBytes = new Uint8Array(
    XLSX.write(wb, { type: 'array', bookType: 'xlsx', compression: true, bookSST: true }),
  );
  const cfb = XLSX.CFB.read(rawBytes, { type: 'array' });
  const encoder = new TextEncoder();

  const worksheetXmls = sheets.map((s) => buildWorksheetXml(s, getSstIndex, options));

  for (let i = 0; i < worksheetXmls.length; i++) {
    const targetPath = `/xl/worksheets/sheet${i + 1}.xml`;
    const entryIndex = cfb.FullPaths.findIndex((p: string) => p.endsWith(targetPath));
    const encoded = encoder.encode(worksheetXmls[i]);
    if (entryIndex >= 0) {
      cfb.FileIndex[entryIndex].content = encoded;
      cfb.FileIndex[entryIndex].size = encoded.length;
    } else {
      XLSX.CFB.utils.cfb_add(cfb, `xl/worksheets/sheet${i + 1}.xml`, encoded);
    }
  }

  const stylesBytes = encoder.encode(
    buildStylesXml(baseFontSize, subjectStyle, teacherStyle, classStyle),
  );
  const stylesIdx = cfb.FullPaths.findIndex((p: string) => p.endsWith('/xl/styles.xml'));
  if (stylesIdx >= 0) {
    cfb.FileIndex[stylesIdx].content = stylesBytes;
    cfb.FileIndex[stylesIdx].size = stylesBytes.length;
  } else {
    XLSX.CFB.utils.cfb_add(cfb, 'xl/styles.xml', stylesBytes);
  }

  const sstXml = [
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
    `<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${sstTotalCount}" uniqueCount="${sstEntries.length}">`,
    ...sstEntries,
    '</sst>',
  ].join('');
  const sstBytes = encoder.encode(sstXml);
  const sstIdx = cfb.FullPaths.findIndex((p: string) => p.endsWith('/xl/sharedStrings.xml'));
  if (sstIdx >= 0) {
    cfb.FileIndex[sstIdx].content = sstBytes;
    cfb.FileIndex[sstIdx].size = sstBytes.length;
  } else {
    XLSX.CFB.utils.cfb_add(cfb, 'xl/sharedStrings.xml', sstBytes);
  }

  return new Uint8Array(XLSX.CFB.write(cfb, { type: 'array', fileType: 'zip', compression: true }));
}

/** 文件名中剔除系统不允许的字符，并保留可辨认的学校和学期名称。 */
export function timetableFilePrefix(schoolName: string, term: AcademicTerm): string {
  const clean = (value: string) =>
    value
      .trim()
      .replace(/[\x00-\x1f\\/:*?"<>|]/g, '_')
      .replace(/[. ]+$/g, '');
  const school = clean(schoolName);
  const title = clean(term.title);
  const semester = title || clean(`${term.academicYear} ${term.semesterLabel}`);
  return `${school || '未命名学校'}_${semester || '未命名学期'}`;
}

export function timetableZipFileName(schoolName: string, term: AcademicTerm): string {
  return `${timetableFilePrefix(schoolName, term)}_课表.zip`;
}

const SCOPE_ORDER: Record<FreeSlot['scopeType'], number> = {
  school: 0,
  stage: 1,
  grade: 2,
  class: 3,
};

export async function buildTimetableWorkbooks(
  data: ScheduleData,
  schoolName: string,
  options: ExportOptions,
): Promise<TimetableWorkbooks> {
  const XLSX = await import('xlsx');
  const baseFontSize = clampFontSize(options.fontSize, 10);
  const subjectStyle = normalizeStyle(options.subjectStyle, {
    fontSize: baseFontSize + 2,
    bold: true,
    color: '#000000',
  });
  const teacherStyle = normalizeStyle(options.teacherStyle, {
    fontSize: baseFontSize,
    bold: false,
    color: '#000000',
  });
  const classStyle = normalizeStyle(options.classStyle, {
    fontSize: baseFontSize,
    bold: false,
    color: '#000000',
  });

  const maxConfiguredFont = Math.max(
    baseFontSize,
    subjectStyle.fontSize - 2,
    teacherStyle.fontSize,
    classStyle.fontSize,
  );
  const sizeScale = maxConfiguredFont > 10 ? maxConfiguredFont / 10 : 1.0;
  const rowHeight = (sheet: SheetModel, row: number, height: number) =>
    sheet.setRowHeight(row, height * sizeScale);

  const classesBook = new WorkbookBuilder();
  const teachersBook = new WorkbookBuilder();
  const schoolBook = new WorkbookBuilder();

  const stageById = new Map(data.stages.map((s) => [s.id, s]));
  const gradeById = new Map(data.grades.map((g) => [g.id, g]));
  const classById = new Map(data.classes.map((c) => [c.id, c]));
  const subjectById = new Map(data.subjects.map((s) => [s.id, s.name]));
  const teacherById = new Map(
    data.teachers.map((t) => [t.id, [t.name, t.displayQualifier].filter(Boolean).join(' · ')]),
  );
  const routineByStage = new Map(data.routines.map((r) => [r.stageId, r]));
  const stageNames = new Map(data.stages.map((s) => [s.id, s.name]));

  const gradeIdForClass = (classId: string) => classById.get(classId)?.gradeId;
  const stageIdForClass = (classId: string) => {
    const gradeId = gradeIdForClass(classId);
    return gradeId ? gradeById.get(gradeId)?.stageId : undefined;
  };

  const placed = data.items.filter(
    (item) =>
      item.weekday !== null &&
      item.stageId !== null &&
      item.periodTypeId !== null &&
      item.lessonIndex !== null,
  );

  const heading = `${schoolName} ${data.term.academicYear}学年${data.term.semesterLabel}`;

  const stageSlots = new Map<string, ExportSlot[]>();
  for (const stage of data.stages) {
    const routine = routineByStage.get(stage.id);
    if (!routine) continue;
    const commons = [...(routine.commonPeriods ?? [])].sort((a, b) => {
      const order = (a.sortOrder ?? 0) - (b.sortOrder ?? 0);
      return order !== 0 ? order : a.name.localeCompare(b.name);
    });
    const lessonIdToKey = new Map<string, string>();
    for (const lt of routine.lessonTimes) {
      lessonIdToKey.set(lt.id, `${lt.periodTypeId}_${lt.lessonIndex}`);
    }
    const anchorKeyOf = (c: CommonPeriod): string | null => {
      if (!c.insertAfterLessonId) return null;
      return lessonIdToKey.get(c.insertAfterLessonId) ?? c.insertAfterLessonId;
    };

    const slots: ExportSlot[] = [];
    const addCommon = (c: CommonPeriod) =>
      slots.push(
        createExportSlot({
          stageId: stage.id,
          label: c.name,
          periodId: null,
          lessonIndex: null,
          start: c.startMinute,
          end: c.endMinute,
          common: c,
        }),
      );

    for (const c of commons.filter((item) => item.insertAfterLessonId === null)) {
      addCommon(c);
    }
    let lessonNumber = 0;
    const used = new Set<string>(
      commons.filter((item) => item.insertAfterLessonId === null).map((item) => item.id),
    );
    const periods = [...routine.periodTypes].sort((a, b) => a.sortOrder - b.sortOrder);
    for (const period of periods) {
      let count = period.defaultLessonCount;
      for (const override of routine.dailyOverrides.filter((o) => o.periodTypeId === period.id)) {
        if (override.lessonCount > count) count = override.lessonCount;
      }
      for (let index = 1; index <= count; index++) {
        lessonNumber++;
        const time = routine.lessonTimes.find(
          (t) => t.periodTypeId === period.id && t.lessonIndex === index,
        );
        slots.push(
          createExportSlot({
            stageId: stage.id,
            label: `第${lessonNumber}节`,
            periodId: period.id,
            lessonIndex: index,
            start: time?.startMinute ?? null,
            end: time?.endMinute ?? null,
          }),
        );
        const targetAnchor = `${period.id}_${index}`;
        for (const c of commons.filter((item) => anchorKeyOf(item) === targetAnchor)) {
          addCommon(c);
          used.add(c.id);
        }
      }
    }
    for (const c of commons.filter((item) => !used.has(item.id))) {
      addCommon(c);
    }
    stageSlots.set(stage.id, slots);
  }

  const teachingWeekdaysSet = (stageId: string): Set<number> => {
    const routine = routineByStage.get(stageId);
    if (!routine) return new Set();
    return new Set(routine.teachingDays.filter((d) => d.isTeachingDay).map((d) => d.weekday));
  };

  const effectiveLessonCount = (stageId: string, periodTypeId: string, weekday: number): number => {
    const routine = routineByStage.get(stageId);
    if (!routine) return 0;
    const override = routine.dailyOverrides.find(
      (o) => o.periodTypeId === periodTypeId && o.weekday === weekday,
    );
    if (override) return override.lessonCount;
    const period = routine.periodTypes.find((p) => p.id === periodTypeId);
    return period?.defaultLessonCount ?? 0;
  };

  const daysFor = (stageId: string): number[] => {
    const days = teachingWeekdaysSet(stageId);
    for (const item of placed) {
      if (stageIdForClass(item.classId) === stageId && item.weekday !== null) {
        days.add(item.weekday);
      }
    }
    return [...days].sort((a, b) => a - b);
  };

  const weekPrefix = (item: ScheduleItem): string => {
    if (!options.showWeek) return '';
    if (item.weekMode === 'odd') return '单周 ';
    if (item.weekMode === 'even') return '双周 ';
    return '';
  };

  const subjectText = (item: ScheduleItem): string =>
    `${weekPrefix(item)}${subjectById.get(item.subjectId) ?? item.subjectId}`;

  const displayClassName = (classId: string): string => {
    const schoolClass = classById.get(classId);
    if (!schoolClass) return classId;
    const grade = gradeById.get(schoolClass.gradeId)?.name ?? '';
    return !grade || schoolClass.name.includes(grade)
      ? schoolClass.name
      : `${grade} ${schoolClass.name}`;
  };

  const className = (item: ScheduleItem): string => displayClassName(item.classId);

  const teacherName = (item: ScheduleItem): string =>
    (item.teacherId ? teacherById.get(item.teacherId) ?? item.teacherId : '');

  const atSlot = (source: ScheduleItem[], slot: ExportSlot, day: number): ScheduleItem[] =>
    source.filter(
      (item) =>
        item.stageId === slot.stageId &&
        item.weekday === day &&
        item.periodTypeId === slot.periodId &&
        item.lessonIndex === slot.lessonIndex,
    );

  const dutiesAtSlot = (slot: ExportSlot, day: number): DutyOccurrence[] =>
    data.visibleSupervision.filter((duty) => {
      const pos = duty.position;
      return (
        pos.stageId === slot.stageId &&
        pos.weekday === day &&
        pos.periodTypeId === slot.periodId &&
        pos.lessonIndex === slot.lessonIndex
      );
    });

  const dutyTeacher = (duty: DutyOccurrence): string =>
    teacherById.get(duty.teacherId) ?? duty.teacherName;

  const dutyClasses = (duty: DutyOccurrence): string =>
    duty.post.classIds.map(displayClassName).join('、');

  const freeLabel = (classId: string, slot: ExportSlot, day: number): string | undefined => {
    const gradeId = gradeIdForClass(classId);
    const matching = data.freeSlots
      .filter((f) => {
        if (
          f.stageId !== slot.stageId ||
          f.periodTypeId !== slot.periodId ||
          f.lessonIndex !== slot.lessonIndex ||
          f.weekday !== day
        ) {
          return false;
        }
        switch (f.scopeType) {
          case 'school':
            return !f.scopeId || f.scopeId === data.term.id;
          case 'stage':
            return f.scopeId === slot.stageId;
          case 'grade':
            return f.scopeId === gradeId;
          case 'class':
            return f.scopeId === classId;
        }
      })
      .sort((a, b) => SCOPE_ORDER[b.scopeType] - SCOPE_ORDER[a.scopeType]);
    return matching[0]?.label;
  };

  const available = (slot: ExportSlot, day: number): boolean => {
    const weekdays = teachingWeekdaysSet(slot.stageId);
    return (
      weekdays.has(day) &&
      slot.periodId !== null &&
      slot.lessonIndex !== null &&
      slot.lessonIndex <= effectiveLessonCount(slot.stageId, slot.periodId, day)
    );
  };

  const writeCommonRow = (sheet: SheetModel, row: number, slot: ExportSlot, days: number[]) => {
    sheet.put(row, 0, options.showTime ? slot.time : '', 'gridSlot');
    const weekdays = teachingWeekdaysSet(slot.stageId);
    let start = 0;
    while (start < days.length) {
      const active = weekdays.has(days[start]);
      let end = start + 1;
      while (end < days.length && weekdays.has(days[end]) === active) {
        end++;
      }
      for (let i = start; i < end; i++) {
        sheet.put(row, i + 1, active ? slot.common!.name : '', 'gridCommon');
      }
      if (active && end - start > 1) {
        sheet.merge(row, start + 1, row, end);
        sheet.put(row, start + 1, slot.common!.name, 'gridCommon');
        sheet.setMergedCellStyle(row, start + 1, 'gridCommon');
      }
      start = end;
    }
  };

  const writeTitle = (sheet: SheetModel, value: string, columns: number, framed = false) => {
    if (columns > 1) sheet.merge(0, 0, 0, columns - 1);
    const selectedStyle: CellStyleKey = framed ? 'gridTitle' : 'title';
    sheet.put(0, 0, value, selectedStyle);
    if (framed && columns > 1) {
      sheet.setMergedCellStyle(0, 0, selectedStyle);
    }
    const titleFontSize = Math.max(baseFontSize + 4, subjectStyle.fontSize + 2);
    sheet.setRowHeight(0, Math.max(28 * sizeScale, titleFontSize * 1.6 + 8));
    sheet.setColumnWidth(0, 15 * sizeScale);
    for (let col = 1; col < columns; col++) {
      sheet.setColumnWidth(col, 18 * sizeScale);
    }
  };

  /** 根据单元格对应的样式返回其字号 */
  const fontSizeForCellStyle = (styleKey: CellStyleKey): number => {
    switch (styleKey) {
      case 'classSubject':
      case 'teacherSubject':
      case 'body':
        return subjectStyle.fontSize;
      case 'classDetail':
        return teacherStyle.fontSize;
      case 'teacherDetail':
        return classStyle.fontSize;
      case 'title':
      case 'gridTitle':
        return Math.max(baseFontSize + 4, subjectStyle.fontSize + 2);
      default:
        return baseFontSize;
    }
  };

  /** 自动根据各列内容扩展列宽，避免单双周教师名/班级名被横向截断折行 */
  const autoExpandColumns = (sheet: SheetModel, totalCols: number) => {
    const horizontalMergedStarts = new Set<string>();
    for (const m of sheet.merges) {
      if (m.e.c > m.s.c) {
        for (let r = m.s.r; r <= m.e.r; r++) {
          for (let c = m.s.c; c <= m.e.c; c++) {
            horizontalMergedStarts.add(`${r}:${c}`);
          }
        }
      }
    }

    for (let c = 0; c < totalCols; c++) {
      let maxW = sheet.colWidths.get(c) ?? (c === 0 ? 15 * sizeScale : 18 * sizeScale);
      for (const [r, rowCells] of sheet.rows.entries()) {
        if (horizontalMergedStarts.has(`${r}:${c}`)) continue;
        const cell = rowCells.get(c);
        if (!cell || !cell.value) continue;
        if (cell.richLines && cell.richLines.length > 0) {
          for (const rl of cell.richLines) {
            const req = estimateRequiredColWidth(rl.text, rl.style.fontSize);
            if (req > maxW) maxW = req;
          }
        } else {
          const fSize = fontSizeForCellStyle(cell.style);
          const req = estimateRequiredColWidth(cell.value, fSize);
          if (req > maxW) maxW = req;
        }
      }
      sheet.setColumnWidth(c, Math.min(44, maxW));
    }
  };

  /** 计算双行课节（班级课表/教师课表）的自适应上下行高，确保单双周多行内容完整显示 */
  const adjustDualSlotRowHeights = (
    sheet: SheetModel,
    topRow: number,
    daysCount: number,
    topFontSize: number,
    bottomFontSize: number,
  ) => {
    let maxTopLines = 1;
    let maxBottomLines = 1;
    const topCells = sheet.rows.get(topRow);
    const bottomCells = sheet.rows.get(topRow + 1);
    for (let c = 1; c <= daysCount; c++) {
      const colW = sheet.colWidths.get(c) ?? 18 * sizeScale;
      const topVal = topCells?.get(c)?.value ?? '';
      const bottomVal = bottomCells?.get(c)?.value ?? '';
      if (topVal) {
        const lines = countVisualLines(topVal, colW, topFontSize);
        if (lines > maxTopLines) maxTopLines = lines;
      }
      if (bottomVal) {
        const lines = countVisualLines(bottomVal, colW, bottomFontSize);
        if (lines > maxBottomLines) maxBottomLines = lines;
      }
    }

    const topLineH = Math.max(15, Math.round(topFontSize * 1.45));
    const bottomLineH = Math.max(13, Math.round(bottomFontSize * 1.45));

    const topHeight =
      maxTopLines <= 1
        ? Math.max(25 * sizeScale, topLineH + 7)
        : Math.max(25 * sizeScale, maxTopLines * topLineH + 8);
    const bottomHeight =
      maxBottomLines <= 1
        ? Math.max(15 * sizeScale, bottomLineH + 4)
        : Math.max(15 * sizeScale, maxBottomLines * bottomLineH + 6);

    sheet.setRowHeight(topRow, topHeight);
    sheet.setRowHeight(topRow + 1, bottomHeight);
  };

  const sortedClasses = [...data.classes].sort((a, b) => {
    const ag = gradeById.get(a.gradeId);
    const bg = gradeById.get(b.gradeId);
    const st =
      (ag ? stageById.get(ag.stageId)?.sortOrder ?? 0 : 0) -
      (bg ? stageById.get(bg.stageId)?.sortOrder ?? 0 : 0);
    if (st !== 0) return st;
    const grade = (ag?.sortOrder ?? 0) - (bg?.sortOrder ?? 0);
    return grade !== 0 ? grade : a.sortOrder - b.sortOrder;
  });

  // 1. 班级课表工作簿（支持 科目 + 教师 样式）
  for (const c of sortedClasses) {
    const stageId = stageIdForClass(c.id);
    if (!stageId) continue;
    const days = daysFor(stageId);
    const slots = stageSlots.get(stageId) ?? [];
    const sheet = classesBook.newSheet(displayClassName(c.id));
    writeTitle(sheet, `${heading} ${displayClassName(c.id)}课表`, days.length + 1, true);
    sheet.put(1, 0, '课节', 'gridHeader');
    for (let d = 0; d < days.length; d++) {
      sheet.put(1, d + 1, `星期${weekdayLabel(days[d])}`, 'gridHeader');
    }
    let row = 2;
    const lessonTopRows: number[] = [];
    const mine = placed.filter((item) => item.classId === c.id);
    for (const slot of slots) {
      if (slot.common) {
        writeCommonRow(sheet, row, slot, days);
        rowHeight(sheet, row, 25);
        row++;
        continue;
      }
      sheet.merge(row, 0, row + 1, 0);
      sheet.put(row, 0, slot.header(options.showTime), 'gridSlot');
      sheet.setMergedCellStyle(row, 0, 'gridSlot');
      lessonTopRows.push(row);
      for (let d = 0; d < days.length; d++) {
        const day = days[d];
        const courses = atSlot(mine, slot, day);
        const duties = dutiesAtSlot(slot, day).filter((duty) => duty.post.classIds.includes(c.id));
        const label = freeLabel(c.id, slot, day);
        sheet.put(
          row,
          d + 1,
          courses.length > 0 || duties.length > 0
            ? [...courses.map(subjectText), ...duties.map((duty) => duty.post.name)].join('\n')
            : label ?? (available(slot, day) ? '' : '—'),
          'classSubject',
        );
        const details = options.showTeacher
          ? [
              ...new Set([
                ...courses.map((item) => `${weekPrefix(item)}${teacherName(item)}`),
                ...duties.map(dutyTeacher),
              ]),
            ].join('\n')
          : '';
        sheet.put(row + 1, d + 1, details, 'classDetail');
      }
      row += 2;
    }
    autoExpandColumns(sheet, days.length + 1);
    for (const topRow of lessonTopRows) {
      adjustDualSlotRowHeights(
        sheet,
        topRow,
        days.length,
        subjectStyle.fontSize,
        teacherStyle.fontSize,
      );
    }
  }

  // 2. 教师课表工作簿（支持 科目 + 班级 样式）
  for (const teacher of data.teachers) {
    const mine = placed.filter((item) => item.teacherId === teacher.id);
    const stageIds = new Set<string>();
    for (const assignment of data.assignments) {
      if (assignment.teacherId === teacher.id) {
        const st = stageIdForClass(assignment.classId);
        if (st) stageIds.add(st);
      }
    }
    for (const item of mine) {
      const st = stageIdForClass(item.classId);
      if (st) stageIds.add(st);
    }
    for (const duty of data.visibleSupervision) {
      if (duty.teacherId === teacher.id) {
        stageIds.add(duty.position.stageId);
      }
    }
    const selectedStages = data.stages.filter((stage) => stageIds.has(stage.id));
    const displayName = teacherById.get(teacher.id) ?? teacher.name;
    const sheet = teachersBook.newSheet(displayName);
    const daysSet = new Set<number>();
    for (const stage of selectedStages) {
      for (const d of daysFor(stage.id)) daysSet.add(d);
    }
    const days = [...daysSet].sort((a, b) => a - b);
    writeTitle(sheet, `${heading} ${displayName}课表`, days.length + 1, true);
    sheet.put(1, 0, '课节', 'gridHeader');
    for (let d = 0; d < days.length; d++) {
      sheet.put(1, d + 1, `星期${weekdayLabel(days[d])}`, 'gridHeader');
    }
    let row = 2;
    const lessonTopRows: number[] = [];
    const groups: ExportSlot[][] = [];
    if (options.teacherUnified) {
      const slots: ExportSlot[] = [];
      for (const stage of selectedStages) {
        slots.push(...(stageSlots.get(stage.id) ?? []));
      }
      const byKey = new Map<string, ExportSlot[]>();
      for (const slot of slots) {
        const key = slot.common
          ? `common:${slot.common.id}`
          : slot.start !== null && slot.end !== null
            ? `clock:${slot.start}:${slot.end}`
            : `stage:${slot.stageId}:${slot.periodId}:${slot.lessonIndex}`;
        const list = byKey.get(key) ?? [];
        list.push(slot);
        byKey.set(key, list);
      }
      groups.push(...byKey.values());
      const orderOf = (slot: ExportSlot): number => {
        if (slot.start !== null) return slot.start;
        const stageRows = stageSlots.get(slot.stageId) ?? [];
        const index = stageRows.indexOf(slot);
        for (let i = index - 1; i >= 0; i--) {
          const previous = stageRows[i];
          if (previous.end !== null) return previous.end + (index - i) / 100;
          if (previous.start !== null) return previous.start + (index - i) / 100;
        }
        for (let i = index + 1; i < stageRows.length; i++) {
          const next = stageRows[i];
          if (next.start !== null) return next.start - (i - index) / 100;
        }
        return 10000 + index;
      };
      groups.sort((a, b) => orderOf(a[0]) - orderOf(b[0]));
    } else {
      for (const stage of selectedStages) {
        groups.push([
          createExportSlot({
            stageId: stage.id,
            label: stage.name,
            periodId: null,
            lessonIndex: null,
            start: null,
            end: null,
          }),
        ]);
        for (const slot of stageSlots.get(stage.id) ?? []) {
          groups.push([slot]);
        }
      }
    }

    for (const group of groups) {
      const slot = group[0];
      if (!options.teacherUnified && slot.periodId === null && !slot.common) {
        if (days.length > 0) sheet.merge(row, 0, row, days.length);
        sheet.put(row, 0, slot.label, 'gridHeader');
        if (days.length > 0) sheet.setMergedCellStyle(row, 0, 'gridHeader');
        row++;
        continue;
      }
      if (slot.common) {
        writeCommonRow(sheet, row, slot, days);
        rowHeight(sheet, row, 25);
        row++;
        continue;
      }
      sheet.merge(row, 0, row + 1, 0);
      sheet.put(row, 0, slot.header(options.showTime), 'gridSlot');
      sheet.setMergedCellStyle(row, 0, 'gridSlot');
      lessonTopRows.push(row);
      for (let d = 0; d < days.length; d++) {
        const found = group.flatMap((entry) => atSlot(mine, entry, days[d]));
        const duties = group.flatMap((entry) =>
          dutiesAtSlot(entry, days[d]).filter((duty) => duty.teacherId === teacher.id),
        );
        sheet.put(
          row,
          d + 1,
          [...found.map(subjectText), ...duties.map((duty) => duty.post.name)].join('\n'),
          'teacherSubject',
        );
        const classDetails = options.showClass
          ? [
              ...new Set([
                ...found.map((item) => {
                  const stId = stageIdForClass(item.classId);
                  const stPrefix =
                    options.showTeacherStage && selectedStages.length > 1
                      ? `${(stId && stageNames.get(stId)) ?? ''} · `
                      : '';
                  return `${weekPrefix(item)}${stPrefix}${className(item)}`;
                }),
                ...duties.map(dutyClasses),
              ]),
            ].join('\n')
          : '';
        sheet.put(row + 1, d + 1, classDetails, 'teacherDetail');
      }
      row += 2;
    }
    autoExpandColumns(sheet, days.length + 1);
    for (const topRow of lessonTopRows) {
      adjustDualSlotRowHeights(
        sheet,
        topRow,
        days.length,
        subjectStyle.fontSize,
        classStyle.fontSize,
      );
    }
  }

  // 3. 学校总课表工作簿（支持同一单元格内 科目 + 教师 富文本样式及单双周自适应行高）
  for (const stage of data.stages) {
    const slots = stageSlots.get(stage.id) ?? [];
    const days = daysFor(stage.id);
    const stageClasses = sortedClasses.filter((c) => stageIdForClass(c.id) === stage.id);
    if (stageClasses.length === 0) continue;
    const dayGroups = options.schoolWeekly ? [days] : days.map((day) => [day]);
    const weekdays = teachingWeekdaysSet(stage.id);
    for (const group of dayGroups) {
      const sheet = schoolBook.newSheet(
        options.schoolWeekly ? stage.name : `${stage.name} 周${weekdayLabel(group[0])}`,
      );
      writeTitle(
        sheet,
        `${heading} ${stage.name}${options.schoolWeekly ? '整周' : `周${weekdayLabel(group[0])}`}总课表`,
        slots.length + 1,
        false,
      );
      let row = 1;
      const classDataRows: number[] = [];
      for (const day of group) {
        if (slots.length > 0) {
          sheet.merge(row, 0, row, slots.length);
        }
        sheet.put(row, 0, `星期${weekdayLabel(day)}`, 'header');
        rowHeight(sheet, row, 25);
        row++;
        sheet.put(row, 0, '班级', 'header');
        for (let col = 0; col < slots.length; col++) {
          sheet.put(row, col + 1, slots[col].header(options.showTime), 'header');
        }
        rowHeight(sheet, row, 34);
        row++;
        for (const c of stageClasses) {
          sheet.put(row, 0, displayClassName(c.id), 'slot');
          classDataRows.push(row);
          const classPlaced = placed.filter((i) => i.classId === c.id);
          for (let col = 0; col < slots.length; col++) {
            const slot = slots[col];
            if (slot.common) {
              sheet.put(row, col + 1, weekdays.has(day) ? slot.common.name : '', 'common');
              continue;
            }
            const found = atSlot(classPlaced, slot, day);
            const label = freeLabel(c.id, slot, day);
            const duties = dutiesAtSlot(slot, day).filter((duty) =>
              duty.post.classIds.includes(c.id),
            );
            if (found.length > 0 || duties.length > 0) {
              const richLines: RichTextLine[] = [];
              for (const item of found) {
                richLines.push({ text: subjectText(item), style: subjectStyle });
                if (options.showTeacher) {
                  const tName = teacherName(item);
                  if (tName) {
                    richLines.push({ text: tName, style: teacherStyle });
                  }
                }
              }
              for (const duty of duties) {
                richLines.push({ text: duty.post.name, style: subjectStyle });
                if (options.showTeacher) {
                  const dTeacher = dutyTeacher(duty);
                  if (dTeacher) {
                    richLines.push({ text: dTeacher, style: teacherStyle });
                  }
                }
                if (options.showClass) {
                  const dClasses = dutyClasses(duty);
                  if (dClasses) {
                    richLines.push({ text: dClasses, style: classStyle });
                  }
                }
              }
              const plainValue = richLines.map((l) => l.text).join('\n');
              const hasMixedRuns = richLines.some(
                (l) =>
                  l.style.fontSize !== subjectStyle.fontSize ||
                  l.style.bold !== subjectStyle.bold ||
                  normalizeOoxmlColor(l.style.color) !== normalizeOoxmlColor(subjectStyle.color),
              );
              sheet.put(
                row,
                col + 1,
                plainValue,
                'body',
                hasMixedRuns ? richLines : undefined,
              );
            } else {
              const fallbackText = label ?? (available(slot, day) ? '' : '—');
              sheet.put(row, col + 1, fallbackText, 'body');
            }
          }
          row++;
        }
      }
      autoExpandColumns(sheet, slots.length + 1);
      for (const dataRow of classDataRows) {
        const rowCells = sheet.rows.get(dataRow);
        let maxRequiredHeight = 42 * sizeScale;
        if (rowCells) {
          for (let col = 1; col <= slots.length; col++) {
            const cell = rowCells.get(col);
            if (!cell || !cell.value) continue;
            const colW = sheet.colWidths.get(col) ?? 18 * sizeScale;
            let cellHeight = 10;
            if (cell.richLines && cell.richLines.length > 0) {
              for (const rl of cell.richLines) {
                const lines = countVisualLines(rl.text, colW, rl.style.fontSize);
                cellHeight += lines * Math.max(13, Math.round(rl.style.fontSize * 1.48));
              }
            } else {
              const fSize = fontSizeForCellStyle(cell.style);
              const lines = countVisualLines(cell.value, colW, fSize);
              cellHeight += lines * Math.max(13, Math.round(fSize * 1.48));
            }
            if (cellHeight > maxRequiredHeight) {
              maxRequiredHeight = cellHeight;
            }
          }
        }
        sheet.setRowHeight(dataRow, maxRequiredHeight);
      }
    }
  }

  const [classWorkbook, teacherWorkbook, schoolWorkbook] = await Promise.all([
    encodeWorkbook(XLSX, classesBook, options),
    encodeWorkbook(XLSX, teachersBook, options),
    encodeWorkbook(XLSX, schoolBook, options),
  ]);

  return { classWorkbook, teacherWorkbook, schoolWorkbook };
}

export async function buildTimetableZip(
  data: ScheduleData,
  schoolName: string,
  options: ExportOptions,
): Promise<Uint8Array> {
  const books = await buildTimetableWorkbooks(data, schoolName, options);
  const prefix = timetableFilePrefix(schoolName, data.term);
  return timetableZip([
    { name: `${prefix}_班级课表.xlsx`, content: books.classWorkbook },
    { name: `${prefix}_教师课表.xlsx`, content: books.teacherWorkbook },
    { name: `${prefix}_学校总课表.xlsx`, content: books.schoolWorkbook },
  ]);
}

export async function exportSchedule(
  data: ScheduleData,
  options: ExportOptions,
  schoolName?: string,
): Promise<boolean> {
  const normalizedSchoolName = (schoolName ?? '').trim() || '未命名学校';
  const fileName = timetableZipFileName(normalizedSchoolName, data.term);

  if (isTauriDesktop()) {
    const [{ save }, { writeFile }] = await Promise.all([
      import('@tauri-apps/plugin-dialog'),
      import('@tauri-apps/plugin-fs'),
    ]);
    const destination = await save({
      defaultPath: fileName,
      filters: [{ name: 'ZIP 压缩包', extensions: ['zip'] }],
    });
    if (!destination) return false;
    const bytes = await buildTimetableZip(data, normalizedSchoolName, options);
    await writeFile(destination, bytes);
    return true;
  }

  const bytes = await buildTimetableZip(data, normalizedSchoolName, options);
  const url = URL.createObjectURL(new Blob([bytes], { type: 'application/zip' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  return true;
}
