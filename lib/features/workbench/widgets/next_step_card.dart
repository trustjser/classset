import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:flutter/material.dart';

/// 「接下来」：当前步骤引导卡（浅蓝底主操作区）。
class NextStepCard extends StatelessWidget {
  const NextStepCard({
    required this.step,
    required this.copy,
    required this.onAction,
    this.comingSoonHint,
    super.key,
  });

  final PreparationStep step;
  final StepCopy copy;

  /// 为 null 表示该步骤尚未实现，仅展示提示。
  final VoidCallback? onAction;
  final String? comingSoonHint;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.appColors.selectedBlue,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
    ),
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppBadge(
              label: '接下来',
              foreground: context.appColors.blue,
              background: context.appColors.surface,
            ),
            const SizedBox(width: 8),
            Text(
              '第 ${step.number} 步',
              style: TextStyle(
                color: context.appColors.blue,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          copy.title,
          style: TextStyle(
            color: context.appColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          copy.description,
          style: TextStyle(
            color: context.appColors.inkSecondary,
            fontSize: 13,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          copy.meta,
          style: TextStyle(color: context.appColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            AppPrimaryButton(
              onPressed: onAction,
              child: Text(copy.actionLabel),
            ),
            if (comingSoonHint != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  comingSoonHint!,
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}
