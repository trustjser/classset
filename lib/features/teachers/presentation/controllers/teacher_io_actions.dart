part of '../teachers_page.dart';

extension _TeacherIoActions on _TeachersPageState {
  Future<void> _importTeachers() async {
    final teachers = await ref.read(teachersProvider(widget.termId).future);
    final subjects = await ref.read(
      subjectsForTermProvider(widget.termId).future,
    );
    final groups = await ref.read(teacherGroupsProvider(widget.termId).future);
    if (!mounted) return;
    final result = await showAppDialog<(List<TeacherImportEntry>, bool)>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TeacherImportDialog(
        teachers: teachers,
        subjects: subjects,
        groups: groups,
        pickFile: ref.read(teacherImportFilePickerProvider),
        download: _downloadTeacherImportTemplate,
      ),
    );
    if (result == null || !mounted) return;
    final (entries, clearEmpty) = result;
    final imported = <Teacher>[];
    final groupsByTeacher = <String, List<String>>{};
    final replaceGroups = <String>{};
    final replaceSubjects = <String>{};
    var order = teachers.length;
    for (final entry in entries.where(
      (item) =>
          item.status == TeacherImportStatus.create ||
          item.status == TeacherImportStatus.update,
    )) {
      final row = entry.row;
      final old = entry.teacher;
      final teacher = old == null
          ? Teacher(
              id: _id('teacher'),
              name: row.name,
              shortName: row.shortName,
              sortOrder: order++,
              subjectIds: entry.subjectIds,
            )
          : old.copyWith(
              shortName: row.shortName.isNotEmpty || clearEmpty
                  ? row.shortName
                  : old.shortName,
              subjectIds: entry.subjectIds,
            );
      imported.add(teacher);
      if (old == null ||
          (row.hasGroups && (row.groups.isNotEmpty || clearEmpty))) {
        groupsByTeacher[teacher.id] = row.groups;
        if (old != null) replaceGroups.add(teacher.id);
      }
      if (old != null &&
          row.hasSubjects &&
          (row.subjects.isNotEmpty || clearEmpty)) {
        replaceSubjects.add(teacher.id);
      }
    }
    try {
      await _repository.importTeachersWithGroups(
        termId: widget.termId,
        teachers: imported,
        groupsByTeacher: groupsByTeacher,
        replaceGroupsForTeachers: replaceGroups,
        replaceSubjectsForTeachers: replaceSubjects,
      );
      if (mounted) _showMessage('已导入 ${imported.length} 名教师');
    } catch (error) {
      if (mounted) _showMessage('导入教师失败：$error');
    }
  }

  Future<void> _downloadTeacherImportTemplate(bool includeExisting) async {
    final location = await getSaveLocation(
      suggestedName: '教师导入模板.xlsx',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
      ],
    );
    if (location == null) return;
    final teachers = await ref.read(teachersProvider(widget.termId).future);
    final subjects = await ref.read(
      subjectsForTermProvider(widget.termId).future,
    );
    final groups = await ref.read(teacherGroupsProvider(widget.termId).future);
    final members = await ref.read(
      teacherGroupMembersProvider(widget.termId).future,
    );
    final groupNames = {for (final group in groups) group.id: group.name};
    final file = XFile.fromData(
      Uint8List.fromList(
        buildTeachersWorkbook(
          includeExisting
              ? [
                  for (final teacher in teachers)
                    TeacherWorkbookRow(
                      name: teacher.name,
                      shortName: teacher.shortName,
                      groups: [
                        for (final member in members.where(
                          (member) => member.teacherId == teacher.id,
                        ))
                          if (groupNames[member.groupId] != null)
                            groupNames[member.groupId]!,
                      ],
                      subjects: [
                        for (final subject in subjects)
                          if (teacher.subjectIds.contains(subject.id))
                            subject.name,
                      ],
                    ),
                ]
              : const [],
          subjectNames: [for (final subject in subjects) subject.name],
        ),
      ),
      name: '教师导入模板.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    await file.saveTo(location.path);
    if (mounted) _showMessage('教师导入模板已下载');
  }

  Future<void> _importAssignments() async {
    final upload = await _showAssignmentImportDialog(
      context,
      onDownloadTemplate: _downloadAssignmentTemplate,
    );
    if (upload != true || !mounted) return;
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
      ],
    );
    if (file == null || !mounted) return;
    final parsed = parseAssignmentWorkbook(await file.readAsBytes());
    if (!mounted) return;
    if (parsed.errors.isNotEmpty) {
      _showMessage(parsed.errors.join('；'));
      return;
    }
    final stages = await ref.read(stagesProvider(widget.termId).future);
    final grades = await ref.read(gradesForTermProvider(widget.termId).future);
    final classes = await ref.read(
      classesForTermProvider(widget.termId).future,
    );
    final subjects = await ref.read(
      subjectsForTermProvider(widget.termId).future,
    );
    final teachers = await ref.read(teachersProvider(widget.termId).future);
    final requirements = await ref.read(allRequirementsProvider.future);
    final existing = await ref.read(
      teacherAssignmentsProvider(widget.termId).future,
    );
    if (!mounted) return;
    final plan = resolveAssignmentWorkbook(
      rows: parsed.rows,
      stages: stages,
      grades: grades,
      classes: classes,
      subjects: subjects,
      teachers: teachers,
      requirements: requirements,
      existingAssignments: existing,
    );
    if (plan.errors.isNotEmpty) {
      _showMessage(plan.errors.join('；'));
      return;
    }
    final confirmed = await _showAssignmentImportPreview(context, plan.rows);
    if (confirmed != true || !mounted) return;
    try {
      await _repository.addTeacherAssignments(
        termId: widget.termId,
        assignments: [
          for (var index = 0; index < plan.rows.length; index++)
            TeacherAssignment(
              id: _id('assignment'),
              termId: widget.termId,
              teacherId: plan.rows[index].teacherId,
              classId: plan.rows[index].classId,
              subjectId: plan.rows[index].subjectId,
              weekMode: plan.rows[index].source.weekMode,
              lessonCount: plan.rows[index].source.lessonCount,
              sortOrder: existing.length + index,
            ),
        ],
      );
      if (mounted) _showMessage('已导入 ${plan.rows.length} 条任课分配');
    } on StateError catch (error) {
      if (mounted) _showMessage('导入任课失败：${error.message}');
    } on ArgumentError catch (error) {
      if (mounted) _showMessage('导入任课失败：${error.message}');
    }
  }

  Future<void> _downloadAssignmentTemplate() async {
    final location = await getSaveLocation(
      suggestedName: '任课分配导入模板.xlsx',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
      ],
    );
    if (location == null) return;
    final stages = await ref.read(stagesProvider(widget.termId).future);
    final grades = await ref.read(gradesForTermProvider(widget.termId).future);
    final classes = await ref.read(
      classesForTermProvider(widget.termId).future,
    );
    final subjects = await ref.read(
      subjectsForTermProvider(widget.termId).future,
    );
    final teachers = await ref.read(teachersProvider(widget.termId).future);
    final requirements = await ref.read(allRequirementsProvider.future);
    final assignments = await ref.read(
      teacherAssignmentsProvider(widget.termId).future,
    );
    if (!mounted) return;
    await XFile.fromData(
      Uint8List.fromList(
        buildAssignmentWorkbook(
          const [],
          stages: stages,
          grades: grades,
          classes: classes,
          subjects: subjects,
          teachers: teachers,
          requirements: requirements,
          existingAssignments: assignments,
        ),
      ),
      name: '任课分配导入模板.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ).saveTo(location.path);
    if (mounted) _showMessage('任课分配导入模板已下载');
  }
}
