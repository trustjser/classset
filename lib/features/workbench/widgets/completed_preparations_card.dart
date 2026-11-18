import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:flutter/material.dart';

/// 「已完成的准备」：以 chips 展示已完成的步骤（支持点击切换上方引导卡回看）。
class CompletedPreparationsCard extends StatelessWidget {
  const CompletedPreparationsCard({
    required this.summary,
    this.selectedStep,
    this.onSelectStep,
    super.key,
  });

  final WorkbenchSummary summary;
  final PreparationStep? selectedStep;
  final ValueChanged<PreparationStep>? onSelectStep;

  @override
  Widget build(BuildContext context) {
    final doneSteps = <PreparationStep>[
      if (summary.stagesDone) PreparationStep.stagesAndClasses,
      if (summary.routineDone) PreparationStep.routine,
      if (completedPreparationCount(summary) > 2)
        PreparationStep.subjectLessons,
      if (completedPreparationCount(summary) > 3)
        PreparationStep.teacherAssignments,
      if (completedPreparationCount(summary) > 4) PreparationStep.autoSchedule,
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
                Text(
                  '随时可调整',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AnimatedSize(
              duration: AppTheme.motionDuration(
                context,
                AppTheme.transitionDuration,
              ),
              curve: AppTheme.entranceCurve,
              alignment: Alignment.topLeft,
              child: doneSteps.isEmpty
                  ? Text(
                      '还没有完成的准备，从「学段与班级」开始吧。',
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final step in doneSteps)
                          TweenAnimationBuilder<double>(
                            key: ValueKey<PreparationStep>(step),
                            tween: Tween<double>(begin: 0.94, end: 1.0),
                            duration: AppTheme.motionDuration(
                              context,
                              AppTheme.transitionDuration,
                            ),
                            curve: AppTheme.entranceCurve,
                            builder: (context, scale, child) => Transform.scale(
                              scale: scale,
                              child: child,
                            ),
                            child: _CompletedStepChip(
                              step: step,
                              isSelected: selectedStep == step,
                              onTap: onSelectStep == null
                                  ? null
                                  : () => onSelectStep!(step),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedStepChip extends StatefulWidget {
  const _CompletedStepChip({
    required this.step,
    required this.isSelected,
    this.onTap,
  });

  final PreparationStep step;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  State<_CompletedStepChip> createState() => _CompletedStepChipState();
}

class _CompletedStepChipState extends State<_CompletedStepChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.motionDuration(context, AppTheme.feedbackDuration),
          curve: AppTheme.entranceCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? colors.selectedBlue
                : _hovered
                ? Color.alphaBlend(
                    colors.success.withValues(alpha: 0.06),
                    colors.tableHeader,
                  )
                : colors.tableHeader,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isSelected
                  ? colors.blue.withValues(alpha: 0.36)
                  : colors.success.withValues(alpha: _hovered ? 0.34 : 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: colors.success,
              ),
              const SizedBox(width: 7),
              Text(
                '${widget.step.title} · 已完成',
                style: TextStyle(
                  color: widget.isSelected ? colors.ink : colors.inkSecondary,
                  fontSize: 12,
                  fontWeight: widget.isSelected
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
