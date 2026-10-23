import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_badges.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:flutter/material.dart';

class TermManagementDialog extends StatelessWidget {
  const TermManagementDialog({
    required this.terms,
    required this.activeTermId,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onCreate,
    super.key,
  });

  final List<AcademicTerm> terms;
  final String? activeTermId;
  final ValueChanged<AcademicTerm> onSelect;
  final ValueChanged<AcademicTerm> onEdit;
  final Future<bool> Function(AcademicTerm) onDelete;
  final VoidCallback onCreate;

  List<AcademicTerm> get _sorted => [...terms]
    ..sort((a, b) {
      final aStart = a.firstTeachingWeekStart;
      final bStart = b.firstTeachingWeekStart;
      if (aStart == null && bStart == null) {
        return b.createdAt.compareTo(a.createdAt);
      }
      if (aStart == null) return 1;
      if (bStart == null) return -1;
      final byDate = bStart.compareTo(aStart);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 620,
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
    titleGap: 12,
    actionsGap: 12,
    title: AppDialogTitle(title: '所有学期', onClose: () => Navigator.pop(context)),
    content: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 572;
        final tableWidth = compact
            ? (constraints.maxWidth < 512 ? 512.0 : constraints.maxWidth)
            : 572.0;
        final cellPadding = compact ? 12.0 : 16.0;
        const switchWidth = 44.0;
        final startWidth = compact ? 100.0 : 115.0;
        final cycleWidth = compact ? 138.0 : 135.0;
        const actionWidth = 113.0;
        final termWidth =
            tableWidth -
            cellPadding * 2 -
            switchWidth -
            startWidth -
            cycleWidth -
            actionWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: context.appColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppDataTableHeader(
                        height: 36,
                        textColor: context.appColors.inkSecondary,
                        padding: EdgeInsets.symmetric(horizontal: cellPadding),
                        children: [
                          const SizedBox(width: switchWidth, child: Text('切换')),
                          SizedBox(
                            width: termWidth,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Text('学期'),
                            ),
                          ),
                          SizedBox(
                            width: startWidth,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Text('第 1 教学周起始'),
                            ),
                          ),
                          SizedBox(
                            width: cycleWidth,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Text('总周数 · 课表周期'),
                            ),
                          ),
                          SizedBox(
                            width: actionWidth,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('操作'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_sorted.isEmpty)
                        const SizedBox(
                          height: 180,
                          child: AppEmptyState(
                            title: '还没有学期',
                            message: '新建学期后，这里会显示学期资料。',
                            icon: Icons.event_note_outlined,
                          ),
                        )
                      else
                        SizedBox(
                          height: (_sorted.length * 45 - 1)
                              .clamp(0, 404)
                              .toDouble(),
                          child: ListView.separated(
                            itemCount: _sorted.length,
                            separatorBuilder: (context, index) => SizedBox(
                              height: 1,
                              child: ColoredBox(
                                color: context.appColors.tableDivider,
                              ),
                            ),
                            itemBuilder: (context, index) => _TermRow(
                              term: _sorted[index],
                              isCurrent: _sorted[index].id == activeTermId,
                              groupValue: activeTermId ?? '',
                              switchWidth: switchWidth,
                              termWidth: termWidth,
                              startWidth: startWidth,
                              cycleWidth: cycleWidth,
                              actionWidth: actionWidth,
                              horizontalPadding: cellPadding,
                              onSelect: (term) {
                                Navigator.pop(context);
                                onSelect(term);
                              },
                              onEdit: () {
                                Navigator.pop(context);
                                onEdit(_sorted[index]);
                              },
                              onDelete: () async {
                                if (await onDelete(_sorted[index]) &&
                                    context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
    actions: [
      AppPrimaryButton.icon(
        onPressed: () {
          Navigator.pop(context);
          onCreate();
        },
        icon: const Icon(Icons.add, size: 16),
        label: const Text('新建学期'),
      ),
    ],
  );
}

class _TermRow extends StatelessWidget {
  const _TermRow({
    required this.term,
    required this.isCurrent,
    required this.groupValue,
    required this.switchWidth,
    required this.termWidth,
    required this.startWidth,
    required this.cycleWidth,
    required this.actionWidth,
    required this.horizontalPadding,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final AcademicTerm term;
  final bool isCurrent;
  final String groupValue;
  final double switchWidth;
  final double termWidth;
  final double startWidth;
  final double cycleWidth;
  final double actionWidth;
  final double horizontalPadding;
  final ValueChanged<AcademicTerm> onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final start = term.firstTeachingWeekStart;
    return Material(
      color: context.appColors.surface,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              SizedBox(
                width: switchWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                    message: '切换到${term.title}',
                    child: AppRadioIndicator<String>(
                      value: term.id,
                      groupValue: groupValue,
                      label: '切换到${term.title}',
                      onChanged: (_) => onSelect(term),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: termWidth,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          term.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.appColors.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isCurrent) ...[
                        const SizedBox(width: 8),
                        AppBadge(
                          label: '当前',
                          foreground: context.appColors.blue,
                          background: context.appColors.selectedBlue,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: startWidth,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    start == null ? '—' : formatDateYmd(start),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: cycleWidth,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '${term.teachingWeekCount} 周 · ${term.cycleMode.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: actionWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: '编辑学期',
                        child: _ActionTextButton(
                          label: '编辑',
                          onPressed: onEdit,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Tooltip(
                        message: isCurrent ? '当前学期不可删除' : '删除学期',
                        child: _ActionTextButton(
                          label: '删除',
                          onPressed: isCurrent ? null : onDelete,
                          foreground: context.appColors.destructive,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTextButton extends StatelessWidget {
  const _ActionTextButton({
    required this.label,
    required this.onPressed,
    this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => AppGhostButton(
    size: .xs,
    onPressed: onPressed,
    child: Text(
      label,
      style: TextStyle(
        color: onPressed == null
            ? context.appColors.muted
            : foreground ?? context.appColors.blue,
        fontSize: 12,
        height: 17 / 12,
      ),
    ),
  );
}
