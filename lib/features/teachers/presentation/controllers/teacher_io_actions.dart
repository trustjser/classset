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

  Future<void> _downloadTeacherImportTemplate() async {
    final location = await getSaveLocation(
      suggestedName: '教师导入模板.xlsx',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
      ],
    );
    if (location == null) return;
    final file = XFile.fromData(
      Uint8List.fromList(buildTeachersWorkbook(const [])),
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

  Future<void> _exportTeachers() async {
    final teachers =
        ref.read(teachersProvider(widget.termId)).valueOrNull ?? const [];
    final location = await getSaveLocation(
      suggestedName: '教师任课.xlsx',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel 工作簿', extensions: ['xlsx']),
      ],
    );
    if (location == null) return;
    final file = XFile.fromData(
      Uint8List.fromList(
        buildTeachersWorkbook([
          for (final teacher in teachers)
            TeacherWorkbookRow(
              name: teacher.name,
              shortName: teacher.shortName,
            ),
        ]),
      ),
      name: '教师任课.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    await file.saveTo(location.path);
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
