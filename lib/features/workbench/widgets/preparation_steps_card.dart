import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:flutter/material.dart';

/// 「新学期排课准备」：进度条 + 6 步指示器。
class PreparationStepsCard extends StatelessWidget {
  const PreparationStepsCard({required this.summary, super.key});

  final WorkbenchSummary summary;

  @override
  Widget build(BuildContext context) {
    final doneCount = completedPreparationCount(summary);
    final currentStep = currentPreparationStep(summary);
    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '新学期排课准备',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                AppBadge(
                  label: '$doneCount / 6 完成',
                  foreground: AppTheme.inkSecondary,
                  background: AppTheme.tableHeader,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _PreparationProgress(value: doneCount / 6),
            const SizedBox(height: 14),
            // IntrinsicHeight：滚动容器内的 Column 高度无界，stretch 前需定高。
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final step in PreparationStep.values) ...[
                    if (step.number > 1) const SizedBox(width: 8),
                    Expanded(
                      child: _StepIndicator(
                        step: step,
                        status: _statusOf(step, doneCount, currentStep),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static _StepStatus _statusOf(
    PreparationStep step,
    int doneCount,
    PreparationStep currentStep,
  ) {
    if (step.index < doneCount) return _StepStatus.done;
    if (step == currentStep) return _StepStatus.current;
    return _StepStatus.locked;
  }
}

enum _StepStatus { done, current, locked }

class _PreparationProgress extends StatelessWidget {
  const _PreparationProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      height: 4,
      child: Row(
        children: [
          if (value > 0)
            Expanded(
              flex: (value * 100).round().clamp(1, 100),
              child: ColoredBox(color: AppTheme.blue),
            ),
          if (value < 1)
            Expanded(
              flex: (100 - value * 100).round().clamp(1, 100),
              child: const ColoredBox(color: AppTheme.tableDivider),
            ),
        ],
      ),
    ),
  );
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.status});

  final PreparationStep step;
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    final isCurrent = status == _StepStatus.current;
    final titleColor = switch (status) {
      _StepStatus.done => AppTheme.inkSecondary,
      _StepStatus.current => AppTheme.ink,
      _StepStatus.locked => AppTheme.muted,
    };
    final statusText = switch (status) {
      _StepStatus.done => '已完成',
      _StepStatus.current => '当前步骤',
      _StepStatus.locked => '完成前一步后解锁',
    };
    final statusColor = switch (status) {
      _StepStatus.done => AppTheme.success,
      _StepStatus.current => AppTheme.blue,
      _StepStatus.locked => AppTheme.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.selectedBlue : AppTheme.tableHeader,
        borderRadius: BorderRadius.circular(10),
        border: isCurrent ? Border.all(color: AppTheme.blue) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StepDot(number: step.number, status: status),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  step.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            statusText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: statusColor, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.number, required this.status});

  final int number;
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    const size = 20.0;
    if (status == _StepStatus.done) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppTheme.success,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
      );
    }
    if (status == _StepStatus.current) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppTheme.blue,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
