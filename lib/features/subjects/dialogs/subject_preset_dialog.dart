import 'dart:async';
import 'dart:math' as math;

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/domain/models/subject_parallel_limit.dart';
import 'package:class_set/features/public_rooms/public_rooms_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_lesson_constraint.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart' as f;

typedef SubjectPresetEdit = ({
  FreeSlotScope scope,
  String scopeId,
  String stageId,
  List<PresetCell> cells,
});

typedef SubjectLessonConstraintEdit = ({
  FreeSlotScope scope,
  String scopeId,
  String stageId,
  List<SubjectLessonConstraint> constraints,
});

typedef SubjectRoomSettingsEdit = ({
  List<SubjectRoomAssignment> assignments,
  List<SubjectParallelLimit> limits,
});

typedef SubjectPresetDialogResult = ({
  List<SubjectPresetEdit> presets,
  List<SubjectLessonConstraintEdit> constraints,
  SubjectRoomSettingsEdit? roomSettings,
});

typedef _PresetDraftKey = ({
  FreeSlotScope scope,
  String scopeId,
  String stageId,
});

typedef _PresetEntryKey = ({
  FreeSlotScope scope,
  String scopeId,
  String stageId,
  int weekday,
  String periodTypeId,
  int lessonIndex,
});

typedef _ConstraintEntryKey = ({
  FreeSlotScope scope,
  String scopeId,
  String stageId,
  int? weekday,
});

typedef _ConstraintListEntry = ({
  _ConstraintEntryKey key,
  SubjectLessonConstraint constraint,
  String rangeLabel,
  String ruleLabel,
  bool pending,
  bool deleted,
  int stageOrder,
  int scopeOrder,
});

typedef _PresetCellAddress = ({
  int weekday,
  String periodTypeId,
  int lessonIndex,
});

typedef _PresetListEntry = ({
  _PresetEntryKey key,
  String rangeLabel,
  String cellLabel,
  String valueLabel,
  bool pending,
  bool deleted,
  int stageOrder,
  int scopeOrder,
  int weekday,
  int periodOrder,
  int lessonIndex,
});

typedef _DeletedPresetCellDraft = ({
  PresetValue? value,
  bool wasChanged,
  bool wasDirty,
});

/// 科目预设弹窗（US-015 / 设计稿 03b）。
///
/// 节次 × 周一~周五 四态方格：单击在 自动 → 尽量排 → 一定排 → 不排
/// 间循环，右键直选；范围三级（学段 / 年级 / 班级），默认矩阵
/// 当前列；预设不区分单双周；「一定排」格数超过该周需求节数时，
/// 保存按周次列出警告（AC6）。
class SubjectPresetDialog extends ConsumerStatefulWidget {
  const SubjectPresetDialog({
    required this.subject,
    required this.termId,
    required this.initialStageId,
    required this.initialGradeId,
    required this.stages,
    required this.grades,
    required this.classes,
    required this.routines,
    required this.presets,
    required this.constraints,
    required this.freeSlots,
    required this.classDemands,
    this.roomAssignments = const [],
    this.parallelLimits = const [],
    super.key,
  });

  final Subject subject;
  final String termId;
  final String initialStageId;
  final String initialGradeId;
  final List<SchoolStage> stages;
  final List<GradeGroup> grades;

  /// 当前学期的全部班级，用于范围树和容量警告。
  final List<ClassBrief> classes;
  final Map<String, StageRoutine> routines;

  /// 该科目全部预设行。
  final List<SubjectPreset> presets;

  /// 该科目的所有范围课节与连堂限制。
  final List<SubjectLessonConstraint> constraints;

  /// 当前学期的免任课标记，用于显示并禁用相应预排格。
  final List<FreeSlot> freeSlots;

  /// 班级 ID → 单 / 双周需求节数（用于 AC6 警告）。
  final Map<String, ClassSubjectValues> classDemands;

  final List<SubjectRoomAssignment> roomAssignments;
  final List<SubjectParallelLimit> parallelLimits;

  @override
  ConsumerState<SubjectPresetDialog> createState() =>
      _SubjectPresetDialogState();
}

class _SubjectPresetDialogState extends ConsumerState<SubjectPresetDialog> {
  static const double _advancedSettingFieldWidth = 360;
  TextStyle get _advancedSettingLabelStyle => TextStyle(
    color: context.appColors.ink,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
  TextStyle get _advancedSettingHelpStyle =>
      TextStyle(color: context.appColors.muted, fontSize: 12, height: 1.45);

  int _selectedEditorTabIndex = 0;
  late final List<SubjectRoomAssignment> _roomAssignments;
  late final List<SubjectParallelLimit> _parallelLimits;
  final Map<_PresetDraftKey, TextEditingController> _limitControllers = {};
  bool _roomSettingsDirty = false;
  late FreeSlotScope _scope;
  late String _scopeId;
  late String _activeStageId;
  late Map<String, PresetValue> _grid;
  late final Set<String> _expandedStageIds;
  final Set<String> _expandedGradeIds = {};
  final Map<_PresetDraftKey, Map<String, PresetValue>> _drafts = {};
  final Set<_PresetDraftKey> _dirtyDrafts = {};
  final Map<_PresetDraftKey, Map<int?, SubjectLessonConstraint>>
  _constraintDrafts = {};
  final Set<_PresetDraftKey> _dirtyConstraintDrafts = {};
  final Map<_ConstraintEntryKey, SubjectLessonConstraint>
  _deletedConstraintSnapshots = {};
  final Map<_PresetDraftKey, Set<String>> _changedCells = {};
  final Map<_PresetDraftKey, Set<String>> _deletedCells = {};
  final Map<_PresetDraftKey, Map<String, _DeletedPresetCellDraft>>
  _deletedSnapshots = {};

  @override
  void initState() {
    super.initState();
    _roomAssignments = widget.roomAssignments
        .where(
          (row) =>
              row.subjectId == widget.subject.id && row.termId == widget.termId,
        )
        .toList();
    _parallelLimits = widget.parallelLimits
        .where(
          (row) =>
              row.subjectId == widget.subject.id && row.termId == widget.termId,
        )
        .toList();
    _scope = FreeSlotScope.stage;
    _scopeId = widget.initialStageId;
    _activeStageId = widget.initialStageId;
    _expandedStageIds = {widget.initialStageId};
    _grid = _loadDraft(_currentDraftKey);
  }

  @override
  void dispose() {
    for (final controller in _limitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  StageRoutine? get _activeRoutine => widget.routines[_activeStageId];

  _PresetDraftKey get _currentDraftKey =>
      (scope: _scope, scopeId: _scopeId, stageId: _activeStageId);

  Map<String, PresetValue> _loadDraft(_PresetDraftKey key) =>
      _drafts.putIfAbsent(
        key,
        () => effectivePresetMap(
          presets: widget.presets,
          stageId: key.stageId,
          scope: key.scope,
          scopeId: key.scopeId,
          parentGradeId: key.scope == FreeSlotScope.schoolClass
              ? widget.classes
                    .where((item) => item.id == key.scopeId)
                    .firstOrNull
                    ?.gradeId
              : null,
        ),
      );

  Map<int?, SubjectLessonConstraint> _loadConstraintDraft(
    _PresetDraftKey key,
  ) => _constraintDrafts.putIfAbsent(key, () {
    return {
      for (final constraint in widget.constraints)
        if (constraint.scope == key.scope &&
            constraint.scopeId == key.scopeId &&
            constraint.stageId == key.stageId)
          constraint.weekday: constraint,
    };
  });

  List<SchoolStage> get _orderedStages =>
      [...widget.stages]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<GradeGroup> _gradesForStage(String stageId) =>
      widget.grades.where((grade) => grade.stageId == stageId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<ClassBrief> _classesForGrade(String gradeId) =>
      widget.classes
          .where((classBrief) => classBrief.gradeId == gradeId)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  void _selectScope({
    required FreeSlotScope scope,
    required String scopeId,
    required String stageId,
  }) {
    setState(() {
      _scope = scope;
      _scopeId = scopeId;
      _activeStageId = stageId;
      _grid = _loadDraft(_currentDraftKey);
    });
  }

  void _cycleCell(int weekday, String periodTypeId, int lessonIndex) {
    if (_effectiveFreeSlot(
          _currentDraftKey,
          weekday,
          periodTypeId,
          lessonIndex,
        ) !=
        null) {
      return;
    }
    final key = presetCellKey(weekday, periodTypeId, lessonIndex);
    setState(() {
      final current = _grid[key] ?? PresetValue.auto;
      _grid[key] = current.next;
      _changedCells.putIfAbsent(_currentDraftKey, () => <String>{}).add(key);
      _dirtyDrafts.add(_currentDraftKey);
    });
  }

  void _setCell(
    int weekday,
    String periodTypeId,
    int lessonIndex,
    PresetValue value,
  ) {
    if (_effectiveFreeSlot(
          _currentDraftKey,
          weekday,
          periodTypeId,
          lessonIndex,
        ) !=
        null) {
      return;
    }
    final key = presetCellKey(weekday, periodTypeId, lessonIndex);
    setState(() {
      _grid[key] = value;
      _changedCells.putIfAbsent(_currentDraftKey, () => <String>{}).add(key);
      _dirtyDrafts.add(_currentDraftKey);
    });
  }

  void _clearPresetCell(int weekday, String periodTypeId, int lessonIndex) {
    final cellKey = presetCellKey(weekday, periodTypeId, lessonIndex);
    final deleted = _deletedCells[_currentDraftKey] ?? const <String>{};
    if (deleted.contains(cellKey)) return;

    final hasLocalPreset = widget.presets.any(
      (preset) =>
          preset.scope == _scope &&
          preset.scopeId == _scopeId &&
          preset.stageId == _activeStageId &&
          preset.weekday == weekday &&
          preset.periodTypeId == periodTypeId &&
          preset.lessonIndex == lessonIndex,
    );
    final hasPendingOverride =
        _changedCells[_currentDraftKey]?.contains(cellKey) ?? false;
    if (!hasLocalPreset && !hasPendingOverride) return;

    _togglePresetDeletion((
      scope: _scope,
      scopeId: _scopeId,
      stageId: _activeStageId,
      weekday: weekday,
      periodTypeId: periodTypeId,
      lessonIndex: lessonIndex,
    ));
  }

  void _togglePresetDeletion(_PresetEntryKey entryKey) {
    final draftKey = (
      scope: entryKey.scope,
      scopeId: entryKey.scopeId,
      stageId: entryKey.stageId,
    );
    final cellKey = presetCellKey(
      entryKey.weekday,
      entryKey.periodTypeId,
      entryKey.lessonIndex,
    );
    final deleted = _deletedCells.putIfAbsent(draftKey, () => <String>{});
    final snapshots = _deletedSnapshots.putIfAbsent(
      draftKey,
      () => <String, _DeletedPresetCellDraft>{},
    );
    setState(() {
      final draft = _loadDraft(draftKey);
      if (deleted.remove(cellKey)) {
        final snapshot = snapshots.remove(cellKey);
        if (snapshot?.value == null) {
          draft.remove(cellKey);
        } else {
          draft[cellKey] = snapshot!.value!;
        }
        final changed = _changedCells.putIfAbsent(draftKey, () => <String>{});
        if (snapshot?.wasChanged == true) {
          changed.add(cellKey);
        } else {
          changed.remove(cellKey);
        }
        if (snapshot?.wasDirty == true ||
            changed.isNotEmpty ||
            deleted.isNotEmpty) {
          _dirtyDrafts.add(draftKey);
        } else {
          _dirtyDrafts.remove(draftKey);
        }
      } else {
        final changed = _changedCells[draftKey] ?? const <String>{};
        snapshots[cellKey] = (
          value: draft[cellKey],
          wasChanged: changed.contains(cellKey),
          wasDirty: _dirtyDrafts.contains(draftKey),
        );
        final inherited = effectivePresetMap(
          presets: widget.presets
              .where(
                (preset) =>
                    !(preset.scope == entryKey.scope &&
                        preset.scopeId == entryKey.scopeId &&
                        preset.stageId == entryKey.stageId &&
                        preset.weekday == entryKey.weekday &&
                        preset.periodTypeId == entryKey.periodTypeId &&
                        preset.lessonIndex == entryKey.lessonIndex),
              )
              .toList(),
          stageId: entryKey.stageId,
          scope: entryKey.scope,
          scopeId: entryKey.scopeId,
          parentGradeId: entryKey.scope == FreeSlotScope.schoolClass
              ? widget.classes
                    .where((item) => item.id == entryKey.scopeId)
                    .firstOrNull
                    ?.gradeId
              : null,
        );
        final inheritedValue = inherited[cellKey];
        if (inheritedValue == null) {
          draft.remove(cellKey);
        } else {
          draft[cellKey] = inheritedValue;
        }
        _changedCells[draftKey]?.remove(cellKey);
        deleted.add(cellKey);
        _dirtyDrafts.add(draftKey);
      }
      if (draftKey == _currentDraftKey) _grid = draft;
    });
  }

  /// 「一定排」格数超过该周需求节数的班级（AC6）。
  List<String> _overDemandWarnings(
    _PresetDraftKey draftKey,
    Map<String, PresetValue> grid,
  ) {
    final routine = widget.routines[draftKey.stageId];
    if (routine == null) return const [];
    var mustCount = 0;
    for (final weekday in routine.teachingWeekdays) {
      for (final period in routine.periodTypes) {
        final count = routine.effectiveLessonCount(period.id, weekday);
        for (var lesson = 1; lesson <= count; lesson++) {
          if (_effectiveFreeSlot(draftKey, weekday, period.id, lesson) !=
              null) {
            continue;
          }
          if (grid[presetCellKey(weekday, period.id, lesson)] ==
              PresetValue.must) {
            mustCount++;
          }
        }
      }
    }
    if (mustCount == 0) return const [];
    final warnings = <String>[];
    for (final classBrief in _classesInScope(draftKey)) {
      final demand = widget.classDemands[classBrief.id];
      if (demand == null) continue;
      if (mustCount > demand.oddWeekDemand) {
        warnings.add(
          '${classBrief.name}单周需求 ${demand.oddWeekDemand} 节，一定排 $mustCount 格',
        );
      } else if (mustCount > demand.evenWeekDemand) {
        warnings.add(
          '${classBrief.name}双周需求 ${demand.evenWeekDemand} 节，一定排 $mustCount 格',
        );
      }
    }
    return warnings;
  }

  List<ClassBrief> _classesInScope(_PresetDraftKey draftKey) =>
      widget.classes.where((item) {
        return switch (draftKey.scope) {
          FreeSlotScope.school ||
          FreeSlotScope.stage => item.stageId == draftKey.stageId,
          FreeSlotScope.grade =>
            item.stageId == draftKey.stageId &&
                item.gradeId == draftKey.scopeId,
          FreeSlotScope.schoolClass => item.id == draftKey.scopeId,
        };
      }).toList();

  FreeSlot? _effectiveFreeSlot(
    _PresetDraftKey draftKey,
    int weekday,
    String periodTypeId,
    int lessonIndex,
  ) {
    FreeSlot? best;
    var bestPriority = -1;
    for (final slot in widget.freeSlots) {
      if (slot.stageId != draftKey.stageId ||
          slot.weekday != weekday ||
          slot.periodTypeId != periodTypeId ||
          slot.lessonIndex != lessonIndex) {
        continue;
      }
      final priority = _freeSlotScopePriority(slot, draftKey);
      if (priority > bestPriority) {
        best = slot;
        bestPriority = priority;
      }
    }
    return bestPriority < 0 ? null : best;
  }

  int _freeSlotScopePriority(FreeSlot slot, _PresetDraftKey draftKey) {
    if (slot.scope == draftKey.scope && slot.scopeId == draftKey.scopeId) {
      return 4;
    }
    if (draftKey.scope == FreeSlotScope.school) return -1;
    if (slot.scope == FreeSlotScope.school && slot.scopeId == widget.termId) {
      return 1;
    }
    if (slot.scope == FreeSlotScope.stage && slot.scopeId == draftKey.stageId) {
      return 2;
    }
    if (draftKey.scope == FreeSlotScope.schoolClass &&
        slot.scope == FreeSlotScope.grade) {
      final classBrief = widget.classes
          .where((item) => item.id == draftKey.scopeId)
          .firstOrNull;
      if (classBrief?.gradeId == slot.scopeId) return 3;
    }
    return -1;
  }

  Future<void> _save() async {
    final draftKeys = _dirtyDrafts.toList();
    final constraintDraftKeys = _dirtyConstraintDrafts.toList();
    if (_roomAssignments.any((row) => row.roomId != null)) {
      try {
        final rooms = await ref.read(publicRoomsProvider.future);
        if (!mounted) return;
        final roomIds = rooms.map((room) => room.id).toSet();
        if (_roomAssignments.any(
          (row) => row.roomId != null && !roomIds.contains(row.roomId),
        )) {
          _showConstraintValidation('所选场室已删除，请重新选择或重置为继承。', title: '场室设置有误');
          return;
        }
      } catch (error) {
        if (mounted) {
          _showConstraintValidation('读取公共场室失败：$error', title: '场室设置有误');
        }
        return;
      }
    }
    if (draftKeys.isEmpty &&
        constraintDraftKeys.isEmpty &&
        !_roomSettingsDirty) {
      Navigator.pop<SubjectPresetDialogResult>(context, (
        presets: const [],
        constraints: const [],
        roomSettings: null,
      ));
      return;
    }
    if (_parallelLimits.any((row) => row.maxParallelLessons <= 0)) {
      _showConstraintValidation('同科目同时上课上限须为正整数');
      return;
    }
    final validationMessage = _constraintValidationMessage();
    if (validationMessage != null) {
      _showConstraintValidation(validationMessage);
      return;
    }
    final warnings = [
      for (final draftKey in draftKeys)
        ..._overDemandWarnings(draftKey, _drafts[draftKey]!),
    ];
    if (warnings.isNotEmpty) {
      final proceed = await showAppDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          title: const Text('一定排超出需求节数'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '以下班级的「一定排」格数超过该周需求节数，排课时可能无法全部满足：',
                  style: TextStyle(fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 8),
                for (final item in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '· $item',
                      style: TextStyle(
                        color: context.appColors.destructive,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            AppGhostButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            AppPrimaryButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续保存'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    if (!mounted) return;
    final edits = <SubjectPresetEdit>[];
    for (final draftKey in draftKeys) {
      final routine = widget.routines[draftKey.stageId];
      if (routine == null) continue;
      final weekdays = routine.teachingWeekdays.toList()..sort();
      final periods = routine.periodTypes.toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final grid = _drafts[draftKey]!;
      final localOverrides = <String, PresetValue>{
        for (final preset in widget.presets)
          if (preset.scope == draftKey.scope &&
              preset.scopeId == draftKey.scopeId &&
              preset.stageId == draftKey.stageId)
            presetCellKey(
              preset.weekday,
              preset.periodTypeId,
              preset.lessonIndex,
            ): preset.value,
      };
      for (final key in _deletedCells[draftKey] ?? const <String>{}) {
        localOverrides.remove(key);
      }
      for (final key in _changedCells[draftKey] ?? const <String>{}) {
        if ((_deletedCells[draftKey] ?? const <String>{}).contains(key)) {
          continue;
        }
        final value = grid[key];
        if (value != null) localOverrides[key] = value;
      }
      final cells = <PresetCell>[];
      for (final period in periods) {
        for (final weekday in weekdays) {
          final lessonCount = routine.effectiveLessonCount(period.id, weekday);
          for (var lesson = 1; lesson <= lessonCount; lesson++) {
            if (_effectiveFreeSlot(draftKey, weekday, period.id, lesson) !=
                null) {
              continue;
            }
            final value =
                localOverrides[presetCellKey(weekday, period.id, lesson)];
            // 只保存本范围自己的覆盖值。空白表示继续继承较宽范围；
            // 显式存储的自动值则用于清除继承预设。
            if (value == null) continue;
            cells.add(
              PresetCell(
                weekday: weekday,
                periodTypeId: period.id,
                lessonIndex: lesson,
                value: value,
              ),
            );
          }
        }
      }
      edits.add((
        scope: draftKey.scope,
        scopeId: draftKey.scopeId,
        stageId: draftKey.stageId,
        cells: cells,
      ));
    }
    Navigator.pop<SubjectPresetDialogResult>(context, (
      presets: edits,
      roomSettings: _roomSettingsDirty
          ? (
              assignments: List<SubjectRoomAssignment>.of(_roomAssignments),
              limits: List<SubjectParallelLimit>.of(_parallelLimits),
            )
          : null,
      constraints: [
        for (final draftKey in constraintDraftKeys)
          (
            scope: draftKey.scope,
            scopeId: draftKey.scopeId,
            stageId: draftKey.stageId,
            constraints: [
              for (final constraint in _constraintDrafts[draftKey]!.values)
                if (_hasConstraintValue(constraint)) constraint,
            ],
          ),
      ],
    ));
  }

  bool _hasConstraintValue(SubjectLessonConstraint constraint) =>
      constraint.minimumDailyLessons != null ||
      constraint.maximumDailyLessons != null ||
      constraint.minimumDailyConsecutivePairs != null ||
      constraint.maximumDailyConsecutivePairs != null ||
      constraint.minimumWeeklyConsecutivePairs != null ||
      constraint.maximumWeeklyConsecutivePairs != null;

  void _updateConstraintField(int? weekday, String field, String rawValue) {
    final draft = _loadConstraintDraft(_currentDraftKey);
    final old = draft[weekday];
    final value = rawValue.isEmpty ? null : int.tryParse(rawValue);
    final updated = SubjectLessonConstraint(
      id: old?.id ?? '',
      subjectId: widget.subject.id,
      scope: _scope,
      scopeId: _scopeId,
      stageId: _activeStageId,
      weekday: weekday,
      minimumDailyLessons: field == 'minDaily'
          ? value
          : old?.minimumDailyLessons,
      maximumDailyLessons: field == 'maxDaily'
          ? value
          : old?.maximumDailyLessons,
      minimumDailyConsecutivePairs: field == 'minDailyPairs'
          ? value
          : old?.minimumDailyConsecutivePairs,
      maximumDailyConsecutivePairs: field == 'maxDailyPairs'
          ? value
          : old?.maximumDailyConsecutivePairs,
      minimumWeeklyConsecutivePairs: field == 'minWeekly'
          ? value
          : old?.minimumWeeklyConsecutivePairs,
      maximumWeeklyConsecutivePairs: field == 'maxWeekly'
          ? value
          : old?.maximumWeeklyConsecutivePairs,
    );
    setState(() {
      if (_hasConstraintValue(updated)) {
        draft[weekday] = updated;
      } else {
        draft.remove(weekday);
      }
      _dirtyConstraintDrafts.add(_currentDraftKey);
    });
  }

  void _toggleConstraintDeletion(SubjectLessonConstraint constraint) {
    final draftKey = (
      scope: constraint.scope,
      scopeId: constraint.scopeId,
      stageId: constraint.stageId,
    );
    final entryKey = (
      scope: constraint.scope,
      scopeId: constraint.scopeId,
      stageId: constraint.stageId,
      weekday: constraint.weekday,
    );
    final draft = _loadConstraintDraft(draftKey);
    setState(() {
      final deletedSnapshot = _deletedConstraintSnapshots.remove(entryKey);
      if (deletedSnapshot != null) {
        draft[constraint.weekday] = deletedSnapshot;
      } else {
        final current = draft[constraint.weekday] ?? constraint;
        draft.remove(constraint.weekday);
        final wasPersisted = widget.constraints.any(
          (item) =>
              item.scope == entryKey.scope &&
              item.scopeId == entryKey.scopeId &&
              item.stageId == entryKey.stageId &&
              item.weekday == entryKey.weekday,
        );
        if (wasPersisted) _deletedConstraintSnapshots[entryKey] = current;
      }
      _dirtyConstraintDrafts.add(draftKey);
    });
  }

  List<SubjectLessonConstraint> _constraintsWithDrafts() {
    final result = widget.constraints
        .where(
          (constraint) => !_dirtyConstraintDrafts.any(
            (key) =>
                constraint.scope == key.scope &&
                constraint.scopeId == key.scopeId &&
                constraint.stageId == key.stageId,
          ),
        )
        .toList();
    for (final key in _dirtyConstraintDrafts) {
      for (final constraint in _constraintDrafts[key]!.values) {
        if (_hasConstraintValue(constraint)) result.add(constraint);
      }
    }
    return result;
  }

  String? _constraintValidationMessage() {
    final constraints = _constraintsWithDrafts();
    try {
      SubjectLessonConstraint.validate(constraints);
    } on ArgumentError catch (error) {
      return error.message.toString();
    }

    final affectedScopes =
        <
          ({
            FreeSlotScope scope,
            String scopeId,
            String stageId,
            String? parentGradeId,
          })
        >{};
    for (final key in _dirtyConstraintDrafts) {
      switch (key.scope) {
        case FreeSlotScope.stage:
          affectedScopes.add((
            scope: key.scope,
            scopeId: key.scopeId,
            stageId: key.stageId,
            parentGradeId: null,
          ));
          for (final grade in widget.grades.where(
            (grade) => grade.stageId == key.scopeId,
          )) {
            affectedScopes.add((
              scope: FreeSlotScope.grade,
              scopeId: grade.id,
              stageId: grade.stageId,
              parentGradeId: null,
            ));
            for (final schoolClass in widget.classes.where(
              (schoolClass) => schoolClass.gradeId == grade.id,
            )) {
              affectedScopes.add((
                scope: FreeSlotScope.schoolClass,
                scopeId: schoolClass.id,
                stageId: grade.stageId,
                parentGradeId: grade.id,
              ));
            }
          }
        case FreeSlotScope.grade:
          affectedScopes.add((
            scope: key.scope,
            scopeId: key.scopeId,
            stageId: key.stageId,
            parentGradeId: null,
          ));
          for (final schoolClass in widget.classes.where(
            (schoolClass) => schoolClass.gradeId == key.scopeId,
          )) {
            affectedScopes.add((
              scope: FreeSlotScope.schoolClass,
              scopeId: schoolClass.id,
              stageId: key.stageId,
              parentGradeId: key.scopeId,
            ));
          }
        case FreeSlotScope.schoolClass:
          final parentGradeId = widget.classes
              .where((item) => item.id == key.scopeId)
              .firstOrNull
              ?.gradeId;
          affectedScopes.add((
            scope: key.scope,
            scopeId: key.scopeId,
            stageId: key.stageId,
            parentGradeId: parentGradeId,
          ));
        case FreeSlotScope.school:
          break;
      }
    }

    final resolutionCache =
        <
          ({
            FreeSlotScope scope,
            String scopeId,
            String stageId,
            String? parentGradeId,
            int? weekday,
          }),
          EffectiveSubjectLessonConstraints
        >{};
    EffectiveSubjectLessonConstraints resolve(
      ({
        FreeSlotScope scope,
        String scopeId,
        String stageId,
        String? parentGradeId,
      })
      context,
      int? weekday,
    ) => resolutionCache.putIfAbsent(
      (
        scope: context.scope,
        scopeId: context.scopeId,
        stageId: context.stageId,
        parentGradeId: context.parentGradeId,
        weekday: weekday,
      ),
      () => resolveSubjectLessonConstraints(
        constraints: constraints,
        scope: context.scope,
        scopeId: context.scopeId,
        stageId: context.stageId,
        parentGradeId: context.parentGradeId,
        weekday: weekday,
      ),
    );

    for (final scope in affectedScopes) {
      final weekdays =
          widget.routines[scope.stageId]?.teachingWeekdays ??
          const <int>{1, 2, 3, 4, 5, 6, 7};
      for (final weekday in weekdays) {
        final effective = resolve(scope, weekday);
        if (effective.minimumDailyLessons != null &&
            effective.maximumDailyLessons != null &&
            effective.minimumDailyLessons! > effective.maximumDailyLessons!) {
          return '单日最少课节数不能大于最多课节数';
        }
        if (effective.minimumDailyConsecutivePairs != null &&
            effective.maximumDailyConsecutivePairs != null &&
            effective.minimumDailyConsecutivePairs! >
                effective.maximumDailyConsecutivePairs!) {
          return '单日最少连堂次数不能大于最多连堂次数';
        }
      }
      final weekly = resolve(scope, null);
      if (weekly.minimumWeeklyConsecutivePairs != null &&
          weekly.maximumWeeklyConsecutivePairs != null &&
          weekly.minimumWeeklyConsecutivePairs! >
              weekly.maximumWeeklyConsecutivePairs!) {
        return '每周最少连堂次数不能大于最多连堂次数';
      }
    }
    return null;
  }

  void _showConstraintValidation(String message, {String title = '限制数值有误'}) {
    showAppDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          AppPrimaryButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      maxWidth: 1080,
      title: Text('科目高级设置 · ${widget.subject.name}'),
      content: LayoutBuilder(
        builder: (context, constraints) {
          final isWideLayout = constraints.maxWidth >= 800;
          final scopeTree = _buildScopeTree(scrollable: isWideLayout);
          final editor = _buildEditor(scrollable: isWideLayout);
          if (isWideLayout) {
            return SizedBox(
              width: 1032,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 236, height: 490, child: scopeTree),
                  const SizedBox(width: 16),
                  Expanded(child: editor),
                ],
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [scopeTree, const SizedBox(height: 12), editor],
          );
        },
      ),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppPrimaryButton(onPressed: _save, child: const Text('保存设置')),
      ],
    );
  }

  bool _isCurrentScope(FreeSlotScope scope, String scopeId, String stageId) =>
      scope == _scope && scopeId == _scopeId && stageId == _activeStageId;

  String? get _parentGradeId => _scope == FreeSlotScope.schoolClass
      ? widget.classes.where((row) => row.id == _scopeId).firstOrNull?.gradeId
      : _scope == FreeSlotScope.grade
      ? _scopeId
      : null;

  String _roomSettingSource(FreeSlotScope scope, String id) => switch (scope) {
    FreeSlotScope.stage =>
      '${widget.stages.where((row) => row.id == id).firstOrNull?.name ?? id}（学段）',
    FreeSlotScope.grade =>
      '${widget.grades.where((row) => row.id == id).firstOrNull?.name ?? id}（年级）',
    FreeSlotScope.schoolClass =>
      '${widget.classes.where((row) => row.id == id).firstOrNull?.name ?? id}（班级）',
    FreeSlotScope.school => '',
  };

  void _setRoom(({bool inherit, String? roomId}) choice) {
    setState(() {
      _roomAssignments.removeWhere(
        (row) => _isCurrentScope(row.scope, row.scopeId, row.stageId),
      );
      if (!choice.inherit) {
        _roomAssignments.add(
          SubjectRoomAssignment(
            id: '',
            subjectId: widget.subject.id,
            termId: widget.termId,
            stageId: _activeStageId,
            scope: _scope,
            scopeId: _scopeId,
            roomId: choice.roomId,
          ),
        );
      }
      _roomSettingsDirty = true;
    });
  }

  void _setParallelLimit(String value) {
    setState(() {
      _parallelLimits.removeWhere(
        (row) => _isCurrentScope(row.scope, row.scopeId, row.stageId),
      );
      if (value.isNotEmpty) {
        _parallelLimits.add(
          SubjectParallelLimit(
            id: '',
            subjectId: widget.subject.id,
            termId: widget.termId,
            stageId: _activeStageId,
            scope: _scope,
            scopeId: _scopeId,
            maxParallelLessons: int.tryParse(value) ?? 0,
          ),
        );
      }
      _roomSettingsDirty = true;
    });
  }

  Future<void> _openPublicRooms() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('公共场室')),
          body: PublicRoomsPage(termId: widget.termId),
        ),
      ),
    );
  }

  Widget _advancedSectionHeading({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: context.appColors.selectedBlue,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: context.appColors.blue, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: context.appColors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildRoomsEditor() {
    final roomsAsync = ref.watch(publicRoomsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEditorNote(
          'subject-settings-rooms-description',
          '行课场室按学段、年级、班级逐级生效；可在当前范围覆盖上级设置。修改后点击“保存设置”生效。',
        ),
        const SizedBox(height: 8),
        roomsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => Text('读取公共场室失败：$error'),
          data: (rooms) {
            final local = _roomAssignments
                .where(
                  (row) => _isCurrentScope(row.scope, row.scopeId, row.stageId),
                )
                .firstOrNull;
            final effective = resolveSubjectRoomAssignment(
              assignments: _roomAssignments,
              subjectId: widget.subject.id,
              termId: widget.termId,
              stageId: _activeStageId,
              scope: _scope,
              scopeId: _scopeId,
              parentGradeId: _parentGradeId,
            );
            final roomName = effective?.roomId == null
                ? '不设场室'
                : rooms
                          .where((room) => room.id == effective!.roomId)
                          .firstOrNull
                          ?.name ??
                      '场室已删除，请重置';
            final source = effective == null
                ? '默认设置'
                : _roomSettingSource(effective.scope, effective.scopeId);

            final roomSelector =
                AppSelectField<({bool inherit, String? roomId})>(
                  key: const ValueKey('subject-room-selection'),
                  items: {
                    _scope == FreeSlotScope.stage ? '使用默认设置' : '继承上级场室': (
                      inherit: true,
                      roomId: null,
                    ),
                    '不设场室': (inherit: false, roomId: null),
                    for (final room in rooms)
                      '${room.name}（公共场室）': (inherit: false, roomId: room.id),
                    if (local?.roomId != null &&
                        !rooms.any((room) => room.id == local!.roomId))
                      '场室已删除，请重置': (inherit: false, roomId: local!.roomId),
                  },
                  value: (inherit: local == null, roomId: local?.roomId),
                  onChanged: (value) {
                    if (value != null) _setRoom(value);
                  },
                );
            final resetRoomButton = AppGhostButton(
              key: const ValueKey('subject-room-reset'),
              onPressed: local == null
                  ? null
                  : () => _setRoom((inherit: true, roomId: null)),
              child: Text(_scope == FreeSlotScope.stage ? '重置为默认' : '重置为继承上级'),
            );
            final roomStatus = LayoutBuilder(
              builder: (context, constraints) {
                final roomDetails = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前生效场室',
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roomName,
                      key: const ValueKey('subject-room-effective'),
                      style: TextStyle(
                        color: context.appColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
                final sourceText = Text(
                  '来源：$source',
                  style: TextStyle(
                    color: context.appColors.inkSecondary,
                    fontSize: 12,
                  ),
                );
                if (constraints.maxWidth < 480) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            color: context.appColors.blue,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: roomDetails),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: sourceText,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      color: context.appColors.blue,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: roomDetails),
                    const SizedBox(width: 12),
                    sourceText,
                  ],
                );
              },
            );
            final manageRoomsButton = AppGhostButton(
              key: const ValueKey('subject-public-rooms-entry'),
              onPressed: _openPublicRooms,
              child: Text(
                '管理公共场室',
                style: TextStyle(
                  color: context.appColors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );

            return AppSurface(
              showBorder: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _advancedSectionHeading(
                          icon: Icons.meeting_room_outlined,
                          title: '行课场室',
                          subtitle: '指定该范围上课使用的场室；选择“不设场室”可覆盖上级设置。',
                          trailing: manageRoomsButton,
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              _buildAlignedSettingField(
                                label: '选择场室',
                                field: roomSelector,
                                resetButton: resetRoomButton,
                                compact: constraints.maxWidth < 560,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: context.appColors.tableHeader,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: roomStatus,
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: context.appColors.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _buildParallelLimitEditor(),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildParallelLimitEditor() {
    final local = _parallelLimits
        .where((row) => _isCurrentScope(row.scope, row.scopeId, row.stageId))
        .firstOrNull;
    final effective = resolveSubjectParallelLimit(
      limits: _parallelLimits,
      subjectId: widget.subject.id,
      termId: widget.termId,
      stageId: _activeStageId,
      gradeId: _parentGradeId,
    );
    final source = effective == null
        ? '默认不限'
        : _roomSettingSource(effective.scope, effective.scopeId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _advancedSectionHeading(
          icon: Icons.groups_2_outlined,
          title: '同科目同时上课上限',
          subtitle: '限制同一时段可安排该科目的班级数；年级设置会覆盖学段设置。',
        ),
        const SizedBox(height: 14),
        if (_scope == FreeSlotScope.schoolClass)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: context.appColors.tableHeader,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '当前班级生效上限',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.inkSecondary,
                    ),
                  ),
                ),
                Text(
                  effective?.maxParallelLessons.toString() ?? '不限',
                  style: TextStyle(
                    color: context.appColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (effective != null) ...[
                  const SizedBox(width: 4),
                  Text('班', style: TextStyle(color: context.appColors.muted)),
                ],
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final field = KeyedSubtree(
                key: ValueKey(_currentDraftKey),
                child: f.FTextField(
                  key: const ValueKey('subject-parallel-limit'),
                  control: f.FTextFieldControl.managed(
                    controller: _limitControllers.putIfAbsent(
                      _currentDraftKey,
                      () => TextEditingController(
                        text: local?.maxParallelLessons.toString() ?? '',
                      ),
                    ),
                    onChange: (value) => _setParallelLimit(value.text),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  hint: effective?.maxParallelLessons.toString() ?? '不限',
                  suffixBuilder: (_, _, _) => Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Text(
                      '班',
                      style: TextStyle(
                        color: context.appColors.inkSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
              final reset = AppGhostButton(
                key: const ValueKey('subject-parallel-reset'),
                onPressed: local == null
                    ? null
                    : () {
                        _limitControllers[_currentDraftKey]?.clear();
                        _setParallelLimit('');
                      },
                child: Text(
                  _scope == FreeSlotScope.stage ? '重置为不限' : '重置为继承学段',
                ),
              );
              final currentValue = local == null
                  ? '当前生效：${effective?.maxParallelLessons ?? '不限'} 班'
                  : '本级设置：${local.maxParallelLessons} 班';
              return _buildAlignedSettingField(
                label: '最多同时上课班级数',
                field: field,
                resetButton: reset,
                compact: constraints.maxWidth < 560,
                helper: _scope == FreeSlotScope.stage
                    ? '填写正整数；留空表示不限。'
                    : '填写后替代学段设置；留空使用学段值。',
                footer: Text(
                  '$currentValue；当前来源：$source',
                  key: const ValueKey('subject-parallel-source'),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.muted,
                    height: 1.4,
                  ),
                ),
              );
            },
          ),
        if (_scope == FreeSlotScope.schoolClass) ...[
          const SizedBox(height: 7),
          Text(
            '来源：$source；班级沿用所属年级或学段设置。',
            key: const ValueKey('subject-parallel-source'),
            style: TextStyle(
              fontSize: 12,
              color: context.appColors.muted,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAlignedSettingField({
    required String label,
    required Widget field,
    required Widget resetButton,
    required bool compact,
    String? helper,
    Widget? footer,
  }) {
    final fieldControl = SizedBox(
      width: compact ? null : _advancedSettingFieldWidth,
      child: field,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _advancedSettingLabelStyle),
        const SizedBox(height: 8),
        if (compact) ...[
          SizedBox(width: double.infinity, child: field),
          Align(alignment: Alignment.centerRight, child: resetButton),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [fieldControl, const SizedBox(width: 12), resetButton],
          ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: compact ? double.infinity : _advancedSettingFieldWidth,
            child: Text(helper, style: _advancedSettingHelpStyle),
          ),
        ],
        if (footer != null) ...[
          const SizedBox(height: 5),
          SizedBox(
            width: compact ? double.infinity : _advancedSettingFieldWidth,
            child: footer,
          ),
        ],
      ],
    );
  }

  Widget _buildEditor({required bool scrollable}) {
    final routine = _activeRoutine;
    final weekdays = routine == null
        ? <int>[]
        : routine.teachingWeekdays.toList();
    weekdays.sort();
    final periods = routine == null
        ? <LessonPeriodType>[]
        : routine.periodTypes.toList();
    periods.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelWidth = 88.0;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 720.0;
        final dayWidth = weekdays.isEmpty
            ? 72.0
            : math.max(72.0, (availableWidth - labelWidth) / weekdays.length);
        final tableWidth = labelWidth + dayWidth * weekdays.length;
        var lessonSequence = 0;
        final presetsContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEditorNote(
              'subject-settings-presets-description',
              '预设不区分单双周；空白格为自动。节次和上课日按当前范围学段的作息显示。保存会提交本次修改的范围。',
            ),
            const SizedBox(height: 8),
            if (routine == null)
              SizedBox(
                height: 120,
                child: Center(
                  child: Text(
                    '该学段尚未配置作息，无法编辑预设。',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
            else if (weekdays.isEmpty)
              SizedBox(
                height: 80,
                child: Center(
                  child: Text(
                    '该学段暂无上课日',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      _GridHeader(
                        weekdays: weekdays,
                        labelWidth: labelWidth,
                        dayWidth: dayWidth,
                      ),
                      for (final period in periods)
                        for (
                          var lesson = 1;
                          lesson <=
                              _maxLessonCount(routine, period.id, weekdays);
                          lesson++
                        )
                          _LessonRow(
                            label: period.name.contains('早')
                                ? '早$lesson'
                                : period.name.contains('晚')
                                ? '晚$lesson'
                                : '第 ${++lessonSequence} 节',
                            labelWidth: labelWidth,
                            dayWidth: dayWidth,
                            visual: periodVisualFor(
                              context,
                              period.name,
                              period.sortOrder,
                            ),
                            lessonIndex: lesson,
                            weekdays: weekdays,
                            lessonCounts: {
                              for (final weekday in weekdays)
                                weekday: routine.effectiveLessonCount(
                                  period.id,
                                  weekday,
                                ),
                            },
                            periodTypeId: period.id,
                            grid: _grid,
                            resolveExemption: (weekday, lessonIndex) =>
                                _effectiveFreeSlot(
                                  _currentDraftKey,
                                  weekday,
                                  period.id,
                                  lessonIndex,
                                ),
                            onCycle: _cycleCell,
                            onSet: _setCell,
                            onClear: _clearPresetCell,
                          ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 14),
            _buildAllPresetsSection(),
          ],
        );
        final constraintsContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (routine != null)
              _buildConstraintEditor(
                weekdays: weekdays,
                labelWidth: labelWidth,
                dayWidth: dayWidth,
              ),
            _buildAllLessonConstraintsSection(),
          ],
        );
        Widget settingsTab({
          required int index,
          required String label,
          required String key,
        }) {
          final isSelected = _selectedEditorTabIndex == index;
          return InkWell(
            key: ValueKey(key),
            onTap: () => setState(() {
              _selectedEditorTabIndex = index;
            }),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? context.appColors.surface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? context.appColors.blue
                      : context.appColors.muted,
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        }

        final tabs = DecoratedBox(
          key: const ValueKey('subject-settings-tabs-container'),
          decoration: BoxDecoration(
            color: context.appColors.tableHeader,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                settingsTab(
                  index: 0,
                  label: '科目预设',
                  key: 'subject-settings-tab-presets',
                ),
                settingsTab(
                  index: 1,
                  label: '课节限制',
                  key: 'subject-settings-tab-constraints',
                ),
                settingsTab(
                  index: 2,
                  label: '行课场室',
                  key: 'subject-settings-tab-rooms',
                ),
              ],
            ),
          ),
        );
        final selectedContent = switch (_selectedEditorTabIndex) {
          0 => presetsContent,
          1 => constraintsContent,
          _ => _buildRoomsEditor(),
        };

        if (!scrollable) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tabs,
              Divider(
                key: ValueKey('subject-settings-content-divider'),
                height: 1,
                color: context.appColors.border,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: selectedContent,
              ),
            ],
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 490),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tabs,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(
                      key: ValueKey('subject-settings-content-divider'),
                      height: 1,
                      color: context.appColors.border,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: selectedContent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConstraintEditor({
    required List<int> weekdays,
    required double labelWidth,
    required double dayWidth,
  }) {
    final draft = _loadConstraintDraft(_currentDraftKey);
    final effectiveConstraints = _constraintsWithDrafts();
    final classBrief = _scope == FreeSlotScope.schoolClass
        ? widget.classes.where((item) => item.id == _scopeId).firstOrNull
        : null;
    final width = labelWidth + dayWidth * weekdays.length;
    final resolvedByWeekday = <int?, EffectiveSubjectLessonConstraints>{};

    EffectiveSubjectLessonConstraints resolve(int? weekday) =>
        resolvedByWeekday.putIfAbsent(
          weekday,
          () => resolveSubjectLessonConstraints(
            constraints: effectiveConstraints,
            scope: _scope,
            scopeId: _scopeId,
            stageId: _activeStageId,
            parentGradeId: classBrief?.gradeId,
            weekday: weekday,
          ),
        );

    Widget labelCell(
      String label, {
      bool header = false,
      bool centered = false,
    }) => Container(
      width: labelWidth,
      height: 38,
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: header
            ? context.appColors.tableHeader
            : context.appColors.canvas,
        border: Border(
          right: BorderSide(color: context.appColors.tableDivider),
          bottom: BorderSide(color: context.appColors.tableDivider),
        ),
      ),
      child: Text(
        label,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          color: header
              ? context.appColors.inkSecondary
              : context.appColors.muted,
          fontSize: 11,
          fontWeight: header ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );

    Widget headerCell(String label) => Container(
      width: dayWidth,
      height: 38,
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
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );

    int? localValue(SubjectLessonConstraint? constraint, String field) =>
        switch (field) {
          'minDaily' => constraint?.minimumDailyLessons,
          'maxDaily' => constraint?.maximumDailyLessons,
          'minDailyPairs' => constraint?.minimumDailyConsecutivePairs,
          'maxDailyPairs' => constraint?.maximumDailyConsecutivePairs,
          _ => null,
        };

    int? effectiveValue(
      EffectiveSubjectLessonConstraints constraints,
      String field,
    ) => switch (field) {
      'minDaily' => constraints.minimumDailyLessons,
      'maxDaily' => constraints.maximumDailyLessons,
      'minDailyPairs' => constraints.minimumDailyConsecutivePairs,
      'maxDailyPairs' => constraints.maximumDailyConsecutivePairs,
      _ => null,
    };

    Widget dailyRow(String label, String field, String unit) => Row(
      children: [
        Container(
          width: labelWidth,
          height: 38,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: context.appColors.selectedBlue,
            border: Border(
              right: BorderSide(color: context.appColors.tableDivider),
              bottom: BorderSide(color: context.appColors.tableDivider),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                key: ValueKey('constraint-daily-label-$field'),
                width: 38,
                child: Text(
                  label,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              _constraintInput(
                weekday: null,
                field: field,
                value: localValue(draft[null], field),
                inherited: effectiveValue(resolve(null), field),
                width: 28,
                compact: true,
                dailyCell: true,
              ),
              const SizedBox(width: 2),
              SizedBox(
                key: ValueKey('constraint-daily-unit-$field'),
                width: 12,
                child: Text(
                  unit,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final weekday in weekdays)
          Builder(
            builder: (context) {
              final local = draft[weekday];
              final effective = resolve(weekday);
              final value = localValue(local, field);
              final inherited = effectiveValue(effective, field);
              return Container(
                width: dayWidth,
                height: 38,
                decoration: BoxDecoration(
                  color: context.appColors.selectedBlue,
                  border: Border(
                    right: BorderSide(color: context.appColors.tableDivider),
                    bottom: BorderSide(color: context.appColors.tableDivider),
                  ),
                ),
                child: _constraintInput(
                  weekday: weekday,
                  field: field,
                  value: value,
                  inherited: inherited,
                  width: dayWidth,
                  dailyCell: true,
                ),
              );
            },
          ),
      ],
    );

    final defaultRow = draft[null];
    final weekly = resolve(null);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEditorNote(
              'subject-settings-constraints-description',
              '左侧“每天”值应用于所有上课日；星期输入覆盖该日对应字段。每日连堂按同一天、同一时段内的相邻双节组数计算，连续 3 节计 2 次。每周连堂上下限为全周总量，单双周共用。空白继承上级范围或“每天”设置，0 表示不设下限 / 不允许上限。',
            ),
            Row(
              children: [
                labelCell('每天', header: true, centered: true),
                for (final weekday in weekdays)
                  headerCell(_weekdayLabel(weekday)),
              ],
            ),
            dailyRow('最少', 'minDaily', '节'),
            dailyRow('最多', 'maxDaily', '节'),
            dailyRow('最多连堂', 'maxDailyPairs', '次'),
            dailyRow('最少连堂', 'minDailyPairs', '次'),
            const SizedBox(height: 8),
            Row(
              children: [
                labelCell('每周连堂组数'),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('最少', style: TextStyle(fontSize: 11)),
                        _constraintInput(
                          weekday: null,
                          field: 'minWeekly',
                          value: defaultRow?.minimumWeeklyConsecutivePairs,
                          inherited: weekly.minimumWeeklyConsecutivePairs,
                          width: 72,
                        ),
                        const Text('最多', style: TextStyle(fontSize: 11)),
                        _constraintInput(
                          weekday: null,
                          field: 'maxWeekly',
                          value: defaultRow?.maximumWeeklyConsecutivePairs,
                          inherited: weekly.maximumWeeklyConsecutivePairs,
                          width: 72,
                        ),
                        Text(
                          '同一天、同一时段的相邻双节数',
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _constraintInput({
    required int? weekday,
    required String field,
    required int? value,
    required int? inherited,
    required double width,
    bool compact = false,
    bool dailyCell = false,
  }) => SizedBox(
    width: width,
    height: compact ? 24 : 38,
    child: Padding(
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(3),
      child: TextFormField(
        key: ValueKey(
          'constraint-${_scope.storageValue}-$_scopeId-${weekday ?? 'daily'}-$field',
        ),
        initialValue: value?.toString() ?? '',
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: compact ? 11 : 12),
        decoration: InputDecoration(
          isDense: true,
          hintText: inherited?.toString(),
          hintStyle: TextStyle(
            color: context.appColors.helpIcon,
            fontSize: compact ? 9 : 12,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: compact ? 1 : 5,
            vertical: compact ? 4 : 8,
          ),
          filled: true,
          fillColor: dailyCell
              ? context.appColors.selectedBlue
              : context.appColors.surface,
          border: dailyCell
              ? InputBorder.none
              : OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: context.appColors.border),
                ),
          enabledBorder: dailyCell
              ? InputBorder.none
              : OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: context.appColors.border),
                ),
          focusedBorder: dailyCell
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: context.appColors.blue),
                )
              : OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: context.appColors.blue,
                    width: 1.4,
                  ),
                ),
        ),
        onChanged: (value) => _updateConstraintField(weekday, field, value),
      ),
    ),
  );

  String _weekdayLabel(int weekday) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

  Widget _buildEditorNote(String key, String text) => Padding(
    key: ValueKey('$key-padding'),
    padding: const EdgeInsets.fromLTRB(0, 2, 0, 10),
    child: Text(
      text,
      key: ValueKey(key),
      style: TextStyle(
        color: context.appColors.inkSecondary,
        fontSize: 12,
        height: 1.5,
      ),
    ),
  );

  Widget _buildAllPresetsSection() {
    final entries = _allPresetEntries();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: context.appColors.border),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            Text(
              '当前学科全部预设',
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${entries.length} 项',
              style: TextStyle(color: context.appColors.muted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              '暂无预设',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.muted, fontSize: 12),
            ),
          )
        else
          for (final entry in entries) ...[
            if (entry != entries.first)
              Divider(height: 1, color: context.appColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.rangeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.appColors.ink,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  decoration: entry.deleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (entry.pending || entry.deleted) ...[
                              const SizedBox(width: 6),
                              Text(
                                entry.deleted ? '待删除' : '未保存',
                                style: TextStyle(
                                  color: entry.deleted
                                      ? context.appColors.destructive
                                      : context.appColors.warning,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          entry.cellLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.valueLabel,
                    style: TextStyle(
                      color: context.appColors.inkSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      'preset-delete-${entry.key.scope.name}-${entry.key.scopeId}-${entry.key.stageId}-${entry.key.weekday}-${entry.key.periodTypeId}-${entry.key.lessonIndex}',
                    ),
                    tooltip: entry.deleted ? '撤销删除' : '删除预设',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    onPressed: () => _togglePresetDeletion(entry.key),
                    icon: Icon(
                      entry.deleted ? Icons.undo : Icons.delete_outline,
                      color: entry.deleted
                          ? context.appColors.warning
                          : context.appColors.destructive,
                    ),
                  ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  Widget _buildAllLessonConstraintsSection() {
    final entries = _allConstraintEntries();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: context.appColors.border),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            Text(
              '当前科目全部课节限制',
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${entries.length} 项',
              style: TextStyle(color: context.appColors.muted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              '暂无课节限制',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.muted, fontSize: 12),
            ),
          )
        else
          for (final entry in entries) ...[
            if (entry != entries.first)
              Divider(height: 1, color: context.appColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.rangeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.appColors.ink,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  decoration: entry.deleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (entry.pending || entry.deleted) ...[
                              const SizedBox(width: 6),
                              Text(
                                entry.deleted ? '待删除' : '未保存',
                                style: TextStyle(
                                  color: entry.deleted
                                      ? context.appColors.destructive
                                      : context.appColors.warning,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          entry.ruleLabel,
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: ValueKey(
                      'constraint-delete-${entry.key.scope.name}-${entry.key.scopeId}-${entry.key.stageId}-${entry.key.weekday ?? 'daily'}',
                    ),
                    tooltip: entry.deleted ? '撤销删除' : '删除限制',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    onPressed: () =>
                        _toggleConstraintDeletion(entry.constraint),
                    icon: Icon(
                      entry.deleted ? Icons.undo : Icons.delete_outline,
                      color: entry.deleted
                          ? context.appColors.warning
                          : context.appColors.destructive,
                    ),
                  ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  List<_ConstraintListEntry> _allConstraintEntries() {
    final stageById = {for (final stage in widget.stages) stage.id: stage};
    final gradeById = {for (final grade in widget.grades) grade.id: grade};
    final classById = {for (final item in widget.classes) item.id: item};
    final entries = <_ConstraintEntryKey, _ConstraintListEntry>{};

    void addEntry(SubjectLessonConstraint constraint, {bool deleted = false}) {
      final stage = stageById[constraint.stageId];
      final stageLabel = stage?.name ?? constraint.stageId;
      final grade = switch (constraint.scope) {
        FreeSlotScope.grade => gradeById[constraint.scopeId],
        FreeSlotScope.schoolClass =>
          gradeById[classById[constraint.scopeId]?.gradeId],
        _ => null,
      };
      final classBrief = constraint.scope == FreeSlotScope.schoolClass
          ? classById[constraint.scopeId]
          : null;
      final rangeLabel = switch (constraint.scope) {
        FreeSlotScope.school => '$stageLabel · 全校范围',
        FreeSlotScope.stage => stageLabel,
        FreeSlotScope.grade =>
          '$stageLabel · ${grade?.name ?? constraint.scopeId}',
        FreeSlotScope.schoolClass =>
          '$stageLabel · ${grade?.name ?? ''} · ${classBrief?.name ?? constraint.scopeId}',
      };
      final dailyRules = <String>[
        if (constraint.minimumDailyLessons case final value?) '最少 $value 节',
        if (constraint.maximumDailyLessons case final value?) '最多 $value 节',
        if (constraint.minimumDailyConsecutivePairs case final value?)
          '最少连堂 $value 次',
        if (constraint.maximumDailyConsecutivePairs case final value?)
          '最多连堂 $value 次',
      ];
      final weeklyRules = <String>[
        if (constraint.minimumWeeklyConsecutivePairs case final value?)
          '最少 $value 次',
        if (constraint.maximumWeeklyConsecutivePairs case final value?)
          '最多 $value 次',
      ];
      final ruleParts = <String>[
        if (dailyRules.isNotEmpty)
          '${constraint.weekday == null ? '每天' : _weekdayLabel(constraint.weekday!)} · ${dailyRules.join(' · ')}',
        if (weeklyRules.isNotEmpty) '每周连堂 ${weeklyRules.join(' · ')}',
      ];
      final original = widget.constraints
          .where(
            (item) =>
                _constraintEntryKey(item) == _constraintEntryKey(constraint),
          )
          .firstOrNull;
      final pending =
          deleted ||
          original == null ||
          !_sameConstraintValues(original, constraint);
      final scopeOrder = switch (constraint.scope) {
        FreeSlotScope.school => 0,
        FreeSlotScope.stage => 1,
        FreeSlotScope.grade => 2,
        FreeSlotScope.schoolClass => 3,
      };
      final key = _constraintEntryKey(constraint);
      entries[key] = (
        key: key,
        constraint: constraint,
        rangeLabel: rangeLabel,
        ruleLabel: ruleParts.join('；'),
        pending: pending,
        deleted: deleted,
        stageOrder: stage?.sortOrder ?? 0,
        scopeOrder: scopeOrder,
      );
    }

    for (final constraint in _constraintsWithDrafts()) {
      addEntry(constraint);
    }
    for (final constraint in _deletedConstraintSnapshots.values) {
      addEntry(constraint, deleted: true);
    }

    return entries.values.toList()..sort((a, b) {
      var order = a.stageOrder.compareTo(b.stageOrder);
      if (order != 0) return order;
      order = a.scopeOrder.compareTo(b.scopeOrder);
      if (order != 0) return order;
      order = a.rangeLabel.compareTo(b.rangeLabel);
      if (order != 0) return order;
      return (a.key.weekday ?? 0).compareTo(b.key.weekday ?? 0);
    });
  }

  _ConstraintEntryKey _constraintEntryKey(SubjectLessonConstraint constraint) =>
      (
        scope: constraint.scope,
        scopeId: constraint.scopeId,
        stageId: constraint.stageId,
        weekday: constraint.weekday,
      );

  bool _sameConstraintValues(
    SubjectLessonConstraint first,
    SubjectLessonConstraint second,
  ) =>
      first.minimumDailyLessons == second.minimumDailyLessons &&
      first.maximumDailyLessons == second.maximumDailyLessons &&
      first.minimumDailyConsecutivePairs ==
          second.minimumDailyConsecutivePairs &&
      first.maximumDailyConsecutivePairs ==
          second.maximumDailyConsecutivePairs &&
      first.minimumWeeklyConsecutivePairs ==
          second.minimumWeeklyConsecutivePairs &&
      first.maximumWeeklyConsecutivePairs ==
          second.maximumWeeklyConsecutivePairs;

  List<_PresetListEntry> _allPresetEntries() {
    final stageById = {for (final stage in widget.stages) stage.id: stage};
    final gradeById = {for (final grade in widget.grades) grade.id: grade};
    final classById = {for (final item in widget.classes) item.id: item};
    final stageIds = stageById.keys.toSet();
    final entries = <_PresetEntryKey, _PresetListEntry>{};

    void addEntry({
      required FreeSlotScope scope,
      required String scopeId,
      required String stageId,
      required int weekday,
      required String periodTypeId,
      required int lessonIndex,
      required PresetValue value,
      required bool pending,
      bool deleted = false,
    }) {
      final stage = stageById[stageId];
      if (stage == null) return;
      final grade = scope == FreeSlotScope.grade
          ? gradeById[scopeId]
          : scope == FreeSlotScope.schoolClass
          ? gradeById[classById[scopeId]?.gradeId]
          : null;
      final classBrief = scope == FreeSlotScope.schoolClass
          ? classById[scopeId]
          : null;
      final scopeOrder = switch (scope) {
        FreeSlotScope.school => 0,
        FreeSlotScope.stage => 1,
        FreeSlotScope.grade => 2,
        FreeSlotScope.schoolClass => 3,
      };
      final rangeLabel = switch (scope) {
        // 旧数据继续可见，但不再把“全校”作为可选择的应用范围。
        FreeSlotScope.school => '${stage.name} · 历史预设',
        FreeSlotScope.stage => stage.name,
        FreeSlotScope.grade => '${stage.name} · ${grade?.name ?? scopeId}',
        FreeSlotScope.schoolClass =>
          '${stage.name} · ${grade?.name ?? ''} · ${classBrief?.name ?? scopeId}',
      };
      final routine = widget.routines[stageId];
      final periodName =
          routine?.periodTypes
              .where((period) => period.id == periodTypeId)
              .firstOrNull
              ?.name ??
          periodTypeId;
      final weekdays = const {
        1: '周一',
        2: '周二',
        3: '周三',
        4: '周四',
        5: '周五',
        6: '周六',
        7: '周日',
      };
      final periodOrder =
          routine?.periodTypes
              .where((period) => period.id == periodTypeId)
              .firstOrNull
              ?.sortOrder ??
          0;
      final key = (
        scope: scope,
        scopeId: scopeId,
        stageId: stageId,
        weekday: weekday,
        periodTypeId: periodTypeId,
        lessonIndex: lessonIndex,
      );
      entries[key] = (
        key: key,
        rangeLabel: rangeLabel,
        cellLabel:
            '${weekdays[weekday] ?? '星期$weekday'} $periodName 第 $lessonIndex 节',
        valueLabel: value == PresetValue.auto ? '自动（覆盖）' : '${value.label}（预设）',
        pending: pending,
        deleted: deleted,
        stageOrder: stage.sortOrder,
        scopeOrder: scopeOrder,
        weekday: weekday,
        periodOrder: periodOrder,
        lessonIndex: lessonIndex,
      );
    }

    for (final preset in widget.presets) {
      if (!stageIds.contains(preset.stageId)) continue;
      addEntry(
        scope: preset.scope,
        scopeId: preset.scopeId,
        stageId: preset.stageId,
        weekday: preset.weekday,
        periodTypeId: preset.periodTypeId,
        lessonIndex: preset.lessonIndex,
        value: preset.value,
        pending: false,
        deleted:
            _deletedCells[(
                  scope: preset.scope,
                  scopeId: preset.scopeId,
                  stageId: preset.stageId,
                )]
                ?.contains(
                  presetCellKey(
                    preset.weekday,
                    preset.periodTypeId,
                    preset.lessonIndex,
                  ),
                ) ??
            false,
      );
    }

    for (final draftKey in _dirtyDrafts) {
      final draft = _drafts[draftKey];
      if (draft == null) continue;
      for (final cellKey in _changedCells[draftKey] ?? const <String>{}) {
        if ((_deletedCells[draftKey] ?? const <String>{}).contains(cellKey)) {
          continue;
        }
        final address = _decodePresetCellKey(cellKey);
        final value = draft[cellKey];
        if (address == null || value == null) continue;
        addEntry(
          scope: draftKey.scope,
          scopeId: draftKey.scopeId,
          stageId: draftKey.stageId,
          weekday: address.weekday,
          periodTypeId: address.periodTypeId,
          lessonIndex: address.lessonIndex,
          value: value,
          pending: true,
        );
      }
    }

    for (final draftKey in _dirtyDrafts) {
      for (final cellKey in _deletedCells[draftKey] ?? const <String>{}) {
        final address = _decodePresetCellKey(cellKey);
        if (address == null) continue;
        final entryKey = (
          scope: draftKey.scope,
          scopeId: draftKey.scopeId,
          stageId: draftKey.stageId,
          weekday: address.weekday,
          periodTypeId: address.periodTypeId,
          lessonIndex: address.lessonIndex,
        );
        if (entries.containsKey(entryKey)) continue;
        final value = _deletedSnapshots[draftKey]?[cellKey]?.value;
        addEntry(
          scope: draftKey.scope,
          scopeId: draftKey.scopeId,
          stageId: draftKey.stageId,
          weekday: address.weekday,
          periodTypeId: address.periodTypeId,
          lessonIndex: address.lessonIndex,
          value: value ?? PresetValue.auto,
          pending: false,
          deleted: true,
        );
      }
    }

    final result = entries.values.toList()
      ..sort((a, b) {
        var order = a.stageOrder.compareTo(b.stageOrder);
        if (order != 0) return order;
        order = a.scopeOrder.compareTo(b.scopeOrder);
        if (order != 0) return order;
        order = a.rangeLabel.compareTo(b.rangeLabel);
        if (order != 0) return order;
        order = a.weekday.compareTo(b.weekday);
        if (order != 0) return order;
        order = a.periodOrder.compareTo(b.periodOrder);
        if (order != 0) return order;
        return a.lessonIndex.compareTo(b.lessonIndex);
      });
    return result;
  }

  _PresetCellAddress? _decodePresetCellKey(String key) {
    final parts = key.split('_');
    if (parts.length < 3) return null;
    final weekday = int.tryParse(parts.first);
    final lessonIndex = int.tryParse(parts.last);
    if (weekday == null || lessonIndex == null) return null;
    return (
      weekday: weekday,
      periodTypeId: parts.sublist(1, parts.length - 1).join('_'),
      lessonIndex: lessonIndex,
    );
  }

  int _maxLessonCount(
    StageRoutine routine,
    String periodId,
    List<int> weekdays,
  ) {
    var result = 0;
    for (final weekday in weekdays) {
      final count = routine.effectiveLessonCount(periodId, weekday);
      if (count > result) result = count;
    }
    return result;
  }

  Widget _buildScopeTree({required bool scrollable}) => AppSectionPanel(
    title: '应用范围',
    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
    expandChild: scrollable,
    child: scrollable
        ? SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final stage in _orderedStages) _buildStageNode(stage),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final stage in _orderedStages) _buildStageNode(stage),
            ],
          ),
  );

  Widget _buildStageNode(SchoolStage stage) {
    final expanded = _expandedStageIds.contains(stage.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTreeTile(
          key: ValueKey('preset-scope-stage-${stage.id}'),
          height: 30,
          contentPadding: const EdgeInsets.only(left: 8, right: 8),
          title: Text(stage.name, style: const TextStyle(fontSize: 13)),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                key: ValueKey('preset-expand-stage-${stage.id}'),
                onTap: () => setState(() {
                  if (expanded) {
                    _expandedStageIds.remove(stage.id);
                  } else {
                    _expandedStageIds.add(stage.id);
                  }
                }),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: context.appColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.layers_outlined,
                size: 15,
                color: context.appColors.sidebarMuted,
              ),
            ],
          ),
          isSelected: _activeStageId == stage.id,
          onTap: () => _selectScope(
            scope: FreeSlotScope.stage,
            scopeId: stage.id,
            stageId: stage.id,
          ),
        ),
        if (expanded)
          for (final grade in _gradesForStage(stage.id)) _buildGradeNode(grade),
      ],
    );
  }

  Widget _buildGradeNode(GradeGroup grade) {
    final expanded = _expandedGradeIds.contains(grade.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTreeTile(
          key: ValueKey('preset-scope-grade-${grade.id}'),
          height: 28,
          contentPadding: const EdgeInsets.only(left: 20, right: 8),
          title: Text(grade.name, style: const TextStyle(fontSize: 12)),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                key: ValueKey('preset-expand-grade-${grade.id}'),
                onTap: () => setState(() {
                  if (expanded) {
                    _expandedGradeIds.remove(grade.id);
                  } else {
                    _expandedGradeIds.add(grade.id);
                  }
                }),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 13,
                    color: context.appColors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.school_outlined, size: 14),
            ],
          ),
          isSelected: _scope == FreeSlotScope.grade && _scopeId == grade.id,
          onTap: () => _selectScope(
            scope: FreeSlotScope.grade,
            scopeId: grade.id,
            stageId: grade.stageId,
          ),
        ),
        if (expanded)
          for (final classBrief in _classesForGrade(grade.id))
            AppTreeTile(
              key: ValueKey('preset-scope-class-${classBrief.id}'),
              height: 26,
              contentPadding: const EdgeInsets.only(left: 8, right: 8),
              title: Text(
                classBrief.name,
                style: const TextStyle(fontSize: 11),
              ),
              leading: const Padding(
                padding: EdgeInsets.only(left: 26),
                child: Icon(Icons.class_outlined, size: 13),
              ),
              isSelected:
                  _scope == FreeSlotScope.schoolClass &&
                  _scopeId == classBrief.id,
              onTap: () => _selectScope(
                scope: FreeSlotScope.schoolClass,
                scopeId: classBrief.id,
                stageId: classBrief.stageId,
              ),
            ),
      ],
    );
  }
}

class _GridHeader extends StatelessWidget {
  const _GridHeader({
    required this.weekdays,
    required this.labelWidth,
    required this.dayWidth,
  });

  final List<int> weekdays;
  final double labelWidth;
  final double dayWidth;

  static const List<String> _weekdayNames = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _heading(context, '节次', labelWidth, 11),
      for (final weekday in weekdays)
        _heading(context, _weekdayNames[weekday - 1], dayWidth, 12),
    ],
  );

  Widget _heading(
    BuildContext context,
    String label,
    double width,
    double fontSize,
  ) => Container(
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
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.label,
    required this.labelWidth,
    required this.dayWidth,
    required this.visual,
    required this.lessonIndex,
    required this.weekdays,
    required this.lessonCounts,
    required this.periodTypeId,
    required this.grid,
    required this.resolveExemption,
    required this.onCycle,
    required this.onSet,
    required this.onClear,
  });

  final String label;
  final double labelWidth;
  final double dayWidth;
  final PeriodVisual visual;
  final int lessonIndex;
  final List<int> weekdays;
  final Map<int, int> lessonCounts;
  final String periodTypeId;
  final Map<String, PresetValue> grid;
  final FreeSlot? Function(int weekday, int lessonIndex) resolveExemption;
  final void Function(int weekday, String periodTypeId, int lessonIndex)
  onCycle;
  final void Function(
    int weekday,
    String periodTypeId,
    int lessonIndex,
    PresetValue value,
  )
  onSet;
  final void Function(int weekday, String periodTypeId, int lessonIndex)
  onClear;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: labelWidth,
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: visual.labelTint,
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
            color: visual.color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      for (final weekday in weekdays)
        if (lessonIndex > (lessonCounts[weekday] ?? 0))
          Container(
            width: dayWidth,
            height: 44,
            decoration: BoxDecoration(
              color: visual.cellTint,
              border: Border(
                right: BorderSide(color: context.appColors.tableDivider),
                bottom: BorderSide(color: context.appColors.tableDivider),
              ),
            ),
          )
        else
          _PresetCell(
            key: ValueKey('preset-cell-$weekday-$periodTypeId-$lessonIndex'),
            width: dayWidth,
            tint: visual.cellTint,
            exemptLabel: resolveExemption(weekday, lessonIndex)?.label,
            value:
                grid[presetCellKey(weekday, periodTypeId, lessonIndex)] ??
                PresetValue.auto,
            onCycle: () => onCycle(weekday, periodTypeId, lessonIndex),
            onSet: (value) => onSet(weekday, periodTypeId, lessonIndex, value),
            onClear: () => onClear(weekday, periodTypeId, lessonIndex),
          ),
    ],
  );
}

class _PresetCell extends StatelessWidget {
  const _PresetCell({
    required this.value,
    required this.onCycle,
    required this.onSet,
    required this.onClear,
    required this.width,
    required this.tint,
    this.exemptLabel,
    super.key,
  });

  final PresetValue value;
  final double width;
  final Color tint;
  final VoidCallback onCycle;
  final ValueChanged<PresetValue> onSet;
  final VoidCallback onClear;
  final String? exemptLabel;

  @override
  Widget build(BuildContext context) {
    if (exemptLabel != null) {
      return Tooltip(
        message: '免任课：$exemptLabel',
        child: Container(
          width: width,
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
            exemptLabel!,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.appColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    final (background, foreground) = switch (value) {
      // 自动延续作息表格的时段底色；预设用状态色区分。
      PresetValue.auto => (tint, context.appColors.muted),
      // 尽量排 = 软性优先：淡蓝底 + 蓝字。
      PresetValue.prefer => (
        context.appColors.selectedBlue,
        context.appColors.blue,
      ),
      // 一定排 = 硬性必须：实蓝底 + 白字。
      PresetValue.must => (
        context.appColors.blue,
        Theme.of(context).colorScheme.onPrimary,
      ),
      // 不排 = 硬性禁止：淡红底 + 红字。
      PresetValue.forbid => (
        context.appColors.destructiveSurface,
        context.appColors.destructive,
      ),
    };
    final cell = InkWell(
      onTap: onCycle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
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
        child: value == PresetValue.auto
            ? null
            : Text(
                value.label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: value == PresetValue.must
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
      ),
    );
    return f.FContextMenu(
      menuBuilder: (context, controller, menu) => [
        f.FItemGroup(
          divider: .none,
          children: [
            for (final preset in PresetValue.values)
              AppMenuTile(
                item: AppMenuItem(
                  label: preset.label,
                  selected: preset == value,
                  onPressed: () {
                    unawaited(controller.hide());
                    onSet(preset);
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
                label: '清除预设',
                onPressed: () {
                  unawaited(controller.hide());
                  onClear();
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
