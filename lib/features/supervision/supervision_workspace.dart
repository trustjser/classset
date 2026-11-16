part of 'supervision_page.dart';

Color _headerBorder(BuildContext context) => context.appColors.border;
Color _headerDivider(BuildContext context) => context.appColors.tableDivider;
Color _headerCanvas(BuildContext context) => context.appColors.canvas;
Color _headerInput(BuildContext context) => context.appColors.tableHeader;
Color _headerInk(BuildContext context) => context.appColors.ink;
Color _headerText(BuildContext context) => context.appColors.inkSecondary;
Color _headerSecondary(BuildContext context) => context.appColors.inkSecondary;
Color _headerMuted(BuildContext context) => context.appColors.muted;

Color _headerBlue(BuildContext context) => context.appColors.blue;

Color _headerBlueHover(BuildContext context) =>
    Color.lerp(context.appColors.blue, context.appColors.ink, .1)!;

Color _headerBadgeFill(BuildContext context) => context.appColors.selectedBlue;

Color _headerBadgeInk(BuildContext context) => context.appColors.blue;

class _DutyPageHeading extends StatelessWidget {
  const _DutyPageHeading({required this.action});
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        '带班安排',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _headerInk(context),
        ),
      );
      final subtitle = Text(
        '为课后时段安排带班教师，与课表协调后生效',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: _headerSecondary(context)),
      );
      final titleLine = constraints.maxWidth >= 720
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                title,
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: subtitle,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, subtitle],
            );
      if (action == null) return titleLine;
      return OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.start,
        spacing: 16,
        overflowSpacing: 12,
        children: [titleLine, action!],
      );
    },
  );
}

class _DutyControlPanel extends StatelessWidget {
  const _DutyControlPanel({
    required this.primary,
    required this.filters,
    required this.horizontalPadding,
  });
  final Widget primary;
  final Widget filters;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('duty-control-panel'),
    decoration: BoxDecoration(
      color: context.appColors.surface,
      border: Border(bottom: BorderSide(color: _headerBorder(context))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            0,
          ),
          child: primary,
        ),
        Container(
          margin: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: _headerDivider(context))),
          ),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            12,
            horizontalPadding,
            16,
          ),
          child: filters,
        ),
      ],
    ),
  );
}

class _DutyCommandGroup extends StatelessWidget {
  const _DutyCommandGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

class _DutyCommand extends StatelessWidget {
  const _DutyCommand({
    required this.label,
    required this.onPressed,
    this.count,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final int? count;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => f.FTappable(
    onPress: onPressed,
    builder: (context, variants, child) => Opacity(
      opacity: onPressed == null ? .42 : 1,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: variants.contains(f.FTappableVariant.hovered)
              ? context.appColors.surface
              : null,
          borderRadius: BorderRadius.circular(8),
          border: variants.contains(f.FTappableVariant.focused)
              ? Border.all(color: _headerBlue(context))
              : Border.all(color: _headerBorder(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: _headerSecondary(context)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: _headerText(context),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 7),
              Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: _headerBadgeFill(context),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _headerBadgeInk(context),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _DutyOutlinedIconButton extends StatelessWidget {
  const _DutyOutlinedIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 32,
    decoration: BoxDecoration(
      color: context.appColors.surface,
      border: Border.all(color: _headerBorder(context)),
      borderRadius: BorderRadius.circular(8),
    ),
    alignment: Alignment.center,
    child: AppIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 16,
      foregroundColor: onPressed == null
          ? _headerMuted(context)
          : _headerSecondary(context),
    ),
  );
}

class _DutyCreatePostButton extends StatelessWidget {
  const _DutyCreatePostButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => f.FTappable(
    onPress: onPressed,
    builder: (context, variants, child) => Opacity(
      opacity: onPressed == null ? .42 : 1,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: variants.contains(f.FTappableVariant.hovered)
              ? _headerBlueHover(context)
              : _headerBlue(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: 14,
              color: context.appColors.onAccent,
            ),
            const SizedBox(width: 6),
            Text(
              '创建岗位',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.appColors.onAccent,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DutyVersionPicker extends StatelessWidget {
  const _DutyVersionPicker({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => f.FTheme(
    data: f.FTheme.of(context).copyWith(
      selectStyle: f.FSelectStyleDelta.delta(
        fieldStyles: f.FVariantsDelta.delta([
          f.FVariantOperation.match(
            {f.FTextFieldSizeVariant.md},
            f.FTextFieldStyleDelta.delta(
              constraints: const BoxConstraints(minHeight: 28),
              contentPadding: .value(
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              ),
              color: f.FVariantsValueDelta.delta([
                f.FVariantValueDeltaOperation.all(_headerInput(context)),
              ]),
              contentTextStyle: f.FVariantsDelta.delta([
                f.FVariantOperation.base(
                  f.TextStyleDelta.delta(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _headerText(context),
                  ),
                ),
              ]),
              border: f.FVariantsValueDelta.delta([
                f.FVariantValueDeltaOperation.base(
                  forui_material.OutlineInputBorder(
                    borderSide: BorderSide(color: _headerBorder(context)),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    ),
    // ForUI's input decorator reserves four pixels below the painted field.
    // Center the visible outline, rather than the decorator's full layout box.
    child: Transform.translate(offset: const Offset(0, 2), child: child),
  );
}

class _DutyProgress extends StatelessWidget {
  const _DutyProgress({
    required this.assigned,
    required this.total,
    required this.dirty,
  });
  final int assigned;
  final int total;
  final bool dirty;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '已安排 $assigned / $total 个岗位${dirty ? '，有未保存的修改' : ''}',
    child: Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$assigned / $total',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.appColors.blue,
          ),
        ),
        SizedBox(
          width: MediaQuery.sizeOf(context).width < 560 ? 80 : 140,
          child: f.FDeterminateProgress(
            value: total == 0 ? 0 : assigned / total,
            semanticsLabel: '已安排 $assigned / $total 个岗位',
            style: f.FDeterminateProgressStyleDelta.delta(
              trackDecoration: .value(
                BoxDecoration(
                  color: context.appColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              fillDecoration: .value(
                BoxDecoration(
                  color: context.appColors.blue,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
        Text(
          '个岗位已安排',
          style: TextStyle(fontSize: 12, color: context.appColors.inkSecondary),
        ),
        if (dirty)
          Text(
            '· 有未保存的修改',
            style: TextStyle(fontSize: 12, color: context.appColors.warning),
          ),
      ],
    ),
  );
}

class _DutyPeriodCard extends StatelessWidget {
  const _DutyPeriodCard({
    required this.title,
    required this.time,
    required this.stage,
  });
  final String title;
  final String? time;
  final String? stage;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 136),
    margin: const EdgeInsets.only(right: 12),
    decoration: BoxDecoration(
      color: context.appColors.tableHeader,
      borderRadius: BorderRadius.circular(8),
      boxShadow: context.appColors.cardShadow,
    ),
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned(
          left: 0,
          top: 16,
          child: Container(
            width: 3,
            height: 24,
            decoration: BoxDecoration(
              color: context.appColors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.ink,
                  ),
                ),
                if (time != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    time!,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.inkSecondary,
                    ),
                  ),
                ],
                if (stage != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      border: Border.all(color: context.appColors.border),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      stage!,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.inkSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
