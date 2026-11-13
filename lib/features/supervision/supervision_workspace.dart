part of 'supervision_page.dart';

class _DutyPageHeading extends StatelessWidget {
  const _DutyPageHeading({required this.action});
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        '带班安排',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: context.appColors.ink,
        ),
      );
      final subtitle = Text(
        '为课后时段安排带班教师，与课表协调后生效',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.appColors.inkSecondary),
      );
      return Row(
        children: [
          Expanded(
            child: constraints.maxWidth >= 720
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      title,
                      const SizedBox(width: 12),
                      Expanded(child: subtitle),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, subtitle],
                  ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      );
    },
  );
}

class _DutyControlPanel extends StatelessWidget {
  const _DutyControlPanel({required this.primary, required this.filters});
  final Widget primary;
  final Widget filters;

  @override
  Widget build(BuildContext context) => AppSurface(
    key: const ValueKey('duty-control-panel'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: primary,
        ),
        Container(
          decoration: BoxDecoration(
            color: context.appColors.tableHeader,
            border: Border(top: BorderSide(color: context.appColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: context.appColors.canvas,
      border: Border.all(color: context.appColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Wrap(spacing: 2, runSpacing: 2, children: children),
  );
}

class _DutyCommand extends StatelessWidget {
  const _DutyCommand({
    required this.label,
    required this.onPressed,
    this.count,
    this.selected = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final int? count;
  final bool selected;
  @override
  Widget build(BuildContext context) => f.FTappable(
    onPress: onPressed,
    builder: (context, variants, child) => Opacity(
      opacity: onPressed == null ? .42 : 1,
      child: Container(
        constraints: const BoxConstraints(minHeight: 26),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected || variants.contains(f.FTappableVariant.hovered)
              ? context.appColors.surface
              : null,
          borderRadius: BorderRadius.circular(6),
          border: variants.contains(f.FTappableVariant.focused)
              ? Border.all(color: context.appColors.blue)
              : null,
          boxShadow: selected ? context.appColors.cardShadow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? context.appColors.ink
                    : context.appColors.inkSecondary,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 7),
              Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: context.appColors.blue,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: f.FTheme.of(context).colors.primaryForeground,
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
                f.FVariantValueDeltaOperation.all(context.appColors.surface),
              ]),
              contentTextStyle: f.FVariantsDelta.delta([
                f.FVariantOperation.base(
                  f.TextStyleDelta.delta(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
              border: f.FVariantsValueDelta.delta([
                f.FVariantValueDeltaOperation.base(
                  forui_material.OutlineInputBorder(
                    borderSide: BorderSide(color: context.appColors.border),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    ),
    child: child,
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
