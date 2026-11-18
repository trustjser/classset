part of 'supervision_page.dart';

Color _headerBorder(BuildContext context) => context.appColors.border;
Color _headerCanvas(BuildContext context) => context.appColors.canvas;
Color _headerInput(BuildContext context) => context.appColors.tableHeader;
Color _headerInk(BuildContext context) => context.appColors.ink;
Color _headerText(BuildContext context) => context.appColors.inkSecondary;
Color _headerSecondary(BuildContext context) => context.appColors.inkSecondary;
Color _headerMuted(BuildContext context) => context.appColors.muted;

Color _headerBlue(BuildContext context) => context.appColors.blue;

Color _headerBadgeFill(BuildContext context) => context.appColors.selectedBlue;

Color _headerBadgeInk(BuildContext context) => context.appColors.blue;

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
  Widget build(BuildContext context) => AppOutlineButton.icon(
    onPressed: onPressed,
    icon: icon == null
        ? null
        : Icon(icon, size: 14, color: _headerSecondary(context)),
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: _headerInk(context))),
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
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _headerBadgeInk(context),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _DutyOutlinedIconButton extends StatelessWidget {
  const _DutyOutlinedIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        border: Border.all(color: _headerBorder(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: AppIconButton(
        key: buttonKey,
        icon: icon,
        iconSize: 16,
        tooltip: tooltip,
        onPressed: onPressed,
        foregroundColor: onPressed == null
            ? _headerMuted(context)
            : _headerBlue(context),
      ),
    ),
  );
}

class _DutyCreatePostButton extends StatelessWidget {
  const _DutyCreatePostButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => AppPrimaryButton.icon(
    onPressed: onPressed,
    icon: Icon(Icons.add_rounded, size: 14, color: context.appColors.onAccent),
    label: const Text('创建岗位'),
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
                    fontSize: 12,
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
  const _DutyProgress({required this.assigned, required this.total});
  final int assigned;
  final int total;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '已安排 $assigned / $total 个岗位',
    child: Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '已安排',
          style: TextStyle(fontSize: 12, color: context.appColors.inkSecondary),
        ),
        Text(
          '$assigned / $total',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: context.appColors.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
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
                        fontSize: 12,
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
