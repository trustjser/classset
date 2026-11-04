part of 'temporary_adjustments_page.dart';

extension _TemporaryAdjustmentsTimetable on _TemporaryAdjustmentsPageState {
  Widget _gridFootNote() {
    final message = _teacherView
        ? '教师视图用于核对占用；请在班级视图选择课次发起调整。'
        : switch (_kind) {
            'swap' when _source != null => '在课表中选择另一节课程作为互换目标。',
            'move' => '在课表中选择一个空课位；原课位会空出来。',
            'substitute' => '选择代课教师后，可预览本次变更。',
            _ => '选择一节课开始调整；已生效的变更会标记在课格中。',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: context.appColors.inkSecondary),
      ),
    );
  }

  // ---------------------------------------------------------------- 周课表

  Widget _dayHeading(TemporaryTimetableState state, DateTime date) {
    final colors = context.appColors;
    final today = DateUtils.isSameDay(date, DateTime.now());
    final exception = _exceptionOn(state, date);
    final note = switch (exception?.kind) {
      CalendarExceptionKind.holiday =>
        exception!.note.isNotEmpty ? exception.note : '休息日',
      CalendarExceptionKind.makeup =>
        '补 · 按周${['一', '二', '三', '四', '五', '六', '日'][exception!.makeupWeekday! - 1]}作息',
      _ => null,
    };
    final noteColor = exception?.kind == CalendarExceptionKind.makeup
        ? colors.warning
        : colors.muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _weekdayLabel(date),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: today ? colors.blue : colors.ink,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _md(date),
                style: TextStyle(
                  fontSize: 12,
                  color: today ? colors.blue : colors.inkSecondary,
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                note,
                style: TextStyle(fontSize: 11, color: noteColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _periodHead(String periodName, int index, SchedulePosition? position) {
    final colors = context.appColors;
    final time = _lessonStartTime(position);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$periodName 第 $index 节',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: colors.inkSecondary,
            ),
          ),
          if (time != null)
            Text(time, style: TextStyle(fontSize: 11, color: colors.muted)),
        ],
      ),
    );
  }

  Widget _typePill(String kind) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _blueWash,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _kindLabel(kind),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: colors.blue,
        ),
      ),
    );
  }

  Widget _grid(TemporaryTimetableState state, DateTime start) {
    final colors = context.appColors;
    final classId = _classId!;
    final stage = state.snapshot.stageIdForClass(classId);
    final routine = state.snapshot.routines
        .where((r) => r.stageId == stage)
        .firstOrNull;
    if (routine == null) return const Center(child: Text('请先设置该班级的作息。'));
    final indexes = _indexesFor(state);
    final positions = indexes.positionsByClass[classId] ?? const [];
    final days = _visibleScheduleDates(state, start, positions);
    final periods = [...routine.periodTypes]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final rows = <(String, int, String, SchedulePosition?)>[];
    for (final period in periods) {
      final count = positions
          .where((p) => p.periodTypeId == period.id)
          .fold<int>(0, (n, p) => p.lessonIndex > n ? p.lessonIndex : n);
      for (var i = 1; i <= count; i++) {
        final position = positions
            .where((p) => p.periodTypeId == period.id && p.lessonIndex == i)
            .firstOrNull;
        rows.add((period.id, i, period.name, position));
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth > 76.0 + days.length * 132.0
              ? constraints.maxWidth
              : 76.0 + days.length * 132.0,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 76),
                    for (final date in days)
                      Expanded(
                        child: Container(
                          color: _isWeekend(date) ? colors.tableHeader : null,
                          child: _dayHeading(state, date),
                        ),
                      ),
                  ],
                ),
                for (final row in rows)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 76,
                        height: 75,
                        child: _periodHead(row.$3, row.$2, row.$4),
                      ),
                      for (final date in days)
                        Expanded(
                          child: Container(
                            color: _isWeekend(date) ? colors.tableHeader : null,
                            child: _cell(state, date, row.$1, row.$2, indexes),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _teacherGrid(TemporaryTimetableState state, DateTime start) {
    final colors = context.appColors;
    if (_viewTeacherId == null) return const Center(child: Text('暂无教师'));
    final indexes = _indexesFor(state);
    String timeLabel(int minute) =>
        '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
    final classIds = {
      for (final assignment in state.snapshot.assignments)
        if (assignment.teacherId == _viewTeacherId) assignment.classId,
      ...indexes.classesForTeacher(_viewTeacherId!),
    };
    final days = _visibleScheduleDates(
      state,
      start,
      classIds.expand(
        (classId) =>
            indexes.positionsByClass[classId] ?? const <SchedulePosition>[],
      ),
    );
    final slots = <String, ({String label, int sort})>{};
    for (final classId in classIds) {
      for (final position
          in indexes.positionsByClass[classId] ?? const <SchedulePosition>[]) {
        final routine = state.snapshot.routines
            .where((r) => r.stageId == position.stageId)
            .firstOrNull;
        final period = routine?.periodTypes
            .where((p) => p.id == position.periodTypeId)
            .firstOrNull;
        final stage = state.snapshot.stages
            .where((s) => s.id == position.stageId)
            .firstOrNull;
        slots.putIfAbsent(
          _teacherGridSlotKey(position),
          () => (
            label: position.hasClockTime
                ? '${timeLabel(position.startMinute!)}\n${timeLabel(position.endMinute!)}'
                : '${stage?.name ?? ''} ${period?.name ?? ''}\n第 ${position.lessonIndex} 节',
            sort:
                position.startMinute ??
                10000 +
                    (stage?.sortOrder ?? 0) * 1000 +
                    (period?.sortOrder ?? 0) * 100 +
                    position.lessonIndex,
          ),
        );
      }
    }
    final ordered = slots.entries.toList()
      ..sort((a, b) => a.value.sort.compareTo(b.value.sort));
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth > 76.0 + days.length * 132.0
              ? constraints.maxWidth
              : 76.0 + days.length * 132.0,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 76),
                    for (final date in days)
                      Expanded(
                        child: Container(
                          color: _isWeekend(date) ? colors.tableHeader : null,
                          child: _dayHeading(state, date),
                        ),
                      ),
                  ],
                ),
                for (final slot in ordered)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 76,
                        height: 75,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 6, 10, 4),
                          child: Text(
                            slot.value.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              color: colors.inkSecondary,
                            ),
                          ),
                        ),
                      ),
                      for (final date in days)
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final courses = indexes.teacherLessons(
                                _viewTeacherId!,
                                date,
                                slot.key,
                              );
                              final subjectColor = courses.isEmpty
                                  ? null
                                  : SubjectColors.of(
                                      context,
                                      courses.first.item.subjectId,
                                    );
                              final subjectBackground = courses.isEmpty
                                  ? null
                                  : SubjectColors.cellBackground(
                                      context,
                                      courses.first.item.subjectId,
                                    );
                              final changed = indexes
                                  .recordForLessons(courses)
                                  ?.record;
                              return Container(
                                color: _isWeekend(date)
                                    ? colors.tableHeader
                                    : null,
                                child: Container(
                                  height: 75,
                                  margin: const EdgeInsets.all(3),
                                  child: _TemporaryLessonHover(
                                    enabled:
                                        !state.reconciliationPending &&
                                        courses.isNotEmpty,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color:
                                            subjectBackground ??
                                            _slotBackground(
                                              filled: courses.isNotEmpty,
                                            ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: courses.isEmpty
                                              ? _isDark
                                                    ? const Color(0x1FFFFFFF)
                                                    : const Color(0x1A000000)
                                              : colors.border,
                                        ),
                                      ),
                                      child: courses.isEmpty
                                          ? null
                                          : InkWell(
                                              hoverColor: Colors.transparent,
                                              splashColor: colors.blue
                                                  .withValues(alpha: .08),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              onTap: state.reconciliationPending
                                                  ? null
                                                  : () => setState(() {
                                                      _invalidateCandidateBatch();
                                                      _classId = courses
                                                          .first
                                                          .item
                                                          .classId;
                                                      _recordClass = _classId;
                                                      _recordTeacher = null;
                                                      _teacherView = false;
                                                      _source = courses.first;
                                                      _kind = 'swap';
                                                    }),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                child: Stack(
                                                  children: [
                                                    Padding(
                                                      padding: changed != null
                                                          ? const EdgeInsets.only(
                                                              right: 34,
                                                            )
                                                          : EdgeInsets.zero,
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            _subject(
                                                              courses
                                                                  .first
                                                                  .item
                                                                  .subjectId,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              color:
                                                                  subjectColor,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Text(
                                                            courses
                                                                .map(
                                                                  (
                                                                    lesson,
                                                                  ) => _className(
                                                                    lesson
                                                                        .item
                                                                        .classId,
                                                                  ),
                                                                )
                                                                .join('、'),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: colors
                                                                  .inkSecondary,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (changed != null)
                                                      Positioned(
                                                        top: 5,
                                                        right: 6,
                                                        child: _typePill(
                                                          changed.kind,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _slotBackground({required bool filled, bool candidate = false}) {
    if (candidate) {
      return _isDark ? const Color(0xFF20384F) : const Color(0xFFF0F7FF);
    }
    return filled ? Theme.of(context).colorScheme.surface : Colors.transparent;
  }

  Widget _cell(
    TemporaryTimetableState state,
    DateTime date,
    String periodId,
    int index,
    _TemporaryTimetableIndexes indexes,
  ) {
    final colors = context.appColors;
    final exception = _exceptionOn(state, date);
    final weekday = exception?.makeupWeekday ?? date.weekday;
    final classId = _classId!;
    final position = indexes.position(classId, weekday, periodId, index);
    final available =
        exception?.kind != CalendarExceptionKind.holiday && position != null;
    final course = indexes.classLesson(classId, date, periodId, index);
    final subjectForeground = course == null
        ? null
        : SubjectColors.of(context, course.item.subjectId);
    final subjectBackground = course == null
        ? null
        : SubjectColors.cellBackground(context, course.item.subjectId);
    final record = course == null
        ? null
        : indexes.recordForLesson(course.key)?.record;
    final selecting = _source != null && (_kind == 'move' || _kind == 'swap');
    final eligible =
        selecting &&
        available &&
        ((_kind == 'move' && course == null) ||
            (_kind == 'swap' && course != null && course.key != _source!.key));
    ActualChangePreview? candidate;
    if (eligible) {
      final key = _candidateKey(
        _source!.key,
        _kind!,
        date,
        periodId,
        index,
        course?.key,
      );
      if (state.lessons.length > 2000) {
        _queueCandidateBatch(
          state,
          indexes.positionsByClass[classId] ?? const [],
        );
        candidate = _candidateCache[key];
      } else {
        candidate = _candidateCache.putIfAbsent(
          key,
          () => _kind == 'move'
              ? state.previewMove(
                  TemporaryMoveRequest(
                    sourceKey: _source!.key,
                    targetDate: date,
                    targetPosition: position,
                  ),
                  problem: indexes.problem,
                )
              : state.previewSwap(
                  TemporarySwapRequest(
                    firstKey: _source!.key,
                    secondKey: course!.key,
                  ),
                  problem: indexes.problem,
                ),
        );
      }
    }
    final batchError = state.lessons.length > 2000
        ? _candidateBatchError ??
              (_candidateBatchComplete && eligible && candidate == null
                  ? '未找到对应课位，请重新选择调整方式'
                  : null)
        : null;
    final waiting = eligible && candidate == null && batchError == null;
    final invalid =
        eligible &&
        (batchError != null ||
            (candidate != null && candidate.errors.isNotEmpty));
    final hint = batchError != null
        ? '候选检测失败：$batchError'
        : invalid
        ? candidate!.errors.join('；')
        : waiting
        ? '正在检测'
        : eligible
        ? '可选'
        : selecting
        ? '不可选'
        : '';
    final isChosenTarget =
        course != null && course.key == _swapTarget?.key ||
        (_targetDate != null &&
            DateUtils.isSameDay(_targetDate, date) &&
            _targetPosition?.periodTypeId == periodId &&
            _targetPosition?.lessonIndex == index);
    final isSource = course != null && course.key == _source?.key;
    final makeupDay = exception?.kind == CalendarExceptionKind.makeup;
    final canTap =
        !state.reconciliationPending &&
        available &&
        !invalid &&
        !waiting &&
        (selecting ? eligible : course != null);

    // 底色与描边
    Color bg() {
      if (!available) return Colors.transparent;
      if (isChosenTarget) return colors.selectedBlue;
      if (invalid) return colors.tableHeader;
      if (subjectBackground != null) return subjectBackground;
      if (makeupDay) return _blueWash;
      return _slotBackground(filled: course != null, candidate: eligible);
    }

    Widget body;
    if (!available) {
      body = Center(
        child: Text('—', style: TextStyle(fontSize: 12, color: colors.muted)),
      );
    } else if (course == null) {
      final text = eligible
          ? (waiting
                ? '检测中'
                : invalid
                ? '不可选'
                : '可选')
          : '空课位';
      final color = invalid
          ? colors.warning
          : eligible
          ? colors.blue
          : colors.muted;
      body = Center(
        child: Text(text, style: TextStyle(fontSize: 11.5, color: color)),
      );
    } else {
      final stateText = selecting && eligible
          ? (waiting
                ? '检测中'
                : invalid
                ? '不可选'
                : '可选')
          : null;
      // 课格内容直接作为容器子节点（容器已有 8px 内边距），
      // 再包一层会挤压三行文字的可用高度导致溢出。
      body = Stack(
        children: [
          Padding(
            padding: record != null && !selecting
                ? const EdgeInsets.only(right: 34)
                : EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _subject(course.item.subjectId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: subjectForeground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _teacher(course.item.teacherId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.inkSecondary),
                ),
                if (stateText != null)
                  Text(
                    stateText,
                    style: TextStyle(
                      fontSize: 11,
                      color: invalid
                          ? colors.warning
                          : waiting
                          ? colors.muted
                          : colors.blue,
                    ),
                  ),
              ],
            ),
          ),
          if (record != null && !selecting)
            Positioned(top: 5, right: 6, child: _typePill(record.kind)),
        ],
      );
    }

    final highlight = isSource || isChosenTarget;
    final dashed = course == null && available;
    Widget decorated;
    if (dashed) {
      decorated = Container(
        height: 75,
        margin: const EdgeInsets.all(3),
        child: _TemporaryLessonHover(
          enabled: canTap && !highlight,
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            foregroundPainter: _DashBorderPainter(
              color: eligible
                  ? (invalid
                        ? colors.warning
                        : colors.blue.withValues(alpha: .45))
                  : _isDark
                  ? const Color(0x1FFFFFFF)
                  : const Color(0x1A000000),
              radius: 8,
            ),
            child: Container(
              height: 75,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bg(),
                borderRadius: BorderRadius.circular(8),
              ),
              child: body,
            ),
          ),
        ),
      );
    } else {
      decorated = Container(
        margin: const EdgeInsets.all(3),
        child: _TemporaryLessonHover(
          enabled: canTap && !highlight,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 75,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bg(),
              borderRadius: BorderRadius.circular(8),
              border: highlight
                  ? Border.all(color: colors.blue, width: 1.5)
                  : null,
            ),
            child: body,
          ),
        ),
      );
    }
    Widget cell = Tooltip(
      message: hint,
      child: InkWell(
        key: ValueKey('temporary-cell-${_date(date)}-$periodId-$index'),
        hoverColor: Colors.transparent,
        splashColor: colors.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        onTap: canTap
            ? () => setState(() {
                if (_source != null && _kind == 'move' && course == null) {
                  _targetDate = date;
                  _targetPosition = position;
                } else if (_source != null &&
                    _kind == 'swap' &&
                    course != null &&
                    course.key != _source!.key) {
                  _swapTarget = course;
                } else if (course != null) {
                  _invalidateCandidateBatch();
                  _source = course;
                  _kind = 'swap';
                  _targetDate = null;
                  _targetPosition = null;
                  _swapTarget = null;
                  _teacherId = null;
                  _subjectId = null;
                }
              })
            : null,
        child: decorated,
      ),
    );
    if (selecting && !eligible && !isSource) {
      cell = Opacity(opacity: .45, child: cell);
    }
    final draggable = course == null || state.reconciliationPending || selecting
        ? cell
        : Draggable<ActualLesson>(
            data: course,
            feedback: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: colors.surface,
              // 拖拽提示靠近视口边缘时会被压紧约束，用 OverflowBox 按自然尺寸绘制。
              child: OverflowBox(
                minWidth: 0,
                maxWidth: 220,
                minHeight: 0,
                maxHeight: double.infinity,
                alignment: Alignment.topLeft,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _subject(course.item.subjectId),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: subjectForeground,
                        ),
                      ),
                      Text(
                        _teacher(course.item.teacherId),
                        style: TextStyle(fontSize: 11, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child: cell,
          );
    return DragTarget<ActualLesson>(
      onWillAcceptWithDetails: (details) =>
          !state.reconciliationPending &&
          available &&
          details.data.item.classId == _classId &&
          details.data.key != course?.key,
      onAcceptWithDetails: (details) {
        setState(() {
          _invalidateCandidateBatch();
          _source = details.data;
          _kind = course == null ? 'move' : 'swap';
          _targetDate = course == null ? date : null;
          _targetPosition = course == null ? position : null;
          _swapTarget = course;
          _teacherId = null;
          _subjectId = null;
          _error = null;
        });
      },
      builder: (context, candidates, rejected) => draggable,
    );
  }
}
