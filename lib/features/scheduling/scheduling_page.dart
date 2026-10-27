import 'dart:async';

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
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
import 'package:class_set/features/scheduling/scheduling_timetable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

class SchedulingPage extends ConsumerStatefulWidget {
  const SchedulingPage({required this.termId, super.key});

  final String termId;

  @override
  ConsumerState<SchedulingPage> createState() => _SchedulingPageState();
}

class _SchedulingPageState extends ConsumerState<SchedulingPage> {
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
            AbsorbPointer(
              absorbing: pending != null,
              child: SchedulingTimetable(
                snapshot: snapshot,
                state: state,
                onStart: () => unawaited(_showStartDialog(state, controller)),
                onRefresh: () => unawaited(controller.detect()),
                onRules: () => unawaited(_showRulesDialog(controller)),
                onReport: () => unawaited(_showReportDialog(state, snapshot)),
                onDetectionReport: () => unawaited(_showDetectionDialog(state)),
                onCancel: controller.cancel,
                onDone: () => unawaited(controller.refresh()),
                onExport: (items, title) =>
                    unawaited(_showExportDialog(snapshot, items, title)),
                onPreviewMove: controller.previewMove,
                onMove: controller.move,
                onUndo: () => unawaited(controller.undo()),
                onRedo: () => unawaited(controller.redo()),
                onSetLock: (lock, enabled) =>
                    controller.setLock(lock, enabled: enabled),
                onSetAllLocks: (enabled) =>
                    controller.setAllClassLocks(enabled: enabled),
              ),
            ),
            if (pending != null && current != null)
              _ScheduleReconciliationOverlay(
                baseline: pending,
                current: current,
                preview: state.reconciliationPreview,
                busy: state.reconciling,
                error: state.error,
                onPreview: () => unawaited(controller.previewReconciliation()),
                onApply: () => unawaited(controller.applyReconciliation()),
              ),
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
                  const SizedBox(height: 28),
                  _DialogSection(
                    title: '第一次排课检查清单',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 12),
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
                            AppGhostButton(
                              onPressed: () =>
                                  update(() => showClasses = !showClasses),
                              child: Text(showClasses ? '收起逐班选择' : '逐班勾选'),
                            ),
                          ],
                        );
                        final strengthChoices = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '求解强度',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            for (final option in const [
                              (ScheduleStrength.fast, '快速 · 适合小规模微调'),
                              (ScheduleStrength.normal, '正常（推荐）· 速度与质量均衡'),
                              (ScheduleStrength.high, '高精度 · 适合最终定稿前重排'),
                            ])
                              AppRadioOption<ScheduleStrength>(
                                value: option.$1,
                                groupValue: strength,
                                label: option.$2,
                                onChanged: (value) =>
                                    update(() => strength = value),
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
                                  Expanded(child: scope),
                                  const SizedBox(width: 32),
                                  Expanded(child: strengthChoices),
                                ],
                              )
                            else ...[
                              scope,
                              const SizedBox(height: 24),
                              strengthChoices,
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
                            const SizedBox(height: 20),
                            FSwitch(
                              value: fixedSeed,
                              onChange: (value) =>
                                  update(() => fixedSeed = value),
                              label: const Text('固定随机种子'),
                            ),
                            if (fixedSeed)
                              SizedBox(
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
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final snapshot = ref
              .watch(schedulingControllerProvider(widget.termId))
              .snapshot;
          if (snapshot == null) return const SizedBox.shrink();
          return AppDialog(
            maxWidth: 720,
            title: AppDialogTitle(
              title: '排课规则与锁定',
              onClose: () => Navigator.pop(dialogContext),
            ),
            content: Column(
              children: [
                _RulePanel(
                  snapshot: snapshot,
                  enabled: true,
                  onSave: (conditions, preferences) =>
                      controller.saveConfiguration(
                        conditions: conditions,
                        preferences: preferences,
                      ),
                ),
                const SizedBox(height: 12),
                _LockPanel(
                  snapshot: snapshot,
                  enabled: true,
                  onSet: (lock, enabled) =>
                      controller.setLock(lock, enabled: enabled),
                ),
              ],
            ),
            actions: [
              AppPrimaryButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('完成'),
              ),
            ],
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
    String title,
  ) async {
    final export = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        maxWidth: 480,
        title: AppDialogTitle(
          title: '导出/打印课表',
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              '导出当前视图的 ${items.length} 节已排课程为 Excel 文件。'
              '保存后可在表格软件中打印。',
            ),
          ],
        ),
        actions: [
          AppSecondaryButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          AppPrimaryButton(
            onPressed: items.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('导出 Excel'),
          ),
        ],
      ),
    );
    if (export != true || !mounted) return;
    try {
      final location = await getSaveLocation(
        suggestedName: '课集课表.xlsx',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
        ],
      );
      if (location == null) return;
      final bytes = buildScheduleWorkbook(snapshot, items);
      await XFile.fromData(
        Uint8List.fromList(bytes),
        name: '课集课表.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ).saveTo(location.path);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('课表已导出')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出课表失败：$error')));
      }
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
    padding: const EdgeInsets.only(bottom: 16),
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
    return AppSectionPanel(
      title: '排课范围 · ${selected.length}/${allIds.length} 个班级',
      trailing: AppGhostButton(
        onPressed: enabled ? () => onChanged(allIds) : null,
        child: const Text('全校'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('未选班级的课表保持原位，并继续占用教师与场室。'),
          const SizedBox(height: 8),
          for (final stage in snapshot.stages)
            _CollapsibleStage(
              title: stage.name,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppGhostButton(
                      onPressed: !enabled
                          ? null
                          : () => onChanged({
                              ...selected,
                              for (final grade in snapshot.grades.where(
                                (item) => item.stageId == stage.id,
                              ))
                                ...snapshot.classes
                                    .where((item) => item.gradeId == grade.id)
                                    .map((item) => item.id),
                            }),
                      child: const Text('选全学段'),
                    ),
                  ),
                  for (final grade in snapshot.grades.where(
                    (item) => item.stageId == stage.id,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(grade.name)),
                              AppGhostButton(
                                onPressed: !enabled
                                    ? null
                                    : () {
                                        final ids = snapshot.classes
                                            .where(
                                              (item) =>
                                                  item.gradeId == grade.id,
                                            )
                                            .map((item) => item.id)
                                            .toSet();
                                        onChanged({...selected, ...ids});
                                      },
                                child: const Text('选全年级'),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              for (final schoolClass in snapshot.classes.where(
                                (item) => item.gradeId == grade.id,
                              ))
                                AppActionPill(
                                  selected: selected.contains(schoolClass.id),
                                  onPressed: !enabled
                                      ? null
                                      : () {
                                          final next = {...selected};
                                          if (!next.add(schoolClass.id)) {
                                            next.remove(schoolClass.id);
                                          }
                                          onChanged(next);
                                        },
                                  child: Text(schoolClass.name),
                                ),
                            ],
                          ),
                        ],
                      ),
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
  const _CollapsibleStage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_CollapsibleStage> createState() => _CollapsibleStageState();
}

class _CollapsibleStageState extends State<_CollapsibleStage> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppGhostButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          label: Text(widget.title),
        ),
        if (_expanded) widget.child,
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
  Widget build(BuildContext context) => AppSectionPanel(
    title: '规则与偏好',
    trailing: AppGhostButton(
      onPressed: enabled ? () => unawaited(_showPreferences(context)) : null,
      child: const Text('调整偏好'),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '强度：${_strengthLabel(snapshot.preferences.strength)}  ·  '
          '自定义硬条件：${snapshot.conditions.length} 条',
        ),
        const SizedBox(height: 8),
        for (final condition in snapshot.conditions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        condition.name?.isNotEmpty == true
                            ? condition.name!
                            : _conditionLabel(condition, snapshot),
                      ),
                      Text(
                        _conditionLabel(condition, snapshot),
                        style: TextStyle(
                          color: context.appColors.inkSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                AppIconButton(
                  tooltip: '编辑条件',
                  icon: Icons.edit_outlined,
                  onPressed: enabled
                      ? () =>
                            unawaited(_showConditionEditor(context, condition))
                      : null,
                ),
                AppIconButton(
                  tooltip: '删除条件',
                  icon: Icons.delete_outline,
                  onPressed: !enabled
                      ? null
                      : () => unawaited(
                          _save(
                            context,
                            snapshot.conditions
                                .where((item) => item.id != condition.id)
                                .toList(),
                            snapshot.preferences,
                          ),
                        ),
                ),
              ],
            ),
          ),
        AppSecondaryButton(
          onPressed: enabled
              ? () => unawaited(_showConditionEditor(context))
              : null,
          child: const Text('添加硬条件'),
        ),
      ],
    ),
  );

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

  Future<void> _showPreferences(BuildContext context) async {
    var strength = snapshot.preferences.strength;
    var progress = snapshot.preferences.progressConsistency;
    var distribution = snapshot.preferences.teacherDistribution;
    var consecutive = snapshot.preferences.consecutiveMode;
    var lunch = snapshot.preferences.protectLunchBreak;
    var checkProgress = snapshot.preferences.checkProgressConsistency;
    final value = await showAppDialog<SchedulePreferences>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AppDialog(
          title: const Text('排课偏好'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _choice<ScheduleStrength>(
                '求解强度',
                strength,
                ScheduleStrength.values,
                _strengthLabel,
                (next) => update(() => strength = next),
              ),
              _choice<ProgressConsistency>(
                '同级同科进度',
                progress,
                ProgressConsistency.values,
                (value) =>
                    value == ProgressConsistency.require ? '必须同步' : '尽量同步',
                (next) => update(() => progress = next),
              ),
              _choice<TeacherDistribution>(
                '教师日分布',
                distribution,
                TeacherDistribution.values,
                (value) => switch (value) {
                  TeacherDistribution.indifferent => '不限制',
                  TeacherDistribution.spread => '尽量分散',
                  TeacherDistribution.concentrate => '尽量集中',
                },
                (next) => update(() => distribution = next),
              ),
              _choice<ConsecutiveMode>(
                '连堂偏好',
                consecutive,
                ConsecutiveMode.values,
                (value) => switch (value) {
                  ConsecutiveMode.preferSeparate => '尽量不连堂',
                  ConsecutiveMode.requireSeparate => '禁止连堂',
                  ConsecutiveMode.preferTogether => '尽量连堂',
                },
                (next) => update(() => consecutive = next),
              ),
              AppCheckbox(
                label: const Text('保护午间休息'),
                value: lunch,
                onChanged: (value) => update(() => lunch = value),
              ),
              AppCheckbox(
                label: const Text('检查教学进度一致性'),
                value: checkProgress,
                onChanged: (value) => update(() => checkProgress = value),
              ),
            ],
          ),
          actions: [
            AppSecondaryButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            AppPrimaryButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                SchedulePreferences(
                  strength: strength,
                  progressConsistency: progress,
                  teacherDistribution: distribution,
                  consecutiveMode: consecutive,
                  protectLunchBreak: lunch,
                  checkProgressConsistency: checkProgress,
                ),
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (value != null && context.mounted) {
      await _save(context, snapshot.conditions, value);
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
    try {
      final condition = await showAppDialog<ScheduleCondition>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
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
            final targets = subjects
                ? snapshot.subjects
                      .map((item) => (item.id, '${item.name} · ${item.id}'))
                      .toList()
                : snapshot.teachers
                      .map(
                        (item) => (item.id, '${item.displayName} · ${item.id}'),
                      )
                      .toList();
            final periods = snapshot.routines
                .expand((item) => item.periodTypes)
                .fold<Map<String, String>>({}, (result, item) {
                  result[item.id] = '${item.name} · ${item.id}';
                  return result;
                });
            return AppDialog(
              title: Text(original == null ? '添加硬条件' : '编辑硬条件'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
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
                      (value) => value == ScheduleConditionTarget.subject
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
                    items: {for (final entry in targets) entry.$2: entry.$1},
                    onChanged: (value) => update(() => targetId = value),
                  ),
                  if (mutual)
                    AppSelectField<String>(
                      key: ValueKey('other-$type'),
                      value: otherId,
                      label: '对象 B',
                      items: {for (final entry in targets) entry.$2: entry.$1},
                      onChanged: (value) => update(() => otherId = value),
                    ),
                  if (type == ScheduleConditionType.periodLimit)
                    AppSelectField<String>(
                      value: periodTypeId,
                      label: '时段',
                      items: {
                        for (final entry in periods.entries)
                          entry.value: entry.key,
                      },
                      onChanged: (value) => update(() => periodTypeId = value),
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
                        for (var day = 1; day <= 7; day++) '星期$day': day,
                      },
                      onChanged: (value) => update(() => weekday = value ?? 0),
                    ),
                  if (!mutual) ...[
                    AppTextFormField(
                      controller: minimum,
                      decoration: const InputDecoration(labelText: '最少节数'),
                      keyboardType: TextInputType.number,
                    ),
                    AppTextFormField(
                      controller: maximum,
                      decoration: const InputDecoration(labelText: '最多节数'),
                      keyboardType: TextInputType.number,
                    ),
                    AppTextFormField(
                      controller: exact,
                      decoration: const InputDecoration(
                        labelText: '恰好节数（填写后优先）',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  AppTextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '备注名称'),
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
        ),
      );
      if (condition != null && context.mounted) {
        await _save(context, [
          ...snapshot.conditions.where((item) => item.id != condition.id),
          condition,
        ], snapshot.preferences);
      }
    } finally {
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
  Widget build(BuildContext context) => AppSectionPanel(
    title: '锁定已有课表',
    trailing: AppGhostButton(
      onPressed: enabled ? () => unawaited(_showAdd(context)) : null,
      child: const Text('添加锁定'),
    ),
    child: snapshot.locks.isEmpty
        ? const Text('尚无锁定。锁定班级或教师后，其已有课程在重新排课时固定位置。')
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final lock in snapshot.locks)
                AppActionPill(
                  onPressed: enabled
                      ? () => unawaited(_set(context, lock, false))
                      : null,
                  child: Text('${_lockName(snapshot, lock)}  ×'),
                ),
            ],
          ),
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
          title: const Text('添加锁定'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _choice<ScheduleLockScope>(
                '锁定对象',
                scope,
                ScheduleLockScope.values,
                (value) => value == ScheduleLockScope.schoolClass ? '班级' : '教师',
                (value) => update(() {
                  scope = value;
                  targetId = null;
                }),
              ),
              AppSelectField<String>(
                key: ValueKey(scope),
                value: targetId,
                label: '选择对象',
                items: scope == ScheduleLockScope.schoolClass
                    ? {
                        for (final item in snapshot.classes)
                          '${item.name} · ${item.id}': item.id,
                      }
                    : {
                        for (final item in snapshot.teachers)
                          '${item.displayName} · ${item.id}': item.id,
                      },
                onChanged: (value) => update(() => targetId = value),
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
    };
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
                    : '上次自动排课：${blockersById[item.id]!.first.message}',
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
        if (item.id == id) return item.name;
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
      if (item.id == lock.targetId) return '班级 ${item.name}';
    }
  } else {
    for (final item in snapshot.teachers) {
      if (item.id == lock.targetId) return '教师 ${item.displayName}';
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
  });

  final SchedulingSnapshot baseline;
  final SchedulingSnapshot current;
  final ScheduleReconciliationPreview? preview;
  final bool busy;
  final String? error;
  final VoidCallback onPreview;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final changes =
        preview?.changes ??
        const ScheduleReconciler().describeChanges(baseline, current);
    final groups = changes.map((change) => change.group).toSet();
    return ColoredBox(
      color: const Color(0xEAF4F6FA),
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
                border: Border.all(color: context.appColors.border),
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
