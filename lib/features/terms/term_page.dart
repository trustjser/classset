import 'package:class_set/app.dart';
import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/features/terms/dialogs/exception_editor_dialog.dart';
import 'package:class_set/features/terms/dialogs/term_editor_dialog.dart';
import 'package:class_set/features/terms/dialogs/term_management_dialog.dart';
import 'package:class_set/features/terms/widgets/teaching_calendar_month.dart';
import 'package:class_set/features/terms/widgets/term_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:class_set/features/terms/dialogs/exception_editor_dialog.dart';
export 'package:class_set/features/terms/dialogs/term_editor_dialog.dart';
export 'package:class_set/features/terms/dialogs/term_management_dialog.dart';

class TermPage extends ConsumerWidget {
  const TermPage({required this.databasePath, super.key});

  final String databasePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termsProvider);
    final activeTermId = ref.watch(activeTermIdProvider);
    return terms.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _ErrorPanel(message: '读取本地学期数据失败：$error'),
      data: (items) {
        if (items.isEmpty) {
          return _EmptyTerms(onCreate: () => _editTerm(context, ref));
        }
        final selected = items.where((item) => item.id == activeTermId);
        final term = selected.isEmpty ? items.first : selected.first;
        final exceptions =
            ref.watch(calendarExceptionsProvider(term.id)).valueOrNull ??
            const <CalendarException>[];
        return _TermCalendarDashboard(
          selectedTerm: term,
          exceptions: exceptions,
          onEditTerm: () => _editTerm(
            context,
            ref,
            term: term,
            existingExceptions: exceptions,
          ),
          onManageTerms: () => _manageTerms(context, ref, items, term.id),
          onAddTerm: () => _editTerm(context, ref, terms: items),
          onGoToRoutines: () =>
              ref.read(selectedSectionProvider.notifier).state =
                  AppSection.routines,
          onAddException: () => _addException(context, ref, term, exceptions),
          onEditWeek: (weekNumber) =>
              _openExceptionEditor(context, ref, term, weekNumber, exceptions),
          onEditDate: (date) {
            final weekNumber = term.teachingWeekOf(date);
            if (weekNumber != null) {
              _openExceptionEditor(
                context,
                ref,
                term,
                weekNumber,
                exceptions,
                initialDate: date,
              );
            }
          },
        );
      },
    );
  }

  Future<void> _editTerm(
    BuildContext context,
    WidgetRef ref, {
    AcademicTerm? term,
    List<AcademicTerm> terms = const [],
    List<CalendarException>? existingExceptions,
  }) async {
    final List<CalendarException> exceptions;
    if (existingExceptions != null) {
      exceptions = existingExceptions;
    } else if (term == null) {
      exceptions = const <CalendarException>[];
    } else {
      exceptions = await ref.read(calendarExceptionsProvider(term.id).future);
    }
    if (!context.mounted) return;
    final result = await showAppDialog<TermEditorResult>(
      context: context,
      builder: (context) => TermEditorDialog(
        term: term,
        availableTerms: terms,
        existingExceptions: exceptions,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      final repository = ref.read(schoolRepositoryProvider);
      final sourceTermId = result.cloneSourceTermId;
      if (sourceTermId == null) {
        await repository.saveTerm(result.term);
      } else {
        await repository.cloneTerm(
          sourceTermId: sourceTermId,
          targetTerm: result.term,
        );
      }
      ref.read(activeTermIdProvider.notifier).state = result.term.id;
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
    } on Object catch (error) {
      if (context.mounted) _showError(context, '保存学期失败：$error');
    }
  }

  Future<void> _manageTerms(
    BuildContext context,
    WidgetRef ref,
    List<AcademicTerm> terms,
    String currentTermId,
  ) async {
    await showAppDialog<void>(
      context: context,
      builder: (_) => TermManagementDialog(
        terms: terms,
        activeTermId: currentTermId,
        onSelect: (term) =>
            ref.read(activeTermIdProvider.notifier).state = term.id,
        onEdit: (term) => _editTerm(context, ref, term: term),
        onDelete: (term) =>
            _deleteTerm(context, ref, term, currentTermId: currentTermId),
        onCreate: () => _editTerm(context, ref, terms: terms),
      ),
    );
  }

  Future<bool> _deleteTerm(
    BuildContext context,
    WidgetRef ref,
    AcademicTerm term, {
    String? currentTermId,
  }) async {
    if ((currentTermId ?? ref.read(activeTermIdProvider)) == term.id) {
      return false;
    }
    final confirmed = await _confirmDelete(
      context,
      title: '删除学期',
      message: '确认删除「${term.title}」？',
      warning: '该学期的学段、年级 / 班级、作息设置和日历例外将一并移除，操作不可恢复。',
    );
    if (!confirmed || !context.mounted) return false;
    try {
      await ref.read(schoolRepositoryProvider).deleteTerm(term.id);
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      return true;
    } on Object catch (error) {
      if (context.mounted) _showError(context, '删除学期失败：$error');
      return false;
    }
  }

  Future<void> _openExceptionEditor(
    BuildContext context,
    WidgetRef ref,
    AcademicTerm term,
    int weekNumber,
    List<CalendarException> exceptions, {
    DateTime? initialDate,
  }) async {
    if (!term.hasCalendar) return;
    await showAppDialog<void>(
      context: context,
      builder: (context) => ExceptionEditorDialog(
        term: term,
        weekNumber: weekNumber,
        initialDate: initialDate,
        existing: exceptions
            .where((item) => term.teachingWeekOf(item.date) == weekNumber)
            .toList(),
      ),
    );
  }

  Future<void> _addException(
    BuildContext context,
    WidgetRef ref,
    AcademicTerm term,
    List<CalendarException> exceptions,
  ) async {
    if (!term.hasCalendar) {
      await _editTerm(context, ref, term: term, existingExceptions: exceptions);
      return;
    }
    final firstDate = term.teachingWeekStart(1)!;
    final lastDate = term.teachingWeekEnd(term.teachingWeekCount)!;
    final today = DateTime.now();
    final candidate = dateOnly(today);
    final initialDate = candidate.isBefore(firstDate)
        ? firstDate
        : candidate.isAfter(lastDate)
        ? firstDate
        : candidate;
    final date = await showAppDialog<DateTime>(
      context: context,
      builder: (context) => _ExceptionDateDialog(
        firstDate: firstDate,
        lastDate: lastDate,
        initialDate: initialDate,
      ),
    );
    if (date == null || !context.mounted) return;
    final week = term.teachingWeekOf(date);
    if (week == null) return;
    await _openExceptionEditor(
      context,
      ref,
      term,
      week,
      exceptions,
      initialDate: date,
    );
  }
}

class _TermCalendarDashboard extends StatelessWidget {
  const _TermCalendarDashboard({
    required this.selectedTerm,
    required this.exceptions,
    required this.onEditTerm,
    required this.onManageTerms,
    required this.onAddTerm,
    required this.onGoToRoutines,
    required this.onAddException,
    required this.onEditWeek,
    required this.onEditDate,
  });

  final AcademicTerm selectedTerm;
  final List<CalendarException> exceptions;
  final VoidCallback onEditTerm;
  final VoidCallback onManageTerms;
  final VoidCallback onAddTerm;
  final VoidCallback onGoToRoutines;
  final VoidCallback onAddException;
  final ValueChanged<int> onEditWeek;
  final ValueChanged<DateTime> onEditDate;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            constraints.maxWidth >= AppTheme.twoColumnLayoutBreakpoint;
        final panelHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - 150).clamp(520.0, 840.0).toDouble()
            : 840.0;
        final termCard = TermSummaryCard(
          selectedTerm: selectedTerm,
          onEditTerm: onEditTerm,
          onManageTerms: onManageTerms,
          onAddTerm: onAddTerm,
          onGoToRoutines: onGoToRoutines,
        );
        final calendar = TeachingCalendarMonth(
          term: selectedTerm,
          exceptions: exceptions,
          onEditWeek: onEditWeek,
          onAddException: onAddException,
          onEditTerm: onEditTerm,
          onEditDate: onEditDate,
          fillHeight: sideBySide,
        );

        return ListView(
          padding: AppTheme.pageInsetsForWidth(constraints.maxWidth),
          children: [
            const _TermPageHeading(),
            const SizedBox(height: 20),
            if (sideBySide)
              SizedBox(
                height: panelHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 365, child: termCard),
                    const SizedBox(width: 16),
                    Expanded(child: calendar),
                  ],
                ),
              )
            else ...[
              calendar,
              const SizedBox(height: 14),
              termCard,
            ],
          ],
        );
      },
    ),
  );
}

class _TermPageHeading extends StatelessWidget {
  const _TermPageHeading();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '学期与日历',
        style: TextStyle(
          color: context.appColors.ink,
          fontSize: 25,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
      SizedBox(height: 5),
      Text(
        '设置教学周范围、单双周锚点和教学日例外。',
        style: TextStyle(color: context.appColors.inkSecondary, fontSize: 12),
      ),
    ],
  );
}

class _ExceptionDateDialog extends StatefulWidget {
  const _ExceptionDateDialog({
    required this.firstDate,
    required this.lastDate,
    required this.initialDate,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime initialDate;

  @override
  State<_ExceptionDateDialog> createState() => _ExceptionDateDialogState();
}

class _ExceptionDateDialogState extends State<_ExceptionDateDialog> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 410,
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
    titleGap: 14,
    actionsGap: 10,
    title: AppDialogTitle(
      title: '添加日历例外',
      onClose: () => Navigator.pop(context),
    ),
    content: SizedBox(
      width: 366,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '先选定日期，再设置补课或停课，并指定补课采用的原课表。',
            style: TextStyle(
              color: context.appColors.inkSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          AppDateField(
            value: _date,
            firstDate: widget.firstDate,
            lastDate: widget.lastDate,
            hint: '选择例外日期',
            format: (date) =>
                '${formatDateYmdWithWeekday(date)} · 第${_weekNumber(date)}周',
            onChanged: (date) {
              if (date != null) setState(() => _date = date);
            },
          ),
        ],
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: () => Navigator.pop(context, _date),
        child: const Text('继续设置'),
      ),
    ],
  );

  int _weekNumber(DateTime date) {
    // 日期始终受限于当前学期教学周范围，序号按周一锚点后的 7 天计算。
    final days = dateOnly(date).difference(widget.firstDate).inDays;
    return days ~/ 7 + 1;
  }
}

class _EmptyTerms extends StatelessWidget {
  const _EmptyTerms({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => AppEmptyState(
    title: '还没有学期资料',
    message: '新建学期后即可建立学段、班级和教学日历。',
    icon: Icons.event_note_outlined,
    action: AppPrimaryButton.icon(
      onPressed: onCreate,
      icon: const Icon(Icons.add),
      label: const Text('新建第一个学期'),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: SelectableText(
      message,
      style: TextStyle(color: context.appColors.destructive),
    ),
  );
}

Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  required String warning,
}) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        maxWidth: 420,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        titleGap: 12,
        actionsGap: 12,
        title: AppDialogTitle(
          title: title,
          onClose: () => Navigator.pop(context, false),
        ),
        content: SizedBox(
          width: 372,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(fontSize: 13, height: 19 / 13),
              ),
              const SizedBox(height: 12),
              Text(
                warning,
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 12,
                  height: 17 / 12,
                ),
              ),
            ],
          ),
        ),
        actions: [
          AppGhostButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          AppDestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ) ??
    false;

void _showError(BuildContext context, String message) => showAppDialog<void>(
  context: context,
  builder: (context) => AppDialog(
    title: const Text('操作失败'),
    content: SelectableText(message),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  ),
);
