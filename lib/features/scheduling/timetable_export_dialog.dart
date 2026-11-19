import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/scheduling/schedule_export.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

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
  bool showTeacher = true;
  bool showClass = true;
  bool showTime = true;
  bool showWeek = true;
  bool landscape = true;
  int fontSize = 10;
  TimetablePrintFit printFit = TimetablePrintFit.original;
  int section = 0;

  int _fontSizeFromPosition(double position) => 8 + (position * 10).round();

  String _formatFontSize(double position) =>
      '${_fontSizeFromPosition(position)} 磅';

  Widget heading(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);

  Widget field(String label, bool selected, ValueChanged<bool> update) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AppCheckbox(
          label: Text(label),
          value: selected,
          onChanged: (value) => setState(() => update(value)),
        ),
      );

  Widget appearance(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: context.appColors.tableHeader,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FSlider(
                label: Row(
                  children: [
                    Expanded(child: heading(context, '正文基准字号')),
                    Text(
                      '$fontSize 磅',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(color: context.appColors.accent),
                    ),
                  ],
                ),
                trackHitRegionCrossExtent: 44,
                semanticValueFormatterCallback: _formatFontSize,
                tooltipBuilder: (_, value) => Text(_formatFontSize(value)),
                control: FSliderControl.liftedContinuous(
                  value: FSliderValue(max: (fontSize - 8) / 10),
                  stepPercentage: 0.1,
                  onChange: (value) => setState(() {
                    fontSize = _fontSizeFromPosition(value.max);
                  }),
                ),
              ),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  border: Border.all(color: context.appColors.tableDivider),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '字号示例',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '语文',
                        style: TextStyle(
                          color: context.appColors.ink,
                          fontSize: fontSize + 2.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      heading(context, '课节字段'),
      const SizedBox(height: 4),
      const Text('科目、带班活动和课表表头始终保留。'),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns =
              width >= 360 && MediaQuery.textScalerOf(context).scale(14) < 20
              ? 2
              : 1;
          final fields = [
            field('任课及带班教师', showTeacher, (value) => showTeacher = value),
            field('课节内的班级', showClass, (value) => showClass = value),
            field('课节起止时间', showTime, (value) => showTime = value),
            field('单双周标记', showWeek, (value) => showWeek = value),
          ];
          return Wrap(
            spacing: 16,
            children: [
              for (final item in fields)
                SizedBox(
                  width: (width - 16 * (columns - 1)) / columns,
                  child: item,
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget printing(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSelectField<TimetablePrintFit>(
        label: '打印缩放',
        value: printFit,
        items: const {
          '原始比例（Excel 默认）': TimetablePrintFit.original,
          '一页宽，高度自动分页': TimetablePrintFit.width,
          '每张表缩放至一页': TimetablePrintFit.page,
        },
        onChanged: (value) {
          if (value != null) setState(() => printFit = value);
        },
      ),
      const SizedBox(height: 8),
      const Text('总课表较长时，选一页宽可保留纵向分页。'),
      const Divider(height: 32),
      FSwitch(
        label: const Text('横向打印'),
        description: Text(
          printFit == TimetablePrintFit.original
              ? '选择自适应缩放后可调整 A4 纸张方向。'
              : landscape
              ? 'A4 横向'
              : 'A4 纵向',
        ),
        value: landscape,
        enabled: printFit != TimetablePrintFit.original,
        onChange: (value) => setState(() => landscape = value),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 544,
    titleGap: 16,
    actionsGap: 12,
    title: AppDialogTitle(title: '导出课表', onClose: () => Navigator.pop(context)),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '班级、教师和学校总课表 · Excel 压缩包',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.appColors.inkSecondary),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) => FTabs(
            scrollable:
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) >= 20,
            control: FTabControl.lifted(
              index: section,
              onChange: (index) => setState(() => section = index),
              motion: FTabMotion(
                duration: AppTheme.motionDuration(
                  context,
                  AppTheme.transitionDuration,
                ),
                curve: AppTheme.entranceCurve,
              ),
            ),
            style: const FTabsStyleDelta.delta(minHeight: 42, spacing: 16),
            children: [
              for (final (label, panel) in [
                ('内容与字号', appearance(context)),
                ('打印设置', printing(context)),
                ('分表方式', organization(context)),
              ])
                FTabEntry(
                  label: Text(label),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 286),
                    child: panel,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 16),
      ],
    ),
    actions: [
      AppGhostButton(
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
            fontSize: fontSize,
            showTeacher: showTeacher,
            showClass: showClass,
            showTime: showTime,
            showWeek: showWeek,
            printFit: printFit,
            landscape: landscape,
          ),
        ),
        child: const Text('确认导出'),
      ),
    ],
  );

  Widget organization(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(context, '教师课表'),
      const SizedBox(height: 8),
      FRadio(
        label: const Text('统一时间轴（推荐）'),
        description: const Text('起止时间相同的课节合并为一行。'),
        value: unified,
        onChange: (_) => setState(() => unified = true),
      ),
      const SizedBox(height: 8),
      FRadio(
        label: const Text('按学段分别展示'),
        description: const Text('保留各学段原有的作息行。'),
        value: !unified,
        onChange: (_) => setState(() => unified = false),
      ),
      const SizedBox(height: 12),
      FCheckbox(
        label: const Text('跨学段课程显示学段'),
        value: showStage && showClass,
        enabled: showClass,
        description: showClass ? null : const Text('请先启用课节内的班级。'),
        onChange: (value) => setState(() => showStage = value),
      ),
      const Divider(height: 32),
      heading(context, '学校总课表'),
      const SizedBox(height: 8),
      FSwitch(
        label: const Text('学校总课表按学段汇总整周'),
        description: const Text('关闭后按星期分别生成。'),
        value: weekly,
        onChange: (value) => setState(() => weekly = value),
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
