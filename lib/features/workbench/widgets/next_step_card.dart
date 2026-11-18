import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/workbench/workbench_data.dart';
import 'package:flutter/material.dart';

/// 「接下来」：当前步骤引导卡（浅蓝底主操作区，支持在已解锁步骤范围内回看调整）。
class NextStepCard extends StatefulWidget {
  const NextStepCard({
    required this.step,
    required this.copy,
    required this.onAction,
    this.currentStep,
    this.onSelectStep,
    this.comingSoonHint,
    super.key,
  });

  final PreparationStep step;
  final StepCopy copy;

  /// 实际进度所在的当前步骤；若传入且与 [step] 不同，则展示「回到当前进度」快捷入口。
  final PreparationStep? currentStep;

  /// 切换查看指定已解锁步骤的回调。
  final ValueChanged<PreparationStep>? onSelectStep;

  /// 为 null 表示该步骤尚未实现，仅展示提示。
  final VoidCallback? onAction;
  final String? comingSoonHint;

  @override
  State<NextStepCard> createState() => _NextStepCardState();
}

class _NextStepCardState extends State<NextStepCard> {
  bool _hovered = false;
  int _slideDirection = 1;

  @override
  void didUpdateWidget(covariant NextStepCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.index != oldWidget.step.index) {
      _slideDirection = widget.step.index > oldWidget.step.index ? 1 : -1;
    }
  }

  Widget _buildDirectionalTransition(
    Widget child,
    Animation<double> animation,
  ) {
    final isIncoming =
        child.key == ValueKey<int>(widget.step.number) ||
        child.key == ValueKey<String>(widget.copy.title) ||
        child.key == ValueKey<String>('desc-${widget.step.name}') ||
        child.key == ValueKey<String>(widget.copy.meta) ||
        child.key == ValueKey<String>('action-${widget.copy.actionLabel}');
    final offset = isIncoming
        ? Offset(0.08 * _slideDirection, 0)
        : Offset(-0.08 * _slideDirection, 0);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: offset, end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: AppTheme.entranceCurve),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final feedbackDuration = AppTheme.motionDuration(
      context,
      AppTheme.feedbackDuration,
    );
    final transitionDuration = AppTheme.motionDuration(
      context,
      AppTheme.transitionDuration,
    );
    final maxUnlockedIndex = (widget.currentStep ?? widget.step).index;
    final isPreviewingDoneStep =
        widget.currentStep != null && widget.step.index < maxUnlockedIndex;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: feedbackDuration,
        curve: AppTheme.entranceCurve,
        decoration: BoxDecoration(
          color: _hovered
              ? Color.alphaBlend(
                  colors.blue.withValues(alpha: 0.04),
                  colors.selectedBlue,
                )
              : colors.selectedBlue,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
            color: colors.blue.withValues(alpha: _hovered ? 0.34 : 0.12),
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppBadge(
                  label: isPreviewingDoneStep ? '回看调整' : '接下来',
                  foreground: colors.blue,
                  background: colors.surface,
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: transitionDuration,
                  transitionBuilder: _buildDirectionalTransition,
                  child: Text(
                    '第 ${widget.step.number} 步',
                    key: ValueKey<int>(widget.step.number),
                    style: TextStyle(
                      color: colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (isPreviewingDoneStep && widget.onSelectStep != null)
                  _StepSwitchPill(
                    label: '回到当前进度',
                    onTap: () => widget.onSelectStep!(widget.currentStep!),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: transitionDuration,
              transitionBuilder: _buildDirectionalTransition,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previousChildren, ?currentChild],
              ),
              child: Text(
                widget.copy.title,
                key: ValueKey<String>(widget.copy.title),
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: transitionDuration,
              transitionBuilder: _buildDirectionalTransition,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topLeft,
                children: [...previousChildren, ?currentChild],
              ),
              child: Text(
                widget.copy.description,
                key: ValueKey<String>('desc-${widget.step.name}'),
                style: TextStyle(
                  color: colors.inkSecondary,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: transitionDuration,
              transitionBuilder: _buildDirectionalTransition,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previousChildren, ?currentChild],
              ),
              child: Text(
                widget.copy.meta,
                key: ValueKey<String>(widget.copy.meta),
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                AnimatedSwitcher(
                  duration: transitionDuration,
                  transitionBuilder: _buildDirectionalTransition,
                  child: KeyedSubtree(
                    key: ValueKey<String>('action-${widget.copy.actionLabel}'),
                    child: AppPrimaryButton(
                      onPressed: widget.onAction,
                      child: Text(widget.copy.actionLabel),
                    ),
                  ),
                ),
                if (widget.comingSoonHint != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      widget.comingSoonHint!,
                      style: TextStyle(color: colors.muted, fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepSwitchPill extends StatelessWidget {
  const _StepSwitchPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              color: colors.blue,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
