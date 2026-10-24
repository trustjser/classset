part of '../teachers_page.dart';

extension _TeacherAssignmentActions on _TeachersPageState {
  Future<bool> _saveAssignments(
    String classId,
    String subjectId,
    List<TeacherAssignment> next,
  ) async {
    try {
      await _repository.replaceTeacherAssignments(
        termId: widget.termId,
        classId: classId,
        subjectId: subjectId,
        assignments: next
            .map(
              (row) => TeacherAssignment(
                id: row.id,
                termId: widget.termId,
                teacherId: row.teacherId,
                classId: classId,
                subjectId: subjectId,
                weekMode: row.weekMode,
                lessonCount: row.lessonCount,
                sortOrder: row.sortOrder,
              ),
            )
            .toList(),
      );
      return true;
    } on StateError catch (error) {
      _showMessage(error.message);
      return false;
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? '任课信息无效');
      return false;
    }
  }

  Future<void> _addBatchAssignments({Teacher? teacher}) async {
    final teachers =
        ref.read(teachersProvider(widget.termId)).valueOrNull ?? const [];
    final classes =
        ref.read(classesForTermProvider(widget.termId)).valueOrNull ?? const [];
    final subjects =
        ref.read(subjectsForTermProvider(widget.termId)).valueOrNull ??
        const [];
    if (teachers.isEmpty || classes.isEmpty || subjects.isEmpty) {
      _showMessage('请先添加教师、班级和科目');
      return;
    }
    final allRequirements =
        ref.read(allRequirementsProvider).valueOrNull ??
        await ref.read(allRequirementsProvider.future) ??
        const <SubjectRequirement>[];
    final subjectIdsByClass = <String, Set<String>>{};
    for (final schoolClass in classes) {
      final eligibleSubjectIds = <String>{};
      for (final subject in subjects) {
        final requirements = _effectiveTeacherAssignmentRequirements(
          allRequirements,
          classId: schoolClass.id,
          gradeId: schoolClass.gradeId,
          subjectId: subject.id,
        );
        if (requirements.any((requirement) => requirement.lessonCount > 0)) {
          eligibleSubjectIds.add(subject.id);
        }
      }
      if (eligibleSubjectIds.isNotEmpty) {
        subjectIdsByClass[schoolClass.id] = eligibleSubjectIds;
      }
    }
    final eligibleClasses = classes
        .where((item) => subjectIdsByClass.containsKey(item.id))
        .toList();
    if (eligibleClasses.isEmpty) {
      _showMessage('请先设置科目节数需求，再添加任课');
      return;
    }
    final grades = await ref.read(gradesForTermProvider(widget.termId).future);
    final stages = await ref.read(stagesProvider(widget.termId).future);
    final assignmentsBeforeDialog =
        ref.read(teacherAssignmentsProvider(widget.termId)).valueOrNull ??
        const <TeacherAssignment>[];
    if (!mounted) return;
    final selection = await _showBatchAssignmentEditor(
      context,
      teachers: teachers,
      classes: eligibleClasses,
      subjects: subjects,
      subjectIdsByClass: subjectIdsByClass,
      gradeNames: {for (final grade in grades) grade.id: grade.name},
      stageNames: {for (final stage in stages) stage.id: stage.name},
      requirements: allRequirements,
      existingAssignments: assignmentsBeforeDialog,
      initialTeacher: teacher,
    );
    if (selection == null) return;
    final current =
        (ref.read(teacherAssignmentsProvider(widget.termId)).valueOrNull ??
                const [])
            .toList();
    final targetTeacherId = selection.teacherId;
    if (targetTeacherId == null || targetTeacherId.isEmpty) return;
    try {
      await _repository.addTeacherAssignments(
        termId: widget.termId,
        assignments: [
          for (var index = 0; index < selection.assignments.length; index++)
            TeacherAssignment(
              id: _id('assignment'),
              termId: widget.termId,
              teacherId: targetTeacherId,
              classId: selection.assignments[index].classId,
              subjectId: selection.assignments[index].subjectId,
              weekMode: selection.assignments[index].weekMode,
              lessonCount: selection.assignments[index].lessonCount,
              sortOrder: current.length + index,
            ),
        ],
      );
      if (mounted) _showMessage('已添加 ${selection.assignments.length} 项任课');
    } on StateError catch (error) {
      _showMessage(error.message);
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? '任课信息无效');
    }
  }

  Future<void> _deleteTeacherAssignments(
    Teacher teacher,
    List<TeacherAssignment> assignments,
  ) async {
    if (assignments.isEmpty) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text('删除${teacher.displayName}的任课？'),
        content: Text('将删除当前学期的 ${assignments.length} 条任课分配。'),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          AppDestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除任课'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteTeacherAssignments(
        termId: widget.termId,
        assignmentIds: assignments.map((row) => row.id).toList(),
      );
    } on StateError catch (error) {
      _showMessage(error.message);
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? '任课信息无效');
    }
  }

  Future<void> _transferAssignment(
    TeacherAssignment assignment,
    String teacherId,
  ) async {
    final rows =
        (ref.read(teacherAssignmentsProvider(widget.termId)).valueOrNull ??
                const [])
            .where(
              (row) =>
                  row.classId == assignment.classId &&
                  row.subjectId == assignment.subjectId &&
                  row.teacherId.isNotEmpty &&
                  (row.id != assignment.id || teacherId.isNotEmpty),
            )
            .map(
              (row) => row.id == assignment.id
                  ? row.copyWith(teacherId: teacherId)
                  : row,
            )
            .toList();
    try {
      await _repository.replaceTeacherAssignments(
        termId: widget.termId,
        classId: assignment.classId,
        subjectId: assignment.subjectId,
        assignments: rows,
      );
    } on StateError catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _combineAssignments(
    Teacher teacher,
    List<TeacherAssignment> assignments,
  ) async {
    final classList =
        ref.read(classesForTermProvider(widget.termId)).valueOrNull ?? const [];
    final classById = {for (final item in classList) item.id: item};
    final subjects =
        ref.read(subjectsForTermProvider(widget.termId)).valueOrNull ??
        const [];
    final subjectNames = {
      for (final subject in subjects) subject.id: subject.name,
    };
    final selected = await _showCombinedAssignmentDialog(
      context,
      assignments: assignments,
      classById: classById,
      subjectNames: subjectNames,
    );
    if (selected == null || selected.length < 2 || !mounted) return;
    try {
      await _repository.combineTeacherAssignments(
        termId: widget.termId,
        assignmentIds: selected.map((row) => row.id).toList(),
        combinedGroupId: _id('combined'),
      );
    } on StateError catch (error) {
      _showMessage(error.message.toString());
      return;
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? '合班信息无效');
      return;
    }
    if (mounted) _showMessage('已将 ${selected.length} 个班级合班');
  }

  Future<void> _separateCombinedGroup(String groupId) async {
    try {
      await _repository.separateTeacherAssignments(
        termId: widget.termId,
        combinedGroupId: groupId,
      );
    } on StateError catch (error) {
      _showMessage(error.message.toString());
      return;
    }
    if (mounted) _showMessage('已拆分合班');
  }

  Future<void> _assignUnassigned(
    Teacher teacher,
    TeacherAssignmentMatrixCourse course,
  ) async {
    final current =
        (ref.read(teacherAssignmentsProvider(widget.termId)).valueOrNull ??
                const [])
            .where(
              (row) =>
                  row.classId == course.classId &&
                  row.subjectId == course.subjectId &&
                  row.teacherId.isNotEmpty,
            )
            .toList();
    try {
      final next = course.existingAssignmentId == null
          ? [
              ...current,
              TeacherAssignment(
                id: _id('assignment'),
                termId: widget.termId,
                teacherId: teacher.id,
                classId: course.classId,
                subjectId: course.subjectId,
                weekMode: course.weekMode,
                lessonCount: course.remainingLessons,
                sortOrder: current.length,
              ),
            ]
          : [
              for (final row in current)
                row.id == course.existingAssignmentId
                    ? row.copyWith(teacherId: teacher.id)
                    : row,
            ];
      await _repository.replaceTeacherAssignments(
        termId: widget.termId,
        classId: course.classId,
        subjectId: course.subjectId,
        assignments: next,
      );
    } on StateError catch (error) {
      _showMessage(error.message);
    }
  }
}

List<SubjectRequirement> _effectiveTeacherAssignmentRequirements(
  List<SubjectRequirement> requirements, {
  required String classId,
  required String gradeId,
  required String subjectId,
}) {
  final classRequirements = requirements
      .where(
        (requirement) =>
            requirement.subjectId == subjectId &&
            requirement.classId == classId,
      )
      .toList();
  if (classRequirements.isNotEmpty) return classRequirements;
  return requirements
      .where(
        (requirement) =>
            requirement.subjectId == subjectId &&
            requirement.gradeId == gradeId &&
            requirement.classId == null,
      )
      .toList();
}
