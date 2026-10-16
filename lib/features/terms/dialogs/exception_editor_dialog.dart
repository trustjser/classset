import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:class_set/app.dart';

class ExceptionEditorDialog extends ConsumerStatefulWidget {
  const ExceptionEditorDialog({
    required this.term,
    required this.weekNumber,
    required this.existing,
    this.initialDate,
    super.key,
  });

  final AcademicTerm term;
  final int weekNumber;
  final List<CalendarException> existing;
  final DateTime? initialDate;

  @override
  ConsumerState<ExceptionEditorDialog> createState() =>
      _ExceptionEditorDialogState();
}

class _ExceptionEditorDialogState extends ConsumerState<ExceptionEditorDialog> {
  late List<CalendarException> _drafts;
  CalendarExceptionRange? _editing;
  late DateTime _startDate;
  late DateTime _endDate;
  late DateTime _formDate;
  late CalendarExceptionKind _formKind;
  DateTime? _makeupForDate;
  final _noteController = TextEditingController();
  String? _formError;
  bool _formDirty = false;
  static int _idCounter = 0;

  DateTime get _weekStart => widget.term.teachingWeekStart(widget.weekNumber)!;
  DateTime get _weekEnd => widget.term.teachingWeekEnd(widget.weekNumber)!;

  @override
  void initState() {
    super.initState();
    _drafts = List.of(widget.existing);
    _resetForm(initialDate: widget.initialDate);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _resetForm({DateTime? initialDate}) {
    final date =
        initialDate != null &&
            !initialDate.isBefore(_weekStart) &&
            !initialDate.isAfter(_weekEnd)
        ? dateOnly(initialDate)
        : _weekStart;
    _startDate = date;
    _endDate = date;
    _formDate = date;
    _formKind = CalendarExceptionKind.makeup;
    _makeupForDate = null;
    _noteController.clear();
    _formError = null;
    _formDirty = false;
    _editing = null;
  }

  void _loadForEdit(CalendarExceptionRange range) {
    setState(() {
      _editing = range;
      _startDate = range.startDate;
      _endDate = range.endDate;
      _formDate = range.startDate;
      _formKind = range.kind;
      _makeupForDate = range.exceptions.first.makeupForDate;
      _noteController.text = range.note;
      _formError = null;
      _formDirty = true;
    });
  }

  bool _submitForm() {
    final eventDates = <DateTime>[];
    if (_formKind == CalendarExceptionKind.holiday) {
      if (_startDate.isAfter(_endDate)) {
        setState(() => _formError = '停课结束日期不能早于开始日期');
        return false;
      }
      for (
        var day = _startDate;
        !day.isAfter(_endDate);
        day = day.add(const Duration(days: 1))
      ) {
        if (day.isBefore(_weekStart) || day.isAfter(_weekEnd)) {
          setState(() => _formError = '停课区间必须位于当前教学周内');
          return false;
        }
        eventDates.add(day);
      }
    } else {
      if (_formDate.isBefore(_weekStart) || _formDate.isAfter(_weekEnd)) {
        setState(() => _formError = '补课日期必须位于当前教学周内');
        return false;
      }
      if (_makeupForDate == null ||
          widget.term.teachingWeekOf(_makeupForDate!) == null) {
        setState(() => _formError = '请选择本学期内被补的原课日期');
        return false;
      }
      eventDates.add(dateOnly(_formDate));
    }

    final editingIds =
        _editing?.exceptions.map((item) => item.id).toSet() ?? {};
    final otherDrafts = _drafts
        .where((item) => !editingIds.contains(item.id))
        .toList();
    final eventKeys = eventDates.map(_dateKey).toSet();
    final duplicate = otherDrafts.any(
      (item) => eventKeys.contains(_dateKey(item.date)),
    );
    if (duplicate) {
      setState(() => _formError = '同一天只能设置一条例外，请调整日期范围');
      return false;
    }

    final oldByDate = <String, CalendarException>{
      for (final item in _editing?.exceptions ?? const <CalendarException>[])
        _dateKey(item.date): item,
    };
    final added = <CalendarException>[
      for (final date in eventDates)
        CalendarException(
          id: oldByDate[_dateKey(date)]?.id ?? _newId(),
          termId: widget.term.id,
          date: dateOnly(date),
          kind: _formKind,
          makeupWeekday: _formKind == CalendarExceptionKind.makeup
              ? _makeupForDate!.weekday
              : null,
          makeupForDate: _formKind == CalendarExceptionKind.makeup
              ? dateOnly(_makeupForDate!)
              : null,
          note: _noteController.text.trim(),
        ),
    ];
    setState(() {
      _drafts = [...otherDrafts, ...added]
        ..sort((a, b) => a.date.compareTo(b.date));
      _resetForm();
    });
    return true;
  }

  Future<void> _save() async {
    if (_formDirty && !_submitForm()) return;
    final originalIds = widget.existing.map((item) => item.id).toSet();
    final draftIds = _drafts.map((item) => item.id).toSet();
    try {
      await ref
          .read(schoolRepositoryProvider)
          .saveCalendarExceptions(
            termId: widget.term.id,
            upserts: _drafts,
            deleteIds: originalIds.difference(draftIds),
          );
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      if (!mounted) return;
      Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) _showError('保存例外安排失败：$error');
    }
  }

  void _deleteRange(CalendarExceptionRange range) {
    final ids = range.exceptions.map((item) => item.id).toSet();
    setState(() {
      _drafts.removeWhere((item) => ids.contains(item.id));
      if (_editing != null &&
          _editing!.exceptions.any((item) => ids.contains(item.id))) {
        _resetForm();
      }
    });
  }

  void _showError(String message) => showAppDialog<void>(
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

  @override
  Widget build(BuildContext context) {
    final range = calendarExceptionRangesForWeek(
      widget.term,
      widget.weekNumber,
      _drafts,
    );
    return AppDialog(
      maxWidth: 540,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      titleGap: 12,
      actionsGap: 12,
      title: _ExceptionDialogTitle(
        contextLabel:
            '第 ${widget.weekNumber} 周 · ${widget.term.weekCycleLabel(widget.weekNumber)} · '
            '${formatDateMd(_weekStart)} – ${formatDateMd(_weekEnd)}',
        onClose: () => Navigator.pop(context),
      ),
      content: SizedBox(
        width: 496,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '例外安排（停课 / 补课 / 节假日）',
              style: TextStyle(
                color: AppTheme.inkSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 17 / 12,
              ),
            ),
            if (range.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in range)
                    _ExceptionRangeChip(
                      label: _rangeLabel(item),
                      isMakeup: item.isMakeup,
                      onPressed: () => _loadForEdit(item),
                      onDelete: () => _deleteRange(item),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFC),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const _ExceptionFieldLabel('类型'),
                      const SizedBox(width: 6),
                      AppRadioOption<CalendarExceptionKind>(
                        value: CalendarExceptionKind.makeup,
                        groupValue: _formKind,
                        label: '补课',
                        onChanged: (value) => setState(() {
                          _formKind = value;
                          _formError = null;
                          _formDirty = true;
                        }),
                      ),
                      const SizedBox(width: 20),
                      AppRadioOption<CalendarExceptionKind>(
                        value: CalendarExceptionKind.holiday,
                        groupValue: _formKind,
                        label: '停课 / 节假日',
                        onChanged: (value) => setState(() {
                          _formKind = value;
                          _formError = null;
                          _formDirty = true;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_formKind == CalendarExceptionKind.makeup)
                    Row(
                      children: [
                        const _ExceptionFieldLabel('补课日期'),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 165,
                          child: AppDateField(
                            value: _formDate,
                            firstDate: _weekStart,
                            lastDate: _weekEnd,
                            hint: '选择补课日期',
                            format: (date) =>
                                '${formatDateMd(date)}（周${weekdayShortName(date.weekday)}）',
                            onChanged: (date) => setState(() {
                              if (date == null) return;
                              _formDate = date;
                              _formError = null;
                              _formDirty = true;
                            }),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const _ExceptionFieldLabel('执行课表'),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 165,
                          child: AppDateField(
                            value: _makeupForDate,
                            firstDate: widget.term.firstTeachingWeekStart!,
                            lastDate: widget.term.teachingWeekEnd(
                              widget.term.teachingWeekCount,
                            )!,
                            hint: '选择被补的原课日期',
                            format: (date) {
                              final week = widget.term.teachingWeekOf(date);
                              return '${formatDateMd(date)} · '
                                  '${weekdayFullName(date.weekday)} · '
                                  '${week == null ? '课表' : '${widget.term.weekCycleLabel(week)}课表'}';
                            },
                            onChanged: (date) => setState(() {
                              _makeupForDate = date;
                              _formError = null;
                              _formDirty = true;
                            }),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    Row(
                      children: [
                        const _ExceptionFieldLabel('停课区间'),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: AppDateField(
                                  value: _startDate,
                                  firstDate: _weekStart,
                                  lastDate: _weekEnd,
                                  hint: '选择开始日期',
                                  format: (date) => '开始 ${formatDateMd(date)}',
                                  onChanged: (date) => setState(() {
                                    if (date == null) return;
                                    _startDate = date;
                                    _formError = null;
                                    _formDirty = true;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: AppDateField(
                                  value: _endDate,
                                  firstDate: _weekStart,
                                  lastDate: _weekEnd,
                                  hint: '选择结束日期',
                                  format: (date) => '结束 ${formatDateMd(date)}',
                                  onChanged: (date) => setState(() {
                                    if (date == null) return;
                                    _endDate = date;
                                    _formError = null;
                                    _formDirty = true;
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const _ExceptionFieldLabel('备注（选填）'),
                        const SizedBox(width: 6),
                        Expanded(
                          child: AppTextFormField(
                            size: .sm,
                            controller: _noteController,
                            decoration: const InputDecoration(
                              hintText: '例如：国庆假期',
                            ),
                            onChanged: (_) => setState(() => _formDirty = true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 8),
              Text(
                _formError!,
                style: const TextStyle(
                  color: AppTheme.destructive,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppGhostButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        AppPrimaryButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  String _rangeLabel(CalendarExceptionRange range) {
    if (range.isMakeup) {
      final exception = range.exceptions.single;
      final makeupForDate = exception.makeupForDate;
      if (makeupForDate == null) return '${formatDateMd(exception.date)} 补课';
      final week = widget.term.teachingWeekOf(makeupForDate);
      final cycle = week == null
          ? '课表'
          : '${widget.term.weekCycleLabel(week)}课表';
      return '${formatDateMd(exception.date)} 补 ${formatDateMd(makeupForDate)}'
          '（${weekdayFullName(makeupForDate.weekday)}·$cycle）';
    }
    final dateLabel = range.startDate == range.endDate
        ? formatDateMd(range.startDate)
        : '${formatDateMd(range.startDate)} – ${formatDateMd(range.endDate)}';
    return range.note.trim().isEmpty
        ? '$dateLabel 停课'
        : '$dateLabel ${range.note}';
  }

  String _dateKey(DateTime date) => formatDateYmd(dateOnly(date));

  static String _newId() =>
      'calendar_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';
}

class _ExceptionDialogTitle extends StatelessWidget {
  const _ExceptionDialogTitle({
    required this.contextLabel,
    required this.onClose,
  });

  final String contextLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text(
        '编辑教学周',
        style: TextStyle(
          color: AppTheme.ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 22 / 15,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          contextLabel,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            height: 17 / 12,
          ),
        ),
      ),
      AppIconButton(
        onPressed: onClose,
        tooltip: '关闭',
        icon: Icons.close,
        iconSize: 14,
      ),
    ],
  );
}

class _ExceptionFieldLabel extends StatelessWidget {
  const _ExceptionFieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AppTheme.inkSecondary,
        fontSize: 12,
        height: 17 / 12,
      ),
    ),
  );
}

class _ExceptionRangeChip extends StatelessWidget {
  const _ExceptionRangeChip({
    required this.label,
    required this.isMakeup,
    required this.onPressed,
    required this.onDelete,
  });

  final String label;
  final bool isMakeup;
  final VoidCallback onPressed;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final foreground = isMakeup
        ? const Color(0xFFE37318)
        : const Color(0xFFC63D36);
    return FTappable(
      semanticsLabel: label,
      onPress: onPressed,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isMakeup ? const Color(0xFFFFF1E8) : const Color(0xFFFFF8F8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                height: 16 / 11,
              ),
            ),
            const SizedBox(width: 6),
            FTappable(
              semanticsLabel: '删除 $label',
              onPress: onDelete,
              child: SizedBox(
                width: 12,
                height: 16,
                child: Icon(Icons.close, size: 10, color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
