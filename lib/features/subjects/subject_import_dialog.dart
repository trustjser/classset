import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/subject_workbook.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

class SubjectImportDialog extends StatefulWidget {
  const SubjectImportDialog({
    required this.termLabel,
    required this.stages,
    required this.grades,
    required this.classes,
    required this.subjects,
    required this.values,
    required this.alternating,
    required this.pickFile,
    required this.saveTemplate,
    super.key,
  });
  final String termLabel;
  final List<SchoolStage> stages;
  final List<GradeGroup> grades;
  final List<ClassBrief> classes;
  final List<Subject> subjects;
  final Map<(String, String), ClassSubjectValues> values;
  final bool alternating;
  final Future<XFile?> Function() pickFile;
  final Future<bool> Function(List<int>) saveTemplate;

  @override
  State<SubjectImportDialog> createState() => _SubjectImportDialogState();
}

class _SubjectImportDialogState extends State<SubjectImportDialog> {
  bool includeExisting = true;
  bool busy = false;
  String? fileName;
  String? notice;
  SubjectWorkbookPlan? plan;

  Future<void> download() async {
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final bytes = buildSubjectWorkbook(
        stages: widget.stages,
        grades: widget.grades,
        classes: widget.classes,
        subjects: widget.subjects,
        values: widget.values,
        includeExisting: includeExisting,
      );
      final saved = await widget.saveTemplate(bytes);
      if (mounted && saved) setState(() => notice = '模板已下载');
    } catch (error) {
      if (mounted) setState(() => notice = '下载失败：$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick() async {
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final file = await widget.pickFile();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final result = parseSubjectWorkbook(
        bytes,
        stages: widget.stages,
        grades: widget.grades,
        classes: widget.classes,
        subjects: widget.subjects,
        alternating: widget.alternating,
      );
      if (mounted) {
        setState(() {
          fileName = file.name;
          plan = result;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          fileName = null;
          plan = null;
          notice = '读取文件失败：$error';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 800,
    title: AppDialogTitle(
      title: 'Excel 导入科目节数',
      onClose: () {
        if (!busy) Navigator.pop(context);
      },
    ),
    content: SizedBox(
      width: 752,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.termLabel,
            style: TextStyle(color: context.appColors.muted),
          ),
          const SizedBox(height: 20),
          Text(
            '01   下载模板',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.appColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text('按模板的“基础数据”填写学段、年级和科目，每行填写一个年级的一门科目。'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appColors.tableHeader,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 14,
              runSpacing: 8,
              children: [
                const Text('模板包含现有数据'),
                AppRadioOption<bool>(
                  value: true,
                  groupValue: includeExisting,
                  label: '是',
                  enabled: !busy,
                  onChanged: (value) => setState(() => includeExisting = value),
                ),
                AppRadioOption<bool>(
                  value: false,
                  groupValue: includeExisting,
                  label: '否',
                  enabled: !busy,
                  onChanged: (value) => setState(() => includeExisting = value),
                ),
                AppOutlineButton(
                  key: const ValueKey('subject-import-download'),
                  onPressed: busy ? null : download,
                  child: const Text('下载模板'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '02   添加本地表格',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.appColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '节数与页面录入格式相同：3 表示全班一致；3,2 按班级顺序填写；2|1|1 表示每周、单周、双周。仅支持 .xlsx 文件，本地解析。',
          ),
          const SizedBox(height: 10),
          AppOutlineButton(
            key: const ValueKey('subject-import-pick'),
            onPressed: busy ? null : pick,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.upload_file_outlined),
                  const SizedBox(height: 6),
                  Text(fileName ?? '点击选择文件'),
                ],
              ),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('处理中…'),
            ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(notice!),
            ),
          if (plan != null && plan!.errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '导入未通过校验，请修改后重新选择文件：',
              style: TextStyle(color: context.appColors.destructive),
            ),
            for (final error in plan!.errors)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  error,
                  style: TextStyle(color: context.appColors.destructive),
                ),
              ),
          ] else if (plan != null) ...[
            const SizedBox(height: 12),
            Text(
              '已校验 ${plan!.values.length} 条班级科目设置。确认后写入页面草稿，点击页面“保存”后生效；未填写的内容保持不变。',
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in plan!.values.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${widget.classes.where((item) => item.id == entry.key.$1).firstOrNull?.name ?? entry.key.$1} · ${widget.subjects.where((item) => item.id == entry.key.$2).firstOrNull?.name ?? entry.key.$2}：每周 ${entry.value.weekly}，单周 ${entry.value.odd}，双周 ${entry.value.even}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        key: const ValueKey('subject-import-confirm'),
        onPressed: busy || plan == null || plan!.errors.isNotEmpty
            ? null
            : () => Navigator.pop(context, plan),
        child: const Text('确认导入'),
      ),
    ],
  );
}
