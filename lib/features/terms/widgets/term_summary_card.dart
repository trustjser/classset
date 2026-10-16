import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:flutter/material.dart';

class TermSummaryCard extends StatelessWidget {
  const TermSummaryCard({
    required this.selectedTerm,
    required this.onEditTerm,
    required this.onManageTerms,
    required this.onAddTerm,
    this.onGoToRoutines,
    super.key,
  });

  final AcademicTerm selectedTerm;
  final VoidCallback onEditTerm;
  final VoidCallback onManageTerms;
  final VoidCallback onAddTerm;
  final VoidCallback? onGoToRoutines;

  @override
  Widget build(BuildContext context) => AppSurface(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 470;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '学期设置',
                      style: TextStyle(
                        color: AppTheme.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      color: AppTheme.successSurface,
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                    ),
                    child: const Text(
                      '当前',
                      style: TextStyle(
                        color: AppTheme.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TermActions(
                    onEditTerm: onEditTerm,
                    onManageTerms: onManageTerms,
                    onAddTerm: onAddTerm,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                selectedTerm.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '青木实验学校',
                style: TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
              const SizedBox(height: 20),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TermDataTile(
                      label: '第 1 教学周起始',
                      value: selectedTerm.firstTeachingWeekStart == null
                          ? '尚未设置'
                          : formatDateYmdWithWeekday(
                              selectedTerm.firstTeachingWeekStart!,
                            ),
                      accent: selectedTerm.firstTeachingWeekStart != null,
                    ),
                    const SizedBox(height: 9),
                    _TermDataTile(
                      label: '课表周期',
                      value:
                          '${selectedTerm.teachingWeekCount} 周 · ${selectedTerm.cycleMode.label}',
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _TermDataTile(
                        label: '第 1 教学周起始',
                        value: selectedTerm.firstTeachingWeekStart == null
                            ? '尚未设置'
                            : formatDateYmdWithWeekday(
                                selectedTerm.firstTeachingWeekStart!,
                              ),
                        accent: selectedTerm.firstTeachingWeekStart != null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TermDataTile(
                        label: '课表周期',
                        value:
                            '${selectedTerm.teachingWeekCount} 周 · ${selectedTerm.cycleMode.label}',
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.selectedBlue,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '上课日与每日节数按学段设置',
                      style: TextStyle(
                        color: AppTheme.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '同一学校不同学段可使用不同作息。学期日历只管理教学周与停课、补课等例外。',
                      style: TextStyle(
                        color: AppTheme.inkSecondary,
                        fontSize: 10,
                        height: 1.5,
                      ),
                    ),
                    if (onGoToRoutines != null) ...[
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerRight,
                        child: AppGhostButton(
                          size: .xs,
                          onPressed: onGoToRoutines,
                          child: const Text(
                            '前往作息设置 →',
                            style: TextStyle(
                              color: AppTheme.blue,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _TermDataTile extends StatelessWidget {
  const _TermDataTile({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 62),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: AppTheme.canvas,
      border: Border.all(color: AppTheme.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.muted, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: accent ? AppTheme.blue : AppTheme.ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _TermActions extends StatelessWidget {
  const _TermActions({
    required this.onEditTerm,
    required this.onManageTerms,
    required this.onAddTerm,
  });

  final VoidCallback onEditTerm;
  final VoidCallback onManageTerms;
  final VoidCallback onAddTerm;

  @override
  Widget build(BuildContext context) => AppMenuButton(
    items: [
      AppMenuItem(label: '编辑当前学期', onPressed: onEditTerm),
      AppMenuItem(label: '所有学期', onPressed: onManageTerms),
      AppMenuItem(label: '＋ 新建学期', onPressed: onAddTerm),
    ],
    child: Container(
      width: 34,
      height: 32,
      alignment: Alignment.center,
      child: const Icon(Icons.more_horiz, size: 19, color: AppTheme.muted),
    ),
  );
}
