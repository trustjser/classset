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

class _TeacherImportActionCard extends StatelessWidget {
  const _TeacherImportActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) => AppSurface(
    backgroundColor: context.appColors.canvas,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.appColors.selectedBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: context.appColors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              action,
            ],
          ),
        ],
      ),
    ),
  );
}
