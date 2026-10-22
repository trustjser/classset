import 'dart:async';
import 'dart:ui' as ui;

import 'package:class_set/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' as forui_material;

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.responsiveActions = false,
    this.actionsFlex = 1,
    super.key,
  }) : assert(actionsFlex > 0);

  final String title;
  final String subtitle;
  final List<Widget> actions;
  final bool responsiveActions;
  final int actionsFlex;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    if (!responsiveActions) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: heading),
          for (final action in actions) ...[const SizedBox(width: 8), action],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWrap = Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: actions,
        );
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                actionWrap,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 1, child: heading),
            const SizedBox(width: 20),
            Expanded(
              flex: actionsFlex,
              child: Align(alignment: Alignment.centerRight, child: actionWrap),
            ),
          ],
        );
      },
    );
  }
}

class AppSectionPanel extends StatelessWidget {
  const AppSectionPanel({
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(12),
    this.headerPadding,
    this.headerDivider = false,
    this.expandChild = false,
    this.showBorder = true,
    super.key,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? headerPadding;
  final bool headerDivider;
  final bool expandChild;
  final bool showBorder;

  @override
  Widget build(BuildContext context) => AppSurface(
    showBorder: showBorder,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: headerPadding ?? const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        if (title != null && headerDivider) const Divider(height: 1),
        if (expandChild)
          Expanded(
            child: Padding(padding: padding, child: child),
          )
        else
          Padding(padding: padding, child: child),
      ],
    ),
  );
}

/// A reusable Forui-token surface for cards and summary blocks.
class AppSurface extends StatelessWidget {
  const AppSurface({
    required this.child,
    this.showBorder = true,
    this.backgroundColor,
    super.key,
  });

  final Widget child;
  final bool showBorder;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: backgroundColor ?? AppTheme.forui.colors.card,
      border: showBorder
          ? Border.all(color: AppTheme.forui.colors.border)
          : null,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: child,
    ),
  );
}

/// Compact hierarchy row used by selectors and navigation trees.
class AppTreeTile extends StatelessWidget {
  const AppTreeTile({
    required this.title,
    required this.leading,
    required this.onTap,
    this.isSelected = false,
    this.selectedBackground = AppTheme.selectedBlue,
    this.selectedForeground,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.height = 38,
    super.key,
  });

  final Widget title;
  final Widget leading;
  final VoidCallback onTap;
  final bool isSelected;

  /// 选中态底色（默认品牌蓝淡底）；范围树编辑中学段用绿色淡底。
  final Color selectedBackground;

  /// 选中态文字色；为 null 时沿用 title 自身样式。
  final Color? selectedForeground;
  final EdgeInsetsGeometry contentPadding;
  final double height;

  @override
  Widget build(BuildContext context) {
    final showSelectedStyle = isSelected && selectedForeground != null;
    return Material(
      color: isSelected ? selectedBackground : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: contentPadding,
            child: Row(
              children: [
                leading,
                const SizedBox(width: 8),
                Expanded(
                  child: showSelectedStyle
                      ? DefaultTextStyle.merge(
                          style: TextStyle(color: selectedForeground),
                          child: title,
                        )
                      : title,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppDataTableHeader extends StatelessWidget {
  const AppDataTableHeader({
    required this.children,
    this.height = 40,
    this.textColor = AppTheme.ink,
    this.backgroundColor = AppTheme.tableHeader,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.textStyle,
    super.key,
  });

  final List<Widget> children;
  final double height;
  final Color textColor;
  final Color backgroundColor;
  final EdgeInsetsGeometry padding;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: padding,
    color: backgroundColor,
    child: DefaultTextStyle(
      style:
          textStyle ??
          TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            height: 17 / 12,
          ),
      child: Row(children: children),
    ),
  );
}

class AppInlineMessage extends StatelessWidget {
  const AppInlineMessage({
    required this.message,
    this.icon = Icons.info_outline,
    this.backgroundColor = AppTheme.selectedBlue,
    super.key,
  });

  final String message;
  final IconData icon;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: AppTheme.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppTheme.ink, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

/// Shared empty state for feature pages and management dialogs.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppTheme.muted),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

/// Tap or hover to show a short contextual explanation.
class AppHelpTooltip extends StatelessWidget {
  const AppHelpTooltip({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    triggerMode: TooltipTriggerMode.tap,
    child: const Icon(Icons.help_outline, size: 14, color: AppTheme.helpIcon),
  );
}

class AppSummaryMetricCard extends StatelessWidget {
  const AppSummaryMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => AppSurface(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppTheme.blue),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: valueColor ?? AppTheme.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class AppWeekdaySelector extends StatelessWidget {
  const AppWeekdaySelector({
    required this.selectedWeekdays,
    required this.onChanged,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.labels = const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
    this.compact = false,
    this.fontSize = 12,
    super.key,
  }) : assert(weekdays.length == labels.length);

  final Set<int> selectedWeekdays;
  final ValueChanged<Set<int>> onChanged;
  final List<int> weekdays;
  final List<String> labels;
  final bool compact;

  /// 紧凑模式（竖排勾选列）文案字号；设计稿上课天卡片为 13px。
  final double fontSize;

  @override
  Widget build(BuildContext context) => compact
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < weekdays.length; index++)
              _CompactWeekdayOption(
                label: labels[index],
                fontSize: fontSize,
                isSelected: selectedWeekdays.contains(weekdays[index]),
                onChanged: () {
                  final next = {...selectedWeekdays};
                  next.contains(weekdays[index])
                      ? next.remove(weekdays[index])
                      : next.add(weekdays[index]);
                  onChanged(next);
                },
              ),
          ],
        )
      : Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < weekdays.length; index++)
              _WeekdayOption(
                label: labels[index],
                isSelected: selectedWeekdays.contains(weekdays[index]),
                onTap: () {
                  final next = {...selectedWeekdays};
                  next.contains(weekdays[index])
                      ? next.remove(weekdays[index])
                      : next.add(weekdays[index]);
                  onChanged(next);
                },
              ),
          ],
        );
}

class _CompactWeekdayOption extends StatelessWidget {
  const _CompactWeekdayOption({
    required this.label,
    required this.isSelected,
    required this.onChanged,
    this.fontSize = 12,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onChanged;
  final double fontSize;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: InkWell(
      onTap: onChanged,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: FCheckbox(value: isSelected, onChange: (_) => onChanged()),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: fontSize)),
        ],
      ),
    ),
  );
}

class _WeekdayOption extends StatelessWidget {
  const _WeekdayOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    checked: isSelected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 92, minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.selectedBlue : Colors.white,
          border: Border.all(
            color: isSelected ? AppTheme.blue : AppTheme.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 17,
              color: isSelected ? AppTheme.blue : AppTheme.muted,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.blue : AppTheme.ink,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AppNumberStepper extends StatelessWidget {
  const AppNumberStepper({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 9,
    this.suffix = '节',
    this.compact = false,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final String suffix;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: AppTheme.border),
      borderRadius: BorderRadius.circular(9),
      color: Colors.white,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FButton.icon(
          variant: .ghost,
          size: .sm,
          semanticsTooltip: '减少',
          onPress: value <= min ? null : () => onChanged(value - 1),
          child: const Icon(Icons.remove, size: 16),
        ),
        SizedBox(
          width: compact ? 38 : 48,
          child: Text(
            '$value$suffix',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        FButton.icon(
          variant: .ghost,
          size: .sm,
          semanticsTooltip: '增加',
          onPress: value >= max ? null : () => onChanged(value + 1),
          child: const Icon(Icons.add, size: 16),
        ),
      ],
    ),
  );
}

/// Shared Forui button adapters for actions across feature modules.
class AppOutlineButton extends StatelessWidget {
  const AppOutlineButton({
    required this.onPressed,
    required this.child,
    super.key,
  }) : icon = null;

  const AppOutlineButton.icon({
    required this.onPressed,
    required this.icon,
    required Widget label,
    super.key,
  }) : child = label;

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => _AppForuiButton(
    onPressed: onPressed,
    icon: icon,
    variant: .outline,
    child: child,
  );
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    required this.onPressed,
    required this.child,
    this.size = FButtonSizeVariant.sm,
    super.key,
  }) : icon = null;

  const AppPrimaryButton.icon({
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.size = FButtonSizeVariant.sm,
    super.key,
  }) : child = label;

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final FButtonSizeVariant size;

  @override
  Widget build(BuildContext context) => _AppForuiButton(
    onPressed: onPressed,
    icon: icon,
    variant: .primary,
    size: size,
    child: child,
  );
}

class AppGhostButton extends StatelessWidget {
  const AppGhostButton({
    required this.onPressed,
    required this.child,
    this.size = FButtonSizeVariant.sm,
    super.key,
  }) : icon = null;

  const AppGhostButton.icon({
    required this.onPressed,
    required this.icon,
    required Widget label,
    this.size = FButtonSizeVariant.sm,
    super.key,
  }) : child = label;

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final FButtonSizeVariant size;

  @override
  Widget build(BuildContext context) => _AppForuiButton(
    onPressed: onPressed,
    icon: icon,
    variant: .ghost,
    size: size,
    child: child,
  );
}

class AppDestructiveButton extends StatelessWidget {
  const AppDestructiveButton({
    required this.onPressed,
    required this.child,
    this.size = FButtonSizeVariant.sm,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final FButtonSizeVariant size;

  @override
  Widget build(BuildContext context) => _AppForuiButton(
    onPressed: onPressed,
    variant: .destructive,
    size: size,
    child: child,
  );
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.iconSize = 14,
    this.foregroundColor = AppTheme.muted,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double iconSize;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => FButton.icon(
    variant: .ghost,
    size: .xs,
    onPress: onPressed,
    semanticsLabel: tooltip,
    semanticsTooltip: tooltip,
    child: Icon(icon, size: iconSize, color: foregroundColor),
  );
}

/// A small interactive pill for compact choices and schedule cells.
class AppActionPill extends StatelessWidget {
  const AppActionPill({
    required this.child,
    required this.onPressed,
    this.selected = false,
    this.destructive = false,
    this.onSecondaryPressed,
    this.onLongPressed,
    this.tooltip,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final bool destructive;
  final VoidCallback? onSecondaryPressed;
  final VoidCallback? onLongPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => FButton(
    variant: destructive
        ? FButtonVariant.destructive
        : selected
        ? FButtonVariant.secondary
        : FButtonVariant.outline,
    size: FButtonSizeVariant.xs,
    mainAxisSize: MainAxisSize.min,
    onPress: onPressed,
    onSecondaryPress: onSecondaryPressed,
    onLongPress: onLongPressed,
    semanticsTooltip: tooltip,
    child: child,
  );
}

/// A compact Forui badge for status and category labels.
class AppForuiBadge extends StatelessWidget {
  const AppForuiBadge({required this.child, this.accent = false, super.key});

  final Widget child;
  final bool accent;

  @override
  Widget build(BuildContext context) => FBadge(
    variant: accent ? FBadgeVariant.primary : FBadgeVariant.secondary,
    child: child,
  );
}

/// A Forui checkbox that can be composed with a feature-specific row layout.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    required this.value,
    required this.onChanged,
    this.label,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => FCheckbox(
    value: value,
    onChange: onChanged,
    label: label,
    enabled: enabled,
  );
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    required this.onPressed,
    required this.child,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _AppForuiButton(onPressed: onPressed, variant: .secondary, child: child);
}

class _AppForuiButton extends StatelessWidget {
  const _AppForuiButton({
    required this.onPressed,
    required this.child,
    required this.variant,
    this.size = FButtonSizeVariant.sm,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final FButtonVariant variant;
  final FButtonSizeVariant size;

  @override
  Widget build(BuildContext context) => FButton(
    variant: variant,
    size: size,
    mainAxisSize: .min,
    onPress: onPressed,
    prefix: icon,
    child: child,
  );
}

/// Forui dialog surface with a consistent title, body, and action layout.
///
/// 内容超出弹窗可视高度时自动滚动，避免 BOTTOM OVERFLOWED；
/// 内部包一层透明 Material，使 InkWell 等墨水效果组件在弹窗内可用。
class AppDialog extends StatelessWidget {
  const AppDialog({
    required this.title,
    required this.content,
    this.actions = const [],
    this.padding = const EdgeInsets.all(24),
    this.titleGap = 16,
    this.actionsGap = 20,
    this.maxWidth = 560,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;
  final double titleGap;
  final double actionsGap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => FDialog(
    constraints: BoxConstraints(minWidth: 280, maxWidth: maxWidth),
    builder: (context, style) => Padding(
      padding: padding,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              DefaultTextStyle(style: style.titleTextStyle, child: title!),
              SizedBox(height: titleGap),
            ],
            if (content != null)
              Flexible(
                child: SingleChildScrollView(
                  child: DefaultTextStyle(
                    style: style.bodyTextStyle,
                    child: content!,
                  ),
                ),
              ),
            if (actions.isNotEmpty) ...[
              SizedBox(height: actionsGap),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showFDialog<T>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: barrierDismissible,
  routeStyle: FDialogRouteStyle(
    barrierFilter: (context, animation) => ui.ColorFilter.mode(
      Color.lerp(Colors.transparent, AppTheme.dialogBarrier, animation)!,
      ui.BlendMode.srcOver,
    ),
  ),
  builder: (context, style, animation) => builder(context),
);

class AppDialogTitle extends StatelessWidget {
  const AppDialogTitle({required this.title, required this.onClose, super.key});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: AppTheme.ink,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 23 / 16,
          ),
        ),
      ),
      AppIconButton(
        onPressed: onClose,
        tooltip: '关闭',
        icon: Icons.close,
        iconSize: 16,
      ),
    ],
  );
}

class AppLabeledFieldRow extends StatelessWidget {
  const AppLabeledFieldRow({
    required this.label,
    required this.child,
    this.labelWidth = 110,
    this.labelHelp,
    super.key,
  });

  final String label;
  final Widget child;
  final double labelWidth;
  final String? labelHelp;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final labelWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.inkSecondary,
                fontSize: 13,
                height: 19 / 13,
              ),
            ),
          ),
          if (labelHelp != null) ...[
            const SizedBox(width: 4),
            AppHelpTooltip(message: labelHelp!),
          ],
        ],
      );
      if (constraints.maxWidth < labelWidth + 250) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [labelWidget, const SizedBox(height: 6), child],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: labelWidth, child: labelWidget),
          Expanded(child: child),
        ],
      );
    },
  );
}

class AppRadioOption<T> extends StatelessWidget {
  const AppRadioOption({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
    this.enabled = true,
    this.compact = false,
    this.fontSize = 13,
    this.textLineHeight,
    this.indicatorSize = 16,
    super.key,
  });

  final T value;
  final T groupValue;
  final String label;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final bool compact;
  final double fontSize;
  final double? textLineHeight;
  final double indicatorSize;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final labelStyle = TextStyle(
      color: enabled ? AppTheme.ink : AppTheme.muted,
      fontSize: fontSize,
      height: textLineHeight ?? (compact ? 19 / fontSize : null),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 4, horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FRadio(
            value: selected,
            semanticsLabel: label,
            enabled: enabled,
            style: .delta(
              padding: .value(EdgeInsets.all((indicatorSize - 8) / 2)),
              indicatorSize: 8,
            ),
            onChange: (next) {
              if (next) onChanged(value);
            },
          ),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => onChanged(value) : null,
            child: Text(label, maxLines: 1, softWrap: false, style: labelStyle),
          ),
        ],
      ),
    );
  }
}

class AppRadioIndicator<T> extends StatelessWidget {
  const AppRadioIndicator({
    required this.value,
    required this.groupValue,
    required this.label,
    required this.onChanged,
    this.enabled = true,
    this.indicatorSize = 14,
    this.hitTargetSize = 24,
    super.key,
  });

  final T value;
  final T groupValue;
  final String label;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final double indicatorSize;
  final double hitTargetSize;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return SizedBox(
      width: hitTargetSize,
      height: hitTargetSize,
      child: FRadio(
        value: selected,
        semanticsLabel: label,
        enabled: enabled,
        style: .delta(
          padding: .value(EdgeInsets.all((indicatorSize - 8) / 2)),
          indicatorSize: 8,
        ),
        onChange: (next) {
          if (next && !selected) onChanged(value);
        },
      ),
    );
  }
}

/// TDesign-styled Forui calendar field with an inclusive selectable date range.
class AppDateField extends StatelessWidget {
  const AppDateField({
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    required this.hint,
    required this.format,
    this.height = 35,
    super.key,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;
  final String hint;
  final String Function(DateTime value) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final boundedToday = today.isBefore(firstDate)
        ? firstDate
        : today.isAfter(lastDate)
        ? lastDate
        : today;

    return SizedBox(
      height: height,
      child: FDateField.calendar(
        size: .sm,
        hint: hint,
        textAlignVertical: TextAlignVertical.center,
        style: FDateFieldStyleDelta.delta(
          fieldStyles: FVariantsDelta.delta([
            FVariantOperation.match(
              {FTextFieldSizeVariant.sm},
              FTextFieldStyleDelta.delta(
                contentPadding: .value(
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8.5),
                ),
              ),
            ),
          ]),
        ),
        format: (context, value, format) => this.format(value),
        selectionControl: FDateSelectionControl.liftedSingle(
          value: value,
          toggleable: false,
          onChange: onChanged,
        ),
        calendar: FDateFieldGridCalendarProperties(
          control: FGridCalendarControl(
            start: firstDate,
            today: boundedToday,
            end: lastDate,
            initial: value ?? firstDate,
          ),
          headerBuilder: _appDateFieldCalendarHeader,
        ),
        prefixBuilder: (context, style, variants) => const SizedBox.shrink(),
        suffixBuilder: (context, style, variants) => const SizedBox.shrink(),
      ),
    );
  }
}

Widget _appDateFieldCalendarHeader(
  BuildContext context,
  FGridCalendarController controller,
  FDateSelectionController<Object?> _,
  Widget _,
) {
  final label = switch (controller.type) {
    FCalendarPickerGridType.day =>
      '${controller.currentMonth.year}年${controller.currentMonth.month}月',
    FCalendarPickerGridType.month => '${controller.currentMonth.year}年',
    FCalendarPickerGridType.year => '${controller.currentMonth.year}年',
  };
  final previous = switch (controller.type) {
    FCalendarPickerGridType.day =>
      controller.day.hasPrevious ? controller.day.previous : null,
    FCalendarPickerGridType.month =>
      controller.month.hasPrevious ? controller.month.previous : null,
    FCalendarPickerGridType.year =>
      controller.year.hasPrevious ? controller.year.previous : null,
  };
  final next = switch (controller.type) {
    FCalendarPickerGridType.day =>
      controller.day.hasNext ? controller.day.next : null,
    FCalendarPickerGridType.month =>
      controller.month.hasNext ? controller.month.next : null,
    FCalendarPickerGridType.year =>
      controller.year.hasNext ? controller.year.next : null,
  };

  Widget navigationButton({
    required String label,
    required VoidCallback? onPressed,
    required Widget icon,
  }) => FButton.icon(
    size: .xs,
    variant: .ghost,
    style: .delta(
      iconContentStyle: .delta(
        constraints: const BoxConstraints.tightFor(width: 22, height: 22),
        padding: .value(EdgeInsets.zero),
      ),
    ),
    onPress: onPressed,
    semanticsLabel: label,
    child: icon,
  );

  return Row(
    children: [
      navigationButton(
        label: '上一个日期范围',
        onPressed: previous,
        icon: context.theme.icons.chevronLeft(context),
      ),
      Expanded(
        child: FTappable(
          semanticsLabel: '切换日期视图',
          onPress: controller.cycle,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: AppTheme.ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
      navigationButton(
        label: '下一个日期范围',
        onPressed: next,
        icon: context.theme.icons.chevronRight(context),
      ),
    ],
  );
}

/// Forui [FSelect] 适配器：替代 Material DropdownButtonFormField。
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.enabled = true,
    this.contentGroupId,
    this.searchable = false,
    this.searchHint = '搜索选项',
    super.key,
  });

  /// 选项：label → value。
  final Map<String, T> items;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? hint;
  final bool enabled;
  final Object? contentGroupId;
  final bool searchable;
  final String searchHint;

  @override
  Widget build(BuildContext context) {
    final control = FSelectControl.lifted(value: value, onChange: onChanged);
    final fieldLabel = label == null ? null : Text(label!);
    if (!searchable) {
      return FSelect<T>(
        items: items,
        control: control,
        enabled: enabled,
        label: fieldLabel,
        hint: hint,
        contentGroupId: contentGroupId,
      );
    }

    return FSelect<T>.search(
      items: items,
      filter: (query) {
        final normalizedQuery = query.trim().toLowerCase();
        return items.entries
            .where((entry) => entry.key.toLowerCase().contains(normalizedQuery))
            .map((entry) => entry.value);
      },
      searchFieldProperties: FSelectSearchFieldProperties(hint: searchHint),
      control: control,
      enabled: enabled,
      label: fieldLabel,
      hint: hint,
      contentGroupId: contentGroupId,
    );
  }
}

/// 弹出菜单项。
class AppMenuItem {
  const AppMenuItem({
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.shortcut,
    this.selected = false,
    this.enabled = true,
  });

  final String label;

  /// false 时菜单项呈禁用态（onPress 置空、文字变灰）。
  final bool enabled;
  final VoidCallback onPressed;
  final bool destructive;

  /// 右侧快捷键提示（设计稿：11px #A6A6A6）。
  final String? shortcut;

  /// 当前选中（左侧显示对勾、底色高亮）。
  final bool selected;
}

/// 设计稿规格的菜单项：30px 高、13px 文案、右侧 11px 快捷键、圆角 4。
class AppMenuTile extends StatelessWidget with FItemMixin {
  const AppMenuTile({required this.item, super.key});

  final AppMenuItem item;

  @override
  Widget build(BuildContext context) {
    final foreground = item.destructive
        ? AppTheme.destructive
        : item.enabled
        ? AppTheme.ink
        : AppTheme.muted;
    return FItem.raw(
      variant: item.destructive ? .destructive : .primary,
      selected: item.selected,
      style: .delta(rawContentStyle: .delta(padding: .value(EdgeInsets.zero))),
      onPress: item.enabled ? item.onPressed : null,
      child: Container(
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: item.selected ? AppTheme.selectedBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            if (item.selected)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.check, size: 13, color: AppTheme.blue),
              ),
            Text(item.label, style: TextStyle(fontSize: 13, color: foreground)),
            const Spacer(),
            if (item.shortcut != null)
              Text(
                item.shortcut!,
                style: const TextStyle(fontSize: 11, color: Color(0xFFA6A6A6)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Forui [FPopoverMenu] 适配器：替代 Material PopupMenuButton。
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({required this.items, required this.child, super.key});

  final List<AppMenuItem> items;
  final Widget child;

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    menuBuilder: (context, controller, menu) => [
      FItemGroup(
        divider: .none,
        children: [
          for (final item in items)
            AppMenuTile(
              item: AppMenuItem(
                label: item.label,
                destructive: item.destructive,
                shortcut: item.shortcut,
                selected: item.selected,
                onPressed: () {
                  unawaited(controller.hide());
                  item.onPressed();
                },
              ),
            ),
        ],
      ),
    ],
    builder: (context, controller, child) => FTappable(
      semanticsLabel: '打开菜单',
      onPress: () => unawaited(controller.toggle()),
      child: child,
    ),
    child: child,
  );
}

/// TDesign-mapped Forui form field adapter shared by edit dialogs and forms.
class AppTextFormField extends StatelessWidget {
  const AppTextFormField({
    this.controller,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.autofocus = false,
    this.maxLines = 1,
    this.size = FTextFieldSizeVariant.md,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.dense = false,
    this.borderless = false,
    super.key,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final bool autofocus;
  final int? maxLines;
  final FTextFieldSizeVariant size;

  /// 文本对齐（时间输入用居中）。
  final TextAlign textAlign;

  /// 文本垂直对齐。
  final TextAlignVertical? textAlignVertical;

  /// 紧凑高度（约 28px，用于节次时间等密集输入）。
  final bool dense;

  /// Removes the border and horizontal padding for inline numeric fields.
  final bool borderless;

  @override
  Widget build(BuildContext context) {
    final field = FTextFormField(
      key: key,
      size: size,
      style: dense || borderless
          ? .delta(
              border: borderless
                  ? FVariantsValueDelta.delta([
                      FVariantValueDeltaOperation.all(
                        forui_material.InputBorder.none,
                      ),
                    ])
                  : null,
              contentPadding: .value(
                borderless
                    ? const EdgeInsets.symmetric(vertical: 7)
                    : const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              ),
            )
          : const FTextFieldStyleDelta.context(),
      control: FTextFieldControl.managed(
        controller: controller,
        initial: controller == null
            ? TextEditingValue(text: initialValue ?? '')
            : null,
        onChange: onChanged == null ? null : (value) => onChanged!(value.text),
      ),
      label: decoration.labelText == null ? null : Text(decoration.labelText!),
      hint: decoration.hintText,
      keyboardType: keyboardType,
      autofocus: autofocus,
      maxLines: maxLines,
      textAlign: textAlign,
      textAlignVertical: textAlignVertical,
      onSubmit: onFieldSubmitted,
      validator: validator,
    );
    final prefix = decoration.prefixIcon;
    final decoratedField = prefix == null
        ? field
        : Row(
            children: [
              prefix,
              const SizedBox(width: 8),
              Expanded(child: field),
            ],
          );
    final suffix = decoration.suffixText;
    if (suffix == null) return decoratedField;
    return Row(
      children: [
        Expanded(child: decoratedField),
        const SizedBox(width: 8),
        Text(suffix, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
