import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:flutter/material.dart';

/// 「新学期排课准备」：进度条 + 6 步指示器（仅已解锁步骤支持点击回看，严格遵守级联解锁）。
class PreparationStepsCard extends StatelessWidget {
  const PreparationStepsCard({
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
    final doneCount = completedPreparationCount(summary);
    final currentStep = currentPreparationStep(summary);
    final activeStep = selectedStep ?? currentStep;
    final total = PreparationStep.values.length;
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
                AnimatedSwitcher(
                  duration: AppTheme.motionDuration(
                    context,
                    AppTheme.feedbackDuration,
                  ),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: KeyedSubtree(
                    key: ValueKey<int>(doneCount),
                    child: AppBadge(
                      label: '$doneCount / $total 完成',
                      foreground: context.appColors.inkSecondary,
                      background: context.appColors.tableHeader,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PreparationProgress(done: doneCount, total: total),
            const SizedBox(height: 14),
            // IntrinsicHeight：滚动容器内的 Column 高度无界，stretch 前需定高。
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final step in PreparationStep.values) ...[
                    if (step.number > 1) const SizedBox(width: 8),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final status = _statusOf(
                            step,
                            doneCount,
                            currentStep,
                          );
                          final unlocked = status != _StepStatus.locked;
                          return _StepIndicator(
                            step: step,
                            status: status,
                            isSelected: step == activeStep,
                            onTap: unlocked && onSelectStep != null
                                ? () => onSelectStep!(step)
                                : null,
                          );
                        },
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

/// 准备进度条：标题下方的胶囊进度条（蓝填充 / 浅灰轨道），进度变化时平滑过渡。
class _PreparationProgress extends StatelessWidget {
  const _PreparationProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: total == 0 ? 0 : done / total),
    duration: AppTheme.motionDuration(
      context,
      const Duration(milliseconds: 300),
    ),
    curve: AppTheme.entranceCurve,
    builder: (context, value, _) => ClipRRect(
      key: const Key('preparation-progress'),
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        // stretch：ColoredBox 无子节点时按 constraints.smallest 布局会得到零高度
        // （同 _BrandLogo 的注意事项），必须让 Row 在交叉轴给紧约束才能撑开填充。
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (value > 0)
              Expanded(
                flex: (value * 100).round().clamp(1, 100),
                child: ColoredBox(color: context.appColors.blue),
              ),
            if (value < 1)
              Expanded(
                flex: (100 - value * 100).round().clamp(1, 100),
                child: ColoredBox(color: context.appColors.tableDivider),
              ),
          ],
        ),
      ),
    ),
  );
}

class _StepIndicator extends StatefulWidget {
  const _StepIndicator({
    required this.step,
    required this.status,
    required this.isSelected,
    this.onTap,
  });

  final PreparationStep step;
  final _StepStatus status;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  State<_StepIndicator> createState() => _StepIndicatorState();
}

class _StepIndicatorState extends State<_StepIndicator> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isCurrent = widget.status == _StepStatus.current;
    final isDone = widget.status == _StepStatus.done;
    final isLocked = widget.status == _StepStatus.locked;
    final canTap = !isLocked && widget.onTap != null;
    final isHighlighted = widget.isSelected || isCurrent;
    final titleColor = switch (widget.status) {
      _StepStatus.done =>
        widget.isSelected ? context.appColors.ink : context.appColors.inkSecondary,
      _StepStatus.current => context.appColors.ink,
      _StepStatus.locked => context.appColors.muted,
    };
    final statusText = switch (widget.status) {
      _StepStatus.done => '已完成',
      _StepStatus.current => '当前步骤',
      _StepStatus.locked => '完成前一步后解锁',
    };
    final statusColor = switch (widget.status) {
      _StepStatus.done => context.appColors.success,
      _StepStatus.current => context.appColors.blue,
      _StepStatus.locked => context.appColors.muted,
    };
    final transitionDuration = AppTheme.motionDuration(
      context,
      AppTheme.transitionDuration,
    );
    final baseBackground = widget.isSelected || isCurrent
        ? context.appColors.selectedBlue
        : isDone
        ? Color.alphaBlend(
            context.appColors.success.withValues(alpha: 0.05),
            context.appColors.tableHeader,
          )
        : context.appColors.tableHeader;
    final backgroundColor = canTap && _hovered
        ? Color.alphaBlend(
            context.appColors.blue.withValues(alpha: 0.05),
            baseBackground,
          )
        : baseBackground;
    final borderColor = widget.isSelected
        ? context.appColors.blue.withValues(
            alpha: canTap && _hovered ? 0.52 : 0.38,
          )
        : isCurrent
        ? context.appColors.blue.withValues(alpha: 0.28)
        : isDone
        ? context.appColors.success.withValues(
            alpha: canTap && _hovered ? 0.36 : 0.22,
          )
        : context.appColors.blue.withValues(alpha: 0);

    return MouseRegion(
      cursor: canTap ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: canTap ? (_) => setState(() => _hovered = true) : null,
      onExit: canTap ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTap ? widget.onTap : null,
        child: AnimatedContainer(
          duration: transitionDuration,
          curve: AppTheme.entranceCurve,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StepDot(number: widget.step.number, status: widget.status),
                  const SizedBox(width: 7),
                  Expanded(
                    child: AnimatedDefaultTextStyle(
                      duration: transitionDuration,
                      curve: AppTheme.entranceCurve,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 12,
                        fontWeight: isHighlighted
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      child: Text(
                        widget.step.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              AnimatedDefaultTextStyle(
                duration: transitionDuration,
                curve: AppTheme.entranceCurve,
                style: TextStyle(color: statusColor, fontSize: 10.5),
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
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
    final colors = context.appColors;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final backgroundColor = switch (status) {
      _StepStatus.done => colors.success,
      _StepStatus.current => colors.blue,
      _StepStatus.locked => colors.blue.withValues(alpha: 0),
    };
    final borderColor = switch (status) {
      _StepStatus.done => colors.success,
      _StepStatus.current => colors.blue,
      _StepStatus.locked => colors.border,
    };
    return AnimatedContainer(
      duration: AppTheme.motionDuration(context, AppTheme.transitionDuration),
      curve: AppTheme.entranceCurve,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor),
      ),
      child: AnimatedSwitcher(
        duration: AppTheme.motionDuration(context, AppTheme.feedbackDuration),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.72, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: AppTheme.entranceCurve),
            ),
            child: child,
          ),
        ),
        child: status == _StepStatus.done
            ? Icon(
                Icons.check_rounded,
                key: const ValueKey('done'),
                size: 13,
                color: onPrimary,
              )
            : Text(
                '$number',
                key: ValueKey('step-$number-${status.name}'),
                style: TextStyle(
                  color: status == _StepStatus.current
                      ? onPrimary
                      : colors.muted,
                  fontSize: 11,
                  fontWeight: status == _StepStatus.current
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
