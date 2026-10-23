import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

/// 「各班不同」下钻弹窗：逐班填写 每周 / 单周 / 双周节数。
///
/// 学期未开启单双周交替（[alternatingWeeks] = false）时只展示每周一列。
///
/// 返回值：班级 ID → 三档节数（仅返回有改动的班级由调用方合并）。
class ClassDetailDialog extends StatefulWidget {
  const ClassDetailDialog({
    required this.subject,
    required this.gradeName,
    required this.classes,
    required this.initialValues,
    required this.capacities,
    required this.alternatingWeeks,
    super.key,
  });

  final Subject subject;
  final String gradeName;
  final List<ClassBrief> classes;

  /// 班级 ID → 初始三档节数。
  final Map<String, ClassSubjectValues> initialValues;

  /// 班级 ID → 单 / 双周容量。
  final Map<String, ClassCapacity> capacities;

  /// 当前学期是否开启单双周交替；未开启时隐藏单 / 双周配置列。
  final bool alternatingWeeks;

  @override
  State<ClassDetailDialog> createState() => _ClassDetailDialogState();
}

class _ClassDetailDialogState extends State<ClassDetailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quickFillController = TextEditingController();
  late final Map<String, ClassSubjectValues> _values;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final entry in widget.initialValues.entries) entry.key: entry.value,
    };
  }

  @override
  void dispose() {
    _quickFillController.dispose();
    super.dispose();
  }

  void _setValue(String classId, {int? weekly, int? odd, int? even}) {
    final current = _values[classId] ?? const ClassSubjectValues();
    setState(() {
      _values[classId] = current.copyWith(weekly: weekly, odd: odd, even: even);
    });
  }

  void _applyQuickFill() {
    final parts = _quickFillController.text
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .toList();
    for (var index = 0; index < widget.classes.length; index++) {
      final count = index < parts.length ? parts[index] : null;
      if (count == null || count < 0) continue;
      _setValue(widget.classes[index].id, weekly: count);
    }
  }

  void _clearAll() {
    setState(() {
      for (final classBrief in widget.classes) {
        _values[classBrief.id] = const ClassSubjectValues();
      }
    });
  }

  ({int weekly, int odd, int even}) get _totals {
    var weekly = 0;
    var odd = 0;
    var even = 0;
    for (final values in _values.values) {
      weekly += values.weekly;
      odd += values.oddWeekDemand;
      even += values.evenWeekDemand;
    }
    return (weekly: weekly, odd: odd, even: even);
  }

  @override
  Widget build(BuildContext context) {
    final totals = _totals;
    final overClasses = _overCapacityClasses();
    final alternating = widget.alternatingWeeks;
    return AppDialog(
      title: Text('${widget.subject.name} · ${widget.gradeName}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                alternating
                    ? '共 ${widget.classes.length} 个班；每周节数计入单双周，单周 / 双周仅计入对应周次。'
                    : '共 ${widget.classes.length} 个班；录入每周节数，所有周使用同一套课表。',
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _DetailHeader(alternatingWeeks: alternating),
                    for (final classBrief in widget.classes)
                      _DetailRow(
                        classBrief: classBrief,
                        values:
                            _values[classBrief.id] ??
                            const ClassSubjectValues(),
                        capacity: widget.capacities[classBrief.id],
                        alternatingWeeks: alternating,
                        onChanged: ({weekly, odd, even}) => _setValue(
                          classBrief.id,
                          weekly: weekly,
                          odd: odd,
                          even: even,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    alternating
                        ? '合计 单周 ${totals.odd} · 双周 ${totals.even} 节'
                        : '合计每周 ${totals.weekly} 节',
                    style: TextStyle(
                      color: context.appColors.inkSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (overClasses.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  overClasses.join('；'),
                  style: TextStyle(
                    color: context.appColors.destructive,
                    fontSize: 11.5,
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
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _values);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  List<String> _overCapacityClasses() {
    final messages = <String>[];
    for (final classBrief in widget.classes) {
      final values = _values[classBrief.id] ?? const ClassSubjectValues();
      final capacity = widget.capacities[classBrief.id];
      if (capacity == null) continue;
      if (values.oddWeekDemand > capacity.oddWeek) {
        messages.add(
          '${classBrief.name}单周需求 ${values.oddWeekDemand} / 容量 ${capacity.oddWeek}，'
          '超 ${values.oddWeekDemand - capacity.oddWeek} 节',
        );
      } else if (values.evenWeekDemand > capacity.evenWeek) {
        messages.add(
          '${classBrief.name}双周需求 ${values.evenWeekDemand} / 容量 ${capacity.evenWeek}，'
          '超 ${values.evenWeekDemand - capacity.evenWeek} 节',
        );
      }
    }
    return messages;
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.alternatingWeeks});

  final bool alternatingWeeks;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.appColors.border)),
    ),
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              '班级',
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 62,
          child: Center(
            child: Text(
              '每周',
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (alternatingWeeks) ...[
          SizedBox(
            width: 62,
            child: Center(
              child: Text(
                '单周',
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Center(
              child: Text(
                '双周',
                style: TextStyle(
                  color: context.appColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.classBrief,
    required this.values,
    required this.capacity,
    required this.alternatingWeeks,
    required this.onChanged,
  });

  final ClassBrief classBrief;
  final ClassSubjectValues values;
  final ClassCapacity? capacity;
  final bool alternatingWeeks;

  final void Function({int? weekly, int? odd, int? even}) onChanged;

  @override
  Widget build(BuildContext context) {
    final overOdd =
        capacity != null && values.oddWeekDemand > capacity!.oddWeek;
    final overEven =
        capacity != null && values.evenWeekDemand > capacity!.evenWeek;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                classBrief.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.appColors.ink, fontSize: 12),
              ),
            ),
          ),
          _CountField(
            value: values.weekly,
            onChanged: (value) => onChanged(weekly: value),
          ),
          if (alternatingWeeks) ...[
            _CountField(
              value: values.odd,
              isOver: overOdd,
              onChanged: (value) => onChanged(odd: value),
            ),
            _CountField(
              value: values.even,
              isOver: overEven,
              onChanged: (value) => onChanged(even: value),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountField extends StatelessWidget {
  const _CountField({
    required this.value,
    required this.onChanged,
    this.isOver = false,
  });

  final int value;
  final bool isOver;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 62,
    child: Center(
      child: SizedBox(
        width: 52,
        child: AppTextFormField(
          initialValue: value == 0 ? '' : '$value',
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 9,
            ),
            enabledBorder: isOver
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(9)),
                    borderSide: BorderSide(
                      color: context.appColors.destructive,
                    ),
                  )
                : null,
          ),
          validator: (input) {
            final text = input?.trim() ?? '';
            if (text.isEmpty) return null;
            final parsed = int.tryParse(text);
            if (parsed == null || parsed < 0) return '无效';
            return null;
          },
          onChanged: (input) => onChanged(int.tryParse(input.trim()) ?? 0),
        ),
      ),
    ),
  );
}
