import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:flutter_test/flutter_test.dart';

AcademicTerm _term({DateTime? firstWeek, int weekCount = 20}) => AcademicTerm(
  id: 't1',
  title: '2026 学年 · 秋季学期',
  academicYear: '2026-2027',
  semesterLabel: '秋季学期',
  firstTeachingWeekStart: firstWeek,
  teachingWeekCount: weekCount,
  createdAt: DateTime(2026, 8, 1),
);

CalendarException _exception(
  DateTime date, {
  CalendarExceptionKind kind = CalendarExceptionKind.holiday,
  int? makeupWeekday,
  DateTime? makeupForDate,
  String note = '',
}) => CalendarException(
  id: 'e${date.microsecondsSinceEpoch}',
  termId: 't1',
  date: date,
  kind: kind,
  makeupWeekday: makeupWeekday,
  makeupForDate: makeupForDate,
  note: note,
);

void main() {
  group('教学周历', () {
    final term = _term(firstWeek: DateTime(2026, 9, 1));

    test('第 1 教学周为单周，此后交替', () {
      expect(term.isOddWeek(1), isTrue);
      expect(term.isOddWeek(2), isFalse);
      expect(term.isOddWeek(5), isTrue);
    });

    test('教学周起止日期按 7 天推进', () {
      expect(term.teachingWeekStart(1), DateTime(2026, 9, 1));
      expect(term.teachingWeekEnd(1), DateTime(2026, 9, 7));
      expect(term.teachingWeekStart(4), DateTime(2026, 9, 22));
      expect(term.teachingWeekEnd(4), DateTime(2026, 9, 28));
      expect(term.teachingWeekStart(20), DateTime(2027, 1, 12));
      expect(term.teachingWeekEnd(20), DateTime(2027, 1, 18));
      expect(term.teachingWeekStart(0), isNull);
      expect(term.teachingWeekEnd(21), isNull);
    });

    test('日期可反查所在教学周', () {
      expect(term.teachingWeekOf(DateTime(2026, 9, 1)), 1);
      expect(term.teachingWeekOf(DateTime(2026, 9, 7)), 1);
      expect(term.teachingWeekOf(DateTime(2026, 9, 8)), 2);
      expect(term.teachingWeekOf(DateTime(2026, 8, 31)), isNull);
      expect(term.teachingWeekOf(DateTime(2026, 9, 8, 23, 59)), 2);
      expect(term.teachingWeekOf(DateTime(2027, 1, 19)), isNull);
      // 第 20 周之后不属于教学周。
      expect(term.teachingWeekOf(DateTime(2027, 1, 20)), isNull);
    });

    test('未配置第 1 教学周时不输出日期', () {
      final bare = _term();
      expect(bare.hasCalendar, isFalse);
      expect(bare.teachingWeekStart(1), isNull);
      expect(bare.teachingWeekEnd(1), isNull);
    });

    test('单双周交替和每周相同模式生成正确标签', () {
      expect(term.weekCycleLabel(1), '单周');
      expect(term.weekCycleLabel(2), '双周');
      final everyWeek = term.copyWith(cycleMode: AcademicTermCycle.everyWeek);
      expect(everyWeek.weekCycleLabel(1), '每周');
      expect(everyWeek.weekCycleLabel(2), '每周');
    });
  });

  group('例外安排摘要', () {
    final term = _term(firstWeek: DateTime(2026, 9, 1));

    test('无例外返回 null', () {
      expect(exceptionSummaryForWeek(term, 1, const []), isNull);
    });

    test('连续停课合并为区间并附带备注', () {
      final summary = exceptionSummaryForWeek(term, 5, [
        _exception(DateTime(2026, 10, 1), note: '国庆假期 · 停课'),
        _exception(DateTime(2026, 10, 2)),
        _exception(DateTime(2026, 10, 3)),
        _exception(DateTime(2026, 10, 4)),
        _exception(DateTime(2026, 10, 5)),
      ]);
      expect(summary, '10/01 – 10/05 国庆假期 · 停课');
    });

    test('补课显示映射关系', () {
      final summary = exceptionSummaryForWeek(term, 4, [
        _exception(
          DateTime(2026, 9, 26),
          kind: CalendarExceptionKind.makeup,
          makeupWeekday: 3,
          makeupForDate: DateTime(2026, 9, 30),
        ),
      ]);
      expect(summary, '09/26（六）补 09/30（星期三·单周课表）');
    });

    test('补课未填原课日期时只显示采用星期', () {
      final summary = exceptionSummaryForWeek(term, 4, [
        _exception(
          DateTime(2026, 9, 26),
          kind: CalendarExceptionKind.makeup,
          makeupWeekday: 3,
        ),
      ]);
      expect(summary, '09/26（六）补 星期三课表');
    });

    test('每周相同模式的补课显示每周课表', () {
      final everyWeek = term.copyWith(cycleMode: AcademicTermCycle.everyWeek);
      final summary = exceptionSummaryForWeek(everyWeek, 4, [
        _exception(
          DateTime(2026, 9, 26),
          kind: CalendarExceptionKind.makeup,
          makeupWeekday: 3,
          makeupForDate: DateTime(2026, 9, 30),
        ),
      ]);
      expect(summary, '09/26（六）补 09/30（星期三·每周课表）');
    });

    test('例外区间只合并本周连续且备注相同的停课日', () {
      final ranges = calendarExceptionRangesForWeek(term, 5, [
        _exception(DateTime(2026, 10, 1), note: '国庆'),
        _exception(DateTime(2026, 10, 2), note: '国庆'),
        _exception(DateTime(2026, 10, 3), note: '调休'),
        _exception(DateTime(2026, 10, 5), note: '国庆'),
        _exception(DateTime(2026, 10, 6), note: '下周'),
      ]);
      expect(ranges, hasLength(2));
      expect(ranges[0].startDate, DateTime(2026, 10, 1));
      expect(ranges[0].endDate, DateTime(2026, 10, 3));
      expect(ranges[0].exceptions, hasLength(3));
      expect(ranges[1].startDate, DateTime(2026, 10, 5));
    });

    test('停课与补课可同时存在于一周', () {
      final summary = exceptionSummaryForWeek(term, 6, [
        _exception(DateTime(2026, 10, 6), note: '假期停课'),
        _exception(DateTime(2026, 10, 7), note: '假期停课'),
        _exception(DateTime(2026, 10, 8), note: '10/09 起恢复'),
        _exception(
          DateTime(2026, 10, 10),
          kind: CalendarExceptionKind.makeup,
          makeupWeekday: 3,
          makeupForDate: DateTime(2026, 10, 7),
        ),
      ]);
      expect(summary, '10/06 – 10/08 假期停课；10/10（六）补 10/07（星期三·双周课表）');
    });
  });

  group('日期格式', () {
    test('常用格式', () {
      expect(formatDateYmd(DateTime(2026, 9, 1)), '2026-09-01');
      expect(formatDateMd(DateTime(2026, 9, 1)), '09/01');
      expect(formatDateYmdWithWeekday(DateTime(2026, 9, 1)), '2026-09-01（周二）');
      expect(weekdayFullName(3), '星期三');
      expect(weekdayShortName(7), '日');
    });
  });
}
