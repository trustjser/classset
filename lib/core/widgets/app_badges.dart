import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 小号胶囊徽章：单周 / 双周、学段标签、公共时段标签等。
class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.label,
    this.foreground = AppTheme.ink,
    this.background = AppTheme.tableHeader,
    this.fontSize = 12,
    super.key,
  });

  final String label;
  final Color foreground;
  final Color background;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
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
    this.background = AppTheme.selectedBlue,
    this.borderColor = AppTheme.border,
    this.showDeleteIcon = true,
    super.key,
  });

  final String name;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final Color background;
  final Color borderColor;
  final bool showDeleteIcon;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 26,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.only(left: 9, right: 4, top: 3, bottom: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: const TextStyle(fontSize: 12, color: AppTheme.ink),
              ),
              if (showDeleteIcon) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 11, color: AppTheme.muted),
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

/// 按设计稿映射时段配色：早读=橙、上午=蓝、下午=绿、晚上=深灰；
/// 自定义时段在四套预设间轮换。
PeriodVisual periodVisualFor(String periodName, int index) {
  final preset = switch (periodName) {
    '早读' => const PeriodVisual(
      color: Color(0xFFE37318),
      cellTint: Color(0xFFE9F0FF),
      labelTint: Color(0xFFFFF8F2),
    ),
    '上午' => const PeriodVisual(
      color: AppTheme.blue,
      cellTint: Color(0xFFE9F0FF),
      labelTint: Color(0xFFF7F9FF),
    ),
    '下午' => const PeriodVisual(
      color: Color(0xFF2BA471),
      cellTint: Color(0xFFE9F7EF),
      labelTint: Color(0xFFF2FAF5),
    ),
    '晚上' => const PeriodVisual(
      color: Color(0xFF4B4B4B),
      cellTint: Color(0xFFEDEFF2),
      labelTint: Color(0xFFF5F5F5),
    ),
    _ => _cyclingVisual(index),
  };
  return preset;
}

const _cyclingPresets = <PeriodVisual>[
  PeriodVisual(
    color: Color(0xFFE37318),
    cellTint: Color(0xFFFFF1E9),
    labelTint: Color(0xFFFFF8F2),
  ),
  PeriodVisual(
    color: AppTheme.blue,
    cellTint: Color(0xFFE9F0FF),
    labelTint: Color(0xFFF7F9FF),
  ),
  PeriodVisual(
    color: Color(0xFF2BA471),
    cellTint: Color(0xFFE9F7EF),
    labelTint: Color(0xFFF2FAF5),
  ),
  PeriodVisual(
    color: Color(0xFF4B4B4B),
    cellTint: Color(0xFFEDEFF2),
    labelTint: Color(0xFFF5F5F5),
  ),
];

PeriodVisual _cyclingVisual(int index) =>
    _cyclingPresets[index % _cyclingPresets.length];

/// 免任课格底色与文字色（设计稿红格）。
abstract final class FreeSlotVisual {
  static const Color cellTint = Color(0xFFFFF0ED);
  static const Color foreground = Color(0xFFC63D36);
}

/// 无效格（非上课天 / 超出当天节数）底色。
abstract final class DisabledCellVisual {
  static const Color cellTint = Color(0xFFFAFAFA);
}
