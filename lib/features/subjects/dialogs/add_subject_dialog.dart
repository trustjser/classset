import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

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

/// 「添加科目」弹窗：全称 + 自动简称 + 常用科目快速添加。
class AddSubjectDialog extends StatefulWidget {
  const AddSubjectDialog({required this.existingNames, super.key});

  final Set<String> existingNames;

  @override
  State<AddSubjectDialog> createState() => _AddSubjectDialogState();
}

class _AddSubjectDialogState extends State<AddSubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _shortNameController = TextEditingController();
  bool _shortNameEdited = false;

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
    Navigator.pop(context, (
      name: _nameController.text.trim(),
      shortName: _shortNameController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('添加科目'),
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
                if (name.isEmpty) return '请输入科目全称';
                if (widget.existingNames.contains(name)) return '已存在同名科目';
                return null;
              },
              onChanged: (_) => setState(_syncShortName),
            ),
            const SizedBox(height: 12),
            AppTextFormField(
              controller: _shortNameController,
              decoration: const InputDecoration(labelText: '简称'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入简称' : null,
              onChanged: (_) => setState(() => _shortNameEdited = true),
            ),
            const SizedBox(height: 6),
            Text(
              '简写自动取首字，可修改；新科目节数默认 0，不参与容量校验。',
              style: TextStyle(color: context.appColors.muted, fontSize: 11),
            ),
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
                  AppGhostButton(
                    size: f.FButtonSizeVariant.xs,
                    onPressed: widget.existingNames.contains(name)
                        ? null
                        : () {
                            _nameController.text = name;
                            _shortNameController.text = String.fromCharCode(
                              name.runes.first,
                            );
                            _shortNameEdited = false;
                            setState(() {});
                            _submit();
                          },
                    child: Text(name),
                  ),
              ],
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
      AppPrimaryButton(onPressed: _submit, child: const Text('添加')),
    ],
  );
}
