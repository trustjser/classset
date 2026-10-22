part of '../teachers_page.dart';

class _UnassignedCoursePanel extends StatefulWidget {
  const _UnassignedCoursePanel({
    required this.courses,
    required this.onReturnAssignment,
  });

  final List<TeacherAssignmentMatrixCourse> courses;
  final ValueChanged<TeacherAssignment> onReturnAssignment;

  @override
  State<_UnassignedCoursePanel> createState() => _UnassignedCoursePanelState();
}

class _UnassignedCoursePanelState extends State<_UnassignedCoursePanel> {
  final Set<String> _expandedClassIds = {};
  bool _initialized = false;

  Widget _draggableCourse(TeacherAssignmentMatrixCourse course) =>
      Draggable<TeacherAssignmentMatrixCourse>(
        data: course,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 260,
            child: _UnassignedCourseTile(course: course),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: _UnassignedCourseTile(course: course),
        ),
        child: _UnassignedCourseTile(course: course),
      );

  Widget _groupedCourses() {
    final byClass = <String, List<TeacherAssignmentMatrixCourse>>{};
    for (final course in widget.courses) {
      byClass.putIfAbsent(course.classId, () => []).add(course);
    }
    if (!_initialized && byClass.isNotEmpty) {
      _expandedClassIds.add(byClass.keys.first);
      _initialized = true;
    }
    final groups = byClass.entries.toList(growable: false);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final expanded = _expandedClassIds.contains(group.key);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('unassigned-class-toggle-${group.key}'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() {
                  if (expanded) {
                    _expandedClassIds.remove(group.key);
                  } else {
                    _expandedClassIds.add(group.key);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.value.first.className,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${group.value.length} 门',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: AppTheme.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 6),
                child: Column(
                  children: [
                    for (final course in group.value) _draggableCourse(course),
                  ],
                ),
              ),
            const Divider(height: 1, color: AppTheme.border),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<TeacherAssignment>(
      onAcceptWithDetails: (details) => widget.onReturnAssignment(details.data),
      builder: (context, candidates, _) => AppSectionPanel(
        title: '未分配课程',
        trailing: DecoratedBox(
          key: const ValueKey('unassigned-course-count'),
          decoration: BoxDecoration(
            color: AppTheme.warningSurface,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Text(
              '${widget.courses.length} 门',
              style: const TextStyle(
                color: AppTheme.warning,
                fontSize: 10,
                height: 1.3,
              ),
            ),
          ),
        ),
        padding: EdgeInsets.zero,
        expandChild: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: candidates.isEmpty
                ? Colors.transparent
                : AppTheme.warningSurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: widget.courses.isEmpty
              ? const Center(child: Text('课程已全部分配'))
              : _groupedCourses(),
        ),
      ),
    );
  }
}

class _UnassignedCourseTile extends StatelessWidget {
  const _UnassignedCourseTile({required this.course});

  final TeacherAssignmentMatrixCourse course;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: _unassignedLabel(course),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${course.subjectName}${course.weekMode == WeekMode.weekly ? '' : '（${course.weekMode.label}）'} · ${course.remainingLessons} 节',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.inkSecondary,
                fontSize: 12,
              ),
            ),
          ),
          const Icon(Icons.drag_indicator, size: 14, color: AppTheme.muted),
        ],
      ),
    ),
  );
}

class _TeacherDropPanel extends StatelessWidget {
  const _TeacherDropPanel({
    required this.searchController,
    required this.teachers,
    required this.assignments,
    required this.classes,
    required this.stageNames,
    required this.onAssign,
  });

  final TextEditingController searchController;
  final List<Teacher> teachers;
  final List<TeacherAssignment> assignments;
  final List<ClassBrief> classes;
  final Map<String, String> stageNames;
  final Future<void> Function(
    Teacher teacher,
    TeacherAssignmentMatrixCourse course,
  )
  onAssign;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: searchController,
    builder: (context, value, _) {
      final query = value.text.trim().toLowerCase();
      final matching = teachers
          .where(
            (teacher) =>
                query.isEmpty ||
                teacher.searchText.toLowerCase().contains(query),
          )
          .toList(growable: false);
      final classById = {for (final item in classes) item.id: item};
      final assignmentsByTeacher = <String, List<TeacherAssignment>>{};
      for (final assignment in assignments) {
        assignmentsByTeacher
            .putIfAbsent(assignment.teacherId, () => [])
            .add(assignment);
      }
      return AppSectionPanel(
        title: '教师',
        trailing: SizedBox(
          width: 128,
          child: AppTextFormField(
            controller: searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 16),
              hintText: '按姓名查找',
              isDense: true,
            ),
          ),
        ),
        padding: EdgeInsets.zero,
        expandChild: true,
        child: matching.isEmpty
            ? const Center(child: Text('没有匹配的教师'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                itemCount: matching.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final teacher = matching[index];
                  final own = assignmentsByTeacher[teacher.id] ?? const [];
                  final summary = TeacherAssignmentSummary.from(own);
                  final stageIds = {
                    for (final assignment in own)
                      if (classById[assignment.classId] != null)
                        classById[assignment.classId]!.stageId,
                  };
                  final stageLabel = stageIds
                      .map((id) => stageNames[id] ?? id)
                      .where((name) => name.isNotEmpty)
                      .join(' + ');
                  return DragTarget<Object>(
                    onAcceptWithDetails: (details) {
                      final data = details.data;
                      if (data is TeacherAssignmentMatrixCourse) {
                        unawaited(onAssign(teacher, data));
                      } else if (data is TeacherAssignment) {
                        unawaited(
                          onAssign(
                            teacher,
                            TeacherAssignmentMatrixCourse(
                              classId: data.classId,
                              className: classById[data.classId]?.name ?? '班级',
                              subjectId: data.subjectId,
                              subjectName: '科目',
                              weekMode: data.weekMode,
                              remainingLessons: data.lessonCount,
                              existingAssignmentId: data.id,
                            ),
                          ),
                        );
                      }
                    },
                    builder: (context, candidates, _) => AppSurface(
                      showBorder: false,
                      backgroundColor: candidates.isEmpty
                          ? null
                          : AppTheme.selectedBlue,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    teacher.displayName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (stageIds.length > 1)
                                    const _TeacherTag(
                                      label: '跨学段',
                                      isAccent: true,
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '${_formatLessons(summary.biweeklyAverage)} 节${stageLabel.isEmpty ? '' : ' · $stageLabel'}',
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      );
    },
  );
}

class _GroupList extends ConsumerWidget {
  const _GroupList({
    required this.termId,
    required this.groups,
    required this.teachers,
    required this.onDelete,
    required this.onEditMembers,
    required this.onEditPreset,
  });
  final String termId;
  final List<TeacherGroup> groups;
  final List<Teacher> teachers;
  final ValueChanged<TeacherGroup> onDelete;
  final ValueChanged<TeacherGroup> onEditMembers;
  final ValueChanged<TeacherGroup> onEditPreset;

  static const _minTableWidth = 720.0;
  static const _memberColumnWidth = 300.0;
  static const _actionsColumnWidth = 220.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members =
        ref.watch(teacherGroupMembersProvider(termId)).valueOrNull ?? const [];
    if (groups.isEmpty) {
      return const AppSectionPanel(
        expandChild: true,
        child: AppEmptyState(
          icon: Icons.groups_outlined,
          title: '还没有教师分组',
          message: '点击右上角“新增分组”，按教研组或排课规则组织教师。',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < _minTableWidth
            ? _minTableWidth
            : constraints.maxWidth;
        return DecoratedBox(
          key: const ValueKey('teacher-groups-table'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    AppDataTableHeader(
                      height: 40,
                      textColor: AppTheme.muted,
                      backgroundColor: Colors.white,
                      textStyle: AppTheme.matrixHeaderTextStyle,
                      children: const [
                        Expanded(child: Text('分组信息')),
                        SizedBox(
                          width: _memberColumnWidth,
                          child: Text('分组成员'),
                        ),
                        SizedBox(width: _actionsColumnWidth, child: Text('操作')),
                      ],
                    ),
                    const Divider(height: 1, color: AppTheme.border),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: groups.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppTheme.border),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final ids = members
                              .where((row) => row.groupId == group.id)
                              .map((row) => row.teacherId)
                              .toSet();
                          final names = teachers
                              .where((teacher) => ids.contains(teacher.id))
                              .map((teacher) => teacher.displayName)
                              .toList(growable: false);
                          return _groupRow(group, names);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _groupRow(TeacherGroup group, List<String> names) => Container(
    key: ValueKey('teacher-group-row-${group.id}'),
    constraints: const BoxConstraints(minHeight: 76),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    color: Colors.white,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                group.description?.trim().isNotEmpty == true
                    ? group.description!.trim()
                    : '暂无说明',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        SizedBox(
          width: _memberColumnWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${names.length} 名教师',
                style: const TextStyle(
                  color: AppTheme.inkSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Tooltip(
                message: names.isEmpty ? '尚未添加成员' : names.join('、'),
                child: Text(
                  names.isEmpty ? '尚未添加成员' : names.join('、'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: _actionsColumnWidth,
          child: Row(
            children: [
              FButton(
                key: ValueKey('teacher-group-members-${group.id}'),
                size: FButtonSizeVariant.xs,
                variant: FButtonVariant.ghost,
                onPress: () => onEditMembers(group),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline, size: 15),
                    SizedBox(width: 4),
                    Text('维护成员'),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              FButton(
                key: ValueKey('teacher-group-preset-${group.id}'),
                size: FButtonSizeVariant.xs,
                variant: FButtonVariant.ghost,
                onPress: () => onEditPreset(group),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy_outlined, size: 15),
                    SizedBox(width: 4),
                    Text('分组预排'),
                  ],
                ),
              ),
              const Spacer(),
              AppMenuButton(
                items: [
                  AppMenuItem(
                    label: '删除分组',
                    destructive: true,
                    onPressed: () => onDelete(group),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: AppTheme.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
