import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:flutter/material.dart';

/// 「各年级容量校验」：按年级展示最紧张班级的单 / 双周需求与容量。
///
/// 超容量用淡色底 + 清晰文字（DESIGN.md 状态色规范），不用重边框与徽章堆叠。
class CapacitySummarySection extends StatelessWidget {
  const CapacitySummarySection({
    required this.grades,
    required this.summaries,
    super.key,
  });

  final List<GradeGroup> grades;

  /// 年级 ID → 容量概要。
  final Map<String, GradeCapacitySummary> summaries;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '各年级容量校验',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 4),
      const Text(
        '容量按班级、单周 / 双周分别校验；任一周超容量都标红。',
        style: TextStyle(color: AppTheme.muted, fontSize: 11.5),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final grade in grades)
            SizedBox(
              width: 218,
              child: _CapacityCard(
                gradeName: grade.name,
                summary: summaries[grade.id],
              ),
            ),
        ],
      ),
    ],
  );
}

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({required this.gradeName, required this.summary});

  final String gradeName;
  final GradeCapacitySummary? summary;

  @override
  Widget build(BuildContext context) {
    final isOver = summary?.isOver ?? false;
    return Container(
      decoration: BoxDecoration(
        color: isOver ? AppTheme.destructiveSurface : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: isOver ? AppTheme.destructiveSurface : AppTheme.border,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  gradeName,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isOver)
                Text(
                  '超 ${summary!.excess} 节',
                  style: const TextStyle(
                    color: AppTheme.destructive,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (summary == null)
            const Text(
              '暂无班级',
              style: TextStyle(color: AppTheme.muted, fontSize: 11.5),
            )
          else
            Text(
              '单周 ${summary!.oddDemand} / ${summary!.oddCapacity}'
              ' · 双周 ${summary!.evenDemand} / ${summary!.evenCapacity}',
              style: TextStyle(
                color: isOver ? AppTheme.destructive : AppTheme.inkSecondary,
                fontSize: 12,
              ),
            ),
          if (isOver) ...[
            const SizedBox(height: 2),
            Text(
              '${summary!.overClassName}超出可排容量',
              style: const TextStyle(
                color: AppTheme.destructive,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
