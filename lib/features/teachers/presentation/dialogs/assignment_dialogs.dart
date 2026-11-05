part of '../teachers_page.dart';

Future<(String, String?)?> _showGroupEditor(BuildContext context) =>
    showAppDialog<(String, String?)>(
      context: context,
      builder: (context) => const _TeacherGroupEditorDialog(),
    );

class _TeacherGroupEditorDialog extends StatefulWidget {
  const _TeacherGroupEditorDialog();
  @override
  State<_TeacherGroupEditorDialog> createState() =>
      _TeacherGroupEditorDialogState();
}

class _TeacherGroupEditorDialogState extends State<_TeacherGroupEditorDialog> {
  final name = TextEditingController();
  final description = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: const Text('新增教师分组'),
      maxWidth: 480,
      content: SizedBox(
        width: 432,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '将教师归入分组，统一设置预排规则。',
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              _TeacherFormField(
                label: '分组名称',
                isRequired: true,
                child: AppTextFormField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '例如：语文教研组'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入分组名称' : null,
                ),
              ),
              const SizedBox(height: 20),
              _TeacherFormField(
                label: '说明',
                child: AppTextFormField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: '选填，简要描述分组用途'),
                ),
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
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              name.text.trim(),
              description.text.trim().isEmpty ? null : description.text.trim(),
            ));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _NewAssignmentSelection {
  const _NewAssignmentSelection({
    required this.classId,
    required this.subjectId,
    required this.weekMode,
    required this.lessonCount,
  });

  final String classId;
  final String subjectId;
  final WeekMode weekMode;
  final int lessonCount;
}

class _AssignmentEditorPopover extends StatefulWidget {
  const _AssignmentEditorPopover({
    required this.child,
    required this.title,
    required this.teachers,
    required this.current,
    required this.requirements,
    required this.onSave,
    super.key,
  });

  final Widget child;
  final String title;
  final List<Teacher> teachers;
  final List<TeacherAssignment> current;
  final List<SubjectRequirement> requirements;
  final Future<bool> Function(List<TeacherAssignment>) onSave;

  @override
  State<_AssignmentEditorPopover> createState() =>
      _AssignmentEditorPopoverState();
}

class _AssignmentEditorPopoverState extends State<_AssignmentEditorPopover> {
  final _groupId = Object();

  @override
  Widget build(BuildContext context) => FPopover(
    groupId: _groupId,
    constraints: const FPortalConstraints(maxWidth: 460, maxHeight: 560),
    spacing: const .spacing(6),
    popoverAnchor: Alignment.topLeft,
    childAnchor: Alignment.bottomLeft,
    popoverBuilder: (context, controller) => _AssignmentEditorPanel(
      title: widget.title,
      teachers: widget.teachers,
      current: widget.current,
      requirements: widget.requirements,
      groupId: _groupId,
      onCancel: controller.hide,
      onSave: widget.onSave,
    ),
    builder: (context, controller, child) => MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller.toggle,
        child: child,
      ),
    ),
    child: widget.child,
  );
}

class _AssignmentEditorPanel extends StatefulWidget {
  const _AssignmentEditorPanel({
    required this.title,
    required this.teachers,
    required this.current,
    required this.requirements,
    required this.groupId,
    required this.onCancel,
    required this.onSave,
  });

  final String title;
  final List<Teacher> teachers;
  final List<TeacherAssignment> current;
  final List<SubjectRequirement> requirements;
  final Object groupId;
  final VoidCallback onCancel;
  final Future<bool> Function(List<TeacherAssignment>) onSave;

  @override
  State<_AssignmentEditorPanel> createState() => _AssignmentEditorPanelState();
}

class _AssignmentEditorPanelState extends State<_AssignmentEditorPanel> {
  late final List<_AssignmentDraft> _drafts = widget.current
      .map(_AssignmentDraft.fromAssignment)
      .toList(growable: true);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_drafts.isEmpty) {
      _drafts.add(_createDraft(0));
    }
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.onSave(
        _drafts
            .map(
              (draft) => TeacherAssignment(
                id: draft.id,
                termId: '',
                teacherId: draft.teacherId,
                classId: '',
                subjectId: '',
                weekMode: draft.weekMode,
                lessonCount: draft.lessonCount,
                sortOrder: draft.sortOrder,
              ),
            )
            .toList(),
      );
      if (saved && mounted) widget.onCancel();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<WeekMode> get _availableWeekModes {
    final requirementByMode = <WeekMode, int>{};
    for (final requirement in widget.requirements) {
      requirementByMode.update(
        requirement.weekMode,
        (total) => total + requirement.lessonCount,
        ifAbsent: () => requirement.lessonCount,
      );
    }
    return WeekMode.values
        .where((mode) => (requirementByMode[mode] ?? 0) > 0)
        .toList(growable: false);
  }

  WeekMode get _defaultWeekMode {
    final available = _availableWeekModes;
    return available.isEmpty ? WeekMode.weekly : available.first;
  }

  _AssignmentDraft _createDraft(int sortOrder) => _AssignmentDraft.create(
    teacherId: '',
    sortOrder: sortOrder,
    weekMode: _defaultWeekMode,
  );

  bool get _canSave => _drafts.every(
    (draft) =>
        draft.teacherId.isNotEmpty &&
        draft.lessonCount > 0 &&
        _availableWeekModes.contains(draft.weekMode),
  );

  @override
  Widget build(BuildContext context) {
    final availableWeekModes = _availableWeekModes;
    final hasUnsupportedWeekMode = _drafts.any(
      (draft) => !availableWeekModes.contains(draft.weekMode),
    );
    final requirementByMode = <WeekMode, int>{};
    for (final requirement in widget.requirements) {
      requirementByMode.update(
        requirement.weekMode,
        (total) => total + requirement.lessonCount,
        ifAbsent: () => requirement.lessonCount,
      );
    }
    final assignedByMode = <WeekMode, int>{};
    for (final draft in _drafts) {
      if (draft.teacherId.isEmpty) continue;
      assignedByMode.update(
        draft.weekMode,
        (total) => total + draft.lessonCount,
        ifAbsent: () => draft.lessonCount,
      );
    }
    final remainderLabels = <String>[];
    var hasExceededRequirement = false;
    for (final mode in WeekMode.values) {
      final requirementCount = requirementByMode[mode];
      if (requirementCount == null) continue;
      final remaining = requirementCount - (assignedByMode[mode] ?? 0);
      if (remaining < 0) hasExceededRequirement = true;
      remainderLabels.add(
        remaining < 0
            ? '${mode.label} 超出 ${-remaining} 节'
            : '${mode.label} $remaining 节',
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FButton(
                    variant: FButtonVariant.ghost,
                    size: FButtonSizeVariant.xs,
                    onPress: () => setState(
                      () => _drafts.add(_createDraft(_drafts.length)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 16),
                        SizedBox(width: 4),
                        Text('添加分担教师'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Row(
                children: [
                  Expanded(child: Text('教师')),
                  SizedBox(width: 8),
                  SizedBox(width: 96, child: Text('周模式')),
                  SizedBox(width: 8),
                  SizedBox(width: 78, child: Text('节数')),
                  SizedBox(width: 30),
                ],
              ),
              const Divider(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _drafts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final draft = _drafts[index];
                    return Row(
                      children: [
                        Expanded(
                          child: AppSelectField<String>(
                            value: draft.teacherId,
                            items: {
                              '请选择教师': '',
                              ...buildUniqueSelectOptions<Teacher, String>(
                                widget.teachers,
                                labelOf: (teacher) => teacher.displayName,
                                valueOf: (teacher) => teacher.id,
                                disambiguatorOf: (teacher) => teacher.shortName,
                                idOf: (teacher) => teacher.id,
                                reservedLabels: const {'请选择教师'},
                              ),
                            },
                            contentGroupId: widget.groupId,
                            searchable: true,
                            searchHint: '搜索教师姓名',
                            onChanged: (value) =>
                                setState(() => draft.teacherId = value ?? ''),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 96,
                          child: AppSelectField<WeekMode>(
                            value: availableWeekModes.contains(draft.weekMode)
                                ? draft.weekMode
                                : null,
                            items: {
                              for (final mode in availableWeekModes)
                                mode.label: mode,
                            },
                            hint: availableWeekModes.contains(draft.weekMode)
                                ? null
                                : '请选择周模式',
                            contentGroupId: widget.groupId,
                            onChanged: (value) => setState(
                              () => draft.weekMode = value ?? _defaultWeekMode,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 78,
                          child: AppTextFormField(
                            controller: draft.lessonCountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              suffixText: '节',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 11,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        SizedBox(
                          width: 30,
                          child: AppIconButton(
                            tooltip: '移除此行',
                            onPressed: _drafts.length == 1
                                ? null
                                : () => setState(() {
                                    _drafts.removeAt(index).dispose();
                                  }),
                            icon: Icons.close,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              if (hasUnsupportedWeekMode) ...[
                Text(
                  '有分担行使用了未设置需求的周模式，请改为有效周模式后保存。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.appColors.warning),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                widget.requirements.isEmpty
                    ? '尚未设置科目需求，无法计算剩余分配数量。'
                    : '剩余可分配：${remainderLabels.join(' · ')}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: hasExceededRequirement
                      ? context.appColors.warning
                      : context.appColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '未分配节数留在课程池，无需添加“未分配”分担行。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: FButtonVariant.ghost,
                    onPress: widget.onCancel,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    onPress: _canSave && !_saving ? _save : null,
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _assignmentEditorTitle(
  String className,
  String subjectName,
  List<SubjectRequirement> requirements,
) {
  final lessonCount = requirements.fold<int>(
    0,
    (total, requirement) => total + requirement.lessonCount,
  );
  return '分配 $className $subjectName $lessonCount节';
}

class _AssignmentDraft {
  _AssignmentDraft({
    required this.id,
    required this.teacherId,
    required this.weekMode,
    required int lessonCount,
    required this.sortOrder,
  }) : lessonCountController = TextEditingController(
         text: lessonCount.toString(),
       );

  factory _AssignmentDraft.fromAssignment(TeacherAssignment assignment) =>
      _AssignmentDraft(
        id: assignment.id,
        teacherId: assignment.teacherId,
        weekMode: assignment.weekMode,
        lessonCount: assignment.lessonCount,
        sortOrder: assignment.sortOrder,
      );

  factory _AssignmentDraft.create({
    required String teacherId,
    required int sortOrder,
    required WeekMode weekMode,
  }) => _AssignmentDraft(
    id: 'assignment-${DateTime.now().microsecondsSinceEpoch}-$sortOrder',
    teacherId: teacherId,
    weekMode: weekMode,
    lessonCount: 1,
    sortOrder: sortOrder,
  );

  final String id;
  String teacherId;
  WeekMode weekMode;
  final int sortOrder;
  final TextEditingController lessonCountController;
  int get lessonCount => int.tryParse(lessonCountController.text.trim()) ?? 0;

  void dispose() => lessonCountController.dispose();
}

Future<Set<String>?> _showMemberEditor(
  BuildContext context,
  String groupName,
  List<Teacher> teachers,
  Set<String> selected,
  Set<String> neverGrouped,
) => showAppDialog<Set<String>>(
  context: context,
  builder: (context) => _TeacherGroupMemberDialog(
    groupName: groupName,
    teachers: teachers,
    selected: selected,
    neverGrouped: neverGrouped,
  ),
);

class _TeacherGroupMemberDialog extends StatefulWidget {
  const _TeacherGroupMemberDialog({
    required this.groupName,
    required this.teachers,
    required this.selected,
    required this.neverGrouped,
  });

  final String groupName;
  final List<Teacher> teachers;
  final Set<String> selected;
  final Set<String> neverGrouped;

  @override
  State<_TeacherGroupMemberDialog> createState() =>
      _TeacherGroupMemberDialogState();
}

class _TeacherGroupMemberDialogState extends State<_TeacherGroupMemberDialog> {
  final _searchController = TextEditingController();
  late final Set<String> _selected = {...widget.selected};
  bool _showNeverGrouped = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleTeacher(String id, bool selected) => setState(() {
    if (selected) {
      _selected.add(id);
    } else {
      _selected.remove(id);
    }
  });

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _searchController,
    builder: (context, value, _) {
      final query = value.text.trim().toLowerCase();
      final visible = widget.teachers
          .where(
            (teacher) =>
                (!_showNeverGrouped ||
                    widget.neverGrouped.contains(teacher.id)) &&
                (query.isEmpty ||
                    teacher.searchText.toLowerCase().contains(query)),
          )
          .toList(growable: false);
      return AppDialog(
        title: Text('维护分组成员 · ${widget.groupName}'),
        maxWidth: 560,
        content: SizedBox(
          width: 512,
          height: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '教师可以同时加入多个分组，成员将共同使用该分组的预排规则。',
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  border: Border.all(color: context.appColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 18,
                      color: context.appColors.muted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: AppTextFormField(
                        key: const ValueKey('teacher-group-member-search'),
                        controller: _searchController,
                        borderless: true,
                        decoration: const InputDecoration(
                          hintText: '搜索教师姓名、简称或限定词',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 ${_selected.length} 名 · 显示 ${visible.length} 名',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  AppActionPill(
                    selected: _showNeverGrouped,
                    onPressed: () =>
                        setState(() => _showNeverGrouped = !_showNeverGrouped),
                    child: const Text('未分组'),
                  ),
                  const SizedBox(width: 4),
                  FButton(
                    size: FButtonSizeVariant.xs,
                    variant: FButtonVariant.ghost,
                    onPress: visible.isEmpty
                        ? null
                        : () => setState(
                            () => _selected.addAll(
                              visible.map((teacher) => teacher.id),
                            ),
                          ),
                    child: const Text('全选'),
                  ),
                  FButton(
                    size: FButtonSizeVariant.xs,
                    variant: FButtonVariant.ghost,
                    onPress: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('清空'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.appColors.surface,
                    border: Border.all(color: context.appColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: visible.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.person_search_outlined,
                            title: '没有匹配的教师',
                            message: '尝试更换关键词或关闭筛选条件。',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(6),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final teacher = visible[index];
                              final selected = _selected.contains(teacher.id);
                              return _TeacherGroupMemberRow(
                                key: ValueKey(
                                  'teacher-group-member-${teacher.id}',
                                ),
                                name: teacher.displayName,
                                selected: selected,
                                neverGrouped: widget.neverGrouped.contains(
                                  teacher.id,
                                ),
                                onChanged: (checked) =>
                                    _toggleTeacher(teacher.id, checked),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          AppPrimaryButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('保存成员'),
          ),
        ],
      );
    },
  );
}

class _TeacherGroupMemberRow extends StatefulWidget {
  const _TeacherGroupMemberRow({
    required this.name,
    required this.selected,
    required this.neverGrouped,
    required this.onChanged,
    super.key,
  });

  final String name;
  final bool selected;
  final bool neverGrouped;
  final ValueChanged<bool> onChanged;

  @override
  State<_TeacherGroupMemberRow> createState() => _TeacherGroupMemberRowState();
}

class _TeacherGroupMemberRowState extends State<_TeacherGroupMemberRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 42,
      decoration: BoxDecoration(
        color: widget.selected
            ? context.appColors.selectedBlue
            : _hovered
            ? context.appColors.canvas
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onChanged(!widget.selected),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 24,
                  child: Center(
                    child: AppCheckbox(
                      value: widget.selected,
                      onChanged: widget.onChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.ink,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ),
                if (widget.neverGrouped)
                  Text(
                    '未分组',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11,
                      height: 1.3,
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
