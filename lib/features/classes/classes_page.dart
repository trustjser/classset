import 'dart:async';

import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/features/classes/grade_name_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

/// 预置学段名称（US-001 AC1）。
const stagePresets = ['小学部', '初中部', '高中部'];

Color _stageAccent(BuildContext context, int index) => switch (index % 3) {
  0 => context.appColors.blue,
  1 => context.appColors.success,
  _ => context.appColors.warning,
};

Color _stageTint(BuildContext context, int index) => Color.alphaBlend(
  _stageAccent(context, index).withValues(alpha: .1),
  context.appColors.surface,
);

Color _stageChipBorder(BuildContext context, int index) => Color.alphaBlend(
  _stageAccent(context, index).withValues(alpha: .34),
  context.appColors.surface,
);

class ClassesPage extends ConsumerStatefulWidget {
  const ClassesPage({required this.termId, super.key});

  final String termId;

  @override
  ConsumerState<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends ConsumerState<ClassesPage> {
  String? _selectedStageId;

  /// 最近一次批量填充的快照，用于「撤销上次填充」。
  List<({ClassGroup before, String after})>? _lastFillUndo;

  @override
  Widget build(BuildContext context) {
    final stages = ref.watch(stagesProvider(widget.termId));
    return stages.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: SelectableText('读取学段失败：$error')),
      data: (items) {
        if (items.isEmpty) {
          return _EmptyStages(onAdd: () => _addStage(items));
        }
        final matching = items
            .where((stage) => stage.id == _selectedStageId)
            .toList();
        final selectedStage = matching.isEmpty ? items.first : matching.first;
        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = AppTheme.pagePaddingForWidth(
              constraints.maxWidth,
            );
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                22,
                horizontalPadding,
                30,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Toolbar(),
                  const SizedBox(height: 20),
                  _StageCardRow(
                    stages: items,
                    onRename: (stage) => _editStage(context, ref, stage),
                    onDelete: (stage) => _deleteStage(context, ref, stage),
                    onAddStage: () => _addStage(items),
                    canDelete: items.length > 1,
                  ),
                  const SizedBox(height: 16),
                  _GradeClassTable(
                    stages: items,
                    onBatchFillHeader: () =>
                        _openBatchFill(items, selectedStage.id),
                    onAddGrade: () => _addGrades(context, ref, items),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addStage(List<SchoolStage> stages) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        return Transform.translate(
          offset: Offset(size.width >= 520 ? size.width / 2 - 270 : 0, -55),
          child: _StageNameDialog(
            existingNames: stages.map((stage) => stage.name).toSet(),
          ),
        );
      },
    );
    if (result == null || !context.mounted) return;
    final stage = SchoolStage(
      id: _newId(),
      termId: widget.termId,
      name: result,
      sortOrder: stages.length,
    );
    await _runSave(() => ref.read(schoolRepositoryProvider).saveStage(stage));
    if (mounted) setState(() => _selectedStageId = stage.id);
  }

  Future<void> _openBatchFill(
    List<SchoolStage> stages,
    String defaultStageId,
  ) async {
    final result = await showDialog<_BatchFillResult>(
      context: context,
      builder: (context) {
        final width = MediaQuery.sizeOf(context).width;
        return Transform.translate(
          offset: Offset(width >= 1158 ? 580 - width / 2 : 0, -32),
          child: _BatchFillNamesDialog(
            stages: stages,
            defaultStageId: defaultStageId,
            canUndo: _lastFillUndo != null,
          ),
        );
      },
    );
    if (result == null || !context.mounted) return;
    if (result.undo) {
      await _undoLastFill();
      return;
    }
    await _applyBatchFill(result);
  }

  Future<void> _applyBatchFill(_BatchFillResult result) async {
    final repository = ref.read(schoolRepositoryProvider);
    final undoSnapshot = <({ClassGroup before, String after})>[];
    final updates = <ClassGroup>[];
    var skipped = 0;
    final existingNames = <String, Set<String>>{};
    final appliedNames = <String, Set<String>>{};
    for (final rename in result.renames) {
      existingNames
          .putIfAbsent(rename.target.gradeId, () => {})
          .add(rename.target.name);
    }
    for (final rename in result.renames) {
      final name = rename.name.trim();
      if (name == rename.target.name) continue;
      if (name.isEmpty ||
          existingNames[rename.target.gradeId]!.contains(name) ||
          !appliedNames
              .putIfAbsent(rename.target.gradeId, () => {})
              .add(name)) {
        skipped++;
        continue;
      }
      undoSnapshot.add((before: rename.target, after: name));
      updates.add(
        ClassGroup(
          id: rename.target.id,
          gradeId: rename.target.gradeId,
          name: name,
          sortOrder: rename.target.sortOrder,
        ),
      );
    }
    try {
      await repository.saveClasses(updates);
    } on Object catch (error) {
      if (mounted) await _showMessage('批量填充失败：$error');
      return;
    }
    ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    if (!mounted) return;
    if (undoSnapshot.isNotEmpty) {
      setState(() => _lastFillUndo = undoSnapshot);
    }
    final message = skipped == 0
        ? '已按模板重命名 ${updates.length} 个班级'
        : '已重命名 ${updates.length} 个班级，$skipped 个名称因重名或为空被跳过';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _undoLastFill() async {
    final snapshot = _lastFillUndo;
    if (snapshot == null) return;
    final repository = ref.read(schoolRepositoryProvider);
    final currentByGrade = <String, Map<String, ClassGroup>>{};
    for (final item in snapshot) {
      currentByGrade.putIfAbsent(
        item.before.gradeId,
        () => {
          for (final current
              in ref.read(classesProvider(item.before.gradeId)).valueOrNull ??
                  const <ClassGroup>[])
            current.id: current,
        },
      );
    }
    final restores = <ClassGroup>[
      for (final item in snapshot)
        if (currentByGrade[item.before.gradeId]?[item.before.id]?.name ==
            item.after)
          item.before,
    ];
    try {
      await repository.saveClasses(restores);
    } on Object catch (error) {
      if (mounted) await _showMessage('撤销填充失败：$error');
      return;
    }
    ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    if (!mounted) return;
    setState(() => _lastFillUndo = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已撤销上次填充（${restores.length} 个班级）')));
  }

  Future<void> _addGrades(
    BuildContext context,
    WidgetRef ref,
    List<SchoolStage> stages,
  ) async {
    final result = await showDialog<_AddGradesResult>(
      context: context,
      builder: (context) => _AddGradesDialog(
        stages: stages,
        existingNamesByStage: {
          for (final stage in stages)
            stage.id:
                (ref.read(gradesProvider(stage.id)).valueOrNull ??
                        const <GradeGroup>[])
                    .map((grade) => grade.name)
                    .toSet(),
        },
      ),
    );
    if (result == null || !context.mounted) return;
    final repository = ref.read(schoolRepositoryProvider);
    final existing =
        ref.read(gradesProvider(result.stageId)).valueOrNull ??
        const <GradeGroup>[];
    final usedNames = existing.map((grade) => grade.name).toSet();
    if (result.names.any((name) => usedNames.contains(name))) {
      if (mounted) await _showMessage('年级名称已存在，请调整命名方式或先编辑现有年级。');
      return;
    }
    final nextOrder = existing.fold<int>(
      0,
      (next, grade) => grade.sortOrder >= next ? grade.sortOrder + 1 : next,
    );
    await _runSave(
      () => repository.saveGrades([
        for (var index = 0; index < result.count; index++)
          GradeGroup(
            id: _newId(),
            stageId: result.stageId,
            name: result.names[index],
            sortOrder: nextOrder + index,
          ),
      ]),
    );
    if (mounted) setState(() => _selectedStageId = result.stageId);
  }

  Future<void> _runSave(Future<void> Function() action) async {
    try {
      await action();
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    } on Object catch (error) {
      if (mounted) await _showMessage('保存失败：$error');
    }
  }

  Future<void> _showMessage(String message) => showDialog<void>(
    context: context,
    builder: (context) => AppDialog(
      title: const Text('操作失败'),
      content: SelectableText(message),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '班级与学段',
            style: TextStyle(
              color: context.appColors.ink,
              fontSize: 25,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          SizedBox(height: 5),
          Text(
            '按学段组织年级和班级，年级仅归属一个学段。',
            style: TextStyle(
              color: context.appColors.inkSecondary,
              fontSize: 12,
            ),
          ),
        ],
      );
      final templateImport = AppOutlineButton.icon(
        onPressed: null,
        icon: const Icon(Icons.upload_file_outlined, size: 16),
        label: const Text('模板导入'),
      );
      if (constraints.maxWidth < 700) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading,
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: templateImport),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: heading),
          const SizedBox(width: 16),
          templateImport,
        ],
      );
    },
  );
}

class _StageCardRow extends StatelessWidget {
  const _StageCardRow({
    required this.stages,
    required this.onRename,
    required this.onDelete,
    required this.onAddStage,
    required this.canDelete,
  });

  final List<SchoolStage> stages;
  final ValueChanged<SchoolStage> onRename;
  final ValueChanged<SchoolStage> onDelete;
  final VoidCallback onAddStage;
  final bool canDelete;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const addCardWidth = 160.0;
      const gap = 12.0;
      const minCardWidth = 260.0;
      final needed =
          stages.length * minCardWidth +
          (stages.length - 1) * gap +
          gap +
          addCardWidth;
      final cardWidth = needed <= constraints.maxWidth
          ? (constraints.maxWidth -
                    gap -
                    addCardWidth -
                    (stages.length - 1) * gap) /
                stages.length
          : minCardWidth;
      final cards = <Widget>[
        for (var index = 0; index < stages.length; index++)
          SizedBox(
            width: cardWidth,
            child: _StageCard(
              stage: stages[index],
              accent: _stageAccent(context, index),
              onRename: () => onRename(stages[index]),
              onDelete: canDelete ? () => onDelete(stages[index]) : null,
            ),
          ),
        SizedBox(
          width: addCardWidth,
          child: _AddStageCard(onTap: onAddStage),
        ),
      ];
      if (needed <= constraints.maxWidth) {
        return Row(
          children: [
            for (var index = 0; index < stages.length; index++) ...[
              if (index > 0) const SizedBox(width: gap),
              Expanded(child: cards[index]),
            ],
            const SizedBox(width: gap),
            cards.last,
          ],
        );
      }
      final stageColumns = ((constraints.maxWidth + gap) / (minCardWidth + gap))
          .floor()
          .clamp(1, stages.length)
          .toInt();
      final wrappedCardWidth =
          (constraints.maxWidth - (stageColumns - 1) * gap) / stageColumns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var index = 0; index < stages.length; index++)
            SizedBox(
              width: wrappedCardWidth,
              child: _StageCard(
                stage: stages[index],
                accent: _stageAccent(context, index),
                onRename: () => onRename(stages[index]),
                onDelete: canDelete ? () => onDelete(stages[index]) : null,
              ),
            ),
          SizedBox(
            width: constraints.maxWidth < addCardWidth
                ? constraints.maxWidth
                : addCardWidth,
            child: _AddStageCard(onTap: onAddStage),
          ),
        ],
      );
    },
  );
}

class _StageCard extends ConsumerWidget {
  const _StageCard({
    required this.stage,
    required this.accent,
    required this.onRename,
    required this.onDelete,
  });

  final SchoolStage stage;
  final Color accent;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grades = ref.watch(gradesProvider(stage.id));
    var classCount = 0;
    for (final grade in grades.valueOrNull ?? const <GradeGroup>[]) {
      classCount +=
          ref.watch(classesProvider(grade.id)).valueOrNull?.length ?? 0;
    }
    final routine = ref.watch(routineProvider(stage.id)).valueOrNull;
    final canDelete =
        onDelete != null &&
        (grades.valueOrNull ?? const <GradeGroup>[]).isEmpty;
    return SizedBox(
      height: 104,
      child: AppSurface(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppStageDot(color: accent),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      stage.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onRename,
                    child: Text(
                      '改名',
                      style: TextStyle(
                        color: context.appColors.blue,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (onDelete != null)
                    Tooltip(
                      message: canDelete ? '删除空学段' : '请先迁移或删除学段下的年级',
                      child: InkWell(
                        onTap: canDelete ? onDelete : null,
                        child: Text(
                          '删除',
                          style: TextStyle(
                            color: context.appColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '${grades.valueOrNull?.length ?? 0} 个年级 · $classCount 个班级',
                style: TextStyle(color: context.appColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 4),
              Text(
                routine == null ? '作息尚未配置' : _routineSummary(routine),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.appColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _routineSummary(StageRoutine routine) {
    final days = routine.teachingWeekdays.toList()..sort();
    final dayLabel = _weekdayRangeLabel(days);
    final periods = routine.periodTypes
        .where((period) => period.defaultLessonCount > 0)
        .map((period) => '${period.name} ${period.defaultLessonCount}')
        .join(' + ');
    final parts = [
      if (dayLabel.isNotEmpty) dayLabel,
      if (periods.isNotEmpty) periods,
    ];
    return parts.join(' · ');
  }

  static String _weekdayRangeLabel(List<int> days) {
    if (days.isEmpty) return '未设置上课天';
    if (days.length == 7) return '每天';
    if (days.length == 5 && days.first == 1 && days.last == 5) return '周一至周五';
    if (days.length == 6 && days.last == 6) return '周一至周六';
    return '周${days.map((day) => '一二三四五六日'[day - 1]).join('、')}';
  }
}

/// 设计稿「学段卡-新增」（9:70）：白底描边卡 + 加号 + 文案。
class _AddStageCard extends StatelessWidget {
  const _AddStageCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('add-stage-card'),
    height: 104,
    child: Material(
      color: context.appColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: context.appColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.appColors.selectedBlue,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 20, color: context.appColors.blue),
            SizedBox(height: 5),
            Text(
              '新增学段',
              style: TextStyle(
                color: context.appColors.blue,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GradeClassTable extends ConsumerWidget {
  const _GradeClassTable({
    required this.stages,
    required this.onBatchFillHeader,
    required this.onAddGrade,
  });

  final List<SchoolStage> stages;
  final VoidCallback onBatchFillHeader;
  final VoidCallback onAddGrade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = <(SchoolStage, GradeGroup)>[];
    final gradesByStage = <String, List<GradeGroup>>{};
    for (final stage in stages) {
      final grades =
          ref.watch(gradesProvider(stage.id)).valueOrNull ??
          const <GradeGroup>[];
      gradesByStage[stage.id] = grades;
      for (final grade in grades) {
        rows.add((stage, grade));
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < 760 ? 760 : constraints.maxWidth,
          child: AppSectionPanel(
            padding: EdgeInsets.zero,
            showBorder: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppDataTableHeader(
                  height: 44,
                  textColor: context.appColors.muted,
                  backgroundColor: context.appColors.surface,
                  children: [
                    SizedBox(
                      width: 136,
                      child: Row(
                        children: [
                          const Text('年级'),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: '新增年级',
                            child: AppIconButton(
                              key: const Key('add-grade-button'),
                              icon: Icons.add,
                              iconSize: 14,
                              foregroundColor: context.appColors.blue,
                              tooltip: '新增年级',
                              onPressed: onAddGrade,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 110, child: Text('所属学段')),
                    Expanded(
                      child: InkWell(
                        onTap: onBatchFillHeader,
                        child: Row(
                          children: [
                            const Text('班级'),
                            const SizedBox(width: 4),
                            Tooltip(
                              message: '批量填充名称',
                              child: Icon(
                                Icons.playlist_add,
                                size: 14,
                                color: context.appColors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 86,
                      child: Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text('操作'),
                      ),
                    ),
                  ],
                ),
                rows.isEmpty
                    ? const _EmptyGradeRows()
                    : Column(
                        children: [
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: rows.length,
                            onReorderItem: (oldIndex, newIndex) =>
                                _reorderGradeRows(
                                  context,
                                  ref,
                                  rows,
                                  gradesByStage,
                                  oldIndex,
                                  newIndex,
                                ),
                            itemBuilder: (context, index) {
                              final entry = rows[index];
                              return _GradeTableRow(
                                key: ValueKey(entry.$2.id),
                                rowIndex: index,
                                stage: entry.$1,
                                grade: entry.$2,
                                stages: stages,
                                gradesByStage: gradesByStage,
                              );
                            },
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
}

class _EmptyGradeRows extends StatelessWidget {
  const _EmptyGradeRows();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(24),
    child: Center(
      child: Text(
        '还没有年级，点击表头的 + 新增年级。',
        style: TextStyle(color: context.appColors.muted),
      ),
    ),
  );
}

class _GradeTableRow extends ConsumerStatefulWidget {
  const _GradeTableRow({
    super.key,
    required this.rowIndex,
    required this.stage,
    required this.grade,
    required this.stages,
    required this.gradesByStage,
  });

  final int rowIndex;
  final SchoolStage stage;
  final GradeGroup grade;
  final List<SchoolStage> stages;
  final Map<String, List<GradeGroup>> gradesByStage;

  @override
  ConsumerState<_GradeTableRow> createState() => _GradeTableRowState();
}

class _GradeTableRowState extends ConsumerState<_GradeTableRow> {
  String? _editingClassId;
  String? _inlineError;

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;
    final grade = widget.grade;
    final stages = widget.stages;
    final gradesByStage = widget.gradesByStage;
    final stageIndex = stages.indexWhere((item) => item.id == stage.id);
    final classes = ref.watch(classesProvider(grade.id));
    final classList = classes.valueOrNull ?? const <ClassGroup>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Divider(
            height: 1,
            thickness: 1,
            color: context.appColors.tableDivider,
          ),
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 136,
                child: ReorderableDragStartListener(
                  index: widget.rowIndex,
                  child: Text(
                    grade.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 110,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppBadge(
                    label: stage.name,
                    fontSize: 11,
                    foreground: _stageAccent(context, stageIndex),
                    background: _stageTint(context, stageIndex),
                  ),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (var index = 0; index < classList.length; index++)
                      if (_editingClassId == classList[index].id)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 130,
                              child: _InlineClassEditor(
                                key: ValueKey(classList[index].id),
                                name: classList[index].name,
                                onSubmit: (name) => _saveClassName(
                                  classList[index],
                                  classList,
                                  name,
                                ),
                                onCancel: () => setState(() {
                                  _editingClassId = null;
                                  _inlineError = null;
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '失焦或回车保存 · Esc 取消',
                              style: TextStyle(
                                color: context.appColors.muted,
                                fontSize: 11,
                              ),
                            ),
                            if (_inlineError != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                _inlineError!,
                                style: TextStyle(
                                  color: context.appColors.destructive,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        )
                      else
                        AppClassChip(
                          name: classList[index].name,
                          background: _stageTint(context, stageIndex),
                          borderColor: _stageChipBorder(context, stageIndex),
                          onTap: () => setState(() {
                            _editingClassId = classList[index].id;
                            _inlineError = null;
                          }),
                          onDelete: () =>
                              _deleteClass(context, ref, classList[index]),
                          onMoveUp: index > 0
                              ? () => _moveClass(
                                  context,
                                  ref,
                                  classList,
                                  classList[index],
                                  -1,
                                )
                              : null,
                          onMoveDown: index < classList.length - 1
                              ? () => _moveClass(
                                  context,
                                  ref,
                                  classList,
                                  classList[index],
                                  1,
                                )
                              : null,
                        ),
                    AppGhostButton.icon(
                      onPressed: () =>
                          _addClass(context, ref, grade, classList),
                      icon: Icon(
                        Icons.add,
                        size: 13,
                        color: context.appColors.blue,
                      ),
                      label: Text(
                        '添加班级',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.appColors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 86,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => _editGrade(
                        context,
                        ref,
                        grade,
                        stages,
                        gradesByStage,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          '编辑',
                          style: TextStyle(
                            color: context.appColors.blue,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () =>
                          _deleteGrade(context, ref, grade, classList.length),
                      child: Text(
                        '删除',
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _saveClassName(
    ClassGroup item,
    List<ClassGroup> siblings,
    String rawName,
  ) async {
    final name = rawName.trim();
    if (name.isEmpty ||
        siblings.any((other) => other.id != item.id && other.name == name)) {
      if (mounted && _editingClassId == item.id) {
        setState(() => _inlineError = name.isEmpty ? '名称不能为空' : '班级名称重复');
      }
      return;
    }
    if (name == item.name) {
      if (mounted && _editingClassId == item.id) {
        setState(() {
          _editingClassId = null;
          _inlineError = null;
        });
      }
      return;
    }
    try {
      await ref
          .read(schoolRepositoryProvider)
          .saveClass(
            ClassGroup(
              id: item.id,
              gradeId: item.gradeId,
              name: name,
              sortOrder: item.sortOrder,
            ),
          );
      if (mounted) {
        setState(() {
          if (_editingClassId == item.id) {
            _editingClassId = null;
            _inlineError = null;
          }
        });
      }
    } on Object catch (error) {
      if (mounted && _editingClassId == item.id) {
        setState(() => _inlineError = '保存失败：$error');
      }
    }
  }
}

class _InlineClassEditor extends StatefulWidget {
  const _InlineClassEditor({
    required this.name,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  final String name;
  final Future<void> Function(String) onSubmit;
  final VoidCallback onCancel;

  @override
  State<_InlineClassEditor> createState() => _InlineClassEditorState();
}

class _InlineClassEditorState extends State<_InlineClassEditor> {
  late final _controller = TextEditingController(text: widget.name);
  var _submitting = false;
  var _cancelled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    _cancelled = true;
    widget.onCancel();
  }

  void _handleFocusChange(bool hasFocus) {
    if (!hasFocus && !_cancelled) unawaited(_submit());
  }

  void _handleFieldSubmitted(String _) => unawaited(_submit());

  Future<void> _submit() async {
    if (_submitting || _cancelled) return;
    _submitting = true;
    try {
      await widget.onSubmit(_controller.text);
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: _handleFocusChange,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _cancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: AppTextFormField(
      controller: _controller,
      autofocus: true,
      size: FTextFieldSizeVariant.md,
      onFieldSubmitted: _handleFieldSubmitted,
    ),
  );
}

class _EmptyStages extends StatelessWidget {
  const _EmptyStages({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('当前学期还没有学段。', style: TextStyle(color: context.appColors.muted)),
        const SizedBox(height: 12),
        AppPrimaryButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('新增学段'),
        ),
      ],
    ),
  );
}

/// 设计稿「弹窗-新增学段」（154:70）：名称输入 + 常用 chips + 说明。
class _StageNameDialog extends StatefulWidget {
  const _StageNameDialog({required this.existingNames});

  final Set<String> existingNames;

  @override
  State<_StageNameDialog> createState() => _StageNameDialogState();
}

class _StageNameDialogState extends State<_StageNameDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  /// 常用候选：预置学段 + 国际部，过滤已存在的。
  List<String> get _candidates => [
    ...stagePresets,
    '国际部',
  ].where((name) => !widget.existingNames.contains(name)).toList();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 420,
    padding: const EdgeInsets.all(22),
    titleGap: 11,
    actionsGap: 16,
    title: AppDialogTitle(title: '新增学段', onClose: () => Navigator.pop(context)),
    content: SizedBox(
      width: 372,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '学段名称',
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            AppTextFormField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '例如：高中部'),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return '名称不能为空';
                if (widget.existingNames.contains(name)) return '学段名称已存在';
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            if (_candidates.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '常用：',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  for (final candidate in _candidates)
                    _CommonStageChip(
                      label: candidate,
                      isSelected: _controller.text.trim() == candidate,
                      onTap: () => setState(() => _controller.text = candidate),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
    actions: [
      AppOutlineButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(onPressed: _submit, child: const Text('创建')),
    ],
  );

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }
}

/// 常用学段候选 chip（设计稿：选中蓝底、未选中白底描边，11px）。
class _CommonStageChip extends StatelessWidget {
  const _CommonStageChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? context.appColors.selectedBlue
            : context.appColors.surface,
        border: Border.all(
          color: isSelected ? context.appColors.blue : context.appColors.border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? context.appColors.blue
              : context.appColors.inkSecondary,
          fontSize: 11,
        ),
      ),
    ),
  );
}

class _AddGradesResult {
  const _AddGradesResult({
    required this.stageId,
    required this.count,
    required this.names,
  });

  final String stageId;
  final int count;
  final List<String> names;
}

class _AddGradesDialog extends StatefulWidget {
  const _AddGradesDialog({
    required this.stages,
    required this.existingNamesByStage,
  });

  final List<SchoolStage> stages;
  final Map<String, Set<String>> existingNamesByStage;

  @override
  State<_AddGradesDialog> createState() => _AddGradesDialogState();
}

class _AddGradesDialogState extends State<_AddGradesDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customController = TextEditingController();
  late String _stageId;
  int _count = 3;
  String _mode = '中文数字';

  /// 按当前命名方式解析出实际模板字符串。
  String _resolveTemplate() =>
      _mode == '自定义' ? _customController.text : gradeNamingTemplates[_mode]!;

  @override
  void initState() {
    super.initState();
    _stageId = widget.stages.first.id;
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  List<String> _previewNames() {
    final template = _resolveTemplate();
    if (!template.contains('{n}') && !template.contains('{N}')) return const [];
    return generateGradeNames(
      template: template,
      count: _count.clamp(1, 9),
      existingNames: widget.existingNamesByStage[_stageId] ?? const {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final stageName = widget.stages
        .firstWhere((stage) => stage.id == _stageId)
        .name;
    return AppDialog(
      title: const Text('新增年级'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSelectField<String>(
                items: {
                  for (final stage in widget.stages) stage.name: stage.id,
                },
                value: _stageId,
                label: '所属学段',
                onChanged: (value) =>
                    setState(() => _stageId = value ?? _stageId),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppSelectField<String>(
                      items: {for (final mode in gradeNamingModes) mode: mode},
                      value: _mode,
                      label: '命名方式',
                      onChanged: (value) =>
                          setState(() => _mode = value ?? _mode),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: AppTextFormField(
                      initialValue: '$_count',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '数量',
                        suffixText: '个',
                      ),
                      validator: (value) {
                        final count = int.tryParse(value ?? '');
                        return count == null || count < 1 || count > 9
                            ? '1–9'
                            : null;
                      },
                      onChanged: (value) => setState(() {
                        _count = int.tryParse(value) ?? _count;
                      }),
                    ),
                  ),
                ],
              ),
              if (_mode == '自定义') ...[
                const SizedBox(height: 12),
                AppTextFormField(
                  controller: _customController,
                  decoration: const InputDecoration(
                    labelText: '自定义名称',
                    hintText: '例如：{n} 年级 或 {N}',
                  ),
                  validator: (value) =>
                      value != null &&
                          (value.contains('{n}') || value.contains('{N}'))
                      ? null
                      : '请包含占位符 {n} 或 {N}',
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '预览：${_previewNames().join('、')}',
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '将添加到「$stageName」，之后可逐个改名。',
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
              _AddGradesResult(
                stageId: _stageId,
                count: _count,
                names: _previewNames(),
              ),
            );
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _ClassRename {
  const _ClassRename({required this.target, required this.name});

  final ClassGroup target;
  final String name;
}

class _BatchFillResult {
  const _BatchFillResult({required this.renames, this.undo = false});

  final List<_ClassRename> renames;
  final bool undo;
}

/// 设计稿「批量填充名称」：模板 → 多学段选择 → 按学段分组预览。
class _BatchFillNamesDialog extends ConsumerStatefulWidget {
  const _BatchFillNamesDialog({
    required this.stages,
    required this.defaultStageId,
    required this.canUndo,
  });

  final List<SchoolStage> stages;
  final String defaultStageId;
  final bool canUndo;

  @override
  ConsumerState<_BatchFillNamesDialog> createState() =>
      _BatchFillNamesDialogState();
}

class _BatchFillNamesDialogState extends ConsumerState<_BatchFillNamesDialog> {
  static const _templates = ['{年级} {n} 班', '{n} 班', '自定义…'];

  late final Set<String> _selectedStageIds;
  late String _template;
  final _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedStageIds = {widget.defaultStageId};
    _template = _templates[0];
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  /// 每个学段的年级列表（保持学段顺序）。
  List<(SchoolStage, List<GradeGroup>)> get _stageGradeRows => [
    for (final stage in widget.stages)
      (
        stage,
        ref.watch(gradesProvider(stage.id)).valueOrNull ?? const <GradeGroup>[],
      ),
  ];

  /// 年级名去掉末尾「年级」：一年级 → 一，初一 → 初一。
  static String _shortName(String gradeName) => gradeName.endsWith('年级')
      ? gradeName.substring(0, gradeName.length - 2)
      : gradeName;

  List<String> _namesForGrade(String gradeName, int classCount) {
    final short = _shortName(gradeName);
    return List.generate(classCount, (index) {
      final ordinal = index + 1;
      return switch (_template) {
        '{n} 班' => '$short（$ordinal）班',
        '第 {n} 班' => '第 $ordinal 班',
        '{年级} {n} 班' => '$gradeName $ordinal 班',
        _ =>
          _customController.text
              .trim()
              .replaceAll('{n}', '$ordinal')
              .replaceAll('{年级}', gradeName),
      };
    });
  }

  int _selectedClassTotal(Map<String, List<ClassGroup>> classesByGrade) =>
      classesByGrade.values.fold(0, (total, classes) => total + classes.length);

  @override
  Widget build(BuildContext context) {
    final stageGradeRows = _stageGradeRows;
    final classesByGrade = <String, List<ClassGroup>>{};
    for (final (stage, grades) in stageGradeRows) {
      if (!_selectedStageIds.contains(stage.id)) continue;
      for (final grade in grades) {
        classesByGrade[grade.id] =
            ref.watch(classesProvider(grade.id)).valueOrNull ??
            const <ClassGroup>[];
      }
    }
    final selectedGrades = [
      for (final (stage, grades) in stageGradeRows)
        if (_selectedStageIds.contains(stage.id))
          for (final grade in grades) grade,
    ];
    final canApply = selectedGrades.isNotEmpty;

    return AppDialog(
      maxWidth: 640,
      title: Row(
        children: [
          const Expanded(child: Text('批量填充名称')),
          InkWell(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.close, size: 16, color: context.appColors.muted),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1 · 选择名称模板',
              style: TextStyle(color: context.appColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final template in _templates)
                  _TemplateChip(
                    label: template,
                    isSelected: template == _template,
                    onTap: () => setState(() => _template = template),
                  ),
              ],
            ),
            if (_template == '自定义…') ...[
              const SizedBox(height: 8),
              AppTextFormField(
                controller: _customController,
                decoration: const InputDecoration(
                  labelText: '命名规则',
                  hintText: '可用 {n} 与 {年级}，如：{年级}（{n}）班',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 32),
            Text(
              '2 · 应用范围（可多选学段）',
              style: TextStyle(color: context.appColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (stage, _) in stageGradeRows)
                  _GradePickChip(
                    label: stage.name,
                    isSelected: _selectedStageIds.contains(stage.id),
                    onTap: () => setState(() {
                      _selectedStageIds.contains(stage.id)
                          ? _selectedStageIds.remove(stage.id)
                          : _selectedStageIds.add(stage.id);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '已选 ${_selectedStageIds.length} 个学段 · ${selectedGrades.length} 个年级 · '
                  '${_selectedClassTotal(classesByGrade)} 个班级',
                  style: TextStyle(color: context.appColors.blue, fontSize: 12),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() {
                    _selectedStageIds.addAll(
                      widget.stages.map((stage) => stage.id),
                    );
                  }),
                  child: Text(
                    '全选',
                    style: TextStyle(
                      color: context.appColors.blue,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => setState(() => _selectedStageIds.clear()),
                  child: Text(
                    '清空',
                    style: TextStyle(
                      color: context.appColors.blue,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '3 · 预览（按年级分组展示，应用后仍可逐个修改）',
              style: TextStyle(color: context.appColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 13),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 75),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appColors.tableHeader,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.appColors.border),
              ),
              child: selectedGrades.isEmpty
                  ? Text(
                      '请先在上方选择要填充的学段',
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 11,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (stage, grades) in stageGradeRows)
                          if (_selectedStageIds.contains(stage.id))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${stage.name}：',
                                    style: TextStyle(
                                      color: context.appColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  for (final name in [
                                    for (final grade in grades)
                                      ..._namesForGrade(
                                        grade.name,
                                        classesByGrade[grade.id]?.length ?? 0,
                                      ),
                                  ].take(3))
                                    _PreviewNameChip(label: name),
                                  Text(
                                    '… 共 ${grades.fold<int>(0, (total, grade) => total + (classesByGrade[grade.id]?.length ?? 0))} 个班级',
                                    style: TextStyle(
                                      color: context.appColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (widget.canUndo)
                  InkWell(
                    onTap: () => Navigator.pop(
                      context,
                      const _BatchFillResult(renames: [], undo: true),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.undo,
                            size: 14,
                            color: context.appColors.inkSecondary,
                          ),
                          SizedBox(width: 5),
                          Text(
                            '撤销上次填充',
                            style: TextStyle(
                              color: context.appColors.inkSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                AppOutlineButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                AppPrimaryButton(
                  onPressed: canApply
                      ? () => Navigator.pop(
                          context,
                          _BatchFillResult(
                            renames: [
                              for (final grade in selectedGrades)
                                for (
                                  var index = 0;
                                  index <
                                      (classesByGrade[grade.id]?.length ?? 0);
                                  index++
                                )
                                  _ClassRename(
                                    target: classesByGrade[grade.id]![index],
                                    name: _namesForGrade(
                                      grade.name,
                                      classesByGrade[grade.id]!.length,
                                    )[index],
                                  ),
                            ],
                          ),
                        )
                      : null,
                  child: const Text('应用填充'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  const _TemplateChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isSelected
            ? context.appColors.selectedBlue
            : context.appColors.surface,
        border: Border.all(
          color: isSelected ? context.appColors.blue : context.appColors.border,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? context.appColors.blue
              : context.appColors.inkSecondary,
          fontSize: 13,
        ),
      ),
    ),
  );
}

/// 年级多选 chip（设计稿：选中蓝底带 ✓，未选中白底描边）。
class _GradePickChip extends StatelessWidget {
  const _GradePickChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isSelected
            ? context.appColors.selectedBlue
            : context.appColors.surface,
        border: Border.all(
          color: isSelected ? context.appColors.blue : context.appColors.border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isSelected ? '$label ✓' : label,
        style: TextStyle(
          color: isSelected
              ? context.appColors.blue
              : context.appColors.inkSecondary,
          fontSize: 12,
        ),
      ),
    ),
  );
}

/// 预览名称 chip（设计稿：#F8F9FD 底、11px）。
class _PreviewNameChip extends StatelessWidget {
  const _PreviewNameChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FD),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(color: context.appColors.ink, fontSize: 11),
    ),
  );
}

// —— 年级 / 班级操作（共享函数） ——

Future<String?> _editName(
  BuildContext context, {
  required String title,
  String? initialValue,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _NameEditorDialog(title: title, initialValue: initialValue),
);

Future<void> _addClass(
  BuildContext context,
  WidgetRef ref,
  GradeGroup grade,
  List<ClassGroup> current,
) async {
  final names = await showDialog<List<String>>(
    context: context,
    builder: (context) => _AddClassesDialog(grade: grade, current: current),
  );
  if (names == null || !context.mounted) return;
  final nextOrder = current.isEmpty
      ? 0
      : current.map((item) => item.sortOrder).reduce((a, b) => a > b ? a : b) +
            1;
  await _runAction(
    context,
    () => ref.read(schoolRepositoryProvider).saveClasses([
      for (var index = 0; index < names.length; index++)
        ClassGroup(
          id: _newId(),
          gradeId: grade.id,
          name: names[index],
          sortOrder: nextOrder + index,
        ),
    ]),
  );
}

class _AddClassesDialog extends StatefulWidget {
  const _AddClassesDialog({required this.grade, required this.current});

  final GradeGroup grade;
  final List<ClassGroup> current;

  @override
  State<_AddClassesDialog> createState() => _AddClassesDialogState();
}

class _AddClassesDialogState extends State<_AddClassesDialog> {
  final _formKey = GlobalKey<FormState>();
  var _count = 1;

  List<String> get _names {
    final used = widget.current.map((item) => item.name).toSet();
    final names = <String>[];
    var ordinal = 1;
    while (names.length < _count && ordinal < 1000) {
      final name = '${widget.grade.name} $ordinal 班';
      if (used.add(name)) names.add(name);
      ordinal++;
    }
    return names;
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('新增班级'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '所属年级：${widget.grade.name}',
              style: TextStyle(color: context.appColors.inkSecondary),
            ),
            const SizedBox(height: 12),
            AppTextFormField(
              initialValue: '1',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '数量',
                suffixText: '个',
              ),
              validator: (value) {
                final count = int.tryParse(value ?? '');
                return count == null || count < 1 || count > 99
                    ? '请输入 1–99'
                    : null;
              },
              onChanged: (value) => setState(() {
                _count = int.tryParse(value) ?? 1;
              }),
            ),
            const SizedBox(height: 10),
            Text(
              '预览：${_names.take(5).join('、')}${_count > 5 ? '…' : ''}',
              style: TextStyle(color: context.appColors.muted, fontSize: 12),
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
          if (_formKey.currentState!.validate()) Navigator.pop(context, _names);
        },
        child: const Text('添加'),
      ),
    ],
  );
}

Future<void> _editStage(
  BuildContext context,
  WidgetRef ref,
  SchoolStage stage,
) async {
  final name = await _editName(
    context,
    title: '修改学段名称',
    initialValue: stage.name,
  );
  if (name == null || !context.mounted) return;
  await _runAction(
    context,
    () => ref
        .read(schoolRepositoryProvider)
        .saveStage(
          SchoolStage(
            id: stage.id,
            termId: stage.termId,
            name: name,
            sortOrder: stage.sortOrder,
          ),
        ),
  );
}

Future<void> _editGrade(
  BuildContext context,
  WidgetRef ref,
  GradeGroup grade,
  List<SchoolStage> stages,
  Map<String, List<GradeGroup>> gradesByStage,
) async {
  final result = await showDialog<({String name, String stageId})>(
    context: context,
    builder: (context) => Transform.translate(
      offset: Offset(0, MediaQuery.sizeOf(context).height >= 600 ? -67 : 0),
      child: _GradeEditorDialog(grade: grade, stages: stages),
    ),
  );
  if (result == null || !context.mounted) return;
  final targetGrades = gradesByStage[result.stageId] ?? const <GradeGroup>[];
  if (targetGrades.any(
    (item) => item.id != grade.id && item.name == result.name,
  )) {
    await showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('年级名称重复'),
        content: const Text('目标学段已存在同名年级，请修改名称后再保存。'),
        actions: [
          AppPrimaryButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return;
  }
  final nextOrder = targetGrades.isEmpty
      ? 0
      : targetGrades
                .map((item) => item.sortOrder)
                .reduce((a, b) => a > b ? a : b) +
            1;
  await _runAction(
    context,
    () => ref
        .read(schoolRepositoryProvider)
        .saveGrade(
          GradeGroup(
            id: grade.id,
            stageId: result.stageId,
            name: result.name,
            sortOrder: result.stageId == grade.stageId
                ? grade.sortOrder
                : nextOrder,
          ),
        ),
  );
}

class _GradeEditorDialog extends StatefulWidget {
  const _GradeEditorDialog({required this.grade, required this.stages});

  final GradeGroup grade;
  final List<SchoolStage> stages;

  @override
  State<_GradeEditorDialog> createState() => _GradeEditorDialogState();
}

class _GradeEditorDialogState extends State<_GradeEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.grade.name);
  late String _stageId = widget.grade.stageId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 420,
    padding: const EdgeInsets.all(22),
    titleGap: 6,
    actionsGap: 15,
    title: AppDialogTitle(title: '编辑年级', onClose: () => Navigator.pop(context)),
    content: SizedBox(
      width: 372,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '年级名称',
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            AppTextFormField(
              controller: _controller,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '年级名称不能为空' : null,
            ),
            const SizedBox(height: 12),
            Text(
              '所属学段',
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            AppSelectField<String>(
              items: {for (final stage in widget.stages) stage.name: stage.id},
              value: _stageId,
              onChanged: (value) =>
                  setState(() => _stageId = value ?? _stageId),
            ),
            const SizedBox(height: 12),
            Text(
              '修改所属学段会改变该年级在课表分组中的位置；名称修改不会影响旗下班级。',
              style: TextStyle(color: context.appColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
    actions: [
      AppOutlineButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, (
            name: _controller.text.trim(),
            stageId: _stageId,
          ));
        },
        child: const Text('保存'),
      ),
    ],
  );
}

Future<void> _deleteStage(
  BuildContext context,
  WidgetRef ref,
  SchoolStage stage,
) async {
  final confirmed = await _confirmDelete(
    context,
    '删除学段「${stage.name}」？',
    '该学段的作息与免任课设置将一并删除。',
  );
  if (confirmed && context.mounted) {
    await _runAction(
      context,
      () => ref.read(schoolRepositoryProvider).deleteStage(stage.id),
    );
  }
}

Future<void> _deleteGrade(
  BuildContext context,
  WidgetRef ref,
  GradeGroup grade,
  int classCount,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => Transform.translate(
      offset: Offset(0, MediaQuery.sizeOf(context).height >= 600 ? -63 : 0),
      child: _GradeDeleteDialog(gradeName: grade.name, classCount: classCount),
    ),
  );
  if (confirmed == true && context.mounted) {
    await _runAction(
      context,
      () => ref.read(schoolRepositoryProvider).deleteGrade(grade.id),
    );
  }
}

Future<void> _deleteClass(
  BuildContext context,
  WidgetRef ref,
  ClassGroup schoolClass,
) async {
  final confirmed = await _confirmDelete(
    context,
    '删除班级「${schoolClass.name}」？',
    '该班级的科目节数、任课、课表数据将一并删除；当前已保存的免任课设置也会移除。',
  );
  if (confirmed && context.mounted) {
    await _runAction(
      context,
      () => ref.read(schoolRepositoryProvider).deleteClass(schoolClass.id),
    );
  }
}

Future<void> _reorderGradeRows(
  BuildContext context,
  WidgetRef ref,
  List<(SchoolStage, GradeGroup)> rows,
  Map<String, List<GradeGroup>> gradesByStage,
  int oldIndex,
  int newIndex,
) async {
  final targetIndex = newIndex;
  if (oldIndex == targetIndex ||
      targetIndex < 0 ||
      targetIndex >= rows.length) {
    return;
  }
  final source = rows[oldIndex];
  final target = rows[targetIndex];
  if (source.$1.id != target.$1.id) return;

  final original = gradesByStage[source.$1.id]!;
  final reordered = [...original];
  final sourceIndex = reordered.indexWhere((grade) => grade.id == source.$2.id);
  final destinationIndex = reordered.indexWhere(
    (grade) => grade.id == target.$2.id,
  );
  reordered.insert(destinationIndex, reordered.removeAt(sourceIndex));
  final sortOrders = [for (final grade in original) grade.sortOrder]..sort();
  await _runAction(
    context,
    () => ref.read(schoolRepositoryProvider).saveGrades([
      for (var index = 0; index < reordered.length; index++)
        GradeGroup(
          id: reordered[index].id,
          stageId: reordered[index].stageId,
          name: reordered[index].name,
          sortOrder: sortOrders[index],
        ),
    ]),
  );
}

Future<void> _moveClass(
  BuildContext context,
  WidgetRef ref,
  List<ClassGroup> classes,
  ClassGroup schoolClass,
  int delta,
) async {
  await _runAction(context, () async {
    final index = classes.indexWhere((item) => item.id == schoolClass.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= classes.length) return;
    final other = classes[target];
    await ref.read(schoolRepositoryProvider).saveClasses([
      ClassGroup(
        id: schoolClass.id,
        gradeId: schoolClass.gradeId,
        name: schoolClass.name,
        sortOrder: other.sortOrder,
      ),
      ClassGroup(
        id: other.id,
        gradeId: other.gradeId,
        name: other.name,
        sortOrder: schoolClass.sortOrder,
      ),
    ]);
  });
}

class _NameEditorDialog extends StatefulWidget {
  const _NameEditorDialog({required this.title, this.initialValue});

  final String title;
  final String? initialValue;

  @override
  State<_NameEditorDialog> createState() => _NameEditorDialogState();
}

class _NameEditorDialogState extends State<_NameEditorDialog> {
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
    content: SizedBox(
      width: 360,
      child: Form(
        key: _formKey,
        child: AppTextFormField(
          autofocus: true,
          controller: _controller,
          decoration: const InputDecoration(labelText: '名称'),
          validator: (value) =>
              value == null || value.trim().isEmpty ? '名称不能为空' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(onPressed: _submit, child: const Text('保存')),
    ],
  );

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }
}

class _GradeDeleteDialog extends StatefulWidget {
  const _GradeDeleteDialog({required this.gradeName, required this.classCount});

  final String gradeName;
  final int classCount;

  @override
  State<_GradeDeleteDialog> createState() => _GradeDeleteDialogState();
}

class _GradeDeleteDialogState extends State<_GradeDeleteDialog> {
  bool _includeClasses = true;

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 440,
    padding: const EdgeInsets.all(22),
    titleGap: 12,
    actionsGap: 16,
    title: AppDialogTitle(
      title: '删除年级',
      onClose: () => Navigator.pop(context, false),
    ),
    content: SizedBox(
      width: 392,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '将删除「${widget.gradeName}」及其 ${widget.classCount} 个班级，同时删除以下数据，且不可恢复：',
            style: TextStyle(fontSize: 12, color: context.appColors.ink),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.appColors.tableHeader,
              border: Border.all(color: context.appColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '• 科目节数\n• 任课关系（含免任课设置）\n• 课表数据',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.inkSecondary,
                height: 1.5,
              ),
            ),
          ),
          if (widget.classCount > 0) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _includeClasses = !_includeClasses),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: FCheckbox(
                      value: _includeClasses,
                      onChange: (value) =>
                          setState(() => _includeClasses = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('同时删除旗下班级', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      AppOutlineButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      AppDestructiveButton(
        onPressed: _includeClasses ? () => Navigator.pop(context, true) : null,
        child: const Text('确认删除'),
      ),
    ],
  );
}

Future<bool> _confirmDelete(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text(title),
        content: Text(message),
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

Future<void> _runAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on Object catch (error) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('操作失败'),
        content: SelectableText('$error'),
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

int _nextLocalId = 0;

String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_nextLocalId++}';
