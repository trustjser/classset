import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

/// 「选择学段与年级」：范围单选列表（全校 / 各学段，选中行淡蓝底）+
/// 年级列 chip 多选（全选 / 清空）。
class SubjectScopeSelector extends StatelessWidget {
  const SubjectScopeSelector({
    required this.stages,
    required this.gradeCountByStage,
    required this.totalGradeCount,
    required this.selectedScopeStageId,
    required this.grades,
    required this.visibleGradeIds,
    required this.onSelectStage,
    required this.onToggleGrade,
    required this.onSelectAllGrades,
    required this.onClearGrades,
    required this.accentForStage,
    super.key,
  });

  final List<SchoolStage> stages;

  /// 学段 ID → 年级数（选项计数提示）。
  final Map<String, int> gradeCountByStage;
  final int totalGradeCount;

  /// 当前范围：null = 全校，否则学段 ID。
  final String? selectedScopeStageId;

  /// 当前范围的年级（chip 候选）。
  final List<GradeGroup> grades;
  final Set<String> visibleGradeIds;

  /// 选择范围；传 null 表示全校。
  final ValueChanged<String?> onSelectStage;
  final ValueChanged<String> onToggleGrade;
  final VoidCallback onSelectAllGrades;
  final VoidCallback onClearGrades;

  /// 学段强调色（按全局学段序号取色，与矩阵列头一致）。
  final Color Function(SchoolStage stage) accentForStage;

  @override
  Widget build(BuildContext context) {
    final scopeName = selectedScopeStageId == null
        ? '全校'
        : stages
                  .where((stage) => stage.id == selectedScopeStageId)
                  .map((stage) => stage.name)
                  .firstOrNull ??
              '';
    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        // 宽屏下面板被拉伸到与矩阵等高；窗口较矮时内容超出可视高度，
        // 面板内部滚动（窄屏外层是整页滚动，高度无界时自然展开不滚动）。
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScopeOptionRow(
                label: '全校（$totalGradeCount 个年级）',
                selected: selectedScopeStageId == null,
                onTap: () => onSelectStage(null),
              ),
              for (final stage in stages)
                _ScopeOptionRow(
                  label: _stageLabel(stage),
                  selected: selectedScopeStageId == stage.id,
                  accent: accentForStage(stage),
                  onTap: () => onSelectStage(stage.id),
                ),
              Divider(height: 24, color: context.appColors.border),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$scopeName · 显示的年级列',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppGhostButton(
                    size: f.FButtonSizeVariant.xs,
                    onPressed: onSelectAllGrades,
                    child: Text(
                      '全选',
                      style: TextStyle(
                        color: context.appColors.blue,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AppGhostButton(
                    size: f.FButtonSizeVariant.xs,
                    onPressed: onClearGrades,
                    child: Text(
                      '清空',
                      style: TextStyle(
                        color: context.appColors.blue,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final grade in grades)
                    _GradeChip(
                      label: grade.name,
                      selected: visibleGradeIds.contains(grade.id),
                      onTap: () => onToggleGrade(grade.id),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '容量按各年级所在学段的作息与免任课计算。',
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _stageLabel(SchoolStage stage) {
    final count = gradeCountByStage[stage.id] ?? 0;
    return count > 0 ? '${stage.name}（$count 个年级）' : stage.name;
  }
}

/// 范围选项行：圆形指示器 + 名称，选中行淡蓝圆角底；学段行的文字与
/// 指示器用该学段的强调色（[accent]），全校行保持中性色。
class _ScopeOptionRow extends StatelessWidget {
  const _ScopeOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 学段强调色；null = 全校行（中性色）。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final textColor =
        accent ?? (selected ? context.appColors.blue : context.appColors.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? context.appColors.selectedBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                _Indicator(
                  selected: selected,
                  color: accent ?? context.appColors.blue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? color : context.appColors.muted,
        width: 1.5,
      ),
    ),
    alignment: Alignment.center,
    child: selected
        ? Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          )
        : null,
  );
}

/// 年级列 chip：选中蓝边蓝字，未选中灰边灰字。
class _GradeChip extends StatelessWidget {
  const _GradeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.appColors.surface,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? context.appColors.blue : context.appColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? context.appColors.blue
                : context.appColors.inkSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}
