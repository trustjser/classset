import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:flutter/material.dart';

/// 「当前学期」：展示所选学期的学年学期、起止日期与当前教学周。
class CurrentTermCard extends StatelessWidget {
  const CurrentTermCard({
    required this.term,
    required this.now,
    required this.onOpenTerms,
    super.key,
  });

  final AcademicTerm term;

  /// 当前时间（测试中可注入以固定教学周）。
  final DateTime now;

  final VoidCallback onOpenTerms;

  @override
  Widget build(BuildContext context) {
    final currentWeek = term.teachingWeekOf(now);
    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '当前学期',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                AppBadge(
                  label: currentWeek == null ? '未开始' : '进行中',
                  foreground: currentWeek == null
                      ? context.appColors.muted
                      : context.appColors.success,
                  background: currentWeek == null
                      ? context.appColors.tableHeader
                      : context.appColors.successSurface,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${term.academicYear} 学年 · ${term.semesterLabel}',
              style: TextStyle(
                color: context.appColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _dateRange(),
              style: TextStyle(color: context.appColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (currentWeek != null)
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.appColors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$currentWeek',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '第 $currentWeek 教学周 · ${term.weekCycleLabel(currentWeek)}',
                    style: TextStyle(
                      color: context.appColors.inkSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              )
            else
              Text(
                '尚未设置第 1 教学周起始日，暂无法定位教学周。',
                style: TextStyle(color: context.appColors.muted, fontSize: 12),
              ),
            const SizedBox(height: 14),
            AppGhostButton(
              onPressed: onOpenTerms,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('查看学期与日历'),
                  Icon(Icons.chevron_right_rounded, size: 15),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 学期起止：第 1 教学周起始日 — 最后教学周结束日。
  String _dateRange() {
    final start = term.firstTeachingWeekStart;
    if (start == null) return '尚未设置教学日历';
    final end = term.teachingWeekEnd(term.teachingWeekCount);
    if (end == null) return '尚未设置教学日历';
    return '${_formatZhDate(start)} — ${_formatZhDate(end)}';
  }

  static String _formatZhDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';
}
