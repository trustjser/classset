import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/features/teachers/domain/combined_lesson_view.dart';
import 'package:flutter/material.dart';

/// 合班工作台的三个视图。
enum CombinedLessonTab { create, existing, all }

/// 从教师行尾 ⋯ →「合班」或主界面汇总条打开右侧合班工作台。
///
/// [onCombine] 返回新写入的合班标识，[onSeparate] 返回是否拆分成功，
/// 工作台据此刷新本地快照，避免关闭重开才能看到结果。
Future<void> showCombinedLessonWorkspace({
  required BuildContext context,
  required String termId,
  required List<TeacherAssignment> assignments,
  required Map<String, ClassBrief> classById,
  required Map<String, String> subjectNames,
  required Map<String, String> teacherNames,
  required String? initialTeacherId,
  required CombinedLessonTab initialTab,
  required Future<String?> Function(List<String> assignmentIds) onCombine,
  required Future<bool> Function(String groupId) onSeparate,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black38,
  barrierDismissible: true,
  builder: (dialogContext) {
    final width = MediaQuery.sizeOf(dialogContext).width;
    // 宽窗口沿用设计稿 720，较窄的桌面按比例收窄，避免主界面被压得过窄。
    final panelWidth = width < 900
        ? width - 24
        : (width * 0.55).clamp(560.0, 720.0);
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: context.appColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: panelWidth,
          height: double.infinity,
          child: _CombinedLessonWorkspace(
            termId: termId,
            assignments: assignments,
            classById: classById,
            subjectNames: subjectNames,
            teacherNames: teacherNames,
            initialTeacherId: initialTeacherId,
            initialTab: initialTab,
            onCombine: onCombine,
            onSeparate: onSeparate,
          ),
        ),
      ),
    );
  },
);

class _CombinedLessonWorkspace extends StatefulWidget {
  const _CombinedLessonWorkspace({
    required this.termId,
    required this.assignments,
    required this.classById,
    required this.subjectNames,
    required this.teacherNames,
    required this.initialTeacherId,
    required this.initialTab,
    required this.onCombine,
    required this.onSeparate,
  });

  final String termId;
  final List<TeacherAssignment> assignments;
  final Map<String, ClassBrief> classById;
  final Map<String, String> subjectNames;
  final Map<String, String> teacherNames;
  final String? initialTeacherId;
  final CombinedLessonTab initialTab;
  final Future<String?> Function(List<String>) onCombine;
  final Future<bool> Function(String) onSeparate;

  @override
  State<_CombinedLessonWorkspace> createState() =>
      _CombinedLessonWorkspaceState();
}

class _CombinedLessonWorkspaceState extends State<_CombinedLessonWorkspace> {
  final _searchController = TextEditingController();
  late List<TeacherAssignment> _assignments = widget.assignments;
  late String? _teacherId = widget.initialTeacherId;
  late CombinedLessonTab _tab = widget.initialTab;
  final Set<String> _selected = <String>{};
  String? _groupKey;
  String _query = '';
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _className(String id) => widget.classById[id]?.name ?? id;
  String _subjectName(String id) => widget.subjectNames[id] ?? id;
  String _teacherName(String id) => widget.teacherNames[id] ?? id;

  List<CombinedLessonGroupView> get _allGroups =>
      buildCombinedLessonGroups(_assignments, termId: widget.termId);

  List<CombinedLessonGroupView> get _teacherGroups => _teacherId == null
      ? const <CombinedLessonGroupView>[]
      : buildCombinedLessonGroups(
          _assignments,
          termId: widget.termId,
          teacherId: _teacherId,
        );

  List<CombinedLessonCandidateGroup> get _candidateGroups => _teacherId == null
      ? const <CombinedLessonCandidateGroup>[]
      : combinedLessonCandidateGroups(
          _assignments,
          teacherId: _teacherId!,
          termId: widget.termId,
        );

  CombinedLessonCandidateGroup? get _activeGroup {
    final groups = _candidateGroups;
    if (groups.isEmpty) return null;
    for (final group in groups) {
      if (group.key == _groupKey) return group;
    }
    return groups.first;
  }

  List<TeacherAssignment> get _selectedAssignments => _assignments
      .where((assignment) => _selected.contains(assignment.id))
      .toList(growable: false);

  void _switchTab(CombinedLessonTab tab) => setState(() => _tab = tab);

  void _toggle(String id, bool checked) {
    setState(() {
      if (checked) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _selectAll(List<TeacherAssignment> available) {
    final ids = available.map((row) => row.id).toSet();
    setState(() {
      if (_selected.length == ids.length && ids.isNotEmpty) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(ids);
      }
    });
  }

  Future<void> _combine() async {
    if (_busy || _selected.length < 2 || _activeGroup == null) return;
    setState(() => _busy = true);
    try {
      final groupId = await widget.onCombine(_selected.toList(growable: false));
      if (groupId == null || !mounted) return;
      setState(() {
        _assignments = _assignments
            .map(
              (row) => _selected.contains(row.id)
                  ? row.copyWith(combinedLessonGroupId: groupId)
                  : row,
            )
            .toList(growable: false);
        _selected.clear();
        _tab = CombinedLessonTab.existing;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _separate(CombinedLessonGroupView group) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: const Text('确认拆分合班'),
        content: Text(
          '拆分「${group.displayName(widget.classById)}」后，这些班级会回到'
          '「可合并的班级」列表，并恢复为独立课程。',
        ),
        actions: [
          AppOutlineButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          AppDestructiveButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认拆分'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final ok = await widget.onSeparate(group.id);
      if (!ok || !mounted) return;
      setState(() {
        _assignments = _assignments
            .map(
              (row) => row.combinedLessonGroupId == group.id
                  ? row.copyWith(clearCombinedLessonGroupId: true)
                  : row,
            )
            .toList(growable: false);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _viewTeacher(String teacherId) => setState(() {
    _teacherId = teacherId;
    _groupKey = null;
    _selected.clear();
    _tab = CombinedLessonTab.existing;
  });

  @override
  Widget build(BuildContext context) {
    final isAll = _tab == CombinedLessonTab.all;
    final stats = combinedLessonStats(_assignments, termId: widget.termId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(isAll),
        _buildTrail(isAll),
        if (!isAll) _buildContextBar(),
        if (!isAll && _candidateGroups.length > 1) _buildGroupPicker(),
        _buildTabs(stats),
        Expanded(child: _buildBody(isAll)),
        _buildFooter(isAll, stats),
      ],
    );
  }

  Widget _buildHeader(bool isAll) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 18, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: context.appColors.selectedBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.group_outlined,
            size: 18,
            color: context.appColors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAll
                    ? '全部合班课'
                    : '合班 · ${_teacherId == null ? '' : _teacherName(_teacherId!)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isAll ? '按教师汇总本学期已设置的合班课' : '候选班级来自该教师展开后的任课明细',
                style: TextStyle(fontSize: 12, color: context.appColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.close, size: 18, color: context.appColors.muted),
        ),
      ],
    ),
  );

  Widget _buildTrail(bool isAll) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        _trailText('教师任课'),
        _trailArrow(),
        if (isAll)
          Text(
            '合班课汇总',
            style: TextStyle(fontSize: 11, color: context.appColors.blue),
          )
        else ...[
          _trailText(_teacherId == null ? '' : _teacherName(_teacherId!)),
          _trailArrow(),
          _trailChip('⋯ 更多操作'),
          _trailArrow(),
          Text(
            '合班',
            style: TextStyle(fontSize: 11, color: context.appColors.blue),
          ),
        ],
      ],
    ),
  );

  Widget _trailText(String text) => Text(
    text,
    style: TextStyle(fontSize: 11, color: context.appColors.muted),
  );

  Widget _trailArrow() =>
      Icon(Icons.chevron_right, size: 12, color: context.appColors.muted);

  Widget _trailChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: context.appColors.canvas,
      border: Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, color: context.appColors.muted),
    ),
  );

  Widget _buildContextBar() {
    final group = _activeGroup;
    final cells = <(String, String)>[
      ('任课教师', _teacherId == null ? '—' : _teacherName(_teacherId!)),
      ('科目', group == null ? '—' : _subjectName(group.subjectId)),
      ('周模式', group?.weekMode.label ?? '—'),
      ('每周节数', group == null ? '—' : '${group.lessonCount} 节'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      decoration: BoxDecoration(
        color: context.appColors.canvas,
        border: Border.all(color: context.appColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  border: i == cells.length - 1
                      ? null
                      : Border(
                          right: BorderSide(color: context.appColors.border),
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cells[i].$1,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.appColors.muted,
                      ),
                    ),
                    Text(
                      cells[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: i == 3
                            ? context.appColors.blue
                            : context.appColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupPicker() {
    final groups = _candidateGroups;
    final activeKey = _activeGroup?.key;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '这位教师有 ${groups.length} 组任课条件，先选择要合并的一组：',
            style: TextStyle(fontSize: 11, color: context.appColors.muted),
          ),
          for (final group in groups)
            _pill(
              label:
                  '${_subjectName(group.subjectId)} · ${group.lessonCount} 节'
                  '（${group.available.length} 个班可合并）',
              selected: group.key == activeKey,
              onTap: () => setState(() {
                _groupKey = group.key;
                _selected.clear();
              }),
            ),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? context.appColors.selectedBlue
            : context.appColors.surface,
        border: Border.all(
          color: selected ? context.appColors.blue : context.appColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: selected
              ? context.appColors.blue
              : context.appColors.inkSecondary,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
        ),
      ),
    ),
  );

  Widget _buildTabs(CombinedLessonStats stats) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
    child: Row(
      children: [
        _tabButton('新建合班', CombinedLessonTab.create),
        const SizedBox(width: 22),
        _tabButton(
          '已有合班组',
          CombinedLessonTab.existing,
          badge: _teacherGroups.length,
        ),
        const SizedBox(width: 22),
        _tabButton('全部合班课', CombinedLessonTab.all, badge: stats.groupCount),
      ],
    ),
  );

  Widget _tabButton(String label, CombinedLessonTab tab, {int? badge}) {
    final active = _tab == tab;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _switchTab(tab),
      child: Container(
        padding: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? context.appColors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: active
                    ? context.appColors.blue
                    : context.appColors.muted,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            if (badge != null && badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: active
                      ? context.appColors.selectedBlue
                      : context.appColors.canvas,
                  border: Border.all(color: context.appColors.border),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    fontSize: 10,
                    color: active
                        ? context.appColors.blue
                        : context.appColors.inkSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isAll) {
    if (isAll) return _buildAllTab();
    if (_tab == CombinedLessonTab.existing) return _buildExistingTab();
    return _buildCreateTab();
  }

  Widget _buildCreateTab() {
    final group = _activeGroup;
    final available = group?.available ?? const <TeacherAssignment>[];
    final visible = available
        .where(
          (row) => _query.isEmpty || _className(row.classId).contains(_query),
        )
        .toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final candidate = _buildCandidatePane(visible, group);
        final preview = _buildPreview(group);
        if (narrow) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [candidate, const SizedBox(height: 18), preview],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SingleChildScrollView(child: candidate)),
              const SizedBox(width: 18),
              Expanded(child: SingleChildScrollView(child: preview)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCandidatePane(
    List<TeacherAssignment> visible,
    CombinedLessonCandidateGroup? group,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          const Text(
            '可合并的班级',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(
            '${visible.length} 个',
            style: TextStyle(fontSize: 11, color: context.appColors.muted),
          ),
          const Spacer(),
          AppGhostButton(
            onPressed: visible.isEmpty ? null : () => _selectAll(visible),
            child: const Text('全选'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      AppTextFormField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value.trim()),
        decoration: const InputDecoration(
          hintText: '搜索班级，如「3 班」',
          isDense: true,
        ),
      ),
      const SizedBox(height: 10),
      _bordered(
        // 候选列表要有清晰圆角外框，否则选中行的浅蓝底看起来没有边界。
        borderColor: Color.lerp(
          context.appColors.border,
          context.appColors.muted,
          0.28,
        ),
        child: group == null
            ? _emptyState(
                '暂无可合并的任课',
                '这位教师没有 2 个以上「教师 / 科目 / 周模式 / 节数」'
                    '完全一致的班级。',
              )
            : visible.isEmpty
            ? _emptyState('没有匹配的班级', '换个关键词，或先拆分已有合班组。')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < visible.length; i++)
                    _candidateRow(
                      visible[i],
                      _selected.contains(visible[i].id),
                      isLast: i == visible.length - 1,
                    ),
                ],
              ),
      ),
      const SizedBox(height: 10),
      Text(
        '只显示与当前条件组完全一致的班级；已合班的班级需先拆分才能重新组合。',
        style: TextStyle(fontSize: 10, color: context.appColors.muted),
      ),
      // 没有已合班组时不渲染这一段，避免挂着空标题和一大片留白。
      if (_teacherGroups.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              '已在合班组中',
              style: TextStyle(fontSize: 12, color: context.appColors.muted),
            ),
            const SizedBox(width: 8),
            Expanded(child: Divider(color: context.appColors.border)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _switchTab(CombinedLessonTab.existing),
              child: Text(
                '查看全部',
                style: TextStyle(fontSize: 12, color: context.appColors.blue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._teacherGroups.map(_lockedGroupRow),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: context.appColors.warningSurface,
            border: Border.all(color: context.appColors.warning),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 13,
                color: context.appColors.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '这些班级已属于其他合班组，需先拆分才能重新组合。',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _candidateRow(
    TeacherAssignment row,
    bool selected, {
    bool isLast = false,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      // 行左右各 12px、checkbox 与间距约 32px，余下宽度给 label；
      // label 不能用 Expanded/Flexible（会触发 ParentDataWidget 断言）。
      final labelWidth = (constraints.maxWidth - 56).clamp(140.0, 320.0);
      return Container(
        constraints: const BoxConstraints(minHeight: 42),
        // 有 minHeight 时 Container 默认把 child 贴在顶部，内容会偏上；
        // centerLeft 让整行内容在 42px 行高里垂直居中。
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? context.appColors.selectedBlue : Colors.transparent,
          border: Border(
            bottom: isLast
                ? BorderSide.none
                : BorderSide(color: context.appColors.border),
            // 每一行都预留同样的 2px 左边框，否则已选行因强调条
            // 比未选行多出 2px，checkbox 与班级名会横向错位。
            left: BorderSide(
              color: selected ? context.appColors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: AppCheckbox(
          value: selected,
          onChanged: (checked) => _toggle(row.id, checked),
          label: SizedBox(
            width: labelWidth,
            // 与 checkbox 等高，配合 Row 的 center 保证文字垂直居中。
            height: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: labelWidth - 66),
                  child: Text(
                    _className(row.classId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? context.appColors.blue
                          : context.appColors.ink,
                    ),
                  ),
                ),
                Text(
                  '每周 ${row.lessonCount} 节',
                  style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? context.appColors.blue
                        : context.appColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _lockedGroupRow(CombinedLessonGroupView group) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: context.appColors.canvas,
      border: Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.displayName(widget.classById),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              '${group.members.length} 个班',
              style: TextStyle(fontSize: 10, color: context.appColors.muted),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _busy ? null : () => _separate(group),
              child: Text(
                '拆分',
                style: TextStyle(fontSize: 11, color: context.appColors.blue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${_teacherName(group.teacherId)} · '
          '${_subjectName(group.subjectId)} · '
          '每周 ${group.lessonCount} 节 · ${group.weekMode.label}',
          style: TextStyle(fontSize: 10, color: context.appColors.muted),
        ),
      ],
    ),
  );

  Widget _buildPreview(CombinedLessonCandidateGroup? group) {
    final selected = _selectedAssignments;
    final title = Row(
      children: [
        const Text(
          '合并预览',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
        ),
        const Spacer(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: context.appColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '实时',
              style: TextStyle(fontSize: 10, color: context.appColors.success),
            ),
          ],
        ),
      ],
    );
    return _bordered(
      padding: const EdgeInsets.all(14),
      minHeight: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          const SizedBox(height: 12),
          if (group == null)
            _emptyState('暂无可合并的任课', '没有 2 个以上条件完全一致的班级。')
          else if (selected.isEmpty)
            _emptyState('还没有选班级', '从左侧勾选至少 2 个班级，这里会显示合并后的课表效果。')
          else if (selected.length == 1)
            Column(
              children: [
                _emptyState(
                  '已选 ${_className(selected.first.classId)}',
                  '再选 1 个班级即可组成合班组。',
                ),
                const SizedBox(height: 10),
                _hintBox('合班至少需要 2 个班级。当前只有 1 个，暂不能确认。', warning: true),
              ],
            )
          else ...[
            _fieldLabel('合班组名称'),
            const SizedBox(height: 5),
            // 只读派生名：不用输入框外观，避免看起来可编辑却点不动。
            Text(
              deriveCombinedLessonName(
                selected
                    .map((row) => _className(row.classId))
                    .toList(growable: false),
              ),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              '名称由参与班级自动生成，暂不支持自定义',
              style: TextStyle(fontSize: 10, color: context.appColors.muted),
            ),
            const SizedBox(height: 14),
            _fieldLabel('参与班级（${selected.length} 个）'),
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final row in selected)
                  _memberChip(
                    _className(row.classId),
                    onRemove: () => _toggle(row.id, false),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _fieldLabel('课表上的样子'),
            const SizedBox(height: 5),
            _timetablePreview(group, selected),
            const SizedBox(height: 12),
            _hintBox(
              '两个班在同一节课一起上课，课时数不叠加：合并前每班 '
              '${group.lessonCount} 节，合并后仍是每周 ${group.lessonCount} 节。',
            ),
            const SizedBox(height: 12),
            _checkList(group),
          ],
        ],
      ),
    );
  }

  Widget _timetablePreview(
    CombinedLessonCandidateGroup group,
    List<TeacherAssignment> selected,
  ) => Container(
    decoration: BoxDecoration(
      color: context.appColors.surface,
      border: Border.all(color: context.appColors.blue),
      borderRadius: BorderRadius.circular(8),
    ),
    // 用 ClipRRect 裁内容，不用 Container.clipBehavior：后者会把 1px
    // 边框在圆角处的抗锯齿一起裁掉，看起来像圆角处缺了一段边框。
    child: ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: context.appColors.selectedBlue,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Text(
              '周三 · 第 3 节 · 1 个课程块',
              style: TextStyle(fontSize: 10, color: context.appColors.blue),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _subjectName(group.subjectId),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final row in selected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: context.appColors.selectedBlue,
                          // 与上方「参与班级」chip 保持一致的蓝色描边。
                          border: Border.all(color: context.appColors.blue),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _className(row.classId),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.appColors.blue,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_teacherName(group.teacherId)} · 普通教室 · '
                  '每周 ${group.lessonCount} 节',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _checkList(CombinedLessonCandidateGroup group) {
    final checks = <String>[
      '同一任课教师：${_teacherName(group.teacherId)}',
      '同一科目：${_subjectName(group.subjectId)}',
      '周模式一致：${group.weekMode.label}',
      '每周节数一致：${group.lessonCount} 节',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.appColors.border)),
          ),
          child: Text(
            '合并条件校验',
            style: TextStyle(fontSize: 11, color: context.appColors.muted),
          ),
        ),
        for (final check in checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(Icons.check, size: 12, color: context.appColors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(check, style: const TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildExistingTab() {
    final groups = _teacherGroups;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: groups.isEmpty
          ? _bordered(child: _emptyState('还没有合班组', '切到「新建合班」，勾选至少 2 个班级即可创建。'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      '当前合班组',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${groups.length} 组',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final group in groups) _existingGroupCard(group),
                const SizedBox(height: 4),
                _hintBox('拆分后，这些班级会立刻回到「可合并的班级」列表，可重新组合。'),
              ],
            ),
    );
  }

  Widget _existingGroupCard(CombinedLessonGroupView group) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.displayName(widget.classById),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${group.members.length} 个班',
              style: TextStyle(fontSize: 10, color: context.appColors.muted),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _busy ? null : () => _separate(group),
              child: Text(
                '拆分',
                style: TextStyle(fontSize: 11, color: context.appColors.blue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_teacherName(group.teacherId)} · '
          '${_subjectName(group.subjectId)} · '
          '每周 ${group.lessonCount} 节 · ${group.weekMode.label}',
          style: TextStyle(fontSize: 11, color: context.appColors.muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final member in group.members)
              _memberChip(_className(member.classId)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 9),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.appColors.border)),
          ),
          child: Text(
            '课表上合并为 1 个课程块，课时数不叠加',
            style: TextStyle(fontSize: 11, color: context.appColors.muted),
          ),
        ),
      ],
    ),
  );

  Widget _buildAllTab() {
    final stats = combinedLessonStats(_assignments, termId: widget.termId);
    final groups = _allGroups;
    final byTeacher = <String, List<CombinedLessonGroupView>>{};
    for (final group in groups) {
      byTeacher.putIfAbsent(group.teacherId, () => []).add(group);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: groups.isEmpty
          ? _bordered(
              child: _emptyState('还没有合班课', '在教师行尾 ⋯ →「合班」中创建的合班组会汇总到这里。'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      '全校合班课',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${stats.groupCount} 组 · ${stats.classCount} 个班 · '
                      '${stats.teacherCount} 位教师',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final entry in byTeacher.entries)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.appColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _teacherName(entry.key),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final group in entry.value)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        group.displayName(widget.classById),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _viewTeacher(entry.key),
                                      child: Text(
                                        '查看该教师',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: context.appColors.blue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_subjectName(group.subjectId)} · '
                                  '每周 ${group.lessonCount} 节 · '
                                  '${group.weekMode.label}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.appColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final member in group.members)
                                      _memberChip(_className(member.classId)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                _hintBox(
                  '这里只做汇总查看。拆分与继续合并请点「查看该教师」，'
                  '回到该教师自己的合班流程。',
                ),
              ],
            ),
    );
  }

  Widget _buildFooter(bool isAll, CombinedLessonStats stats) {
    final count = _selected.length;
    final group = _activeGroup;
    String title;
    String subtitle;
    var warning = true;
    if (isAll) {
      title = '共 ${stats.groupCount} 组合班课 · ${stats.classCount} 个班级';
      subtitle = '涉及 ${stats.teacherCount} 位教师；拆分请进入对应教师的「已有合班组」';
      warning = false;
    } else if (_tab == CombinedLessonTab.existing) {
      title = '已有 ${_teacherGroups.length} 个合班组';
      subtitle = '可在此拆分，或切到「新建合班」继续组合';
      warning = false;
    } else if (_busy) {
      title = '正在保存…';
      subtitle = '请稍候';
    } else if (group == null) {
      title = '暂无可合并的班级';
      subtitle = '该教师没有条件完全一致的 2 个以上班级';
    } else if (count == 0) {
      title = '已选 0 个班级';
      subtitle = '至少选择 2 个班级才能合班';
    } else if (count == 1) {
      title = '已选 1 个班级';
      subtitle = '再选 1 个班级即可合班';
    } else {
      title = '已选 $count 个班级，条件全部满足';
      subtitle = '合并后共 1 个上课单位，每周 ${group.lessonCount} 节';
      warning = false;
    }
    final canConfirm =
        !_busy &&
        !isAll &&
        _tab == CombinedLessonTab.create &&
        group != null &&
        count >= 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.appColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: warning
                        ? context.appColors.warning
                        : context.appColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppGhostButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(_tab == CombinedLessonTab.create ? '取消' : '关闭'),
          ),
          if (!isAll && _tab == CombinedLessonTab.create) ...[
            const SizedBox(width: 8),
            AppPrimaryButton(
              onPressed: canConfirm ? _combine : null,
              child: const Text('确认合班'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memberChip(String label, {VoidCallback? onRemove}) => Container(
    height: 26,
    padding: EdgeInsets.only(left: 9, right: onRemove == null ? 9 : 5),
    decoration: BoxDecoration(
      color: context.appColors.selectedBlue,
      border: Border.all(color: context.appColors.blue),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.appColors.blue),
        ),
        if (onRemove != null)
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: context.appColors.blue),
          ),
      ],
    ),
  );

  Widget _fieldLabel(String text) => Text(
    text,
    style: TextStyle(fontSize: 11, color: context.appColors.muted),
  );

  Widget _hintBox(String text, {bool warning = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: warning
          ? context.appColors.warningSurface
          : context.appColors.successSurface,
      border: Border.all(
        color: warning ? context.appColors.warning : context.appColors.success,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 13,
          color: warning
              ? context.appColors.warning
              : context.appColors.success,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: warning
                  ? context.appColors.warning
                  : context.appColors.success,
              height: 1.55,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _bordered({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    double minHeight = 0,
    Color? borderColor,
  }) => Container(
    constraints: BoxConstraints(minHeight: minHeight),
    decoration: BoxDecoration(
      border: Border.all(color: borderColor ?? context.appColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );

  Widget _emptyState(String title, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: context.appColors.canvas,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.group_outlined,
            size: 22,
            color: context.appColors.muted,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.appColors.inkSecondary),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.appColors.muted),
        ),
      ],
    ),
  );
}
