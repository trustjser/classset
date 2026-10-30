part of 'teachers_page.dart';

class TeachersPage extends ConsumerStatefulWidget {
  const TeachersPage({required this.termId, super.key});

  final String termId;

  @override
  ConsumerState<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends ConsumerState<TeachersPage> {
  static int _generatedIdSequence = 0;

  final _searchController = TextEditingController();
  final _viewTabsKey = GlobalKey(debugLabel: 'teacher-view-tabs');
  int _viewIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  SchoolRepository get _repository => ref.read(schoolRepositoryProvider);

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_generatedIdSequence++}';

  Future<void> _openTeacherPresetPage({
    required _PresetOwnerKind ownerKind,
    String? ownerId,
  }) async {
    final configuration = await _loadPresetConfiguration();
    if (!mounted || configuration == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(title: const Text('教师预排')),
          body: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.pagePaddingForWidth(
                MediaQuery.sizeOf(routeContext).width,
              ),
              vertical: 20,
            ),
            child: _TeacherPresetWorkspace(
              key: const ValueKey('teacher-preset-workspace'),
              termId: widget.termId,
              configuration: configuration,
              initialOwnerKind: ownerKind,
              initialOwnerId: ownerId,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewSwitcher() {
    return FTabs(
      key: _viewTabsKey,
      control: FTabControl.lifted(
        index: _viewIndex,
        onChange: (index) => setState(() => _viewIndex = index),
        motion: const FTabMotion(
          duration: Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
        ),
      ),
      style: FTabsStyleDelta.delta(
        decoration: DecorationDelta.value(
          ShapeDecoration(
            color: context.appColors.selectedBlue,
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
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        padding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
        spacing: 0,
        minHeight: 34,
      ),
      scrollable: false,
      children: [
        FTabEntry(
          label: const Text(
            '班级',
            key: ValueKey('teacher-view-tab-class'),
            style: TextStyle(fontSize: 12),
          ),
          child: const SizedBox.shrink(),
        ),
        FTabEntry(
          label: const Text(
            '教师',
            key: ValueKey('teacher-view-tab-teacher'),
            style: TextStyle(fontSize: 12),
          ),
          child: const SizedBox.shrink(),
        ),
        FTabEntry(
          label: const Text(
            '分组',
            key: ValueKey('teacher-view-tab-group'),
            style: TextStyle(fontSize: 12),
          ),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }

  List<Widget> _buildHeaderActions() {
    final isGroupView = _viewIndex == 2;
    final showSearch = _viewIndex == 1;
    final showAddAssignment = !isGroupView;
    final search = SizedBox(
      width: 180,
      child: AppTextFormField(
        controller: _searchController,
        decoration: const InputDecoration(hintText: '按姓名查找教师', isDense: true),
      ),
    );
    final addAssignment = AppGhostButton.icon(
      key: const ValueKey('teacher-header-add-assignment'),
      onPressed: _addBatchAssignments,
      icon: Icon(Icons.add, size: 18, color: context.appColors.blue),
      label: Text(
        '添加任课',
        style: TextStyle(
          color: context.appColors.blue,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final addGroup = AppGhostButton.icon(
      key: const ValueKey('teacher-groups-add'),
      onPressed: _addGroup,
      icon: Icon(Icons.add, size: 18, color: context.appColors.blue),
      label: Text(
        '新增分组',
        style: TextStyle(
          color: context.appColors.blue,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final more = AppMenuButton(
      key: const ValueKey('teacher-header-overflow'),
      items: isGroupView
          ? [
              AppMenuItem(
                label: '预排',
                onPressed: () =>
                    _openTeacherPresetPage(ownerKind: _PresetOwnerKind.teacher),
              ),
            ]
          : [
              AppMenuItem(
                label: '预排',
                onPressed: () =>
                    _openTeacherPresetPage(ownerKind: _PresetOwnerKind.teacher),
              ),
              AppMenuItem(label: '新增教师', onPressed: _addTeacher),
              AppMenuItem(label: 'Excel导入教师', onPressed: _importTeachers),
              AppMenuItem(label: 'Excel导入任课分配', onPressed: _importAssignments),
              AppMenuItem(label: '新增分组', onPressed: _addGroup),
            ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '更多',
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
              ),
            ),
            SizedBox(width: 4),
            Icon(
              Icons.expand_more_rounded,
              size: 15,
              color: context.appColors.muted,
            ),
          ],
        ),
      ),
    );

    return [
      if (isGroupView) addGroup,
      if (showSearch) search,
      if (showAddAssignment) addAssignment,
      more,
      SizedBox(
        key: const ValueKey('teacher-view-switcher-header'),
        width: 210,
        child: _buildViewSwitcher(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final teachers = ref.watch(teachersProvider(widget.termId));
    final assignments = ref.watch(teacherAssignmentsProvider(widget.termId));
    final groups = ref.watch(teacherGroupsProvider(widget.termId));
    final subjects = ref.watch(subjectsForTermProvider(widget.termId));
    final classes = ref.watch(classesForTermProvider(widget.termId));
    final requirements = ref.watch(allRequirementsProvider);
    final subjectNames = {
      for (final subject in subjects.valueOrNull ?? const <Subject>[])
        subject.id: subject.name,
    };
    final pageWidth = MediaQuery.sizeOf(context).width;
    final subtitle = _viewIndex == 2
        ? '按分组维护教师成员，并设置该组在具体课节的预排规则。'
        : _viewIndex == 0
        ? '按班级查看科目任课，点击单元格分配或调整任课教师。'
        : '按教师查看任课和周均节数；可从右侧未分配课程区拖拽分配。';

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.pagePaddingForWidth(pageWidth),
        vertical: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: '教师任课',
            subtitle: subtitle,
            actions: _buildHeaderActions(),
            responsiveActions: true,
            actionsFlex: 2,
          ),
          const SizedBox(height: AppTheme.pageSectionGap),
          Expanded(
            child: _viewIndex == 2
                ? _GroupList(
                    termId: widget.termId,
                    groups: groups.valueOrNull ?? const [],
                    teachers: teachers.valueOrNull ?? const [],
                    onDelete: _confirmDeleteGroup,
                    onEditMembers: _editMembers,
                    onEditPreset: (group) => _openTeacherPresetPage(
                      ownerKind: _PresetOwnerKind.group,
                      ownerId: group.id,
                    ),
                  )
                : _viewIndex == 1
                ? _TeacherAssignmentOverview(
                    classes: classes.valueOrNull ?? const [],
                    subjects: subjects.valueOrNull ?? const [],
                    requirements: requirements.valueOrNull ?? const [],
                    assignments: assignments.valueOrNull ?? const [],
                    onReturnAssignment: _transferAssignment,
                    teacherTable: _TeacherList(
                      searchController: _searchController,
                      teachers: teachers.valueOrNull ?? const [],
                      assignments: assignments.valueOrNull ?? const [],
                      classes: classes.valueOrNull ?? const [],
                      requirements: requirements.valueOrNull ?? const [],
                      subjectNames: subjectNames,
                      onDelete: _confirmDeleteTeacher,
                      onDeleteAssignments: _deleteTeacherAssignments,
                      onAddTeacher: _addTeacher,
                      onEditTeacher: _editTeacher,
                      onEditPreset: (teacher) => _openTeacherPresetPage(
                        ownerKind: _PresetOwnerKind.teacher,
                        ownerId: teacher.id,
                      ),
                      onSaveAssignments: _saveAssignments,
                      onAddAssignment: (teacher) =>
                          _addBatchAssignments(teacher: teacher),
                      onAssignUnassigned: _assignUnassigned,
                      onTransferAssignment: _transferAssignment,
                      onCombineAssignments: _combineAssignments,
                      onSeparateCombinedGroup: _separateCombinedGroup,
                    ),
                  )
                : _ClassMatrix(
                    termId: widget.termId,
                    teachers: teachers.valueOrNull ?? const [],
                    assignments: assignments.valueOrNull ?? const [],
                    onSaveAssignments: _saveAssignments,
                  ),
          ),
        ],
      ),
    );
  }
}
