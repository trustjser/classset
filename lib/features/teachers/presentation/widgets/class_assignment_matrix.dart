part of '../teachers_page.dart';

class _ClassMatrix extends ConsumerStatefulWidget {
  const _ClassMatrix({
    required this.termId,
    required this.teachers,
    required this.assignments,
    required this.onSaveAssignments,
  });

  final String termId;
  final List<Teacher> teachers;
  final List<TeacherAssignment> assignments;
  final Future<bool> Function(
    String classId,
    String subjectId,
    List<TeacherAssignment> assignments,
  )
  onSaveAssignments;

  @override
  ConsumerState<_ClassMatrix> createState() => _ClassMatrixState();
}

class _ClassMatrixState extends ConsumerState<_ClassMatrix> {
  static const _subjectColumnWidth = 184.0;
  static const _rowHeight = 48.0;

  final _subjectScrollController = ScrollController();
  final _classScrollController = ScrollController();
  final _horizontalScrollSync = _HorizontalScrollSync();
  ({int rowIndex, int columnIndex})? _hoveredCell;
  bool _syncingVerticalScroll = false;

  @override
  void initState() {
    super.initState();
    _subjectScrollController.addListener(_syncSubjectScroll);
    _classScrollController.addListener(_syncClassScroll);
  }

  @override
  void dispose() {
    _subjectScrollController
      ..removeListener(_syncSubjectScroll)
      ..dispose();
    _classScrollController
      ..removeListener(_syncClassScroll)
      ..dispose();
    _horizontalScrollSync.dispose();
    super.dispose();
  }

  void _syncSubjectScroll() =>
      _syncVerticalScroll(_subjectScrollController, _classScrollController);

  void _syncClassScroll() =>
      _syncVerticalScroll(_classScrollController, _subjectScrollController);

  void _syncVerticalScroll(ScrollController source, ScrollController target) {
    if (_syncingVerticalScroll || !source.hasClients || !target.hasClients) {
      return;
    }
    _syncingVerticalScroll = true;
    try {
      final targetPosition = target.position;
      final offset = source.position.pixels
          .clamp(0.0, targetPosition.maxScrollExtent)
          .toDouble();
      if ((targetPosition.pixels - offset).abs() > 0.5) {
        target.jumpTo(offset);
      }
    } finally {
      _syncingVerticalScroll = false;
    }
  }

  void _setHoveredCell(int rowIndex, int columnIndex) {
    if (_hoveredCell == (rowIndex: rowIndex, columnIndex: columnIndex)) {
      return;
    }
    setState(
      () => _hoveredCell = (rowIndex: rowIndex, columnIndex: columnIndex),
    );
  }

  void _clearHoveredCell(int rowIndex, int columnIndex) {
    if (_hoveredCell != (rowIndex: rowIndex, columnIndex: columnIndex)) {
      return;
    }
    setState(() => _hoveredCell = null);
  }

  @override
  Widget build(BuildContext context) {
    final classes =
        ref.watch(classesForTermProvider(widget.termId)).valueOrNull ??
        const [];
    final subjects = ref.watch(subjectsProvider).valueOrNull ?? const [];
    final stages =
        ref.watch(stagesProvider(widget.termId)).valueOrNull ?? const [];
    final requirements =
        ref.watch(allRequirementsProvider).valueOrNull ?? const [];
    if (classes.isEmpty || subjects.isEmpty) {
      return const Center(child: Text('请先设置班级和科目'));
    }

    final matrixData = TeacherAssignmentMatrixData.build(
      classes: classes,
      subjects: subjects,
      requirements: requirements,
      assignments: widget.assignments,
    );
    final teachersById = {
      for (final teacher in widget.teachers) teacher.id: teacher,
    };
    final stageIndexById = {
      for (final (index, stage) in stages.indexed) stage.id: index,
    };
    final matrix = _buildMatrix(
      classes: classes,
      subjects: subjects,
      matrixData: matrixData,
      teachersById: teachersById,
      stageIndexById: stageIndexById,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1000) {
          final matrixHeight = (40 + subjects.length * _rowHeight)
              .clamp(320.0, double.infinity)
              .toDouble();
          return SingleChildScrollView(
            key: const ValueKey('teacher-class-view-page-scroll'),
            child: SizedBox(height: matrixHeight, child: matrix),
          );
        }
        return matrix;
      },
    );
  }

  Widget _buildMatrix({
    required List<ClassBrief> classes,
    required List<Subject> subjects,
    required TeacherAssignmentMatrixData matrixData,
    required Map<String, Teacher> teachersById,
    required Map<String, int> stageIndexById,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableGridWidth = (constraints.maxWidth - _subjectColumnWidth)
            .clamp(0.0, double.infinity);
        final fittedColumnWidth = availableGridWidth / classes.length;
        final classColumnWidth = fittedColumnWidth > 190
            ? fittedColumnWidth
            : 190.0;

        Widget subjectRow(int index) {
          final subject = subjects[index];
          return ColoredBox(
            color: context.appColors.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                key: ValueKey('subject-info-${subject.id}'),
                children: [
                  Flexible(
                    child: Text(
                      subject.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final mode in _subjectWeekModes(
                    matrixData,
                    classes,
                    subject,
                  )) ...[
                    const SizedBox(width: 4),
                    _SubjectWeekModeTag(mode: mode),
                  ],
                ],
              ),
            ),
          );
        }

        Widget assignmentCell(
          ClassBrief item,
          Subject subject,
          int rowIndex,
          int columnIndex,
        ) {
          final cell = matrixData.cellFor(
            classId: item.id,
            subjectId: subject.id,
          );
          final canEditAssignments = cell.requirements.any(
            (requirement) => requirement.lessonCount > 0,
          );
          final assignmentSpans = <InlineSpan>[];
          final tooltipEntries = <String>[];
          void appendAssignment(InlineSpan span) {
            if (assignmentSpans.isNotEmpty) {
              assignmentSpans.add(const TextSpan(text: ' '));
            }
            assignmentSpans.add(span);
          }

          for (final assignment in cell.assignments) {
            tooltipEntries.add(_assignmentLabel(assignment, teachersById));
            appendAssignment(_assignmentSpan(assignment, teachersById));
          }
          for (final course in cell.remainingCourses) {
            tooltipEntries.add(_unassignedLabel(course));
          }
          Widget unassignedCourse(TeacherAssignmentMatrixCourse course) =>
              Draggable<TeacherAssignmentMatrixCourse>(
                data: course,
                feedback: Material(
                  color: Colors.transparent,
                  child: _UnassignedCourseTile(course: course),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: Text(
                    _unassignedCellLabel(course),
                    style: TextStyle(
                      color: context.appColors.warning,
                      fontSize: 12,
                    ),
                  ),
                ),
                child: Text(
                  _unassignedCellLabel(course),
                  style: TextStyle(
                    color: context.appColors.warning,
                    fontSize: 12,
                  ),
                ),
              );

          final hasAssignments = assignmentSpans.isNotEmpty;
          final hasUnassigned = cell.remainingCourses.isNotEmpty;
          final Widget? assignedContent = hasAssignments
              ? Text.rich(
                  TextSpan(children: assignmentSpans),
                  key: ValueKey(
                    'assignment-cell-content-${item.id}-${subject.id}',
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                )
              : null;
          final Widget? unassignedContent = !hasUnassigned
              ? null
              : cell.remainingCourses.length == 1
              ? unassignedCourse(cell.remainingCourses.single)
              : SizedBox(
                  width: 112,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, course)
                            in cell.remainingCourses.indexed) ...[
                          if (index > 0) const SizedBox(width: 4),
                          unassignedCourse(course),
                        ],
                      ],
                    ),
                  ),
                );
          final cellContent = !hasAssignments && !hasUnassigned
              ? Center(
                  child: Text(
                    '—',
                    style: TextStyle(
                      color: context.appColors.muted.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : Tooltip(
                  message: tooltipEntries.join(' '),
                  child: SizedBox.expand(
                    child: hasAssignments && hasUnassigned
                        ? Row(
                            children: [
                              Expanded(child: assignedContent!),
                              const SizedBox(width: 4),
                              unassignedContent!,
                            ],
                          )
                        : Center(
                            child: hasAssignments
                                ? assignedContent!
                                : unassignedContent!,
                          ),
                  ),
                );
          final isHoveredCell =
              _hoveredCell == (rowIndex: rowIndex, columnIndex: columnIndex);
          final backgroundColor = isHoveredCell
              ? context.appColors.selectedBlue
              : context.appColors.surface;
          return SizedBox(
            width: classColumnWidth,
            child: MouseRegion(
              onEnter: (_) => _setHoveredCell(rowIndex, columnIndex),
              onExit: (_) => _clearHoveredCell(rowIndex, columnIndex),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    key: ValueKey(
                      'assignment-cell-background-${item.id}-${subject.id}',
                    ),
                    color: backgroundColor,
                  ),
                  Positioned.fill(
                    child: canEditAssignments
                        ? _AssignmentEditorPopover(
                            key: ValueKey(
                              'assignment-cell-${item.id}-${subject.id}',
                            ),
                            title: _assignmentEditorTitle(
                              item.name,
                              subject.name,
                              cell.requirements,
                            ),
                            teachers: widget.teachers,
                            current: cell.assignments,
                            requirements: cell.requirements,
                            onSave: (next) => widget.onSaveAssignments(
                              item.id,
                              subject.id,
                              next,
                            ),
                            child: SizedBox.expand(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: cellContent,
                              ),
                            ),
                          )
                        : SizedBox.expand(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: cellContent,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        }

        final subjectHeader = SizedBox(
          width: _subjectColumnWidth,
          height: 40,
          child: AppDataTableHeader(
            height: 40,
            textColor: context.appColors.muted,
            backgroundColor: context.appColors.surface,
            textStyle: AppTheme.matrixHeaderTextStyle(context),
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(
                width: _subjectColumnWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Text('科目'),
                ),
              ),
            ],
          ),
        );
        final classHeader = SizedBox(
          height: 40,
          child: AppDataTableHeader(
            height: 40,
            textColor: context.appColors.muted,
            backgroundColor: context.appColors.surface,
            textStyle: AppTheme.matrixHeaderTextStyle(context),
            padding: EdgeInsets.zero,
            children: [
              Expanded(
                child: _SynchronizedHorizontalList(
                  key: const ValueKey('teacher-class-header-list'),
                  scrollKey: const ValueKey('teacher-class-matrix-scroll'),
                  sync: _horizontalScrollSync,
                  itemCount: classes.length,
                  itemExtent: classColumnWidth,
                  itemBuilder: (context, columnIndex) => ColoredBox(
                    key: ValueKey(
                      'teacher-class-header-${classes[columnIndex].id}',
                    ),
                    color: context.appColors.surface,
                    child: Center(
                      child: Text(
                        classes[columnIndex].name,
                        style: AppTheme.matrixHeaderTextStyle(context).copyWith(
                          color: AppTheme.stageAccent(
                            context,
                            stageIndexById[classes[columnIndex].stageId] ?? 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        final subjectRows = Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: ListView.builder(
              key: const ValueKey('teacher-class-matrix-subject-rows'),
              controller: _subjectScrollController,
              itemExtent: _rowHeight,
              itemCount: subjects.length,
              itemBuilder: (context, index) => subjectRow(index),
            ),
          ),
        );
        final classRows = Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: ListView.builder(
              key: const ValueKey('teacher-class-matrix-rows'),
              controller: _classScrollController,
              itemExtent: _rowHeight,
              itemCount: subjects.length,
              itemBuilder: (context, rowIndex) {
                final subject = subjects[rowIndex];
                return SizedBox(
                  height: _rowHeight,
                  child: _SynchronizedHorizontalList(
                    key: ValueKey('teacher-class-row-${subject.id}'),
                    sync: _horizontalScrollSync,
                    itemCount: classes.length,
                    itemExtent: classColumnWidth,
                    itemBuilder: (context, columnIndex) => assignmentCell(
                      classes[columnIndex],
                      subject,
                      rowIndex,
                      columnIndex,
                    ),
                  ),
                );
              },
            ),
          ),
        );

        return DecoratedBox(
          key: const ValueKey('teacher-class-matrix-border'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: context.appColors.border),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _subjectColumnWidth,
                      child: Column(children: [subjectHeader, subjectRows]),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [classHeader, classRows],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  key: const ValueKey('teacher-class-matrix-header-divider'),
                  top: 40,
                  left: 0,
                  right: 0,
                  height: 1,
                  child: IgnorePointer(
                    child: ColoredBox(color: context.appColors.border),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<WeekMode> _subjectWeekModes(
    TeacherAssignmentMatrixData data,
    List<ClassBrief> classes,
    Subject subject,
  ) {
    final modes = <WeekMode>{
      for (final item in classes)
        for (final requirement
            in data
                .cellFor(classId: item.id, subjectId: subject.id)
                .requirements)
          if (requirement.lessonCount > 0) requirement.weekMode,
    };
    return [
      for (final mode in modes)
        if (mode != WeekMode.weekly) mode,
    ];
  }

  String _assignmentLabel(
    TeacherAssignment assignment,
    Map<String, Teacher> teachersById,
  ) {
    final teacher = teachersById[assignment.teacherId];
    return '${teacher?.displayName ?? '未分配'}${_compactLessonCount(assignment.weekMode, assignment.lessonCount)}';
  }

  TextSpan _assignmentSpan(
    TeacherAssignment assignment,
    Map<String, Teacher> teachersById,
  ) {
    final teacher = teachersById[assignment.teacherId];
    return TextSpan(
      text: _assignmentLabel(assignment, teachersById),
      style: TextStyle(
        color: teacher == null
            ? context.appColors.warning
            : context.appColors.ink,
        fontSize: 12,
      ),
    );
  }
}

class _HorizontalScrollSync {
  final _listeners = <ScrollController, VoidCallback>{};
  double _offset = 0;
  bool _syncing = false;

  double get offset => _offset;

  void attach(ScrollController controller) {
    void listener() => _syncFrom(controller);

    _listeners[controller] = listener;
    controller.addListener(listener);
  }

  void detach(ScrollController controller) {
    final listener = _listeners.remove(controller);
    if (listener != null) controller.removeListener(listener);
  }

  void _syncFrom(ScrollController source) {
    if (_syncing || !source.hasClients) return;
    _offset = source.position.pixels;
    _syncing = true;
    try {
      for (final target in _listeners.keys.toList()) {
        if (target == source || !target.hasClients) continue;
        final position = target.position;
        final offset = _offset.clamp(0.0, position.maxScrollExtent).toDouble();
        if ((position.pixels - offset).abs() > 0.5) target.jumpTo(offset);
      }
    } finally {
      _syncing = false;
    }
  }

  void dispose() {
    for (final entry in _listeners.entries) {
      entry.key.removeListener(entry.value);
    }
    _listeners.clear();
  }
}

class _SynchronizedHorizontalList extends StatefulWidget {
  const _SynchronizedHorizontalList({
    super.key,
    this.scrollKey,
    required this.sync,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
  });

  final Key? scrollKey;
  final _HorizontalScrollSync sync;
  final int itemCount;
  final double itemExtent;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_SynchronizedHorizontalList> createState() =>
      _SynchronizedHorizontalListState();
}

class _SynchronizedHorizontalListState
    extends State<_SynchronizedHorizontalList> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: widget.sync.offset,
      keepScrollOffset: false,
    );
    widget.sync.attach(_controller);
  }

  @override
  void didUpdateWidget(covariant _SynchronizedHorizontalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sync != widget.sync) {
      oldWidget.sync.detach(_controller);
      widget.sync.attach(_controller);
    }
  }

  @override
  void dispose() {
    widget.sync.detach(_controller);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: ListView.builder(
      key: widget.scrollKey,
      controller: _controller,
      scrollDirection: Axis.horizontal,
      itemCount: widget.itemCount,
      itemExtent: widget.itemExtent,
      addAutomaticKeepAlives: false,
      itemBuilder: widget.itemBuilder,
    ),
  );
}

class _SubjectWeekModeTag extends StatelessWidget {
  const _SubjectWeekModeTag({required this.mode});

  final WeekMode mode;

  @override
  Widget build(BuildContext context) {
    final isEven = mode == WeekMode.even;
    final color = isEven
        ? context.appColors.success
        : context.appColors.warning;
    final backgroundColor = isEven
        ? context.appColors.successSurface
        : context.appColors.warningSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          mode.label,
          style: TextStyle(color: color, fontSize: 10, height: 1.3),
        ),
      ),
    );
  }
}

String _compactLessonCount(WeekMode mode, int count) {
  final prefix = switch (mode) {
    WeekMode.weekly => '',
    WeekMode.odd => '单.',
    WeekMode.even => '双.',
  };
  return '($prefix$count)';
}

String _unassignedCellLabel(TeacherAssignmentMatrixCourse course) =>
    '未分配${_compactLessonCount(course.weekMode, course.remainingLessons)}';

String _unassignedLabel(TeacherAssignmentMatrixCourse course) {
  final weekMode = course.weekMode == WeekMode.weekly
      ? ''
      : '（${course.weekMode.label}）';
  return '${course.className} · ${course.subjectName}$weekMode · ${course.remainingLessons} 节';
}
