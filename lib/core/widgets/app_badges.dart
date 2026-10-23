import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 小号胶囊徽章：单周 / 双周、学段标签、公共时段标签等。
class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.label,
    this.foreground,
    this.background,
    this.fontSize = 12,
    super.key,
  });

  final String label;
  final Color? foreground;
  final Color? background;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: background ?? context.appColors.tableHeader,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground ?? context.appColors.ink,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// 学段色标圆点（10×10）。
class AppStageDot extends StatelessWidget {
  const AppStageDot({required this.color, this.size = 10, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 班级名称 chip：点击改名，尾部删除按钮，右键可调整顺序。
class AppClassChip extends StatelessWidget {
  const AppClassChip({
    required this.name,
    required this.onTap,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    this.background,
    this.borderColor,
    this.showDeleteIcon = true,
    super.key,
  });

  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final Color? background;
  final Color? borderColor;
  final bool showDeleteIcon;

  @override
  Widget build(BuildContext context) {
    final background = this.background ?? context.appColors.selectedBlue;
    final borderColor = this.borderColor ?? context.appColors.border;
    final chip = Container(
      height: 32,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 6, top: 4, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(fontSize: 12, color: context.appColors.ink),
              ),
              if (showDeleteIcon) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: '删除班级',
                  child: InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 11,
                        color: context.appColors.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (onMoveUp == null && onMoveDown == null) return chip;
    return FContextMenu(
      menu: [
        FItemGroup(
          divider: .none,
          children: [
            AppMenuTile(
              item: AppMenuItem(label: '修改名称', onPressed: onTap),
            ),
            if (onMoveUp != null)
              AppMenuTile(
                item: AppMenuItem(label: '上移', onPressed: onMoveUp!),
              ),
            if (onMoveDown != null)
              AppMenuTile(
                item: AppMenuItem(label: '下移', onPressed: onMoveDown!),
              ),
            AppMenuTile(
              item: AppMenuItem(
                label: '删除班级',
                onPressed: onDelete,
                destructive: true,
              ),
            ),
          ],
        ),
      ],
      child: chip,
    );
  }
}

/// 时段类型的视觉呈现：主色、矩阵格底色、节次标签底色。
class PeriodVisual {
  const PeriodVisual({
    required this.color,
    required this.cellTint,
    required this.labelTint,
  });

  final Color color;
  final Color cellTint;
  final Color labelTint;
}

/// 按设计稿映射时段配色：早上/早读=紫、上午=蓝、下午=绿、晚上=深灰；
/// 自定义时段在四套预设间轮换。
PeriodVisual periodVisualFor(
  BuildContext context,
  String periodName,
  int index,
) {
  final colors = context.appColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final presetIndex = switch (periodName) {
    '早上' || '早读' => 0,
    '上午' => 1,
    '下午' => 2,
    '晚上' => 3,
    _ => index % 4,
  };
  final color = switch (presetIndex) {
    0 => colors.purple,
    1 => colors.blue,
    2 => colors.success,
    _ => colors.inkSecondary,
  };
  final cellTint = switch (presetIndex) {
    0 => isDark ? const Color(0xFF342E43) : const Color(0xFFF4F1FB),
    1 => colors.selectedBlue,
    2 => colors.successSurface,
    _ => colors.tableHeader,
  };
  final labelTint = switch (presetIndex) {
    0 => isDark ? const Color(0xFF2A2636) : const Color(0xFFF8F6FD),
    1 => isDark ? const Color(0xFF1C2D3D) : const Color(0xFFF7F9FF),
    2 => isDark ? const Color(0xFF1B3027) : const Color(0xFFF2FAF5),
    _ => colors.tableHeader,
  };
  return PeriodVisual(color: color, cellTint: cellTint, labelTint: labelTint);
}
