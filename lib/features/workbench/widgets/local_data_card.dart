import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:flutter/material.dart';

/// 「数据只保存在这台设备」：本地数据说明 + 上手指南入口。
class LocalDataCard extends StatelessWidget {
  const LocalDataCard({required this.onOpenGuide, super.key});

  final VoidCallback onOpenGuide;

  @override
  Widget build(BuildContext context) => AppSurface(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('数据只保存在这台设备', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            '离线也能排课，数据文件可随时备份。',
            style: TextStyle(
              color: context.appColors.inkSecondary,
              fontSize: 12,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          AppGhostButton(
            onPressed: onOpenGuide,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('查看六步上手指南'),
                Icon(Icons.chevron_right_rounded, size: 15),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 六步上手指南弹窗。
Future<void> showGettingStartedGuide(
  BuildContext context,
) => showAppDialog<void>(
  context: context,
  builder: (context) => AppDialog(
    title: const Text('六步上手指南'),
    content: const SizedBox(
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _GuideStep(
            number: 1,
            title: '学段与班级',
            description: '先创建学期并设置教学日历，再搭好学段、年级与班级。',
          ),
          _GuideStep(
            number: 2,
            title: '作息设置',
            description: '按学段设置上课日、各时段节数与节次时间。',
          ),
          _GuideStep(number: 3, title: '科目节数', description: '填写各年级每周各科所需的课时。'),
          _GuideStep(
            number: 4,
            title: '教师任课',
            description: '为各班科目分配教师，补齐所需节数。',
          ),
          _GuideStep(number: 5, title: '开始排课', description: '检查排课条件并生成课表。'),
          _GuideStep(number: 6, title: '打开课表', description: '查看排课结果，并按需调整课表。'),
        ],
      ),
    ),
    actions: [
      AppPrimaryButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('知道了'),
      ),
    ],
  ),
);

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final int number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.appColors.selectedBlue,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: context.appColors.blue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.appColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: context.appColors.inkSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
