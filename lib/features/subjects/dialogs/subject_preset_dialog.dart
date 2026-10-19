import 'dart:async';

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

/// 科目预设弹窗（US-015 / 设计稿 03b）。
///
/// 节次 × 周一~周五 四态方格：单击在 自动 → 尽量排 → 一定排 → 不排
/// 间循环，右键直选；范围四级（全校 / 学段 / 年级 / 班级），默认矩阵
/// 当前列；预设不区分单双周；「一定排」格数超过该周需求节数时，
/// 保存按周次列出警告（AC6）。
class SubjectPresetDialog extends StatefulWidget {
  const SubjectPresetDialog({
    required this.subject,
    required this.termId,
    required this.stage,
    required this.grade,
    required this.classes,
    required this.routine,
    required this.presets,
    required this.classDemands,
    super.key,
  });

  final Subject subject;
  final String termId;
  final SchoolStage stage;
  final GradeGroup grade;

  /// 当前年级的班级（供班级级范围与容量警告使用）。
  final List<ClassBrief> classes;
  final StageRoutine routine;

  /// 该科目全部预设行。
  final List<SubjectPreset> presets;

  /// 班级 ID → 单 / 双周需求节数（用于 AC6 警告）。
  final Map<String, ClassSubjectValues> classDemands;

  @override
  State<SubjectPresetDialog> createState() => _SubjectPresetDialogState();
}

class _SubjectPresetDialogState extends State<SubjectPresetDialog> {
  late _ScopeOption _scope;
  late Map<String, PresetValue> _grid;

  @override
  void initState() {
    super.initState();
    // 默认矩阵当前列（年级）。
    _scope = _ScopeOption(
      scope: FreeSlotScope.grade,
      scopeId: widget.grade.id,
      label: '${widget.grade.name}（矩阵当前列）',
    );
    _grid = _effectiveForScope();
  }

  Map<String, PresetValue> _effectiveForScope() => effectivePresetMap(
    presets: widget.presets,
    stageId: widget.stage.id,
    scope: _scope.scope,
    scopeId: _scope.scopeId,
  );

  List<_ScopeOption> get _scopeOptions => [
    const _ScopeOption(
      scope: FreeSlotScope.school,
      scopeId: '',
      label: '全校（对本未单独设置的年级生效）',
    ),
    _ScopeOption(
      scope: FreeSlotScope.stage,
      scopeId: widget.stage.id,
      label: '${widget.stage.name}（本学段）',
    ),
    _ScopeOption(
      scope: FreeSlotScope.grade,
      scopeId: widget.grade.id,
      label: '${widget.grade.name}（矩阵当前列）',
    ),
    for (final classBrief in widget.classes)
      _ScopeOption(
        scope: FreeSlotScope.schoolClass,
        scopeId: classBrief.id,
        label: '${classBrief.name}（精确到班）',
      ),
  ];

  /// 实际写入的 scopeId：全校用学期 ID。
  String get _effectiveScopeId =>
      _scope.scope == FreeSlotScope.school ? widget.termId : _scope.scopeId;

  void _cycleCell(int weekday, String periodTypeId, int lessonIndex) {
    final key = presetCellKey(weekday, periodTypeId, lessonIndex);
    setState(() {
      final current = _grid[key] ?? PresetValue.auto;
      _grid[key] = current.next;
    });
  }

  void _setCell(int weekday, String periodTypeId, int lessonIndex, PresetValue value) {
    final key = presetCellKey(weekday, periodTypeId, lessonIndex);
    setState(() => _grid[key] = value);
  }

  /// 「一定排」格数超过该周需求节数的班级（AC6）。
  List<String> _overDemandWarnings() {
    final mustCount = _grid.values
        .where((value) => value == PresetValue.must)
        .length;
    if (mustCount == 0) return const [];
    final warnings = <String>[];
    for (final classBrief in widget.classes) {
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

  Future<void> _save() async {
    final warnings = _overDemandWarnings();
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
                      style: const TextStyle(
                        color: AppTheme.destructive,
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
    final weekdays = widget.routine.teachingWeekdays.toList()..sort();
    final periods = widget.routine.periodTypes.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final cells = <PresetCell>[];
    for (final period in periods) {
      for (var lesson = 1; lesson <= period.defaultLessonCount; lesson++) {
        for (final weekday in weekdays) {
          final value =
              _grid[presetCellKey(weekday, period.id, lesson)] ??
              PresetValue.auto;
          if (value == PresetValue.auto) continue;
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
    Navigator.pop(context, (
      scope: _scope.scope,
      scopeId: _effectiveScopeId,
      cells: cells,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final weekdays = widget.routine.teachingWeekdays.toList()..sort();
    final periods = widget.routine.periodTypes.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final scopeItems = {
      for (final option in _scopeOptions) option.label: option.label,
    };
    return AppDialog(
      maxWidth: 680,
      title: Row(
        children: [
          Expanded(child: Text('科目预设 · ${widget.subject.name}')),
          SizedBox(
            width: 220,
            child: AppSelectField<String>(
              items: scopeItems,
              value: _scope.label,
              onChanged: (label) {
                if (label == null) return;
                final option = _scopeOptions.firstWhere(
                  (item) => item.label == label,
                );
                setState(() {
                  _scope = option;
                  _grid = _effectiveForScope();
                });
              },
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '预设不区分单双周（同一格对两种周次均生效）；「一定排」超出该周需求节数时，保存按周次列出警告。',
              style: TextStyle(color: AppTheme.muted, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            // AppDialog 的 content 处于无界高度（外层可滚动），网格需自带
            // 有界高度，不能用 Flexible（会触发 unbounded constraints 断言）。
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GridHeader(weekdays: weekdays),
                    for (final period in periods) ...[
                      if (period.defaultLessonCount > 0) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 2),
                          child: Text(
                            period.name,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (var lesson = 1;
                            lesson <= period.defaultLessonCount;
                            lesson++)
                          _LessonRow(
                            lessonIndex: lesson,
                            weekdays: weekdays,
                            periodTypeId: period.id,
                            grid: _grid,
                            onCycle: _cycleCell,
                            onSet: _setCell,
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                AppGhostButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 10),
                AppPrimaryButton(
                  onPressed: _save,
                  child: const Text('保存预设'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopeOption {
  const _ScopeOption({
    required this.scope,
    required this.scopeId,
    required this.label,
  });

  final FreeSlotScope scope;

  /// 全校范围在保存时替换为学期 ID（此处固定为空串以保持值语义一致）。
  final String scopeId;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is _ScopeOption &&
      other.scope == scope &&
      other.scopeId == scopeId;

  @override
  int get hashCode => Object.hash(scope, scopeId);
}

class _GridHeader extends StatelessWidget {
  const _GridHeader({required this.weekdays});

  final List<int> weekdays;

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
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppTheme.border)),
    ),
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        const SizedBox(
          width: 52,
          child: Text(
            '节次',
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final weekday in weekdays)
          Expanded(
            child: Center(
              child: Text(
                _weekdayNames[weekday - 1],
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.lessonIndex,
    required this.weekdays,
    required this.periodTypeId,
    required this.grid,
    required this.onCycle,
    required this.onSet,
  });

  final int lessonIndex;
  final List<int> weekdays;
  final String periodTypeId;
  final Map<String, PresetValue> grid;
  final void Function(int weekday, String periodTypeId, int lessonIndex)
  onCycle;
  final void Function(int weekday, String periodTypeId, int lessonIndex, PresetValue value)
  onSet;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            '第 $lessonIndex 节',
            style: const TextStyle(color: AppTheme.inkSecondary, fontSize: 12),
          ),
        ),
        for (final weekday in weekdays)
          Expanded(
            child: _PresetCell(
              key: ValueKey('preset-cell-$weekday-$periodTypeId-$lessonIndex'),
              value:
                  grid[presetCellKey(weekday, periodTypeId, lessonIndex)] ??
                  PresetValue.auto,
              onCycle: () => onCycle(weekday, periodTypeId, lessonIndex),
              onSet: (value) =>
                  onSet(weekday, periodTypeId, lessonIndex, value),
            ),
          ),
      ],
    ),
  );
}

class _PresetCell extends StatelessWidget {
  const _PresetCell({
    required this.value,
    required this.onCycle,
    required this.onSet,
    super.key,
  });

  final PresetValue value;
  final VoidCallback onCycle;
  final ValueChanged<PresetValue> onSet;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (value) {
      // 自动 = 无偏好（空态）：仅浅边框的空白格（设计稿），网格可见可点。
      PresetValue.auto => (Colors.transparent, AppTheme.muted, AppTheme.border),
      // 尽量排 = 软性优先：淡蓝底 + 蓝字。
      PresetValue.prefer => (
        AppTheme.selectedBlue,
        AppTheme.blue,
        AppTheme.selectedBlue,
      ),
      // 一定排 = 硬性必须：实蓝底 + 白字。
      PresetValue.must => (AppTheme.blue, Colors.white, AppTheme.blue),
      // 不排 = 硬性禁止：淡红底 + 红字。
      PresetValue.forbid => (
        AppTheme.destructiveSurface,
        AppTheme.destructive,
        AppTheme.destructiveSurface,
      ),
    };
    final cell = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onCycle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
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
      ],
      child: cell,
    );
  }
}
