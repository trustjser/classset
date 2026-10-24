import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:flutter/material.dart';

/// 常用科目（设计稿「从常用科目快速添加」）。
const commonSubjects = [
  '语文',
  '数学',
  '外语',
  '物理',
  '化学',
  '生物',
  '历史',
  '地理',
  '政治',
  '科学',
  '道德与法治',
  '信息科技',
  '体育与健康',
  '艺术',
  '劳动',
  '综合实践活动',
  '音乐',
  '美术',
];

typedef SubjectDraftInput = ({String name, String shortName});

/// 「添加科目」弹窗：全称 + 自动简称 + 常用科目快速添加。
class AddSubjectDialog extends StatefulWidget {
  const AddSubjectDialog({
    required this.existingNames,
    this.subject,
    super.key,
  });

  final Set<String> existingNames;
  final Subject? subject;

  @override
  State<AddSubjectDialog> createState() => _AddSubjectDialogState();
}

class _AddSubjectDialogState extends State<AddSubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _shortNameController;
  bool _shortNameEdited = false;
  final Set<String> _selectedCommonSubjects = {};

  bool get _needsManualSubject =>
      widget.subject != null ||
      _selectedCommonSubjects.isEmpty ||
      _nameController.text.trim().isNotEmpty ||
      _shortNameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.subject?.name);
    _shortNameController = TextEditingController(
      text: widget.subject?.shortName,
    );
    _shortNameEdited = widget.subject != null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortNameController.dispose();
    super.dispose();
  }

  void _syncShortName() {
    if (_shortNameEdited) return;
    final name = _nameController.text.trim();
    _shortNameController.text = name.isEmpty
        ? ''
        : String.fromCharCode(name.runes.first);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final subjects = <SubjectDraftInput>[
      if (_needsManualSubject)
        (
          name: _nameController.text.trim(),
          shortName: _shortNameController.text.trim(),
        ),
      for (final name in commonSubjects)
        if (_selectedCommonSubjects.contains(name))
          (name: name, shortName: String.fromCharCode(name.runes.first)),
    ];
    Navigator.pop(context, subjects);
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(widget.subject == null ? '添加科目' : '编辑科目'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '科目全称'),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (!_needsManualSubject) return null;
                if (name.isEmpty) return '请输入科目全称';
                if (widget.existingNames.contains(name)) return '已存在同名科目';
                if (_selectedCommonSubjects.contains(name)) {
                  return '该科目已在常用科目中选中';
                }
                return null;
              },
              onChanged: (_) => setState(_syncShortName),
            ),
            const SizedBox(height: 12),
            AppTextFormField(
              controller: _shortNameController,
              decoration: const InputDecoration(labelText: '简称'),
              validator: (value) =>
                  _needsManualSubject && (value == null || value.trim().isEmpty)
                  ? '请输入简称'
                  : null,
              onChanged: (_) => setState(() => _shortNameEdited = true),
            ),
            const SizedBox(height: 6),
            Text(
              widget.subject == null
                  ? '简写自动取首字，可修改；新科目节数默认 0，不参与容量校验。'
                  : '可同时修改科目全称与简称；点击页面右上角“保存”后生效。',
              style: TextStyle(color: context.appColors.muted, fontSize: 11),
            ),
            if (widget.subject == null) ...[
              const SizedBox(height: 14),
              Text(
                '从常用科目快速添加',
                style: TextStyle(
                  color: context.appColors.inkSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in commonSubjects)
                    _CommonSubjectChip(
                      name: name,
                      selected: _selectedCommonSubjects.contains(name),
                      enabled: !widget.existingNames.contains(name),
                      onPressed: () => setState(() {
                        if (!_selectedCommonSubjects.add(name)) {
                          _selectedCommonSubjects.remove(name);
                        }
                      }),
                    ),
                ],
              ),
            ],
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
        onPressed: _submit,
        child: Text(widget.subject == null ? '添加' : '保存'),
      ),
    ],
  );
}

class _CommonSubjectChip extends StatelessWidget {
  const _CommonSubjectChip({
    required this.name,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String name;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? colors.selectedBlue : colors.surface,
            border: Border.all(color: selected ? colors.blue : colors.border),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 14, color: colors.blue),
                const SizedBox(width: 4),
              ],
              Text(
                name,
                style: TextStyle(
                  color: !enabled
                      ? colors.muted
                      : selected
                      ? colors.blue
                      : colors.inkSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
