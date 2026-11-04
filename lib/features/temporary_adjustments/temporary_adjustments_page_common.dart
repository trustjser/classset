part of 'temporary_adjustments_page.dart';

extension _TemporaryAdjustmentsCommon on _TemporaryAdjustmentsPageState {
  String _subject(String id) =>
      _data!.snapshot.subjects.where((s) => s.id == id).firstOrNull?.name ?? id;
  String _teacher(String id) =>
      _data!.snapshot.teachers
          .where((t) => t.id == id)
          .firstOrNull
          ?.displayName ??
      id;
  String _className(String id) =>
      _data!.snapshot.classes.where((c) => c.id == id).firstOrNull?.name ?? id;
  String _kindLabel(String kind) => switch (kind) {
    'move' => '移课',
    'swap' => '换课',
    _ => '代课',
  };

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _md(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  String _dateLabel(DateTime date) => '${date.month}月${date.day}日';
  String _weekdayLabel(DateTime date) =>
      '周${['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}';

  String _slotLabel(SchedulePosition? position) {
    final routine = _data!.snapshot.routines
        .where((r) => r.stageId == position?.stageId)
        .firstOrNull;
    final period = routine?.periodTypes
        .where((p) => p.id == position?.periodTypeId)
        .firstOrNull;
    return '${period?.name ?? ''}第 ${position?.lessonIndex ?? '-'} 节';
  }

  String _subjectTeacher(ActualLesson lesson) =>
      '${_subject(lesson.item.subjectId)}·${_teacher(lesson.item.teacherId)}';

  String _lesson(ActualLesson lesson) =>
      '${_dateLabel(lesson.date)}（${_weekdayLabel(lesson.date)}）'
      '${_slotLabel(lesson.item.position)} '
      '${_subject(lesson.item.subjectId)} ${_teacher(lesson.item.teacherId)}';

  String? _lessonStartTime(SchedulePosition? position) {
    final routine = _data!.snapshot.routines
        .where((r) => r.stageId == position?.stageId)
        .firstOrNull;
    final period = routine?.periodTypes
        .where((p) => p.id == position?.periodTypeId)
        .firstOrNull;
    return period?.lessonTimes
        .where((t) => t.lessonIndex == position?.lessonIndex)
        .firstOrNull
        ?.startLabel;
  }

  CalendarException? _exceptionOn(
    TemporaryTimetableState state,
    DateTime date,
  ) => state.exceptions.where((e) => _date(e.date) == _date(date)).firstOrNull;

  bool _isWeekend(DateTime date) => date.weekday >= DateTime.saturday;

  List<DateTime> _visibleScheduleDates(
    TemporaryTimetableState state,
    DateTime start,
    Iterable<SchedulePosition> positions,
  ) {
    final weekdays = positions.map((position) => position.weekday).toSet();
    final week = List.generate(7, (index) => start.add(Duration(days: index)));
    final visible = week.where((date) {
      final exception = _exceptionOn(state, date);
      final scheduleWeekday = exception?.makeupWeekday ?? date.weekday;
      if (exception?.kind == CalendarExceptionKind.holiday &&
          _isWeekend(date)) {
        return false;
      }
      return exception != null || weekdays.contains(scheduleWeekday);
    }).toList();
    return visible.isEmpty ? week : visible;
  }

  // ---------------------------------------------------------------- 视觉令牌

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _borderStrong =>
      _isDark ? const Color(0x38FFFFFF) : const Color(0x24000000);
  Color get _blueWash =>
      _isDark ? const Color(0xFF1C2D3D) : const Color(0xFFF3F8FE);
  Color get _segBackground =>
      _isDark ? const Color(0xFF262A31) : const Color(0xFFEFEDEB);
  Color get _hintNeutral =>
      _isDark ? const Color(0xFF2A2E35) : const Color(0xFFF4F3F2);
  Color get _amberText =>
      _isDark ? context.appColors.warning : const Color(0xFF8A5A14);
  Color get _blueHintText =>
      _isDark ? context.appColors.inkSecondary : const Color(0xFF1C5A96);
  Color get _switchTrackOff =>
      _isDark ? const Color(0xFF4A4F57) : const Color(0xFFD8D5D2);

  // ---------------------------------------------------------------- 小控件

  Widget _secLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: .2,
      color: context.appColors.muted,
    ),
  );

  Widget _hintBox(Widget child, {String tone = 'neutral'}) {
    final colors = context.appColors;
    final (bg, fg) = switch (tone) {
      'blue' => (colors.selectedBlue, _blueHintText),
      'amber' => (colors.warningSurface, _amberText),
      _ => (_hintNeutral, colors.inkSecondary),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 12, height: 1.55, color: fg),
        child: child,
      ),
    );
  }

  Widget _textButton(
    String label, {
    VoidCallback? onTap,
    Color? color,
    double fontSize = 13,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          color:
              color ??
              (onTap == null
                  ? context.appColors.muted
                  : context.appColors.blue),
        ),
      ),
    ),
  );

  Widget _iconButton(IconData icon, String tooltip, VoidCallback? onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 16,
            color: onTap == null
                ? context.appColors.muted
                : context.appColors.inkSecondary,
          ),
        ),
      );

  Widget _segmentShell(List<Widget> children) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: _segBackground,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );

  Widget _segmentButton(
    String label, {
    required bool active,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: active ? _blueWash : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                color: active ? colors.blue : colors.inkSecondary,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing],
          ],
        ),
      ),
    );
  }

  /// 弹出式选择按钮：白底描边小壳 + FPopoverMenu 菜单（30px 行）。
  /// 带搜索的弹出选择控件：Forui FSelect 自带搜索框与限高滚动列表，
  /// 班级 / 教师等长选项列表不会溢出屏幕。
  Widget _selectField({
    required Map<String, String?> items,
    required String? value,
    required ValueChanged<String?> onChanged,
    String? hint,
    String searchHint = '搜索',
    double width = 148,
    bool compact = true,
    bool stretch = false,
  }) {
    final field = AppSelectField<String?>(
      compact: compact,
      items: items,
      value: value,
      hint: hint,
      searchable: true,
      searchHint: searchHint,
      onChanged: onChanged,
    );
    return stretch ? field : SizedBox(width: width, child: field);
  }

  // ---------------------------------------------------------------- 工具栏

  Widget _tabsSegment(TemporaryTimetableState state, {bool showCount = true}) {
    final visibleCount = _filteredRecords(state).length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pageTabButton(
          '实际课表',
          active: !_records,
          onTap: () => setState(() {
            _records = false;
            if (_recordClass != null) _classId = _recordClass;
            if (_recordTeacher != null) {
              _viewTeacherId = _recordTeacher;
              _teacherView = true;
            }
            _recordClass = _teacherView ? null : _classId;
            _recordTeacher = _teacherView ? _viewTeacherId : null;
          }),
        ),
        _pageTabButton(
          '调整记录',
          active: _records,
          onTap: () => setState(() {
            _records = true;
            if (_teacherView) {
              _recordTeacher = _viewTeacherId;
              _recordClass = null;
            } else {
              _recordClass = _classId;
              _recordTeacher = null;
            }
          }),
          trailing: showCount
              ? Text(
                  '$visibleCount 条',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.appColors.inkSecondary,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _pageTabButton(
    String label, {
    required bool active,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? colors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? colors.ink : colors.inkSecondary,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      ),
    );
  }

  Widget _viewSegment() => _segmentShell([
    _segmentButton(
      '班级视图',
      active: !_teacherView,
      onTap: () => setState(() {
        _invalidateCandidateBatch();
        _teacherView = false;
        _recordClass = _classId;
        _recordTeacher = null;
      }),
    ),
    _segmentButton(
      '教师视图',
      active: _teacherView,
      onTap: () => setState(() {
        _invalidateCandidateBatch();
        _teacherView = true;
        _recordClass = null;
        _recordTeacher = _viewTeacherId;
        _source = null;
        _kind = null;
      }),
    ),
  ]);

  Widget _classSelect(TemporaryTimetableState state, {double width = 148}) =>
      _selectField(
        width: width,
        items: {for (final c in state.snapshot.classes) c.name: c.id},
        value: _classId,
        hint: '选择班级',
        searchHint: '搜索班级',
        onChanged: (value) => setState(() {
          _invalidateCandidateBatch();
          _classId = value;
          _recordClass = value;
          _source = null;
          _kind = null;
        }),
      );

  Widget _teacherSelect(TemporaryTimetableState state, {double width = 148}) =>
      _selectField(
        width: width,
        items: {
          for (final teacher in state.snapshot.teachers)
            teacher.displayName: teacher.id,
        },
        value: _viewTeacherId,
        hint: '选择教师',
        searchHint: '搜索教师',
        onChanged: (value) => setState(() {
          _viewTeacherId = value;
          _recordTeacher = value;
        }),
      );

  Widget _weekNav(
    TemporaryTimetableState state,
    DateTime start, {
    bool compact = false,
  }) {
    final colors = context.appColors;
    final week = _week ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLayout =
            compact ||
            (constraints.maxWidth.isFinite && constraints.maxWidth < 760);
        final showDateRange =
            !compactLayout ||
            !constraints.maxWidth.isFinite ||
            constraints.maxWidth >= 360;
        final weekLabel = compactLayout
            ? '第${week + 1}教学周'
            : '第${week + 1}教学周 · ${state.snapshot.term.weekCycleLabel(week + 1)}';
        final dateRange =
            '${_md(start)}–${_md(start.add(const Duration(days: 6)))}';

        final weekAndDate = compactLayout
            ? Flexible(
                fit: FlexFit.loose,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          weekLabel,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: colors.ink,
                          ),
                        ),
                      ),
                      if (showDateRange) ...[
                        const SizedBox(width: 6),
                        Text(
                          dateRange,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      weekLabel,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      dateRange,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ],
                ),
              );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconButton(
              Icons.chevron_left,
              '上一周',
              week > 0 ? () => _changeWeek(week - 1) : null,
            ),
            weekAndDate,
            _iconButton(
              Icons.chevron_right,
              '下一周',
              week + 1 < state.snapshot.term.teachingWeekCount
                  ? () => _changeWeek(week + 1)
                  : null,
            ),
            _textButton(
              '本周',
              onTap: () => _changeWeek(
                (state.snapshot.term.teachingWeekOf(DateTime.now()) ?? 1) - 1,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _exportMenuButton() {
    final colors = context.appColors;
    final shell = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('导出', style: TextStyle(fontSize: 13, color: colors.ink)),
          const SizedBox(width: 5),
          Icon(Icons.expand_more, size: 14, color: colors.muted),
        ],
      ),
    );
    return FPopoverMenu(
      menuBuilder: (context, controller, menu) => [
        FItemGroup(
          divider: .none,
          children: [
            for (final kind in TemporaryExportKind.values)
              AppMenuTile(
                item: AppMenuItem(
                  label: switch (kind) {
                    TemporaryExportKind.teacher => '教师通知',
                    TemporaryExportKind.schoolClass => '班级通知',
                    TemporaryExportKind.details => '调整明细',
                  },
                  onPressed: () {
                    unawaited(controller.hide());
                    unawaited(_export(kind));
                  },
                ),
              ),
          ],
        ),
      ],
      builder: (context, controller, child) => FTappable(
        semanticsLabel: '导出',
        onPress: () => unawaited(controller.toggle()),
        child: child!,
      ),
      child: shell,
    );
  }

  Widget _showCancelledToggle() {
    final colors = context.appColors;
    final on = _showCancelled;
    return InkWell(
      onTap: () => setState(() => _showCancelled = !on),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? colors.selectedBlue : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? colors.blue.withValues(alpha: .35) : _borderStrong,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 12,
              decoration: BoxDecoration(
                color: on ? colors.blue : _switchTrackOff,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 150),
                    left: on ? 11 : 2,
                    top: 1.5,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '显示已取消',
              style: TextStyle(
                fontSize: 12.5,
                color: on ? colors.blue : colors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleToolbar(TemporaryTimetableState state, DateTime start) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        final scopeControls = [
          _viewSegment(),
          _teacherView
              ? _teacherSelect(state, width: wide ? 148 : 132)
              : _classSelect(state, width: wide ? 148 : 132),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 38,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.appColors.border),
                ),
              ),
              child: Row(
                children: [
                  _tabsSegment(state),
                  const Spacer(),
                  if (wide) ...[
                    _weekNav(state, start),
                    const SizedBox(width: 10),
                  ],
                  _exportMenuButton(),
                ],
              ),
            ),
            if (!wide) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _weekNav(
                  state,
                  start,
                  compact: constraints.maxWidth < 760,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: scopeControls,
            ),
          ],
        );
      },
    );
  }

  Widget _recordsToolbar(TemporaryTimetableState state) {
    final colors = context.appColors;
    final filters = [
      _selectField(
        width: 112,
        hint: '全部类型',
        searchHint: '搜索类型',
        items: const {
          '全部类型': null,
          '换课': 'swap',
          '移课': 'move',
          '代课': 'substitute',
        },
        value: _recordType,
        onChanged: (value) => setState(() => _recordType = value),
      ),
      _selectField(
        width: 112,
        hint: '全部状态',
        searchHint: '搜索状态',
        items: const {
          '全部状态': null,
          '有效': 'active',
          '需处理': 'invalid',
          '已取消': 'cancelled',
        },
        value: _recordStatus,
        onChanged: (value) => setState(() => _recordStatus = value),
      ),
      _selectField(
        width: 132,
        hint: '全部班级',
        searchHint: '搜索班级',
        items: {
          '全部班级': null,
          for (final c in state.snapshot.classes) c.name: c.id,
        },
        value: _recordClass,
        onChanged: (value) => setState(() => _recordClass = value),
      ),
      _selectField(
        width: 132,
        hint: '全部教师',
        searchHint: '搜索教师',
        items: {
          '全部教师': null,
          for (final teacher in state.snapshot.teachers)
            teacher.displayName: teacher.id,
        },
        value: _recordTeacher,
        onChanged: (value) => setState(() => _recordTeacher = value),
      ),
      InkWell(
        onTap: _selectRecordDates,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            // 与 compact 筛选器一致的浅灰底无边框样式。
            color: colors.tableHeader,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _recordDates == null
                    ? '全部日期'
                    : '${_date(_recordDates!.start)} 至 ${_date(_recordDates!.end)}',
                style: TextStyle(fontSize: 12.5, color: colors.inkSecondary),
              ),
            ],
          ),
        ),
      ),
      if (_recordDates != null)
        _textButton(
          '清除日期',
          onTap: () => setState(() => _recordDates = null),
          fontSize: 12.5,
        ),
      _showCancelledToggle(),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1050;
        final filterRow = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: filters,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 38,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.appColors.border),
                ),
              ),
              child: wide
                  ? Row(
                      children: [
                        _tabsSegment(state),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: filterRow,
                          ),
                        ),
                      ],
                    )
                  : _tabsSegment(state),
            ),
            if (!wide) ...[const SizedBox(height: 10), filterRow],
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- 页面骨架
}
