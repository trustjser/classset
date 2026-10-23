import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class TeachingCalendarTable extends StatefulWidget {
  const TeachingCalendarTable({
    required this.term,
    required this.exceptions,
    required this.onEditWeek,
    super.key,
  });

  final AcademicTerm term;
  final List<CalendarException> exceptions;
  final ValueChanged<int> onEditWeek;

  @override
  State<TeachingCalendarTable> createState() => _TeachingCalendarTableState();
}

class _TeachingCalendarTableState extends State<TeachingCalendarTable> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final visibleWeeks = _isExpanded || widget.term.teachingWeekCount <= 6
        ? widget.term.teachingWeekCount
        : 6;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < 860 ? 860 : constraints.maxWidth,
          child: AppSurface(
            child: Column(
              children: [
                AppDataTableHeader(
                  height: 36,
                  padding: EdgeInsets.zero,
                  textColor: context.appColors.inkSecondary,
                  children: [
                    const SizedBox(
                      width: 90,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('教学周'),
                      ),
                    ),
                    const SizedBox(
                      width: 100,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('单 / 双周'),
                      ),
                    ),
                    const SizedBox(
                      width: 200,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('日期范围'),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            const Flexible(child: Text('例外安排（停课 / 补课 / 节假日）')),
                            const SizedBox(width: 4),
                            const AppHelpTooltip(
                              message: '第 1 教学周为单周，之后单双周交替。停课日不排课、不计容量；补课日按被补日期的课表执行。未配置日历时仅可查看周模板。',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 120,
                      child: Center(child: Text('操作')),
                    ),
                  ],
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleWeeks,
                  separatorBuilder: (context, index) => SizedBox(
                    height: 1,
                    child: ColoredBox(color: context.appColors.tableDivider),
                  ),
                  itemBuilder: (context, index) {
                    final weekNumber = index + 1;
                    final summary = exceptionSummaryForWeek(
                      widget.term,
                      weekNumber,
                      widget.exceptions,
                    );
                    final hasMakeupException = widget.exceptions.any(
                      (exception) =>
                          exception.isMakeup &&
                          widget.term.teachingWeekOf(exception.date) ==
                              weekNumber,
                    );
                    return _TeachingWeekRow(
                      weekNumber: weekNumber,
                      term: widget.term,
                      summary: summary,
                      hasMakeupException: hasMakeupException,
                      onEdit: () => widget.onEditWeek(weekNumber),
                    );
                  },
                ),
                if (widget.term.teachingWeekCount > 6)
                  ColoredBox(
                    color: context.appColors.tableHeader,
                    child: FTappable(
                      semanticsLabel: _isExpanded ? '收起教学周' : '展开教学周',
                      semanticsExpanded: _isExpanded,
                      onPress: () => setState(() => _isExpanded = !_isExpanded),
                      child: SizedBox(
                        height: 34,
                        width: double.infinity,
                        child: Center(
                          child: Text(
                            _isExpanded
                                ? '收起教学周'
                                : '第 7 – ${widget.term.teachingWeekCount} 周 未展开（'
                                      '${widget.term.cycleMode == AcademicTermCycle.everyWeek ? '每周相同' : '单双周自动交替'}）',
                            style: TextStyle(
                              color: context.appColors.blue,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeachingWeekRow extends StatelessWidget {
  const _TeachingWeekRow({
    required this.weekNumber,
    required this.term,
    required this.summary,
    required this.hasMakeupException,
    required this.onEdit,
  });

  final int weekNumber;
  final AcademicTerm term;
  final String? summary;
  final bool hasMakeupException;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final start = term.teachingWeekStart(weekNumber);
    final end = term.teachingWeekEnd(weekNumber);
    final hasException = summary != null;
    final backgroundColor = !hasException
        ? context.appColors.surface
        : hasMakeupException
        ? context.appColors.warningSurface
        : context.appColors.destructiveSurface;
    final cycleLabel = term.cycleMode == AcademicTermCycle.everyWeek
        ? '每周相同'
        : term.weekCycleLabel(weekNumber);
    final exceptionCell = Text(
      summary ?? '—',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: summary == null
            ? context.appColors.muted
            : context.appColors.ink,
        fontSize: 12,
        height: 17 / 12,
      ),
    );
    return ColoredBox(
      color: backgroundColor,
      child: SizedBox(
        height: 34,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '第 $weekNumber 周',
                    style: TextStyle(
                      color: context.appColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 19 / 13,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    cycleLabel,
                    style: TextStyle(
                      color: term.cycleMode == AcademicTermCycle.everyWeek
                          ? context.appColors.inkSecondary
                          : (term.isOddWeek(weekNumber)
                                ? context.appColors.warning
                                : context.appColors.success),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 17 / 12,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    start == null
                        ? '设置第 1 教学周日期后生成'
                        : '${formatDateMd(start)} – ${formatDateMd(end!)}',
                    style: TextStyle(
                      color: start == null
                          ? context.appColors.muted
                          : context.appColors.ink,
                      fontSize: 12,
                      height: 17 / 12,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: summary == null
                      ? exceptionCell
                      : Tooltip(message: summary!, child: exceptionCell),
                ),
              ),
              SizedBox(
                width: 120,
                child: Center(
                  child: Tooltip(
                    message: term.hasCalendar
                        ? '编辑本周例外安排'
                        : '配置第 1 教学周日期后可编辑例外安排',
                    child: SizedBox(
                      width: 64,
                      height: 24,
                      child: AppGhostButton(
                        size: .xs,
                        onPressed: term.hasCalendar ? onEdit : null,
                        child: Text(
                          '编辑',
                          style: TextStyle(
                            color: term.hasCalendar
                                ? context.appColors.blue
                                : context.appColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
