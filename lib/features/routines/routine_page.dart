import 'dart:async';
import 'dart:math' as math;

import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/routine_grid.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart' as f;

const _weekdayNames = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
const _weekdayShort = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 范围树「编辑中」学段的绿色高亮（设计稿 02b：初中部（编辑中））。
const _editingStageBackground = Color(0xFFE9F7EF);
const _editingStageForeground = Color(0xFF2BA471);

class RoutinePage extends ConsumerStatefulWidget {
  const RoutinePage({required this.termId, super.key});

  final String termId;

  @override
  ConsumerState<RoutinePage> createState() => _RoutinePageState();
}

class _RoutinePageState extends ConsumerState<RoutinePage> {
  String? _selectedStageId;

  @override
  Widget build(BuildContext context) {
    final stages = ref.watch(stagesProvider(widget.termId));
    return RepaintBoundary(
      key: const ValueKey('routine-page-snapshot'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: stages.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) =>
              Center(child: SelectableText('读取学段失败：$error')),
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Text(
                  '请先在「班级与学段」新增学段。',
                  style: TextStyle(color: AppTheme.muted),
                ),
              );
            }
            final matching = items
                .where((stage) => stage.id == _selectedStageId)
                .toList();
            final selectedStage = matching.isEmpty
                ? items.first
                : matching.first;
            return _RoutineEditor(
              termId: widget.termId,
              stage: selectedStage,
              stages: items,
              onSelectStage: (stageId) =>
                  setState(() => _selectedStageId = stageId),
            );
          },
        ),
      ),
    );
  }
}

/// 免任课范围：全校 / 学段 / 年级 / 班级。
class _FreeSlotScopeSelection {
  const _FreeSlotScopeSelection({required this.scope, required this.scopeId});

  final FreeSlotScope scope;
  final String scopeId;

  String get label => switch (scope) {
    FreeSlotScope.school => '全校',
    FreeSlotScope.stage => '本学段',
    FreeSlotScope.grade => '年级',
    FreeSlotScope.schoolClass => '班级',
  };
}

class _RoutineEditor extends ConsumerStatefulWidget {
  const _RoutineEditor({
    required this.termId,
    required this.stage,
    required this.stages,
    required this.onSelectStage,
  });

  final String termId;
  final SchoolStage stage;
  final List<SchoolStage> stages;
  final ValueChanged<String> onSelectStage;

  @override
  ConsumerState<_RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends ConsumerState<_RoutineEditor> {
  String? _loadedStageId;
  Set<int> _teachingDays = {};
  List<_PeriodDraft> _periods = [];
  Map<String, int> _overrides = {};
  final Map<String, String> _timeInputs = {};
  final Set<String> _collapsedPeriodGroups = {};
  final Map<String, TextEditingController> _commonTimeControllers = {};
  bool _isSaving = false;

  /// 网格折叠行是否展开（设计稿：第 7–10 节 ▸）。
  bool _gridExpanded = false;

  _FreeSlotScopeSelection _scope = const _FreeSlotScopeSelection(
    scope: FreeSlotScope.school,
    scopeId: '',
  );
  final Set<String> _expandedStages = {};
  final Set<String> _expandedGrades = {};

  // —— 草稿快照与撤销（设计稿操作 02d）——
  _DraftSnapshot _snapshot = const _DraftSnapshot();
  final List<_UndoableEdit> _undoStack = [];
  _UndoableEdit? _toastEdit;
  Timer? _toastTimer;

  /// 草稿相对上次加载 / 保存是否有未保存修改。
  bool get _routineDirty => !_snapshot.isSame(_currentSnapshot());

  @override
  void dispose() {
    _toastTimer?.cancel();
    for (final controller in _commonTimeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routine = ref.watch(routineProvider(widget.stage.id));
    return routine.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: SelectableText('读取作息失败：$error')),
      data: (value) {
        if (value == null) return const Center(child: Text('该学段尚未初始化作息。'));
        if (_loadedStageId != widget.stage.id) {
          // 同步加载（学段页签已预热过 routineProvider，切换学段无需闪烁加载态）。
          _load(value);
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final showTimeRail = constraints.maxWidth >= 1020;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 220,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      _ScopeTreeCard(
                        termId: widget.termId,
                        stages: widget.stages,
                        selectedStageId: widget.stage.id,
                        scope: _scope,
                        expandedStages: _expandedStages,
                        expandedGrades: _expandedGrades,
                        onSelectStage: widget.onSelectStage,
                        onSelectScope: (scope) =>
                            setState(() => _scope = scope),
                        onToggleStage: (id) => setState(() {
                          _expandedStages.contains(id)
                              ? _expandedStages.remove(id)
                              : _expandedStages.add(id);
                        }),
                        onToggleGrade: (id) => setState(() {
                          _expandedGrades.contains(id)
                              ? _expandedGrades.remove(id)
                              : _expandedGrades.add(id);
                        }),
                      ),
                      const SizedBox(height: 12),
                      AppSectionPanel(
                        title: '上课天',
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: AppWeekdaySelector(
                          compact: true,
                          fontSize: 13,
                          labels: _weekdayNames,
                          selectedWeekdays: _teachingDays,
                          onChanged: _toggleTeachingDay,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppSectionPanel(
                        title: _periodCountsCardTitle,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var index = 0;
                              index < _periods.length;
                              index++
                            )
                              _PeriodCountRow(
                                period: _periods[index],
                                visual: periodVisualFor(
                                  _periods[index].name,
                                  index,
                                ),
                                onChanged: _setPeriodCount,
                                onEnable: _enablePeriod,
                                onRename: _renamePeriod,
                                onDelete: _deletePeriod,
                              ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: AppGhostButton.icon(
                                onPressed: _addPeriod,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('新增时段'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CommonPeriodsCard(
                        stageId: widget.stage.id,
                        stageName: widget.stage.name,
                        onAdd: _insertCommonPeriod,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppSectionPanel(
                    padding: const EdgeInsets.all(16),
                    expandChild: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StageTabs(
                          stages: widget.stages,
                          selectedStageId: widget.stage.id,
                          onSelectStage: widget.onSelectStage,
                        ),
                        const SizedBox(height: 12),
                        _OverrideSummaryBar(
                          periods: _periods,
                          overrides: _overrides,
                          capacity: _weeklyCapacity(),
                          onAdd: _addOverride,
                          onEdit: _editOverride,
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(child: _buildMatrix()),
                              if (_toastEdit != null)
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  bottom: 10,
                                  child: Center(
                                    child: _UndoToastBar(
                                      key: const ValueKey('routine-undo-toast'),
                                      edit: _toastEdit!,
                                      onUndo: _applyToastUndo,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_routineDirty) ...[
                          const SizedBox(height: 10),
                          _UnsavedChangesBar(
                            key: const ValueKey('routine-unsaved-bar'),
                            isSaving: _isSaving,
                            onRevert: _revertAll,
                            onSave: _save,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (showTimeRail) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 280,
                    child: _LessonTimePanel(
                      periods: _periods,
                      timeInputs: _timeInputs,
                      commonPeriods:
                          ref
                              .watch(commonPeriodsProvider(widget.stage.id))
                              .valueOrNull ??
                          const <CommonPeriod>[],
                      commonTimeControllers: _commonTimeControllers,
                      needsCrossStageTimes: _needsCrossStageTimes(),
                      collapsedGroups: _collapsedPeriodGroups,
                      teachingDays: _teachingDays,
                      overrides: _overrides,
                      onToggleGroup: (periodId) => setState(() {
                        _collapsedPeriodGroups.contains(periodId)
                            ? _collapsedPeriodGroups.remove(periodId)
                            : _collapsedPeriodGroups.add(periodId);
                      }),
                      onTimeChanged: _updateTime,
                      onInsertCommonPeriod: _insertCommonPeriod,
                      onCommonPeriodTimeChanged: _updateCommonPeriodTime,
                      onDeleteCommonPeriod: _deleteCommonPeriod,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // —— 数据加载与保存 ——

  void _load(StageRoutine routine) {
    _loadedStageId = widget.stage.id;
    _teachingDays = {...routine.teachingWeekdays};
    _periods = routine.periodTypes.map(_PeriodDraft.fromDomain).toList();
    _overrides = {
      for (final item in routine.overrides)
        _overrideKey(item.periodTypeId, item.weekday): item.lessonCount,
    };
    _renumberLabels();
    _timeInputs
      ..clear()
      ..addEntries([
        for (final period in routine.periodTypes)
          for (final time in period.lessonTimes) ...[
            MapEntry(
              _timeKey(period.id, time.lessonIndex, true),
              time.startLabel ?? '',
            ),
            MapEntry(
              _timeKey(period.id, time.lessonIndex, false),
              time.endLabel ?? '',
            ),
          ],
      ]);
    _gridExpanded = false;
    _undoStack.clear();
    _toastEdit = null;
    _toastTimer?.cancel();
    _snapshot = _currentSnapshot();
  }

  /// 按设计稿规则重建节次标签：早读→「早读」，晚上→「晚自习 N」，其余→全局连续「第 N 节」。
  void _renumberLabels() {
    for (final label in lessonLabels(_domainPeriods())) {
      final period = _periods.firstWhere((item) => item.id == label.periodId);
      final time = period.times.firstWhere(
        (item) => item.lessonIndex == label.lessonIndex,
      );
      time.label = label.label;
    }
  }

  List<LessonPeriodType> _domainPeriods() => [
    for (final period in _periods)
      LessonPeriodType(
        id: period.id,
        name: period.name,
        defaultLessonCount: period.defaultLessonCount,
        sortOrder: period.sortOrder,
        lessonTimes: [
          for (final time in period.times)
            LessonTime(
              lessonIndex: time.lessonIndex,
              label: time.label,
              startMinute: null,
              endMinute: null,
            ),
        ],
      ),
  ];

  // —— 草稿快照 ——

  _DraftSnapshot _currentSnapshot() => _DraftSnapshot(
    teachingDays: {..._teachingDays},
    overrides: {..._overrides},
    periods: [
      for (final period in _periods)
        _PeriodSnapshot(
          id: period.id,
          name: period.name,
          defaultLessonCount: period.defaultLessonCount,
          sortOrder: period.sortOrder,
          times: [
            for (final time in period.times)
              _TimeSnapshot(lessonIndex: time.lessonIndex, label: time.label),
          ],
        ),
    ],
    timeInputs: {..._timeInputs},
  );

  // —— 撤销提示条（设计稿操作 02d）——

  void _pushUndo(String message, VoidCallback undo) {
    final edit = _UndoableEdit(message: message, undo: undo);
    setState(() => _undoStack.add(edit));
    _showToast(edit);
  }

  void _showToast(_UndoableEdit edit) {
    _toastTimer?.cancel();
    setState(() => _toastEdit = edit);
    _toastTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _toastEdit = null);
    });
  }

  Future<void> _applyToastUndo() async {
    final edit = _toastEdit;
    if (edit == null) return;
    _toastTimer?.cancel();
    setState(() {
      _toastEdit = null;
      _undoStack.remove(edit);
    });
    edit.undo();
  }

  void _revertAll() {
    final loaded = ref.read(routineProvider(widget.stage.id)).valueOrNull;
    if (loaded != null) setState(() => _load(loaded));
  }

  // —— 时段节数 ——

  /// 「每天节数」卡片标题：存在其他学段时标注互不相关（设计稿 02b）。
  String get _periodCountsCardTitle {
    final others = widget.stages
        .where((stage) => stage.id != widget.stage.id)
        .toList();
    if (others.isEmpty) return '每天节数';
    if (others.length == 1) return '每天节数（与${others.first.name}无关）';
    return '每天节数（与其他学段无关）';
  }

  void _toggleTeachingDay(Set<int> weekdays) {
    final previous = {..._teachingDays};
    setState(() => _teachingDays = weekdays);
    final added = weekdays.difference(previous);
    final removed = previous.difference(weekdays);
    final weekday = (added.isNotEmpty ? added : removed).first;
    _pushUndo(
      added.isNotEmpty
          ? '已将 ${_weekdayNames[weekday - 1]} 设为上课天'
          : '已取消 ${_weekdayNames[weekday - 1]} 上课天',
      () => setState(() => _teachingDays = previous),
    );
  }

  void _setPeriodCount(String periodId, int count) {
    final index = _periods.indexWhere((period) => period.id == periodId);
    if (index < 0) return;
    final period = _periods[index];
    final previous = period.defaultLessonCount;
    setState(() {
      period.defaultLessonCount = count.clamp(0, 9);
      _ensureTimes(period);
      _renumberLabels();
    });
    _pushUndo(
      '已将 ${period.name} 设为 $count 节',
      () => setState(() {
        period.defaultLessonCount = previous;
        _ensureTimes(period);
        _renumberLabels();
      }),
    );
  }

  /// 启用未启用的时段（设计稿：早读（未启用）+ 启用）。
  void _enablePeriod(_PeriodDraft period) {
    final previous = period.defaultLessonCount;
    setState(() {
      period.defaultLessonCount = 1;
      _ensureTimes(period);
      _renumberLabels();
    });
    _pushUndo('已启用「${period.name}」', () {
      setState(() {
        period.defaultLessonCount = previous;
        _ensureTimes(period);
        _renumberLabels();
      });
    });
  }

  void _ensureTimes(_PeriodDraft period) {
    final overriddenCount = _overrides.entries
        .where((entry) => entry.key.startsWith('${period.id}_'))
        .map((entry) => entry.value)
        .fold<int>(0, math.max);
    final count = math.max(period.defaultLessonCount, overriddenCount);
    while (period.times.length < count) {
      period.times.add(
        _TimeDraft(lessonIndex: period.times.length + 1, label: ''),
      );
    }
    if (period.times.length > count) {
      period.times.removeRange(count, period.times.length);
    }
  }

  Future<void> _addPeriod() async {
    final result = await showDialog<_NewPeriodResult>(
      context: context,
      builder: (context) => const _NewPeriodDialog(),
    );
    if (result == null) return;
    setState(() {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final period = _PeriodDraft(
        id: id,
        name: result.name,
        defaultLessonCount: result.count,
        sortOrder: _periods.length,
        times: [],
      );
      _periods.add(period);
      _ensureTimes(period);
      _renumberLabels();
    });
  }

  Future<void> _renamePeriod(_PeriodDraft period) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          _TextEntryDialog(title: '修改时段名称', initialValue: period.name),
    );
    if (result == null) return;
    setState(() {
      period.name = result;
      _renumberLabels();
    });
  }

  Future<void> _deletePeriod(_PeriodDraft period) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AppDialog(
            title: Text('删除「${period.name}」？'),
            content: const Text('该时段的默认节数、按天覆盖、免任课与节次时间会一并删除。'),
            actions: [
              AppGhostButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              AppSecondaryButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() {
      _periods.removeWhere((item) => item.id == period.id);
      _overrides.removeWhere((key, value) => key.startsWith('${period.id}_'));
      _renumberLabels();
    });
  }

  void _updateTime(
    _PeriodDraft period,
    int lessonIndex,
    bool isStart,
    String value,
  ) {
    setState(() {
      _timeInputs[_timeKey(period.id, lessonIndex, isStart)] = value.trim();
    });
  }

  int _weeklyCapacity() {
    var total = 0;
    for (final weekday in _teachingDays) {
      for (final period in _periods) {
        total +=
            _overrides[_overrideKey(period.id, weekday)] ??
            period.defaultLessonCount;
      }
    }
    // 减去当前范围可见的免任课格数。
    for (final weekday in _teachingDays) {
      for (final period in _periods) {
        for (
          var lessonIndex = 1;
          lessonIndex <=
              (_overrides[_overrideKey(period.id, weekday)] ??
                  period.defaultLessonCount);
          lessonIndex++
        ) {
          if (_cellInfo(period, weekday, lessonIndex).marker != null) total--;
        }
      }
    }
    return total;
  }

  Future<void> _save() async {
    final periods = <LessonPeriodType>[];
    for (final period in _periods) {
      final times = <LessonTime>[];
      for (final time in period.times) {
        final startText =
            _timeInputs[_timeKey(period.id, time.lessonIndex, true)] ?? '';
        final endText =
            _timeInputs[_timeKey(period.id, time.lessonIndex, false)] ?? '';
        final start = _parseTime(startText);
        final end = _parseTime(endText);
        if ((startText.isEmpty) != (endText.isEmpty) ||
            start == null && startText.isNotEmpty ||
            end == null && endText.isNotEmpty) {
          await _showError(
            '「${period.name} ${time.label}」时间格式不正确，请填写完整的 HH:mm。',
          );
          return;
        }
        if (start != null && end != null && start >= end) {
          await _showError('「${period.name} ${time.label}」开始时间必须早于结束时间。');
          return;
        }
        times.add(
          LessonTime(
            lessonIndex: time.lessonIndex,
            label: time.label,
            startMinute: start,
            endMinute: end,
          ),
        );
      }
      periods.add(
        LessonPeriodType(
          id: period.id,
          name: period.name,
          defaultLessonCount: period.defaultLessonCount,
          sortOrder: _periods.indexOf(period),
          lessonTimes: times,
        ),
      );
    }
    final routine = StageRoutine(
      stageId: widget.stage.id,
      teachingWeekdays: {..._teachingDays},
      periodTypes: periods,
      overrides: [
        for (final entry in _overrides.entries)
          RoutineOverride(
            periodTypeId: entry.key.substring(0, entry.key.lastIndexOf('_')),
            weekday: int.parse(
              entry.key.substring(entry.key.lastIndexOf('_') + 1),
            ),
            lessonCount: entry.value,
          ),
      ],
    );
    setState(() => _isSaving = true);
    try {
      await ref.read(schoolRepositoryProvider).saveRoutine(routine);
      if (!mounted) return;
      setState(() {
        _load(routine);
        _isSaving = false;
      });
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      _showSaved();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      await _showError('保存作息失败：$error');
    }
  }

  Future<void> _showError(String message) => showDialog<void>(
    context: context,
    builder: (context) => AppDialog(
      title: const Text('无法保存'),
      content: SelectableText(message),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  void _showSaved() => f.showFToast(
    context: context,
    title: const Text('作息已保存到本地'),
    duration: const Duration(seconds: 3),
  );

  // —— 按天差异 ——

  Future<void> _addOverride() async {
    if (_periods.isEmpty) return;
    final result = await showDialog<_OverrideEdit>(
      context: context,
      builder: (context) => _OverrideDialog(
        weekdayName:
            _weekdayNames[_teachingDays.isEmpty ? 0 : _teachingDays.first - 1],
        periodName: _periods.first.name,
        defaultCount: _periods.first.defaultLessonCount,
        currentCount: null,
        periods: _periods,
        teachingDays: _teachingDays,
      ),
    );
    if (result == null) return;
    _applyOverride(result);
  }

  Future<void> _editOverride(_PeriodDraft period, int weekday) async {
    final key = _overrideKey(period.id, weekday);
    final result = await showDialog<_OverrideEdit>(
      context: context,
      builder: (context) => _OverrideDialog(
        weekdayName: _weekdayNames[weekday - 1],
        periodName: period.name,
        defaultCount: period.defaultLessonCount,
        currentCount: _overrides[key],
        periods: _periods,
        teachingDays: _teachingDays,
        fixedPeriodId: period.id,
        fixedWeekday: weekday,
      ),
    );
    if (result == null) return;
    _applyOverride(result);
  }

  void _applyOverride(_OverrideEdit result) {
    if (result.periodTypeId == null || result.weekday == null) return;
    final targetKey = _overrideKey(result.periodTypeId!, result.weekday!);
    final previous = _overrides[targetKey];
    final period = _periods.firstWhere(
      (item) => item.id == result.periodTypeId,
    );
    setState(() {
      if (result.lessonCount == null) {
        _overrides.remove(targetKey);
      } else {
        _overrides[targetKey] = result.lessonCount!;
      }
      _ensureTimes(period);
      _renumberLabels();
    });
    final weekdayName = _weekdayNames[result.weekday! - 1];
    _pushUndo(
      result.lessonCount == null
          ? '已恢复 $weekdayName · ${period.name} 默认节数'
          : '已将 $weekdayName · ${period.name} 设为 ${result.lessonCount} 节',
      () => setState(() {
        if (previous == null) {
          _overrides.remove(targetKey);
        } else {
          _overrides[targetKey] = previous;
        }
        _ensureTimes(period);
        _renumberLabels();
      }),
    );
  }

  // —— 免任课 ——

  _CellInfo _cellInfo(_PeriodDraft period, int weekday, int lessonIndex) {
    if (!_teachingDays.contains(weekday)) {
      return const _CellInfo.invalid();
    }
    final override = _overrides[_overrideKey(period.id, weekday)];
    final effective = override ?? period.defaultLessonCount;
    if (lessonIndex > effective) {
      return _CellInfo(
        invalid: true,
        overrideShortfall: override != null,
        marker: null,
      );
    }
    return _CellInfo(
      invalid: false,
      overrideShortfall: false,
      marker: _resolveMarker(period.id, weekday, lessonIndex),
    );
  }

  /// 解析格子当前范围的免任课标记（更具体的范围优先）。
  FreeSlot? _resolveMarker(String periodTypeId, int weekday, int lessonIndex) {
    final slots =
        ref.watch(freeSlotsProvider(widget.stage.id)).valueOrNull ??
        const <FreeSlot>[];
    FreeSlot? best;
    int bestPriority = -1;
    for (final slot in slots) {
      if (slot.periodTypeId != periodTypeId ||
          slot.weekday != weekday ||
          slot.lessonIndex != lessonIndex) {
        continue;
      }
      final priority = _scopePriority(slot);
      if (priority < 0) continue;
      if (priority > bestPriority) {
        best = slot;
        bestPriority = priority;
      }
    }
    return best;
  }

  /// 标记属于当前可见范围的优先级：当前范围 > 学段 > 全校；不在范围内返回 -1。
  int _scopePriority(FreeSlot slot) {
    final isCurrentScope = switch (_scope.scope) {
      FreeSlotScope.school => slot.scope == FreeSlotScope.school,
      FreeSlotScope.stage =>
        slot.scope == FreeSlotScope.stage && slot.scopeId == widget.stage.id,
      FreeSlotScope.grade =>
        slot.scope == FreeSlotScope.grade && slot.scopeId == _scope.scopeId,
      FreeSlotScope.schoolClass =>
        slot.scope == FreeSlotScope.schoolClass &&
            slot.scopeId == _scope.scopeId,
    };
    if (isCurrentScope) return 3;
    if (slot.scope == FreeSlotScope.stage &&
        slot.scopeId == widget.stage.id &&
        _scope.scope != FreeSlotScope.school) {
      return 2;
    }
    if (slot.scope == FreeSlotScope.school) return 1;
    return -1;
  }

  Future<void> _toggleMarker(
    _PeriodDraft period,
    int weekday,
    int lessonIndex,
    String lessonLabel,
  ) async {
    final existing = _resolveMarker(period.id, weekday, lessonIndex);
    final weekdayName = _weekdayNames[weekday - 1];
    if (existing != null) {
      await _deleteMarkers(period, weekday, lessonIndex);
      _pushUndo('已取消 $weekdayName · $lessonLabel 的免任课', () {
        _createMarker(period, weekday, lessonIndex, existing.label);
      });
      return;
    }
    await _createMarker(period, weekday, lessonIndex, FreeSlotLabels.none);
    _pushUndo('已将 $weekdayName · $lessonLabel 设为「${FreeSlotLabels.none}」', () {
      _deleteMarkers(period, weekday, lessonIndex);
    });
  }

  Future<void> _setMarkerLabel(
    _PeriodDraft period,
    int weekday,
    int lessonIndex,
    String lessonLabel,
    String label,
  ) async {
    final existing = _resolveMarker(period.id, weekday, lessonIndex);
    if (existing != null && existing.label == label) return;
    if (existing != null) {
      await _deleteMarkers(period, weekday, lessonIndex);
    }
    await _createMarker(period, weekday, lessonIndex, label);
    final weekdayName = _weekdayNames[weekday - 1];
    _pushUndo('已将 $weekdayName · $lessonLabel 设为「$label」', () {
      if (existing != null) {
        _createMarker(period, weekday, lessonIndex, existing.label);
      } else {
        _deleteMarkers(period, weekday, lessonIndex);
      }
    });
  }

  /// 全校范围标记展开到该学期所有学段（按时段名称匹配）。
  Future<void> _createMarker(
    _PeriodDraft period,
    int weekday,
    int lessonIndex,
    String label,
  ) async {
    final repository = ref.read(schoolRepositoryProvider);
    try {
      if (_scope.scope == FreeSlotScope.school) {
        for (final stage in widget.stages) {
          final routine = await repository.watchRoutine(stage.id).first;
          if (routine == null) continue;
          final target = routine.periodTypes
              .where((item) => item.name == period.name)
              .firstOrNull;
          if (target == null) continue;
          if (lessonIndex > target.lessonTimes.length) continue;
          await repository.saveFreeSlot(
            FreeSlot(
              id: '${stage.id}_free_${target.id}_${weekday}_$lessonIndex',
              scope: FreeSlotScope.school,
              scopeId: widget.termId,
              stageId: stage.id,
              periodTypeId: target.id,
              weekday: weekday,
              lessonIndex: lessonIndex,
              label: label,
            ),
          );
        }
      } else {
        await repository.saveFreeSlot(
          FreeSlot(
            id:
                '${widget.stage.id}_free_${period.id}_${weekday}_$lessonIndex'
                '_${_scope.scope.storageValue}_${_scope.scopeId}',
            scope: _scope.scope,
            scopeId: _scope.scopeId,
            stageId: widget.stage.id,
            periodTypeId: period.id,
            weekday: weekday,
            lessonIndex: lessonIndex,
            label: label,
          ),
        );
      }
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    } on Object catch (error) {
      if (mounted) await _showError('设置免任课失败：$error');
    }
  }

  Future<void> _deleteMarkers(
    _PeriodDraft period,
    int weekday,
    int lessonIndex,
  ) async {
    final repository = ref.read(schoolRepositoryProvider);
    final slots = (await repository.watchFreeSlots(widget.stage.id).first)
        .where(
          (slot) => slot.weekday == weekday && slot.lessonIndex == lessonIndex,
        )
        .toList();
    try {
      if (_scope.scope == FreeSlotScope.school) {
        // 删除所有学段中同时段名称的全校范围标记。
        for (final slot in slots) {
          if (slot.scope != FreeSlotScope.school) continue;
          if (slot.periodTypeId == period.id) {
            await repository.deleteFreeSlot(slot.id);
            continue;
          }
          final otherRoutine = await repository
              .watchRoutine(slot.stageId)
              .first;
          final otherPeriod = otherRoutine?.periodTypes
              .where((item) => item.id == slot.periodTypeId)
              .firstOrNull;
          if (otherPeriod != null && otherPeriod.name == period.name) {
            await repository.deleteFreeSlot(slot.id);
          }
        }
      } else {
        for (final slot in slots) {
          final matches = switch (_scope.scope) {
            FreeSlotScope.stage =>
              slot.scope == FreeSlotScope.stage &&
                  slot.scopeId == widget.stage.id &&
                  slot.periodTypeId == period.id,
            FreeSlotScope.grade =>
              slot.scope == FreeSlotScope.grade &&
                  slot.scopeId == _scope.scopeId &&
                  slot.periodTypeId == period.id,
            FreeSlotScope.schoolClass =>
              slot.scope == FreeSlotScope.schoolClass &&
                  slot.scopeId == _scope.scopeId &&
                  slot.periodTypeId == period.id,
            FreeSlotScope.school => false,
          };
          if (matches) await repository.deleteFreeSlot(slot.id);
        }
      }
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    } on Object catch (error) {
      if (mounted) await _showError('取消免任课失败：$error');
    }
  }

  Future<void> _promptCustomLabel(
    _PeriodDraft period,
    int weekday,
    int lessonIndex,
    String lessonLabel,
  ) async {
    final existing = _resolveMarker(period.id, weekday, lessonIndex);
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          _TextEntryDialog(title: '自定义免任课名称', initialValue: existing?.label),
    );
    if (name != null && name.trim().isNotEmpty) {
      await _setMarkerLabel(
        period,
        weekday,
        lessonIndex,
        lessonLabel,
        name.trim(),
      );
    }
  }

  bool _needsCrossStageTimes() {
    if (widget.stages.length < 2) return false;
    for (final stage in widget.stages) {
      final routine = ref.read(routineProvider(stage.id)).valueOrNull;
      if (routine == null) continue;
      for (final period in routine.periodTypes) {
        for (final time in period.lessonTimes) {
          if (time.startMinute == null || time.endMinute == null) return true;
        }
      }
    }
    return false;
  }

  // —— 公共时段 ——

  Future<void> _insertCommonPeriod({String? afterLessonId}) async {
    final result = await showDialog<_CommonPeriodResult>(
      context: context,
      builder: (context) => _InsertCommonPeriodDialog(
        periods: _periods,
        initialAfterLessonId: afterLessonId,
      ),
    );
    if (result == null) return;
    try {
      await ref
          .read(schoolRepositoryProvider)
          .saveCommonPeriod(
            CommonPeriod(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              stageId: widget.stage.id,
              name: result.name,
              insertAfterLessonId: result.afterLessonId,
              durationMinutes: result.durationMinutes,
              startMinute: null,
              endMinute: null,
            ),
          );
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    } on Object catch (error) {
      if (mounted) await _showError('插入公共时段失败：$error');
    }
  }

  void _updateCommonPeriodTime(
    CommonPeriod period,
    bool isStart,
    String value,
  ) {
    final text = value.trim();
    final minutes = text.isEmpty ? null : _parseTime(text);
    if (text.isNotEmpty && minutes == null) {
      _showError('时间格式不正确，请填写 HH:mm。');
      return;
    }
    final other = isStart ? period.endMinute : period.startMinute;
    if (minutes != null && other != null) {
      if (isStart && minutes >= other) {
        _showError('开始时间必须早于结束时间。');
        return;
      }
      if (!isStart && minutes <= other) {
        _showError('结束时间必须晚于开始时间。');
        return;
      }
    }
    final updated = isStart
        ? period.copyWith(startMinute: minutes)
        : period.copyWith(endMinute: minutes);
    _persistCommonPeriod(updated);
  }

  Future<void> _persistCommonPeriod(CommonPeriod period) async {
    try {
      await ref.read(schoolRepositoryProvider).saveCommonPeriod(period);
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    } on Object catch (error) {
      if (mounted) await _showError('保存公共时段失败：$error');
    }
  }

  Future<void> _deleteCommonPeriod(CommonPeriod period) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AppDialog(
            title: Text('删除公共时段「${period.name}」？'),
            content: const Text('删除后课表与打印布局中将不再显示该时段。'),
            actions: [
              AppGhostButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              AppSecondaryButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(schoolRepositoryProvider).deleteCommonPeriod(period.id);
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    } on Object catch (error) {
      if (mounted) await _showError('删除公共时段失败：$error');
    }
  }

  // —— 免任课网格 ——

  /// 网格列：上课天的最小~最大星期构成连续区间（设计稿 02b：周六列无效）。
  List<int> get _gridDays => routineGridColumns(_teachingDays);

  /// 网格行：前 6 个非晚自习行平铺，其余折叠为「第 X–Y 节」，晚自习行始终平铺。
  List<_GridItem> _gridItems() {
    final periods = _domainPeriods();
    final draftById = {for (final period in _periods) period.id: period};
    final items = <_GridItem>[];
    if (_gridExpanded) {
      final collapsed = buildRoutineRows(periods);
      final foldRow = collapsed.where((row) => row.isFolded).firstOrNull;
      var foldableSeen = 0;
      for (final row in buildRoutineRows(periods, expandFolded: true)) {
        items.add(_GridItem.lesson(row, draftById[row.periodId]!));
        if (row.isEvening) continue;
        foldableSeen++;
        if (foldRow != null && foldableSeen == kRoutineVisibleLessonRows) {
          items.add(_GridItem.collapseBar(foldRow.label));
        }
      }
    } else {
      for (final row in buildRoutineRows(periods)) {
        items.add(_GridItem.lesson(row, draftById[row.periodId]!));
      }
    }
    return items;
  }

  Widget _buildMatrix() => _FreeSlotMatrix(
    key: const ValueKey('routine-matrix'),
    items: _gridItems(),
    days: _gridDays,
    teachingDays: _teachingDays,
    cellInfo: _cellInfo,
    onCellTap: _toggleMarker,
    onSetMarkerLabel: _setMarkerLabel,
    onCustomLabel: _promptCustomLabel,
    onAddCommonPeriod: (period, weekday, lessonIndex) =>
        _insertCommonPeriod(afterLessonId: '${period.id}_$lessonIndex'),
    onExpandFold: () => setState(() => _gridExpanded = true),
    onCollapseFold: () => setState(() => _gridExpanded = false),
  );
}

// —— 小组件 ——

class _ScopeTreeCard extends ConsumerWidget {
  const _ScopeTreeCard({
    required this.termId,
    required this.stages,
    required this.selectedStageId,
    required this.scope,
    required this.expandedStages,
    required this.expandedGrades,
    required this.onSelectStage,
    required this.onSelectScope,
    required this.onToggleStage,
    required this.onToggleGrade,
  });

  final String termId;
  final List<SchoolStage> stages;
  final String selectedStageId;
  final _FreeSlotScopeSelection scope;
  final Set<String> expandedStages;
  final Set<String> expandedGrades;
  final ValueChanged<String> onSelectStage;
  final ValueChanged<_FreeSlotScopeSelection> onSelectScope;
  final ValueChanged<String> onToggleStage;
  final ValueChanged<String> onToggleGrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppSectionPanel(
    title: '免任课范围',
    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
    child: Column(
      children: [
        AppTreeTile(
          isSelected: scope.scope == FreeSlotScope.school,
          leading: const Icon(Icons.domain_outlined, size: 15),
          title: const Text(
            '全校',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          height: 30,
          onTap: () => onSelectScope(
            const _FreeSlotScopeSelection(
              scope: FreeSlotScope.school,
              scopeId: '',
            ),
          ),
        ),
        for (final stage in stages)
          _ScopeStageNode(
            termId: termId,
            stage: stage,
            isEditing: stage.id == selectedStageId,
            isSelected:
                scope.scope == FreeSlotScope.stage && scope.scopeId == stage.id,
            isExpanded: expandedStages.contains(stage.id),
            expandedGrades: expandedGrades,
            scope: scope,
            onSelectStage: onSelectStage,
            onSelectScope: onSelectScope,
            onToggle: () => onToggleStage(stage.id),
            onToggleGrade: onToggleGrade,
          ),
      ],
    ),
  );
}

class _ScopeStageNode extends ConsumerWidget {
  const _ScopeStageNode({
    required this.termId,
    required this.stage,
    required this.isEditing,
    required this.isSelected,
    required this.isExpanded,
    required this.expandedGrades,
    required this.scope,
    required this.onSelectStage,
    required this.onSelectScope,
    required this.onToggle,
    required this.onToggleGrade,
  });

  final String termId;
  final SchoolStage stage;
  final bool isEditing;
  final bool isSelected;
  final bool isExpanded;
  final Set<String> expandedGrades;
  final _FreeSlotScopeSelection scope;
  final ValueChanged<String> onSelectStage;
  final ValueChanged<_FreeSlotScopeSelection> onSelectScope;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleGrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grades =
        ref.watch(gradesProvider(stage.id)).valueOrNull ?? const <GradeGroup>[];
    // 设计稿 02b：编辑中的学段绿色高亮「（编辑中）」，其他学段标注「（独立作息）」。
    final highlight = isEditing
        ? (
            _editingStageBackground,
            _editingStageForeground,
            '${stage.name}（编辑中）',
            FontWeight.w600,
          )
        : (
            AppTheme.selectedBlue,
            AppTheme.blue,
            '${stage.name}（独立作息）',
            FontWeight.w400,
          );
    return Column(
      children: [
        AppTreeTile(
          isSelected: isEditing || isSelected,
          selectedBackground: highlight.$1,
          selectedForeground: isEditing ? highlight.$2 : null,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: AppTheme.muted,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.layers_outlined,
                size: 15,
                color: isEditing ? AppTheme.blue : AppTheme.sidebarMuted,
              ),
            ],
          ),
          title: Text(
            highlight.$3,
            style: TextStyle(
              fontSize: 13,
              color: isEditing ? highlight.$2 : null,
              fontWeight: highlight.$4,
            ),
          ),
          height: 30,
          contentPadding: const EdgeInsets.only(left: 8, right: 8),
          onTap: () {
            onSelectStage(stage.id);
            onSelectScope(
              _FreeSlotScopeSelection(
                scope: FreeSlotScope.stage,
                scopeId: stage.id,
              ),
            );
          },
        ),
        if (isExpanded)
          for (final grade in grades)
            _ScopeGradeNode(
              stage: stage,
              grade: grade,
              isSelected:
                  scope.scope == FreeSlotScope.grade &&
                  scope.scopeId == grade.id,
              isExpanded: expandedGrades.contains(grade.id),
              scope: scope,
              onSelectScope: onSelectScope,
              onToggle: () => onToggleGrade(grade.id),
            ),
      ],
    );
  }
}

class _ScopeGradeNode extends ConsumerWidget {
  const _ScopeGradeNode({
    required this.stage,
    required this.grade,
    required this.isSelected,
    required this.isExpanded,
    required this.scope,
    required this.onSelectScope,
    required this.onToggle,
  });

  final SchoolStage stage;
  final GradeGroup grade;
  final bool isSelected;
  final bool isExpanded;
  final _FreeSlotScopeSelection scope;
  final ValueChanged<_FreeSlotScopeSelection> onSelectScope;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes =
        ref.watch(classesProvider(grade.id)).valueOrNull ??
        const <ClassGroup>[];
    return Column(
      children: [
        AppTreeTile(
          isSelected: isSelected,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 13,
                    color: AppTheme.muted,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.school_outlined, size: 14),
            ],
          ),
          title: Text(grade.name, style: const TextStyle(fontSize: 12)),
          height: 28,
          contentPadding: const EdgeInsets.only(left: 20, right: 8),
          onTap: () => onSelectScope(
            _FreeSlotScopeSelection(
              scope: FreeSlotScope.grade,
              scopeId: grade.id,
            ),
          ),
        ),
        if (isExpanded)
          for (final schoolClass in classes)
            AppTreeTile(
              isSelected:
                  scope.scope == FreeSlotScope.schoolClass &&
                  scope.scopeId == schoolClass.id,
              leading: const Padding(
                padding: EdgeInsets.only(left: 26),
                child: Icon(Icons.class_outlined, size: 13),
              ),
              title: Text(
                schoolClass.name,
                style: const TextStyle(fontSize: 11),
              ),
              height: 26,
              contentPadding: const EdgeInsets.only(left: 8, right: 8),
              onTap: () => onSelectScope(
                _FreeSlotScopeSelection(
                  scope: FreeSlotScope.schoolClass,
                  scopeId: schoolClass.id,
                ),
              ),
            ),
      ],
    );
  }
}

class _StageTabs extends StatelessWidget {
  const _StageTabs({
    required this.stages,
    required this.selectedStageId,
    required this.onSelectStage,
  });

  final List<SchoolStage> stages;
  final String selectedStageId;
  final ValueChanged<String> onSelectStage;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppTheme.tableHeader,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final stage in stages)
            _StageTab(
              stage: stage,
              isSelected: stage.id == selectedStageId,
              onTap: () => onSelectStage(stage.id),
            ),
        ],
      ),
    ),
  );
}

class _StageTab extends ConsumerWidget {
  const _StageTab({
    required this.stage,
    required this.isSelected,
    required this.onTap,
  });

  final SchoolStage stage;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = ref.watch(routineProvider(stage.id)).valueOrNull;
    final total =
        routine?.periodTypes.fold<int>(
          0,
          (sum, period) => sum + period.defaultLessonCount,
        ) ??
        0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${stage.name} · $total 节',
          style: TextStyle(
            color: isSelected ? AppTheme.blue : AppTheme.muted,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _OverrideSummaryBar extends StatelessWidget {
  const _OverrideSummaryBar({
    required this.periods,
    required this.overrides,
    required this.capacity,
    required this.onAdd,
    required this.onEdit,
  });

  final List<_PeriodDraft> periods;
  final Map<String, int> overrides;
  final int capacity;
  final Future<void> Function() onAdd;
  final Future<void> Function(_PeriodDraft, int) onEdit;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, int, int)>[];
    for (final period in periods) {
      for (final entry in overrides.entries) {
        if (!entry.key.startsWith('${period.id}_')) continue;
        final weekday = int.parse(
          entry.key.substring(entry.key.lastIndexOf('_') + 1),
        );
        entries.add((
          '${_weekdayNames[weekday - 1]} ${period.name} '
              '${period.defaultLessonCount}→${entry.value}',
          period.sortOrder,
          weekday,
        ));
      }
    }
    entries.sort(
      (a, b) => a.$2.compareTo(b.$2) == 0
          ? a.$3.compareTo(b.$3)
          : a.$2.compareTo(b.$2),
    );
    return Row(
      children: [
        const Text(
          '按天差异',
          style: TextStyle(color: AppTheme.muted, fontSize: 11),
        ),
        const SizedBox(width: 8),
        if (entries.isEmpty)
          AppGhostButton(
            onPressed: () => onAdd(),
            child: const Text('暂无差异 · 添加', style: TextStyle(fontSize: 11)),
          )
        else
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in entries)
                  InkWell(
                    onTap: () {
                      final period = periods.firstWhere(
                        (item) => item.sortOrder == entry.$2,
                      );
                      onEdit(period, entry.$3);
                    },
                    child: AppBadge(
                      label: entry.$1,
                      foreground: const Color(0xFFE37318),
                      background: const Color(0xFFFFF1E9),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        const Spacer(),
        Text(
          '每周容量 $capacity 格 / 班',
          style: const TextStyle(
            color: AppTheme.blue,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CellInfo {
  const _CellInfo({
    required this.invalid,
    required this.overrideShortfall,
    required this.marker,
  });

  const _CellInfo.invalid()
    : invalid = true,
      overrideShortfall = false,
      marker = null;

  final bool invalid;
  final bool overrideShortfall;
  final FreeSlot? marker;
}

/// 网格行条目：节次行 / 折叠行 / 展开后的收起条。
class _GridItem {
  const _GridItem.lesson(this.row, this.period) : collapseLabel = null;

  const _GridItem.collapseBar(this.collapseLabel) : row = null, period = null;

  final RoutineRow? row;
  final _PeriodDraft? period;
  final String? collapseLabel;

  bool get isCollapseBar => collapseLabel != null;
}

class _FreeSlotMatrix extends StatelessWidget {
  const _FreeSlotMatrix({
    super.key,
    required this.items,
    required this.days,
    required this.teachingDays,
    required this.cellInfo,
    required this.onCellTap,
    required this.onSetMarkerLabel,
    required this.onCustomLabel,
    required this.onAddCommonPeriod,
    required this.onExpandFold,
    required this.onCollapseFold,
  });

  final List<_GridItem> items;
  final List<int> days;
  final Set<int> teachingDays;
  final _CellInfo Function(_PeriodDraft, int, int) cellInfo;
  final Future<void> Function(_PeriodDraft, int, int, String) onCellTap;
  final Future<void> Function(_PeriodDraft, int, int, String, String)
  onSetMarkerLabel;
  final Future<void> Function(_PeriodDraft, int, int, String) onCustomLabel;
  final Future<void> Function(_PeriodDraft, int, int) onAddCommonPeriod;
  final VoidCallback onExpandFold;
  final VoidCallback onCollapseFold;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Center(child: Text('请先在左侧选择上课天。'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 88.0;
        final dayWidth = math.max(
          72.0,
          (constraints.maxWidth - labelWidth) / days.length,
        );
        final totalWidth = labelWidth + dayWidth * days.length;
        // 外层垂直滚动 + 内层水平滚动，避免行数多时溢出。
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(
                  children: [
                    _matrixHeading('节次', width: labelWidth, fontSize: 11),
                    for (final weekday in days)
                      _matrixHeading(
                        teachingDays.contains(weekday)
                            ? _weekdayShort[weekday - 1]
                            : '',
                        width: dayWidth,
                        fontSize: 12,
                      ),
                  ],
                ),
                for (final item in items)
                  _buildItem(item, labelWidth, dayWidth, totalWidth),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItem(
    _GridItem item,
    double labelWidth,
    double dayWidth,
    double totalWidth,
  ) {
    if (item.isCollapseBar) {
      return _FoldBar(
        key: const ValueKey('routine-fold-bar'),
        label: item.collapseLabel!,
        width: totalWidth,
        onTap: onCollapseFold,
      );
    }
    final row = item.row!;
    final period = item.period!;
    final visual = periodVisualFor(row.periodName, period.sortOrder);
    if (row.isFolded) {
      return _FoldRow(
        key: const ValueKey('routine-fold-row'),
        label: '${row.label} ▸',
        labelWidth: labelWidth,
        dayWidth: dayWidth,
        days: days,
        teachingDays: teachingDays,
        visual: visual,
        onTap: onExpandFold,
      );
    }
    return Row(
      children: [
        _matrixLabelCell(
          label: row.label,
          width: labelWidth,
          color: visual.color,
          background: visual.labelTint,
        ),
        for (final weekday in days)
          _MatrixCell(
            key: ValueKey(
              'routine-cell-${period.id}-$weekday-${row.lessonIndex}',
            ),
            width: dayWidth,
            info: cellInfo(period, weekday, row.lessonIndex),
            tint: visual.cellTint,
            periodName: period.name,
            weekdayName: _weekdayNames[weekday - 1],
            onTap: () => onCellTap(period, weekday, row.lessonIndex, row.label),
            onSetMarkerLabel: (label) => onSetMarkerLabel(
              period,
              weekday,
              row.lessonIndex,
              row.label,
              label,
            ),
            onCustomLabel: () =>
                onCustomLabel(period, weekday, row.lessonIndex, row.label),
            onAddCommonPeriod: () =>
                onAddCommonPeriod(period, weekday, row.lessonIndex),
          ),
      ],
    );
  }

  Widget _matrixHeading(
    String label, {
    required double width,
    required double fontSize,
  }) => Container(
    width: width,
    height: 32,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppTheme.tableHeader,
      border: Border(
        right: BorderSide(color: Colors.white),
        bottom: BorderSide(color: Colors.white),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
    ),
  );

  Widget _matrixLabelCell({
    required String label,
    required double width,
    required Color color,
    required Color background,
  }) => Container(
    width: width,
    height: 44,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: background,
      border: const Border(
        right: BorderSide(color: Colors.white),
        bottom: BorderSide(color: Colors.white),
      ),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

/// 折叠行：「第 7–10 节 ▸」，点击展开隐藏的行。
/// 折叠行（设计稿「第 7–10 节 ▸」）：与普通行同构——节次标签格 +
/// 首节所属时段的着色格（非上课天列置灰显示「—」），整行点击展开；
/// 格内不含免任课标记。
class _FoldRow extends StatelessWidget {
  const _FoldRow({
    required this.label,
    required this.labelWidth,
    required this.dayWidth,
    required this.days,
    required this.teachingDays,
    required this.visual,
    required this.onTap,
    super.key,
  });

  final String label;
  final double labelWidth;
  final double dayWidth;
  final List<int> days;
  final Set<int> teachingDays;
  final PeriodVisual visual;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Row(
      children: [
        Container(
          width: labelWidth,
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: visual.labelTint,
            border: const Border(
              right: BorderSide(color: Colors.white),
              bottom: BorderSide(color: Colors.white),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: visual.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final weekday in days)
          Container(
            width: dayWidth,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: teachingDays.contains(weekday)
                  ? visual.cellTint
                  : DisabledCellVisual.cellTint,
              border: const Border(
                right: BorderSide(color: Colors.white),
                bottom: BorderSide(color: Colors.white),
              ),
            ),
            child: teachingDays.contains(weekday)
                ? null
                : const Text(
                    '—',
                    style: TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
          ),
      ],
    ),
  );
}

/// 展开后的收起条：出现在第 6 行之后，点击重新折叠。
class _FoldBar extends StatelessWidget {
  const _FoldBar({
    required this.label,
    required this.width,
    required this.onTap,
    super.key,
  });

  final String label;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const Icon(Icons.expand_less, size: 12, color: AppTheme.muted),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF5E5E5E)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MatrixCell extends StatelessWidget {
  const _MatrixCell({
    super.key,
    required this.width,
    required this.info,
    required this.tint,
    required this.periodName,
    required this.weekdayName,
    required this.onTap,
    required this.onSetMarkerLabel,
    required this.onCustomLabel,
    required this.onAddCommonPeriod,
  });

  final double width;
  final _CellInfo info;
  final Color tint;
  final String periodName;
  final String weekdayName;
  final VoidCallback onTap;
  final ValueChanged<String> onSetMarkerLabel;
  final VoidCallback onCustomLabel;
  final VoidCallback onAddCommonPeriod;

  static const _shortcuts = {
    FreeSlotLabels.none: 'L',
    FreeSlotLabels.selfStudy: 'S',
    FreeSlotLabels.labor: 'V',
    FreeSlotLabels.teachingResearch: 'W',
    FreeSlotLabels.partyLeague: 'X',
  };

  @override
  Widget build(BuildContext context) {
    final background = info.marker != null
        ? FreeSlotVisual.cellTint
        : info.overrideShortfall
        ? FreeSlotVisual.cellTint
        : info.invalid
        ? DisabledCellVisual.cellTint
        : tint;
    final label = info.marker?.label ?? (info.overrideShortfall ? '无课' : null);
    final currentLabel = info.marker?.label;
    final cell = InkWell(
      onTap: onTap,
      child: Tooltip(
        message: info.marker != null
            ? '${info.marker!.label} · $periodName · $weekdayName'
            : info.overrideShortfall
            ? '$weekdayName $periodName 节数已覆盖，点击「按天差异」可调整'
            : info.invalid
            ? '$weekdayName 不上课'
            : '$weekdayName $periodName · 点击标记免任课',
        child: Container(
          width: width,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            border: const Border(
              right: BorderSide(color: Colors.white),
              bottom: BorderSide(color: Colors.white),
            ),
          ),
          child: label == null
              ? info.invalid
                    ? const Text(
                        '—',
                        style: TextStyle(color: AppTheme.muted, fontSize: 11),
                      )
                    : const SizedBox.shrink()
              : Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: FreeSlotVisual.foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
    // FContextMenu 点选后不会自动收起，需经 menuBuilder 取到 controller 手动隐藏。
    return f.FContextMenu(
      menuBuilder: (context, controller, menu) => [
        f.FItemGroup(
          divider: .none,
          children: [
            for (final preset in FreeSlotLabels.presets)
              AppMenuTile(
                item: AppMenuItem(
                  label: preset,
                  shortcut: _shortcuts[preset],
                  selected: currentLabel == preset,
                  onPressed: () {
                    unawaited(controller.hide());
                    onSetMarkerLabel(preset);
                  },
                ),
              ),
          ],
        ),
        f.FItemGroup(
          divider: .none,
          children: [
            AppMenuTile(
              item: AppMenuItem(
                label: '自定义名称…',
                shortcut: 'N',
                onPressed: () {
                  unawaited(controller.hide());
                  onCustomLabel();
                },
              ),
            ),
            AppMenuTile(
              item: AppMenuItem(
                label: '添加公共时段',
                shortcut: 'Z',
                onPressed: () {
                  unawaited(controller.hide());
                  onAddCommonPeriod();
                },
              ),
            ),
          ],
        ),
      ],
      child: cell,
    );
  }
}

class _PeriodCountRow extends StatelessWidget {
  const _PeriodCountRow({
    required this.period,
    required this.visual,
    required this.onChanged,
    required this.onEnable,
    required this.onRename,
    required this.onDelete,
  });

  final _PeriodDraft period;
  final PeriodVisual visual;
  final void Function(String, int) onChanged;
  final ValueChanged<_PeriodDraft> onEnable;
  final ValueChanged<_PeriodDraft> onRename;
  final ValueChanged<_PeriodDraft> onDelete;

  @override
  Widget build(BuildContext context) {
    final isEnabled = period.defaultLessonCount > 0;
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          AppStageDot(color: visual.color, size: 8),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              isEnabled ? period.name : '${period.name}（未启用）',
              style: TextStyle(
                color: isEnabled ? visual.color : AppTheme.muted,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          if (isEnabled)
            AppNumberStepper(
              value: period.defaultLessonCount,
              onChanged: (value) => onChanged(period.id, value),
              min: 0,
              max: 9,
              compact: true,
            )
          else
            InkWell(
              onTap: () => onEnable(period),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(
                  '+ 启用',
                  style: TextStyle(
                    color: AppTheme.blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    // 设计稿 02b：行内不放「⋯」按钮，改名 / 删除走右键菜单。
    // FContextMenu 点选后不会自动收起，需经 menuBuilder 取到 controller 手动隐藏。
    return f.FContextMenu(
      menuBuilder: (context, controller, menu) => [
        f.FItemGroup(
          divider: .none,
          children: [
            AppMenuTile(
              item: AppMenuItem(
                label: '修改名称',
                onPressed: () {
                  unawaited(controller.hide());
                  onRename(period);
                },
              ),
            ),
            AppMenuTile(
              item: AppMenuItem(
                label: '删除时段',
                destructive: true,
                onPressed: () {
                  unawaited(controller.hide());
                  onDelete(period);
                },
              ),
            ),
          ],
        ),
      ],
      child: row,
    );
  }
}

class _CommonPeriodsCard extends ConsumerWidget {
  const _CommonPeriodsCard({
    required this.stageId,
    required this.stageName,
    required this.onAdd,
  });

  final String stageId;
  final String stageName;
  final Future<void> Function({String? afterLessonId}) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods =
        ref.watch(commonPeriodsProvider(stageId)).valueOrNull ??
        const <CommonPeriod>[];
    return AppSectionPanel(
      title: '公共时段（$stageName独立）',
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: AppGhostButton.icon(
              onPressed: () => onAdd(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新增', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          AppOutlineButton(
            onPressed: periods.isEmpty ? null : () => _manage(context, periods),
            child: Text(
              '管理（${periods.length}）',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manage(BuildContext context, List<CommonPeriod> periods) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('公共时段'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final period in periods)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(period.name),
                  subtitle: Text(
                    period.startLabel == null
                        ? '时长 ${period.durationMinutes} 分钟 · 未填起止时间'
                        : '${period.startLabel} – ${period.endLabel}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 撤销提示条（设计稿操作 02d）：白底浮条 + 琥珀提示点 + 描述 + 撤销链接。
class _UndoToastBar extends StatelessWidget {
  const _UndoToastBar({required this.edit, required this.onUndo, super.key});

  final _UndoableEdit edit;
  final Future<void> Function() onUndo;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFDEDEDE)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x24000000),
          offset: Offset(0, 4),
          blurRadius: 16,
          spreadRadius: -2,
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFFE37318),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            edit.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.ink, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: () => unawaited(onUndo()),
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              '撤销',
              style: TextStyle(
                color: AppTheme.blue,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 未保存修改底栏：提示 + 撤销修改 + 保存（顶栏-未保存态在本壳内的落位）。
class _UnsavedChangesBar extends StatelessWidget {
  const _UnsavedChangesBar({
    required this.isSaving,
    required this.onRevert,
    required this.onSave,
    super.key,
  });

  final bool isSaving;
  final VoidCallback onRevert;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFFE37318),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          '有未保存的修改',
          style: TextStyle(color: AppTheme.ink, fontSize: 12),
        ),
        const Spacer(),
        AppGhostButton(
          onPressed: isSaving ? null : onRevert,
          child: const Text('撤销修改'),
        ),
        const SizedBox(width: 8),
        AppPrimaryButton.icon(
          onPressed: isSaving ? null : onSave,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: Text(isSaving ? '保存中' : '保存'),
        ),
      ],
    ),
  );
}

class _LessonTimePanel extends StatelessWidget {
  const _LessonTimePanel({
    required this.periods,
    required this.timeInputs,
    required this.commonPeriods,
    required this.commonTimeControllers,
    required this.needsCrossStageTimes,
    required this.collapsedGroups,
    required this.teachingDays,
    required this.overrides,
    required this.onToggleGroup,
    required this.onTimeChanged,
    required this.onInsertCommonPeriod,
    required this.onCommonPeriodTimeChanged,
    required this.onDeleteCommonPeriod,
  });

  final List<_PeriodDraft> periods;
  final Map<String, String> timeInputs;
  final List<CommonPeriod> commonPeriods;
  final Map<String, TextEditingController> commonTimeControllers;
  final bool needsCrossStageTimes;
  final Set<String> collapsedGroups;
  final Set<int> teachingDays;
  final Map<String, int> overrides;
  final ValueChanged<String> onToggleGroup;
  final void Function(_PeriodDraft, int, bool, String) onTimeChanged;
  final Future<void> Function({String? afterLessonId}) onInsertCommonPeriod;
  final void Function(CommonPeriod, bool, String) onCommonPeriodTimeChanged;
  final Future<void> Function(CommonPeriod) onDeleteCommonPeriod;

  TextEditingController _controller(String key, String initial) {
    final existing = commonTimeControllers[key];
    if (existing != null) return existing;
    final controller = TextEditingController(text: initial);
    commonTimeControllers[key] = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) => AppSectionPanel(
    title: '节次与时间',
    expandChild: true,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (needsCrossStageTimes)
          const AppBadge(
            label: '跨学段必填',
            foreground: Color(0xFFE37318),
            background: Color(0xFFFFF1E9),
            fontSize: 11,
          ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () => onInsertCommonPeriod(),
          child: const Text(
            '+ 插入',
            style: TextStyle(
              color: AppTheme.blue,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
    child: ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (var index = 0; index < periods.length; index++) ...[
          if (collapsedGroups.contains(periods[index].id))
            _PeriodGroupHeaderCollapsed(
              period: periods[index],
              visual: periodVisualFor(periods[index].name, index),
              timeInputs: timeInputs,
              teachingDays: teachingDays,
              overrides: overrides,
              onExpand: () => onToggleGroup(periods[index].id),
            )
          else ...[
            _PeriodGroupHeader(
              period: periods[index],
              visual: periodVisualFor(periods[index].name, index),
              onCollapse: () => onToggleGroup(periods[index].id),
            ),
            for (final time in periods[index].times) ...[
              _LessonTimeRow(
                period: periods[index],
                time: time,
                timeInputs: timeInputs,
                onChanged: onTimeChanged,
              ),
              _InsertCommonPeriodSlot(
                onTap: () => onInsertCommonPeriod(
                  afterLessonId: '${periods[index].id}_${time.lessonIndex}',
                ),
              ),
              for (final common in commonPeriods.where(
                (item) =>
                    item.insertAfterLessonId ==
                    '${periods[index].id}_${time.lessonIndex}',
              ))
                _CommonPeriodRow(
                  period: common,
                  controllerStart: _controller(
                    '${common.id}_start',
                    common.startLabel ?? '',
                  ),
                  controllerEnd: _controller(
                    '${common.id}_end',
                    common.endLabel ?? '',
                  ),
                  onChanged: onCommonPeriodTimeChanged,
                  onDelete: onDeleteCommonPeriod,
                ),
            ],
          ],
          for (final common in commonPeriods.where(
            (item) =>
                item.insertAfterLessonId == null &&
                periods.isNotEmpty &&
                periods.first.id == periods[index].id &&
                index == 0,
          ))
            _CommonPeriodRow(
              period: common,
              controllerStart: _controller(
                '${common.id}_start',
                common.startLabel ?? '',
              ),
              controllerEnd: _controller(
                '${common.id}_end',
                common.endLabel ?? '',
              ),
              onChanged: onCommonPeriodTimeChanged,
              onDelete: onDeleteCommonPeriod,
            ),
        ],
      ],
    ),
  );
}

/// 展开的分组头（18px：色点 + 「上午时段 · 每天 5 节」），点击收起。
class _PeriodGroupHeader extends StatelessWidget {
  const _PeriodGroupHeader({
    required this.period,
    required this.visual,
    required this.onCollapse,
  });

  final _PeriodDraft period;
  final PeriodVisual visual;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onCollapse,
    child: Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        children: [
          AppStageDot(color: visual.color, size: 6),
          const SizedBox(width: 7),
          Text(
            '${period.name}时段 · 每天 ${period.defaultLessonCount} 节',
            style: const TextStyle(color: Color(0xFF5E5E5E), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

/// 折叠的分组头（24px #FAFAFA：「下午 · 5 节 14:00–18:30」+ 展开）。
///
/// 时间未填全时退化为按天节数概要（设计稿界面 02：晚上 · 2 节 周五 5/周日 2）。
class _PeriodGroupHeaderCollapsed extends StatelessWidget {
  const _PeriodGroupHeaderCollapsed({
    required this.period,
    required this.visual,
    required this.timeInputs,
    required this.teachingDays,
    required this.overrides,
    required this.onExpand,
  });

  final _PeriodDraft period;
  final PeriodVisual visual;
  final Map<String, String> timeInputs;
  final Set<int> teachingDays;
  final Map<String, int> overrides;
  final VoidCallback onExpand;

  String? get _timeRangeLabel {
    int? parse(String? value) {
      if (value == null) return null;
      final match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(value.trim());
      if (match == null) return null;
      final hour = int.parse(match.group(1)!);
      if (hour > 23) return null;
      return hour * 60 + int.parse(match.group(2)!);
    }

    final starts = <int>[];
    final ends = <int>[];
    for (final time in period.times) {
      final start = parse(timeInputs['${period.id}_${time.lessonIndex}_start']);
      final end = parse(timeInputs['${period.id}_${time.lessonIndex}_end']);
      if (start != null) starts.add(start);
      if (end != null) ends.add(end);
    }
    if (starts.isEmpty || ends.isEmpty) return null;
    String format(int minutes) =>
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
    final minStart = starts.reduce((a, b) => a < b ? a : b);
    final maxEnd = ends.reduce((a, b) => a > b ? a : b);
    return '${format(minStart)}–${format(maxEnd)}';
  }

  /// 时间未填全时的按天节数概要：「周五 5/周日 2」。
  String? get _perDayCountsLabel {
    final parts = <String>[];
    for (final weekday in teachingDays.toList()..sort()) {
      final count =
          overrides[_overrideKey(period.id, weekday)] ??
          period.defaultLessonCount;
      if (count > 0) parts.add('${_weekdayShort[weekday - 1]} $count');
    }
    if (parts.isEmpty) return null;
    return parts.join('/');
  }

  @override
  Widget build(BuildContext context) {
    final summary = _timeRangeLabel ?? _perDayCountsLabel;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              AppStageDot(color: visual.color, size: 6),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${period.name} · ${period.defaultLessonCount} 节'
                  '${summary == null ? '' : ' $summary'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5E5E5E),
                    fontSize: 12,
                  ),
                ),
              ),
              const Text(
                '展开',
                style: TextStyle(color: AppTheme.blue, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonTimeRow extends StatelessWidget {
  const _LessonTimeRow({
    required this.period,
    required this.time,
    required this.timeInputs,
    required this.onChanged,
  });

  final _PeriodDraft period;
  final _TimeDraft time;
  final Map<String, String> timeInputs;
  final void Function(_PeriodDraft, int, bool, String) onChanged;

  @override
  Widget build(BuildContext context) {
    final visual = periodVisualFor(period.name, period.sortOrder);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: visual.labelTint,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              time.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: visual.color, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 50,
            child: AppTextFormField(
              key: ValueKey('${period.id}_${time.lessonIndex}_start'),
              initialValue:
                  timeInputs['${period.id}_${time.lessonIndex}_start'] ?? '',
              decoration: const InputDecoration(hintText: '08:00'),
              dense: true,
              textAlign: TextAlign.center,
              onChanged: (value) =>
                  onChanged(period, time.lessonIndex, true, value),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              '–',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 50,
            child: AppTextFormField(
              key: ValueKey('${period.id}_${time.lessonIndex}_end'),
              initialValue:
                  timeInputs['${period.id}_${time.lessonIndex}_end'] ?? '',
              decoration: const InputDecoration(hintText: '08:45'),
              dense: true,
              textAlign: TextAlign.center,
              onChanged: (value) =>
                  onChanged(period, time.lessonIndex, false, value),
            ),
          ),
        ],
      ),
    );
  }
}

/// 插入公共时段槽（26px #FAFAFA）。
class _InsertCommonPeriodSlot extends StatelessWidget {
  const _InsertCommonPeriodSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 6),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 11, color: AppTheme.muted),
            SizedBox(width: 4),
            Text(
              '+ 插入公共时段',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CommonPeriodRow extends StatelessWidget {
  const _CommonPeriodRow({
    required this.period,
    required this.controllerStart,
    required this.controllerEnd,
    required this.onChanged,
    required this.onDelete,
  });

  final CommonPeriod period;
  final TextEditingController controllerStart;
  final TextEditingController controllerEnd;
  final void Function(CommonPeriod, bool, String) onChanged;
  final Future<void> Function(CommonPeriod) onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Container(
          width: 64,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            period.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFE37318), fontSize: 11),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 50,
          child: AppTextFormField(
            controller: controllerStart,
            decoration: const InputDecoration(hintText: '09:05'),
            dense: true,
            textAlign: TextAlign.center,
            onChanged: (value) => onChanged(period, true, value),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            '–',
            style: TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
        ),
        SizedBox(
          width: 50,
          child: AppTextFormField(
            controller: controllerEnd,
            decoration: const InputDecoration(hintText: '09:15'),
            dense: true,
            textAlign: TextAlign.center,
            onChanged: (value) => onChanged(period, false, value),
          ),
        ),
        const SizedBox(width: 4),
        const AppBadge(
          label: '公共',
          foreground: Color(0xFFE37318),
          background: Color(0xFFFFF1E9),
          fontSize: 11,
        ),
        const SizedBox(width: 2),
        InkWell(
          onTap: () => onDelete(period),
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: Icon(Icons.close, size: 12, color: AppTheme.muted),
          ),
        ),
      ],
    ),
  );
}

// —— 弹窗 ——

class _OverrideEdit {
  const _OverrideEdit(this.lessonCount, {this.periodTypeId, this.weekday});

  final int? lessonCount;
  final String? periodTypeId;
  final int? weekday;
}

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({
    required this.weekdayName,
    required this.periodName,
    required this.defaultCount,
    required this.currentCount,
    required this.periods,
    required this.teachingDays,
    this.fixedPeriodId,
    this.fixedWeekday,
  });

  final String weekdayName;
  final String periodName;
  final int defaultCount;
  final int? currentCount;
  final List<_PeriodDraft> periods;
  final Set<int> teachingDays;
  final String? fixedPeriodId;
  final int? fixedWeekday;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  late bool _isCustom = widget.currentCount != null;
  late int _count = widget.currentCount ?? widget.defaultCount;
  late String _periodId = widget.fixedPeriodId ?? widget.periods.first.id;
  late int _weekday =
      widget.fixedWeekday ??
      (widget.teachingDays.isEmpty ? 1 : widget.teachingDays.first);

  @override
  Widget build(BuildContext context) {
    final period = widget.periods.firstWhere((item) => item.id == _periodId);
    return AppDialog(
      title: Text('${_weekdayNames[_weekday - 1]} · ${period.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.fixedPeriodId == null)
            AppSelectField<String>(
              items: {for (final item in widget.periods) item.name: item.id},
              value: _periodId,
              label: '时段类型',
              onChanged: (value) =>
                  setState(() => _periodId = value ?? _periodId),
            ),
          if (widget.fixedWeekday == null) ...[
            const SizedBox(height: 12),
            AppSelectField<int>(
              items: {
                for (final day in widget.teachingDays.toList()..sort())
                  _weekdayNames[day - 1]: day,
              },
              value: _weekday,
              label: '星期',
              onChanged: (value) =>
                  setState(() => _weekday = value ?? _weekday),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('为这一天单独设置'),
                    const SizedBox(height: 2),
                    Text(
                      '默认每天 ${period.defaultLessonCount} 节',
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              f.FSwitch(
                value: _isCustom,
                onChange: (value) => setState(() {
                  _isCustom = value;
                  _count = period.defaultLessonCount;
                }),
              ),
            ],
          ),
          if (_isCustom) ...[
            const SizedBox(height: 12),
            AppSelectField<int>(
              items: {
                for (var count = 0; count <= 9; count++) '$count 节': count,
              },
              value: _count,
              label: '当天节数',
              onChanged: (value) => setState(() => _count = value ?? _count),
            ),
          ],
          if (_isCustom && _count == 0)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '覆盖为 0 后，这一天不安排该时段课程。',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        if (widget.currentCount != null)
          AppGhostButton(
            onPressed: () => Navigator.pop(
              context,
              _OverrideEdit(null, periodTypeId: _periodId, weekday: _weekday),
            ),
            child: const Text('恢复默认'),
          ),
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppPrimaryButton(
          onPressed: () => Navigator.pop(
            context,
            _OverrideEdit(
              _isCustom ? _count : null,
              periodTypeId: _periodId,
              weekday: _weekday,
            ),
          ),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _NewPeriodResult {
  const _NewPeriodResult({required this.name, required this.count});

  final String name;
  final int count;
}

class _NewPeriodDialog extends StatefulWidget {
  const _NewPeriodDialog();

  @override
  State<_NewPeriodDialog> createState() => _NewPeriodDialogState();
}

class _NewPeriodDialogState extends State<_NewPeriodDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int _count = 1;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('新增时段类型'),
    content: SizedBox(
      width: 360,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '时段名称',
                hintText: '例如：早读、晚自习',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入名称' : null,
            ),
            const SizedBox(height: 12),
            AppSelectField<int>(
              items: {
                for (var count = 0; count <= 9; count++) '$count 节': count,
              },
              value: _count,
              label: '默认每天节数',
              onChanged: (value) => setState(() => _count = value ?? _count),
            ),
          ],
        ),
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: () => _formKey.currentState!.validate()
            ? Navigator.pop(
                context,
                _NewPeriodResult(
                  name: _nameController.text.trim(),
                  count: _count,
                ),
              )
            : null,
        child: const Text('添加'),
      ),
    ],
  );
}

class _CommonPeriodResult {
  const _CommonPeriodResult({
    required this.name,
    required this.durationMinutes,
    required this.afterLessonId,
  });

  final String name;
  final int durationMinutes;
  final String? afterLessonId;
}

class _InsertCommonPeriodDialog extends StatefulWidget {
  const _InsertCommonPeriodDialog({
    required this.periods,
    this.initialAfterLessonId,
  });

  final List<_PeriodDraft> periods;
  final String? initialAfterLessonId;

  @override
  State<_InsertCommonPeriodDialog> createState() =>
      _InsertCommonPeriodDialogState();
}

class _InsertCommonPeriodDialogState extends State<_InsertCommonPeriodDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _durationController = TextEditingController(text: '10');
  String? _afterLessonId;

  @override
  void initState() {
    super.initState();
    _afterLessonId = widget.initialAfterLessonId;
    if (_afterLessonId == null && widget.periods.isNotEmpty) {
      final first = widget.periods.first;
      if (first.times.isNotEmpty) {
        _afterLessonId = '${first.id}_${first.times.first.lessonIndex}';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('插入公共时段'),
    content: SizedBox(
      width: 300,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：眼保健操',
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入名称' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppTextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '时长',
                      suffixText: '分钟',
                    ),
                    validator: (value) {
                      final minutes = int.tryParse(value ?? '');
                      return minutes == null || minutes < 1 || minutes > 120
                          ? '1–120'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSelectField<String?>(
              items: {
                '第 1 节之前': null,
                for (final period in widget.periods)
                  for (final time in period.times)
                    '${time.label} 之后': '${period.id}_${time.lessonIndex}',
              },
              value: _afterLessonId,
              label: '位置',
              onChanged: (value) => setState(() => _afterLessonId = value),
            ),
            const SizedBox(height: 12),
            const Text(
              '公共时段不排正课；插入后该学段所有上课日的课表与打印布局同步显示。',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _CommonPeriodResult(
              name: _nameController.text.trim(),
              durationMinutes: int.parse(_durationController.text),
              afterLessonId: _afterLessonId,
            ),
          );
        },
        child: const Text('插入'),
      ),
    ],
  );
}

class _TextEntryDialog extends StatefulWidget {
  const _TextEntryDialog({required this.title, this.initialValue});

  final String title;
  final String? initialValue;

  @override
  State<_TextEntryDialog> createState() => _TextEntryDialogState();
}

class _TextEntryDialogState extends State<_TextEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: AppTextFormField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? '名称不能为空' : null,
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: () => _formKey.currentState!.validate()
            ? Navigator.pop(context, _controller.text.trim())
            : null,
        child: const Text('保存'),
      ),
    ],
  );
}

// —— 草稿模型与工具 ——

class _PeriodDraft {
  _PeriodDraft({
    required this.id,
    required this.name,
    required this.defaultLessonCount,
    required this.sortOrder,
    required this.times,
  });

  factory _PeriodDraft.fromDomain(LessonPeriodType value) => _PeriodDraft(
    id: value.id,
    name: value.name,
    defaultLessonCount: value.defaultLessonCount,
    sortOrder: value.sortOrder,
    times: value.lessonTimes.map(_TimeDraft.fromDomain).toList(),
  );

  final String id;
  String name;
  int defaultLessonCount;
  int sortOrder;
  final List<_TimeDraft> times;
}

class _TimeDraft {
  _TimeDraft({required this.lessonIndex, required this.label});

  factory _TimeDraft.fromDomain(LessonTime value) =>
      _TimeDraft(lessonIndex: value.lessonIndex, label: value.label);

  final int lessonIndex;
  String label;
}

/// 可撤销的一次编辑（设计稿操作 02d 撤销提示条）。
class _UndoableEdit {
  const _UndoableEdit({required this.message, required this.undo});

  final String message;
  final VoidCallback undo;
}

/// 草稿快照：用于判定是否有未保存修改。
class _DraftSnapshot {
  const _DraftSnapshot({
    this.teachingDays = const {},
    this.overrides = const {},
    this.periods = const [],
    this.timeInputs = const {},
  });

  final Set<int> teachingDays;
  final Map<String, int> overrides;
  final List<_PeriodSnapshot> periods;
  final Map<String, String> timeInputs;

  bool isSame(_DraftSnapshot other) {
    if (teachingDays.length != other.teachingDays.length) return false;
    if (!teachingDays.containsAll(other.teachingDays)) return false;
    if (overrides.length != other.overrides.length) return false;
    for (final entry in overrides.entries) {
      if (other.overrides[entry.key] != entry.value) return false;
    }
    if (periods.length != other.periods.length) return false;
    for (var index = 0; index < periods.length; index++) {
      if (!periods[index].isSame(other.periods[index])) return false;
    }
    if (timeInputs.length != other.timeInputs.length) return false;
    for (final entry in timeInputs.entries) {
      if (other.timeInputs[entry.key] != entry.value) return false;
    }
    return true;
  }
}

class _PeriodSnapshot {
  const _PeriodSnapshot({
    required this.id,
    required this.name,
    required this.defaultLessonCount,
    required this.sortOrder,
    required this.times,
  });

  final String id;
  final String name;
  final int defaultLessonCount;
  final int sortOrder;
  final List<_TimeSnapshot> times;

  bool isSame(_PeriodSnapshot other) {
    if (id != other.id ||
        name != other.name ||
        defaultLessonCount != other.defaultLessonCount ||
        sortOrder != other.sortOrder ||
        times.length != other.times.length) {
      return false;
    }
    for (var index = 0; index < times.length; index++) {
      if (!times[index].isSame(other.times[index])) return false;
    }
    return true;
  }
}

class _TimeSnapshot {
  const _TimeSnapshot({required this.lessonIndex, required this.label});

  final int lessonIndex;
  final String label;

  bool isSame(_TimeSnapshot other) =>
      lessonIndex == other.lessonIndex && label == other.label;
}

String _overrideKey(String periodId, int weekday) => '${periodId}_$weekday';

String _timeKey(String periodId, int lessonIndex, bool isStart) =>
    '${periodId}_${lessonIndex}_${isStart ? 'start' : 'end'}';

int? _parseTime(String value) {
  final match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  if (hour > 23) return null;
  return hour * 60 + int.parse(match.group(2)!);
}
