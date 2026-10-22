part of '../teachers_page.dart';

class _TeacherAssignmentOverview extends StatelessWidget {
  const _TeacherAssignmentOverview({
    required this.classes,
    required this.subjects,
    required this.requirements,
    required this.assignments,
    required this.viewSwitcher,
    required this.teacherTable,
    required this.onReturnAssignment,
  });

  final List<ClassBrief> classes;
  final List<Subject> subjects;
  final List<SubjectRequirement> requirements;
  final List<TeacherAssignment> assignments;
  final Widget viewSwitcher;
  final Widget teacherTable;
  final Future<void> Function(TeacherAssignment assignment, String teacherId)
  onReturnAssignment;

  @override
  Widget build(BuildContext context) {
    final courses = TeacherAssignmentMatrixData.build(
      classes: classes,
      subjects: subjects,
      requirements: requirements,
      assignments: assignments,
    ).unassignedCourses;
    final unassignedPanel = _UnassignedCoursePanel(
      courses: courses,
      onReturnAssignment: (assignment) => onReturnAssignment(assignment, ''),
    );
    final viewSwitcherPanel = _teacherViewSwitcherPanel(viewSwitcher);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1000) {
          return Column(
            children: [
              viewSwitcherPanel,
              const SizedBox(height: 8),
              Expanded(child: teacherTable),
              const SizedBox(height: 8),
              SizedBox(height: 230, child: unassignedPanel),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 296,
              child: Column(
                children: [
                  viewSwitcherPanel,
                  const SizedBox(height: 8),
                  Expanded(child: unassignedPanel),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: teacherTable),
          ],
        );
      },
    );
  }
}
