import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';

const weekdayFullNames = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
const weekdayShortNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 2026-09-01
String formatDateYmd(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// 09/01
String formatDateMd(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

/// 2026-09-01（周二）
String formatDateYmdWithWeekday(DateTime date) =>
    '${formatDateYmd(date)}（周${weekdayShortNames[date.weekday - 1]}）';

/// 1=星期一 … 7=星期日 → 星期一
String weekdayFullName(int weekday) => weekdayFullNames[weekday - 1];

/// 1=星期一 … 7=星期日 → 一
String weekdayShortName(int weekday) => weekdayShortNames[weekday - 1];

/// 归一化到日期（去掉时分秒）。
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// 生成某一教学周的「例外安排」摘要文本；无例外返回 null。
///
/// 连续停课合并为区间（如「10/01 – 10/05 国庆假期 · 停课」）；
/// 补课显示映射关系（如「09/26（六）补 09/30（周三·单周课表）」）。
String? exceptionSummaryForWeek(
  AcademicTerm term,
  int weekNumber,
  List<CalendarException> exceptions,
) {
  final weekStart = term.teachingWeekStart(weekNumber);
  final weekEnd = term.teachingWeekEnd(weekNumber);
  if (weekStart == null || weekEnd == null || exceptions.isEmpty) return null;

  final inWeek =
      exceptions
          .where(
            (item) =>
                !dateOnly(item.date).isBefore(weekStart) &&
                !dateOnly(item.date).isAfter(weekEnd),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  if (inWeek.isEmpty) return null;

  final holidays = inWeek.where((item) => !item.isMakeup).toList();
  final makeups = inWeek.where((item) => item.isMakeup).toList();

  // 合并连续停课为区间。
  final segments = <String>[];
  var index = 0;
  while (index < holidays.length) {
    var end = index;
    while (end + 1 < holidays.length &&
        dateOnly(holidays[end + 1].date)
                .difference(dateOnly(holidays[end].date))
                .inDays ==
            1) {
      end++;
    }
    final first = holidays[index];
    final last = holidays[end];
    final range = dateOnly(first.date) == dateOnly(last.date)
        ? formatDateMd(first.date)
        : '${formatDateMd(first.date)} – ${formatDateMd(last.date)}';
    final note = first.note.trim();
    segments.add(note.isEmpty ? '$range · 停课' : '$range $note');
    index = end + 1;
  }

  for (final item in makeups) {
    final date = dateOnly(item.date);
    final weekday = item.makeupWeekday;
    final forDate = item.makeupForDate;
    if (weekday == null) {
      segments.add(
        '${formatDateMd(date)}（${weekdayShortNames[date.weekday - 1]}）补课',
      );
      continue;
    }
    if (forDate == null) {
      segments.add(
        '${formatDateMd(date)}（${weekdayShortNames[date.weekday - 1]}）'
        '补 ${weekdayFullName(weekday)}课表',
      );
      continue;
    }
    final targetWeek = term.teachingWeekOf(forDate);
    final cycleLabel = targetWeek == null
        ? '单双周'
        : term.weekCycleLabel(targetWeek);
    segments.add(
      '${formatDateMd(date)}（${weekdayShortNames[date.weekday - 1]}）'
      '补 ${formatDateMd(forDate)}（${weekdayFullName(forDate.weekday)}·$cycleLabel课表）',
    );
  }

  return segments.join('；');
}

/// 将某教学周内按日保存的例外整理成界面可编辑的区间。
///
/// 连续停课日只有在备注一致时才合并，补课始终单独显示。
List<CalendarExceptionRange> calendarExceptionRangesForWeek(
  AcademicTerm term,
  int weekNumber,
  List<CalendarException> exceptions,
) {
  final weekStart = term.teachingWeekStart(weekNumber);
  final weekEnd = term.teachingWeekEnd(weekNumber);
  if (weekStart == null || weekEnd == null) return const [];

  final inWeek = exceptions.where((item) {
    final date = dateOnly(item.date);
    return !date.isBefore(weekStart) && !date.isAfter(weekEnd);
  }).toList()..sort((a, b) => a.date.compareTo(b.date));
  final ranges = <CalendarExceptionRange>[];
  final holidays = inWeek.where((item) => !item.isMakeup).toList();
  var index = 0;
  while (index < holidays.length) {
    var end = index;
    while (end + 1 < holidays.length &&
        dateOnly(holidays[end + 1].date)
                .difference(dateOnly(holidays[end].date))
                .inDays ==
            1) {
      end++;
    }
    final group = holidays.sublist(index, end + 1);
    ranges.add(
      CalendarExceptionRange(
        kind: CalendarExceptionKind.holiday,
        startDate: dateOnly(group.first.date),
        endDate: dateOnly(group.last.date),
        note: group.first.note,
        exceptions: group,
      ),
    );
    index = end + 1;
  }
  for (final exception in inWeek.where((item) => item.isMakeup)) {
    final date = dateOnly(exception.date);
    ranges.add(
      CalendarExceptionRange(
        kind: CalendarExceptionKind.makeup,
        startDate: date,
        endDate: date,
        note: exception.note,
        exceptions: [exception],
      ),
    );
  }
  ranges.sort((a, b) => a.startDate.compareTo(b.startDate));
  return List.unmodifiable(ranges);
}

class CalendarExceptionRange {
  const CalendarExceptionRange({
    required this.kind,
    required this.startDate,
    required this.endDate,
    required this.note,
    required this.exceptions,
  });

  final CalendarExceptionKind kind;
  final DateTime startDate;
  final DateTime endDate;
  final String note;
  final List<CalendarException> exceptions;

  bool get isMakeup => kind == CalendarExceptionKind.makeup;
}
