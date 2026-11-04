part of 'temporary_adjustments_page.dart';

extension _TemporaryAdjustmentsEditor on _TemporaryAdjustmentsPageState {
  void _queueCandidateBatch(
    TemporaryTimetableState state,
    List<SchedulePosition> positions,
  ) {
    final sourceKey = _source!.key;
    final kind = _kind!;
    final classId = _classId!;
    final weekIndex = _week ?? 0;
    final batchKey = '$sourceKey:$kind:$classId:$weekIndex';
    if (_candidateBatchKey == batchKey) return;
    _cancelCandidateBatchWorker();
    _candidateBatchKey = batchKey;
    _candidateBatchError = null;
    _candidateBatchComplete = false;
    _candidateCache.clear();
    if (_candidateBatchInFlightKey == batchKey) {
      _queuedCandidateBatch = null;
      return;
    }
    final start = state.snapshot.term.firstTeachingWeekStart!.add(
      Duration(days: weekIndex * 7),
    );
    _queuedCandidateBatch = (
      key: batchKey,
      input: (
        state: state,
        positions: positions,
        sourceKey: sourceKey,
        kind: kind,
        classId: classId,
        start: start,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_runNextCandidateBatch());
    });
  }

  Future<void> _runNextCandidateBatch() async {
    if (!mounted || _candidateBatchRunning) return;
    final queued = _queuedCandidateBatch;
    if (queued == null) return;
    _queuedCandidateBatch = null;
    if (_candidateBatchKey != queued.key) return;

    final generation = _candidateBatchGeneration;
    _candidateBatchRunning = true;
    _candidateBatchInFlightKey = queued.key;
    try {
      final result = await _runCandidateBatchIsolate(queued.input, generation);
      if (result != null &&
          mounted &&
          generation == _candidateBatchGeneration &&
          _candidateBatchKey == queued.key) {
        setState(() {
          _candidateCache.addAll(result);
          _candidateBatchComplete = true;
        });
      }
    } on Object catch (error) {
      if (mounted &&
          generation == _candidateBatchGeneration &&
          _candidateBatchKey == queued.key) {
        setState(() {
          _candidateBatchError = '$error';
          _error = '候选课位检测失败，请重新选择调整方式：$error';
        });
      }
    } finally {
      if (generation == _candidateBatchGeneration) {
        _candidateBatchRunning = false;
        _candidateBatchInFlightKey = null;
      }
      if (mounted &&
          generation == _candidateBatchGeneration &&
          _queuedCandidateBatch != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_runNextCandidateBatch());
        });
      }
    }
  }

  Future<Map<String, ActualChangePreview>?> _runCandidateBatchIsolate(
    _CandidateBatch input,
    int generation,
  ) async {
    final resultPort = ReceivePort();
    final errorPort = ReceivePort();
    final completer = Completer<Map<String, ActualChangePreview>?>();
    _candidateBatchResultPort = resultPort;
    _candidateBatchErrorPort = errorPort;
    _candidateBatchCompleter = completer;
    resultPort.listen((message) {
      if (generation != _candidateBatchGeneration || completer.isCompleted) {
        return;
      }
      if (message is Map<String, ActualChangePreview>) {
        completer.complete(message);
      } else if (message is _CandidateBatchWorkerError) {
        completer.completeError(
          StateError('${message.message}\n${message.stackTrace}'),
        );
      } else {
        completer.completeError(StateError('候选课位检测返回了无法识别的结果。'));
      }
    });
    errorPort.listen((message) {
      if (generation != _candidateBatchGeneration || completer.isCompleted) {
        return;
      }
      completer.completeError(StateError('候选课位检测 isolate 异常：$message'));
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<_CandidateBatchMessage>(
        _candidateBatchWorker,
        (input: input, replyTo: resultPort.sendPort),
        onError: errorPort.sendPort,
      );
      if (generation != _candidateBatchGeneration || !mounted) {
        isolate.kill(priority: Isolate.immediate);
        if (!completer.isCompleted) completer.complete(null);
      } else {
        _candidateBatchIsolate = isolate;
      }
      return await completer.future;
    } finally {
      resultPort.close();
      errorPort.close();
      if (identical(_candidateBatchResultPort, resultPort)) {
        _candidateBatchResultPort = null;
      }
      if (identical(_candidateBatchErrorPort, errorPort)) {
        _candidateBatchErrorPort = null;
      }
      if (identical(_candidateBatchCompleter, completer)) {
        _candidateBatchCompleter = null;
      }
      if (identical(_candidateBatchIsolate, isolate)) {
        _candidateBatchIsolate = null;
      }
    }
  }

  // ---------------------------------------------------------------- 面板

  bool get _panelReady {
    if (_kind == null || _saving) return false;
    if (_kind == 'substitute') return _teacherId != null;
    if (_kind == 'move') return _targetDate != null && _targetPosition != null;
    return _swapTarget != null;
  }

  Widget _radioIndicator(bool selected) {
    final colors = context.appColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? colors.blue : _borderStrong,
          width: 1.5,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }

  Widget _courseCard({
    required String line1,
    String? line2,
    String? subjectId,
    String? line2SubjectId,
    Widget? extra,
    bool plain = false,
  }) {
    final colors = context.appColors;
    final titleStyle = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: colors.ink,
    );
    final subjectName = subjectId == null ? null : _subject(subjectId);
    final title = subjectName != null && line1.startsWith(subjectName)
        ? Text.rich(
            TextSpan(
              style: titleStyle,
              children: [
                TextSpan(
                  text: subjectName,
                  style: TextStyle(
                    color: SubjectColors.of(context, subjectId!),
                  ),
                ),
                TextSpan(text: line1.substring(subjectName.length)),
              ],
            ),
          )
        : Text(line1, style: titleStyle);
    final line2SubjectName = line2SubjectId == null
        ? null
        : _subject(line2SubjectId);
    final subtitle = line2 == null
        ? null
        : line2SubjectName != null && line2.startsWith(line2SubjectName)
        ? Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12, color: colors.inkSecondary),
              children: [
                TextSpan(
                  text: line2SubjectName,
                  style: TextStyle(
                    color: SubjectColors.of(context, line2SubjectId!),
                  ),
                ),
                TextSpan(text: line2.substring(line2SubjectName.length)),
              ],
            ),
          )
        : Text(
            line2,
            style: TextStyle(fontSize: 12, color: colors.inkSecondary),
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: plain ? _hintNeutral : colors.selectedBlue,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          if (subtitle != null) ...[const SizedBox(height: 2), subtitle],
          if (extra != null) ...[const SizedBox(height: 3), extra],
        ],
      ),
    );
  }

  void _setAdjustmentKind(String value) {
    if (_kind == value) return;
    setState(() {
      _kind = value;
      _invalidateCandidateBatch();
      _error = null;
      _targetDate = null;
      _targetPosition = null;
      _swapTarget = null;
    });
  }

  Widget _adjustmentModeSelector() {
    final colors = context.appColors;
    Widget option(String value, String label) {
      final selected = _kind == value;
      return Expanded(
        child: InkWell(
          onTap: () => _setAdjustmentKind(value),
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? _blueWash : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? colors.blue : colors.inkSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _segBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          option('swap', '换课'),
          option('move', '移课'),
          option('substitute', '代课'),
        ],
      ),
    );
  }

  String get _adjustmentModeDescription => switch (_kind) {
    'move' => '移到本班空课位，原位置变为空位。',
    'substitute' => '更换任课教师，时间和班级保持不变。',
    _ => '与本班另一实际课次互换时间，可跨日期、跨周。',
  };

  Widget _panel(TemporaryTimetableState state) {
    final colors = context.appColors;
    final source = _source!;
    final group = source.item.meetingId == null
        ? [source]
        : state.lessons
              .where(
                (lesson) =>
                    lesson.item.meetingId == source.item.meetingId &&
                    lesson.date == source.date,
              )
              .toList();
    final classIds = group.map((lesson) => lesson.item.classId).toSet();
    final teacherIds = group.map((lesson) => lesson.item.teacherId).toSet();
    final locks = state.snapshot.locks
        .where(
          (lock) =>
              (lock.scope == ScheduleLockScope.schoolClass &&
                  classIds.contains(lock.targetId)) ||
              (lock.scope == ScheduleLockScope.teacher &&
                  teacherIds.contains(lock.targetId)),
        )
        .toList();
    final previous = state.records.reversed
        .where(
          (record) =>
              record.cancelledAt == null &&
              !record.needsAttention &&
              record.changes.any((change) => change.after.key == source.key),
        )
        .firstOrNull;

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _secLabel('已选课次'),
            const SizedBox(height: 7),
            _courseCard(
              line1:
                  '${_subject(source.item.subjectId)} · ${_dateLabel(source.date)}（${_weekdayLabel(source.date)}）',
              subjectId: source.item.subjectId,
              line2:
                  '${_slotLabel(source.item.position)} · ${_teacher(source.item.teacherId)} · ${_className(source.item.classId)}'
                  '${classIds.length > 1 ? ' 等 ${classIds.length} 个班' : ''}',
            ),
          ],
        ),
        if (locks.isNotEmpty)
          _hintBox(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '课表已锁定：${locks.map((lock) => lock.scope == ScheduleLockScope.teacher ? '教师 ${_teacher(lock.targetId)}' : '班级 ${_className(lock.targetId)}').join('、')}。',
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: _amberText,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () =>
                      ref.read(selectedSectionProvider.notifier).state =
                          AppSection.scheduling,
                  child: const Text('前往课表解锁'),
                ),
              ],
            ),
            tone: 'amber',
          ),
        if (previous != null)
          _hintBox(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '此课格已按调整生效，常规周课表不受影响。调整前：'
                  '${_lesson(previous.changes.firstWhere((change) => change.after.key == source.key).before)}。',
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: _blueHintText,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => setState(() {
                    _records = true;
                    _recordClass = source.item.classId;
                  }),
                  child: const Text('查看关联记录'),
                ),
              ],
            ),
            tone: 'blue',
          ),
        const SizedBox(height: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _secLabel('调整方式'),
            const SizedBox(height: 7),
            _adjustmentModeSelector(),
            const SizedBox(height: 6),
            Text(
              _adjustmentModeDescription,
              style: TextStyle(fontSize: 12, color: colors.inkSecondary),
            ),
          ],
        ),
        if (_kind == 'swap')
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              _secLabel('目标课次'),
              const SizedBox(height: 7),
              _swapTarget != null
                  ? _courseCard(
                      plain: true,
                      line1:
                          '${_subject(_swapTarget!.item.subjectId)} · ${_dateLabel(_swapTarget!.date)}（${_weekdayLabel(_swapTarget!.date)}）',
                      subjectId: _swapTarget!.item.subjectId,
                      line2:
                          '${_slotLabel(_swapTarget!.item.position)} · ${_teacher(_swapTarget!.item.teacherId)} · ${_className(_swapTarget!.item.classId)}',
                      extra: Text(
                        '⇅ 与已选课次互换',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.blue,
                        ),
                      ),
                    )
                  : _hintBox(
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: '在周课表中'),
                            TextSpan(
                              text: '选择另一节课程',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: colors.ink,
                              ),
                            ),
                            const TextSpan(text: '作为互换目标，可跨日期、跨周。'),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        if (_kind == 'move')
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              _secLabel('目标空课位'),
              const SizedBox(height: 7),
              _targetDate != null && _targetPosition != null
                  ? _courseCard(
                      plain: true,
                      line1:
                          '${_dateLabel(_targetDate!)}（${_weekdayLabel(_targetDate!)}）'
                          '${_slotLabel(_targetPosition)}',
                      line2:
                          '空课位 · ${_subject(source.item.subjectId)} 将移入，原位置变为空位',
                    )
                  : _hintBox(
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: '在周课表中'),
                            TextSpan(
                              text: '选择一个空课位',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: colors.ink,
                              ),
                            ),
                            const TextSpan(text: '作为目标，原位置会空出来。'),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        if (_kind == 'substitute')
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              _secLabel('代课教师'),
              const SizedBox(height: 7),
              _teacherId != null
                  ? _courseCard(
                      plain: true,
                      line1: _teacher(_teacherId!),
                      line2:
                          '${_subject(_subjectId ?? source.item.subjectId)} · 该时段空闲 · ${_className(source.item.classId)}',
                      line2SubjectId: _subjectId ?? source.item.subjectId,
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: AppOutlineButton(
                        onPressed: _saving ? null : _chooseTeacher,
                        child: const Text('选择代课教师'),
                      ),
                    ),
              const SizedBox(height: 7),
              AppSelectField<String?>(
                items: {
                  '保留原科目': null,
                  for (final s in state.snapshot.subjects) s.name: s.id,
                },
                value: _subjectId,
                hint: '保留原科目（可更改）',
                searchable: true,
                searchHint: '搜索科目',
                onChanged: (value) => setState(() => _subjectId = value),
              ),
            ],
          ),
        const SizedBox(height: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _secLabel('原因（选填，会记录在调整记录中）'),
            const SizedBox(height: 7),
            AppTextFormField(
              controller: _reason,
              decoration: const InputDecoration(hintText: '如：教研活动、外出培训、场地占用'),
            ),
          ],
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '调整课次',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.ink,
                    ),
                  ),
                ),
                AppIconButton(
                  icon: Icons.close,
                  tooltip: '关闭',
                  iconSize: 15,
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _invalidateCandidateBatch();
                          _source = null;
                        }),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: body,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                AppGhostButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _invalidateCandidateBatch();
                          _source = null;
                        }),
                  child: const Text('取消'),
                ),
                const Spacer(),
                AppPrimaryButton(
                  onPressed: _panelReady ? _openPreview : null,
                  child: Text(_saving ? '正在处理…' : '下一步 · 预览'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 弹窗部件

  Widget _dialogHeader(
    String title, {
    String? sub,
    required VoidCallback onClose,
  }) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 23 / 16,
                    color: colors.ink,
                  ),
                ),
              ),
              AppIconButton(
                icon: Icons.close,
                tooltip: '关闭',
                iconSize: 15,
                onPressed: onClose,
              ),
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(
              sub,
              style: TextStyle(fontSize: 12.5, color: colors.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scopeRadio({
    required String title,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? _blueWash : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _radioIndicator(selected),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: colors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: colors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopeBlock({
    required TemporaryTimetableState state,
    required ActualLesson source,
    required bool range,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required ValueChanged<bool> onScopeChanged,
    required void Function(DateTime start, DateTime end) onDatesChanged,
  }) {
    final colors = context.appColors;
    final term = state.snapshot.term;
    final firstDate = term.firstTeachingWeekStart!;
    final lastDate = term.teachingWeekEnd(term.teachingWeekCount) ?? firstDate;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _scopeRadio(
            title: '仅本次',
            desc:
                '仅 ${_dateLabel(source.date)}（${_weekdayLabel(source.date)}）'
                '${_slotLabel(source.item.position)} 这一次课',
            selected: !range,
            onTap: () {
              if (range) onScopeChanged(false);
            },
          ),
          Divider(height: 1, color: colors.border),
          _scopeRadio(
            title: '日期范围',
            desc: '按选定星期与节次逐周展开，换课保留源与目标的日期间隔',
            selected: range,
            onTap: () {
              if (!range) onScopeChanged(true);
            },
          ),
          if (range)
            Container(
              color: _blueWash,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '开始日期',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.inkSecondary,
                        ),
                      ),
                      SizedBox(
                        width: 132,
                        child: AppDateField(
                          value: rangeStart,
                          onChanged: (value) {
                            if (value != null) {
                              onDatesChanged(value, rangeEnd);
                            }
                          },
                          firstDate: firstDate,
                          lastDate: lastDate,
                          hint: '请选择日期',
                          format: _dateLabel,
                        ),
                      ),
                      Text(
                        '至',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.inkSecondary,
                        ),
                      ),
                      Text(
                        '结束日期',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.inkSecondary,
                        ),
                      ),
                      SizedBox(
                        width: 132,
                        child: AppDateField(
                          value: rangeEnd,
                          onChanged: (value) {
                            if (value != null) {
                              onDatesChanged(rangeStart, value);
                            }
                          },
                          firstDate: firstDate,
                          lastDate: lastDate,
                          hint: '请选择日期',
                          format: _dateLabel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '按教学日历、单双周与补课映射生成实际课次',
                    style: TextStyle(fontSize: 11.5, color: colors.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
