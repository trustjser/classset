import 'dart:async';

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/schedule_reconciler.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:class_set/features/scheduling/schedule_export.dart';
import 'package:class_set/features/scheduling/timetable_export_dialog.dart';
import 'package:class_set/features/scheduling/scheduling_timetable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

/// 保存位置选择器作为依赖注入，便于不同平台和测试复用。
final timetableExportSaveLocationProvider =
    Provider<Future<FileSaveLocation?> Function(String)>(
      (ref) =>
          (name) => getSaveLocation(
            suggestedName: name,
            acceptedTypeGroups: [
              const XTypeGroup(label: 'ZIP 压缩包', extensions: ['zip']),
            ],
          ),
    );

class SchedulingPage extends ConsumerStatefulWidget {
  const SchedulingPage({required this.termId, super.key});

  final String termId;

  @override
  ConsumerState<SchedulingPage> createState() => _SchedulingPageState();
}

class _SchedulingPageState extends ConsumerState<SchedulingPage> {
  bool _showReconciliation = false;
  bool _exporting = false;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(schedulingControllerProvider(widget.termId));
    final controller = ref.read(
      schedulingControllerProvider(widget.termId).notifier,
    );
    final snapshot = state.snapshot;
    if (snapshot == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppSectionPanel(
            title: '排课与课表',
            child: state.status == SchedulingStatus.loading
                ? const FProgress()
                : Text(state.error ?? '尚未加载学期排课资料。'),
          ),
        ],
      );
    }
    final pending = state.pendingBaseline;
    final current = state.currentSnapshot;
    final commonPeriods = <String, List<CommonPeriod>>{
      for (final stage in snapshot.stages)
        stage.id:
            ref.watch(commonPeriodsProvider(stage.id)).valueOrNull ?? const [],
    };
    return CallbackShortcuts(
      bindings: pending == null
          ? {
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
                  unawaited(controller.undo()),
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
              ): () =>
                  unawaited(controller.undo()),
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ): () =>
                  unawaited(controller.redo()),
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
                shift: true,
              ): () =>
                  unawaited(controller.redo()),
              const SingleActivator(
                LogicalKeyboardKey.keyY,
                control: true,
              ): () =>
                  unawaited(controller.redo()),
            }
          : const {},
      child: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                if (pending != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.warningSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: context.appColors.warning.withValues(
                            alpha: .3,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: context.appColors.warning,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '课表待协调',
                                  style: TextStyle(
                                    color: context.appColors.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '设置已保存，当前显示变更前的课表；协调完成前不可编辑或自动排课。',
                                  style: TextStyle(
                                    color: context.appColors.inkSecondary,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          AppSecondaryButton(
                            key: const ValueKey('schedule-reconciliation-open'),
                            onPressed: () =>
                                setState(() => _showReconciliation = true),
                            child: const Text('查看协调'),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: SchedulingTimetable(
                    snapshot: snapshot,
                    commonPeriods: commonPeriods,
                    state: state,
                    onStart: () =>
                        unawaited(_showStartDialog(state, controller)),
                    onRefresh: () => unawaited(controller.detect()),
                    onRules: () => unawaited(_showRulesDialog(controller)),
                    onReport: () =>
                        unawaited(_showReportDialog(state, snapshot)),
                    onDetectionReport: () =>
                        unawaited(_showDetectionDialog(state)),
                    onCancel: controller.cancel,
                    onDone: () => unawaited(controller.refresh()),
                    onExport: (items, title) =>
                        unawaited(_showExportDialog(snapshot, state.items)),
                    onPreviewMove: controller.previewMove,
                    onMove: controller.move,
                    onPlaceUnplaced: controller.placeUnplaced,
                    onUndo: () => unawaited(controller.undo()),
                    onRedo: () => unawaited(controller.redo()),
                    onSetLock: (lock, enabled) =>
                        controller.setLock(lock, enabled: enabled),
                    onSetAllLocks: (enabled) =>
                        controller.setAllClassLocks(enabled: enabled),
                    onSetClassLocks: (ids, enabled) =>
                        controller.setClassLocks(ids, enabled: enabled),
                  ),
                ),
              ],
            ),
            if (_showReconciliation && pending != null && current != null)
              _ScheduleReconciliationOverlay(
                key: const ValueKey('schedule-reconciliation-overlay'),
                baseline: pending,
                current: current,
                preview: state.reconciliationPreview,
                busy: state.reconciling,
                error: state.error,
                onPreview: () => unawaited(controller.previewReconciliation()),
                onApply: () async {
                  await controller.applyReconciliation();
                  if (mounted &&
                      ref
                              .read(schedulingControllerProvider(widget.termId))
                              .pendingBaseline ==
                          null) {
                    setState(() => _showReconciliation = false);
                  }
                },
                onClose: () => setState(() => _showReconciliation = false),
              ),
            if (_exporting) const TimetableExportLoading(),
          ],
        ),
      ),
    );
  }

  Future<void> _showStartDialog(
    SchedulingState state,
    SchedulingController controller,
  ) async {
    final snapshot = state.snapshot;
    if (snapshot == null) return;
    var selected = {...state.selectedClassIds};
    var strength = snapshot.preferences.strength;
    var fixedSeed = false;
    var showClasses = false;
    final seedController = TextEditingController(text: '1');
    try {
      final options = await showAppDialog<_StartOptions>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) {
            final problem = const ProblemBuilder().build(
              snapshot,
              selectedClassIds: selected,
            );
            return AppDialog(
              maxWidth: 680,
              title: AppDialogTitle(
                title: '自动排课',
                onClose: () => Navigator.pop(dialogContext),
              ),
              titleGap: 16,
              actionsGap: 24,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '开始前核对排课资料与设置。未通过的项目需要先处理；'
                    '容量不足的课程会进入暂放区。',
                    style: TextStyle(
                      color: context.appColors.inkSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _DialogSection(
                    title: '排课前检查',
                    child: _DialogGrid(
                      children: [
                        _checkRow(
                          context,
                          '班级与学段',
                          '${snapshot.stages.length} 个学段 · '
                              '${snapshot.grades.length} 个年级 · '
                              '${snapshot.classes.length} 个班级',
                          problem.checks
                              .where((check) => check.code == 'classes')
                              .toList(),
                        ),
                        _checkRow(
                          context,
                          '作息设置',
                          '${snapshot.routines.length} 个学段已配置作息',
                          problem.checks
                              .where((check) => check.code == 'routine')
                              .toList(),
                        ),
                        _checkRow(
                          context,
                          '科目节数与容量',
                          '${snapshot.requirements.length} 条节数需求',
                          problem.checks
                              .where((check) => check.code == 'capacity')
                              .toList(),
                        ),
                        _checkRow(
                          context,
                          '教师任课',
                          '${snapshot.assignments.length} 条任课分配',
                          problem.checks
                              .where((check) => check.code == 'assignment')
                              .toList(),
                        ),
                        _checkRow(
                          context,
                          '跨学段节次时间',
                          '按教师与场室使用范围检查',
                          problem.checks
                              .where((check) => check.code == 'clock')
                              .toList(),
                        ),
                        _checkRow(
                          context,
                          '排课规则确认',
                          '${snapshot.conditions.length} 条自定义条件生效中',
                          problem.checks
                              .where(
                                (check) => const {
                                  'combinedScope',
                                  'combined',
                                  'pairing',
                                }.contains(check.code),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(height: 1, color: context.appColors.border),
                  const SizedBox(height: 24),
                  _DialogSection(
                    title: '排课设置',
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final scope = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '排课范围',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '已选 ${selected.length} / ${snapshot.classes.length} 个班级',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.appColors.inkSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 16,
                              runSpacing: 10,
                              children: [
                                for (final stage in snapshot.stages)
                                  AppCheckbox(
                                    value:
                                        _stageClassIds(
                                          snapshot,
                                          stage.id,
                                        ).isNotEmpty &&
                                        _stageClassIds(
                                          snapshot,
                                          stage.id,
                                        ).every(selected.contains),
                                    onChanged: (checked) => update(() {
                                      final ids = _stageClassIds(
                                        snapshot,
                                        stage.id,
                                      );
                                      checked
                                          ? selected.addAll(ids)
                                          : selected.removeAll(ids);
                                    }),
                                    label: Text(stage.name),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            AppGhostButton.icon(
                              onPressed: () =>
                                  update(() => showClasses = !showClasses),
                              icon: Icon(
                                showClasses ? Icons.expand_less : Icons.tune,
                                size: 16,
                              ),
                              label: Text(showClasses ? '收起班级选择' : '选择具体班级'),
                            ),
                          ],
                        );
                        final strengthChoices = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '求解强度',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '选择速度与排课质量的平衡',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.appColors.inkSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            for (final option in const [
                              (ScheduleStrength.fast, '快速 · 小规模微调'),
                              (ScheduleStrength.normal, '标准 · 速度与质量均衡（推荐）'),
                              (ScheduleStrength.high, '高精度 · 最终定稿前重排'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: AppRadioOption<ScheduleStrength>(
                                  value: option.$1,
                                  groupValue: strength,
                                  label: option.$2,
                                  onChanged: (value) =>
                                      update(() => strength = value),
                                ),
                              ),
                          ],
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (constraints.maxWidth >= 520)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _DialogInset(child: scope)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _DialogInset(child: strengthChoices),
                                  ),
                                ],
                              )
                            else ...[
                              _DialogInset(child: scope),
                              const SizedBox(height: 12),
                              _DialogInset(child: strengthChoices),
                            ],
                            if (showClasses) ...[
                              const SizedBox(height: 16),
                              _ScopePanel(
                                snapshot: snapshot,
                                selected: selected,
                                enabled: true,
                                onChanged: (next) =>
                                    update(() => selected = next),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _DialogInset(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => update(
                                            () => fixedSeed = !fixedSeed,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                '固定随机种子',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '排课条件相同时，使用相同种子可复现结果。',
                                                style: TextStyle(
                                                  color: context
                                                      .appColors
                                                      .inkSecondary,
                                                  fontSize: 12,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Transform.scale(
                                        scale: .8,
                                        child: Switch(
                                          value: fixedSeed,
                                          onChanged: (value) =>
                                              update(() => fixedSeed = value),
                                          activeThumbColor:
                                              context.appColors.surface,
                                          activeTrackColor:
                                              context.appColors.blue,
                                          inactiveThumbColor:
                                              context.appColors.surface,
                                          inactiveTrackColor:
                                              context.appColors.border,
                                          trackOutlineColor:
                                              const WidgetStatePropertyAll(
                                                Colors.transparent,
                                              ),
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (fixedSeed) ...[
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: SizedBox(
                                        width: 180,
                                        child: AppTextFormField(
                                          controller: seedController,
                                          keyboardType: TextInputType.number,
                                          onChanged: (_) => update(() {}),
                                          decoration: const InputDecoration(
                                            labelText: '随机种子',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '开始后底部会显示排课任务条；取消不会保存半成品，'
                    '已锁定课节会保留位置。',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              actions: [
                AppSecondaryButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                AppPrimaryButton(
                  onPressed:
                      !problem.isReady ||
                          selected.isEmpty ||
                          (fixedSeed &&
                              int.tryParse(seedController.text) == null)
                      ? null
                      : () => Navigator.pop(
                          dialogContext,
                          _StartOptions(
                            classIds: {...selected},
                            strength: strength,
                            seed: fixedSeed
                                ? int.parse(seedController.text)
                                : DateTime.now().millisecondsSinceEpoch,
                          ),
                        ),
                  child: const Text('开始自动排课'),
                ),
              ],
            );
          },
        ),
      );
      if (!mounted || options == null) return;
      controller.selectClasses(options.classIds);
      if (options.strength != snapshot.preferences.strength) {
        await controller.saveConfiguration(
          conditions: snapshot.conditions,
          preferences: SchedulePreferences(
            strength: options.strength,
            progressConsistency: snapshot.preferences.progressConsistency,
            teacherDistribution: snapshot.preferences.teacherDistribution,
            consecutiveMode: snapshot.preferences.consecutiveMode,
            protectLunchBreak: snapshot.preferences.protectLunchBreak,
            checkProgressConsistency:
                snapshot.preferences.checkProgressConsistency,
          ),
        );
      }
      await controller.start(seed: options.seed);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法开始排课：$error')));
      }
    } finally {
      seedController.dispose();
    }
  }

  Future<void> _showRulesDialog(SchedulingController controller) async {
    await showAppDrawer<void>(
      context: context,
      builder: (drawerContext) => Consumer(
        builder: (context, ref, _) {
          final schedulingState = ref.watch(
            schedulingControllerProvider(widget.termId),
          );
          final snapshot =
              schedulingState.currentSnapshot ?? schedulingState.snapshot;
          if (snapshot == null) return const SizedBox.shrink();
          return _RulesDrawer(
            snapshot: snapshot,
            controller: controller,
            lockEnabled: schedulingState.pendingBaseline == null,
            onClose: () => Navigator.pop(drawerContext),
          );
        },
      ),
    );
  }

  Future<void> _showReportDialog(
    SchedulingState state,
    SchedulingSnapshot snapshot,
  ) async {
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 660,
        title: AppDialogTitle(
          title: '未排课程报告',
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: _ReportPanel(snapshot: snapshot, state: state),
        actions: [
          AppPrimaryButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetectionDialog(SchedulingState state) async {
    final itemsById = {for (final item in state.items) item.id: item};
    bool crossStageTeacherConflict(int index) {
      final issue = state.detectionIssues[index];
      if (issue.code != 'teacherOccupied' || issue.position == null) {
        return false;
      }
      return issue.relatedIds.any(
        (id) =>
            itemsById[id]?.position?.stageId != null &&
            itemsById[id]!.position!.stageId != issue.position!.stageId,
      );
    }

    final crossStage = <String>[];
    final other = <String>[];
    for (var index = 0; index < state.detectionIssues.length; index++) {
      final issue = state.detectionIssues[index];
      final position = issue.position;
      final place = position == null
          ? ''
          : '${_detectDayLabel(position.weekday)}第 ${position.lessonIndex} 节 · ';
      (crossStageTeacherConflict(index) ? crossStage : other).add(
        '$place${issue.message}',
      );
    }
    final contentText = [
      if (crossStage.isNotEmpty) ...['跨学段教师时钟冲突', ...crossStage, ''],
      '其他检测结果',
      if (other.isEmpty) '未发现其他硬约束冲突' else ...other,
    ].join('\n');
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 680,
        title: AppDialogTitle(
          title: '课表检测结果',
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('共发现 ${state.detectionIssues.length} 项硬约束问题'),
                const SizedBox(height: 20),
                if (crossStage.isNotEmpty) ...[
                  Text(
                    '跨学段教师时钟冲突 · ${crossStage.length} 项',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  for (final message in crossStage)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(message),
                    ),
                  const SizedBox(height: 16),
                ],
                Text(
                  '其他检测结果 · ${other.length} 项',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                if (other.isEmpty)
                  const Text('未发现其他硬约束冲突')
                else
                  for (final message in other)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(message),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          AppSecondaryButton(
            onPressed: () =>
                unawaited(Clipboard.setData(ClipboardData(text: contentText))),
            child: const Text('复制全部'),
          ),
          AppPrimaryButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  String _detectDayLabel(int weekday) => switch (weekday) {
    1 => '周一',
    2 => '周二',
    3 => '周三',
    4 => '周四',
    5 => '周五',
    6 => '周六',
    _ => '周日',
  };

  Future<void> _showExportDialog(
    SchedulingSnapshot snapshot,
    List<ScheduleItem> items,
  ) async {
    if (_exporting) return;
    final options = await showAppDialog<TimetableExportOptions>(
      context: context,
      builder: (context) => const TimetableExportDialog(),
    );
    if (options == null || !mounted || _exporting) return;
    setState(() => _exporting = true);
    try {
      final repository = ref.read(schoolRepositoryProvider);
      final storedName = (await repository.watchSchoolName().first).trim();
      final schoolName = storedName.isEmpty ? '未命名学校' : storedName;
      if (!mounted) return;
      final name = timetableZipFileName(schoolName, snapshot.term);
      final location = await ref.read(timetableExportSaveLocationProvider)(
        name,
      );
      if (location == null || !mounted) return;
      final results = await Future.wait([
        for (final stage in snapshot.stages)
          repository.watchCommonPeriods(stage.id).first,
      ]);
      final commonPeriods = {
        for (var i = 0; i < snapshot.stages.length; i++)
          snapshot.stages[i].id: results[i],
      };
      final bytes = await buildTimetableZipAsync(
        snapshot,
        items,
        schoolName: schoolName,
        commonPeriods: commonPeriods,
        options: options,
      );
      await XFile.fromData(
        Uint8List.fromList(bytes),
        name: name,
        mimeType: 'application/zip',
      ).saveTo(location.path);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('课表压缩包已导出')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出课表失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _StartOptions {
  const _StartOptions({
    required this.classIds,
    required this.strength,
    required this.seed,
  });

  final Set<String> classIds;
  final ScheduleStrength strength;
  final int seed;
}

Set<String> _stageClassIds(SchedulingSnapshot snapshot, String stageId) {
  final grades = snapshot.grades
      .where((item) => item.stageId == stageId)
      .map((item) => item.id)
      .toSet();
  return snapshot.classes
      .where((item) => grades.contains(item.gradeId))
      .map((item) => item.id)
      .toSet();
}

/// 右侧抽屉：把原先两个叠层的居中弹窗（排课偏好 / 排课规则与锁定）
/// 合并为「排课偏好 → 自定义硬条件 → 锁定已有课表」三段。
///
/// 按设计稿采用草稿态：三段共用一份本地 [SchedulingSnapshot] 副本，
/// 所有改动只更新草稿，点「保存」才一次性提交；「取消」/ 关闭 / Esc /
/// 点遮罩均丢弃草稿。_RulePanel 与 _LockPanel 已是受控组件，只需把它们的
/// onSave / onSet 从落库改为更新草稿。
class _RulesDrawer extends StatefulWidget {
  const _RulesDrawer({
    required this.snapshot,
    required this.controller,
    required this.lockEnabled,
    required this.onClose,
  });

  final SchedulingSnapshot snapshot;
  final SchedulingController controller;
  final bool lockEnabled;
  final VoidCallback onClose;

  @override
  State<_RulesDrawer> createState() => _RulesDrawerState();
}

/// [ScheduleLock] 未实现 ==，用稳定 key 做草稿与已保存状态的增删 diff。
String _lockKey(ScheduleLock lock) =>
    '${lock.termId}|${lock.scope.name}|${lock.targetId}';

class _RulesDrawerState extends State<_RulesDrawer> {
  late SchedulingSnapshot _draft;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.snapshot;
  }

  void _update(SchedulingSnapshot next) {
    if (_saving) return;
    setState(() {
      _draft = next;
      _dirty = true;
    });
  }

  void _setLock(ScheduleLock lock, bool enabled) {
    final key = _lockKey(lock);
    final current = _draft.locks;
    final exists = current.any((item) => _lockKey(item) == key);
    if (exists == enabled) return;
    final next = enabled
        ? [...current, lock]
        : current.where((item) => _lockKey(item) != key).toList();
    _update(_draft.copyWith(locks: next));
  }

  Future<void> _commit() async {
    if (_saving) return;
    // 没有改动时直接关闭，避免一次无意义的写库与 refresh。
    if (!_dirty) {
      widget.onClose();
      return;
    }
    setState(() => _saving = true);
    // 先取快照：saveConfiguration 会触发 refresh，之后 widget.snapshot 可能已变。
    final originalLocks = widget.snapshot.locks;
    try {
      await widget.controller.saveConfiguration(
        conditions: _draft.conditions,
        preferences: _draft.preferences,
      );
      final originalKeys = originalLocks.map(_lockKey).toSet();
      final draftKeys = _draft.locks.map(_lockKey).toSet();
      for (final lock in originalLocks) {
        if (!draftKeys.contains(_lockKey(lock))) {
          await widget.controller.setLock(lock, enabled: false);
        }
      }
      for (final lock in _draft.locks) {
        if (!originalKeys.contains(_lockKey(lock))) {
          await widget.controller.setLock(lock, enabled: true);
        }
      }
      if (!mounted) return;
      widget.onClose();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存排课偏好与规则失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppDrawerSurface(
      title: '排课偏好与规则',
      subtitle: '设置求解策略、约束与锁定范围，左侧课表可直接对照。',
      onClose: widget.onClose,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DrawerSection(
            title: '排课偏好',
            description: '设置排课时的求解策略和需要遵守的约束。',
            child: _PreferencesFields(
              preferences: _draft.preferences,
              onChanged: (next) => _update(_draft.copyWith(preferences: next)),
            ),
          ),
          const _SectionDivider(),
          _DrawerSection(
            title: '自定义硬条件',
            count: '${_draft.conditions.length} 条',
            description: '自动排课必须满足这些条件，条件过多时可能排不满课表。',
            child: _RulePanel(
              snapshot: _draft,
              enabled: !_saving,
              onSave: (conditions, preferences) async => _update(
                _draft.copyWith(
                  conditions: conditions,
                  preferences: preferences,
                ),
              ),
            ),
          ),
          const _SectionDivider(),
          _DrawerSection(
            title: '锁定已有课表',
            count: '${_draft.locks.length} 个范围',
            description: '锁定范围内的课程在自动排课时保持原位，不会被移动或覆盖。',
            child: _LockPanel(
              snapshot: _draft,
              enabled: widget.lockEnabled && !_saving,
              onSet: (lock, enabled) async => _setLock(lock, enabled),
            ),
          ),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '自定义硬条件 ${_draft.conditions.length} 条 · '
                  '锁定范围 ${_draft.locks.length} 个',
                  style: TextStyle(
                    color: colors.inkSecondary,
                    fontSize: 12,
                    height: 18 / 12,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (_dirty) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colors.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        _dirty ? '有未保存的修改' : '修改在点击「保存」后生效',
                        style: TextStyle(
                          color: _dirty ? colors.warning : colors.inkSecondary,
                          fontSize: 12,
                          height: 18 / 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AppSecondaryButton(
            onPressed: _saving ? null : widget.onClose,
            child: const Text('取消'),
          ),
          const SizedBox(width: 10),
          AppPrimaryButton(
            onPressed: _saving ? null : () => unawaited(_commit()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

/// ===== 抽屉视觉组件：与 design/schedule_rules_drawer_redesign.html 对齐 =====

/// 去掉「类型 · 」前缀，供条件卡片显示对象值（如「数学 / 语文」）。
String _conditionValue(
  ScheduleCondition condition,
  SchedulingSnapshot snapshot,
) {
  final label = _conditionLabel(condition, snapshot);
  final prefix = '${_conditionTypeLabel(condition.type)} · ';
  return label.startsWith(prefix) ? label.substring(prefix.length) : label;
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({
    required this.title,
    required this.description,
    required this.child,
    this.count,
  });

  final String title;
  final String description;
  final String? count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: colors.ink,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.canvas,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count!,
                  style: TextStyle(color: colors.inkSecondary, fontSize: 11.5),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: TextStyle(
            color: colors.inkSecondary,
            fontSize: 12.5,
            height: 20 / 12.5,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Container(height: 1, color: context.appColors.border),
  );
}

class _DrawerSubhead extends StatelessWidget {
  const _DrawerSubhead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        color: context.appColors.ink,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// 设计稿的方形圆角复选框（Forui AppCheckbox 为圆形勾，形态不同）。
class _DrawerCheckbox extends StatelessWidget {
  const _DrawerCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      checked: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.canvas,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value ? colors.blue : colors.surface,
                  border: Border.all(
                    color: value ? colors.blue : colors.border,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: value
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 12.5,
                    fontWeight: value ? FontWeight.w600 : FontWeight.w400,
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

/// 设计稿的整行虚线「+ 添加」按钮。
class _DashedAddButton extends StatelessWidget {
  const _DashedAddButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final active = onPressed != null;
    return Semantics(
      button: true,
      enabled: active,
      child: GestureDetector(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CustomPaint(
            painter: _DashedBorderPainter(color: colors.border, radius: 9),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add,
                    size: 14,
                    color: active ? colors.blue : colors.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? colors.blue : colors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + dash > metric.length
            ? metric.length
            : distance + dash;
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

class _DrawerEmptyState extends StatelessWidget {
  const _DrawerEmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return CustomPaint(
      painter: _DashedBorderPainter(color: colors.border, radius: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            Icon(icon, size: 22, color: colors.muted),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.muted,
                fontSize: 12.5,
                height: 20 / 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.index,
    required this.condition,
    required this.snapshot,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final ScheduleCondition condition;
  final SchedulingSnapshot snapshot;
  final bool enabled;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.canvas,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$index',
              style: TextStyle(color: colors.muted, fontSize: 11),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.selectedBlue,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    _conditionTypeLabel(condition.type),
                    style: TextStyle(
                      color: colors.blue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _conditionValue(condition, snapshot),
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 13.5,
                    height: 22 / 13.5,
                  ),
                ),
              ],
            ),
          ),
          AppIconButton(
            tooltip: '编辑条件',
            icon: Icons.edit_outlined,
            onPressed: onEdit,
          ),
          AppIconButton(
            tooltip: '删除条件',
            icon: Icons.delete_outline,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _LockCard extends StatelessWidget {
  const _LockCard({
    required this.name,
    required this.enabled,
    required this.onRemove,
  });

  final String name;
  final bool enabled;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.warningSurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.lock_outline, size: 14, color: colors.warning),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 13, color: colors.ink)),
                Text(
                  '该范围整周课表保持不变',
                  style: TextStyle(fontSize: 11.5, color: colors.muted),
                ),
              ],
            ),
          ),
          AppIconButton(
            tooltip: '移除锁定',
            icon: Icons.close,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// 排课偏好字段：标题/说明/分区线由外层 _DrawerSection 统一提供。
class _PreferencesFields extends StatelessWidget {
  const _PreferencesFields({
    required this.preferences,
    required this.onChanged,
  });

  final SchedulePreferences preferences;
  final ValueChanged<SchedulePreferences> onChanged;

  void _update({
    ScheduleStrength? strength,
    ProgressConsistency? progressConsistency,
    TeacherDistribution? teacherDistribution,
    ConsecutiveMode? consecutiveMode,
    bool? protectLunchBreak,
    bool? checkProgressConsistency,
  }) => onChanged(
    SchedulePreferences(
      strength: strength ?? preferences.strength,
      progressConsistency:
          progressConsistency ?? preferences.progressConsistency,
      teacherDistribution:
          teacherDistribution ?? preferences.teacherDistribution,
      consecutiveMode: consecutiveMode ?? preferences.consecutiveMode,
      protectLunchBreak: protectLunchBreak ?? preferences.protectLunchBreak,
      checkProgressConsistency:
          checkProgressConsistency ?? preferences.checkProgressConsistency,
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _DrawerSubhead('排课策略'),
      _DialogGrid(
        twoColumnBreakpoint: 320,
        children: [
          _choice<ScheduleStrength>(
            '求解强度',
            preferences.strength,
            ScheduleStrength.values,
            _strengthLabel,
            (value) => _update(strength: value),
          ),
          _choice<ProgressConsistency>(
            '同级同科进度',
            preferences.progressConsistency,
            ProgressConsistency.values,
            (value) => value == ProgressConsistency.require ? '必须同步' : '尽量同步',
            (value) => _update(progressConsistency: value),
          ),
          _choice<TeacherDistribution>(
            '教师日分布',
            preferences.teacherDistribution,
            TeacherDistribution.values,
            (value) => switch (value) {
              TeacherDistribution.indifferent => '不限制',
              TeacherDistribution.spread => '尽量分散',
              TeacherDistribution.concentrate => '尽量集中',
            },
            (value) => _update(teacherDistribution: value),
          ),
          _choice<ConsecutiveMode>(
            '连堂偏好',
            preferences.consecutiveMode,
            ConsecutiveMode.values,
            (value) => switch (value) {
              ConsecutiveMode.preferSeparate => '尽量不连堂',
              ConsecutiveMode.requireSeparate => '禁止连堂',
              ConsecutiveMode.preferTogether => '尽量连堂',
            },
            (value) => _update(consecutiveMode: value),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const _DrawerSubhead('附加约束'),
      _DialogGrid(
        twoColumnBreakpoint: 320,
        children: [
          _DrawerCheckbox(
            label: '保护午间休息',
            value: preferences.protectLunchBreak,
            onChanged: (value) => _update(protectLunchBreak: value),
          ),
          _DrawerCheckbox(
            label: '检查教学进度一致性',
            value: preferences.checkProgressConsistency,
            onChanged: (value) => _update(checkProgressConsistency: value),
          ),
        ],
      ),
    ],
  );
}

class _DialogDescription extends StatelessWidget {
  const _DialogDescription(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: context.appColors.inkSecondary,
      fontSize: 13,
      height: 1.5,
    ),
  );
}

class _DialogInset extends StatelessWidget {
  const _DialogInset({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.appColors.canvas,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

class _DialogGrid extends StatelessWidget {
  const _DialogGrid({required this.children, this.twoColumnBreakpoint = 480});
  final List<Widget> children;

  /// 抽屉内可用宽度更窄，允许调用方下调两列阈值。
  final double twoColumnBreakpoint;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 16.0;
      final width = constraints.maxWidth >= twoColumnBreakpoint
          ? (constraints.maxWidth - gap) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: gap,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _DialogSection extends StatelessWidget {
  const _DialogSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 18),
      child,
    ],
  );
}

Widget _checkRow(
  BuildContext context,
  String title,
  String summary,
  List<SchedulePreflightCheck> issues,
) {
  final ready = issues.every((item) => item.ready);
  final warning = ready && issues.isNotEmpty;
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning
              ? Icons.warning_amber_outlined
              : ready
              ? Icons.check_circle_outline
              : Icons.error_outline,
          size: 16,
          color: warning || !ready
              ? context.appColors.warning
              : context.appColors.success,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                issues.isEmpty
                    ? summary
                    : issues.map((item) => item.message).join('；'),
                style: TextStyle(
                  color: context.appColors.inkSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ScopePanel extends StatelessWidget {
  const _ScopePanel({
    required this.snapshot,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final SchedulingSnapshot snapshot;
  final Set<String> selected;
  final bool enabled;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final allIds = snapshot.classes.map((item) => item.id).toSet();
    bool allSelected(Set<String> ids) =>
        ids.isNotEmpty && ids.every(selected.contains);
    void toggle(Set<String> ids) => onChanged(
      allSelected(ids)
          ? (Set<String>.of(selected)..removeAll(ids))
          : {...selected, ...ids},
    );
    return _DialogInset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '逐班选择 · ${selected.length}/${allIds.length} 个班级',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AppGhostButton(
                onPressed: enabled && allIds.isNotEmpty
                    ? () => toggle(allIds)
                    : null,
                child: Text(
                  allSelected(allIds) ? '取消全选' : '全选',
                  style: TextStyle(color: context.appColors.blue),
                ),
              ),
            ],
          ),
          Text(
            '未选班级保持原课表，并继续占用教师与场室。',
            style: TextStyle(
              color: context.appColors.inkSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          for (final stage in snapshot.stages)
            _CollapsibleStage(
              key: ValueKey(stage.id),
              title: stage.name,
              selectedCount: _stageClassIds(
                snapshot,
                stage.id,
              ).where(selected.contains).length,
              totalCount: _stageClassIds(snapshot, stage.id).length,
              allSelected: allSelected(_stageClassIds(snapshot, stage.id)),
              onToggleSelection:
                  enabled && _stageClassIds(snapshot, stage.id).isNotEmpty
                  ? () => toggle(_stageClassIds(snapshot, stage.id))
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final grade in snapshot.grades.where(
                    (item) => item.stageId == stage.id,
                  ))
                    Builder(
                      builder: (context) {
                        final classes = snapshot.classes
                            .where((item) => item.gradeId == grade.id)
                            .toList();
                        final ids = classes.map((item) => item.id).toSet();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      grade.name,
                                      style: TextStyle(
                                        color: context.appColors.inkSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  AppGhostButton(
                                    onPressed: enabled && ids.isNotEmpty
                                        ? () => toggle(ids)
                                        : null,
                                    child: Text(
                                      allSelected(ids) ? '取消年级全选' : '全选年级',
                                      style: TextStyle(
                                        color: context.appColors.blue,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final schoolClass in classes)
                                    FilterChip(
                                      label: Text(schoolClass.name),
                                      selected: selected.contains(
                                        schoolClass.id,
                                      ),
                                      onSelected: enabled
                                          ? (_) => toggle({schoolClass.id})
                                          : null,
                                      selectedColor:
                                          context.appColors.selectedBlue,
                                      backgroundColor:
                                          context.appColors.surface,
                                      checkmarkColor: context.appColors.blue,
                                      side: BorderSide(
                                        color: selected.contains(schoolClass.id)
                                            ? context.appColors.blue.withValues(
                                                alpha: .35,
                                              )
                                            : context.appColors.border,
                                      ),
                                      labelStyle: TextStyle(
                                        fontSize: 12,
                                        color: selected.contains(schoolClass.id)
                                            ? context.appColors.blue
                                            : context.appColors.inkSecondary,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CollapsibleStage extends StatefulWidget {
  const _CollapsibleStage({
    required this.title,
    required this.selectedCount,
    required this.totalCount,
    required this.allSelected,
    required this.onToggleSelection,
    required this.child,
    super.key,
  });
  final String title;
  final int selectedCount;
  final int totalCount;
  final bool allSelected;
  final VoidCallback? onToggleSelection;
  final Widget child;
  @override
  State<_CollapsibleStage> createState() => _CollapsibleStageState();
}

class _CollapsibleStageState extends State<_CollapsibleStage> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: context.appColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.appColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 18,
                        color: context.appColors.inkSecondary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.selectedCount}/${widget.totalCount}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppGhostButton(
                onPressed: widget.onToggleSelection,
                child: Text(
                  widget.allSelected ? '取消学段全选' : '全选学段',
                  style: TextStyle(color: context.appColors.blue, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        if (_expanded) ...[
          Divider(height: 1, color: context.appColors.border),
          widget.child,
        ],
      ],
    ),
  );
}

class _RulePanel extends StatelessWidget {
  const _RulePanel({
    required this.snapshot,
    required this.enabled,
    required this.onSave,
  });

  final SchedulingSnapshot snapshot;
  final bool enabled;
  final Future<void> Function(List<ScheduleCondition>, SchedulePreferences)
  onSave;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (snapshot.conditions.isEmpty)
        const _DrawerEmptyState(
          icon: Icons.rule_outlined,
          text: '还没有自定义硬条件\n添加后，自动排课会优先满足这些约束',
        )
      else
        ..._conditionCards(context),
      _DashedAddButton(
        label: '添加硬条件',
        onPressed: enabled
            ? () => unawaited(_showConditionEditor(context))
            : null,
      ),
    ],
  );

  List<Widget> _conditionCards(BuildContext context) {
    final cards = <Widget>[];
    for (var i = 0; i < snapshot.conditions.length; i++) {
      final condition = snapshot.conditions[i];
      cards.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _RuleCard(
            index: i + 1,
            condition: condition,
            snapshot: snapshot,
            enabled: enabled,
            onEdit: enabled
                ? () => unawaited(_showConditionEditor(context, condition))
                : null,
            onDelete: enabled
                ? () => unawaited(
                    _save(
                      context,
                      snapshot.conditions
                          .where((item) => item.id != condition.id)
                          .toList(),
                      snapshot.preferences,
                    ),
                  )
                : null,
          ),
        ),
      );
    }
    return cards;
  }

  Future<void> _save(
    BuildContext context,
    List<ScheduleCondition> conditions,
    SchedulePreferences preferences,
  ) async {
    try {
      await onSave(conditions, preferences);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存规则失败：$error')));
      }
    }
  }

  Future<void> _showConditionEditor(
    BuildContext context, [
    ScheduleCondition? original,
  ]) async {
    var type = original?.type ?? ScheduleConditionType.periodLimit;
    var targetType = original?.targetType ?? ScheduleConditionTarget.subject;
    String? targetId = original?.targetId;
    String? otherId = original?.otherTargetId;
    String? periodTypeId = original?.periodTypeId;
    var weekday = original?.weekday ?? 0;
    final minimum = TextEditingController(text: original?.minimum?.toString());
    final maximum = TextEditingController(text: original?.maximum?.toString());
    final exact = TextEditingController(text: original?.exact?.toString());
    final name = TextEditingController(text: original?.name);
    Future<void>? dialogClosed;
    try {
      final condition = await showAppDialog<ScheduleCondition>(
        context: context,
        builder: (dialogContext) {
          final route = ModalRoute.of(dialogContext);
          if (route != null) {
            dialogClosed = route.completed.then((_) {});
          }
          return StatefulBuilder(
            builder: (context, update) {
              final mutual =
                  type == ScheduleConditionType.teacherMutualExclusion ||
                  type == ScheduleConditionType.subjectMutualExclusion ||
                  type == ScheduleConditionType.forbiddenAdjacency;
              final subjects = switch (type) {
                ScheduleConditionType.teacherMutualExclusion => false,
                ScheduleConditionType.subjectMutualExclusion ||
                ScheduleConditionType.forbiddenAdjacency => true,
                _ => targetType == ScheduleConditionTarget.subject,
              };
              final targets = _uniqueSelectOptions(
                subjects
                    ? [
                        for (final item in snapshot.subjects)
                          (item.id, item.name),
                      ]
                    : [
                        for (final item in snapshot.teachers)
                          (item.id, item.displayName),
                      ],
              );
              final stagesById = {
                for (final stage in snapshot.stages) stage.id: stage.name,
              };
              final seenPeriodIds = <String>{};
              final periods = _uniqueSelectOptions([
                for (final routine in snapshot.routines)
                  for (final period in routine.periodTypes)
                    if (seenPeriodIds.add(period.id))
                      (
                        period.id,
                        '${stagesById[routine.stageId] ?? '未知学段'} · ${period.name}',
                      ),
              ]);
              return AppDialog(
                maxWidth: 680,
                title: AppDialogTitle(
                  title: original == null ? '添加硬条件' : '编辑硬条件',
                  onClose: () => Navigator.pop(dialogContext),
                ),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DialogDescription('选择约束对象与适用范围，排课时将严格遵守这些条件。'),
                    const SizedBox(height: 20),
                    _DialogSection(
                      title: '条件与对象',
                      child: _DialogGrid(
                        children: [
                          _choice<ScheduleConditionType>(
                            '条件类型',
                            type,
                            ScheduleConditionType.values,
                            _conditionTypeLabel,
                            (value) => update(() {
                              type = value;
                              targetId = null;
                              otherId = null;
                            }),
                          ),
                          if (!mutual)
                            _choice<ScheduleConditionTarget>(
                              '对象类型',
                              targetType,
                              ScheduleConditionTarget.values,
                              (value) =>
                                  value == ScheduleConditionTarget.subject
                                  ? '科目（逐班）'
                                  : '教师',
                              (value) => update(() {
                                targetType = value;
                                targetId = null;
                              }),
                            ),
                          AppSelectField<String>(
                            key: ValueKey('target-$type-$targetType'),
                            value: targetId,
                            label: mutual ? '对象 A' : '对象',
                            hint: '请选择对象',
                            searchable: true,
                            searchHint: '搜索科目或教师',
                            items: targets,
                            onChanged: (value) =>
                                update(() => targetId = value),
                          ),
                          if (mutual)
                            AppSelectField<String>(
                              key: ValueKey('other-$type'),
                              value: otherId,
                              label: '对象 B',
                              hint: '请选择对象',
                              searchable: true,
                              searchHint: '搜索科目或教师',
                              items: targets,
                              onChanged: (value) =>
                                  update(() => otherId = value),
                            ),
                          if (type == ScheduleConditionType.periodLimit)
                            AppSelectField<String>(
                              value: periodTypeId,
                              label: '时段',
                              hint: '请选择时段',
                              searchable: true,
                              searchHint: '搜索学段或时段',
                              items: periods,
                              onChanged: (value) =>
                                  update(() => periodTypeId = value),
                            ),
                          if (!mutual)
                            AppSelectField<int>(
                              value: weekday,
                              label: type == ScheduleConditionType.dailyLimit
                                  ? '适用星期'
                                  : '统计星期',
                              items: {
                                type == ScheduleConditionType.dailyLimit
                                        ? '每天分别计算'
                                        : '整周合计':
                                    0,
                                for (var day = 1; day <= 7; day++)
                                  '星期$day': day,
                              },
                              onChanged: (value) =>
                                  update(() => weekday = value ?? 0),
                            ),
                        ],
                      ),
                    ),
                    if (!mutual) ...[
                      const SizedBox(height: 24),
                      _DialogSection(
                        title: '节数限制',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DialogDescription('至少填写一项；填写恰好节数时优先按该值计算。'),
                            const SizedBox(height: 12),
                            _DialogGrid(
                              children: [
                                AppTextFormField(
                                  controller: minimum,
                                  decoration: const InputDecoration(
                                    labelText: '最少节数',
                                    hintText: '不限制',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                                AppTextFormField(
                                  controller: maximum,
                                  decoration: const InputDecoration(
                                    labelText: '最多节数',
                                    hintText: '不限制',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                                AppTextFormField(
                                  controller: exact,
                                  decoration: const InputDecoration(
                                    labelText: '恰好节数',
                                    hintText: '不限制',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    AppTextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '备注名称（选填）',
                        hintText: '方便识别这条条件',
                      ),
                    ),
                  ],
                ),
                actions: [
                  AppSecondaryButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'),
                  ),
                  AppPrimaryButton(
                    onPressed:
                        targetId == null ||
                            (mutual &&
                                (otherId == null || otherId == targetId)) ||
                            (type == ScheduleConditionType.periodLimit &&
                                periodTypeId == null)
                        ? null
                        : () {
                            final min = int.tryParse(minimum.text.trim());
                            final max = int.tryParse(maximum.text.trim());
                            final eq = int.tryParse(exact.text.trim());
                            if (!mutual &&
                                min == null &&
                                max == null &&
                                eq == null) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(content: Text('请至少填写一个节数限制')),
                              );
                              return;
                            }
                            Navigator.pop(
                              dialogContext,
                              ScheduleCondition(
                                id:
                                    original?.id ??
                                    'condition-${DateTime.now().microsecondsSinceEpoch}',
                                termId: snapshot.term.id,
                                type: type,
                                targetType: mutual
                                    ? (subjects
                                          ? ScheduleConditionTarget.subject
                                          : ScheduleConditionTarget.teacher)
                                    : targetType,
                                targetId: targetId,
                                otherTargetId: otherId,
                                periodTypeId: periodTypeId,
                                weekday: weekday == 0 ? null : weekday,
                                minimum: min,
                                maximum: max,
                                exact: eq,
                                name: name.text.trim(),
                              ),
                            );
                          },
                    child: Text(original == null ? '添加' : '保存'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (condition != null && context.mounted) {
        await _save(context, [
          ...snapshot.conditions.where((item) => item.id != condition.id),
          condition,
        ], snapshot.preferences);
      }
    } finally {
      await dialogClosed;
      minimum.dispose();
      maximum.dispose();
      exact.dispose();
      name.dispose();
    }
  }
}

class _LockPanel extends StatelessWidget {
  const _LockPanel({
    required this.snapshot,
    required this.enabled,
    required this.onSet,
  });

  final SchedulingSnapshot snapshot;
  final bool enabled;
  final Future<void> Function(ScheduleLock, bool) onSet;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (snapshot.locks.isEmpty)
        const _DrawerEmptyState(
          icon: Icons.lock_outline,
          text: '还没有锁定范围\n添加后，自动排课会保留这些课程',
        )
      else
        for (final lock in snapshot.locks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LockCard(
              name: _lockName(snapshot, lock),
              enabled: enabled,
              onRemove: enabled
                  ? () => unawaited(_set(context, lock, false))
                  : null,
            ),
          ),
      _DashedAddButton(
        label: '添加锁定',
        onPressed: enabled ? () => unawaited(_showAdd(context)) : null,
      ),
    ],
  );

  Future<void> _set(BuildContext context, ScheduleLock lock, bool value) async {
    try {
      await onSet(lock, value);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存锁定失败：$error')));
      }
    }
  }

  Future<void> _showAdd(BuildContext context) async {
    var scope = ScheduleLockScope.schoolClass;
    String? targetId;
    final lock = await showAppDialog<ScheduleLock>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AppDialog(
          maxWidth: 620,
          title: AppDialogTitle(
            title: '添加锁定',
            onClose: () => Navigator.pop(dialogContext),
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DialogDescription('选择要锁定的班级或教师，重新排课时将保留已有课程位置。'),
              const SizedBox(height: 20),
              _DialogSection(
                title: '锁定范围',
                child: _DialogGrid(
                  children: [
                    _choice<ScheduleLockScope>(
                      '锁定对象',
                      scope,
                      ScheduleLockScope.values,
                      (value) =>
                          value == ScheduleLockScope.schoolClass ? '班级' : '教师',
                      (value) => update(() {
                        scope = value;
                        targetId = null;
                      }),
                    ),
                    AppSelectField<String>(
                      key: ValueKey(scope),
                      value: targetId,
                      label: '选择对象',
                      hint: scope == ScheduleLockScope.schoolClass
                          ? '请选择班级'
                          : '请选择教师',
                      searchable: true,
                      searchHint: scope == ScheduleLockScope.schoolClass
                          ? '搜索班级'
                          : '搜索教师',
                      items: _uniqueSelectOptions(
                        scope == ScheduleLockScope.schoolClass
                            ? [
                                for (final item in snapshot.classes)
                                  (item.id, _lockClassLabel(snapshot, item.id)),
                              ]
                            : [
                                for (final item in snapshot.teachers)
                                  (item.id, item.displayName),
                              ],
                      ),
                      onChanged: (value) => update(() => targetId = value),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            AppSecondaryButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            AppPrimaryButton(
              onPressed: targetId == null
                  ? null
                  : () => Navigator.pop(
                      dialogContext,
                      ScheduleLock(
                        termId: snapshot.term.id,
                        scope: scope,
                        targetId: targetId!,
                      ),
                    ),
              child: const Text('锁定'),
            ),
          ],
        ),
      ),
    );
    if (lock != null && context.mounted) await _set(context, lock, true);
  }
}

String _lockClassLabel(SchedulingSnapshot snapshot, String classId) {
  final schoolClass = snapshot.classes
      .where((item) => item.id == classId)
      .firstOrNull;
  if (schoolClass == null) return '未知班级';
  final grade = snapshot.grades
      .where((item) => item.id == schoolClass.gradeId)
      .firstOrNull;
  final stage = snapshot.stages
      .where((item) => item.id == grade?.stageId)
      .firstOrNull;
  return [
    if (stage != null) stage.name,
    if (grade != null && !schoolClass.name.startsWith(grade.name)) grade.name,
    schoolClass.name,
  ].join(' · ');
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({required this.snapshot, required this.state});

  final SchedulingSnapshot snapshot;
  final SchedulingState state;

  @override
  Widget build(BuildContext context) {
    final report = state.run?.report;
    final unplaced = state.items.where((item) => !item.isPlaced).toList();
    final blockersById = {
      for (final entry in report?.unplaced ?? const <ScheduleUnplacedCourse>[])
        entry.itemId: entry.blockers,
      for (final entry in state.placementUnplaced) entry.itemId: entry.blockers,
    };
    final placementIds = state.placementUnplaced
        .map((entry) => entry.itemId)
        .toSet();
    final classNames = {
      for (final item in snapshot.classes) item.id: item.name,
    };
    final subjectNames = {
      for (final item in snapshot.subjects) item.id: item.name,
    };
    return AppSectionPanel(
      title: '当前课表状态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已安排 ${state.items.length - unplaced.length}/${state.items.length} 节 · '
            '暂放 ${unplaced.length} 节',
          ),
          if (report != null) ...[
            const SizedBox(height: 10),
            Text('上次自动排课：候选检查 ${report.candidateChecks} 次'),
            for (final entry in report.preferenceScores.entries)
              Text(
                '${_scoreLabel(entry.key)}：'
                '${entry.value.rate == null ? '不适用' : '${(entry.value.rate! * 100).toStringAsFixed(0)}%'}',
              ),
          ],
          if (report?.unmetHardRequirements.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              '上次自动排课未满足的硬性总量要求',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final blocker in report!.unmetHardRequirements)
              Text('• ${blocker.message}'),
          ],
          if (unplaced.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '暂放课程（${unplaced.length}）',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final item in unplaced)
              _CollapsibleReportItem(
                title: _itemLabel(item, classNames, subjectNames),
                summary: blockersById[item.id]?.firstOrNull == null
                    ? '手工暂放或尚未安排'
                    : '${placementIds.contains(item.id) ? '本次一键放入' : '上次自动排课'}：${blockersById[item.id]!.first.message}',
                blockers:
                    blockersById[item.id]
                        ?.map((blocker) => blocker.message)
                        .toList() ??
                    const [],
              ),
          ],
        ],
      ),
    );
  }
}

class _CollapsibleReportItem extends StatefulWidget {
  const _CollapsibleReportItem({
    required this.title,
    required this.summary,
    required this.blockers,
  });

  final String title;
  final String summary;
  final List<String> blockers;

  @override
  State<_CollapsibleReportItem> createState() => _CollapsibleReportItemState();
}

class _CollapsibleReportItemState extends State<_CollapsibleReportItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppGhostButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(widget.title),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Text(
            widget.summary,
            style: TextStyle(
              color: context.appColors.inkSecondary,
              fontSize: 12,
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final blocker in widget.blockers) Text('• $blocker'),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget _choice<T>(
  String label,
  T value,
  List<T> values,
  String Function(T) describe,
  ValueChanged<T> onChanged,
) => AppSelectField<T>(
  value: value,
  label: label,
  items: {for (final item in values) describe(item): item},
  onChanged: (item) {
    if (item != null) onChanged(item);
  },
);

String _strengthLabel(ScheduleStrength value) => switch (value) {
  ScheduleStrength.fast => '快速',
  ScheduleStrength.normal => '标准',
  ScheduleStrength.high => '高强度',
};

// The select component uses labels as map keys, so repeated names need
// distinct, human-readable labels while their stored values remain IDs.
Map<String, String> _uniqueSelectOptions(List<(String, String)> entries) {
  final counts = <String, int>{};
  for (final (_, label) in entries) {
    counts[label] = (counts[label] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final result = <String, String>{};
  for (final (id, label) in entries) {
    var number = (seen[label] ?? 0) + 1;
    var candidate = counts[label] == 1 ? label : '$label（$number）';
    while (result.containsKey(candidate)) {
      number++;
      candidate = '$label（$number）';
    }
    seen[label] = number;
    result[candidate] = id;
  }
  return result;
}

String _conditionTypeLabel(ScheduleConditionType type) => switch (type) {
  ScheduleConditionType.periodLimit => '指定时段节数',
  ScheduleConditionType.dailyLimit => '每天节数',
  ScheduleConditionType.teacherMutualExclusion => '教师互斥',
  ScheduleConditionType.subjectMutualExclusion => '科目互斥',
  ScheduleConditionType.forbiddenAdjacency => '禁止相邻',
};

String _conditionLabel(ScheduleCondition value, SchedulingSnapshot snapshot) {
  String target(String? id) {
    if (id == null) return '';
    if (value.type == ScheduleConditionType.teacherMutualExclusion ||
        value.targetType == ScheduleConditionTarget.teacher) {
      for (final teacher in snapshot.teachers) {
        if (teacher.id == id) return teacher.displayName;
      }
    } else {
      for (final subject in snapshot.subjects) {
        if (subject.id == id) return subject.name;
      }
    }
    return id;
  }

  String period() {
    final id = value.periodTypeId;
    if (id == null) return '';
    for (final routine in snapshot.routines) {
      for (final item in routine.periodTypes) {
        if (item.id == id) {
          final stage = snapshot.stages
              .where((stage) => stage.id == routine.stageId)
              .firstOrNull;
          return stage == null ? item.name : '${stage.name} · ${item.name}';
        }
      }
    }
    return id;
  }

  return '${_conditionTypeLabel(value.type)} · ${target(value.targetId)}'
      '${value.otherTargetId == null ? '' : ' / ${target(value.otherTargetId)}'}'
      '${value.periodTypeId == null ? '' : ' · ${period()}'}'
      '${value.weekday == null ? '' : ' · 星期${value.weekday}'}'
      '${value.exact == null ? '' : ' · 恰好 ${value.exact} 节'}'
      '${value.minimum == null ? '' : ' · 至少 ${value.minimum} 节'}'
      '${value.maximum == null ? '' : ' · 最多 ${value.maximum} 节'}';
}

String _lockName(SchedulingSnapshot snapshot, ScheduleLock lock) {
  if (lock.scope == ScheduleLockScope.schoolClass) {
    for (final item in snapshot.classes) {
      if (item.id == lock.targetId) return '班级 · ${item.name}';
    }
  } else {
    for (final item in snapshot.teachers) {
      if (item.id == lock.targetId) return '教师 · ${item.displayName}';
    }
  }
  return lock.targetId;
}

String _itemLabel(
  ScheduleItem? item,
  Map<String, String> classes,
  Map<String, String> subjects,
) {
  if (item == null) return '未知课程';
  return '${classes[item.classId] ?? item.classId} · '
      '${subjects[item.subjectId] ?? item.subjectId} · ${item.weekMode.label}';
}

String _scoreLabel(String key) => switch (key) {
  'prefer' => '优先位置',
  'progress' => '教学进度',
  'teacherDistribution' => '教师分布',
  'consecutive' => '连堂偏好',
  'balanced' => '课表均衡',
  _ => key,
};

class _ScheduleReconciliationOverlay extends StatelessWidget {
  const _ScheduleReconciliationOverlay({
    required this.baseline,
    required this.current,
    required this.preview,
    required this.busy,
    required this.error,
    required this.onPreview,
    required this.onApply,
    required this.onClose,
    super.key,
  });

  final SchedulingSnapshot baseline;
  final SchedulingSnapshot current;
  final ScheduleReconciliationPreview? preview;
  final bool busy;
  final String? error;
  final VoidCallback onPreview;
  final VoidCallback onApply;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final changes =
        preview?.changes ??
        const ScheduleReconciler().describeChanges(baseline, current);
    final groups = changes.map((change) => change.group).toSet();
    return ColoredBox(
      color: context.appColors.canvas.withValues(alpha: .92),
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: constraints.maxHeight > 64
                  ? constraints.maxHeight - 48
                  : constraints.maxHeight,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .09),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tune_outlined,
                        size: 22,
                        color: context.appColors.warning,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '课表待协调',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '设置已保存。当前显示的是变更前的课表，完成增量协调前暂不可编辑。'
                    '协调会尽量保留原课位，并先展示调整预览。',
                    style: TextStyle(
                      color: context.appColors.inkSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (error != null) ...[
                          AppInlineMessage(
                            message: error!,
                            icon: Icons.error_outline,
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (changes.isEmpty)
                          const Text('排课约束已有变化，请生成协调预览查看受影响课程。'),
                        for (final group in groups) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, top: 8),
                            child: Text(
                              group,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          for (final change in changes.where(
                            (item) => item.group == group,
                          ))
                            _changeRow(context, change),
                        ],
                        if (preview case final result?) ...[
                          const SizedBox(height: 18),
                          Divider(color: context.appColors.border),
                          const SizedBox(height: 10),
                          const Text(
                            '调整预览',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '保留 ${result.keptCount} 节 · 调整 ${result.movedCount} 节 · '
                            '暂放 ${result.unplacedCount} 节 · 新增 ${result.addedCount} 节 · '
                            '减少 ${result.removedCount} 节',
                            style: TextStyle(
                              color: context.appColors.inkSecondary,
                              fontSize: 13,
                            ),
                          ),
                          if (result.locksToRelease.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '确认后会解除受影响的 ${result.locksToRelease.length} 项锁定。',
                                style: TextStyle(
                                  color: context.appColors.warning,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          for (final check in result.checks.where(
                            (check) => !check.ready,
                          ))
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '待处理：${check.message}',
                                style: TextStyle(
                                  color: context.appColors.destructive,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (result.adjustments.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            for (final adjustment in result.adjustments)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 7),
                                child: Text(
                                  '${adjustment.label}：${adjustment.before} → ${adjustment.after}',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppGhostButton(
                        onPressed: busy ? null : onClose,
                        child: const Text('暂不协调'),
                      ),
                      const SizedBox(width: 10),
                      if (preview != null) ...[
                        AppGhostButton(
                          onPressed: busy ? null : onPreview,
                          child: const Text('重新计算'),
                        ),
                        const SizedBox(width: 10),
                      ],
                      AppPrimaryButton(
                        onPressed: busy
                            ? null
                            : preview == null
                            ? onPreview
                            : preview!.canApply
                            ? onApply
                            : null,
                        child: Text(
                          busy
                              ? '处理中…'
                              : preview == null
                              ? '增量协调'
                              : '确认应用调整',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _changeRow(BuildContext context, ScheduleSettingChange change) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(change.label, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 3),
            Text(
              '${change.before}  →  ${change.after}',
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
}
