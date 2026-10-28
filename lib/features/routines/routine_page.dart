import 'dart:async';
import 'dart:math' as math;

import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/navigation/draft_navigation_guard.dart';
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
const _builtInPeriodDefinitions = <(String, String, int, List<String>)>[
  ('早上', 'early', 0, ['早上', '早读']),
  ('上午', '0', 4, ['上午', '上午时段']),
  ('下午', '1', 4, ['下午', '下午时段']),
  ('晚上', '2', 2, ['晚上', '晚自习']),
];
const _timeSeparatorWidth = 16.0;
const _timeRowTrailingWidth = 22.0;
const _timeRowFixedWidth = 44.0;
const _routineStackedLayoutBreakpoint = AppTheme.twoColumnLayoutBreakpoint;
const _routineThreeColumnLayoutBreakpoint = 1120.0;

({double label, double field}) _timeRowWidths(double availableWidth) {
  final flexibleWidth = math
      .max(0.0, availableWidth - _timeRowFixedWidth)
      .toDouble();
  return (label: flexibleWidth * 0.36, field: flexibleWidth * 0.32);
}

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < AppTheme.compactPageBreakpoint;
          final horizontalPadding = AppTheme.pagePaddingForWidth(
            constraints.maxWidth,
          );
          return Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              compact ? 16 : 20,
              horizontalPadding,
              16,
            ),
            child: stages.when(
              loading: () => _StaticRoutinePage(
                child: const Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => _StaticRoutinePage(
                child: Center(child: SelectableText('读取学段失败：$error')),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return _StaticRoutinePage(
                    child: Center(
                      child: Text(
                        '请先在「班级与学段」新增学段。',
                        style: TextStyle(color: context.appColors.muted),
                      ),
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
          );
        },
      ),
    );
  }
}

class _RoutinePageHeading extends StatelessWidget {
  const _RoutinePageHeading({this.actions = const []});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '作息设置',
              style: TextStyle(
                color: context.appColors.ink,
                fontSize: 25,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            SizedBox(height: 5),
            Text(
              '按学段设置上课日、时段节数、免任课范围和节次时间。',
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      if (actions.isNotEmpty) ...[
        const SizedBox(width: 16),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        ),
      ],
    ],
  );
}

class _StaticRoutinePage extends StatelessWidget {
  const _StaticRoutinePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _RoutinePageHeading(),
      const SizedBox(height: 20),
      Expanded(child: child),
    ],
  );
}

/// 免任课范围：全校 / 学段 / 年级 / 班级。
class _FreeSlotScopeSelection {
  const _FreeSlotScopeSelection({
    required this.scope,
    required this.scopeId,
    this.parentGradeId,
  });

  final FreeSlotScope scope;
  final String scopeId;
  final String? parentGradeId;

  String get label => switch (scope) {
    FreeSlotScope.school => '全校',
    FreeSlotScope.stage => '本学段',
    FreeSlotScope.grade => '年级',
    FreeSlotScope.schoolClass => '班级',
  };
}

/// 范围树选中回调：scope 所属的 [stageId] 一并回传，供调用方在跨学段选中时先切换学段。
typedef _ScopeSelectCallback = void Function(
  String stageId,
  _FreeSlotScopeSelection selection,
);

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
  late final DraftNavigationGuard _navigationGuard;
  String? _loadedStageId;
  Set<int> _teachingDays = {};
  List<_PeriodDraft> _periods = [];
  final Map<String, String> _timeInputs = {};
  final Set<String> _collapsedPeriodGroups = {};
  final Map<String, FreeSlot?> _freeSlotBaseline = {};
  final Map<String, FreeSlot?> _freeSlotDraft = {};
  // Legacy per-day overrides are represented as editable slots in the UI.
  // They are an initial projection, not changes made by the user.
  final Map<String, FreeSlot?> _initialOverrideSlots = {};
  final Map<String, CommonPeriod?> _commonPeriodBaseline = {};
  final Map<String, CommonPeriod?> _commonPeriodDraft = {};
  final Map<String, _DraftSnapshot> _routineBaselineByStage = {};
  final Map<String, _DraftSnapshot> _routineDraftByStage = {};
  final Map<String, bool> _routineNeedsNormalizationByStage = {};
  final Map<String, List<RoutineOverride>> _routineOverridesByStage = {};
  bool _isSaving = false;
  Future<bool>? _saveInFlight;
  bool _isHistoryBusy = false;
  bool _needsNormalization = false;
  int _draftRevision = 0;

  _FreeSlotScopeSelection _scope = const _FreeSlotScopeSelection(
    scope: FreeSlotScope.stage,
    scopeId: '',
  );

  /// 在范围内点击了其他学段下的年级/班级时暂存选中项，待学段切换完成后恢复。
  _FreeSlotScopeSelection? _pendingScope;
  final Set<String> _expandedStages = {};
  final Set<String> _expandedGrades = {};

  // —— 草稿快照与撤销（设计稿操作 02d）——
  final List<_UndoableEdit> _undoStack = [];
  final List<_UndoableEdit> _redoStack = [];

  /// 当前页面是否存在尚未通过保存按钮确认的修改。
  bool get _hasUnsavedChanges {
    if (!_sameNullableMap(
          _freeSlotDraft,
          _initialOverrideSlots,
          _sameFreeSlot,
        ) ||
        _commonPeriodDraft.isNotEmpty) {
      return true;
    }
    for (final entry in _routineDraftByStage.entries) {
      final baseline = _routineBaselineByStage[entry.key];
      if (baseline == null || !baseline.isSame(entry.value)) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _navigationGuard = ref.read(draftNavigationGuardProvider);
    _registerDraftGuard();
  }

  @override
  void didUpdateWidget(covariant _RoutineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.termId != widget.termId) _registerDraftGuard();
  }

  void _registerDraftGuard() => _navigationGuard.register(
    owner: this,
    pageKey: 'routines:${widget.termId}',
    hasChanges: () => _hasUnsavedChanges,
    isSaving: () => _saveInFlight != null,
    save: _save,
  );

  @override
  void dispose() {
    _navigationGuard.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routine = ref.watch(routineProvider(widget.stage.id));
    return routine.when(
      loading: () => const _StaticRoutinePage(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _StaticRoutinePage(
        child: Center(child: SelectableText('读取作息失败：$error')),
      ),
      data: (value) {
        if (value == null) {
          return const _StaticRoutinePage(
            child: Center(child: Text('该学段尚未初始化作息。')),
          );
        }
        if (_loadedStageId != widget.stage.id) {
          // 同步加载（学段页签已预热过 routineProvider，切换学段无需闪烁加载态）。
          _load(value);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RoutinePageHeading(actions: _buildHeaderActions()),
            const SizedBox(height: 20),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < _routineStackedLayoutBreakpoint) {
                    return _buildStackedLayout();
                  }

                  if (constraints.maxWidth <
                      _routineThreeColumnLayoutBreakpoint) {
                    return _buildTwoColumnLayout(constraints.maxWidth);
                  }

                  return _buildThreeColumnLayout(constraints.maxWidth);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStackedLayout() => SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSettingsContent(),
        const SizedBox(height: 16),
        _buildMatrixPanel(compact: true),
        const SizedBox(height: 16),
        _buildLessonTimePanel(scrollable: false),
      ],
    ),
  );

  Widget _buildTwoColumnLayout(double maxWidth) {
    final settingsWidth = maxWidth >= 960 ? 280.0 : 248.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: settingsWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSettingsContent(),
                const SizedBox(height: 16),
                _buildLessonTimePanel(scrollable: false),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: _buildMatrixPanel())],
          ),
        ),
      ],
    );
  }

  Widget _buildThreeColumnLayout(double maxWidth) {
    final settingsWidth = maxWidth >= 1520 ? 248.0 : 232.0;
    final timeWidth = maxWidth >= 1520 ? 304.0 : 288.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: settingsWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildSettingsContent(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: _buildMatrixPanel())],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(width: timeWidth, child: _buildLessonTimePanel()),
      ],
    );
  }

  List<Widget> _buildHeaderActions() => [
    Tooltip(
      message: _undoStack.isEmpty ? '撤销' : '撤销：${_undoStack.last.message}',
      child: IconButton(
        onPressed: _undoStack.isEmpty || _isHistoryBusy
            ? null
            : () => unawaited(_undo()),
        icon: const Icon(Icons.undo_rounded),
      ),
    ),
    Tooltip(
      message: _redoStack.isEmpty ? '重做' : '重做：${_redoStack.last.message}',
      child: IconButton(
        onPressed: _redoStack.isEmpty || _isHistoryBusy
            ? null
            : () => unawaited(_redo()),
        icon: const Icon(Icons.redo_rounded),
      ),
    ),
    const SizedBox(width: 4),
    Tooltip(
      message: _isSaving ? '保存中' : '保存作息设置',
      child: AppPrimaryButton(
        onPressed: _hasUnsavedChanges && !_isSaving ? _save : null,
        child: Text(_isSaving ? '保存中' : '保存'),
      ),
    ),
  ];

  /// 范围树节点点击：若所选年级/班级不属于当前编辑学段，先切换到对应学段再恢复选中项。
  void _selectScope(String stageId, _FreeSlotScopeSelection selection) {
    if (stageId == widget.stage.id) {
      setState(() => _scope = selection);
      return;
    }
    if (_isHistoryBusy) return;
    setState(() {
      _pendingScope = selection;
      _expandedStages.add(stageId);
    });
    widget.onSelectStage(stageId);
  }

  Widget _buildSettingsContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ScopeTreeCard(
        termId: widget.termId,
        stages: widget.stages,
        selectedStageId: widget.stage.id,
        scope: _scope,
        expandedStages: _expandedStages,
        expandedGrades: _expandedGrades,
        onSelectScope: _selectScope,
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
        title: '每天节数',
        useShadow: true,
        headerPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < _periods.length; index++)
              _PeriodCountRow(
                period: _periods[index],
                visual: periodVisualFor(context, _periods[index].name, index),
                onChanged: _setPeriodCount,
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppSectionPanel(
        title: '上课日',
        useShadow: true,
        headerPadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
        child: AppWeekdaySelector(
          compact: true,
          fontSize: 13,
          labels: _weekdayNames,
          selectedWeekdays: _teachingDays,
          onChanged: _toggleTeachingDay,
        ),
      ),
    ],
  );

  Widget _buildMatrixPanel({bool compact = false}) {
    final persistedCommonPeriods =
        ref.watch(commonPeriodsProvider(widget.stage.id)).valueOrNull ??
        const <CommonPeriod>[];
    final commonPeriods = _effectiveCommonPeriods(persistedCommonPeriods);
    return AppSectionPanel(
      useShadow: true,
      // 右侧留白 = 该内边距 + 表格滚动条槽宽，与左侧 16 保持一致。
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        compact ? 16 : 16 - _verticalScrollbarGutterWidth,
        16,
      ),
      expandChild: !compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // 与表格内容右边界对齐（表格右侧让出滚动条槽）。
            padding: EdgeInsets.only(
              right: compact ? 0 : _verticalScrollbarGutterWidth,
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _StageTabs(
                      stages: widget.stages,
                      selectedStageId: widget.stage.id,
                      onSelectStage: (id) {
                        if (!_isHistoryBusy) widget.onSelectStage(id);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_weeklyCapacity()} 格 / 班',
                  style: TextStyle(
                    color: context.appColors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (compact)
            _buildMatrix(
              commonPeriods,
              scrollVertically: false,
              footer: _AllSchoolFreeSlotsSummary(
                stages: widget.stages,
                draftChanges: _freeSlotDraft,
                trailingInset: compact ? 20 : 0,
                onDelete: _deleteFreeSlotEntry,
              ),
            )
          else
            Expanded(
              child: _buildMatrix(
                commonPeriods,
                footer: _AllSchoolFreeSlotsSummary(
                  stages: widget.stages,
                  draftChanges: _freeSlotDraft,
                  trailingInset: compact ? 20 : 0,
                  onDelete: _deleteFreeSlotEntry,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLessonTimePanel({bool scrollable = true}) => _LessonTimePanel(
    scrollable: scrollable,
    periods: _periods,
    timeInputs: _timeInputs,
    revision: _draftRevision,
    commonPeriods: _effectiveCommonPeriods(
      ref.watch(commonPeriodsProvider(widget.stage.id)).valueOrNull ??
          const <CommonPeriod>[],
    ),
    needsCrossStageTimes: _needsCrossStageTimes(),
    collapsedGroups: _collapsedPeriodGroups,
    onToggleGroup: (periodId) => setState(() {
      _collapsedPeriodGroups.contains(periodId)
          ? _collapsedPeriodGroups.remove(periodId)
          : _collapsedPeriodGroups.add(periodId);
    }),
    onTimeChanged: _updateTime,
    onInsertCommonPeriod: _insertCommonPeriod,
    onCommonPeriodTimeChanged: (period, isStart, value) =>
        unawaited(_updateCommonPeriodTime(period, isStart, value)),
    onRenameCommonPeriod: _renameCommonPeriod,
    onDeleteCommonPeriod: _deleteCommonPeriod,
  );

  // —— 数据加载与保存 ——

  void _load(StageRoutine routine) {
    final previousStageId = _loadedStageId;
    if (previousStageId != null) {
      _routineDraftByStage[previousStageId] = _currentRoutineSnapshot();
      _routineNeedsNormalizationByStage[previousStageId] = _needsNormalization;
    }

    final stageId = widget.stage.id;
    _loadedStageId = stageId;
    final existingDraft = _routineDraftByStage[stageId];
    if (existingDraft != null) {
      _applyRoutineSnapshot(existingDraft);
      _needsNormalization = _routineNeedsNormalizationByStage[stageId] ?? false;
    } else {
      _teachingDays = {...routine.teachingWeekdays};
      _needsNormalization = _requiresFixedPeriods(routine);
      _periods = _fixedPeriodDrafts(routine);
      final remainingOverrides = <RoutineOverride>[];
      for (final override in routine.overrides) {
        final period = _periods
            .where((item) => item.id == override.periodTypeId)
            .firstOrNull;
        if (period == null ||
            override.lessonCount > period.defaultLessonCount) {
          remainingOverrides.add(override);
          continue;
        }
        for (
          var index = override.lessonCount + 1;
          index <= period.defaultLessonCount;
          index++
        ) {
          final id =
              '${stageId}_no_class_${period.id}_${override.weekday}_$index';
          final slot = FreeSlot(
            id: id,
            scope: FreeSlotScope.stage,
            scopeId: stageId,
            stageId: stageId,
            periodTypeId: period.id,
            weekday: override.weekday,
            lessonIndex: index,
            label: FreeSlotLabels.noClass,
          );
          _rememberFreeSlotBaseline(id, null);
          _stageFreeSlot(id, slot);
          _initialOverrideSlots[id] = slot;
        }
      }
      _routineOverridesByStage[stageId] = remainingOverrides;
      for (final period in _periods) {
        _ensureTimes(period);
      }
      _renumberLabels();
      _timeInputs
        ..clear()
        ..addEntries([
          for (final period in routine.periodTypes.where(
            (item) => _periods.any((draft) => draft.id == item.id),
          ))
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
      final initialSnapshot = _currentRoutineSnapshot();
      _routineBaselineByStage[stageId] = initialSnapshot;
      _routineDraftByStage[stageId] = initialSnapshot;
      _routineNeedsNormalizationByStage[stageId] = _needsNormalization;
    }

    // 跨学段点击年级/班级时保留待恢复的选中项，其余情况回到学段级范围。
    final pending = _pendingScope;
    _pendingScope = null;
    _scope =
        pending ??
        _FreeSlotScopeSelection(scope: FreeSlotScope.stage, scopeId: stageId);
    _draftRevision++;
    _syncCurrentRoutineDraft();
  }

  bool _requiresFixedPeriods(StageRoutine routine) {
    if (routine.overrides.isNotEmpty ||
        routine.periodTypes.length != _builtInPeriodDefinitions.length) {
      return true;
    }
    final orderedPeriods = [...routine.periodTypes]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (var index = 0; index < orderedPeriods.length; index++) {
      final period = orderedPeriods[index];
      if (period.name != _builtInPeriodDefinitions[index].$1 ||
          period.sortOrder != index ||
          period.lessonTimes.length != period.defaultLessonCount) {
        return true;
      }
    }
    return false;
  }

  List<_PeriodDraft> _fixedPeriodDrafts(StageRoutine routine) {
    final result = <_PeriodDraft>[];
    for (var index = 0; index < _builtInPeriodDefinitions.length; index++) {
      final (name, key, defaultCount, aliases) =
          _builtInPeriodDefinitions[index];
      LessonPeriodType? source;
      for (final alias in aliases) {
        for (final period in routine.periodTypes) {
          if (period.name == alias) {
            source = period;
            break;
          }
        }
        if (source != null) break;
      }
      result.add(
        source == null
              ? _PeriodDraft(
                  id: '${routine.stageId}_period_$key',
                  name: name,
                  defaultLessonCount: routine.periodTypes.isEmpty
                      ? defaultCount
                      : 0,
                  sortOrder: index,
                  times: [],
                )
              : _PeriodDraft.fromDomain(source)
          ..name = name
          ..sortOrder = index,
      );
    }
    return result;
  }

  /// 按时段重建节次标签：早上→「早 N」，晚上→「晚 N」，其余→全局连续「第 N 节」。
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

  _DraftSnapshot _currentRoutineSnapshot() => _DraftSnapshot(
    teachingDays: {..._teachingDays},
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

  _DraftSnapshot _currentSnapshot() {
    final routine = _currentRoutineSnapshot();
    return _DraftSnapshot(
      teachingDays: routine.teachingDays,
      periods: routine.periods,
      timeInputs: routine.timeInputs,
      freeSlotDraft: {..._freeSlotDraft},
      commonPeriodDraft: {..._commonPeriodDraft},
    );
  }

  void _applyDraftSnapshot(_DraftSnapshot snapshot) {
    _applyRoutineSnapshot(snapshot);
    _freeSlotDraft
      ..clear()
      ..addAll(snapshot.freeSlotDraft);
    _commonPeriodDraft
      ..clear()
      ..addAll(snapshot.commonPeriodDraft);
  }

  void _applyRoutineSnapshot(_DraftSnapshot snapshot) {
    _draftRevision++;
    _teachingDays = {...snapshot.teachingDays};
    _periods = [
      for (final period in snapshot.periods)
        _PeriodDraft(
          id: period.id,
          name: period.name,
          defaultLessonCount: period.defaultLessonCount,
          sortOrder: period.sortOrder,
          times: [
            for (final time in period.times)
              _TimeDraft(lessonIndex: time.lessonIndex, label: time.label),
          ],
        ),
    ];
    _timeInputs
      ..clear()
      ..addAll(snapshot.timeInputs);
    _syncCurrentRoutineDraft();
  }

  void _syncCurrentRoutineDraft() {
    final stageId = _loadedStageId;
    if (stageId == null) return;
    _routineDraftByStage[stageId] = _currentRoutineSnapshot();
    _routineNeedsNormalizationByStage[stageId] = _needsNormalization;
  }

  // —— 页面历史：撤销/重做并恢复操作时选中的范围 ——

  void _pushUndo(
    String message, {
    required FutureOr<void> Function() undo,
    required FutureOr<void> Function() redo,
    String? coalesceKey,
  }) {
    final stageId = _loadedStageId ?? widget.stage.id;
    final previous = _undoStack.isEmpty ? null : _undoStack.last;
    final samePosition =
        previous != null &&
        previous.stageId == stageId &&
        previous.scope.scope == _scope.scope &&
        previous.scope.scopeId == _scope.scopeId &&
        previous.expandedStages.length == _expandedStages.length &&
        previous.expandedStages.containsAll(_expandedStages) &&
        previous.expandedGrades.length == _expandedGrades.length &&
        previous.expandedGrades.containsAll(_expandedGrades);
    if (coalesceKey != null &&
        previous != null &&
        samePosition &&
        previous.coalesceKey == coalesceKey) {
      setState(() {
        previous
          ..message = message
          ..redo = redo;
        _redoStack.clear();
      });
      return;
    }
    final edit = _UndoableEdit(
      message: message,
      undo: undo,
      redo: redo,
      stageId: stageId,
      scope: _scope,
      expandedStages: {..._expandedStages},
      expandedGrades: {..._expandedGrades},
      coalesceKey: coalesceKey,
    );
    setState(() {
      _undoStack.add(edit);
      _redoStack.clear();
      if (_undoStack.length > 100) _undoStack.removeAt(0);
    });
  }

  void _pushSnapshotUndo(
    String message,
    _DraftSnapshot before,
    _DraftSnapshot after, {
    String? coalesceKey,
  }) => _pushUndo(
    message,
    undo: () => setState(() => _applyDraftSnapshot(before)),
    redo: () => setState(() => _applyDraftSnapshot(after)),
    coalesceKey: coalesceKey,
  );

  Future<void> _undo() => _applyHistory(undo: true);

  Future<void> _redo() => _applyHistory(undo: false);

  Future<void> _applyHistory({required bool undo}) async {
    if (_isHistoryBusy) return;
    final source = undo ? _undoStack : _redoStack;
    if (source.isEmpty) return;
    final edit = source.last;
    setState(() => _isHistoryBusy = true);
    try {
      await _selectHistoryStage(edit.stageId);
      if (!mounted) return;
      if (_loadedStageId != edit.stageId) {
        throw StateError('该学段的作息配置不存在。');
      }
      setState(() {
        _scope = edit.scope;
        _expandedStages
          ..clear()
          ..addAll(edit.expandedStages);
        _expandedGrades
          ..clear()
          ..addAll(edit.expandedGrades);
      });
      await (undo ? edit.undo : edit.redo)();
      if (!mounted) return;
      setState(() {
        source.removeLast();
        (undo ? _redoStack : _undoStack).add(edit);
        _isHistoryBusy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _isHistoryBusy = false);
      await _showError('无法${undo ? '撤销' : '重做'}这项修改：$error');
    }
  }

  Future<void> _selectHistoryStage(String stageId) async {
    if (_loadedStageId == stageId && widget.stage.id == stageId) return;

    final routine = await ref.read(routineProvider(stageId).future);
    if (!mounted || routine == null) return;
    if (widget.stage.id != stageId) widget.onSelectStage(stageId);

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _loadedStageId == stageId) return;
    setState(() => _load(routine));
  }

  // —— 时段节数 ——

  void _toggleTeachingDay(Set<int> weekdays) {
    final previous = {..._teachingDays};
    final next = {...weekdays};
    final before = _currentSnapshot();
    setState(() => _teachingDays = next);
    _syncCurrentRoutineDraft();
    final added = next.difference(previous);
    final removed = previous.difference(next);
    final weekday = (added.isNotEmpty ? added : removed).first;
    _pushSnapshotUndo(
      added.isNotEmpty
          ? '已将 ${_weekdayNames[weekday - 1]} 设为上课天'
          : '已取消 ${_weekdayNames[weekday - 1]} 上课天',
      before,
      _currentSnapshot(),
    );
  }

  void _setPeriodCount(String periodId, int count) {
    final index = _periods.indexWhere((period) => period.id == periodId);
    if (index < 0) return;
    final period = _periods[index];
    final before = _currentSnapshot();
    setState(() {
      period.defaultLessonCount = count.clamp(0, 9);
      _ensureTimes(period);
      _renumberLabels();
    });
    _syncCurrentRoutineDraft();
    _pushSnapshotUndo(
      '已将 ${period.name} 设为 $count 节',
      before,
      _currentSnapshot(),
    );
  }

  void _ensureTimes(_PeriodDraft period) {
    final count = period.defaultLessonCount;
    while (period.times.length < count) {
      period.times.add(
        _TimeDraft(lessonIndex: period.times.length + 1, label: ''),
      );
    }
    if (period.times.length > count) {
      period.times.removeRange(count, period.times.length);
    }
  }

  void _updateTime(
    _PeriodDraft period,
    int lessonIndex,
    bool isStart,
    String value,
  ) {
    final key = _timeKey(period.id, lessonIndex, isStart);
    final nextValue = value.trim();
    final previousValue = _timeInputs[key] ?? '';
    if (previousValue == nextValue) return;
    final before = _currentSnapshot();
    setState(() => _timeInputs[key] = nextValue);
    _syncCurrentRoutineDraft();
    final after = _currentSnapshot();
    _pushSnapshotUndo(
      '调整${period.times.firstWhere((time) => time.lessonIndex == lessonIndex).label}'
      '${isStart ? '开始' : '结束'}时间',
      before,
      after,
      coalesceKey: key,
    );
  }

  int _weeklyCapacity() {
    var total = 0;
    // 减去当前范围可见的免任课格数。
    for (final weekday in _teachingDays) {
      for (final period in _periods) {
        for (
          var lessonIndex = 1;
          lessonIndex <= period.defaultLessonCount;
          lessonIndex++
        ) {
          final info = _cellInfo(period, weekday, lessonIndex);
          if (!info.invalid && info.marker == null) total++;
        }
      }
    }
    return total;
  }

  Future<bool> _save() =>
      _saveInFlight ??= _performSave().whenComplete(() => _saveInFlight = null);

  Future<bool> _performSave() async {
    final freeSlotDraft = Map<String, FreeSlot?>.of(_freeSlotDraft);
    final commonPeriodDraft = Map<String, CommonPeriod?>.of(_commonPeriodDraft);
    final routineSnapshots = <String, _DraftSnapshot>{};
    for (final entry in _routineDraftByStage.entries) {
      final baseline = _routineBaselineByStage[entry.key];
      if (_routineNeedsNormalizationByStage[entry.key] == true ||
          baseline == null ||
          !baseline.isSame(entry.value)) {
        routineSnapshots[entry.key] = entry.value;
      }
    }

    final routines = <StageRoutine>[];
    for (final entry in routineSnapshots.entries) {
      final snapshot = entry.value;
      final periods = <LessonPeriodType>[];
      for (final period in snapshot.periods) {
        final times = <LessonTime>[];
        for (final time in period.times) {
          final startText =
              snapshot.timeInputs[_timeKey(
                period.id,
                time.lessonIndex,
                true,
              )] ??
              '';
          final endText =
              snapshot.timeInputs[_timeKey(
                period.id,
                time.lessonIndex,
                false,
              )] ??
              '';
          final start = _parseTime(startText);
          final end = _parseTime(endText);
          if ((startText.isEmpty) != (endText.isEmpty) ||
              start == null && startText.isNotEmpty ||
              end == null && endText.isNotEmpty) {
            await _showError(
              '「${period.name} ${time.label}」时间格式不正确，请填写完整的 HH:mm。',
            );
            return false;
          }
          if (start != null && end != null && start >= end) {
            await _showError('「${period.name} ${time.label}」开始时间必须早于结束时间。');
            return false;
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
            sortOrder: period.sortOrder,
            lessonTimes: times,
          ),
        );
      }
      routines.add(
        StageRoutine(
          stageId: entry.key,
          teachingWeekdays: {...snapshot.teachingDays},
          periodTypes: periods,
          overrides: _routineOverridesByStage[entry.key] ?? const [],
        ),
      );
    }
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(schoolRepositoryProvider);
      for (final routine in routines) {
        await repository.saveRoutine(routine);
      }
      for (final entry in freeSlotDraft.entries) {
        final slot = entry.value;
        if (slot == null) {
          await repository.deleteFreeSlot(entry.key);
        } else {
          await repository.saveFreeSlot(slot);
        }
      }
      for (final entry in commonPeriodDraft.entries) {
        final period = entry.value;
        if (period == null) {
          await repository.deleteCommonPeriod(entry.key);
        } else {
          await repository.saveCommonPeriod(period);
        }
      }
      if (!mounted) return false;
      setState(() {
        for (final entry in freeSlotDraft.entries) {
          _freeSlotBaseline[entry.key] = entry.value;
          if (_freeSlotDraft.containsKey(entry.key) &&
              _sameFreeSlot(_freeSlotDraft[entry.key], entry.value)) {
            _freeSlotDraft.remove(entry.key);
          }
        }
        for (final entry in commonPeriodDraft.entries) {
          _commonPeriodBaseline[entry.key] = entry.value;
          if (_commonPeriodDraft.containsKey(entry.key) &&
              _sameCommonPeriod(_commonPeriodDraft[entry.key], entry.value)) {
            _commonPeriodDraft.remove(entry.key);
          }
        }
        for (final entry in routineSnapshots.entries) {
          _routineBaselineByStage[entry.key] = entry.value;
          _routineNeedsNormalizationByStage[entry.key] = false;
        }
        _initialOverrideSlots.removeWhere(
          (_, slot) =>
              slot != null && routineSnapshots.containsKey(slot.stageId),
        );
        _needsNormalization =
            _routineNeedsNormalizationByStage[_loadedStageId] ?? false;
        _isSaving = false;
        _undoStack.clear();
        _redoStack.clear();
      });
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      _showSaved();
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      setState(() => _isSaving = false);
      await _showError('保存作息失败：$error');
      return false;
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

  // —— 免任课 ——

  _CellInfo _cellInfo(_PeriodDraft period, int weekday, int lessonIndex) {
    if (!_teachingDays.contains(weekday)) {
      return const _CellInfo.invalid();
    }
    final overrides = _routineOverridesByStage[widget.stage.id] ?? const [];
    final matching = overrides.where(
      (item) => item.periodTypeId == period.id && item.weekday == weekday,
    );
    final count = matching.isEmpty
        ? period.defaultLessonCount
        : matching.first.lessonCount;
    if (lessonIndex > math.min(period.defaultLessonCount, count)) {
      return const _CellInfo.invalid();
    }
    return _CellInfo(
      invalid: false,
      marker: _resolveMarker(period.id, weekday, lessonIndex),
    );
  }

  /// 解析格子当前范围的免任课标记（更具体的范围优先）。
  FreeSlot? _resolveMarker(String periodTypeId, int weekday, int lessonIndex) {
    final persistedSlots =
        ref.watch(freeSlotsProvider(widget.stage.id)).valueOrNull ??
        const <FreeSlot>[];
    final slots = _effectiveFreeSlots(widget.stage.id, persistedSlots);
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

  /// 标记继承顺序：当前范围 > 年级 > 学段 > 全校；不在范围内返回 -1。
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
    if (isCurrentScope) return 4;
    if (_scope.scope == FreeSlotScope.schoolClass &&
        slot.scope == FreeSlotScope.grade &&
        slot.scopeId == _scope.parentGradeId) {
      return 3;
    }
    if (_scope.scope != FreeSlotScope.school &&
        slot.scope == FreeSlotScope.stage &&
        slot.scopeId == widget.stage.id) {
      return 2;
    }
    if (_scope.scope != FreeSlotScope.school &&
        slot.scope == FreeSlotScope.school) {
      return 1;
    }
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
    final before = _currentSnapshot();
    if (existing != null) {
      await _deleteMarkers(period, weekday, lessonIndex);
      _pushSnapshotUndo(
        '已取消 $weekdayName · $lessonLabel 的免任课',
        before,
        _currentSnapshot(),
      );
      return;
    }
    await _createMarker(period, weekday, lessonIndex, FreeSlotLabels.none);
    _pushSnapshotUndo(
      '已将 $weekdayName · $lessonLabel 设为「${FreeSlotLabels.none}」',
      before,
      _currentSnapshot(),
    );
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
    final before = _currentSnapshot();
    if (existing != null) {
      await _deleteMarkers(period, weekday, lessonIndex);
    }
    await _createMarker(period, weekday, lessonIndex, label);
    final weekdayName = _weekdayNames[weekday - 1];
    _pushSnapshotUndo(
      '已将 $weekdayName · $lessonLabel 设为「$label」',
      before,
      _currentSnapshot(),
    );
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
      final desiredSlots = <FreeSlot>[];
      if (_scope.scope == FreeSlotScope.school) {
        for (final stage in widget.stages) {
          final routine = await repository.watchRoutine(stage.id).first;
          if (routine == null) continue;
          final target = routine.periodTypes
              .where((item) => item.name == period.name)
              .firstOrNull;
          if (target == null) continue;
          if (lessonIndex > target.lessonTimes.length) continue;
          desiredSlots.add(
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
        desiredSlots.add(
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

      final persistedByStage = <String, List<FreeSlot>>{};
      for (final slot in desiredSlots) {
        if (!persistedByStage.containsKey(slot.stageId)) {
          persistedByStage[slot.stageId] = await repository
              .watchFreeSlots(slot.stageId)
              .first;
        }
        final previous = persistedByStage[slot.stageId]!
            .where((item) => item.id == slot.id)
            .firstOrNull;
        _rememberFreeSlotBaseline(slot.id, previous);
      }
      if (!mounted) return;
      setState(() {
        for (final slot in desiredSlots) {
          _stageFreeSlot(slot.id, slot);
        }
      });
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
    try {
      final stageIds = _scope.scope == FreeSlotScope.school
          ? widget.stages.map((stage) => stage.id)
          : [widget.stage.id];
      final matching = <FreeSlot>[];
      final persistedById = <String, FreeSlot>{};
      final periodNameByStage = <String, Map<String, String>>{};
      for (final stageId in stageIds) {
        final persisted = await repository.watchFreeSlots(stageId).first;
        persistedById.addEntries(
          persisted.map((slot) => MapEntry(slot.id, slot)),
        );
        final slots = _effectiveFreeSlots(stageId, persisted).where(
          (slot) => slot.weekday == weekday && slot.lessonIndex == lessonIndex,
        );
        if (_scope.scope == FreeSlotScope.school) {
          final routine = await repository.watchRoutine(stageId).first;
          periodNameByStage[stageId] = {
            for (final item
                in routine?.periodTypes ?? const <LessonPeriodType>[])
              item.id: item.name,
          };
        }
        for (final slot in slots) {
          final bool matches;
          if (_scope.scope == FreeSlotScope.school) {
            matches =
                slot.scope == FreeSlotScope.school &&
                periodNameByStage[stageId]?[slot.periodTypeId] == period.name;
          } else {
            matches =
                slot.scope == _scope.scope &&
                slot.scopeId == _scope.scopeId &&
                slot.periodTypeId == period.id;
          }
          if (matches) matching.add(slot);
        }
      }

      if (!mounted || matching.isEmpty) return;
      setState(() {
        for (final slot in matching) {
          _rememberFreeSlotBaseline(slot.id, persistedById[slot.id]);
          _stageFreeSlot(slot.id, null);
        }
      });
    } on Object catch (error) {
      if (mounted) await _showError('取消免任课失败：$error');
    }
  }

  List<FreeSlot> _effectiveFreeSlots(String stageId, List<FreeSlot> persisted) {
    final slotsById = {for (final slot in persisted) slot.id: slot};
    for (final entry in _freeSlotDraft.entries) {
      final slot = entry.value;
      if (slot == null || slot.stageId != stageId) {
        slotsById.remove(entry.key);
      } else {
        slotsById[entry.key] = slot;
      }
    }
    return slotsById.values.toList(growable: false);
  }

  void _rememberFreeSlotBaseline(String id, FreeSlot? persisted) {
    if (!_freeSlotBaseline.containsKey(id)) {
      _freeSlotBaseline[id] = persisted;
    }
  }

  void _stageFreeSlot(String id, FreeSlot? value) {
    if (_sameFreeSlot(_freeSlotBaseline[id], value)) {
      _freeSlotDraft.remove(id);
    } else {
      _freeSlotDraft[id] = value;
    }
  }

  void _deleteFreeSlotEntry(FreeSlot slot) {
    if (_isSaving || _isHistoryBusy) return;
    final before = _currentSnapshot();
    _rememberFreeSlotBaseline(slot.id, slot);
    setState(() => _stageFreeSlot(slot.id, null));
    final after = _currentSnapshot();
    if (!before.isSame(after)) {
      _pushSnapshotUndo('删除免任课「${slot.label}」', before, after);
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
    final before = _currentSnapshot();
    final period = CommonPeriod(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      stageId: widget.stage.id,
      name: result.name,
      insertAfterLessonId: result.afterLessonId,
      durationMinutes: result.durationMinutes,
      startMinute: null,
      endMinute: null,
    );
    _commonPeriodBaseline[period.id] = null;
    setState(() => _stageCommonPeriod(period.id, period));
    _pushSnapshotUndo('新增公共时段「${period.name}」', before, _currentSnapshot());
  }

  Future<void> _updateCommonPeriodTime(
    CommonPeriod period,
    bool isStart,
    String value,
  ) async {
    final text = value.trim();
    final minutes = text.isEmpty ? null : _parseTime(text);
    if (text.isNotEmpty && minutes == null) {
      await _showError('时间格式不正确，请填写 HH:mm。');
      return;
    }
    final other = isStart ? period.endMinute : period.startMinute;
    if (minutes != null && other != null) {
      if (isStart && minutes >= other) {
        await _showError('开始时间必须早于结束时间。');
        return;
      }
      if (!isStart && minutes <= other) {
        await _showError('结束时间必须晚于开始时间。');
        return;
      }
    }
    final before = _currentSnapshot();
    try {
      await _rememberCommonPeriodBaseline(period.id);
      final updated = CommonPeriod(
        id: period.id,
        stageId: period.stageId,
        name: period.name,
        insertAfterLessonId: period.insertAfterLessonId,
        durationMinutes: period.durationMinutes,
        startMinute: isStart ? minutes : period.startMinute,
        endMinute: isStart ? period.endMinute : minutes,
      );
      setState(() => _stageCommonPeriod(period.id, updated));
      _pushSnapshotUndo(
        '调整公共时段「${period.name}」${isStart ? '开始' : '结束'}时间',
        before,
        _currentSnapshot(),
        coalesceKey: 'common-${period.id}-${isStart ? 'start' : 'end'}',
      );
    } on Object catch (error) {
      if (mounted) await _showError('修改公共时段失败：$error');
    }
  }

  Future<void> _renameCommonPeriod(CommonPeriod period) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          _TextEntryDialog(title: '编辑公共时段名称', initialValue: period.name),
    );
    if (name == null || name == period.name) return;

    final before = _currentSnapshot();
    try {
      await _rememberCommonPeriodBaseline(period.id);
      setState(() {
        _stageCommonPeriod(period.id, period.copyWith(name: name));
      });
      _pushSnapshotUndo('重命名公共时段「${period.name}」', before, _currentSnapshot());
    } on Object catch (error) {
      if (mounted) await _showError('修改公共时段名称失败：$error');
    }
  }

  List<CommonPeriod> _effectiveCommonPeriods(List<CommonPeriod> persisted) {
    final periodsById = {for (final period in persisted) period.id: period};
    for (final entry in _commonPeriodDraft.entries) {
      final period = entry.value;
      if (period == null) {
        periodsById.remove(entry.key);
      } else if (period.stageId == widget.stage.id) {
        periodsById[entry.key] = period;
      }
    }
    return periodsById.values.toList(growable: false);
  }

  Future<void> _rememberCommonPeriodBaseline(String id) async {
    if (_commonPeriodBaseline.containsKey(id)) return;
    final period =
        (await ref
                .read(schoolRepositoryProvider)
                .watchCommonPeriods(widget.stage.id)
                .first)
            .where((item) => item.id == id)
            .firstOrNull;
    _commonPeriodBaseline[id] = period;
  }

  void _stageCommonPeriod(String id, CommonPeriod? value) {
    if (_sameCommonPeriod(_commonPeriodBaseline[id], value)) {
      _commonPeriodDraft.remove(id);
    } else {
      _commonPeriodDraft[id] = value;
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
    final before = _currentSnapshot();
    try {
      await _rememberCommonPeriodBaseline(period.id);
      setState(() => _stageCommonPeriod(period.id, null));
      _pushSnapshotUndo('删除公共时段「${period.name}」', before, _currentSnapshot());
    } on Object catch (error) {
      if (mounted) await _showError('暂存删除公共时段失败：$error');
    }
  }

  // —— 免任课网格 ——

  /// 网格只展示已选为上课日的列。
  List<int> get _gridDays => _teachingDays.toList()..sort();

  /// 网格始终展示全部课节。
  List<_GridItem> _gridItems(List<CommonPeriod> commonPeriods) {
    final periods = _domainPeriods();
    final draftById = {for (final period in _periods) period.id: period};
    final items = <_GridItem>[];
    final rows = buildRoutineRows(periods, expandFolded: true);
    final insertedCommonPeriodIds = <String>{};
    for (final commonPeriod in commonPeriods.where(
      (item) => item.insertAfterLessonId == null,
    )) {
      items.add(_GridItem.common(commonPeriod));
      insertedCommonPeriodIds.add(commonPeriod.id);
    }
    for (final row in rows) {
      items.add(_GridItem.lesson(row, draftById[row.periodId]!));
      final lessonId = '${row.periodId}_${row.lessonIndex}';
      for (final commonPeriod in commonPeriods.where(
        (item) => item.insertAfterLessonId == lessonId,
      )) {
        items.add(_GridItem.common(commonPeriod));
        insertedCommonPeriodIds.add(commonPeriod.id);
      }
    }
    // 锚点课节已被删除的公共时段保留在表格末尾，避免无法找到。
    items.addAll(
      commonPeriods
          .where((item) => !insertedCommonPeriodIds.contains(item.id))
          .map(_GridItem.common),
    );
    return items;
  }

  Widget _buildMatrix(
    List<CommonPeriod> commonPeriods, {
    bool scrollVertically = true,
    Widget? footer,
  }) => _FreeSlotMatrix(
    key: const ValueKey('routine-matrix'),
    items: _gridItems(commonPeriods),
    days: _gridDays,
    teachingDays: _teachingDays,
    scrollVertically: scrollVertically,
    footer: footer,
    cellInfo: _cellInfo,
    onCellTap: _toggleMarker,
    onSetMarkerLabel: _setMarkerLabel,
    onCustomLabel: _promptCustomLabel,
    onAddCommonPeriod: (period, weekday, lessonIndex) =>
        _insertCommonPeriod(afterLessonId: '${period.id}_$lessonIndex'),
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
  final _ScopeSelectCallback onSelectScope;
  final ValueChanged<String> onToggleStage;
  final ValueChanged<String> onToggleGrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppSectionPanel(
    title: '免任课范围',
    useShadow: true,
    headerPadding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Column(
      children: [
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
  final _ScopeSelectCallback onSelectScope;
  final VoidCallback onToggle;
  final ValueChanged<String> onToggleGrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grades =
        ref.watch(gradesProvider(stage.id)).valueOrNull ?? const <GradeGroup>[];
    // 清新版范围树：编辑中学段绿色圆点 + 绿底高亮 + 右侧「编辑中」标签；
    // 其他学段灰色圆点，行下方以辅助小字标注「独立作息」。
    return Column(
      children: [
        AppTreeTile(
          isSelected: isEditing || isSelected,
          selectedBackground: isEditing
              ? context.appColors.successSurface
              : context.appColors.selectedBlue,
          selectedForeground: isEditing ? context.appColors.success : null,
          borderRadius: BorderRadius.circular(8),
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
                    color: context.appColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AppStageDot(
                color: isEditing
                    ? context.appColors.success
                    : context.appColors.sidebarMuted,
                size: 7,
              ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  stage.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isEditing
                        ? context.appColors.success
                        : context.appColors.inkSecondary,
                    fontWeight: isEditing ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (isEditing) const _TreeTag(label: '编辑中'),
            ],
          ),
          height: 30,
          contentPadding: const EdgeInsets.only(left: 12, right: 8),
          onTap: () => onSelectScope(
            stage.id,
            _FreeSlotScopeSelection(
              scope: FreeSlotScope.stage,
              scopeId: stage.id,
            ),
          ),
        ),
        if (!isEditing)
          Padding(
            padding: const EdgeInsets.only(left: 32, right: 8, bottom: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '独立作息',
                style: TextStyle(color: context.appColors.muted, fontSize: 11),
              ),
            ),
          ),
        if (isExpanded)
          for (final grade in grades)
            _ScopeGradeNode(
              stage: stage,
              grade: grade,
              stageIsEditing: isEditing,
              isSelected:
                  scope.scope == FreeSlotScope.grade &&
                  scope.scopeId == grade.id,
              isExpanded: expandedGrades.contains(grade.id),
              scope: scope,
              onSelectScope: (selection) => onSelectScope(stage.id, selection),
              onToggle: () => onToggleGrade(grade.id),
            ),
      ],
    );
  }
}

/// 范围树行尾的状态小标签（「编辑中」）。
class _TreeTag extends StatelessWidget {
  const _TreeTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.appColors.surface,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: context.appColors.success,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _ScopeGradeNode extends ConsumerWidget {
  const _ScopeGradeNode({
    required this.stage,
    required this.grade,
    required this.stageIsEditing,
    required this.isSelected,
    required this.isExpanded,
    required this.scope,
    required this.onSelectScope,
    required this.onToggle,
  });

  final SchoolStage stage;
  final GradeGroup grade;

  /// 所属学段是否处于编辑中（年级圆点随之用浅绿）。
  final bool stageIsEditing;
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
          borderRadius: BorderRadius.circular(8),
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
                    color: context.appColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AppStageDot(
                color: stageIsEditing
                    ? context.appColors.success.withValues(alpha: 0.38)
                    : context.appColors.sidebarMuted.withValues(alpha: 0.5),
                size: 6,
              ),
            ],
          ),
          title: Text(
            grade.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: context.appColors.inkSecondary,
            ),
          ),
          height: 28,
          contentPadding: const EdgeInsets.only(left: 24, right: 8),
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
              borderRadius: BorderRadius.circular(8),
              leading: Padding(
                padding: const EdgeInsets.only(left: 26),
                child: AppStageDot(
                  color: context.appColors.sidebarMuted.withValues(alpha: 0.5),
                  size: 5,
                ),
              ),
              title: Text(
                schoolClass.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: context.appColors.inkSecondary,
                ),
              ),
              height: 26,
              contentPadding: const EdgeInsets.only(left: 12, right: 8),
              onTap: () => onSelectScope(
                _FreeSlotScopeSelection(
                  scope: FreeSlotScope.schoolClass,
                  scopeId: schoolClass.id,
                  parentGradeId: grade.id,
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
      color: context.appColors.tableHeader,
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
          color: isSelected ? context.appColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${stage.name} · $total 节',
          style: TextStyle(
            color: isSelected
                ? context.appColors.blue
                : context.appColors.muted,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _CommonPeriodChip extends StatelessWidget {
  const _CommonPeriodChip({required this.period});

  final CommonPeriod period;

  @override
  Widget build(BuildContext context) {
    final start = period.startLabel;
    final end = period.endLabel;
    final detail = start != null && end != null
        ? '$start–$end'
        : '${period.durationMinutes} 分钟';
    return AppBadge(
      label: '${period.name} · $detail',
      foreground: context.appColors.warning,
      background: context.appColors.warningSurface,
      fontSize: 11,
    );
  }
}

class _CellInfo {
  const _CellInfo({required this.invalid, required this.marker});

  const _CellInfo.invalid() : invalid = true, marker = null;

  final bool invalid;
  final FreeSlot? marker;
}

/// 网格行条目。
class _GridItem {
  const _GridItem.lesson(this.row, this.period) : commonPeriod = null;
  const _GridItem.common(this.commonPeriod) : row = null, period = null;

  final RoutineRow? row;
  final _PeriodDraft? period;
  final CommonPeriod? commonPeriod;
}

/// 纵向滚动条在内容区右侧占用的槽宽，与 Scrollbar 的 thickness 一致。
/// 面板右侧内边距 = 期望的右侧留白 - 该槽宽，使内容（含滚动条）左右留白等宽。
const double _verticalScrollbarGutterWidth = 8;

class _NoAutoVerticalScrollbarBehavior extends MaterialScrollBehavior {
  const _NoAutoVerticalScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final isVertical =
        details.direction == AxisDirection.down ||
        details.direction == AxisDirection.up;
    return isVertical ? child : super.buildScrollbar(context, child, details);
  }
}

class _VerticalScrollWithGutter extends StatefulWidget {
  const _VerticalScrollWithGutter({required this.child});

  final Widget child;

  @override
  State<_VerticalScrollWithGutter> createState() =>
      _VerticalScrollWithGutterState();
}

class _VerticalScrollWithGutterState extends State<_VerticalScrollWithGutter> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: const _NoAutoVerticalScrollbarBehavior(),
    child: ScrollbarTheme(
      data: ScrollbarTheme.of(context).copyWith(crossAxisMargin: 0),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: false,
        thickness: 8,
        radius: const Radius.circular(4),
        scrollbarOrientation: ScrollbarOrientation.right,
        notificationPredicate: (notification) =>
            notification.depth == 0 &&
            (notification.metrics.axisDirection == AxisDirection.down ||
                notification.metrics.axisDirection == AxisDirection.up),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: widget.child,
              ),
            ),
            const SizedBox(width: _verticalScrollbarGutterWidth),
          ],
        ),
      ),
    ),
  );
}

class _FreeSlotMatrix extends StatelessWidget {
  const _FreeSlotMatrix({
    super.key,
    required this.items,
    required this.days,
    required this.teachingDays,
    this.footer,
    this.scrollVertically = true,
    required this.cellInfo,
    required this.onCellTap,
    required this.onSetMarkerLabel,
    required this.onCustomLabel,
    required this.onAddCommonPeriod,
  });

  final List<_GridItem> items;
  final List<int> days;
  final Set<int> teachingDays;
  final Widget? footer;
  final bool scrollVertically;
  final _CellInfo Function(_PeriodDraft, int, int) cellInfo;
  final Future<void> Function(_PeriodDraft, int, int, String) onCellTap;
  final Future<void> Function(_PeriodDraft, int, int, String, String)
  onSetMarkerLabel;
  final Future<void> Function(_PeriodDraft, int, int, String) onCustomLabel;
  final Future<void> Function(_PeriodDraft, int, int) onAddCommonPeriod;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return _buildScrollableContent(
        const SizedBox(height: 44, child: Center(child: Text('请先在左侧选择上课天。'))),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 88.0;
        final matrixWidth =
            constraints.maxWidth -
            (scrollVertically ? _verticalScrollbarGutterWidth : 0);
        final dayWidth = math.max(
          72.0,
          (matrixWidth - labelWidth) / days.length,
        );
        final table = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            children: [
              Row(
                children: [
                  _matrixHeading(
                    context,
                    '节次',
                    width: labelWidth,
                    fontSize: 11,
                  ),
                  for (final weekday in days)
                    _matrixHeading(
                      context,
                      teachingDays.contains(weekday)
                          ? _weekdayShort[weekday - 1]
                          : '',
                      width: dayWidth,
                      fontSize: 12,
                    ),
                ],
              ),
              for (final item in items)
                _buildItem(context, item, labelWidth, dayWidth),
            ],
          ),
        );
        return _buildScrollableContent(table);
      },
    );
  }

  Widget _buildScrollableContent(Widget table) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        table,
        if (footer != null) ...[const SizedBox(height: 12), footer!],
      ],
    );
    // 窄布局由页面统一纵向滚动；其余布局让表格与汇总共用滚动区。
    return scrollVertically
        ? _VerticalScrollWithGutter(child: content)
        : content;
  }

  Widget _buildItem(
    BuildContext context,
    _GridItem item,
    double labelWidth,
    double dayWidth,
  ) {
    final commonPeriod = item.commonPeriod;
    if (commonPeriod != null) {
      return _buildCommonPeriodRow(context, commonPeriod, labelWidth, dayWidth);
    }
    final row = item.row!;
    final period = item.period!;
    final visual = periodVisualFor(context, row.periodName, period.sortOrder);
    return Row(
      children: [
        _matrixLabelCell(
          context: context,
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

  Widget _buildCommonPeriodRow(
    BuildContext context,
    CommonPeriod period,
    double labelWidth,
    double dayWidth,
  ) => Row(
    children: [
      Container(
        width: labelWidth,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.appColors.warningSurface,
          border: Border(
            bottom: BorderSide(color: context.appColors.tableDivider),
          ),
        ),
        child: Text(
          '公共时段',
          style: TextStyle(
            color: context.appColors.warning,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Container(
        width: dayWidth * days.length,
        height: 34,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: context.appColors.warningSurface,
          border: Border(
            bottom: BorderSide(color: context.appColors.tableDivider),
          ),
        ),
        child: _CommonPeriodChip(period: period),
      ),
    ],
  );

  Widget _matrixHeading(
    BuildContext context,
    String label, {
    required double width,
    required double fontSize,
  }) => Container(
    width: width,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.appColors.tableHeader,
      border: Border(
        right: BorderSide(color: context.appColors.tableDivider),
        bottom: BorderSide(color: context.appColors.tableDivider),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
    ),
  );

  Widget _matrixLabelCell({
    required BuildContext context,
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
      border: Border(
        right: BorderSide(color: context.appColors.tableDivider),
        bottom: BorderSide(color: context.appColors.tableDivider),
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
    FreeSlotLabels.noClass: 'N',
    FreeSlotLabels.none: 'L',
    FreeSlotLabels.selfStudy: 'S',
    FreeSlotLabels.labor: 'V',
    FreeSlotLabels.teachingResearch: 'W',
    FreeSlotLabels.partyLeague: 'X',
  };

  @override
  Widget build(BuildContext context) {
    final background = info.marker?.label == FreeSlotLabels.noClass
        ? context.appColors.tableHeader
        : info.marker != null
        ? context.appColors.destructiveSurface
        : info.invalid
        ? context.appColors.tableHeader
        : tint;
    final label = info.marker?.label;
    final currentLabel = info.marker?.label;
    final cell = InkWell(
      onTap: info.invalid ? null : onTap,
      child: Tooltip(
        message: info.marker != null
            ? '${info.marker!.label} · $periodName · $weekdayName'
            : info.invalid
            ? '$weekdayName 不上课'
            : '$weekdayName $periodName · 点击标记免任课',
        child: Container(
          width: width,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            border: Border(
              right: BorderSide(color: context.appColors.tableDivider),
              bottom: BorderSide(color: context.appColors.tableDivider),
            ),
          ),
          child: label == null
              ? info.invalid
                    ? Text(
                        '—',
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 11,
                        ),
                      )
                    : const SizedBox.shrink()
              : Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: label == FreeSlotLabels.noClass
                        ? context.appColors.inkSecondary
                        : context.appColors.destructive,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
    if (info.invalid) return cell;
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
                shortcut: 'C',
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
  });

  final _PeriodDraft period;
  final PeriodVisual visual;
  final void Function(String, int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          AppStageDot(color: visual.color, size: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              period.name,
              style: TextStyle(
                color: context.appColors.ink,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          AppNumberStepper(
            value: period.defaultLessonCount,
            onChanged: (value) => onChanged(period.id, value),
            min: 0,
            max: 9,
          ),
        ],
      ),
    );
  }
}

class _SchoolFreeSlotEntry {
  const _SchoolFreeSlotEntry({
    required this.stageOrder,
    required this.stageName,
    required this.scopeName,
    required this.periodOrder,
    required this.periodName,
    required this.slot,
  });

  final int stageOrder;
  final String stageName;
  final String scopeName;
  final int periodOrder;
  final String periodName;
  final FreeSlot slot;
}

class _AllSchoolFreeSlotsSummary extends ConsumerWidget {
  const _AllSchoolFreeSlotsSummary({
    required this.stages,
    required this.draftChanges,
    required this.trailingInset,
    required this.onDelete,
  });

  final List<SchoolStage> stages;
  final Map<String, FreeSlot?> draftChanges;
  final double trailingInset;
  final ValueChanged<FreeSlot> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = <_SchoolFreeSlotEntry>[];
    var isLoading = false;
    var hasError = false;
    for (var stageIndex = 0; stageIndex < stages.length; stageIndex++) {
      final stage = stages[stageIndex];
      final slotsState = ref.watch(freeSlotsProvider(stage.id));
      final routineState = ref.watch(routineProvider(stage.id));
      final gradesState = ref.watch(gradesProvider(stage.id));
      final grades = gradesState.valueOrNull ?? const <GradeGroup>[];
      final gradeNames = {for (final grade in grades) grade.id: grade.name};
      final classNames = <String, String>{};
      for (final grade in grades) {
        final classesState = ref.watch(classesProvider(grade.id));
        for (final group in classesState.valueOrNull ?? const <ClassGroup>[]) {
          classNames[group.id] = '${grade.name} · ${group.name}';
        }
        isLoading =
            isLoading ||
            classesState.isLoading && classesState.valueOrNull == null;
        hasError = hasError || classesState.hasError;
      }

      final periods =
          routineState.valueOrNull?.periodTypes ?? const <LessonPeriodType>[];
      final periodById = {for (final item in periods) item.id: item};
      final slotsById = {
        for (final slot in slotsState.valueOrNull ?? const <FreeSlot>[])
          slot.id: slot,
      };
      for (final entry in draftChanges.entries) {
        final slot = entry.value;
        if (slot == null) {
          slotsById.remove(entry.key);
        } else if (slot.stageId == stage.id) {
          slotsById[entry.key] = slot;
        }
      }
      for (final slot in slotsById.values) {
        final period = periodById[slot.periodTypeId];
        final scopeName = switch (slot.scope) {
          FreeSlotScope.school => '全校',
          FreeSlotScope.stage => '学段',
          FreeSlotScope.grade => gradeNames[slot.scopeId] ?? '年级',
          FreeSlotScope.schoolClass => classNames[slot.scopeId] ?? '班级',
        };
        entries.add(
          _SchoolFreeSlotEntry(
            stageOrder: stageIndex,
            stageName: stage.name,
            scopeName: scopeName,
            periodOrder: period?.sortOrder ?? 0,
            periodName: period?.name ?? '时段',
            slot: slot,
          ),
        );
      }
      isLoading =
          isLoading ||
          slotsState.isLoading && slotsState.valueOrNull == null ||
          routineState.isLoading && routineState.valueOrNull == null ||
          gradesState.isLoading && gradesState.valueOrNull == null;
      hasError =
          hasError ||
          slotsState.hasError ||
          routineState.hasError ||
          gradesState.hasError;
    }
    entries.sort((a, b) {
      final stageOrder = a.stageOrder.compareTo(b.stageOrder);
      if (stageOrder != 0) return stageOrder;
      final weekday = a.slot.weekday.compareTo(b.slot.weekday);
      if (weekday != 0) return weekday;
      final periodOrder = a.periodOrder.compareTo(b.periodOrder);
      if (periodOrder != 0) return periodOrder;
      return a.slot.lessonIndex.compareTo(b.slot.lessonIndex);
    });
    final entriesByWeekday = <int, List<_SchoolFreeSlotEntry>>{};
    for (final entry in entries) {
      entriesByWeekday
          .putIfAbsent(entry.slot.weekday, () => <_SchoolFreeSlotEntry>[])
          .add(entry);
    }
    final weekdays = entriesByWeekday.keys.toList()..sort();
    final weekdayGroups = [
      for (final weekday in weekdays)
        _buildWeekdayGroup(
          context: context,
          weekdayLabel: weekday >= 1 && weekday <= 7
              ? _weekdayNames[weekday - 1]
              : '其他日期',
          entries: entriesByWeekday[weekday]!,
          onDelete: onDelete,
        ),
    ];
    final groupedList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < weekdayGroups.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          weekdayGroups[index],
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Row(
              children: [
                Text('全校免任课', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  '${entries.length} 项',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading && entries.isEmpty)
            const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (hasError && entries.isEmpty)
            Text(
              '免任课暂时无法读取',
              style: TextStyle(color: context.appColors.muted, fontSize: 11),
            )
          else if (entries.isEmpty)
            Text(
              '暂无免任课',
              style: TextStyle(color: context.appColors.muted, fontSize: 11),
            )
          else
            Padding(
              // 与右侧滚动条留出间距，避免误触滚动条。
              padding: EdgeInsets.only(right: trailingInset),
              child: groupedList,
            ),
        ],
      ),
    );
  }

  Widget _buildWeekdayGroup({
    required BuildContext context,
    required String weekdayLabel,
    required List<_SchoolFreeSlotEntry> entries,
    required ValueChanged<FreeSlot> onDelete,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          weekdayLabel,
          style: TextStyle(
            color: context.appColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      for (final entry in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entry.periodName}第 ${entry.slot.lessonIndex} 节',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: Text(
                      entry.slot.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.warning,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: 20,
                    child: IconButton(
                      tooltip: '删除这条免任课',
                      onPressed: () => onDelete(entry.slot),
                      constraints: const BoxConstraints.tightFor(
                        width: 20,
                        height: 20,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 12,
                      color: context.appColors.muted,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.stageName} · ${entry.scopeName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.appColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
    ],
  );
}

class _LessonTimePanel extends StatelessWidget {
  const _LessonTimePanel({
    this.scrollable = true,
    required this.periods,
    required this.timeInputs,
    required this.revision,
    required this.commonPeriods,
    required this.needsCrossStageTimes,
    required this.collapsedGroups,
    required this.onToggleGroup,
    required this.onTimeChanged,
    required this.onInsertCommonPeriod,
    required this.onCommonPeriodTimeChanged,
    required this.onRenameCommonPeriod,
    required this.onDeleteCommonPeriod,
  });

  final bool scrollable;
  final List<_PeriodDraft> periods;
  final Map<String, String> timeInputs;
  final int revision;
  final List<CommonPeriod> commonPeriods;
  final bool needsCrossStageTimes;
  final Set<String> collapsedGroups;
  final ValueChanged<String> onToggleGroup;
  final void Function(_PeriodDraft, int, bool, String) onTimeChanged;
  final Future<void> Function({String? afterLessonId}) onInsertCommonPeriod;
  final void Function(CommonPeriod, bool, String) onCommonPeriodTimeChanged;
  final Future<void> Function(CommonPeriod) onRenameCommonPeriod;
  final Future<void> Function(CommonPeriod) onDeleteCommonPeriod;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      const _TimeColumnHeader(),
      for (var index = 0; index < periods.length; index++) ...[
        if (collapsedGroups.contains(periods[index].id))
          _PeriodGroupHeaderCollapsed(
            period: periods[index],
            visual: periodVisualFor(context, periods[index].name, index),
            timeInputs: timeInputs,
            onExpand: () => onToggleGroup(periods[index].id),
          )
        else ...[
          _PeriodGroupHeader(
            period: periods[index],
            visual: periodVisualFor(context, periods[index].name, index),
            onCollapse: () => onToggleGroup(periods[index].id),
          ),
          for (final time in periods[index].times) ...[
            _LessonTimeRow(
              period: periods[index],
              time: time,
              timeInputs: timeInputs,
              revision: revision,
              onChanged: onTimeChanged,
            ),
            for (final common in commonPeriods.where(
              (item) =>
                  item.insertAfterLessonId ==
                  '${periods[index].id}_${time.lessonIndex}',
            ))
              _CommonPeriodRow(
                period: common,
                onChanged: onCommonPeriodTimeChanged,
                onRename: onRenameCommonPeriod,
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
            onChanged: onCommonPeriodTimeChanged,
            onRename: onRenameCommonPeriod,
            onDelete: onDeleteCommonPeriod,
          ),
      ],
    ];
    return AppSectionPanel(
      title: '节次与时间',
      useShadow: true,
      expandChild: scrollable,
      // 右侧留白 = 该内边距 + 滚动条槽宽，与左侧 12 保持一致。
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        scrollable ? 12 - _verticalScrollbarGutterWidth : 12,
        0,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (needsCrossStageTimes)
            AppBadge(
              label: '跨学段必填',
              foreground: context.appColors.warning,
              background: context.appColors.warningSurface,
              fontSize: 11,
            ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => onInsertCommonPeriod(),
            child: Text(
              '+ 插入',
              style: TextStyle(
                color: context.appColors.blue,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      child: scrollable
          ? _VerticalScrollWithGutter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
    );
  }
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
            style: TextStyle(
              color: context.appColors.inkSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}

/// 折叠的分组头（24px #FAFAFA：时段节数与起止时间摘要）。
///
/// 时间未填写时只显示当前时段节数。
class _PeriodGroupHeaderCollapsed extends StatelessWidget {
  const _PeriodGroupHeaderCollapsed({
    required this.period,
    required this.visual,
    required this.timeInputs,
    required this.onExpand,
  });

  final _PeriodDraft period;
  final PeriodVisual visual;
  final Map<String, String> timeInputs;
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

  @override
  Widget build(BuildContext context) {
    final summary = _timeRangeLabel;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: context.appColors.tableHeader,
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
                  style: TextStyle(
                    color: context.appColors.inkSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '展开',
                style: TextStyle(color: context.appColors.blue, fontSize: 11),
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
    required this.revision,
    required this.onChanged,
  });

  final _PeriodDraft period;
  final _TimeDraft time;
  final Map<String, String> timeInputs;
  final int revision;
  final void Function(_PeriodDraft, int, bool, String) onChanged;

  @override
  Widget build(BuildContext context) {
    final visual = periodVisualFor(context, period.name, period.sortOrder);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths = _timeRowWidths(constraints.maxWidth);
          return Row(
            children: [
              Container(
                width: widths.label,
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
                width: widths.field,
                child: _TimePickerField(
                  key: ValueKey(
                    '${revision}_${period.id}_${time.lessonIndex}_start',
                  ),
                  value:
                      timeInputs['${period.id}_${time.lessonIndex}_start'] ??
                      '',
                  hint: '08:00',
                  onPicked: (value) =>
                      onChanged(period, time.lessonIndex, true, value),
                ),
              ),
              SizedBox(
                width: _timeSeparatorWidth,
                child: Center(
                  child: Text(
                    '–',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: widths.field,
                child: _TimePickerField(
                  key: ValueKey(
                    '${revision}_${period.id}_${time.lessonIndex}_end',
                  ),
                  value:
                      timeInputs['${period.id}_${time.lessonIndex}_end'] ?? '',
                  hint: '08:45',
                  onPicked: (value) =>
                      onChanged(period, time.lessonIndex, false, value),
                ),
              ),
              const SizedBox(width: _timeRowTrailingWidth),
            ],
          );
        },
      ),
    );
  }
}

class _TimePickerField extends StatelessWidget {
  const _TimePickerField({
    required this.value,
    required this.hint,
    required this.onPicked,
    super.key,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onPicked;

  Future<void> _pickTime(BuildContext context) async {
    final minutes = _parseTime(value) ?? _parseTime(hint) ?? 0;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    onPicked(
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedValue = value.isEmpty ? '--:--' : value;
    final color = value.isEmpty
        ? context.appColors.muted
        : Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _pickTime(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            color: context.appColors.surface,
            border: Border.all(color: context.appColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(right: value.isEmpty ? 0 : 14),
                    child: Text(
                      displayedValue,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(fontSize: 12, color: color),
                    ),
                  ),
                ),
              ),
              if (value.isNotEmpty)
                Positioned(
                  right: 1,
                  top: 0,
                  bottom: 0,
                  child: Tooltip(
                    message: '清空时间',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onPicked(''),
                      child: SizedBox(
                        width: 16,
                        child: Center(
                          child: Icon(
                            Icons.close_rounded,
                            size: 10,
                            color: context.appColors.muted,
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

class _TimeColumnHeader extends StatelessWidget {
  const _TimeColumnHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 2),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final widths = _timeRowWidths(constraints.maxWidth);
        return Row(
          children: [
            SizedBox(
              width: widths.label,
              child: Text(
                '节次',
                style: TextStyle(color: context.appColors.muted, fontSize: 10),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: widths.field,
              child: Center(
                child: Text(
                  '开始',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: _timeSeparatorWidth),
            SizedBox(
              width: widths.field,
              child: Center(
                child: Text(
                  '结束',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: _timeRowTrailingWidth),
          ],
        );
      },
    ),
  );
}

class _CommonPeriodRow extends StatelessWidget {
  const _CommonPeriodRow({
    required this.period,
    required this.onChanged,
    required this.onRename,
    required this.onDelete,
  });

  final CommonPeriod period;
  final void Function(CommonPeriod, bool, String) onChanged;
  final Future<void> Function(CommonPeriod) onRename;
  final Future<void> Function(CommonPeriod) onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final widths = _timeRowWidths(constraints.maxWidth);
        return Row(
          children: [
            Tooltip(
              message: '点击编辑名称',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => unawaited(onRename(period)),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: widths.label,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.appColors.warningSurface,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      period.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.warning,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: widths.field,
              child: _TimePickerField(
                value: period.startLabel ?? '',
                hint: '09:05',
                onPicked: (value) => onChanged(period, true, value),
              ),
            ),
            SizedBox(
              width: _timeSeparatorWidth,
              child: Center(
                child: Text(
                  '–',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: widths.field,
              child: _TimePickerField(
                value: period.endLabel ?? '',
                hint: '09:15',
                onPicked: (value) => onChanged(period, false, value),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: _timeRowTrailingWidth - 4,
              child: InkWell(
                onTap: () => onDelete(period),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: context.appColors.muted,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

// —— 弹窗 ——

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

  /// 「第 1 节之前」的哨兵值：下拉组件无法把 null 当作可回显的选中项
  /// （null 会被当作未选择而显示为空），提交时再映射回领域层的 null
  /// （afterLessonId = null 表示插在最前）。
  static const _beforeFirstLessonId = '__before_first__';

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
                '第 1 节之前': _beforeFirstLessonId,
                for (final period in widget.periods)
                  for (final time in period.times)
                    '${time.label} 之后': '${period.id}_${time.lessonIndex}',
              },
              value: _afterLessonId,
              label: '位置',
              onChanged: (value) => setState(() => _afterLessonId = value),
            ),
            const SizedBox(height: 12),
            Text(
              '公共时段不排正课；插入后该学段所有上课日的课表与打印布局同步显示。',
              style: TextStyle(color: context.appColors.muted, fontSize: 11),
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
              afterLessonId: _afterLessonId == _beforeFirstLessonId
                  ? null
                  : _afterLessonId,
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

/// 一次编辑及其作用范围，用于在撤销/重做时恢复选中位置。
class _UndoableEdit {
  _UndoableEdit({
    required this.message,
    required this.undo,
    required this.redo,
    required this.stageId,
    required this.scope,
    required this.expandedStages,
    required this.expandedGrades,
    this.coalesceKey,
  });

  String message;
  final FutureOr<void> Function() undo;
  FutureOr<void> Function() redo;
  final String stageId;
  final _FreeSlotScopeSelection scope;
  final Set<String> expandedStages;
  final Set<String> expandedGrades;
  final String? coalesceKey;
}

/// 草稿快照：用于判定是否有未保存修改。
class _DraftSnapshot {
  const _DraftSnapshot({
    this.teachingDays = const {},
    this.periods = const [],
    this.timeInputs = const {},
    this.freeSlotDraft = const {},
    this.commonPeriodDraft = const {},
  });

  final Set<int> teachingDays;
  final List<_PeriodSnapshot> periods;
  final Map<String, String> timeInputs;
  final Map<String, FreeSlot?> freeSlotDraft;
  final Map<String, CommonPeriod?> commonPeriodDraft;

  bool isSame(_DraftSnapshot other) {
    if (teachingDays.length != other.teachingDays.length) return false;
    if (!teachingDays.containsAll(other.teachingDays)) return false;
    if (periods.length != other.periods.length) return false;
    for (var index = 0; index < periods.length; index++) {
      if (!periods[index].isSame(other.periods[index])) return false;
    }
    if (timeInputs.length != other.timeInputs.length) return false;
    for (final entry in timeInputs.entries) {
      if (other.timeInputs[entry.key] != entry.value) return false;
    }
    if (!_sameNullableMap(freeSlotDraft, other.freeSlotDraft, _sameFreeSlot)) {
      return false;
    }
    if (!_sameNullableMap(
      commonPeriodDraft,
      other.commonPeriodDraft,
      _sameCommonPeriod,
    )) {
      return false;
    }
    return true;
  }
}

bool _sameNullableMap<T>(
  Map<String, T?> left,
  Map<String, T?> right,
  bool Function(T?, T?) sameValue,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) ||
        !sameValue(entry.value, right[entry.key])) {
      return false;
    }
  }
  return true;
}

bool _sameFreeSlot(FreeSlot? left, FreeSlot? right) =>
    identical(left, right) ||
    left != null &&
        right != null &&
        left.id == right.id &&
        left.scope == right.scope &&
        left.scopeId == right.scopeId &&
        left.stageId == right.stageId &&
        left.periodTypeId == right.periodTypeId &&
        left.weekday == right.weekday &&
        left.lessonIndex == right.lessonIndex &&
        left.label == right.label;

bool _sameCommonPeriod(CommonPeriod? left, CommonPeriod? right) =>
    identical(left, right) ||
    left != null &&
        right != null &&
        left.id == right.id &&
        left.stageId == right.stageId &&
        left.name == right.name &&
        left.insertAfterLessonId == right.insertAfterLessonId &&
        left.durationMinutes == right.durationMinutes &&
        left.startMinute == right.startMinute &&
        left.endMinute == right.endMinute;

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

String _timeKey(String periodId, int lessonIndex, bool isStart) =>
    '${periodId}_${lessonIndex}_${isStart ? 'start' : 'end'}';

int? _parseTime(String value) {
  final match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  if (hour > 23) return null;
  return hour * 60 + int.parse(match.group(2)!);
}
