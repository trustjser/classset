part of 'teachers_page.dart';

Widget _teacherViewSwitcherPanel(Widget switcher) => SizedBox(
  key: const ValueKey('teacher-view-switcher-block'),
  height: 56,
  child: AppSurface(
    child: Padding(padding: const EdgeInsets.all(4), child: switcher),
  ),
);

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
  bool _showGroups = false;

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
        onChange: (index) => setState(() {
          _viewIndex = index;
          _showGroups = false;
        }),
        motion: const FTabMotion(
          duration: Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
        ),
      ),
      style: FTabsStyleDelta.delta(
        decoration: DecorationDelta.value(
          ShapeDecoration(
            color: AppTheme.selectedBlue,
            shape: RoundedSuperellipseBorder(
              side: const BorderSide(color: AppTheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        indicatorDecoration: DecorationDelta.value(
          ShapeDecoration(
            color: Colors.white,
            shape: RoundedSuperellipseBorder(
              side: const BorderSide(color: AppTheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        padding: EdgeInsetsGeometryDelta.value(EdgeInsets.zero),
        spacing: 0,
        minHeight: 44,
      ),
      scrollable: false,
      children: [
        FTabEntry(
          label: const Text('班级视角', key: ValueKey('teacher-view-tab-class')),
          child: const SizedBox.shrink(),
        ),
        FTabEntry(
          label: const Text('教师视角', key: ValueKey('teacher-view-tab-teacher')),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }

  List<Widget> _buildHeaderActions() {
    final showSearch = !_showGroups && _viewIndex == 1;
    final showAddAssignment = !_showGroups;
    final search = SizedBox(
      width: 180,
      child: AppTextFormField(
        controller: _searchController,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search, size: 18),
          hintText: '按姓名查找教师',
          isDense: true,
        ),
      ),
    );
    final addAssignment = AppGhostButton(
      key: const ValueKey('teacher-header-add-assignment'),
      onPressed: _addBatchAssignments,
      child: const Text(
        '添加任课',
        style: TextStyle(color: AppTheme.blue, fontWeight: FontWeight.w600),
      ),
    );
    final returnToAssignments = AppOutlineButton.icon(
      key: const ValueKey('teacher-groups-return'),
      onPressed: () => setState(() => _showGroups = false),
      icon: const Icon(Icons.arrow_back_rounded, size: 17),
      label: const Text('返回任课视图'),
    );
    final addGroup = AppPrimaryButton.icon(
      key: const ValueKey('teacher-groups-add'),
      onPressed: _addGroup,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('新增分组'),
    );
    final more = AppMenuButton(
      key: const ValueKey('teacher-header-overflow'),
      items: _showGroups
          ? [
              AppMenuItem(
                label: '预排',
                onPressed: () =>
                    _openTeacherPresetPage(ownerKind: _PresetOwnerKind.teacher),
              ),
              AppMenuItem(label: '导入分组', onPressed: _importGroups),
              AppMenuItem(label: '导出分组', onPressed: _exportGroups),
            ]
          : [
              AppMenuItem(
                label: '预排',
                onPressed: () =>
                    _openTeacherPresetPage(ownerKind: _PresetOwnerKind.teacher),
              ),
              AppMenuItem(
                label: '教师分组管理',
                onPressed: () => setState(() => _showGroups = true),
              ),
              AppMenuItem(label: '新增教师', onPressed: _addTeacher),
              AppMenuItem(label: 'Excel导入教师', onPressed: _importTeachers),
              AppMenuItem(label: '导出教师 Excel', onPressed: _exportTeachers),
              AppMenuItem(label: '导入分组', onPressed: _importGroups),
              AppMenuItem(label: '导出分组', onPressed: _exportGroups),
              AppMenuItem(label: '新增分组', onPressed: _addGroup),
            ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '更多',
              style: TextStyle(color: AppTheme.inkSecondary, fontSize: 12),
            ),
            SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 15, color: AppTheme.muted),
          ],
        ),
      ),
    );

    return [
      if (_showGroups) returnToAssignments,
      if (_showGroups) addGroup,
      if (showSearch) search,
      if (showAddAssignment) addAssignment,
      more,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final teachers = ref.watch(teachersProvider(widget.termId));
    final assignments = ref.watch(teacherAssignmentsProvider(widget.termId));
    final groups = ref.watch(teacherGroupsProvider(widget.termId));
    final subjects = ref.watch(subjectsProvider);
    final classes = ref.watch(classesForTermProvider(widget.termId));
    final requirements = ref.watch(allRequirementsProvider);
    final subjectNames = {
      for (final subject in subjects.valueOrNull ?? const <Subject>[])
        subject.id: subject.name,
    };
    final pageWidth = MediaQuery.sizeOf(context).width;
    final subtitle = _showGroups
        ? '按分组维护教师成员，并设置该组在具体课节的预排规则。'
        : _viewIndex == 0
        ? '支持拖拽分配：把未分配课程拖给教师，或把任课拖回未分配课程区；可跨学段选择班级。'
        : '按教师查看任课和周均节数；任课可拖回未分配课程区，课程池中的课程可拖给教师。';

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
          ),
          const SizedBox(height: AppTheme.pageSectionGap),
          Expanded(
            child: _showGroups
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
                    viewSwitcher: _buildViewSwitcher(),
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
                    searchController: _searchController,
                    viewSwitcher: _buildViewSwitcher(),
                    onSaveAssignments: _saveAssignments,
                    onAssignUnassigned: _assignUnassigned,
                    onReturnAssignment: _transferAssignment,
                  ),
          ),
        ],
      ),
    );
  }
}
