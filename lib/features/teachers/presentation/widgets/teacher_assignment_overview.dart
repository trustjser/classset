part of '../teachers_page.dart';

class _TeacherAssignmentOverview extends StatefulWidget {
  const _TeacherAssignmentOverview({
    required this.classes,
    required this.subjects,
    required this.requirements,
    required this.assignments,
    required this.teacherTable,
    required this.onReturnAssignment,
  });

  final List<ClassBrief> classes;
  final List<Subject> subjects;
  final List<SubjectRequirement> requirements;
  final List<TeacherAssignment> assignments;
  final Widget teacherTable;
  final Future<void> Function(TeacherAssignment assignment, String teacherId)
  onReturnAssignment;

  @override
  State<_TeacherAssignmentOverview> createState() =>
      _TeacherAssignmentOverviewState();
}

class _TeacherAssignmentOverviewState
    extends State<_TeacherAssignmentOverview> {
  bool _showUnassignedCourses = true;

  @override
  Widget build(BuildContext context) {
    final courses = TeacherAssignmentMatrixData.build(
      classes: widget.classes,
      subjects: widget.subjects,
      requirements: widget.requirements,
      assignments: widget.assignments,
    ).unassignedCourses;
    final unassignedPanel = _UnassignedCoursePanel(
      courses: courses,
      onReturnAssignment: (assignment) =>
          widget.onReturnAssignment(assignment, ''),
    );
    final toggle = Tooltip(
      message: _showUnassignedCourses ? '收起未分配课程' : '展开未分配课程',
      child: Material(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        child: InkWell(
          key: const ValueKey('teacher-unassigned-toggle'),
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          onTap: () =>
              setState(() => _showUnassignedCourses = !_showUnassignedCourses),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              _showUnassignedCourses
                  ? Icons.chevron_right_rounded
                  : Icons.chevron_left_rounded,
              color: context.appColors.inkSecondary,
              size: 20,
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1000) {
          final panelWidth = (constraints.maxWidth - 48)
              .clamp(0.0, 296.0)
              .toDouble();
          return Stack(
            children: [
              Positioned.fill(right: 40, child: widget.teacherTable),
              if (_showUnassignedCourses)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 40,
                  width: panelWidth,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    child: unassignedPanel,
                  ),
                ),
              Positioned(top: 0, right: 0, child: toggle),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: widget.teacherTable),
            if (_showUnassignedCourses) ...[
              const SizedBox(width: 12),
              SizedBox(width: 296, child: unassignedPanel),
            ],
            toggle,
          ],
        );
      },
    );
  }
}
