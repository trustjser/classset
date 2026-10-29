import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/scheduling/schedule_export.dart';
import 'package:flutter/material.dart';

/// 配置三个课表工作簿的展示方式。
class TimetableExportDialog extends StatefulWidget {
  const TimetableExportDialog({super.key});

  @override
  State<TimetableExportDialog> createState() => _TimetableExportDialogState();
}

class _TimetableExportDialogState extends State<TimetableExportDialog> {
  bool unified = true;
  bool showStage = true;
  bool weekly = true;

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 560,
    title: AppDialogTitle(
      title: '导出全部 Excel',
      onClose: () => Navigator.pop(context),
    ),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('选择导出方式后，将班级、教师和学校课表打包为 ZIP 文件。'),
        const SizedBox(height: 18),
        Text(
          '教师跨学段课表展示方式',
          style: TextStyle(
            color: context.appColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        RadioGroup<bool>(
          groupValue: unified,
          onChanged: (value) => setState(() => unified = value ?? true),
          child: Column(
            children: [
              RadioListTile<bool>(
                value: true,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('统一时间轴（推荐）'),
                subtitle: const Text('起止时间相同的课节合并为一行。'),
              ),
              RadioListTile<bool>(
                value: false,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('按学段分别展示'),
                subtitle: const Text('保留各学段原有的作息行。'),
              ),
            ],
          ),
        ),
        CheckboxListTile(
          value: showStage,
          onChanged: (value) => setState(() => showStage = value ?? false),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('跨学段课程显示学段'),
          subtitle: const Text('关闭后显示科目和班级。'),
        ),
        const Divider(height: 28),
        Text(
          '学校总课表展示方式',
          style: TextStyle(
            color: context.appColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        CheckboxListTile(
          value: weekly,
          onChanged: (value) => setState(() => weekly = value ?? false),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('学校总课表按学段汇总整周'),
          subtitle: const Text('勾选后每个学段一张表；否则按星期分别生成。'),
        ),
      ],
    ),
    actions: [
      AppSecondaryButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: () => Navigator.pop(
          context,
          TimetableExportOptions(
            teacherUnified: unified,
            showTeacherStage: showStage,
            schoolWeekly: weekly,
          ),
        ),
        child: const Text('确认导出'),
      ),
    ],
  );
}

/// 导出期间阻止重复操作，并提示正在处理。
class TimetableExportLoading extends StatelessWidget {
  const TimetableExportLoading({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const ModalBarrier(dismissible: false, color: Color(0x66000000)),
      Center(
        child: AppSurface(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  '正在导出课表，请稍候…',
                  style: TextStyle(color: context.appColors.ink, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
