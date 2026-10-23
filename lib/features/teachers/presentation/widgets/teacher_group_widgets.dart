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
                        style: TextStyle(
                          fontSize: 11,
                          color: context.appColors.muted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: context.appColors.muted,
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
            Divider(height: 1, color: context.appColors.border),
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
            color: context.appColors.warningSurface,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Text(
              '${widget.courses.length} 门',
              style: TextStyle(
                color: context.appColors.warning,
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
                : context.appColors.warningSurface,
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
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Icon(Icons.drag_indicator, size: 14, color: context.appColors.muted),
        ],
      ),
    ),
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
            border: Border.all(color: context.appColors.border),
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
                      textColor: context.appColors.muted,
                      backgroundColor: context.appColors.surface,
                      textStyle: AppTheme.matrixHeaderTextStyle(context),
                      children: const [
                        Expanded(child: Text('分组信息')),
                        SizedBox(
                          width: _memberColumnWidth,
                          child: Text('分组成员'),
                        ),
                        SizedBox(width: _actionsColumnWidth, child: Text('操作')),
                      ],
                    ),
                    Divider(height: 1, color: context.appColors.border),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: groups.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: context.appColors.border),
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
                          return _groupRow(context, group, names);
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

  Widget _groupRow(
    BuildContext context,
    TeacherGroup group,
    List<String> names,
  ) => Container(
    key: ValueKey('teacher-group-row-${group.id}'),
    constraints: const BoxConstraints(minHeight: 76),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    color: context.appColors.surface,
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
                style: TextStyle(
                  color: context.appColors.ink,
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
                style: TextStyle(color: context.appColors.muted, fontSize: 11),
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
                style: TextStyle(
                  color: context.appColors.inkSecondary,
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
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 11,
                  ),
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
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: context.appColors.inkSecondary,
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
