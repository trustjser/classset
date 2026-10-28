part of '../teachers_page.dart';

class _TeacherList extends StatelessWidget {
  const _TeacherList({
    required this.searchController,
    required this.teachers,
    required this.assignments,
    required this.classes,
    required this.requirements,
    required this.subjectNames,
    required this.onDelete,
    required this.onDeleteAssignments,
    required this.onAddTeacher,
    required this.onEditTeacher,
    required this.onEditPreset,
    required this.onSaveAssignments,
    required this.onAddAssignment,
    required this.onAssignUnassigned,
    required this.onTransferAssignment,
    required this.onCombineAssignments,
    required this.onSeparateCombinedGroup,
  });

  static const _minTableWidth = 600.0;
  static const _teacherColumnWidth = 190.0;
  static const _workloadColumnWidth = 84.0;
  static const _actionsColumnWidth = 52.0;

  final TextEditingController searchController;
  final List<Teacher> teachers;
  final List<TeacherAssignment> assignments;
  final List<ClassBrief> classes;
  final List<SubjectRequirement> requirements;
  final Map<String, String> subjectNames;
  final Future<void> Function(Teacher) onDelete;
  final Future<void> Function(Teacher, List<TeacherAssignment>)
  onDeleteAssignments;
  final VoidCallback onAddTeacher;
  final ValueChanged<Teacher> onEditTeacher;
  final ValueChanged<Teacher> onEditPreset;
  final Future<bool> Function(
    String classId,
    String subjectId,
    List<TeacherAssignment> assignments,
  )
  onSaveAssignments;
  final ValueChanged<Teacher> onAddAssignment;
  final Future<void> Function(
    Teacher teacher,
    TeacherAssignmentMatrixCourse course,
  )
  onAssignUnassigned;
  final Future<void> Function(TeacherAssignment assignment, String teacherId)
  onTransferAssignment;
  final Future<void> Function(Teacher, List<TeacherAssignment>)
  onCombineAssignments;
  final Future<void> Function(String groupId) onSeparateCombinedGroup;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: searchController,
    builder: (context, value, _) {
      final query = value.text.trim().toLowerCase();
      final visible = teachers
          .where(
            (teacher) =>
                query.isEmpty ||
                teacher.searchText.toLowerCase().contains(query),
          )
          .toList(growable: false);
      final classById = {for (final item in classes) item.id: item};
      final teachersById = {
        for (final teacher in teachers) teacher.id: teacher,
      };
      final assignmentsByTeacher = <String, List<TeacherAssignment>>{};
      final assignmentsByDemand = <String, List<TeacherAssignment>>{};
      for (final assignment in assignments) {
        if (assignment.teacherId.isEmpty) continue;
        assignmentsByTeacher
            .putIfAbsent(assignment.teacherId, () => [])
            .add(assignment);
        assignmentsByDemand
            .putIfAbsent(assignment.demandKey, () => [])
            .add(assignment);
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final tableWidth = constraints.maxWidth < _minTableWidth
              ? _minTableWidth
              : constraints.maxWidth;
          return DecoratedBox(
            key: const ValueKey('teacher-assignment-table'),
            decoration: BoxDecoration(
              color: context.appColors.surface,
              boxShadow: context.appColors.cardShadow,
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
                        key: const ValueKey('teacher-assignment-table-header'),
                        height: 40,
                        textColor: context.appColors.muted,
                        backgroundColor: context.appColors.surface,
                        textStyle: AppTheme.matrixHeaderTextStyle(context),
                        children: const [
                          SizedBox(
                            width: _teacherColumnWidth,
                            child: Text('教师'),
                          ),
                          Expanded(child: Text('任课安排')),
                          SizedBox(
                            width: _workloadColumnWidth,
                            child: Text('周均节数'),
                          ),
                          SizedBox(
                            width: _actionsColumnWidth,
                            child: Center(child: Text('操作')),
                          ),
                        ],
                      ),
                      Divider(height: 1, color: context.appColors.border),
                      Expanded(
                        child: ListView.builder(
                          key: const ValueKey('teacher-assignment-list'),
                          padding: EdgeInsets.zero,
                          itemCount: visible.isEmpty ? 2 : visible.length + 1,
                          itemBuilder: (context, index) {
                            if (visible.isEmpty && index == 0) {
                              return const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(child: Text('没有匹配的教师')),
                              );
                            }
                            if (index >= visible.length) {
                              return _addTeacherRow(context);
                            }
                            final teacher = visible[index];
                            final own =
                                assignmentsByTeacher[teacher.id] ??
                                const <TeacherAssignment>[];
                            return _teacherRow(
                              teacher: teacher,
                              own: own,
                              classById: classById,
                              teachersById: teachersById,
                              assignmentsByDemand: assignmentsByDemand,
                              requirements: requirements,
                            );
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
    },
  );

  Widget _addTeacherRow(BuildContext context) => SizedBox(
    height: 48,
    child: FButton(
      variant: FButtonVariant.ghost,
      mainAxisSize: MainAxisSize.max,
      onPress: onAddTeacher,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add, color: context.appColors.blue, size: 18),
          SizedBox(width: 6),
          Text('添加新教师'),
        ],
      ),
    ),
  );

  Widget _teacherRow({
    required Teacher teacher,
    required List<TeacherAssignment> own,
    required Map<String, ClassBrief> classById,
    required Map<String, Teacher> teachersById,
    required Map<String, List<TeacherAssignment>> assignmentsByDemand,
    required List<SubjectRequirement> requirements,
  }) {
    final summary = TeacherAssignmentSummary.from(own);
    final stageIds = {
      for (final assignment in own)
        if (classById[assignment.classId] != null)
          classById[assignment.classId]!.stageId,
    };
    final combinedGroups = <String, List<TeacherAssignment>>{};
    for (final assignment in own) {
      final groupId = assignment.combinedLessonGroupId;
      if (groupId != null) {
        combinedGroups.putIfAbsent(groupId, () => []).add(assignment);
      }
    }
    final subjectLabels = {
      for (final assignment in own)
        subjectNames[assignment.subjectId] ?? assignment.subjectId,
    }.toList(growable: false);
    final canCombine =
        own
            .where((assignment) => assignment.combinedLessonGroupId == null)
            .length >=
        2;
    final menuItems = [
      AppMenuItem(label: '添加任课', onPressed: () => onAddAssignment(teacher)),
      if (own.isNotEmpty)
        AppMenuItem(
          label: '删除任课',
          destructive: true,
          onPressed: () => onDeleteAssignments(teacher, own),
        ),
      if (canCombine)
        AppMenuItem(
          label: '合班',
          onPressed: () => onCombineAssignments(teacher, own),
        ),
      for (final entry in combinedGroups.entries)
        AppMenuItem(
          label: '拆分 ${entry.value.length} 班',
          onPressed: () => onSeparateCombinedGroup(entry.key),
        ),
      AppMenuItem(label: '教师预排', onPressed: () => onEditPreset(teacher)),
      AppMenuItem(label: '编辑教师', onPressed: () => onEditTeacher(teacher)),
      AppMenuItem(
        label: '删除教师',
        destructive: true,
        onPressed: () => onDelete(teacher),
      ),
    ];

    return _ExpandableTeacherRow(
      key: ValueKey('teacher-row-expansion-${teacher.id}'),
      builder: (context, expanded, toggleExpanded) => DragTarget<Object>(
        onAcceptWithDetails: (details) {
          final data = details.data;
          if (data is TeacherAssignment) {
            if (data.teacherId != teacher.id) {
              unawaited(onTransferAssignment(data, teacher.id));
            }
          } else if (data is TeacherAssignmentMatrixCourse) {
            unawaited(onAssignUnassigned(teacher, data));
          }
        },
        builder: (context, candidates, _) => DecoratedBox(
          key: ValueKey('teacher-assignment-row-${teacher.id}'),
          decoration: BoxDecoration(
            color: candidates.isEmpty
                ? context.appColors.surface
                : context.appColors.selectedBlue,
            border: Border(bottom: BorderSide(color: context.appColors.border)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _teacherColumnWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message:
                              !teacher.subjectIds.any(subjectNames.containsKey)
                              ? teacher.displayName
                              : '${teacher.displayName}\n可授：${teacher.subjectIds.where(subjectNames.containsKey).map((id) => subjectNames[id]!).join('、')}',
                          child: Text(
                            teacher.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (stageIds.length > 1) ...[
                          const SizedBox(height: 4),
                          const _TeacherTag(label: '跨学段', isAccent: true),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: own.isEmpty
                        ? Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              '暂无任课',
                              style: TextStyle(
                                color: context.appColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : own.length == 1
                        ? _TeacherAssignmentDraggableChip(
                            assignment: own.first,
                            peers:
                                assignmentsByDemand[own.first.demandKey] ??
                                const [],
                            teachersById: teachersById,
                            teachers: teachers,
                            classesById: classById,
                            subjectNames: subjectNames,
                            requirements: _assignmentRequirements(
                              own.first,
                              classById,
                              requirements,
                            ),
                            onSaveAssignments: onSaveAssignments,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${own.length} 项任课',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Tooltip(
                                          message: subjectLabels.join('、'),
                                          child: Text(
                                            subjectLabels.join('、'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: context.appColors.muted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  FButton(
                                    key: ValueKey(
                                      'teacher-assignment-toggle-${teacher.id}',
                                    ),
                                    variant: FButtonVariant.ghost,
                                    size: FButtonSizeVariant.xs,
                                    style: .delta(
                                      contentStyle: .delta(
                                        constraints:
                                            const BoxConstraints.tightFor(
                                              height: 24,
                                            ),
                                        padding: .value(
                                          const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                        ),
                                      ),
                                    ),
                                    onPress: toggleExpanded,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          expanded ? '收起' : '展开',
                                          style: TextStyle(
                                            color: context.appColors.muted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w400,
                                            height: 16 / 11,
                                          ),
                                        ),
                                        const SizedBox(width: 1),
                                        Icon(
                                          expanded
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          size: 14,
                                          color: context.appColors.muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (expanded)
                                Container(
                                  key: ValueKey(
                                    'teacher-assignment-detail-${teacher.id}',
                                  ),
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: context.appColors.border,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final assignment in own)
                                        _TeacherAssignmentDraggableChip(
                                          assignment: assignment,
                                          peers:
                                              assignmentsByDemand[assignment
                                                  .demandKey] ??
                                              const [],
                                          teachersById: teachersById,
                                          teachers: teachers,
                                          classesById: classById,
                                          subjectNames: subjectNames,
                                          requirements: _assignmentRequirements(
                                            assignment,
                                            classById,
                                            requirements,
                                          ),
                                          onSaveAssignments: onSaveAssignments,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                  SizedBox(
                    width: _workloadColumnWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${_formatLessons(summary.biweeklyAverage)} 节',
                        style: TextStyle(
                          color: context.appColors.inkSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _actionsColumnWidth,
                    child: Center(
                      child: AppMenuButton(
                        key: ValueKey('teacher-row-more-${teacher.id}'),
                        items: menuItems,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: context.appColors.inkSecondary,
                          ),
                        ),
                      ),
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

  List<SubjectRequirement> _assignmentRequirements(
    TeacherAssignment assignment,
    Map<String, ClassBrief> classById,
    List<SubjectRequirement> allRequirements,
  ) {
    final schoolClass = classById[assignment.classId];
    if (schoolClass == null) return const [];
    return _effectiveTeacherAssignmentRequirements(
      allRequirements,
      classId: assignment.classId,
      gradeId: schoolClass.gradeId,
      subjectId: assignment.subjectId,
    );
  }
}

class _ExpandableTeacherRow extends StatefulWidget {
  const _ExpandableTeacherRow({required this.builder, super.key});

  final Widget Function(
    BuildContext context,
    bool expanded,
    VoidCallback toggle,
  )
  builder;

  @override
  State<_ExpandableTeacherRow> createState() => _ExpandableTeacherRowState();
}

class _ExpandableTeacherRowState extends State<_ExpandableTeacherRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _expanded,
    () => setState(() => _expanded = !_expanded),
  );
}

class _TeacherAssignmentDraggableChip extends StatelessWidget {
  const _TeacherAssignmentDraggableChip({
    required this.assignment,
    required this.peers,
    required this.teachers,
    required this.teachersById,
    required this.classesById,
    required this.subjectNames,
    required this.requirements,
    required this.onSaveAssignments,
  });

  final TeacherAssignment assignment;
  final List<TeacherAssignment> peers;
  final List<Teacher> teachers;
  final Map<String, Teacher> teachersById;
  final Map<String, ClassBrief> classesById;
  final Map<String, String> subjectNames;
  final List<SubjectRequirement> requirements;
  final Future<bool> Function(
    String classId,
    String subjectId,
    List<TeacherAssignment> assignments,
  )
  onSaveAssignments;

  @override
  Widget build(BuildContext context) {
    final otherTeachers = peers
        .where(
          (peer) =>
              peer.id != assignment.id &&
              peer.teacherId != assignment.teacherId,
        )
        .toList(growable: false);
    final splitNames = otherTeachers
        .map((peer) => teachersById[peer.teacherId]?.displayName ?? '未分配')
        .join('、');
    final splitCounts = [
      assignment.lessonCount,
      for (final peer in otherTeachers) peer.lessonCount,
    ].join('/');
    final splitNote = otherTeachers.isEmpty
        ? null
        : '（与$splitNames $splitCounts 拆分）';
    final fullLabel = _assignmentLabel(
      assignment,
      classesById,
      subjectNames,
      splitNote: splitNote,
    );
    final label = _assignmentLabel(assignment, classesById, subjectNames);
    Widget chip({VoidCallback? onTap}) => _AssignmentChip(
      label: label,
      tooltip: fullLabel,
      subjectId: assignment.subjectId,
      onPressed: onTap,
      isSplit: otherTeachers.isNotEmpty,
    );

    final canEdit = requirements.any(
      (requirement) => requirement.lessonCount > 0,
    );
    final assignmentChip = chip();
    final child = canEdit
        ? _AssignmentEditorPopover(
            key: ValueKey('teacher-assignment-editor-${assignment.id}'),
            title: _assignmentEditorTitle(
              classesById[assignment.classId]?.name ?? assignment.classId,
              subjectNames[assignment.subjectId] ?? assignment.subjectId,
              requirements,
            ),
            teachers: teachers,
            current: peers,
            requirements: requirements,
            onSave: (next) => onSaveAssignments(
              assignment.classId,
              assignment.subjectId,
              next,
            ),
            child: assignmentChip,
          )
        : assignmentChip;

    return Draggable<TeacherAssignment>(
      data: assignment,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 240, child: chip()),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: chip()),
      child: child,
    );
  }
}

class _AssignmentChip extends StatelessWidget {
  const _AssignmentChip({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    required this.subjectId,
    this.isSplit = false,
  });

  final String label;
  final String tooltip;
  final String subjectId;
  final VoidCallback? onPressed;
  final bool isSplit;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        hoverColor: context.appColors.selectedBlue,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              SubjectDot(subjectId: subjectId),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.inkSecondary,
                  ),
                ),
              ),
              if (isSplit) ...[
                const SizedBox(width: 6),
                Text(
                  '拆分',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appColors.warning,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _TeacherTag extends StatelessWidget {
  const _TeacherTag({required this.label, this.isAccent = false});

  final String label;
  final bool isAccent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: isAccent
          ? context.appColors.selectedBlue
          : context.appColors.canvas,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      child: Text(
        label,
        style: TextStyle(
          color: isAccent
              ? context.appColors.blue
              : context.appColors.inkSecondary,
          fontSize: 10,
          height: 1.3,
        ),
      ),
    ),
  );
}

String _formatLessons(double lessons) => lessons == lessons.roundToDouble()
    ? lessons.toInt().toString()
    : lessons.toStringAsFixed(1);

String _assignmentLabel(
  TeacherAssignment assignment,
  Map<String, ClassBrief> classes,
  Map<String, String> subjectNames, {
  String? splitNote,
}) {
  final className = classes[assignment.classId]?.name ?? '班级';
  final subjectName = subjectNames[assignment.subjectId] ?? '科目';
  final weekModeLabel = assignment.weekMode == WeekMode.weekly
      ? ''
      : '（${assignment.weekMode.label}）';
  final combinedTag = assignment.combinedLessonGroupId == null ? '' : ' · 合班';
  return '$subjectName$weekModeLabel · $className · ${assignment.lessonCount} 节${splitNote ?? ''}$combinedTag';
}
