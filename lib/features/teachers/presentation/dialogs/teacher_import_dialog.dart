part of '../teachers_page.dart';

class _TeacherImportDialog extends StatefulWidget {
  const _TeacherImportDialog({
    required this.teachers,
    required this.subjects,
    required this.groups,
    required this.pickFile,
    required this.download,
  });
  final List<Teacher> teachers;
  final List<Subject> subjects;
  final List<TeacherGroup> groups;
  final Future<XFile?> Function() pickFile;
  final Future<void> Function(bool) download;
  @override
  State<_TeacherImportDialog> createState() => _TeacherImportDialogState();
}

class _TeacherImportDialogState extends State<_TeacherImportDialog> {
  TeacherImportMode mode = TeacherImportMode.create;
  bool clearEmpty = false;
  bool includeExisting = true;
  bool busy = false;
  String? fileName;
  TeacherWorkbookResult? workbook;
  TeacherImportStatus selected = TeacherImportStatus.create;

  List<TeacherImportEntry> get entries => planTeacherImport(
    rows: workbook?.rows ?? [],
    teachers: widget.teachers,
    subjects: widget.subjects,
    groups: widget.groups,
    mode: mode,
  );
  int count(TeacherImportStatus status) =>
      entries.where((entry) => entry.status == status).length +
      (status == TeacherImportStatus.error ? workbook?.errors.length ?? 0 : 0);
  void updateSelection() {
    selected = TeacherImportStatus.values.firstWhere(
      (status) => count(status) > 0,
      orElse: () => TeacherImportStatus.create,
    );
  }

  Future<void> pick() async {
    setState(() => busy = true);
    try {
      final file = await widget.pickFile();
      if (file == null) return;
      final parsed = parseTeachersWorkbook(await file.readAsBytes());
      if (mounted) {
        setState(() {
          fileName = file.name;
          workbook = parsed;
          updateSelection();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          fileName = null;
          workbook = TeacherWorkbookResult(
            errors: [TeacherWorkbookError(1, '读取文件失败：$error')],
          );
          selected = TeacherImportStatus.error;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    setState(() => busy = true);
    try {
      await widget.download(includeExisting);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载失败：$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget sectionTitle(String number, String title, String description) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.appColors.selectedBlue,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  number,
                  style: TextStyle(
                    color: context.appColors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: context.appColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: TextStyle(
              color: context.appColors.inkSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
        ],
      );

  Widget optionRow(String label, List<Widget> options) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(
              color: context.appColors.inkSecondary,
              fontSize: 12,
            ),
          ),
        ),
        ...options,
      ],
    ),
  );

  Widget templateCard() => Container(
    key: const ValueKey('teacher-import-template-card'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: context.appColors.surface,
      border: Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.appColors.selectedBlue,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.description_outlined,
            size: 19,
            color: context.appColors.blue,
          ),
        ),
        SizedBox(
          width: 235,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '教师导入模板.xlsx',
                style: TextStyle(
                  color: context.appColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '模板是否包含现有教师数据',
                style: TextStyle(color: context.appColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
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
          key: const ValueKey('teacher-import-download-template'),
          onPressed: busy ? null : download,
          child: const Text('下载模板'),
        ),
      ],
    ),
  );

  Widget fileCard() {
    final valid = workbook != null && count(TeacherImportStatus.error) == 0;
    final accent = workbook == null
        ? context.appColors.blue
        : valid
        ? context.appColors.success
        : context.appColors.destructive;
    final background = workbook == null
        ? context.appColors.selectedBlue
        : valid
        ? context.appColors.successSurface
        : context.appColors.destructiveSurface;
    return Material(
      color: context.appColors.tableHeader,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: const ValueKey('teacher-import-select-file'),
        onTap: busy ? null : pick,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          key: const ValueKey('teacher-import-file-card'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: context.appColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.description_outlined,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          fileName ?? '选择 Excel 文件',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appColors.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (workbook != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: background,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              valid ? '校验通过' : '有待处理问题',
                              style: TextStyle(color: accent, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fileName == null ? '点击选择本地 .xlsx 文件' : '点击可更换文件',
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.upload_file_outlined,
                size: 18,
                color: context.appColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget previewCell(String value, {Color? color, bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Tooltip(
          message: value,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? context.appColors.inkSecondary,
              fontSize: 12,
              fontWeight: strong ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );

  Widget previewTable(List<TeacherImportEntry> rows, String label) {
    final visibleRows = rows
        .where((entry) => entry.status == selected)
        .toList();
    final parseErrors = selected == TeacherImportStatus.error
        ? workbook!.errors
        : <TeacherWorkbookError>[];
    final total = visibleRows.length + parseErrors.length;
    return Container(
      key: const ValueKey('teacher-import-preview-table'),
      decoration: BoxDecoration(
        border: Border.all(color: context.appColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: context.appColors.tableHeader,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$label数据',
                      style: TextStyle(
                        color: context.appColors.inkSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$total 条',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (total == 0)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '暂无$label数据',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 12,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 168),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (visibleRows.isNotEmpty)
                        Container(
                          color: context.appColors.tableHeader,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 60,
                                child: previewCell(
                                  '行号',
                                  color: context.appColors.muted,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: previewCell(
                                  '教师',
                                  color: context.appColors.muted,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: previewCell(
                                  selected == TeacherImportStatus.create ||
                                          selected == TeacherImportStatus.update
                                      ? '科目'
                                      : '原因',
                                  color: context.appColors.muted,
                                ),
                              ),
                              if (selected == TeacherImportStatus.create ||
                                  selected == TeacherImportStatus.update)
                                Expanded(
                                  flex: 3,
                                  child: previewCell(
                                    '分组',
                                    color: context.appColors.muted,
                                  ),
                                ),
                              SizedBox(
                                width: 56,
                                child: previewCell(
                                  '操作',
                                  color: context.appColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (final entry in visibleRows)
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: context.appColors.border),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 60,
                                child: previewCell(
                                  '第 ${entry.row.rowNumber} 行',
                                  color: context.appColors.muted,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: previewCell(
                                  entry.row.name,
                                  color: context.appColors.ink,
                                  strong: true,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: previewCell(
                                  selected == TeacherImportStatus.create ||
                                          selected == TeacherImportStatus.update
                                      ? (entry.row.subjects.isEmpty
                                            ? '—'
                                            : entry.row.subjects.join('、'))
                                      : entry.message,
                                  color: selected == TeacherImportStatus.error
                                      ? context.appColors.destructive
                                      : null,
                                ),
                              ),
                              if (selected == TeacherImportStatus.create ||
                                  selected == TeacherImportStatus.update)
                                Expanded(
                                  flex: 3,
                                  child: previewCell(
                                    entry.row.groups.isEmpty
                                        ? '—'
                                        : entry.row.groups.join('、'),
                                  ),
                                ),
                              SizedBox(
                                width: 56,
                                child: previewCell(
                                  label,
                                  color: selected == TeacherImportStatus.update
                                      ? context.appColors.warning
                                      : context.appColors.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (final error in parseErrors)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: context.appColors.border),
                            ),
                          ),
                          child: Text(
                            '$error',
                            style: TextStyle(
                              color: context.appColors.destructive,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = entries;
    final errors = count(TeacherImportStatus.error);
    final actionable =
        count(TeacherImportStatus.create) + count(TeacherImportStatus.update);
    const labels = {
      TeacherImportStatus.create: '可新增',
      TeacherImportStatus.update: '可更新',
      TeacherImportStatus.skip: '跳过',
      TeacherImportStatus.error: '错误',
    };
    Color statusColor(TeacherImportStatus status) => switch (status) {
      TeacherImportStatus.create => context.appColors.success,
      TeacherImportStatus.update => context.appColors.blue,
      TeacherImportStatus.skip => context.appColors.muted,
      TeacherImportStatus.error => context.appColors.destructive,
    };
    return AppDialog(
      maxWidth: 720,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.zero,
      titleGap: 0,
      actionsGap: 0,
      title: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 16, 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.appColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Excel 导入教师',
                    style: TextStyle(
                      color: context.appColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '支持 .xlsx，导入前可预览变更',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            AppIconButton(
              onPressed: () {
                if (!busy) Navigator.pop(context);
              },
              tooltip: '关闭',
              icon: Icons.close,
              iconSize: 16,
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 672,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sectionTitle(
                '01',
                '配置信息',
                '按教师姓名匹配；同名教师无法唯一确定时请先处理。更新时填写的科目和分组会替换对应设置。',
              ),
              optionRow('导入方式', [
                for (final option in const [
                  (TeacherImportMode.create, '新增'),
                  (TeacherImportMode.update, '更新'),
                  (TeacherImportMode.upsert, '新增或更新'),
                ])
                  AppRadioOption<TeacherImportMode>(
                    value: option.$1,
                    groupValue: mode,
                    label: option.$2,
                    enabled: !busy,
                    onChanged: (value) => setState(() {
                      mode = value;
                      updateSelection();
                    }),
                  ),
              ]),
              optionRow('空单元格', [
                AppRadioOption<bool>(
                  value: false,
                  groupValue: clearEmpty,
                  label: '不处理',
                  enabled: !busy,
                  onChanged: (value) => setState(() => clearEmpty = value),
                ),
                AppRadioOption<bool>(
                  value: true,
                  groupValue: clearEmpty,
                  label: '清空',
                  enabled: !busy,
                  onChanged: (value) => setState(() => clearEmpty = value),
                ),
              ]),
              const SizedBox(height: 12),
              sectionTitle('02', '下载模板', '模板包含填写说明与科目数据源，多个分组或科目用英文逗号分隔。'),
              templateCard(),
              const SizedBox(height: 20),
              sectionTitle('03', '添加本地表格', '仅支持 .xlsx 文件，选择后立即在本地校验。'),
              fileCard(),
              if (busy)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '处理中…',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (workbook != null) ...[
                const SizedBox(height: 20),
                sectionTitle('04', '导入预览', '校验结果按行统计，点击分类可筛选查看对应明细。'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in TeacherImportStatus.values)
                      OutlinedButton(
                        key: ValueKey('teacher-import-status-${status.name}'),
                        onPressed: () => setState(() => selected = status),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: selected == status
                              ? context.appColors.selectedBlue
                              : context.appColors.surface,
                          foregroundColor: selected == status
                              ? context.appColors.blue
                              : context.appColors.inkSecondary,
                          side: BorderSide(
                            color: selected == status
                                ? context.appColors.blue
                                : context.appColors.border,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor(status),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${labels[status]} ${count(status)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                previewTable(rows, labels[selected]!),
                const SizedBox(height: 8),
                Text(
                  '${labels[selected]}数据 · ${count(selected)} 条',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        Container(
          width: 720,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: context.appColors.tableHeader,
            border: Border(top: BorderSide(color: context.appColors.border)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(
                workbook == null ? '选择文件后可预览变更' : '共 $actionable 条变更，导入后立即生效',
                style: TextStyle(color: context.appColors.muted, fontSize: 11),
              ),
              Wrap(
                spacing: 8,
                children: [
                  AppGhostButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  AppPrimaryButton(
                    key: const ValueKey('teacher-import-confirm'),
                    onPressed: busy || errors > 0 || actionable == 0
                        ? null
                        : () => Navigator.pop(context, (rows, clearEmpty)),
                    child: Text(actionable > 0 ? '导入 $actionable 条' : '导入'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
