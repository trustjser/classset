part of '../teachers_page.dart';

Future<(String, String, String?, Set<String>)?> _showTeacherEditor(
  BuildContext context,
  List<Subject> subjects, {
  Teacher? initial,
}) => showAppDialog<(String, String, String?, Set<String>)>(
  context: context,
  builder: (context) =>
      _TeacherEditorDialog(subjects: subjects, initial: initial),
);

class _TeacherEditorDialog extends StatefulWidget {
  const _TeacherEditorDialog({required this.subjects, this.initial});
  final List<Subject> subjects;
  final Teacher? initial;
  @override
  State<_TeacherEditorDialog> createState() => _TeacherEditorDialogState();
}

class _TeacherEditorDialogState extends State<_TeacherEditorDialog> {
  late final name = TextEditingController(text: widget.initial?.name ?? '');
  late final short = TextEditingController(
    text: widget.initial?.shortName ?? '',
  );
  late final qualifier = TextEditingController(
    text: widget.initial?.displayQualifier ?? '',
  );
  late final selectedSubjects = {...?widget.initial?.subjectIds};
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    name.dispose();
    short.dispose();
    qualifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: Text(widget.initial == null ? '新增教师' : '编辑教师'),
      maxWidth: 600,
      content: SizedBox(
        width: 552,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final nameField = _TeacherFormField(
                    label: '姓名',
                    isRequired: true,
                    child: AppTextFormField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: '例如：王建国'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请输入教师姓名'
                          : null,
                    ),
                  );
                  final shortField = _TeacherFormField(
                    label: '简称',
                    child: AppTextFormField(
                      controller: short,
                      decoration: const InputDecoration(hintText: '例如：王老师'),
                    ),
                  );
                  if (constraints.maxWidth < 420) {
                    return Column(
                      children: [
                        nameField,
                        const SizedBox(height: 20),
                        shortField,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: nameField),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: shortField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              _TeacherFormField(
                label: '显示限定词',
                help: '选填，用于区分同名教师。',
                child: AppTextFormField(
                  controller: qualifier,
                  decoration: const InputDecoration(hintText: '例如：小学部、初中部'),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 20),
              _TeacherSubjectPicker(
                subjects: widget.subjects,
                selected: selectedSubjects,
                onChanged: (id, checked) => setState(() {
                  if (checked) {
                    selectedSubjects.add(id);
                  } else {
                    selectedSubjects.remove(id);
                  }
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppPrimaryButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              name.text.trim(),
              short.text.trim(),
              qualifier.text.trim().isEmpty ? null : qualifier.text.trim(),
              {...selectedSubjects},
            ));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

const _createTeacherChoice = '__create_teacher__';

class _TeacherImportPlanItem {
  const _TeacherImportPlanItem({
    required this.row,
    required this.teacherId,
    required this.displayQualifier,
  });

  final TeacherWorkbookRow row;
  final String? teacherId;
  final String? displayQualifier;
}

class _TeacherImportDraft {
  _TeacherImportDraft({
    required this.row,
    required this.candidates,
    required this.duplicateName,
    required this.choice,
  });

  final TeacherWorkbookRow row;
  final List<Teacher> candidates;
  final bool duplicateName;
  final TextEditingController qualifier = TextEditingController();
  String choice;

  bool get asksForQualifier =>
      choice == _createTeacherChoice &&
      (duplicateName || candidates.isNotEmpty);

  void dispose() => qualifier.dispose();
}

Future<List<_TeacherImportPlanItem>?> _showTeacherImportPreview(
  BuildContext context, {
  required List<TeacherWorkbookRow> rows,
  required List<Teacher> teachers,
}) async {
  final nameCounts = <String, int>{};
  for (final row in rows) {
    final key = row.name.trim().toLowerCase();
    nameCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
  }
  final drafts = [
    for (final row in rows)
      () {
        final candidates = teachers
            .where(
              (teacher) =>
                  teacher.name.toLowerCase() == row.name.toLowerCase() ||
                  (row.shortName.isNotEmpty &&
                      teacher.shortName.toLowerCase() ==
                          row.shortName.toLowerCase()),
            )
            .toList();
        return _TeacherImportDraft(
          row: row,
          candidates: candidates,
          duplicateName: nameCounts[row.name.trim().toLowerCase()]! > 1,
          choice: candidates.isEmpty ? _createTeacherChoice : '',
        );
      }(),
  ];

  bool canSave() {
    if (drafts.any((draft) => draft.choice.isEmpty)) return false;
    final existingIds = drafts
        .where((draft) => draft.choice != _createTeacherChoice)
        .map((draft) => draft.choice)
        .toList();
    if (existingIds.toSet().length != existingIds.length) return false;
    for (final draft in drafts.where((draft) => draft.asksForQualifier)) {
      if (draft.qualifier.text.trim().isEmpty) return false;
    }
    final newIdentityKeys = drafts
        .where((draft) => draft.choice == _createTeacherChoice)
        .map(
          (draft) =>
              '${draft.row.name.toLowerCase()}|${draft.qualifier.text.trim().toLowerCase()}',
        )
        .toList();
    return newIdentityKeys.toSet().length == newIdentityKeys.length;
  }

  final plan = await showAppDialog<List<_TeacherImportPlanItem>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AppDialog(
        title: const Text('导入教师 · 核对身份'),
        maxWidth: 760,
        content: SizedBox(
          width: 680,
          height: 540,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '表格只提供姓名和简称。请选择匹配已有教师，或明确新建；重名的新教师需要填写显示区分名。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: drafts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final draft = drafts[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${draft.row.name} · ${draft.row.shortName}'),
                          const SizedBox(height: 8),
                          AppSelectField<String>(
                            value: draft.choice,
                            label: '导入方式',
                            items: {
                              if (draft.choice.isEmpty) '请选择新建或匹配身份': '',
                              '新建教师': _createTeacherChoice,
                              for (final teacher in draft.candidates)
                                '匹配 ${teacher.displayName} · ${teacher.shortName} · ${teacher.id}':
                                    teacher.id,
                            },
                            onChanged: (choice) => setState(
                              () => draft.choice = choice ?? draft.choice,
                            ),
                          ),
                          if (draft.asksForQualifier)
                            AppTextFormField(
                              controller: draft.qualifier,
                              decoration: const InputDecoration(
                                labelText: '显示区分名 *',
                                hintText: '例如：小学部、初中部',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          AppPrimaryButton(
            onPressed: canSave()
                ? () => Navigator.pop(context, [
                    for (final draft in drafts)
                      _TeacherImportPlanItem(
                        row: draft.row,
                        teacherId: draft.choice == _createTeacherChoice
                            ? null
                            : draft.choice,
                        displayQualifier: draft.asksForQualifier
                            ? draft.qualifier.text.trim()
                            : null,
                      ),
                  ])
                : null,
            child: Text('导入 ${rows.length} 行'),
          ),
        ],
      ),
    ),
  );
  for (final draft in drafts) {
    draft.dispose();
  }
  return plan;
}
