import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:flutter/material.dart';

class TermEditorResult {
  const TermEditorResult({required this.term, this.cloneSourceTermId});

  final AcademicTerm term;
  final String? cloneSourceTermId;
}

class TermEditorDialog extends StatefulWidget {
  const TermEditorDialog({
    this.term,
    this.availableTerms = const [],
    this.existingExceptions = const [],
    super.key,
  });

  final AcademicTerm? term;
  final List<AcademicTerm> availableTerms;
  final List<CalendarException> existingExceptions;

  @override
  State<TermEditorDialog> createState() => _TermEditorDialogState();
}

class _TermEditorDialogState extends State<TermEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _weekCountController;
  late AcademicTermCycle _cycleMode;
  late String _creationMode;
  String? _cloneSourceId;
  DateTime? _firstTeachingWeekStart;
  String? _dateValidationError;

  bool get _isCreating => widget.term == null;

  @override
  void initState() {
    super.initState();
    final term = widget.term;
    final now = DateTime.now();
    final semesterLabel =
        term?.semesterLabel ?? (now.month >= 7 ? '秋季学期' : '春季学期');
    _titleController = TextEditingController(
      text: term?.title ?? '${now.year} 学年 · $semesterLabel',
    );
    _weekCountController = TextEditingController(
      text: '${term?.teachingWeekCount ?? 20}',
    );
    _firstTeachingWeekStart = term?.firstTeachingWeekStart;
    _cycleMode = term?.cycleMode ?? AcademicTermCycle.alternating;
    _creationMode = 'blank';
    _cloneSourceId = widget.availableTerms.isEmpty
        ? null
        : widget.availableTerms.first.id;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _weekCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 620,
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
    titleGap: 13,
    actionsGap: 13,
    title: AppDialogTitle(
      title: _isCreating ? '新建学期' : '编辑学期信息',
      onClose: () => Navigator.pop(context),
    ),
    content: SizedBox(
      width: 572,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isCreating) ...[
              AppLabeledFieldRow(
                label: '创建方式',
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    AppRadioOption<String>(
                      value: 'blank',
                      groupValue: _creationMode,
                      label: '空白创建',
                      compact: true,
                      onChanged: (value) => setState(() {
                        _creationMode = value;
                        _dateValidationError = null;
                      }),
                    ),
                    AppRadioOption<String>(
                      value: 'clone',
                      groupValue: _creationMode,
                      label: '复制上学期课表（含教学日历）',
                      enabled: widget.availableTerms.isNotEmpty,
                      compact: true,
                      onChanged: (value) => setState(() {
                        _creationMode = value;
                        _dateValidationError = null;
                      }),
                    ),
                  ],
                ),
              ),
              if (widget.availableTerms.isEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.only(left: 110),
                  child: Text(
                    '暂无可复制的学期资料。',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 13),
            ],
            AppLabeledFieldRow(
              label: '学期名称',
              child: AppTextFormField(
                size: .sm,
                controller: _titleController,
                decoration: const InputDecoration(hintText: '如：2027 学年 · 春季学期'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入学期名称' : null,
              ),
            ),
            const SizedBox(height: 13),
            AppLabeledFieldRow(
              label: '第 1 教学周起始',
              labelHelp: '调整日期会重新映射周次和单双周；已有例外保留公历日期。',
              child: AppDateField(
                value: _firstTeachingWeekStart,
                hint: '选择日期',
                firstDate: DateTime(DateTime.now().year - 10),
                lastDate: DateTime(DateTime.now().year + 10),
                format: formatDateYmdWithWeekday,
                onChanged: (date) => setState(() {
                  _firstTeachingWeekStart = date;
                  _dateValidationError = null;
                }),
              ),
            ),
            const SizedBox(height: 13),
            AppLabeledFieldRow(
              label: '总周数',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _StepperButton(
                    icon: Icons.remove,
                    onPressed: () => _changeWeekCount(-1),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: AppTextFormField(
                      size: .sm,
                      controller: _weekCountController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      textAlignVertical: TextAlignVertical.center,
                      borderless: true,
                      validator: (value) {
                        final count = int.tryParse(value ?? '');
                        return count == null || count < 1 || count > 52
                            ? '请输入 1–52 之间的周数'
                            : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 20,
                    child: Text(
                      '周',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.appColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StepperButton(
                    icon: Icons.add,
                    onPressed: () => _changeWeekCount(1),
                    emphasized: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            AppLabeledFieldRow(
              label: '课表周期',
              labelHelp: '单双周交替时第 1 教学周固定为单周；每周相同则所有周使用同一套周课表。',
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  AppRadioOption<AcademicTermCycle>(
                    value: AcademicTermCycle.everyWeek,
                    groupValue: _cycleMode,
                    label: '每周相同',
                    compact: true,
                    onChanged: (value) => setState(() => _cycleMode = value),
                  ),
                  AppRadioOption<AcademicTermCycle>(
                    value: AcademicTermCycle.alternating,
                    groupValue: _cycleMode,
                    label: '单双周交替',
                    compact: true,
                    onChanged: (value) => setState(() => _cycleMode = value),
                  ),
                ],
              ),
            ),
            if (_dateValidationError != null) ...[
              const SizedBox(height: 12),
              Text(
                _dateValidationError!,
                style: TextStyle(
                  color: context.appColors.destructive,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      AppGhostButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppPrimaryButton(
        onPressed: _submit,
        child: Text(_isCreating ? '创建' : '保存'),
      ),
    ],
  );

  void _changeWeekCount(int delta) {
    final current = int.tryParse(_weekCountController.text) ?? 20;
    final next = (current + delta).clamp(1, 52);
    _weekCountController.value = TextEditingValue(
      text: '$next',
      selection: TextSelection.collapsed(offset: '$next'.length),
    );
    setState(() => _dateValidationError = null);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_isCreating && _firstTeachingWeekStart == null) {
      setState(() => _dateValidationError = '请选择第 1 教学周起始日期');
      return;
    }
    if (_isCreating &&
        _creationMode == 'clone' &&
        (_cloneSourceId == null || widget.availableTerms.isEmpty)) {
      setState(() => _dateValidationError = '当前没有可复制的学期资料');
      return;
    }

    final now = DateTime.now();
    final title = _titleController.text.trim();
    final titleUnchanged = widget.term?.title == title;
    final yearMatch = RegExp(r'\d{4}(?:-\d{4})?').firstMatch(title);
    final academicYear = titleUnchanged
        ? widget.term!.academicYear
        : yearMatch?.group(0) ??
              widget.term?.academicYear ??
              '${now.year}-${now.year + 1}';
    final semesterLabel = titleUnchanged
        ? widget.term!.semesterLabel
        : title.contains('春')
        ? '春季学期'
        : title.contains('秋')
        ? '秋季学期'
        : widget.term?.semesterLabel ?? (now.month >= 7 ? '秋季学期' : '春季学期');
    final candidate = AcademicTerm(
      id: widget.term?.id ?? now.microsecondsSinceEpoch.toString(),
      title: title,
      academicYear: academicYear,
      semesterLabel: semesterLabel,
      firstTeachingWeekStart: _firstTeachingWeekStart,
      teachingWeekCount: int.parse(_weekCountController.text),
      createdAt: widget.term?.createdAt ?? now,
      cycleMode: _cycleMode,
    );
    final outOfRangeDates = <DateTime>{};
    for (final exception in widget.existingExceptions) {
      if (candidate.teachingWeekOf(exception.date) == null) {
        outOfRangeDates.add(dateOnly(exception.date));
      }
      final makeupForDate = exception.makeupForDate;
      if (makeupForDate != null &&
          candidate.teachingWeekOf(makeupForDate) == null) {
        outOfRangeDates.add(dateOnly(makeupForDate));
      }
    }
    if (outOfRangeDates.isNotEmpty) {
      final dates = outOfRangeDates.map(formatDateYmd).join('、');
      setState(() => _dateValidationError = '以下例外日期超出学期范围，请先调整或删除：$dates');
      return;
    }
    Navigator.pop(
      context,
      TermEditorResult(
        term: candidate,
        cloneSourceTermId: _creationMode == 'clone' ? _cloneSourceId : null,
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => AppIconButton(
    onPressed: onPressed,
    tooltip: icon == Icons.add ? '增加周数' : '减少周数',
    icon: icon,
    iconSize: 14,
    foregroundColor: emphasized
        ? context.appColors.blue
        : context.appColors.inkSecondary,
  );
}
