import { isTauriDesktop } from '@/adapter/db/databaseAdapter';
import type {
  ActualLesson,
  ActualSupervision,
  TemporaryAdjustmentRecord,
  TemporaryTimetableState,
} from '@/domain/actualTimetable';
import type { SchedulePosition } from '@/domain/supervision';
import { timetableFilePrefix } from '@/features/scheduling/scheduleExport';
import {
  adjustmentKindLabel,
  adjustmentRecordStatus,
  adjustmentStatusLabels,
  formatMinuteClock,
  formatTimestampTime,
  getClassDisplayName,
  getPeriodLessonLabel,
  getSubjectDisplayName,
  getTeacherNameById,
  isInAdjustmentDateRange,
  recordClassIds,
  recordDates,
  recordTeacherIds,
  type AdjustmentDateRange,
} from './temporaryAdjustmentsHelpers';

type Row = (string | number)[];
type Column = [label: string, width: number];

interface ExportOptions extends AdjustmentDateRange {
  schoolName: string;
  filterLabel: string;
}

interface RecordSheet {
  name: string;
  note: string;
  columns: Column[];
  rows: Row[];
}

const SHEET_HEADER_ROW = 4;
const spreadsheetNamespace = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

function recordStylesXml(): string {
  const fonts = [
    [11, 'FF202A3D', false],
    [18, 'FFFFFFFF', true],
    [10, 'FF4A6472', false],
    [11, 'FF164C57', true],
  ].map(([size, color, bold]) =>
    `<font>${bold ? '<b/>' : ''}<sz val="${size}"/><color rgb="${color}"/><name val="等线"/></font>`,
  );
  const fills = ['FF135C68', 'FFE7F3F5', 'FFD2E8EB', 'FFF4F8FA'].map((color) =>
    `<fill><patternFill patternType="solid"><fgColor rgb="${color}"/><bgColor indexed="64"/></patternFill></fill>`,
  );
  const styles = [[0, 0], [1, 2], [2, 3], [3, 4], [0, 5], [0, 0], [0, 5]].map(([fontId, fillId], i) =>
    `<xf numFmtId="0" fontId="${fontId}" fillId="${fillId}" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="${i >= 5 ? 'center' : 'left'}" vertical="center" wrapText="1"/></xf>`,
  );
  return [
    `<styleSheet xmlns="${spreadsheetNamespace}">`,
    `<fonts count="${fonts.length}">${fonts.join('')}</fonts>`,
    `<fills count="${fills.length + 2}"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>${fills.join('')}</fills>`,
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>',
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>',
    `<cellXfs count="${styles.length}">${styles.join('')}</cellXfs>`,
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>',
    '</styleSheet>',
  ].join('');
}

function wrappedLineCount(value: string | number, width: number): number {
  return String(value).split(/\r?\n/).reduce((total, line) => {
    const units = [...line].reduce((length, char) => length + (char.charCodeAt(0) > 255 ? 2 : 1), 0);
    return total + Math.max(1, Math.ceil(units / (width - 2)));
  }, 0);
}

async function encodeRecordSheets(sheets: RecordSheet[], context: string, filterLabel: string): Promise<Uint8Array> {
  const xlsx = await import('xlsx');
  const book = xlsx.utils.book_new();
  for (const { name, note, columns, rows } of sheets) {
    const widths = columns.map(([, width]) => width);
    const bannerWidth = widths.slice(0, Math.min(columns.length, 5)).reduce((sum, width) => sum + width, 0);
    const banners = [name, context, `${filterLabel}\n${note}`];
    const sheet = xlsx.utils.aoa_to_sheet([
      ...banners.map((value) => [value, ...columns.slice(1).map(() => '')]),
      columns.map(([label]) => label),
      ...rows,
    ]);
    sheet['!cols'] = widths.map((wch) => ({ wch }));
    sheet['!rows'] = [
      { hpt: 34 },
      { hpt: Math.min(409, Math.max(22, 15 * wrappedLineCount(context, bannerWidth) + 6)) },
      { hpt: Math.min(409, Math.max(32, 15 * wrappedLineCount(banners[2], bannerWidth) + 8)) },
      { hpt: 26 },
      ...rows.map((row) => ({
        hpt: Math.min(409, Math.max(22, 15 * Math.max(...row.map((cell, i) => wrappedLineCount(cell, widths[i]))) + 6)),
      })),
    ];
    sheet['!merges'] = banners.flatMap((_, r) => {
      const lastColumn = columns.length - 1;
      const bannerEnd = Math.min(lastColumn, 4);
      const main = { s: { r, c: 0 }, e: { r, c: bannerEnd } };
      return lastColumn > bannerEnd + 1
        ? [main, { s: { r, c: bannerEnd + 1 }, e: { r, c: lastColumn } }]
        : [main];
    });
    sheet['!autofilter'] = {
      ref: xlsx.utils.encode_range({
        s: { r: SHEET_HEADER_ROW - 1, c: 0 },
        e: { r: SHEET_HEADER_ROW + rows.length - 1, c: columns.length - 1 },
      }),
    };
    xlsx.utils.book_append_sheet(book, sheet, name);
  }

  // SheetJS writes the data and workbook structure. Add presentation styles and
  // frozen headers to the worksheet XML, as the timetable export does for styles.
  const raw = new Uint8Array(xlsx.write(book, { type: 'array', bookType: 'xlsx', cellStyles: true }));
  const archive = xlsx.CFB.read(raw, { type: 'array' });
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const editPart = (path: string, transform: (xml: string) => string) => {
    const entry = xlsx.CFB.find(archive, path);
    if (!entry) throw new Error('Excel 工作簿组件缺失');
    entry.content = encoder.encode(transform(decoder.decode(entry.content as Uint8Array)));
    entry.size = entry.content.length;
  };
  editPart('/xl/styles.xml', recordStylesXml);
  sheets.forEach(({ rows, columns }, i) => {
    const freezeIdColumn = columns[0][0] === '记录编号';
    const firstDataCell = `${freezeIdColumn ? 'B' : 'A'}${SHEET_HEADER_ROW + 1}`;
    const activePane = freezeIdColumn ? 'bottomRight' : 'bottomLeft';
    const views = [
      '<sheetViews><sheetView showGridLines="0" workbookViewId="0">',
      `<pane${freezeIdColumn ? ' xSplit="1"' : ''} ySplit="${SHEET_HEADER_ROW}" topLeftCell="${firstDataCell}" activePane="${activePane}" state="frozen"/>`,
      `<selection pane="${activePane}" activeCell="${firstDataCell}" sqref="${firstDataCell}"/></sheetView></sheetViews>`,
    ].join('');
    editPart(`/xl/worksheets/sheet${i + 1}.xml`, (xml) => xml
      .replace(/<sheetViews>.*?<\/sheetViews>/s, views)
      .replace(/<c r="([A-Z]+)(\d+)"/g, (cell, column: string, rowNumber: string) => {
        const row = Number(rowNumber);
        const striped = row % 2 === 0;
        let style = striped ? 4 : 0;
        if (row === 1) style = 1;
        else if (row < SHEET_HEADER_ROW) style = 2;
        else if (row === SHEET_HEADER_ROW) style = 3;
        else if (typeof rows[row - SHEET_HEADER_ROW - 1]?.[xlsx.utils.decode_col(column)] === 'number') {
          style = striped ? 6 : 5;
        }
        return `${cell} s="${style}"`;
      }));
  });
  return new Uint8Array(xlsx.CFB.write(archive, { type: 'array', fileType: 'zip', compression: true }));
}

export async function buildTemporaryAdjustmentWorkbook(
  state: TemporaryTimetableState,
  records: TemporaryAdjustmentRecord[],
  options: ExportOptions,
): Promise<Uint8Array> {
  const { classes, grades, teachers, subjects, term } = state.snapshot;
  const className = (id: string) => classes.some((item) => item.id === id)
    ? getClassDisplayName(id, classes, grades) : id;
  const teacherName = (id: string) => teachers.some((item) => item.id === id)
    ? getTeacherNameById(id, teachers) : id;
  const subjectName = (id: string) => subjects.some((item) => item.id === id)
    ? getSubjectDisplayName(id, subjects) : id;
  const timeRange = (start?: number | null, end?: number | null) =>
    start != null && end != null ? `${formatMinuteClock(start)}–${formatMinuteClock(end)}` : '';
  const slot = (position: SchedulePosition | null) => getPeriodLessonLabel(state, position);
  const lessonColumns = ({ date, item }: ActualLesson): Row => [
    date, className(item.classId), slot(item.position),
    timeRange(item.position?.startMinute, item.position?.endMinute),
    subjectName(item.subjectId), teacherName(item.teacherId), item.teacherId, '',
  ];
  const supervisionColumns = (duty: ActualSupervision): Row => [
    duty.date, duty.classIds.map((id, i) => duty.classNames[i] || className(id)).join('、'),
    duty.occurrences.map(({ position }) => slot(position)).join('、'),
    duty.occurrences.map(({ startMinute, endMinute, position }) =>
      timeRange(startMinute ?? position.startMinute, endMinute ?? position.endMinute)).filter(Boolean).join('、'),
    duty.post.name, duty.teacherName || teacherName(duty.teacherId), duty.teacherId, duty.post.location,
  ];

  const currentLessons = new Map(state.lessons.map((lesson) => [lesson.key, lesson]));
  const recordsRows: Row[] = [];
  const detailRows: Row[] = [];
  for (const record of records) {
    const kind = adjustmentKindLabel(record.kind);
    const recordStatus = adjustmentRecordStatus(record);
    const status = adjustmentStatusLabels[recordStatus];
    const { supervisionChange } = record;
    recordsRows.push([
      record.id, formatTimestampTime(record.createdAt), kind, status,
      recordDates(record).join('、'),
      recordClassIds(record).map(className).join('、'),
      recordTeacherIds(record).map(teacherName).join('、'),
      supervisionChange ? 1 : record.changes.length,
      record.reason, record.cancelledAt == null ? '' : formatTimestampTime(record.cancelledAt),
    ]);
    function appendDetail(
      sequence: number,
      before: Row,
      after: Row,
      date: string,
      period: string,
      transfer?: {
        from: { id: string; name: string };
        to: { id: string; name: string };
        lessons: number;
      },
    ) {
      const prefix = [record.id, sequence, kind, status];
      const context = [...before, ...after, record.reason];
      if (!transfer) {
        detailRows.push([...prefix, '', '', '', '', 0, ...context]);
        return;
      }
      const { from, to, lessons } = transfer;
      detailRows.push(
        [...prefix, date, period, from.name, from.id, -lessons, ...context],
        [...prefix, date, period, to.name, to.id, lessons, ...context],
      );
    }

    if (supervisionChange) {
      const { before, after } = supervisionChange;
      const period = after.occurrences.map(({ position }) => slot(position)).join('、');
      const eligible = recordStatus === 'active' && before.teacherId !== after.teacherId &&
        after.occurrences.length > 0 && isInAdjustmentDateRange(after.date, options);
      appendDetail(1, supervisionColumns(before), supervisionColumns(after), after.date, period, eligible ? {
        from: { id: before.teacherId, name: before.teacherName || teacherName(before.teacherId) },
        to: { id: after.teacherId, name: after.teacherName || teacherName(after.teacherId) },
        lessons: after.occurrences.length,
      } : undefined);
    }

    const countedMeetings = new Set<string>();
    record.changes.forEach(({ before, after }, i) => {
      const current = currentLessons.get(after.key) ?? after;
      const from = before.item.teacherId;
      const to = after.item.teacherId;
      const meetingId = after.item.meetingId;
      // Deduplicate the class rows within one transfer. Later transfers of the
      // same lesson must retain both sides so the intermediate teacher nets to zero.
      const meetingKey = meetingId == null ? null : JSON.stringify([meetingId, current.date, from, to]);
      const eligible = record.kind === 'substitute' && recordStatus === 'active' &&
        current.item.position != null && from !== to &&
        isInAdjustmentDateRange(current.date, options) &&
        (meetingKey == null || !countedMeetings.has(meetingKey));
      if (eligible && meetingKey != null) countedMeetings.add(meetingKey);

      appendDetail(
        i + 1, lessonColumns(before), lessonColumns(after), current.date, slot(current.item.position),
        eligible ? {
          from: { id: from, name: teacherName(from) },
          to: { id: to, name: teacherName(to) },
          lessons: 1,
        } : undefined,
      );
    });
  }
  const changeColumns = (side: string): Column[] => [
    [`${side}日期`, 15], [`${side}班级`, 24], [`${side}节次`, 24], [`${side}时间`, 19],
    [`${side}科目或活动`, 24], [`${side}教师`, 24], [`${side}教师编号`, 23], [`${side}地点`, 19],
  ];
  const termName = term.title || `${term.academicYear} ${term.semesterLabel}`;
  return encodeRecordSheets([
    {
      name: '调整记录',
      note: `共 ${records.length} 条。每条记录的全部变更可按记录编号在「调整明细」中查阅。`,
      columns: [
        ['记录编号', 27], ['调整时间', 21], ['类型', 16], ['状态', 15], ['涉及日期', 30],
        ['涉及班级', 26], ['涉及教师', 26], ['变更项数', 15], ['原因', 36], ['取消时间', 21],
      ],
      rows: recordsRows,
    },
    {
      name: '调整明细',
      note: '同一明细序号下，接替教师记正数，原教师记负数。按课时变动教师编号对课时求和，即可得到净变动。合班同一课次计 1 节，连续带班按实际节次计，核算日期遵循筛选范围。',
      columns: [
        ['记录编号', 27], ['明细序号', 15], ['类型', 16], ['状态', 15],
        ['核算日期', 15], ['核算节次', 22],
        ['课时变动教师', 24], ['课时变动教师编号', 24], ['课时变动（节）', 18],
        ...changeColumns('调整前'), ...changeColumns('调整后'), ['原因', 36],
      ],
      rows: detailRows,
    },
  ], `${options.schoolName.trim() || '未命名学校'} · ${termName}`, options.filterLabel);
}

export async function exportTemporaryAdjustments(
  state: TemporaryTimetableState,
  records: TemporaryAdjustmentRecord[],
  options: ExportOptions,
): Promise<void> {
  const prefix = timetableFilePrefix(options.schoolName, state.snapshot.term);
  const fileName = `${prefix}_调整记录.xlsx`;
  if (isTauriDesktop()) {
    const [{ save }, { writeFile }] = await Promise.all([
      import('@tauri-apps/plugin-dialog'),
      import('@tauri-apps/plugin-fs'),
    ]);
    const destination = await save({
      defaultPath: fileName,
      filters: [{ name: 'Excel 工作簿', extensions: ['xlsx'] }],
    });
    if (!destination) return;
    await writeFile(destination, await buildTemporaryAdjustmentWorkbook(state, records, options));
    return;
  }

  const bytes = await buildTemporaryAdjustmentWorkbook(state, records, options);
  const url = URL.createObjectURL(new Blob([bytes], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  }));
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
