part of '../teachers_page.dart';

typedef TeacherPresetMatrixCell = ({
  int weekday,
  String periodTypeId,
  int lessonIndex,
});

class TeacherPresetMatrixHeader extends StatelessWidget {
  const TeacherPresetMatrixHeader({
    required this.description,
    this.selector,
    super.key,
  });

  final Widget description;
  final Widget? selector;

  @override
  Widget build(BuildContext context) {
    final selector = this.selector;
    if (selector == null) return description;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              description,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: constraints.maxWidth < 180
                      ? constraints.maxWidth
                      : 180,
                  child: selector,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: description),
            const SizedBox(width: 8),
            SizedBox(width: 180, child: selector),
          ],
        );
      },
    );
  }
}

class TeacherPresetMatrix extends StatelessWidget {
  const TeacherPresetMatrix({
    required this.routine,
    required this.values,
    required this.onChanged,
    this.exemptions = const {},
    super.key,
  });

  final StageRoutine routine;
  final Map<TeacherPresetMatrixCell, PresetValue> values;
  final void Function(TeacherPresetMatrixCell cell, PresetValue? value)
  onChanged;

  /// 免任课标记解析结果：整体生效的格子锁定展示，部分生效的
  /// 格子以警示色标记但仍可设置预排。
  final Map<TeacherPresetMatrixCell, FreeSlotViewResolution> exemptions;

  @override
  Widget build(BuildContext context) {
    final weekdays = routine.teachingWeekdays.toList()..sort();
    final rows = _presetMatrixRows(routine, weekdays);
    if (weekdays.isEmpty || rows.isEmpty) {
      return Center(
        child: Text(
          '当前范围作息暂无可用课节',
          style: TextStyle(color: context.appColors.muted, fontSize: 12),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 88.0;
        final dayWidth = ((constraints.maxWidth - labelWidth) / weekdays.length)
            .clamp(72.0, double.infinity);
        final tableWidth = labelWidth + dayWidth * weekdays.length;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                Row(
                  children: [
                    _tableCell(
                      context,
                      '节次',
                      labelWidth,
                      height: 32,
                      background: context.appColors.tableHeader,
                      foreground: context.appColors.muted,
                    ),
                    for (final weekday in weekdays)
                      _tableCell(
                        context,
                        _weekdayLabel(weekday),
                        dayWidth,
                        height: 32,
                        background: context.appColors.tableHeader,
                        foreground: context.appColors.muted,
                      ),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) =>
                        _lessonRow(context, rows[index], weekdays, dayWidth),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lessonRow(
    BuildContext context,
    _TeacherPresetMatrixRow row,
    List<int> weekdays,
    double dayWidth,
  ) {
    final visual = periodVisualFor(
      context,
      row.period.name,
      row.period.sortOrder,
    );
    return Row(
      children: [
        _tableCell(
          context,
          row.label,
          88,
          background: visual.labelTint,
          foreground: visual.color,
        ),
        for (final weekday in weekdays)
          _lessonCell(context, row, weekday, dayWidth, visual),
      ],
    );
  }

  Widget _lessonCell(
    BuildContext context,
    _TeacherPresetMatrixRow row,
    int weekday,
    double dayWidth,
    PeriodVisual visual,
  ) {
    final cell = (
      weekday: weekday,
      periodTypeId: row.period.id,
      lessonIndex: row.lessonIndex,
    );
    final exemption = exemptions[cell];
    final fullExemption = exemption?.full;
    final partialExemption = exemption?.partial;
    final hasLesson =
        row.lessonIndex <= routine.effectiveLessonCount(row.period.id, weekday);
    Widget child;
    if (fullExemption != null) {
      // 免任课整体生效：无论当天是否有课节都锁定展示，
      // 覆盖「当天无课节」的空白格（如周日 / 周五晚）。
      child = Tooltip(
        message: '免任课：${fullExemption.label}',
        child: Container(
          width: dayWidth,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.appColors.destructiveSurface,
            border: Border(
              right: BorderSide(color: context.appColors.tableDivider),
              bottom: BorderSide(color: context.appColors.tableDivider),
            ),
          ),
          child: Text(
            fullExemption.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.appColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    } else if (!hasLesson) {
      child = _blankCell(
        context,
        dayWidth,
        visual,
        partialLabel: partialExemption?.label,
      );
    } else {
      final current = values[cell];
      final showPartialMark =
          partialExemption != null &&
          (current == null || current == PresetValue.auto);
      child = _PresetHoverCell(
        child: TeacherPresetValueMenu(
          key: ValueKey(
            'preset-cell-$weekday-${row.period.id}-${row.lessonIndex}',
          ),
          contextLabel: '${row.label} · ${_weekdayLabel(weekday)}',
          current: current,
          onChanged: (value) => onChanged(cell, value),
          child: showPartialMark
              ? _partialExemptContent(context, partialExemption.label, visual)
              : _presetCellContent(context, current, visual),
        ),
      );
      if (partialExemption != null) {
        child = Tooltip(
          message: '部分班级免任课：${partialExemption.label}',
          child: child,
        );
      }
    }
    return SizedBox(width: dayWidth, height: 44, child: child);
  }

  /// 当天该时段没有课节的空白格；带 [partialLabel] 时展示部分免任课标记。
  Widget _blankCell(
    BuildContext context,
    double dayWidth,
    PeriodVisual visual, {
    String? partialLabel,
  }) {
    final cell = Container(
      width: dayWidth,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: visual.cellTint,
        border: Border(
          right: BorderSide(color: context.appColors.tableDivider),
          bottom: BorderSide(color: context.appColors.tableDivider),
        ),
      ),
      child: partialLabel == null
          ? null
          : Text(
              partialLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appColors.warning,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
    );
    return partialLabel == null
        ? cell
        : Tooltip(message: '部分班级免任课：$partialLabel', child: cell);
  }

  /// 部分班级免任课内容：警示色文字叠加时段底色，格子仍可编辑。
  Widget _partialExemptContent(
    BuildContext context,
    String label,
    PeriodVisual visual,
  ) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: visual.cellTint,
      border: Border(
        right: BorderSide(color: context.appColors.tableDivider),
        bottom: BorderSide(color: context.appColors.tableDivider),
      ),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.appColors.warning,
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  Widget _tableCell(
    BuildContext context,
    String label,
    double width, {
    double height = 44,
    required Color background,
    Color? foreground,
  }) => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      border: Border(
        right: BorderSide(color: context.appColors.tableDivider),
        bottom: BorderSide(color: context.appColors.tableDivider),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: foreground ?? context.appColors.ink,
        fontSize: height == 32 ? 12 : 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _presetCellContent(
    BuildContext context,
    PresetValue? value,
    PeriodVisual visual,
  ) {
    final (background, foreground) = switch (value) {
      PresetValue.prefer => (
        context.appColors.selectedBlue,
        context.appColors.blue,
      ),
      PresetValue.must => (
        context.appColors.blue,
        Theme.of(context).colorScheme.onPrimary,
      ),
      PresetValue.forbid => (
        context.appColors.destructiveSurface,
        context.appColors.destructive,
      ),
      PresetValue.auto || null => (visual.cellTint, context.appColors.muted),
    };
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        border: Border(
          right: BorderSide(color: context.appColors.tableDivider),
          bottom: BorderSide(color: context.appColors.tableDivider),
        ),
      ),
      child: value == null || value == PresetValue.auto
          ? null
          : Text(
              value.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: value == PresetValue.must
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
    );
  }
}

class _PresetHoverCell extends StatefulWidget {
  const _PresetHoverCell({required this.child});
  final Widget child;

  @override
  State<_PresetHoverCell> createState() => _PresetHoverCellState();
}

class _PresetHoverCellState extends State<_PresetHoverCell> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedContainer(
            key: const ValueKey('teacher-preset-hover-overlay'),
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: hovered
                  ? context.appColors.blue.withValues(alpha: .10)
                  : Colors.transparent,
              border: hovered
                  ? Border.all(
                      color: context.appColors.blue.withValues(alpha: .65),
                    )
                  : null,
            ),
          ),
        ),
      ],
    ),
  );
}

class TeacherPresetValueMenu extends StatelessWidget {
  const TeacherPresetValueMenu({
    required this.contextLabel,
    required this.current,
    required this.onChanged,
    required this.child,
    super.key,
  });

  final String contextLabel;
  final PresetValue? current;
  final ValueChanged<PresetValue?> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    menuBuilder: (context, controller, menu) => [
      FItemGroup(
        divider: .none,
        children: [
          FItem.raw(
            variant: .primary,
            onPress: null,
            style: .delta(
              rawContentStyle: .delta(padding: .value(EdgeInsets.zero)),
            ),
            child: Container(
              width: 148,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.appColors.tableDivider),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.inkSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '当前：${current?.label ?? PresetValue.auto.label}',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      FItemGroup(
        divider: .none,
        children: [
          for (final value in PresetValue.values)
            _menuTile(
              label: value.label,
              key: 'teacher-preset-menu-${value.storageValue}',
              selected:
                  current == value ||
                  (current == null && value == PresetValue.auto),
              onPressed: () {
                unawaited(controller.hide());
                onChanged(value);
              },
            ),
          _menuTile(
            label: '清除',
            key: 'teacher-preset-menu-clear',
            selected: false,
            onPressed: () {
              unawaited(controller.hide());
              onChanged(null);
            },
          ),
        ],
      ),
    ],
    builder: (context, controller, child) => FTappable(
      semanticsLabel: '设置$contextLabel，当前${current?.label ?? '自动'}',
      onPress: () => unawaited(controller.toggle()),
      child: child,
    ),
    child: child,
  );

  AppMenuTile _menuTile({
    required String label,
    required String key,
    required bool selected,
    required VoidCallback onPressed,
  }) => AppMenuTile(
    key: ValueKey(key),
    item: AppMenuItem(label: label, selected: selected, onPressed: onPressed),
  );
}

class _TeacherPresetMatrixRow {
  const _TeacherPresetMatrixRow({
    required this.label,
    required this.period,
    required this.lessonIndex,
  });

  final String label;
  final LessonPeriodType period;
  final int lessonIndex;
}

List<_TeacherPresetMatrixRow> _presetMatrixRows(
  StageRoutine routine,
  List<int> weekdays,
) {
  final rows = <_TeacherPresetMatrixRow>[];
  final periods = [...routine.periodTypes]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  var daytimeLesson = 0;
  for (final period in periods) {
    final lessonCount = weekdays
        .map((weekday) => routine.effectiveLessonCount(period.id, weekday))
        .fold<int>(0, (maximum, count) => count > maximum ? count : maximum);
    for (var lessonIndex = 1; lessonIndex <= lessonCount; lessonIndex++) {
      final label = period.name.contains('早')
          ? lessonCount == 1
                ? '早读'
                : '早读 $lessonIndex'
          : period.name.contains('晚')
          ? '晚自习 $lessonIndex'
          : '第 ${++daytimeLesson} 节';
      rows.add(
        _TeacherPresetMatrixRow(
          label: label,
          period: period,
          lessonIndex: lessonIndex,
        ),
      );
    }
  }
  return rows;
}

String _weekdayLabel(int weekday) => switch (weekday) {
  1 => '周一',
  2 => '周二',
  3 => '周三',
  4 => '周四',
  5 => '周五',
  6 => '周六',
  7 => '周日',
  _ => '星期$weekday',
};
