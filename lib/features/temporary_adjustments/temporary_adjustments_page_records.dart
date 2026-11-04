part of 'temporary_adjustments_page.dart';

extension _TemporaryAdjustmentsRecords on _TemporaryAdjustmentsPageState {
  Widget _miniPill(String label, {Color? background, Color? foreground}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: background ?? _hintNeutral,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: foreground ?? context.appColors.inkSecondary,
          ),
        ),
      );

  Widget _filterChip(String label, bool value, ValueChanged<bool> onChanged) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: value ? colors.selectedBlue : colors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value ? colors.blue.withValues(alpha: .35) : _borderStrong,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: value ? colors.blue : colors.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseTeacher() async {
    final state = _data!;
    final source = _source!;
    var sameSubject = false;
    var sameGrade = false;
    var sameClass = false;
    var searchQuery = '';
    var pickedId = _teacherId;
    var expandedId = <String>{};
    final week = state.snapshot.term.teachingWeekOf(source.date);
    final weeklyByTeacher = <String, List<ActualLesson>>{};
    for (final lesson in state.lessons) {
      if (state.snapshot.term.teachingWeekOf(lesson.date) == week) {
        weeklyByTeacher
            .putIfAbsent(lesson.item.teacherId, () => [])
            .add(lesson);
      }
    }
    final avatarPalette = [
      context.appColors.blue,
      context.appColors.success,
      context.appColors.warning,
      context.appColors.purple,
    ];

    final selected = await showAppDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final colors = context.appColors;
          final normalizedQuery = searchQuery.trim().toLowerCase();
          final candidates = state.snapshot.teachers.where((teacher) {
            if (normalizedQuery.isNotEmpty &&
                !teacher.displayName.toLowerCase().contains(normalizedQuery)) {
              return false;
            }
            final assignments = state.snapshot.assignments.where(
              (assignment) => assignment.teacherId == teacher.id,
            );
            if (sameSubject &&
                !teacher.subjectIds.contains(
                  _subjectId ?? source.item.subjectId,
                ) &&
                !assignments.any(
                  (assignment) =>
                      assignment.subjectId ==
                      (_subjectId ?? source.item.subjectId),
                )) {
              return false;
            }
            if (sameGrade &&
                !assignments.any(
                  (assignment) =>
                      state.snapshot.gradeIdForClass(assignment.classId) ==
                      state.snapshot.gradeIdForClass(source.item.classId),
                )) {
              return false;
            }
            if (sameClass &&
                !assignments.any(
                  (assignment) => assignment.classId == source.item.classId,
                )) {
              return false;
            }
            return true;
          }).toList();

          return AppDialog(
            maxWidth: 560,
            padding: EdgeInsets.zero,
            titleGap: 0,
            actionsGap: 0,
            title: _dialogHeader(
              '选择代课教师',
              sub:
                  '${_dateLabel(source.date)}（${_weekdayLabel(source.date)}）'
                  '${_slotLabel(source.item.position)} · ${_subject(source.item.subjectId)} · ${_className(source.item.classId)}',
              onClose: () => Navigator.pop(dialogContext),
            ),
            content: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hintBox(
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                '科目：${_subject(_subjectId ?? source.item.subjectId)}',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const TextSpan(text: '（默认保留，可在发起调整中更改）'),
                        ],
                      ),
                    ),
                    tone: 'blue',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _filterChip('同科目', sameSubject, (value) {
                          if (sameSubject != value) {
                            update(() => sameSubject = value);
                          }
                        }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _filterChip('同年级', sameGrade, (value) {
                          if (sameGrade != value) {
                            update(() => sameGrade = value);
                          }
                        }),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _filterChip('本班优先', sameClass, (value) {
                          if (sameClass != value) {
                            update(() => sameClass = value);
                          }
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    onChanged: (value) => update(() => searchQuery = value),
                    decoration: InputDecoration(
                      hintText: '搜索教师姓名',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: colors.muted,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (candidates.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '没有符合条件的教师',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                    )
                  else
                    for (var index = 0; index < candidates.length; index++)
                      Builder(
                        builder: (context) {
                          final teacher = candidates[index];
                          final weekLessons =
                              weeklyByTeacher[teacher.id] ??
                              const <ActualLesson>[];
                          var busy = false;
                          var missingClock = false;
                          ActualLesson? busyLesson;
                          final sourcePosition = source.item.position!;
                          for (final lesson in weekLessons.where(
                            (lesson) => lesson.date == source.date,
                          )) {
                            if (lesson.key == source.key ||
                                (source.item.meetingId != null &&
                                    lesson.item.meetingId ==
                                        source.item.meetingId)) {
                              continue;
                            }
                            final position = lesson.item.position;
                            if (position == null) continue;
                            if (sourcePosition.stageId != position.stageId &&
                                (!sourcePosition.hasClockTime ||
                                    !position.hasClockTime)) {
                              missingClock = true;
                            } else if (sourcePosition.overlaps(position)) {
                              busy = true;
                              busyLesson = lesson;
                            }
                          }
                          final noChange =
                              teacher.id == source.item.teacherId &&
                              (_subjectId == null ||
                                  _subjectId == source.item.subjectId);
                          final teacherLocked = state.snapshot.locks.any(
                            (lock) =>
                                lock.scope == ScheduleLockScope.teacher &&
                                lock.targetId == teacher.id,
                          );
                          final available =
                              !busy &&
                              !missingClock &&
                              !noChange &&
                              !teacherLocked;
                          final weekCount = weekLessons
                              .map(
                                (lesson) =>
                                    '${_date(lesson.date)}:${lesson.item.meetingId ?? lesson.item.id}',
                              )
                              .toSet()
                              .length;
                          final statusLine = available
                              ? '本次新增 1 节 · 本周 $weekCount 节'
                              : missingClock
                              ? '✕ 缺少可对比的作息时间'
                              : busy
                              ? '✕ 该时段有课：${_className(busyLesson!.item.classId)} ${_subject(busyLesson.item.subjectId)}'
                              : noChange
                              ? '✕ 与当前任课教师相同'
                              : '✕ 教师课表已锁定';
                          final expanded = expandedId.contains(teacher.id);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: pickedId == teacher.id
                                      ? colors.blue
                                      : colors.border,
                                ),
                                borderRadius: BorderRadius.circular(11),
                                color: pickedId == teacher.id
                                    ? _blueWash
                                    : colors.surface,
                              ),
                              child: Column(
                                children: [
                                  InkWell(
                                    onTap: available
                                        ? () => update(
                                            () => pickedId = teacher.id,
                                          )
                                        : null,
                                    child: Opacity(
                                      opacity: available ? 1 : .62,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color:
                                                    avatarPalette[index %
                                                        avatarPalette.length],
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  teacher
                                                      .displayName
                                                      .characters
                                                      .first,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 11),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          teacher.displayName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 13.5,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: colors.ink,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      _miniPill(
                                                        teacher.subjectIds
                                                                .map(_subject)
                                                                .firstOrNull ??
                                                            _subject(
                                                              _subjectId ??
                                                                  source
                                                                      .item
                                                                      .subjectId,
                                                            ),
                                                      ),
                                                      if (available) ...[
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        _miniPill(
                                                          '该时段空闲',
                                                          background: colors
                                                              .successSurface,
                                                          foreground:
                                                              colors.success,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    statusLine,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: available
                                                          ? colors.inkSecondary
                                                          : colors.warning,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            _textButton(
                                              '查看课表',
                                              fontSize: 12,
                                              onTap: () => update(() {
                                                if (expandedId.contains(
                                                  teacher.id,
                                                )) {
                                                  expandedId.remove(teacher.id);
                                                } else {
                                                  expandedId.add(teacher.id);
                                                }
                                              }),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (expanded)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final lesson in weekLessons)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 2,
                                                  ),
                                              child: Text(
                                                _lesson(lesson),
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: colors.muted,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ],
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: Row(
                  children: [
                    Text(
                      '候选默认按空闲状态排序；可展开查看候选教师同期课表。',
                      style: TextStyle(fontSize: 11.5, color: colors.muted),
                    ),
                    const Spacer(),
                    AppGhostButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('关闭'),
                    ),
                    const SizedBox(width: 8),
                    AppPrimaryButton(
                      onPressed: pickedId != null
                          ? () => Navigator.pop(dialogContext, pickedId)
                          : null,
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    if (selected != null && mounted) setState(() => _teacherId = selected);
  }

  // ---------------------------------------------------------------- 记录列表

  String _recordDateSummary(TemporaryAdjustmentRecord record) {
    if (record.changes.isEmpty) return '';
    final first = record.changes.first;
    final last = record.changes.last;
    String slot(ActualLessonChange change) =>
        '${_dateLabel(change.before.date)}（${_weekdayLabel(change.before.date)}）'
        '${_slotLabel(change.before.item.position)}';
    if (record.kind == 'swap' && record.changes.length >= 2) {
      final count = record.changes.length ~/ 2;
      return '${slot(first)} ↔ ${slot(record.changes[1])}${count > 1 ? ' 等 $count 组' : ''}';
    }
    if (record.kind == 'move') {
      return '${slot(first)} → ${_dateLabel(last.after.date)}（${_weekdayLabel(last.after.date)}）'
          '${_slotLabel(last.after.item.position)}';
    }
    return slot(first);
  }

  String _substitutionSummary(ActualLessonChange change) {
    final before = change.before.item;
    final after = change.after.item;
    if (before.subjectId != after.subjectId) {
      return '${_subjectTeacher(change.before)} → ${_subjectTeacher(change.after)}（保留时间）';
    }
    return '${_teacher(before.teacherId)} → ${_teacher(after.teacherId)}（保留科目与时间）';
  }

  String _recordChangeSummary(TemporaryAdjustmentRecord record) {
    if (record.changes.isEmpty) return '';
    if (record.kind == 'swap') {
      final pairs = [
        for (var index = 0; index + 1 < record.changes.length; index += 2)
          '${_subjectTeacher(record.changes[index].before)} ↔ ${_subjectTeacher(record.changes[index + 1].before)}',
      ];
      if (pairs.isEmpty) return _subjectTeacher(record.changes.first.before);
      final shownPairs = pairs.take(2).join('；');
      final remaining = pairs.length - 2;
      return '$shownPairs${remaining > 0 ? '；另 $remaining 组' : ''} · 互换时间，科目与教师不变';
    }
    final change = record.changes.first;
    final summary = record.kind == 'move'
        ? '${_subjectTeacher(change.before)} 移至 ${_dateLabel(change.after.date)}（${_weekdayLabel(change.after.date)}）${_slotLabel(change.after.item.position)}'
        : _substitutionSummary(change);
    return record.changes.length > 1
        ? '$summary · 共 ${record.changes.length} 节'
        : summary;
  }

  Widget _statusBadge(TemporaryAdjustmentRecord record) {
    final colors = context.appColors;
    final (color, label) = record.cancelledAt != null
        ? (colors.muted, '已取消')
        : record.needsAttention
        ? (colors.warning, '需处理')
        : (colors.success, '有效');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12.5, color: color)),
      ],
    );
  }

  Widget _recordList(TemporaryTimetableState state) {
    final colors = context.appColors;
    final records = _filteredRecords(state).reversed.toList();
    if (records.isEmpty) {
      final noRecordsYet = state.records.isEmpty;
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      noRecordsYet ? '还没有调整记录' : '没有符合筛选条件的记录',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      noRecordsYet
                          ? '确认一次调整后，变更课次与原因会显示在这里。'
                          : '当前筛选范围内没有调整记录。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.inkSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                noRecordsYet
                    ? AppPrimaryButton(
                        onPressed: () => setState(() => _records = false),
                        child: const Text('查看实际课表'),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _textButton('清除筛选条件', onTap: _clearRecordFilters),
                          if (!_showCancelled &&
                              _recordStatus == null &&
                              state.records.any(
                                (record) => record.cancelledAt != null,
                              ))
                            _textButton(
                              '显示已取消记录',
                              onTap: () =>
                                  setState(() => _showCancelled = true),
                            ),
                        ],
                      ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1280,
            maxHeight: constraints.maxHeight,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < records.length; i++)
                Container(
                  decoration: i == records.length - 1
                      ? null
                      : BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: colors.border),
                          ),
                        ),
                  child: _recordRow(records[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearRecordFilters() => setState(() {
    _recordType = null;
    _recordStatus = null;
    _recordClass = null;
    _recordTeacher = null;
    _recordDates = null;
    _showCancelled = false;
  });

  Widget _recordRow(TemporaryAdjustmentRecord record) {
    final colors = context.appColors;
    final cancelled = record.cancelledAt != null;
    final className = record.changes.isEmpty
        ? ''
        : _className(record.changes.first.before.item.classId);
    final title = Text(
      '$className · ${_recordDateSummary(record)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: colors.ink,
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _recordChangeSummary(record),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: colors.inkSecondary,
          ),
        ),
        if (record.needsAttention)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: colors.warning),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '常规课表已变化，此调整需人工处理',
                    style: TextStyle(fontSize: 12, color: colors.warning),
                  ),
                ),
              ],
            ),
          ),
        if (record.reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '原因：${record.reason}',
              style: TextStyle(fontSize: 12, color: colors.muted),
            ),
          ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _textButton('详情', onTap: () => _showRecordDetails(record)),
        if (!cancelled)
          _textButton(
            '取消',
            color: colors.destructive,
            onTap: _saving ? null : () => _cancel(record),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Opacity(
          opacity: cancelled ? .6 : 1,
          child: constraints.maxWidth < 760
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _typePill(record.kind),
                        const SizedBox(width: 10),
                        Expanded(child: title),
                        const SizedBox(width: 8),
                        _statusBadge(record),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: details,
                    ),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                )
              : Row(
                  children: [
                    _typePill(record.kind),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 3), details],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _statusBadge(record),
                    const SizedBox(width: 12),
                    actions,
                  ],
                ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: content,
        );
      },
    );
  }

  Future<void> _showRecordDetails(TemporaryAdjustmentRecord record) async {
    final colors = context.appColors;
    final className = record.changes.isEmpty
        ? ''
        : _className(record.changes.first.before.item.classId);
    await showAppDialog(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 560,
        padding: EdgeInsets.zero,
        titleGap: 0,
        actionsGap: 0,
        title: _dialogHeader(
          '调整详情',
          sub:
              '${_kindLabel(record.kind)} · $className · ${_recordDateSummary(record)}',
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final change in record.changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_lesson(change.before)}\n→ ${_lesson(change.after)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: colors.inkSecondary,
                    ),
                  ),
                ),
              if (record.reason.isNotEmpty)
                Text(
                  '原因：${record.reason}',
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
              if (record.cancelledAt != null) ...[
                const SizedBox(height: 8),
                _hintBox(const Text('此调整已取消，未应用在实际课表中。')),
              ],
              if (record.needsAttention) ...[
                const SizedBox(height: 8),
                _hintBox(const Text('常规课表已变化，此调整需人工处理。'), tone: 'amber'),
              ],
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Row(
              children: [
                const Spacer(),
                AppGhostButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 记录筛选 / 导出 / 取消

  List<TemporaryAdjustmentRecord> _filteredRecords(
    TemporaryTimetableState state,
  ) => state.records.where((record) {
    final status = record.cancelledAt != null
        ? 'cancelled'
        : record.needsAttention
        ? 'invalid'
        : 'active';
    if (_recordStatus != null && status != _recordStatus) return false;
    if (_recordStatus == null && !_showCancelled && status == 'cancelled') {
      return false;
    }
    if (_recordType != null && record.kind != _recordType) return false;
    return record.changes.any(_matchesChange);
  }).toList();

  bool _matchesChange(ActualLessonChange change) {
    if (_recordClass != null && change.before.item.classId != _recordClass) {
      return false;
    }
    if (_recordTeacher != null &&
        change.before.item.teacherId != _recordTeacher &&
        change.after.item.teacherId != _recordTeacher) {
      return false;
    }
    if (_recordDates != null &&
        (change.before.date.isBefore(_recordDates!.start) ||
            change.before.date.isAfter(_recordDates!.end)) &&
        (change.after.date.isBefore(_recordDates!.start) ||
            change.after.date.isAfter(_recordDates!.end))) {
      return false;
    }
    return true;
  }

  Future<void> _selectRecordDates() async {
    final term = _data!.snapshot.term;
    final range = await showDateRangePicker(
      context: context,
      firstDate: term.firstTeachingWeekStart!,
      lastDate: term.teachingWeekEnd(term.teachingWeekCount)!,
      initialDateRange: _recordDates,
    );
    if (range != null && mounted) setState(() => _recordDates = range);
  }

  Future<void> _export(TemporaryExportKind kind) async {
    final state = _data!;
    final title = switch (kind) {
      TemporaryExportKind.teacher => '教师通知',
      TemporaryExportKind.schoolClass => '班级通知',
      TemporaryExportKind.details => '调整明细',
    };
    try {
      final location = await ref.read(temporaryExportSaveLocationProvider)(
        '$title.xlsx',
      );
      if (location == null) return;
      final bytes = buildTemporaryAdjustmentWorkbook(
        state.snapshot,
        _filteredRecords(state),
        kind,
        teacherId: _recordTeacher,
        includeChange: _matchesChange,
        includeCancelled: _showCancelled || _recordStatus == 'cancelled',
      );
      await XFile.fromData(
        Uint8List.fromList(bytes),
        name: '$title.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ).saveTo(location.path);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$title 已导出')));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '导出失败：$error');
    }
  }

  Future<void> _cancel(TemporaryAdjustmentRecord record) async {
    final state = _data!;
    final colors = context.appColors;
    final index = state.records.indexWhere((item) => item.id == record.id);
    final keys = record.changes.map((change) => change.before.key).toSet();
    final dependencies = index < 0
        ? <TemporaryAdjustmentRecord>[]
        : state.records
              .skip(index + 1)
              .where(
                (later) =>
                    later.cancelledAt == null &&
                    later.changes.any(
                      (change) => keys.contains(change.before.key),
                    ),
              )
              .toList();
    final className = record.changes.isEmpty
        ? ''
        : _className(record.changes.first.before.item.classId);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 470,
        padding: EdgeInsets.zero,
        titleGap: 0,
        actionsGap: 0,
        title: _dialogHeader(
          '取消调整',
          sub:
              '${_kindLabel(record.kind)} · $className · ${_recordDateSummary(record)}',
          onClose: () => Navigator.pop(dialogContext, false),
        ),
        content: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (record.needsAttention)
                _hintBox(
                  const Text('此调整已失效，当前没有应用到实际课表。取消后保留历史记录。'),
                  tone: 'amber',
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final change in record.changes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                color: colors.successSurface,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '✓',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.success,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                '${_dateLabel(change.after.date)}（${_weekdayLabel(change.after.date)}）'
                                '${_slotLabel(change.after.item.position)} 恢复为 '
                                '${_subject(change.after.item.subjectId)}·${_teacher(change.before.item.teacherId)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: colors.inkSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              if (dependencies.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.warningSurface,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '存在依赖此结果的后续调整：',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: dependencies
                              .map(
                                (later) =>
                                    '${_kindLabel(later.kind)} · ${_recordDateSummary(later)}',
                              )
                              .join('；'),
                        ),
                        const TextSpan(text: '。建议先取消后续调整，再取消本条。'),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: _amberText,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _hintBox(const Text('取消后实际课表将恢复原安排，常规周课表不受影响。')),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Row(
              children: [
                AppGhostButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('关闭'),
                ),
                const Spacer(),
                if (dependencies.isNotEmpty)
                  AppGhostButton(onPressed: null, child: const Text('先取消后续调整')),
                const SizedBox(width: 8),
                AppDestructiveButton(
                  onPressed: dependencies.isEmpty
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  child: const Text('取消调整'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(schoolRepositoryProvider)
          .cancelTemporaryAdjustment(
            termId: widget.termId,
            adjustmentId: record.id,
            expectedRevision: state.revision,
          );
      if (!mounted) return;
      await _load();
    } on Object catch (error) {
      if (error.toString().contains('已改变')) await _load();
      if (mounted) setState(() => _error = '取消失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
