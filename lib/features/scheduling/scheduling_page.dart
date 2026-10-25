import 'dart:async';

import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SchedulingPage extends ConsumerWidget {
  const SchedulingPage({required this.termId, super.key});

  final String termId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(schedulingControllerProvider(termId));
    final controller = ref.read(schedulingControllerProvider(termId).notifier);
    final snapshot = state.snapshot;
    final busy =
        state.status == SchedulingStatus.loading ||
        state.status == SchedulingStatus.solving ||
        state.status == SchedulingStatus.committing;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppPageHeader(
          title: '自动排课',
          subtitle: '确认范围与规则后生成课表。已有排课在求解期间保持可用。',
          responsiveActions: true,
          actions: [
            AppSecondaryButton(
              onPressed: busy ? null : () => unawaited(controller.refresh()),
              child: const Text('重新检查'),
            ),
            if (state.status == SchedulingStatus.solving)
              AppSecondaryButton(
                onPressed: controller.cancel,
                child: const Text('取消排课'),
              )
            else
              AppPrimaryButton(
                onPressed: state.canStart
                    ? () => unawaited(
                        controller.start(
                          seed: DateTime.now().millisecondsSinceEpoch,
                        ),
                      )
                    : null,
                child: Text(
                  state.status == SchedulingStatus.committing
                      ? '正在保存…'
                      : '开始排课',
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (state.error != null) ...[
          AppInlineMessage(message: state.error!, icon: Icons.error_outline),
          const SizedBox(height: 16),
        ],
        if (state.backupWarning != null) ...[
          AppInlineMessage(
            message: state.backupWarning!,
            icon: Icons.warning_amber_outlined,
          ),
          const SizedBox(height: 16),
        ],
        if (snapshot == null)
          AppSectionPanel(
            title: '准备排课资料',
            child: state.status == SchedulingStatus.loading
                ? const LinearProgressIndicator()
                : const Text('尚未加载学期数据。'),
          )
        else ...[
          _ScopePanel(
            snapshot: snapshot,
            selected: state.selectedClassIds,
            enabled: !busy,
            onChanged: controller.selectClasses,
          ),
          const SizedBox(height: 16),
          _RulePanel(
            snapshot: snapshot,
            enabled: !busy,
            onSave: (conditions, preferences) => controller.saveConfiguration(
              conditions: conditions,
              preferences: preferences,
            ),
          ),
          const SizedBox(height: 16),
          _LockPanel(
            snapshot: snapshot,
            enabled: !busy,
            onSet: (lock, enabled) =>
                controller.setLock(lock, enabled: enabled),
          ),
          const SizedBox(height: 16),
          AppSectionPanel(
            title: '启动前检查',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.checks.isEmpty) const Text('基础资料检查通过，可以开始排课。'),
                for (final check in state.checks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          check.ready
                              ? Icons.info_outline
                              : Icons.error_outline,
                          size: 18,
                          color: check.ready ? Colors.blueGrey : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(check.message)),
                      ],
                    ),
                  ),
                if (state.status == SchedulingStatus.loading ||
                    state.status == SchedulingStatus.committing)
                  const LinearProgressIndicator(),
                if (state.status == SchedulingStatus.solving) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: state.progress?.fraction.clamp(0, 1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.progress == null
                        ? '正在生成候选课表…'
                        : '已检查 ${state.progress!.candidateChecks} 个候选；'
                              '当前覆盖 ${state.progress!.bestCoverage} 个实际周课节',
                  ),
                ],
                if (state.status == SchedulingStatus.cancelled)
                  const Text('已取消，本次没有保存候选课表。'),
              ],
            ),
          ),
          if (state.run != null) ...[
            const SizedBox(height: 16),
            _ReportPanel(snapshot: snapshot, state: state),
          ],
        ],
      ],
    );
  }
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
      trailing: TextButton(
        onPressed: enabled ? () => onChanged(allIds) : null,
        child: const Text('全校'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('未选班级的课表保持原位，并继续占用教师与场室。'),
          const SizedBox(height: 8),
          for (final stage in snapshot.stages)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(stage.name),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
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
                            TextButton(
                              onPressed: !enabled
                                  ? null
                                  : () {
                                      final ids = snapshot.classes
                                          .where(
                                            (item) => item.gradeId == grade.id,
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
                              FilterChip(
                                label: Text(schoolClass.name),
                                selected: selected.contains(schoolClass.id),
                                onSelected: !enabled
                                    ? null
                                    : (value) {
                                        final next = {...selected};
                                        value
                                            ? next.add(schoolClass.id)
                                            : next.remove(schoolClass.id);
                                        onChanged(next);
                                      },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
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
    trailing: TextButton(
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              condition.name?.isNotEmpty == true
                  ? condition.name!
                  : _conditionLabel(condition, snapshot),
            ),
            subtitle: Text(_conditionLabel(condition, snapshot)),
            onTap: enabled
                ? () => unawaited(_showConditionEditor(context, condition))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '编辑条件',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: enabled
                      ? () =>
                            unawaited(_showConditionEditor(context, condition))
                      : null,
                ),
                IconButton(
                  tooltip: '删除条件',
                  icon: const Icon(Icons.delete_outline),
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
    final value = await showDialog<SchedulePreferences>(
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
              CheckboxListTile(
                title: const Text('保护午间休息'),
                value: lunch,
                onChanged: (value) => update(() => lunch = value ?? false),
              ),
              CheckboxListTile(
                title: const Text('检查教学进度一致性'),
                value: checkProgress,
                onChanged: (value) =>
                    update(() => checkProgress = value ?? false),
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
      final condition = await showDialog<ScheduleCondition>(
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
                ? snapshot.subjects.map((item) => (item.id, item.name)).toList()
                : snapshot.teachers
                      .map((item) => (item.id, item.displayName))
                      .toList();
            final periods = snapshot.routines
                .expand((item) => item.periodTypes)
                .fold<Map<String, String>>({}, (result, item) {
                  result[item.id] = item.name;
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
                  DropdownButtonFormField<String>(
                    key: ValueKey('target-$type-$targetType'),
                    initialValue: targetId,
                    decoration: InputDecoration(
                      labelText: mutual ? '对象 A' : '对象',
                    ),
                    items: [
                      for (final entry in targets)
                        DropdownMenuItem(
                          value: entry.$1,
                          child: Text(entry.$2),
                        ),
                    ],
                    onChanged: (value) => update(() => targetId = value),
                  ),
                  if (mutual)
                    DropdownButtonFormField<String>(
                      key: ValueKey('other-$type'),
                      initialValue: otherId,
                      decoration: const InputDecoration(labelText: '对象 B'),
                      items: [
                        for (final entry in targets)
                          DropdownMenuItem(
                            value: entry.$1,
                            child: Text(entry.$2),
                          ),
                      ],
                      onChanged: (value) => update(() => otherId = value),
                    ),
                  if (type == ScheduleConditionType.periodLimit)
                    DropdownButtonFormField<String>(
                      initialValue: periodTypeId,
                      decoration: const InputDecoration(labelText: '时段'),
                      items: [
                        for (final entry in periods.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) => update(() => periodTypeId = value),
                    ),
                  if (!mutual)
                    DropdownButtonFormField<int>(
                      initialValue: weekday,
                      decoration: InputDecoration(
                        labelText: type == ScheduleConditionType.dailyLimit
                            ? '适用星期'
                            : '统计星期',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 0,
                          child: Text(
                            type == ScheduleConditionType.dailyLimit
                                ? '每天分别计算'
                                : '整周合计',
                          ),
                        ),
                        for (var day = 1; day <= 7; day++)
                          DropdownMenuItem(value: day, child: Text('星期$day')),
                      ],
                      onChanged: (value) => update(() => weekday = value ?? 0),
                    ),
                  if (!mutual) ...[
                    TextField(
                      controller: minimum,
                      decoration: const InputDecoration(labelText: '最少节数'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: maximum,
                      decoration: const InputDecoration(labelText: '最多节数'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: exact,
                      decoration: const InputDecoration(
                        labelText: '恰好节数（填写后优先）',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  TextField(
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
    trailing: TextButton(
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
                InputChip(
                  label: Text(_lockName(snapshot, lock)),
                  onDeleted: enabled
                      ? () => unawaited(_set(context, lock, false))
                      : null,
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
    final lock = await showDialog<ScheduleLock>(
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
              DropdownButtonFormField<String>(
                key: ValueKey(scope),
                initialValue: targetId,
                decoration: const InputDecoration(labelText: '选择对象'),
                items: scope == ScheduleLockScope.schoolClass
                    ? [
                        for (final item in snapshot.classes)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                      ]
                    : [
                        for (final item in snapshot.teachers)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.displayName),
                          ),
                      ],
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
    final report = state.run!.report;
    final byItem = {for (final item in state.run!.items) item.id: item};
    final classNames = {
      for (final item in snapshot.classes) item.id: item.name,
    };
    final subjectNames = {
      for (final item in snapshot.subjects) item.id: item.name,
    };
    return AppSectionPanel(
      title: state.status == SchedulingStatus.completed ? '本次排课结果' : '上次排课结果',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已安排 ${report.placedItems}/${report.totalItems} 节 · '
            '双周覆盖 ${report.coverage} 次 · '
            '候选检查 ${report.candidateChecks} 次',
          ),
          const SizedBox(height: 10),
          for (final entry in report.preferenceScores.entries)
            Text(
              '${_scoreLabel(entry.key)}：'
              '${entry.value.rate == null ? '不适用' : '${(entry.value.rate! * 100).toStringAsFixed(0)}%'}',
            ),
          if (report.unmetHardRequirements.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('未满足的硬性总量要求', style: Theme.of(context).textTheme.titleSmall),
            for (final blocker in report.unmetHardRequirements)
              Text('• ${blocker.message}'),
          ],
          if (report.unplaced.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '暂放课程（${report.unplaced.length}）',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final course in report.unplaced)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  _itemLabel(byItem[course.itemId], classNames, subjectNames),
                ),
                subtitle: Text(
                  course.blockers.isEmpty
                      ? '候选预算耗尽或没有可用位置'
                      : course.blockers.first.message,
                ),
                children: [
                  for (final blocker in course.blockers)
                    ListTile(dense: true, title: Text(blocker.message)),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

Widget _choice<T>(
  String label,
  T value,
  List<T> values,
  String Function(T) describe,
  ValueChanged<T> onChanged,
) => DropdownButtonFormField<T>(
  initialValue: value,
  decoration: InputDecoration(labelText: label),
  items: [
    for (final item in values)
      DropdownMenuItem(value: item, child: Text(describe(item))),
  ],
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
