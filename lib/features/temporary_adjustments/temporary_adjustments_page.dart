import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/theme/subject_colors.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/core/widgets/app_page_layout.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/temporary_preview_worker.dart';
import 'package:class_set/features/temporary_adjustments/temporary_adjustment_export.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

part 'temporary_adjustments_page_support.dart';
part 'temporary_adjustments_page_common.dart';
part 'temporary_adjustments_page_timetable.dart';
part 'temporary_adjustments_page_adjustment.dart';
part 'temporary_adjustments_page_preview.dart';
part 'temporary_adjustments_page_records.dart';

/// 按实际日期查看课表并预览临时调整。
class TemporaryAdjustmentsPage extends ConsumerStatefulWidget {
  const TemporaryAdjustmentsPage({required this.termId, super.key});
  final String termId;

  @override
  ConsumerState<TemporaryAdjustmentsPage> createState() =>
      _TemporaryAdjustmentsPageState();
}

class _TemporaryAdjustmentsPageState
    extends ConsumerState<TemporaryAdjustmentsPage> {
  TemporaryTimetableState? _data;
  _TemporaryTimetableIndexes? _timetableIndexes;
  String? _error;
  String? _classId;
  bool _teacherView = false;
  String? _viewTeacherId;
  int? _week;
  bool _records = false;
  bool _showCancelled = false;
  String? _recordType;
  String? _recordStatus;
  String? _recordClass;
  String? _recordTeacher;
  DateTimeRange? _recordDates;
  ActualLesson? _source;
  ActualLesson? _swapTarget;
  DateTime? _targetDate;
  SchedulePosition? _targetPosition;
  String? _teacherId;
  String? _subjectId;
  String? _kind;
  final _reason = TextEditingController();
  bool _saving = false;
  final _candidateCache = <String, ActualChangePreview>{};
  String? _candidateBatchKey;
  String? _candidateBatchError;
  bool _candidateBatchComplete = false;
  String? _candidateBatchInFlightKey;
  _QueuedCandidateBatch? _queuedCandidateBatch;
  bool _candidateBatchRunning = false;
  int _candidateBatchGeneration = 0;
  Isolate? _candidateBatchIsolate;
  ReceivePort? _candidateBatchResultPort;
  ReceivePort? _candidateBatchErrorPort;
  Completer<Map<String, ActualChangePreview>?>? _candidateBatchCompleter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancelCandidateBatchWorker();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = await ref
          .read(schoolRepositoryProvider)
          .loadTemporaryTimetable(widget.termId);
      if (!mounted) return;
      final start = state.snapshot.term.firstTeachingWeekStart;
      final currentWeek = state.snapshot.term.teachingWeekOf(DateTime.now());
      setState(() {
        _data = state;
        if (state.reconciliationPending) {
          _source = null;
          _kind = null;
        }
        _candidateCache.clear();
        _candidateBatchKey = null;
        _candidateBatchError = null;
        _candidateBatchComplete = false;
        _queuedCandidateBatch = null;
        _error = null;
        _classId = state.snapshot.classes.any((c) => c.id == _classId)
            ? _classId
            : state.snapshot.classes.firstOrNull?.id;
        _viewTeacherId =
            state.snapshot.teachers.any((t) => t.id == _viewTeacherId)
            ? _viewTeacherId
            : state.snapshot.teachers.firstOrNull?.id;
        if (!_records) {
          _recordClass = _teacherView ? null : _classId;
          _recordTeacher = _teacherView ? _viewTeacherId : null;
        }
        _week ??= currentWeek == null || start == null ? 0 : currentWeek - 1;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '加载调代课失败：$error');
    }
  }

  void _showTemporaryError(String message) => setState(() => _error = message);

  Future<void> _commitSupervisionReplacement(
    TemporaryTimetableState state,
    TemporarySupervisionSubstituteRequest request,
  ) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(schoolRepositoryProvider)
          .commitTemporarySupervisionSubstitute(
            termId: widget.termId,
            request: request,
            expectedRevision: state.revision,
          );
      await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '替班失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  _TemporaryTimetableIndexes _indexesFor(TemporaryTimetableState state) {
    final current = _timetableIndexes;
    if (current != null && identical(current.state, state)) return current;
    return _timetableIndexes = _TemporaryTimetableIndexes(state);
  }

  void _changeWeek(int week) {
    if (_week == week) return;
    setState(() {
      _week = week;
      _invalidateCandidateBatch();
    });
  }

  void _invalidateCandidateBatch() {
    _cancelCandidateBatchWorker();
    _candidateBatchKey = null;
    _candidateBatchError = null;
    _candidateBatchComplete = false;
    _candidateCache.clear();
    _queuedCandidateBatch = null;
  }

  void _cancelCandidateBatchWorker() {
    _candidateBatchGeneration++;
    _candidateBatchIsolate?.kill(priority: Isolate.immediate);
    _candidateBatchIsolate = null;
    _candidateBatchResultPort?.close();
    _candidateBatchResultPort = null;
    _candidateBatchErrorPort?.close();
    _candidateBatchErrorPort = null;
    final completer = _candidateBatchCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
    _candidateBatchCompleter = null;
    _candidateBatchInFlightKey = null;
    _candidateBatchRunning = false;
  }

  // ---------------------------------------------------------------- 基础查询

  @override
  Widget build(BuildContext context) {
    final state = _data;
    if (_error != null && state == null) return Center(child: Text(_error!));
    if (state == null) return const Center(child: CircularProgressIndicator());
    if (state.snapshot.term.firstTeachingWeekStart == null) {
      return const Center(child: Text('请先在学期与日历中设置第 1 教学周起始日期。'));
    }
    if (state.snapshot.classes.isEmpty) {
      return const Center(child: Text('请先添加班级。'));
    }
    final start = state.snapshot.term.firstTeachingWeekStart!.add(
      Duration(days: (_week ?? 0) * 7),
    );
    return Padding(
      padding: AppPageLayout.insetsOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _records ? _recordsToolbar(state) : _scheduleToolbar(state, start),
          if (!_records && _source != null) ...[
            const SizedBox(height: 10),
            _flowBar(),
          ],
          if (state.reconciliationPending) ...[
            const SizedBox(height: 10),
            _hintBox(
              Text(
                state.snapshot.supervisionCalendar == null
                    ? '课表待协调，完成协调后才能进行临时调整。'
                    : '课表待协调。可取消有冲突的已有调整，完成协调后可新增调整。',
              ),
              tone: 'amber',
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: _records
                ? _recordList(state)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 1040) {
                        if (_source == null) {
                          // 未选中源课次时没有调整面板，课表直接撑满可用高度。
                          // 旧逻辑固定 420 会让下方留白、课表内部却出现垂直滚动条。
                          return _timetablePanel(
                            _teacherView
                                ? _teacherGrid(state, start)
                                : _grid(state, start),
                            expandChild: true,
                          );
                        }
                        // 有调整面板时仍需一个页面级纵向滚动源：
                        // 面板按内容自然撑高（不再内部滚动抢手势），
                        // 课表给固定高度，在其内部横向 / 纵向滚动。
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _panel(state, scrollBody: false),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 420,
                                child: _timetablePanel(
                                  _teacherView
                                      ? _teacherGrid(state, start)
                                      : _grid(state, start),
                                  expandChild: true,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _timetablePanel(
                              _teacherView
                                  ? _teacherGrid(state, start)
                                  : _grid(state, start),
                              expandChild: true,
                            ),
                          ),
                          if (_source != null) ...[
                            const SizedBox(width: 16),
                            SizedBox(width: 336, child: _panel(state)),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _timetablePanel(Widget grid, {required bool expandChild}) =>
      AppSectionPanel(
        key: const ValueKey('temporary-adjustments-grid-panel'),
        title: '本周课表',
        expandTitle: false,
        trailing: Expanded(child: Center(child: _gridFootNote())),
        padding: const EdgeInsets.all(12),
        expandChild: expandChild,
        child: grid,
      );
}
