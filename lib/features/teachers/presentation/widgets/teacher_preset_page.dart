part of '../teachers_page.dart';

enum _PresetOwnerKind { teacher, group }

typedef _TeacherPresetCellKey = ({
  TeacherPresetScope scope,
  String scopeId,
  String stageId,
  int weekday,
  String periodTypeId,
  int lessonIndex,
});

class _PresetScopeOption {
  const _PresetScopeOption({
    required this.scope,
    required this.scopeId,
    required this.label,
    required this.stageIds,
    this.parentKey,
  });

  final TeacherPresetScope scope;
  final String scopeId;
  final String label;
  final Set<String> stageIds;
  final String? parentKey;

  String get key => '${scope.storageValue}:$scopeId';
}

class _PresetConfiguration {
  const _PresetConfiguration({
    required this.routines,
    required this.scopes,
    required this.classes,
    required this.freeSlots,
  });

  final Map<String, StageRoutine> routines;
  final List<_PresetScopeOption> scopes;

  /// 当前学期全部班级，用于判定免任课标记的部分生效范围。
  final List<ClassBrief> classes;

  /// 当前学期免任课标记，用于在预排矩阵中标记不可排的位置。
  final List<FreeSlot> freeSlots;
}

List<TeacherPresetScopeNode> _teacherPresetScopeTree(
  List<_PresetScopeOption> scopes,
) {
  final children = <String, List<_PresetScopeOption>>{};
  for (final scope in scopes) {
    final parentKey = scope.parentKey;
    if (parentKey != null) {
      children.putIfAbsent(parentKey, () => []).add(scope);
    }
  }

  TeacherPresetScopeNode buildNode(_PresetScopeOption scope) =>
      TeacherPresetScopeNode(
        id: scope.key,
        label: scope.label,
        children: [
          for (final child in children[scope.key] ?? const []) buildNode(child),
        ],
      );

  return [
    for (final scope in scopes)
      if (scope.parentKey == null) buildNode(scope),
  ];
}

class _PresetMatrixHint extends StatelessWidget {
  const _PresetMatrixHint();

  @override
  Widget build(BuildContext context) => Text(
    '预排不区分单双周；空白格为自动。节次和上课日按所选范围的作息显示。红底为免任课格，不可编辑；黄字为部分班级免任课。',
    style: TextStyle(color: context.appColors.muted, fontSize: 12, height: 1.5),
  );
}

class _PresetRuleItem {
  const _PresetRuleItem({
    required this.id,
    required this.kind,
    required this.ownerId,
    required this.ownerLabel,
    required this.scope,
    required this.scopeId,
    required this.scopeLabel,
    required this.stageId,
    required this.weekday,
    required this.periodTypeId,
    required this.lessonIndex,
    required this.value,
  });

  final String id;
  final _PresetOwnerKind kind;
  final String ownerId;
  final String ownerLabel;
  final TeacherPresetScope scope;
  final String scopeId;
  final String scopeLabel;
  final String stageId;
  final int weekday;
  final String periodTypeId;
  final int lessonIndex;
  final PresetValue value;
}

class _TeacherPresetWorkspace extends ConsumerStatefulWidget {
  const _TeacherPresetWorkspace({
    required this.termId,
    required this.configuration,
    required this.initialOwnerKind,
    this.initialOwnerId,
    super.key,
  });

  final String termId;
  final _PresetConfiguration configuration;
  final _PresetOwnerKind initialOwnerKind;
  final String? initialOwnerId;

  @override
  ConsumerState<_TeacherPresetWorkspace> createState() =>
      _TeacherPresetWorkspaceState();
}

class _TeacherPresetWorkspaceState
    extends ConsumerState<_TeacherPresetWorkspace> {
  final _ownerSearchController = TextEditingController();
  late _PresetOwnerKind _ownerKind = widget.initialOwnerKind;
  String? _ownerId;
  late String _scopeKey = widget.configuration.scopes.first.key;
  String? _draftOwnerKey;
  final Map<_TeacherPresetCellKey, PresetValue> _values = {};
  final Set<String> _editedScopeKeys = {};
  final Map<String, List<TeacherPreset>> _personalOverrides = {};
  final Map<String, List<TeacherGroupPreset>> _groupOverrides = {};
  Future<bool>? _saveInFlight;
  bool _saving = false;
  bool _popWhenSaved = false;

  @override
  void initState() {
    super.initState();
    _ownerId = widget.initialOwnerId;
  }

  @override
  void dispose() {
    _ownerSearchController.dispose();
    super.dispose();
  }

  List<TeacherPreset> _personalPresets(List<TeacherPreset> watched) => [
    for (final preset in watched)
      if (!_personalOverrides.containsKey(preset.teacherId)) preset,
    for (final rows in _personalOverrides.values) ...rows,
  ];

  List<TeacherGroupPreset> _groupPresets(List<TeacherGroupPreset> watched) => [
    for (final preset in watched)
      if (!_groupOverrides.containsKey(preset.groupId)) preset,
    for (final rows in _groupOverrides.values) ...rows,
  ];

  String _ownerKey(_PresetOwnerKind kind, String id) => '${kind.name}:$id';

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  void _loadDraft(
    String ownerId,
    List<TeacherPreset> personalPresets,
    List<TeacherGroupPreset> groupPresets,
  ) {
    final ownerKey = _ownerKey(_ownerKind, ownerId);
    if (_draftOwnerKey == ownerKey) return;
    _draftOwnerKey = ownerKey;
    _values.clear();
    _editedScopeKeys.clear();
    if (_ownerKind == _PresetOwnerKind.teacher) {
      for (final preset in personalPresets.where(
        (item) => item.teacherId == ownerId,
      )) {
        _values[_cellKey(
              scope: preset.scope,
              scopeId: preset.scopeId,
              stageId: preset.stageId,
              weekday: preset.weekday,
              periodTypeId: preset.periodTypeId,
              lessonIndex: preset.lessonIndex,
            )] =
            preset.value;
      }
    } else {
      for (final preset in groupPresets.where(
        (item) => item.groupId == ownerId,
      )) {
        _values[_cellKey(
              scope: preset.scope,
              scopeId: preset.scopeId,
              stageId: preset.stageId,
              weekday: preset.weekday,
              periodTypeId: preset.periodTypeId,
              lessonIndex: preset.lessonIndex,
            )] =
            preset.value;
      }
    }
  }

  _TeacherPresetCellKey _cellKey({
    required TeacherPresetScope scope,
    required String scopeId,
    required String stageId,
    required int weekday,
    required String periodTypeId,
    required int lessonIndex,
  }) => (
    scope: scope,
    scopeId: scopeId,
    stageId: stageId,
    weekday: weekday,
    periodTypeId: periodTypeId,
    lessonIndex: lessonIndex,
  );

  List<TeacherPreset> _makeTeacherPresets(String teacherId) => [
    for (final entry in _values.entries)
      if (_editedScopeKeys.contains(
        '${entry.key.scope.storageValue}:${entry.key.scopeId}',
      ))
        TeacherPreset(
          id: _id('teacher-preset'),
          teacherId: teacherId,
          scope: entry.key.scope,
          scopeId: entry.key.scopeId,
          stageId: entry.key.stageId,
          weekday: entry.key.weekday,
          periodTypeId: entry.key.periodTypeId,
          lessonIndex: entry.key.lessonIndex,
          value: entry.value,
        ),
  ];

  List<TeacherGroupPreset> _makeGroupPresets(String groupId) => [
    for (final entry in _values.entries)
      if (_editedScopeKeys.contains(
        '${entry.key.scope.storageValue}:${entry.key.scopeId}',
      ))
        TeacherGroupPreset(
          id: _id('group-preset'),
          groupId: groupId,
          scope: entry.key.scope,
          scopeId: entry.key.scopeId,
          stageId: entry.key.stageId,
          weekday: entry.key.weekday,
          periodTypeId: entry.key.periodTypeId,
          lessonIndex: entry.key.lessonIndex,
          value: entry.value,
        ),
  ];

  Future<bool> _saveDraft() async {
    final ownerId = _ownerId;
    if (ownerId == null || _editedScopeKeys.isEmpty) return true;
    final editedScopes = {..._editedScopeKeys};
    try {
      if (_ownerKind == _PresetOwnerKind.teacher) {
        final current = _personalPresets(
          await ref.read(teacherPresetsProvider(widget.termId).future),
        );
        final next = mergeTeacherPresetEdit(
          teacherId: ownerId,
          current: current,
          editedScopeKeys: editedScopes,
          editedPresets: _makeTeacherPresets(ownerId),
        );
        await ref
            .read(schoolRepositoryProvider)
            .replaceTeacherPresets(
              termId: widget.termId,
              teacherId: ownerId,
              presets: teacherPresetReplacementPayload(
                teacherId: ownerId,
                allPresets: next,
              ),
            );
        _personalOverrides[ownerId] = next
            .where((preset) => preset.teacherId == ownerId)
            .toList(growable: false);
      } else {
        final current = _groupPresets(
          await ref.read(teacherGroupPresetsProvider(widget.termId).future),
        );
        final memberships = await ref.read(
          teacherGroupMembersProvider(widget.termId).future,
        );
        final memberTeacherIds = memberships
            .where((member) => member.groupId == ownerId)
            .map((member) => member.teacherId)
            .toSet();
        final next = mergeTeacherGroupPresetEdit(
          groupId: ownerId,
          current: current,
          editedScopeKeys: editedScopes,
          editedPresets: _makeGroupPresets(ownerId),
        );
        final teachers = await ref.read(teachersProvider(widget.termId).future);
        for (final teacherId in memberTeacherIds) {
          final ownGroupIds = memberships
              .where((member) => member.teacherId == teacherId)
              .map((member) => member.groupId)
              .toSet();
          final cells = <String, List<TeacherGroupPreset>>{};
          for (final preset in next.where(
            (preset) => ownGroupIds.contains(preset.groupId),
          )) {
            cells.putIfAbsent(preset.cellKey, () => []).add(preset);
          }
          for (final presets in cells.values) {
            try {
              resolveTeacherPreset(personal: null, groups: presets);
            } on TeacherPresetConflictException catch (error) {
              final teacherName = teachers
                  .where((teacher) => teacher.id == teacherId)
                  .map((teacher) => teacher.displayName)
                  .firstOrNull;
              _showMessage(
                '${teacherName ?? '该教师'}的分组预排冲突（${error.values.map((value) => value.label).join('、')}），请先解决冲突。',
              );
              return false;
            }
          }
        }
        await ref
            .read(schoolRepositoryProvider)
            .replaceTeacherGroupPresets(
              groupId: ownerId,
              presets: teacherGroupPresetReplacementPayload(
                groupId: ownerId,
                allPresets: next,
              ),
            );
        _groupOverrides[ownerId] = next
            .where((preset) => preset.groupId == ownerId)
            .toList(growable: false);
      }
      _editedScopeKeys.clear();
      if (mounted) setState(() {});
      return true;
    } catch (error) {
      _showMessage('保存预排失败：$error');
      return false;
    }
  }

  Future<void> _changeOwnerKind(_PresetOwnerKind kind) async {
    if (kind == _ownerKind || !await (_saveInFlight ?? _saveDraft())) return;
    if (!mounted) return;
    setState(() {
      _ownerKind = kind;
      _ownerId = null;
      _draftOwnerKey = null;
      _ownerSearchController.clear();
    });
  }

  Future<void> _selectOwner(String id) async {
    if (id == _ownerId || !await (_saveInFlight ?? _saveDraft())) return;
    if (!mounted) return;
    setState(() {
      _ownerId = id;
      _draftOwnerKey = null;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteRule(_PresetRuleItem rule) async {
    if (rule.kind == _ownerKind &&
        rule.ownerId == _ownerId &&
        _editedScopeKeys.isNotEmpty) {
      _showMessage('预排正在保存，请稍后再删除规则。');
      return;
    }
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('删除这条预排规则？'),
        content: Text(
          '${rule.ownerLabel} · ${rule.scopeLabel} · ${_ruleLocation(rule)} · ${rule.value.label}',
        ),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          AppDestructiveButton(
            key: ValueKey('teacher-preset-confirm-delete-${rule.id}'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除规则'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (rule.kind == _PresetOwnerKind.teacher) {
        final current = _personalPresets(
          await ref.read(teacherPresetsProvider(widget.termId).future),
        );
        final next = current.where((preset) => preset.id != rule.id).toList();
        await ref
            .read(schoolRepositoryProvider)
            .replaceTeacherPresets(
              termId: widget.termId,
              teacherId: rule.ownerId,
              presets: teacherPresetReplacementPayload(
                teacherId: rule.ownerId,
                allPresets: next,
              ),
            );
        _personalOverrides[rule.ownerId] = next
            .where((preset) => preset.teacherId == rule.ownerId)
            .toList(growable: false);
      } else {
        final current = _groupPresets(
          await ref.read(teacherGroupPresetsProvider(widget.termId).future),
        );
        final next = current.where((preset) => preset.id != rule.id).toList();
        await ref
            .read(schoolRepositoryProvider)
            .replaceTeacherGroupPresets(
              groupId: rule.ownerId,
              presets: teacherGroupPresetReplacementPayload(
                groupId: rule.ownerId,
                allPresets: next,
              ),
            );
        _groupOverrides[rule.ownerId] = next
            .where((preset) => preset.groupId == rule.ownerId)
            .toList(growable: false);
      }
      if (rule.kind == _ownerKind && rule.ownerId == _ownerId) {
        _values.removeWhere(
          (key, _) =>
              key.scope == rule.scope &&
              key.scopeId == rule.scopeId &&
              key.stageId == rule.stageId &&
              key.weekday == rule.weekday &&
              key.periodTypeId == rule.periodTypeId &&
              key.lessonIndex == rule.lessonIndex,
        );
      }
      if (mounted) setState(() {});
    } catch (error) {
      _showMessage('删除预排失败：$error');
    }
  }

  List<_PresetRuleItem> _rules({
    required List<Teacher> teachers,
    required List<TeacherGroup> groups,
    required List<TeacherPreset> teacherPresets,
    required List<TeacherGroupPreset> groupPresets,
  }) {
    final teacherNames = {
      for (final teacher in teachers) teacher.id: teacher.displayName,
    };
    final groupNames = {for (final group in groups) group.id: group.name};
    final scopeNames = {
      for (final scope in widget.configuration.scopes) scope.key: scope.label,
    };
    final rules = <_PresetRuleItem>[
      for (final preset in teacherPresets)
        _PresetRuleItem(
          id: preset.id,
          kind: _PresetOwnerKind.teacher,
          ownerId: preset.teacherId,
          ownerLabel: teacherNames[preset.teacherId] ?? '已删除的教师',
          scope: preset.scope,
          scopeId: preset.scopeId,
          scopeLabel:
              scopeNames['${preset.scope.storageValue}:${preset.scopeId}'] ??
              preset.scopeId,
          stageId: preset.stageId,
          weekday: preset.weekday,
          periodTypeId: preset.periodTypeId,
          lessonIndex: preset.lessonIndex,
          value: preset.value,
        ),
      for (final preset in groupPresets)
        _PresetRuleItem(
          id: preset.id,
          kind: _PresetOwnerKind.group,
          ownerId: preset.groupId,
          ownerLabel: groupNames[preset.groupId] ?? '已删除的分组',
          scope: preset.scope,
          scopeId: preset.scopeId,
          scopeLabel:
              scopeNames['${preset.scope.storageValue}:${preset.scopeId}'] ??
              preset.scopeId,
          stageId: preset.stageId,
          weekday: preset.weekday,
          periodTypeId: preset.periodTypeId,
          lessonIndex: preset.lessonIndex,
          value: preset.value,
        ),
    ];
    rules.sort((a, b) {
      final kind = a.kind.index.compareTo(b.kind.index);
      if (kind != 0) return kind;
      final owner = a.ownerLabel.compareTo(b.ownerLabel);
      if (owner != 0) return owner;
      final weekday = a.weekday.compareTo(b.weekday);
      if (weekday != 0) return weekday;
      final lesson = a.lessonIndex.compareTo(b.lessonIndex);
      if (lesson != 0) return lesson;
      return a.scopeLabel.compareTo(b.scopeLabel);
    });
    return rules;
  }

  String _ruleLocation(_PresetRuleItem rule) {
    final period = widget.configuration.routines[rule.stageId]?.periodTypes
        .where((item) => item.id == rule.periodTypeId)
        .firstOrNull;
    var lessonLabel = '第 ${rule.lessonIndex} 节';
    if (period != null) {
      for (final lesson in period.lessonTimes) {
        if (lesson.lessonIndex == rule.lessonIndex) {
          lessonLabel = lesson.label;
          break;
        }
      }
      return '${_weekdayLabel(rule.weekday)} · ${period.name} $lessonLabel';
    }
    return '${_weekdayLabel(rule.weekday)} · $lessonLabel';
  }

  Widget _modeTabs() => FTabs(
    control: FTabControl.lifted(
      index: _ownerKind.index,
      onChange: (index) =>
          unawaited(_changeOwnerKind(_PresetOwnerKind.values[index])),
      motion: const FTabMotion(
        duration: Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
      ),
    ),
    style: FTabsStyleDelta.delta(
      decoration: DecorationDelta.value(
        ShapeDecoration(
          color: context.appColors.canvas,
          shape: RoundedSuperellipseBorder(
            side: BorderSide(color: context.appColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      indicatorDecoration: DecorationDelta.value(
        ShapeDecoration(
          color: context.appColors.surface,
          shape: RoundedSuperellipseBorder(
            side: BorderSide(color: context.appColors.border),
            borderRadius: BorderRadius.circular(7),
          ),
        ),
      ),
      padding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
      spacing: 0,
      minHeight: 42,
    ),
    scrollable: false,
    children: [
      FTabEntry(
        label: const Text('按教师', key: ValueKey('teacher-preset-mode-teacher')),
        child: const SizedBox.shrink(),
      ),
      FTabEntry(
        label: const Text('按教师分组', key: ValueKey('teacher-preset-mode-group')),
        child: const SizedBox.shrink(),
      ),
    ],
  );

  Widget _ownerPanel({
    required List<Teacher> teachers,
    required List<TeacherGroup> groups,
    required String? selectedId,
  }) {
    final owners = _ownerKind == _PresetOwnerKind.teacher
        ? [
            for (final teacher in teachers)
              (id: teacher.id, label: teacher.displayName),
          ]
        : [for (final group in groups) (id: group.id, label: group.name)];
    return AppSectionPanel(
      key: const ValueKey('teacher-preset-owner-panel'),
      title: _ownerKind == _PresetOwnerKind.teacher ? '教师' : '教师分组',
      padding: EdgeInsets.zero,
      expandChild: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: AppTextFormField(
              controller: _ownerSearchController,
              decoration: InputDecoration(
                hintText: _ownerKind == _PresetOwnerKind.teacher
                    ? '搜索教师'
                    : '搜索分组',
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ownerSearchController,
              builder: (context, value, _) {
                final query = value.text.trim().toLowerCase();
                final visible = owners
                    .where((owner) => owner.label.toLowerCase().contains(query))
                    .toList(growable: false);
                if (visible.isEmpty) {
                  return Center(
                    child: Text(
                      owners.isEmpty ? '暂无可选对象' : '没有匹配结果',
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final owner = visible[index];
                    final selected = owner.id == selectedId;
                    return FTappable(
                      key: ValueKey(
                        selected
                            ? 'teacher-preset-selected-owner-${_ownerKind.name}-${owner.id}'
                            : 'teacher-preset-owner-${_ownerKind.name}-${owner.id}',
                      ),
                      onPress: () => unawaited(_selectOwner(owner.id)),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? context.appColors.selectedBlue
                              : null,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          owner.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? context.appColors.blue
                                : context.appColors.ink,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 免任课标记在当前范围视图下的解析结果（整体生效 / 部分生效）。
  Map<TeacherPresetMatrixCell, FreeSlotViewResolution> _exemptionsFor(
    _PresetScopeOption scope,
    String stageId,
    StageRoutine routine,
  ) {
    final viewScope = switch (scope.scope) {
      TeacherPresetScope.school => FreeSlotScope.school,
      TeacherPresetScope.stage => FreeSlotScope.stage,
      TeacherPresetScope.grade => FreeSlotScope.grade,
      TeacherPresetScope.schoolClass => FreeSlotScope.schoolClass,
    };
    final classGradeId = scope.scope == TeacherPresetScope.schoolClass
        ? widget.configuration.classes
              .where((item) => item.id == scope.scopeId)
              .firstOrNull
              ?.gradeId
        : null;
    final (applicableGradeIds, applicableClassIds) = switch (scope.scope) {
      TeacherPresetScope.school || TeacherPresetScope.stage => (
        {
          for (final item in widget.configuration.classes)
            if (item.stageId == stageId) item.gradeId,
        },
        {
          for (final item in widget.configuration.classes)
            if (item.stageId == stageId) item.id,
        },
      ),
      TeacherPresetScope.grade => (
        const <String>{},
        {
          for (final item in widget.configuration.classes)
            if (item.gradeId == scope.scopeId) item.id,
        },
      ),
      TeacherPresetScope.schoolClass => (const <String>{}, const <String>{}),
    };
    final weekdays = routine.teachingWeekdays.toList()..sort();
    final exemptions = <TeacherPresetMatrixCell, FreeSlotViewResolution>{};
    for (final period in routine.periodTypes) {
      for (final weekday in weekdays) {
        final lessonCount = routine.effectiveLessonCount(period.id, weekday);
        for (var lesson = 1; lesson <= lessonCount; lesson++) {
          final resolution = resolveFreeSlotsForView(
            widget.configuration.freeSlots,
            viewScope: viewScope,
            viewScopeId: scope.scopeId,
            termId: widget.termId,
            stageId: stageId,
            weekday: weekday,
            periodTypeId: period.id,
            lessonIndex: lesson,
            classGradeId: classGradeId,
            applicableGradeIds: applicableGradeIds,
            applicableClassIds: applicableClassIds,
          );
          if (resolution.full != null || resolution.partial != null) {
            exemptions[(
                  weekday: weekday,
                  periodTypeId: period.id,
                  lessonIndex: lesson,
                )] =
                resolution;
          }
        }
      }
    }
    return exemptions;
  }

  Widget _matrixPanel({
    required _PresetScopeOption? scope,
    required String? ownerLabel,
  }) {
    final stageId = scope?.stageIds
        .where(widget.configuration.routines.containsKey)
        .firstOrNull;
    final routine = stageId == null
        ? null
        : widget.configuration.routines[stageId];
    return AppSectionPanel(
      key: const ValueKey('teacher-preset-matrix-panel'),
      title: ownerLabel == null
          ? '预排矩阵'
          : '$ownerLabel · ${scope?.label ?? '选择应用范围'}',
      trailing: _saving
          ? Text(
              '保存中…',
              style: TextStyle(color: context.appColors.muted, fontSize: 11),
            )
          : null,
      padding: EdgeInsets.zero,
      expandChild: true,
      child: routine == null || scope == null || ownerLabel == null
          ? Center(
              child: Text(
                '选择教师或分组及应用范围后设置预排',
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _PresetMatrixHint(),
                  ),
                ),
                Expanded(
                  child: TeacherPresetMatrix(
                    routine: routine,
                    exemptions: _exemptionsFor(scope, stageId!, routine),
                    values: {
                      for (final entry in _values.entries)
                        if (entry.key.scope == scope.scope &&
                            entry.key.scopeId == scope.scopeId &&
                            entry.key.stageId == stageId)
                          (
                            weekday: entry.key.weekday,
                            periodTypeId: entry.key.periodTypeId,
                            lessonIndex: entry.key.lessonIndex,
                          ): entry.value,
                    },
                    onChanged: (cell, value) {
                      if (_saving) return;
                      final key = (
                        scope: scope.scope,
                        scopeId: scope.scopeId,
                        stageId: stageId,
                        weekday: cell.weekday,
                        periodTypeId: cell.periodTypeId,
                        lessonIndex: cell.lessonIndex,
                      );
                      final previousValues =
                          Map<_TeacherPresetCellKey, PresetValue>.of(_values);
                      final previousScopes = Set<String>.of(_editedScopeKeys);
                      setState(() {
                        _editedScopeKeys.add(scope.key);
                        if (value == null) {
                          _values.remove(key);
                        } else {
                          _values[key] = value;
                        }
                        _saving = true;
                      });
                      _saveInFlight = () async {
                        final saved = await _saveDraft();
                        if (!saved) {
                          _values
                            ..clear()
                            ..addAll(previousValues);
                          _editedScopeKeys
                            ..clear()
                            ..addAll(previousScopes);
                        }
                        _saveInFlight = null;
                        if (mounted) setState(() => _saving = false);
                        return saved;
                      }();
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _rulesPanel(List<_PresetRuleItem> rules) => AppSectionPanel(
    key: const ValueKey('teacher-preset-rules-panel'),
    title: '全部预排信息',
    trailing: Text(
      '${rules.length} 条',
      style: TextStyle(color: context.appColors.muted, fontSize: 11),
    ),
    padding: EdgeInsets.zero,
    expandChild: true,
    child: rules.isEmpty
        ? Center(
            child: Text(
              '暂无预排规则，矩阵中的空白表示自动安排。',
              style: TextStyle(color: context.appColors.muted, fontSize: 12),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
            itemCount: rules.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: context.appColors.border),
            itemBuilder: (context, index) {
              final rule = rules[index];
              final ownerKindLabel = rule.kind == _PresetOwnerKind.teacher
                  ? '教师'
                  : '分组';
              return Container(
                key: ValueKey(
                  'teacher-preset-rule-${rule.kind.name}-${rule.id}',
                ),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.selectedBlue,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        ownerKindLabel,
                        style: TextStyle(
                          color: context.appColors.blue,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${rule.ownerLabel} · ${rule.scopeLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.appColors.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            _ruleLocation(rule),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.appColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rule.value.label,
                      style: TextStyle(
                        color: rule.value == PresetValue.forbid
                            ? context.appColors.destructive
                            : context.appColors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    FButton(
                      key: ValueKey('teacher-preset-delete-${rule.id}'),
                      size: FButtonSizeVariant.xs,
                      variant: FButtonVariant.ghost,
                      onPress: () => unawaited(_deleteRule(rule)),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: context.appColors.muted,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
  );

  @override
  Widget build(BuildContext context) {
    final teachersAsync = ref.watch(teachersProvider(widget.termId));
    final groupsAsync = ref.watch(teacherGroupsProvider(widget.termId));
    final personalAsync = ref.watch(teacherPresetsProvider(widget.termId));
    final groupPresetsAsync = ref.watch(
      teacherGroupPresetsProvider(widget.termId),
    );
    final teachers = teachersAsync.valueOrNull ?? const <Teacher>[];
    final groups = groupsAsync.valueOrNull ?? const <TeacherGroup>[];
    final watchedPersonal =
        personalAsync.valueOrNull ?? const <TeacherPreset>[];
    final watchedGroups =
        groupPresetsAsync.valueOrNull ?? const <TeacherGroupPreset>[];
    final personalPresets = _personalPresets(watchedPersonal);
    final groupPresets = _groupPresets(watchedGroups);
    final owners = _ownerKind == _PresetOwnerKind.teacher
        ? teachers.map((teacher) => teacher.id).toSet()
        : groups.map((group) => group.id).toSet();
    final ownersLoaded = _ownerKind == _PresetOwnerKind.teacher
        ? teachersAsync.hasValue
        : groupsAsync.hasValue;
    if (ownersLoaded && (_ownerId == null || !owners.contains(_ownerId))) {
      _ownerId = _ownerKind == _PresetOwnerKind.teacher
          ? teachers.firstOrNull?.id
          : groups.firstOrNull?.id;
      _draftOwnerKey = null;
    }
    final ownerId = _ownerId;
    final presetsLoaded = _ownerKind == _PresetOwnerKind.teacher
        ? personalAsync.hasValue
        : groupPresetsAsync.hasValue;
    if (ownerId != null && presetsLoaded) {
      _loadDraft(ownerId, personalPresets, groupPresets);
    }
    final ownerLabel = _ownerKind == _PresetOwnerKind.teacher
        ? teachers
              .where((teacher) => teacher.id == ownerId)
              .map((teacher) => teacher.displayName)
              .firstOrNull
        : groups
              .where((group) => group.id == ownerId)
              .map((group) => group.name)
              .firstOrNull;
    final selectedScope = widget.configuration.scopes
        .where((scope) => scope.key == _scopeKey)
        .firstOrNull;
    final rules = _rules(
      teachers: teachers,
      groups: groups,
      teacherPresets: personalPresets,
      groupPresets: groupPresets,
    );

    final modePanel = SizedBox(
      key: const ValueKey('teacher-preset-mode-panel'),
      height: 52,
      child: AppSurface(
        child: Padding(padding: const EdgeInsets.all(4), child: _modeTabs()),
      ),
    );
    final scopePanel = TeacherPresetScopeTree(
      key: const ValueKey('teacher-preset-scope-panel'),
      nodes: _teacherPresetScopeTree(widget.configuration.scopes),
      selectedId: _scopeKey,
      onSelected: (key) => setState(() => _scopeKey = key),
    );
    final ownerPanel = _ownerPanel(
      teachers: teachers,
      groups: groups,
      selectedId: ownerId,
    );
    final matrixPanel = _matrixPanel(
      scope: selectedScope,
      ownerLabel: ownerLabel,
    );
    final rulesPanel = _rulesPanel(rules);

    return PopScope(
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _saveInFlight == null || _popWhenSaved) return;
        _popWhenSaved = true;
        final navigator = Navigator.of(context);
        await _saveInFlight;
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) {
          _popWhenSaved = false;
          navigator.maybePop();
        }
      },
      child: AbsorbPointer(
        absorbing: _saving,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Scrollbar(
                child: SingleChildScrollView(
                  key: const ValueKey('teacher-preset-page-scroll'),
                  primary: true,
                  child: Column(
                    children: [
                      modePanel,
                      const SizedBox(height: 10),
                      SizedBox(height: 220, child: ownerPanel),
                      const SizedBox(height: 10),
                      SizedBox(height: 240, child: scopePanel),
                      const SizedBox(height: 10),
                      SizedBox(height: 420, child: matrixPanel),
                      const SizedBox(height: 12),
                      SizedBox(height: 300, child: rulesPanel),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  flex: 7,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 228,
                        child: Column(
                          children: [
                            modePanel,
                            const SizedBox(height: 10),
                            Expanded(child: ownerPanel),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(width: 228, child: scopePanel),
                      const SizedBox(width: 10),
                      Expanded(child: matrixPanel),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(flex: 3, child: rulesPanel),
              ],
            );
          },
        ),
      ),
    );
  }
}
