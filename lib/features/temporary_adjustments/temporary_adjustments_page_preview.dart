part of 'temporary_adjustments_page.dart';

extension _TemporaryAdjustmentsPreview on _TemporaryAdjustmentsPageState {
  Widget _previewItem({
    required String mark,
    required Color markBackground,
    required Color markForeground,
    String? date,
    required String change,
    String? issue,
    String? skipNote,
    Widget? action,
    bool bad = false,
    bool skip = false,
  }) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bad
            ? _isDark
                  ? colors.destructiveSurface
                  : const Color(0xFFFDF7F6)
            : colors.surface,
        border: Border.all(
          color: bad ? colors.destructive.withValues(alpha: .4) : colors.border,
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Opacity(
        opacity: skip ? .65 : 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: markBackground,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  mark,
                  style: TextStyle(fontSize: 11, color: markForeground),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (date != null)
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.ink,
                      ),
                    ),
                  Text(
                    change,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: colors.inkSecondary,
                    ),
                  ),
                  if (issue != null)
                    Text(
                      issue,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: colors.destructive,
                      ),
                    ),
                  if (skipNote != null)
                    Text(
                      skipNote,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: colors.muted,
                      ),
                    ),
                  ?action,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 预览弹窗

  Future<void> _openPreview() async {
    final state = _data!;
    final source = _source!;
    final term = state.snapshot.term;
    final defaultEnd =
        term.teachingWeekEnd(term.teachingWeekCount) ?? source.date;
    var range = false;
    var rangeStart = source.date;
    var rangeEnd = defaultEnd;
    final excluded = <DateTime>{};
    var computeToken = 0;

    ({
      TemporaryMoveRequest? move,
      TemporarySwapRequest? swap,
      TemporarySubstituteRequest? sub,
    })
    buildRequests() => (
      move: _kind == 'move' && _targetDate != null && _targetPosition != null
          ? TemporaryMoveRequest(
              sourceKey: source.key,
              targetDate: _targetDate!,
              targetPosition: _targetPosition!,
              reason: _reason.text,
              rangeStart: range ? rangeStart : null,
              rangeEnd: range ? rangeEnd : null,
              excludedDates: excluded,
            )
          : null,
      swap: _kind == 'swap' && _swapTarget != null
          ? TemporarySwapRequest(
              firstKey: source.key,
              secondKey: _swapTarget!.key,
              reason: _reason.text,
              rangeStart: range ? rangeStart : null,
              rangeEnd: range ? rangeEnd : null,
              excludedDates: excluded,
            )
          : null,
      sub: _kind == 'substitute' && _teacherId != null
          ? TemporarySubstituteRequest(
              sourceKey: source.key,
              teacherId: _teacherId!,
              subjectId: _subjectId,
              reason: _reason.text,
              rangeStart: range ? rangeStart : null,
              rangeEnd: range ? rangeEnd : null,
              excludedDates: excluded,
            )
          : null,
    );

    final ui = ValueNotifier<_PreviewUi>(
      const _PreviewUi(
        preview: ActualChangePreview(changes: [], errors: ['请先选择调整目标']),
      ),
    );

    Future<void> recompute() async {
      final reqs = buildRequests();
      if (reqs.move == null && reqs.swap == null && reqs.sub == null) {
        ui.value = const _PreviewUi(
          preview: ActualChangePreview(changes: [], errors: ['请先选择调整目标']),
        );
        return;
      }
      final token = ++computeToken;
      if (state.lessons.length <= 2000) {
        ui.value = _PreviewUi(
          preview: reqs.move != null
              ? state.previewMove(reqs.move!)
              : reqs.swap != null
              ? state.previewSwap(reqs.swap!)
              : state.previewSubstitute(reqs.sub!),
        );
        return;
      }
      ui.value = _PreviewUi(preview: ui.value.preview, computing: true);
      if (mounted) setState(() => _saving = true);
      try {
        final preview = await computeTemporaryPreview(
          state: state,
          move: reqs.move,
          swap: reqs.swap,
          substitute: reqs.sub,
        );
        if (token != computeToken || !mounted) return;
        if (_data?.revision != state.revision) {
          ui.value = const _PreviewUi(
            preview: ActualChangePreview(
              changes: [],
              errors: ['课表已改变，请重新选择并预览。'],
            ),
            computing: false,
          );
          return;
        }
        ui.value = _PreviewUi(preview: preview, computing: false);
      } on Object catch (error) {
        if (token != computeToken || !mounted) return;
        ui.value = _PreviewUi(
          preview: ActualChangePreview(changes: [], errors: ['预览失败：$error']),
          computing: false,
        );
      } finally {
        if (mounted && token == computeToken) setState(() => _saving = false);
      }
    }

    await recompute();
    if (!mounted) {
      ui.dispose();
      return;
    }

    final colors = context.appColors;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<_PreviewUi>(
        valueListenable: ui,
        builder: (context, value, _) {
          final preview = value.preview;
          final reqs = buildRequests();
          final count = <String>{};
          for (var index = 0; index < preview.changes.length; index++) {
            if (reqs.swap != null && index.isOdd) continue;
            final lesson = preview.changes[index].before;
            count.add(
              '${_date(lesson.date)}:${lesson.item.meetingId ?? lesson.item.id}',
            );
          }
          final canConfirm =
              preview.errors.isEmpty &&
              preview.changes.isNotEmpty &&
              !value.computing;

          final previewItems = <Widget>[];
          for (var index = 0; index < preview.changes.length; index++) {
            final change = preview.changes[index];
            if (reqs.swap != null && index.isOdd) continue;
            final dateLine =
                '${_dateLabel(change.before.date)}（${_weekdayLabel(change.before.date)}）';
            final changeLine = switch (_kind) {
              'swap' when index + 1 < preview.changes.length =>
                '${_subjectTeacher(change.before)} ↔ ${_subjectTeacher(preview.changes[index + 1].before)}（互换时间，各自科目与教师不变）',
              'swap' => '${_subjectTeacher(change.before)}（互换时间）',
              'move' =>
                '${_subjectTeacher(change.before)} → ${_dateLabel(change.after.date)}（${_weekdayLabel(change.after.date)}）'
                    '${_slotLabel(change.after.item.position)}（移至空课位，原位置变为空位）',
              _ => _substitutionSummary(change),
            };
            previewItems.add(
              _previewItem(
                mark: '✓',
                markBackground: colors.successSurface,
                markForeground: colors.success,
                date: dateLine,
                change: changeLine,
              ),
            );
          }
          for (final error in preview.errors) {
            final excludeDate = range && error.length >= 10
                ? DateTime.tryParse(error.substring(0, 10))
                : null;
            previewItems.add(
              _previewItem(
                mark: '✕',
                markBackground: colors.destructiveSurface,
                markForeground: colors.destructive,
                change: error,
                bad: true,
                action: excludeDate != null
                    ? _textButton(
                        '移除此日期',
                        fontSize: 12,
                        onTap: () {
                          excluded.add(excludeDate);
                          unawaited(recompute());
                        },
                      )
                    : null,
              ),
            );
          }
          for (final date in preview.skippedDates) {
            previewItems.add(
              _previewItem(
                mark: '－',
                markBackground: _hintNeutral,
                markForeground: colors.muted,
                change: '${_dateLabel(date)}（${_weekdayLabel(date)}）',
                skipNote: '没有实际课次，已跳过',
                skip: true,
              ),
            );
          }

          final subTitle = switch (_kind) {
            'swap' =>
              _swapTarget == null
                  ? '换课'
                  : '换课 · ${_subjectTeacher(source)} 与 ${_subjectTeacher(_swapTarget!)} 互换时间',
            'move' =>
              _targetDate == null
                  ? '移课'
                  : '移课 · ${_subjectTeacher(source)} 移至 ${_dateLabel(_targetDate!)}（${_weekdayLabel(_targetDate!)}）${_slotLabel(_targetPosition)}',
            _ =>
              _teacherId == null
                  ? '代课'
                  : _subjectId != null && _subjectId != source.item.subjectId
                  ? '代课 · ${_subjectTeacher(source)} → ${_subject(_subjectId!)}·${_teacher(_teacherId!)}（保留时间）'
                  : '代课 · ${_teacher(source.item.teacherId)} → ${_teacher(_teacherId!)}（保留科目与时间）',
          };

          return AppDialog(
            maxWidth: 560,
            padding: EdgeInsets.zero,
            titleGap: 0,
            actionsGap: 0,
            title: _dialogHeader(
              '预览调整',
              sub: subTitle,
              onClose: () => Navigator.pop(dialogContext, false),
            ),
            content: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _scopeBlock(
                    state: state,
                    source: source,
                    range: range,
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd,
                    onScopeChanged: (value) {
                      range = value;
                      unawaited(recompute());
                    },
                    onDatesChanged: (start, end) {
                      rangeStart = start;
                      rangeEnd = end;
                      unawaited(recompute());
                    },
                  ),
                  const SizedBox(height: 14),
                  if (value.computing)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '正在生成预览…',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (previewItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '没有可调整的课次',
                        style: TextStyle(fontSize: 12.5, color: colors.muted),
                      ),
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < previewItems.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          previewItems[i],
                        ],
                      ],
                    ),
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
                      child: const Text('返回修改'),
                    ),
                    const Spacer(),
                    if (!canConfirm &&
                        preview.errors.isNotEmpty &&
                        !value.computing)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          '存在冲突课次，需修正后再确认',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.destructive,
                          ),
                        ),
                      ),
                    AppPrimaryButton(
                      onPressed: canConfirm
                          ? () => Navigator.pop(dialogContext, true)
                          : null,
                      child: Text('确认调整（${count.length}次）'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    ui.dispose();
    if (confirmed != true || !mounted) return;
    await _commitAdjustment(
      move: buildRequests().move,
      swap: buildRequests().swap,
      sub: buildRequests().sub,
    );
  }

  Future<void> _commitAdjustment({
    required TemporaryMoveRequest? move,
    required TemporarySwapRequest? swap,
    required TemporarySubstituteRequest? sub,
  }) async {
    final state = _data!;
    setState(() => _saving = true);
    try {
      final repo = ref.read(schoolRepositoryProvider);
      if (move != null) {
        await repo.commitTemporaryMove(
          termId: widget.termId,
          request: move,
          expectedRevision: state.revision,
        );
      }
      if (swap != null) {
        await repo.commitTemporarySwap(
          termId: widget.termId,
          request: swap,
          expectedRevision: state.revision,
        );
      }
      if (sub != null) {
        await repo.commitTemporarySubstitute(
          termId: widget.termId,
          request: sub,
          expectedRevision: state.revision,
        );
      }
      if (!mounted) return;
      _source = null;
      _kind = null;
      _swapTarget = null;
      _targetDate = null;
      _targetPosition = null;
      _teacherId = null;
      _subjectId = null;
      _reason.clear();
      await _load();
    } on Object catch (error) {
      if (error.toString().contains('已改变')) {
        await _load();
        _source = null;
        _kind = null;
      }
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------- 代课弹窗
}
