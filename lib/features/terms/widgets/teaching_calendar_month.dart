import 'dart:math' as math;

import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:flutter/material.dart';

class TeachingCalendarMonth extends StatefulWidget {
  const TeachingCalendarMonth({
    required this.term,
    required this.exceptions,
    required this.onEditWeek,
    required this.onAddException,
    required this.onEditTerm,
    required this.onEditDate,
    this.fillHeight = false,
    super.key,
  });

  final AcademicTerm term;
  final List<CalendarException> exceptions;
  final ValueChanged<int> onEditWeek;
  final VoidCallback onAddException;
  final VoidCallback onEditTerm;
  final ValueChanged<DateTime> onEditDate;

  /// 桌面双栏布局中填满父级分配的高度。
  final bool fillHeight;

  @override
  State<TeachingCalendarMonth> createState() => _TeachingCalendarMonthState();
}

class _TeachingCalendarMonthState extends State<TeachingCalendarMonth> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _resetVisibleMonth();
  }

  @override
  void didUpdateWidget(covariant TeachingCalendarMonth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.term.id != widget.term.id ||
        oldWidget.term.firstTeachingWeekStart !=
            widget.term.firstTeachingWeekStart ||
        oldWidget.term.teachingWeekCount != widget.term.teachingWeekCount) {
      _resetVisibleMonth();
    }
  }

  void _resetVisibleMonth() {
    final now = DateTime.now();
    final inTerm = widget.term.teachingWeekOf(now) != null;
    final anchor = inTerm ? now : widget.term.firstTeachingWeekStart ?? now;
    _visibleMonth = DateTime(anchor.year, anchor.month);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.term.hasCalendar) return _calendarNotConfigured();

    final first = widget.term.firstTeachingWeekStart!;
    final last = widget.term.teachingWeekEnd(widget.term.teachingWeekCount)!;
    final minMonth = DateTime(first.year, first.month);
    final maxMonth = DateTime(last.year, last.month);
    final visible = _monthDates(_visibleMonth);
    final monthExceptions =
        widget.exceptions
            .where(
              (item) =>
                  item.date.year == _visibleMonth.year &&
                  item.date.month == _visibleMonth.month,
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CalendarHeader(
              month: _visibleMonth,
              canGoBack: _visibleMonth.isAfter(minMonth),
              canGoForward: _visibleMonth.isBefore(maxMonth),
              onPrevious: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _LegendDot(color: AppTheme.blue, label: '单周'),
                _LegendDot(color: AppTheme.purple, label: '双周'),
                _LegendDot(color: AppTheme.success, label: '补课'),
                _LegendDot(color: AppTheme.destructive, label: '停课'),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.fillHeight)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final gridWidth = math
                        .max(620.0, constraints.maxWidth)
                        .toDouble();
                    final idealHeight = _cellHeightForWidth(gridWidth);
                    final maxHeight = math
                        // Reserve the weekday label, all grid gaps, and a small
                        // buffer for platform-specific text metrics.
                        .max(36.0, (constraints.maxHeight - 48) / 6)
                        .toDouble();
                    return _gridViewport(
                      visible,
                      gridWidth,
                      math.min(idealHeight, maxHeight).toDouble(),
                      constraints.maxWidth,
                    );
                  },
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final gridWidth = math
                      .max(620.0, constraints.maxWidth)
                      .toDouble();
                  return _gridViewport(
                    visible,
                    gridWidth,
                    _cellHeightForWidth(gridWidth),
                    constraints.maxWidth,
                  );
                },
              ),
            const SizedBox(height: 12),
            _MonthlyExceptions(
              exceptions: monthExceptions,
              term: widget.term,
              onAddException: widget.onAddException,
              onPressed: (exception) {
                final week = widget.term.teachingWeekOf(exception.date);
                if (week != null) widget.onEditWeek(week);
              },
            ),
            const SizedBox(height: 7),
            const Text(
              '选择教学日可编辑该周例外；教学周锚点固定，不会因停课或补课而顺延。',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 10,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendarNotConfigured() => AppSurface(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CalendarHeader(
            month: _visibleMonth,
            canGoBack: false,
            canGoForward: false,
            onPrevious: () {},
            onNext: () {},
          ),
          const SizedBox(height: 22),
          AppEmptyState(
            title: '先设置教学周起始日',
            message: '学期有了第 1 教学周的起始日期，才能生成教学日历和单双周。',
            icon: Icons.calendar_month_outlined,
            action: AppPrimaryButton(
              onPressed: widget.onEditTerm,
              child: const Text('设置教学周起始日'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _gridViewport(
    List<DateTime> visible,
    double gridWidth,
    double rowHeight,
    double viewportWidth,
  ) {
    final grid = SizedBox(
      width: gridWidth,
      child: Column(
        children: [
          const _WeekdayLabels(),
          const SizedBox(height: 5),
          for (var row = 0; row < 6; row++) ...[
            SizedBox(
              height: rowHeight,
              child: _CalendarWeekRow(
                dates: visible.skip(row * 7).take(7).toList(),
                term: widget.term,
                month: _visibleMonth,
                exceptions: widget.exceptions,
                onEditDate: widget.onEditDate,
              ),
            ),
            if (row < 5) const SizedBox(height: 5),
          ],
        ],
      ),
    );
    if (gridWidth <= viewportWidth) return grid;
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid);
  }

  double _cellHeightForWidth(double gridWidth) {
    const gutter = 59.0;
    final dayWidth = (gridWidth - gutter - 30) / 7;
    return (dayWidth / 1.58).clamp(54.0, 108.0).toDouble();
  }

  void _shiftMonth(int offset) => setState(() {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
  });

  List<DateTime> _monthDates(DateTime month) {
    final firstOfMonth = DateTime(month.year, month.month);
    final mondayOffset = firstOfMonth.weekday - DateTime.monday;
    final firstVisible = firstOfMonth.subtract(Duration(days: mondayOffset));
    return List.generate(
      42,
      (index) => firstVisible.add(Duration(days: index)),
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.month,
    required this.canGoBack,
    required this.canGoForward,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text(
        '教学日历',
        style: TextStyle(
          color: AppTheme.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          '${month.year}年${month.month}月',
          style: const TextStyle(
            color: AppTheme.inkSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      AppIconButton(
        icon: Icons.chevron_left_rounded,
        tooltip: '上个月',
        iconSize: 18,
        onPressed: canGoBack ? onPrevious : null,
      ),
      AppIconButton(
        icon: Icons.chevron_right_rounded,
        tooltip: '下个月',
        iconSize: 18,
        onPressed: canGoForward ? onNext : null,
      ),
    ],
  );
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels();

  static const _gutterWidth = 52.0;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(width: _gutterWidth),
      const SizedBox(width: 7),
      Expanded(
        child: Row(
          children: [
            for (var index = 0; index < weekdayShortNames.length; index++) ...[
              Expanded(
                child: Center(
                  child: Text(
                    '周${weekdayShortNames[index]}',
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (index < weekdayShortNames.length - 1)
                const SizedBox(width: 5),
            ],
          ],
        ),
      ),
    ],
  );
}

class _CalendarWeekRow extends StatelessWidget {
  const _CalendarWeekRow({
    required this.dates,
    required this.term,
    required this.month,
    required this.exceptions,
    required this.onEditDate,
  });

  final List<DateTime> dates;
  final AcademicTerm term;
  final DateTime month;
  final List<CalendarException> exceptions;
  final ValueChanged<DateTime> onEditDate;

  @override
  Widget build(BuildContext context) {
    int? week;
    for (final date in dates) {
      week = term.teachingWeekOf(date);
      if (week != null) break;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 52,
          child: _TeachingWeekLabel(term: term, week: week),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < dates.length; index++) ...[
                Expanded(
                  child: _DayCell(
                    date: dates[index],
                    month: month,
                    term: term,
                    exception: _exceptionFor(dates[index]),
                    onPressed: onEditDate,
                  ),
                ),
                if (index < dates.length - 1) const SizedBox(width: 5),
              ],
            ],
          ),
        ),
      ],
    );
  }

  CalendarException? _exceptionFor(DateTime date) {
    for (final item in exceptions) {
      if (dateOnly(item.date) == dateOnly(date)) return item;
    }
    return null;
  }
}

class _TeachingWeekLabel extends StatelessWidget {
  const _TeachingWeekLabel({required this.term, required this.week});

  final AcademicTerm term;
  final int? week;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppTheme.canvas,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          week == null ? '—' : 'W${week.toString().padLeft(2, '0')}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 9),
        ),
        const SizedBox(height: 3),
        if (week != null)
          Text(
            switch (term.cycleMode) {
              AcademicTermCycle.everyWeek => '每周',
              AcademicTermCycle.alternating =>
                term.isOddWeek(week!) ? '单' : '双',
            },
            style: TextStyle(
              color: switch (term.cycleMode) {
                AcademicTermCycle.everyWeek => AppTheme.blue,
                AcademicTermCycle.alternating =>
                  term.isOddWeek(week!) ? AppTheme.blue : AppTheme.purple,
              },
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    ),
  );
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.month,
    required this.term,
    required this.exception,
    required this.onPressed,
  });

  final DateTime date;
  final DateTime month;
  final AcademicTerm term;
  final CalendarException? exception;
  final ValueChanged<DateTime> onPressed;

  @override
  Widget build(BuildContext context) {
    final inMonth = date.month == month.month;
    final week = term.teachingWeekOf(date);
    final inTerm = week != null;
    final isMakeup = exception?.isMakeup ?? false;
    final exceptionColor = isMakeup ? AppTheme.success : AppTheme.destructive;
    final exceptionSurface = isMakeup
        ? AppTheme.successSurface
        : AppTheme.destructiveSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: inMonth && inTerm ? () => onPressed(date) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 7, 6, 5),
          decoration: BoxDecoration(
            color: exception == null
                ? inMonth
                      ? (inTerm ? Colors.white : AppTheme.canvas)
                      : AppTheme.canvas.withValues(alpha: .48)
                : exceptionSurface,
            border: Border.all(
              color: exception == null ? AppTheme.border : exceptionColor,
              width: exception == null ? 1 : 1.2,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  color: !inMonth
                      ? AppTheme.muted
                      : inTerm
                      ? AppTheme.ink
                      : AppTheme.muted,
                  fontSize: 12,
                  fontWeight: inTerm ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (exception != null) ...[
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    exception!.note.trim().isEmpty
                        ? (isMakeup ? '补课' : '停课')
                        : exception!.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: exceptionColor,
                      fontSize: 9,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyExceptions extends StatelessWidget {
  const _MonthlyExceptions({
    required this.exceptions,
    required this.term,
    required this.onAddException,
    required this.onPressed,
  });

  final List<CalendarException> exceptions;
  final AcademicTerm term;
  final VoidCallback onAddException;
  final ValueChanged<CalendarException> onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: AppTheme.canvas,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '本月例外',
                style: TextStyle(
                  color: AppTheme.inkSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            AppGhostButton.icon(
              size: .xs,
              onPressed: onAddException,
              icon: const Icon(Icons.add, size: 13),
              label: const Text('添加例外'),
            ),
          ],
        ),
        if (exceptions.isEmpty)
          const Text(
            '暂无例外安排',
            style: TextStyle(color: AppTheme.muted, fontSize: 10),
          )
        else ...[
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in exceptions)
                _ExceptionChip(
                  exception: item,
                  week: term.teachingWeekOf(item.date),
                  onPressed: () => onPressed(item),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _ExceptionChip extends StatelessWidget {
  const _ExceptionChip({
    required this.exception,
    required this.week,
    required this.onPressed,
  });

  final CalendarException exception;
  final int? week;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isMakeup = exception.isMakeup;
    final color = isMakeup ? AppTheme.blue : AppTheme.destructive;
    final text =
        '${formatDateMd(exception.date)} '
        '${exception.note.trim().isNotEmpty ? exception.note : (isMakeup ? '补课' : '停课')}'
        '${week == null ? '' : ' · 第$week周'}';
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isMakeup ? AppTheme.selectedBlue : AppTheme.destructiveSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(color: AppTheme.inkSecondary, fontSize: 9),
      ),
    ],
  );
}
