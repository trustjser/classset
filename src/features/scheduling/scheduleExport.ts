import { isTauriDesktop } from '@/adapter/db/databaseAdapter';
import { createScheduleContext, groupBy, occursInWeek, positionOf, roomFor, slotKey, type ScheduleData } from '@/domain/scheduling';
import type { WeekMode } from '@/domain/models';
import { clockLabel, weekdayName } from './TimetableGrid';
import { timetableZip } from './timetableZip';

export interface ExportOptions {
  classes: boolean;
  teachers: boolean;
  school: boolean;
  rooms: boolean;
  showTeacher: boolean;
  showClass: boolean;
  showTime: boolean;
  showWeek: boolean;
  fontSize: number;
  printFit: 'original' | 'width' | 'page';
  landscape: boolean;
}

export async function exportSchedule(data: ScheduleData, options: ExportOptions) {
  const XLSX = await import('xlsx');
  const entries: Array<{ name: string; content: Uint8Array }> = [];
  const context = createScheduleContext(data);
  const weeks: WeekMode[] = data.term.cycleMode === 'alternating' ? ['odd', 'even'] : ['weekly'];
  const clean = (name: string) => name.replace(/[\\/:*?"<>|]/g, ' ').trim() || '课表';
  const addWorkbook = (path: string, tabs: Array<{ name: string; records: string[][] }>) => {
    if (!tabs.length) return;
    const workbook = XLSX.utils.book_new();
    for (const { name, records } of tabs) {
      const sheet = XLSX.utils.aoa_to_sheet(records);
      sheet['!cols'] = [{ wch: 25 }, ...Array.from({ length: Math.max(1, records[0].length - 1) }, () => ({ wch: 23 }))];
      XLSX.utils.book_append_sheet(workbook, sheet, name);
    }
    let bytes = new Uint8Array(XLSX.write(workbook, { type: 'array', bookType: 'xlsx', compression: true }));
    const document = XLSX.CFB.read(bytes, { type: 'array' });
    const decoder = new TextDecoder();
    const encoder = new TextEncoder();
    document.FullPaths.forEach((entry: string, index: number) => {
      const file = document.FileIndex[index];
      const replaceXml = (transform: (xml: string) => string) => {
        file.content = encoder.encode(transform(decoder.decode(file.content)));
        file.size = file.content.length;
      };
      if (entry.endsWith('/xl/styles.xml')) replaceXml((xml) => xml.replace(/<sz val="[^"]+"\/>/, `<sz val="${options.fontSize}"/>`)
        .replace(/(<cellXfs[^>]*>)(<xf[^>]*?)\/>/, '$1$2 applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'));
      if (options.printFit === 'original' || !/\/xl\/worksheets\/sheet\d+\.xml$/.test(entry)) return;
      replaceXml((source) => {
        const xml = source.replace('<sheetPr/>', '');
        const properties = '<pageSetUpPr fitToPage="1"/>';
        const setup = `<pageSetup paperSize="9" orientation="${options.landscape ? 'landscape' : 'portrait'}" fitToWidth="1" fitToHeight="${options.printFit === 'page' ? '1' : '0'}"/>`;
        const withProperties = xml.includes('</sheetPr>') ? xml.replace('</sheetPr>', `${properties}</sheetPr>`)
          : xml.replace(/(<worksheet[^>]*>)/, `$1<sheetPr>${properties}</sheetPr>`);
        return withProperties.includes('<ignoredErrors')
          ? withProperties.replace('<ignoredErrors', `${setup}<ignoredErrors`)
          : withProperties.replace('</worksheet>', `${setup}</worksheet>`);
      });
    });
    bytes = new Uint8Array(XLSX.CFB.write(document, { type: 'array', fileType: 'zip', compression: true }));
    entries.push({ name: path, content: bytes });
  };
  function tab(week: WeekMode, selected: typeof data.items, classIds: string[], teacherId?: string) {
    const stages = new Set([...classIds.map(context.stageForClass), ...selected.map((row) => row.stageId)]);
    const duties = data.visibleSupervision.filter((row) => teacherId ? row.teacherId === teacherId : row.post.classIds.some((id) => classIds.includes(id)));
    for (const duty of duties) stages.add(duty.position.stageId);
    const stageRows = data.stages.filter((row) => stages.has(row.id));
    const days = [...new Set(stageRows.flatMap((row) => (context.slotsByStage.get(row.id) ?? []).map((slot) => slot.weekday)))].sort((a, b) => a - b);
    const records = [['学段 / 节次', ...days.map(weekdayName)]];
    const bySlot = groupBy(selected.filter((row) => occursInWeek(row.weekMode, week) && positionOf(context, row)), (row) => slotKey(positionOf(context, row)!));
    for (const stage of stageRows) {
      const slots = context.slotsByStage.get(stage.id) ?? [];
      const routine = data.routines.find((row) => row.stageId === stage.id);
      const anchors = new Map(routine?.lessonTimes.map((row) => [row.id, `${row.periodTypeId}:${row.lessonIndex}`]));
      const byPeriod = groupBy(slots, (slot) => slot.periodTypeId);
      const common = [...(routine?.commonPeriods ?? [])].sort((a, b) => a.sortOrder - b.sortOrder);
      const inserted = new Set<string>();
      const addCommon = (row: typeof common[number]) => {
        inserted.add(row.id);
        records.push([[stage.name, row.name, options.showTime && clockLabel(row.startMinute, row.endMinute)].filter(Boolean).join(' · '),
          ...days.map((day) => slots.some((slot) => slot.weekday === day) ? row.name : '—')]);
      };
      for (const period of [...(routine?.periodTypes ?? [])].sort((a, b) => a.sortOrder - b.sortOrder)) {
        const timeRows = groupBy(byPeriod.get(period.id) ?? [], (slot) => slot.lessonIndex);
        for (const [index, rows] of timeRows) {
          const sample = rows[0];
          const title = [stage.name, sample.periodName + sample.label, options.showTime && clockLabel(sample.startMinute, sample.endMinute)].filter(Boolean).join(' · ');
          const content = days.map((day) => {
            const slot = rows.find((row) => row.weekday === day);
            if (!slot) return '—';
            const atSlot = (bySlot.get(slotKey(slot)) ?? []).map((row) => [
              context.subjects.get(row.subjectId), options.showTeacher && context.teachers.get(row.teacherId ?? ''),
              options.showClass && context.classes.get(row.classId)?.name,
              options.showWeek && row.weekMode !== 'weekly' && (row.weekMode === 'odd' ? '单周' : '双周'),
            ].filter(Boolean).join(' · '));
            for (const duty of duties.filter((row) => slotKey(row.position) === slotKey(slot))) atSlot.push([
              duty.post.name, options.showTeacher && duty.teacherName, options.showClass && duty.classNames.join('、'),
            ].filter(Boolean).join(' · '));
            return atSlot.join('\n');
          });
          records.push([title, ...content]);
          common.filter((row) => anchors.get(row.insertAfterLessonId ?? '') === `${period.id}:${index}`).forEach(addCommon);
        }
      }
      common.filter((row) => !inserted.has(row.id)).forEach(addCommon);
    }
    return { name: week === 'odd' ? '单周' : week === 'even' ? '双周' : '每周', records };
  }
  const placed = data.items.filter((row) => row.weekday !== null);
  if (options.classes) for (const row of data.classes) addWorkbook(`班级课表/${clean(row.name)}-${clean(row.id)}.xlsx`,
    weeks.map((week) => tab(week, placed.filter((item) => item.classId === row.id), [row.id])));
  if (options.teachers) for (const row of data.teachers.filter((teacher) => placed.some((item) => item.teacherId === teacher.id) ||
    data.visibleSupervision.some((item) => item.teacherId === teacher.id))) addWorkbook(`教师课表/${clean(row.name)}-${clean(row.id)}.xlsx`,
    weeks.map((week) => tab(week, placed.filter((item) => item.teacherId === row.id), [], row.id)));
  if (options.rooms) for (const row of data.rooms) addWorkbook(`场室课表/${clean(row.name)}-${clean(row.id)}.xlsx`,
    weeks.map((week) => tab(week, placed.filter((item) => roomFor(context, item) === row.id), [])));
  if (options.school) addWorkbook('学校总课表.xlsx', weeks.map((week) => tab(week, placed, data.classes.map((row) => row.id))));
  const bytes = timetableZip(entries);
  const fileName = `${clean(data.term.title)}-课表.zip`;
  if (isTauriDesktop()) {
    const [{ save }, { writeFile }] = await Promise.all([import('@tauri-apps/plugin-dialog'), import('@tauri-apps/plugin-fs')]);
    const destination = await save({ defaultPath: fileName, filters: [{ name: 'ZIP 压缩包', extensions: ['zip'] }] });
    if (!destination) return false;
    await writeFile(destination, bytes);
  } else {
    const url = URL.createObjectURL(new Blob([bytes], { type: 'application/zip' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  return true;
}
