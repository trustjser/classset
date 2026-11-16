import 'package:class_set/core/theme/app_appearance.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:flutter/material.dart';

class AppearanceSettingsDialog extends StatelessWidget {
  const AppearanceSettingsDialog({
    required this.appearance,
    required this.onChanged,
    super.key,
  });

  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onChanged;

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 760,
    title: const Text('主题与外观'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选择后立即生效，并自动保存到这台设备。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.appColors.inkSecondary)),
        const SizedBox(height: 24),
        Text('主题配色', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 600 ? 3 : 1;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final palette in AppPalette.values)
              SizedBox(width: width, child: _PaletteChoice(
                palette: palette,
                selected: appearance.palette == palette,
                isDark: Theme.of(context).brightness == Brightness.dark,
                onTap: () => onChanged(appearance.copyWith(palette: palette)),
              )),
          ]);
        }),
        const SizedBox(height: 24),
        Text('明暗模式', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final mode in AppAppearanceMode.values)
            AppActionPill(
              selected: appearance.mode == mode,
              onPressed: () => onChanged(appearance.copyWith(mode: mode)),
              child: Text(mode.label),
            ),
        ]),
      ],
    ),
    actions: [AppPrimaryButton(
      onPressed: () => Navigator.pop(context), child: const Text('完成'),
    )],
  );
}

class _PaletteChoice extends StatelessWidget {
  const _PaletteChoice({required this.palette, required this.selected,
    required this.isDark, required this.onTap});

  final AppPalette palette;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsFor(isDark, palette: palette);
    return Semantics(
      button: true,
      onTap: onTap,
      selected: selected,
      label: palette.label,
      excludeSemantics: true,
      child: Material(
        color: colors.canvas,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? colors.accent : context.appColors.border,
            width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 68,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colors.surface,
                  borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Container(width: 8, decoration: BoxDecoration(
                    color: colors.selection, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(height: 6, decoration: BoxDecoration(
                        color: colors.tableHeader, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(height: 8),
                      Row(children: [
                        Container(width: 34, height: 12, decoration: BoxDecoration(
                          color: colors.accent, borderRadius: BorderRadius.circular(4))),
                      ]),
                    ])),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text(palette.label, style: TextStyle(
                  color: colors.ink, fontSize: 14, fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18, color: selected ? colors.accent : colors.muted),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
