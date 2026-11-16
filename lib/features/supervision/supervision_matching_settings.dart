part of 'supervision_page.dart';

class _MatchingPreferencesEditor extends StatelessWidget {
  const _MatchingPreferencesEditor({
    required this.value,
    required this.onChanged,
    this.allowSubject = true,
    this.global = false,
  });
  final SupervisionMatchingPreferences value;
  final ValueChanged<SupervisionMatchingPreferences> onChanged;
  final bool allowSubject;
  final bool global;

  void _move(int index, int offset) {
    final order = [...value.order];
    final target = index + offset;
    if (target < 0 || target >= order.length) return;
    final item = order.removeAt(index);
    order.insert(target, item);
    onChanged(value.copyWith(order: order));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final colors = context.appColors;
    final preferences = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('匹配优先级', style: theme.titleSmall),
        Text(
          '从上到下逐项比较；关闭的项目不参与匹配。',
          style: theme.bodySmall?.copyWith(color: colors.inkSecondary),
        ),
        const SizedBox(height: 10),
        for (final (index, preference) in value.order.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: value.enabled.contains(preference)
                    ? colors.selectedBlue
                    : colors.surface,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(
                  children: [
                    AppCheckbox(
                      key: ValueKey('matching-enable-${preference.name}'),
                      value: value.enabled.contains(preference),
                      onChanged:
                          preference == SupervisionPreference.subjectTeacher &&
                              !allowSubject
                          ? null
                          : (checked) {
                              final enabled = {...value.enabled};
                              checked
                                  ? enabled.add(preference)
                                  : enabled.remove(preference);
                              onChanged(value.copyWith(enabled: enabled));
                            },
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: value.enabled.contains(preference)
                            ? colors.blue
                            : colors.canvas,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: value.enabled.contains(preference)
                              ? colors.surface
                              : colors.inkSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preference.label,
                            style: theme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color:
                                  preference ==
                                          SupervisionPreference
                                              .subjectTeacher &&
                                      !allowSubject
                                  ? colors.muted
                                  : colors.ink,
                            ),
                          ),
                          Text(
                            switch (preference) {
                              SupervisionPreference.classTeacher =>
                                '实际任教该班的教师优先；合班优先覆盖更多班级。',
                              SupervisionPreference.gradeTeacher =>
                                '优先安排本学期实际任教该年级的教师。',
                              SupervisionPreference.subjectTeacher =>
                                global
                                    ? '仅对设置了目标学科的岗位生效。'
                                    : allowSubject
                                    ? '实际任教学科命中岗位目标学科。'
                                    : '先在上方为岗位选择目标学科。',
                            },
                            style: theme.bodySmall?.copyWith(
                              color: colors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      key: ValueKey('matching-up-${preference.name}'),
                      onPressed: index == 0 ? null : () => _move(index, -1),
                      icon: Icons.arrow_upward,
                      tooltip: '上移${preference.label}',
                      iconSize: 15,
                    ),
                    AppIconButton(
                      key: ValueKey('matching-down-${preference.name}'),
                      onPressed: index == value.order.length - 1
                          ? null
                          : () => _move(index, 1),
                      icon: Icons.arrow_downward,
                      tooltip: '下移${preference.label}',
                      iconSize: 15,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    final modes = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('排序方式', style: theme.titleSmall),
        const SizedBox(height: 8),
        _DutySegments<SupervisionMatchMode>(
          items: const {
            SupervisionMatchMode.matchFirst: '匹配优先',
            SupervisionMatchMode.balanceFirst: '均衡优先',
          },
          value: value.mode,
          onChanged: (mode) => onChanged(value.copyWith(mode: mode)),
        ),
        const SizedBox(height: 8),
        Text(
          '先尽量排满岗位，再按匹配程度或带班工作量排序。',
          style: theme.bodySmall?.copyWith(color: colors.inkSecondary),
        ),
        const SizedBox(height: 20),
        Text('匹配门槛', style: theme.titleSmall),
        const SizedBox(height: 8),
        _DutySegments<SupervisionMatchRequirement>(
          items: const {
            SupervisionMatchRequirement.none: '不限',
            SupervisionMatchRequirement.any: '满足任一',
            SupervisionMatchRequirement.all: '满足全部',
          },
          value: value.requirement,
          onChanged: (requirement) =>
              onChanged(value.copyWith(requirement: requirement)),
        ),
        const SizedBox(height: 8),
        Text(
          value.enabled.isEmpty
              ? '未启用匹配偏好，候选池内的合法教师均可参与。'
              : value.requirement == SupervisionMatchRequirement.none
              ? '偏好用于排序；未命中时其他合法教师仍可补位。'
              : value.requirement == SupervisionMatchRequirement.any
              ? '至少命中一项已启用偏好；无合格教师时保留缺岗。'
              : '须命中全部已启用偏好；无合格教师时保留缺岗。班级、年级条件需覆盖合班来源。',
          style: theme.bodySmall?.copyWith(color: colors.inkSecondary),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 720
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: preferences),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: modes),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [preferences, const SizedBox(height: 12), modes],
            ),
    );
  }
}

class _MatchingPreferencesDialog extends StatefulWidget {
  const _MatchingPreferencesDialog({required this.initial});
  final SupervisionMatchingPreferences initial;
  @override
  State<_MatchingPreferencesDialog> createState() =>
      _MatchingPreferencesDialogState();
}

class _MatchingPreferencesDialogState
    extends State<_MatchingPreferencesDialog> {
  late var _value = widget.initial;
  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('人员匹配'),
    maxWidth: 920,
    titleGap: 12,
    actionsGap: 16,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '作为所有岗位的默认规则，岗位可单独覆盖。时间冲突、禁排和带班上限始终生效。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.appColors.inkSecondary),
        ),
        const SizedBox(height: 16),
        _MatchingPreferencesEditor(
          value: _value,
          global: true,
          onChanged: (value) => setState(() => _value = value),
        ),
      ],
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: () => Navigator.pop(context, _value),
        child: const Text('应用'),
      ),
    ],
  );
}

enum _PersonnelEditMode { all, pool, matching }

typedef _PersonnelSettings = ({
  String? poolId,
  SupervisionMatchingPreferences? preferences,
  Set<String>? subjects,
});

class _PostPersonnelDialog extends StatefulWidget {
  const _PostPersonnelDialog({
    required this.draft,
    required this.snapshot,
    required this.initial,
    this.count = 1,
    this.mode = _PersonnelEditMode.all,
  });
  final SupervisionDraft draft;
  final SchedulingSnapshot snapshot;
  final _PersonnelSettings initial;
  final int count;
  final _PersonnelEditMode mode;
  @override
  State<_PostPersonnelDialog> createState() => _PostPersonnelDialogState();
}

class _PostPersonnelDialogState extends State<_PostPersonnelDialog> {
  late String? _poolId = widget.initial.poolId;
  late bool _inherit = widget.initial.preferences == null;
  late var _preferences =
      widget.initial.preferences ?? widget.draft.matchingPreferences;
  late final _subjects = {...?widget.initial.subjects};
  late bool _applySubjects = widget.count == 1;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: Text(widget.count > 1 ? '批量设置 · ${widget.count} 个岗位' : '岗位人员设置'),
      maxWidth: 920,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.count > 1
                ? '仅修改本次设置项，保留现有教师指派。'
                : '跟随默认设置，或为这个岗位指定候选范围与匹配规则。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.inkSecondary),
          ),
          if (widget.mode != _PersonnelEditMode.matching) ...[
            const SizedBox(height: 16),
            AppSelectField<String>(
              key: const ValueKey('post-teacher-pool'),
              label: '教师候选池',
              value: _poolId ?? '',
              items: {
                '跟随默认 · ${widget.draft.defaultTeacherPoolName}': '',
                if (_poolId != null &&
                    _poolId != SupervisionDraft.basePoolId &&
                    !widget.draft.teacherPools.any(
                      (pool) => pool.id == _poolId,
                    ))
                  '已失效候选池（请重新选择）': _poolId!,
                '基础候选池 · ${widget.draft.teacherIds.length} 人':
                    SupervisionDraft.basePoolId,
                for (final pool in widget.draft.teacherPools)
                  '${pool.name} · ${pool.teacherIds.length} 人': pool.id,
              },
              onChanged: (id) => setState(() => _poolId = id == '' ? null : id),
            ),
          ],
          if (widget.mode != _PersonnelEditMode.pool) ...[
            const SizedBox(height: 16),
            if (widget.count > 1)
              f.FSwitch(
                label: const Text('同时设置目标学科'),
                description: const Text('关闭时保留各岗位原有目标学科。'),
                value: _applySubjects,
                onChange: (value) => setState(() => _applySubjects = value),
              ),
            if (_applySubjects) ...[
              Text('目标学科（可多选）', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              if (widget.snapshot.subjects.isEmpty)
                const Text('暂无学科，请先在科目节数中添加。'),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final id in _subjects.where(
                    (id) => !widget.snapshot.subjects.any(
                      (subject) => subject.id == id,
                    ),
                  ))
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppCheckbox(
                          key: ValueKey('post-target-$id'),
                          value: true,
                          onChanged: (_) =>
                              setState(() => _subjects.remove(id)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '已删除学科（取消勾选以移除）',
                          style: TextStyle(
                            color: context.appColors.destructive,
                          ),
                        ),
                      ],
                    ),
                  for (final subject in widget.snapshot.subjects)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppCheckbox(
                          key: ValueKey('post-target-${subject.id}'),
                          value: _subjects.contains(subject.id),
                          onChanged: (checked) => setState(() {
                            checked
                                ? _subjects.add(subject.id)
                                : _subjects.remove(subject.id);
                          }),
                        ),
                        const SizedBox(width: 6),
                        Text(subject.name),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _DutySegments<bool>(
              items: const {true: '跟随全局', false: '单独设置'},
              value: _inherit,
              onChanged: (value) => setState(() => _inherit = value),
            ),
            const SizedBox(height: 16),
            if (_inherit)
              Text(
                '使用全局人员匹配规则；以后全局调整时会同步跟随。',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              _MatchingPreferencesEditor(
                value: _preferences,
                allowSubject: !_applySubjects || _subjects.isNotEmpty,
                onChanged: (value) => setState(() => _preferences = value),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            '已安排的教师会保留。不符合新规则的指派会提示，并在发布前要求修正。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.appColors.inkSecondary),
          ),
        ],
      ),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppPrimaryButton(
          onPressed: () => Navigator.pop(context, (
            poolId: _poolId,
            preferences: _inherit ? null : _preferences,
            subjects: _applySubjects ? _subjects : null,
          )),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _PoolNameDialog extends StatefulWidget {
  const _PoolNameDialog({required this.names, this.initial});
  final Set<String> names;
  final String? initial;
  @override
  State<_PoolNameDialog> createState() => _PoolNameDialogState();
}

class _PoolNameDialogState extends State<_PoolNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(widget.initial == null ? '新建候选池' : '重命名候选池'),
    maxWidth: 420,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextFormField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: '候选池名称'),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.appColors.destructive),
            ),
          ),
      ],
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: () {
          final name = _name.text.trim();
          if (name.isEmpty || widget.names.contains(name)) {
            setState(() => _error = name.isEmpty ? '请输入候选池名称' : '候选池名称已存在');
            return;
          }
          Navigator.pop(context, name);
        },
        child: Text(widget.initial == null ? '创建' : '保存'),
      ),
    ],
  );
}
