part of '../teachers_page.dart';

Future<bool?> _showAssignmentImportDialog(
  BuildContext context, {
  required Future<void> Function() onDownloadTemplate,
}) => showAppDialog<bool>(
  context: context,
  builder: (context) => AppDialog(
    title: const Text('Excel导入任课分配'),
    maxWidth: 560,
    content: SizedBox(
      width: 512,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '请填写当前学期的学段、年级、班级、科目、教师、周模式和节数。上传后可先预览，再确认导入。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          _TeacherImportActionCard(
            icon: Icons.download_outlined,
            title: '下载任课分配模板',
            description: '含「导入说明」「数据源」「任课分配」三个工作表。',
            action: AppOutlineButton(
              key: const ValueKey('assignment-import-download-template'),
              onPressed: onDownloadTemplate,
              child: const Text('下载模板'),
            ),
          ),
          const SizedBox(height: 12),
          _TeacherImportActionCard(
            icon: Icons.upload_file_outlined,
            title: '上传填写后的 Excel',
            description: '仅支持 .xlsx 文件，上传后先核对任课分配。',
            action: AppPrimaryButton(
              key: const ValueKey('assignment-import-select-file'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('选择 Excel 文件'),
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
    ],
  ),
);

Future<bool?> _showAssignmentImportPreview(
  BuildContext context,
  List<ResolvedAssignmentRow> rows,
) => showAppDialog<bool>(
  context: context,
  builder: (context) => AppDialog(
    title: Text('预览任课分配 · ${rows.length} 条'),
    maxWidth: 760,
    content: SizedBox(
      width: 712,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '以下分配将添加到当前学期；已有任课不会被覆盖。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final item in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                '${item.source.stage} · ${item.source.grade} · ${item.source.schoolClass}  '
                '${item.source.subject}  ${item.source.teacher}  '
                '${item.source.weekMode.label} ${item.source.lessonCount} 节',
              ),
            ),
        ],
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('确认导入'),
      ),
    ],
  ),
);
