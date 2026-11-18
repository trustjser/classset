import 'dart:ui' show FontFeature;

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:flutter/material.dart';

/// 「当前学期」：展示所选学期的学年学期、起止日期与当前教学周。
class CurrentTermCard extends StatefulWidget {
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
  State<CurrentTermCard> createState() => _CurrentTermCardState();
}

class _CurrentTermCardState extends State<CurrentTermCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final currentWeek = widget.term.teachingWeekOf(widget.now);
    final colors = context.appColors;
    final feedbackDuration = AppTheme.motionDuration(
      context,
      AppTheme.feedbackDuration,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: feedbackDuration,
        curve: AppTheme.entranceCurve,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
            color: _hovered
                ? colors.blue.withValues(alpha: 0.26)
                : colors.blue.withValues(alpha: 0),
          ),
          boxShadow: colors.cardShadow,
        ),
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
                  AnimatedSwitcher(
                    duration: feedbackDuration,
                    child: KeyedSubtree(
                      key: ValueKey<bool>(currentWeek != null),
                      child: AppBadge(
                        label: currentWeek == null ? '未开始' : '进行中',
                        foreground: currentWeek == null
                            ? colors.muted
                            : colors.success,
                        background: currentWeek == null
                            ? colors.tableHeader
                            : colors.successSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: feedbackDuration,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previousChildren, ?currentChild],
                ),
                child: Text(
                  '${widget.term.academicYear} 学年 · ${widget.term.semesterLabel}',
                  key: ValueKey<String>(widget.term.id),
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _dateRange(),
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (currentWeek != null)
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: colors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: AnimatedSwitcher(
                        duration: feedbackDuration,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: Text(
                          '$currentWeek',
                          key: ValueKey<int>(currentWeek),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '第 $currentWeek 教学周 · ${widget.term.weekCycleLabel(currentWeek)}',
                      style: TextStyle(
                        color: colors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  '尚未设置第 1 教学周起始日，暂无法定位教学周。',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              const SizedBox(height: 14),
              AppGhostButton(
                onPressed: widget.onOpenTerms,
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
      ),
    );
  }

  /// 学期起止：第 1 教学周起始日 — 最后教学周结束日。
  String _dateRange() {
    final start = widget.term.firstTeachingWeekStart;
    if (start == null) return '尚未设置教学日历';
    final end = widget.term.teachingWeekEnd(widget.term.teachingWeekCount);
    if (end == null) return '尚未设置教学日历';
    return '${_formatZhDate(start)} — ${_formatZhDate(end)}';
  }

  static String _formatZhDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';
}
