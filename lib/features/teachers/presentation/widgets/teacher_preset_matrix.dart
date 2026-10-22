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
    super.key,
  });

  final StageRoutine routine;
  final Map<TeacherPresetMatrixCell, PresetValue> values;
  final void Function(TeacherPresetMatrixCell cell, PresetValue? value)
  onChanged;

  @override
  Widget build(BuildContext context) {
    final weekdays = routine.teachingWeekdays.toList()..sort();
    final rows = _presetMatrixRows(routine, weekdays);
    if (weekdays.isEmpty || rows.isEmpty) {
      return const Center(
        child: Text(
          '当前范围作息暂无可用课节',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
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
                      '节次',
                      labelWidth,
                      height: 32,
                      background: AppTheme.tableHeader,
                      foreground: AppTheme.muted,
                    ),
                    for (final weekday in weekdays)
                      _tableCell(
                        _weekdayLabel(weekday),
                        dayWidth,
                        height: 32,
                        background: AppTheme.tableHeader,
                        foreground: AppTheme.muted,
                      ),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) =>
                        _lessonRow(rows[index], weekdays, dayWidth),
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
    _TeacherPresetMatrixRow row,
    List<int> weekdays,
    double dayWidth,
  ) {
    final visual = periodVisualFor(row.period.name, row.period.sortOrder);
    return Row(
      children: [
        _tableCell(
          row.label,
          88,
          background: visual.labelTint,
          foreground: visual.color,
        ),
        for (final weekday in weekdays)
          SizedBox(
            width: dayWidth,
            height: 44,
            child:
                row.lessonIndex <=
                    routine.effectiveLessonCount(row.period.id, weekday)
                ? TeacherPresetValueMenu(
                    key: ValueKey(
                      'preset-cell-$weekday-${row.period.id}-${row.lessonIndex}',
                    ),
                    contextLabel: '${row.label} · ${_weekdayLabel(weekday)}',
                    current:
                        values[(
                          weekday: weekday,
                          periodTypeId: row.period.id,
                          lessonIndex: row.lessonIndex,
                        )],
                    onChanged: (value) => onChanged((
                      weekday: weekday,
                      periodTypeId: row.period.id,
                      lessonIndex: row.lessonIndex,
                    ), value),
                    child: _presetCellContent(
                      values[(
                        weekday: weekday,
                        periodTypeId: row.period.id,
                        lessonIndex: row.lessonIndex,
                      )],
                      visual,
                    ),
                  )
                : _tableCell('', dayWidth, background: visual.cellTint),
          ),
      ],
    );
  }

  Widget _tableCell(
    String label,
    double width, {
    double height = 44,
    required Color background,
    Color foreground = AppTheme.ink,
  }) => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      border: const Border(
        right: BorderSide(color: Colors.white),
        bottom: BorderSide(color: Colors.white),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: foreground,
        fontSize: height == 32 ? 12 : 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _presetCellContent(PresetValue? value, PeriodVisual visual) {
    final (background, foreground) = switch (value) {
      PresetValue.prefer => (AppTheme.selectedBlue, AppTheme.blue),
      PresetValue.must => (AppTheme.blue, Colors.white),
      PresetValue.forbid => (AppTheme.destructiveSurface, AppTheme.destructive),
      PresetValue.auto || null => (visual.cellTint, AppTheme.muted),
    };
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        border: const Border(
          right: BorderSide(color: Colors.white),
          bottom: BorderSide(color: Colors.white),
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
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.tableDivider),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.inkSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '当前：${current?.label ?? PresetValue.auto.label}',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
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
