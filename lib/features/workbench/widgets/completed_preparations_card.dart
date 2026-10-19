import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:flutter/material.dart';

/// 「已完成的准备」：以 chips 展示已完成的步骤。
class CompletedPreparationsCard extends StatelessWidget {
  const CompletedPreparationsCard({required this.summary, super.key});

  final WorkbenchSummary summary;

  @override
  Widget build(BuildContext context) {
    final doneSteps = <PreparationStep>[
      if (summary.stagesDone) PreparationStep.stagesAndClasses,
      if (summary.routineDone) PreparationStep.routine,
    ];
    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已完成的准备',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const Text(
                  '随时可调整',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (doneSteps.isEmpty)
              const Text(
                '还没有完成的准备，从「学段与班级」开始吧。',
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final step in doneSteps)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.tableHeader,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: AppTheme.success,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            '${step.title} · 已完成',
                            style: const TextStyle(
                              color: AppTheme.inkSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
