part of '../teachers_page.dart';

extension _TeacherCrudActions on _TeachersPageState {
  Future<void> _addTeacher() async {
    final subjects = ref.read(subjectsProvider).valueOrNull ?? const [];
    final value = await _showTeacherEditor(context, subjects);
    if (value == null) return;
    await _repository.saveTeachers([
      Teacher(
        id: _id('teacher'),
        name: value.$1,
        shortName: value.$2,
        displayQualifier: value.$3,
        sortOrder:
            (ref.read(teachersProvider(widget.termId)).valueOrNull ?? const [])
                .length,
        subjectIds: value.$4,
      ),
    ]);
  }

  Future<void> _editTeacher(Teacher teacher) async {
    final subjects = ref.read(subjectsProvider).valueOrNull ?? const [];
    final value = await _showTeacherEditor(context, subjects, initial: teacher);
    if (value == null) return;
    await _repository.saveTeachers([
      teacher.copyWith(
        name: value.$1,
        shortName: value.$2,
        displayQualifier: value.$3,
        clearDisplayQualifier: value.$3 == null,
        subjectIds: value.$4,
      ),
    ]);
  }

  Future<void> _addGroup() async {
    final value = await _showGroupEditor(context);
    if (value == null) return;
    await _repository.saveTeacherGroup(
      TeacherGroup(
        id: _id('group'),
        termId: widget.termId,
        name: value.$1,
        description: value.$2,
        sortOrder:
            (ref.read(teacherGroupsProvider(widget.termId)).valueOrNull ??
                    const [])
                .length,
      ),
    );
  }

  Future<void> _confirmDeleteTeacher(Teacher teacher) async {
    final assignments =
        (ref.read(teacherAssignmentsProvider(widget.termId)).valueOrNull ??
                const [])
            .where((row) => row.teacherId == teacher.id)
            .toList();
    final lessons = assignments.fold<int>(
      0,
      (total, row) => total + row.lessonCount,
    );
    final assignmentCount = await _repository.countTeacherAssignments(
      teacher.id,
    );
    if (!mounted) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text('删除${teacher.displayName}？'),
        content: Text(
          assignmentCount == 0
              ? '删除后无法撤销。'
              : '该教师在所有学期共有 $assignmentCount 条任课记录（当前学期 $lessons 节）。删除后全部退回未分配课程池。',
        ),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          AppDestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除教师'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _repository.deleteTeacher(teacher.id);
  }

  Future<void> _confirmDeleteGroup(TeacherGroup group) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text('删除「${group.name}」？'),
        content: const Text('会同时删除分组成员和分组预排规则。'),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          AppDestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除分组'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _repository.deleteTeacherGroup(group.id);
  }

  void _showMessage(String? message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message ?? '操作失败')));
  }

  Future<void> _editMembers(TeacherGroup group) async {
    final teachers =
        ref.read(teachersProvider(widget.termId)).valueOrNull ?? const [];
    final members =
        ref.read(teacherGroupMembersProvider(widget.termId)).valueOrNull ??
        const [];
    final selected = members
        .where((row) => row.groupId == group.id)
        .map((row) => row.teacherId)
        .toSet();
    final everGrouped = members.map((row) => row.teacherId).toSet();
    final neverGrouped = teachers
        .where((teacher) => !everGrouped.contains(teacher.id))
        .map((teacher) => teacher.id)
        .toSet();
    final next = await _showMemberEditor(
      context,
      group.name,
      teachers,
      selected,
      neverGrouped,
    );
    if (next == null) return;
    try {
      await _repository.replaceTeacherGroupMembers(
        groupId: group.id,
        members: next
            .map(
              (id) => TeacherGroupMember(
                id: _id('member'),
                groupId: group.id,
                teacherId: id,
              ),
            )
            .toList(),
      );
      ref.invalidate(teacherGroupMembersProvider(widget.termId));
      await ref.read(teacherGroupMembersProvider(widget.termId).future);
    } catch (error) {
      _showMessage('保存分组成员失败：$error');
    }
  }
}
