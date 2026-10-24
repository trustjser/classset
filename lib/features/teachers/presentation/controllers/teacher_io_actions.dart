part of '../teachers_page.dart';

extension _TeacherIoActions on _TeachersPageState {
  Future<void> _importTeachers() async {
    final upload = await _showTeacherImportDialog(
      context,
      onDownloadTemplate: _downloadTeacherImportTemplate,
    );
    if (upload != true || !mounted) return;
    await _selectAndImportTeachers();
  }

  Future<void> _downloadTeacherImportTemplate(bool includeExisting) async {
    final location = await getSaveLocation(
      suggestedName: '教师导入模板.xlsx',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
      ],
    );
    if (location == null) return;
    final file = XFile.fromData(
      Uint8List.fromList(
        buildTeachersWorkbook(
          includeExisting
              ? [
                  for (final teacher
                      in ref
                              .read(teachersProvider(widget.termId))
                              .valueOrNull ??
                          const <Teacher>[])
                    TeacherWorkbookRow(
                      name: teacher.name,
                      shortName: teacher.shortName,
                    ),
                ]
              : const [],
        ),
      ),
      name: '教师导入模板.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    await file.saveTo(location.path);
    if (mounted) _showMessage('教师导入模板已下载');
  }

  Future<void> _selectAndImportTeachers() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
      ],
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final result = parseTeachersWorkbook(bytes);
    if (result.errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errors.map((error) => '$error').join('；')),
        ),
      );
      return;
    }
    final current =
        ref.read(teachersProvider(widget.termId)).valueOrNull ?? const [];
    final plan = await _showTeacherImportPreview(
      context,
      rows: result.rows,
      teachers: current,
    );
    if (plan == null) return;
    var newTeacherOrder = current.length;
    try {
      await _repository.saveTeachers([
        for (final item in plan)
          if (item.teacherId != null)
            current
                .firstWhere((teacher) => teacher.id == item.teacherId)
                .copyWith(name: item.row.name, shortName: item.row.shortName)
          else
            Teacher(
              id: _id('teacher'),
              name: item.row.name,
              shortName: item.row.shortName,
              displayQualifier: item.displayQualifier,
              sortOrder: newTeacherOrder++,
            ),
      ]);
    } catch (error) {
      if (mounted) _showMessage('导入教师失败：$error');
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 ${result.rows.length} 名教师')));
    }
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

  Future<void> _importGroups() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
      ],
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final result = parseTeacherGroupsWorkbook(bytes);
    if (result.errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errors.map((error) => '$error').join('；')),
        ),
      );
      return;
    }
    final teachers =
        ref.read(teachersProvider(widget.termId)).valueOrNull ?? const [];
    final teachersByName = <String, List<Teacher>>{};
    for (final teacher in teachers) {
      teachersByName.putIfAbsent(teacher.name, () => []).add(teacher);
    }
    final existing =
        ref.read(teacherGroupsProvider(widget.termId)).valueOrNull ?? const [];
    final groups = <TeacherGroup>[];
    final members = <TeacherGroupMember>[];
    final memberErrors = <String>[];
    for (var index = 0; index < result.rows.length; index++) {
      final row = result.rows[index];
      final group = TeacherGroup(
        id: _id('group'),
        termId: widget.termId,
        name: row.name,
        description: row.description.isEmpty ? null : row.description,
        sortOrder: existing.length + index,
      );
      groups.add(group);
      for (final name in row.memberNames) {
        final candidates = teachersByName[name] ?? const <Teacher>[];
        if (candidates.length != 1) {
          memberErrors.add(
            '第 ${index + 2} 行成员「$name」${candidates.isEmpty ? '不存在' : '姓名重复'}，请先在教师视角手动核对。',
          );
          continue;
        }
        members.add(
          TeacherGroupMember(
            id: '${group.id}:${candidates.single.id}',
            groupId: group.id,
            teacherId: candidates.single.id,
          ),
        );
      }
    }
    if (memberErrors.isNotEmpty) {
      _showMessage(memberErrors.join('；'));
      return;
    }
    await _repository.saveTeacherGroupsWithMembers(
      groups: groups,
      members: members,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 ${result.rows.length} 个分组')));
    }
  }

  Future<void> _exportGroups() async {
    final groups =
        ref.read(teacherGroupsProvider(widget.termId)).valueOrNull ?? const [];
    final teachers =
        ref.read(teachersProvider(widget.termId)).valueOrNull ?? const [];
    final members =
        ref.read(teacherGroupMembersProvider(widget.termId)).valueOrNull ??
        const [];
    final names = {for (final teacher in teachers) teacher.id: teacher.name};
    final location = await getSaveLocation(
      suggestedName: '教师分组.xlsx',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
      ],
    );
    if (location == null) return;
    final file = XFile.fromData(
      Uint8List.fromList(
        buildTeacherGroupsWorkbook([
          for (final group in groups)
            TeacherGroupWorkbookRow(
              name: group.name,
              description: group.description ?? '',
              memberNames: [
                for (final member in members.where(
                  (row) => row.groupId == group.id,
                ))
                  if (names[member.teacherId] != null) names[member.teacherId]!,
              ],
            ),
        ]),
      ),
      name: '教师分组.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    await file.saveTo(location.path);
  }
}
