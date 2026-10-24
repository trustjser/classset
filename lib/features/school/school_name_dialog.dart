import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:flutter/material.dart';

class SchoolNameDialog extends StatefulWidget {
  const SchoolNameDialog({required this.initialName, super.key});

  final String initialName;

  @override
  State<SchoolNameDialog> createState() => _SchoolNameDialogState();
}

class _SchoolNameDialogState extends State<SchoolNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 420,
    title: AppDialogTitle(
      title: '编辑学校名称',
      onClose: () => Navigator.of(context).pop(),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('学校名称', style: TextStyle(color: context.appColors.ink)),
        const SizedBox(height: 8),
        AppTextFormField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入学校名称'),
          onFieldSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Text(
          '留空将显示“未命名学校”。',
          style: TextStyle(color: context.appColors.muted, fontSize: 11),
        ),
      ],
    ),
    actions: [
      AppSecondaryButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      AppPrimaryButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
