import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

/// 配对课程弹窗（US-013 AC2 / 设计稿 03c）。
///
/// 同班两门课（一单一双）共用同一时段；不配对也可由求解器分别安排。
/// 配对只约束「两门课必须占同一时段」，不改变各自节数与周模式；
/// 在弹窗内暂存更改，页面点击「保存」后生效。
class PairingDialog extends StatefulWidget {
  const PairingDialog({
    required this.classes,
    required this.subjects,
    required this.pairings,
    required this.subjectNames,
    required this.classLabels,
    required this.gradeLabels,
    required this.valuesByClassAndSubject,
    super.key,
  });

  /// 当前学段的班级。
  final List<ClassBrief> classes;

  /// 全校科目。
  final List<Subject> subjects;

  /// 当前学段班级的全部配对。
  final List<SubjectPairing> pairings;

  /// 科目 ID → 名称（含暂存的新科目）。
  final Map<String, String> subjectNames;

  /// 班级 ID → 下拉显示标签（同名班级已按学段/年级消歧）。
  final Map<String, String> classLabels;
  final Map<String, String> gradeLabels;
  final Map<(String, String), ClassSubjectValues> valuesByClassAndSubject;

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  late List<SubjectPairing> _pairings;
  String? _classId;
  String? _oddSubjectId;
  String? _evenSubjectId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pairings = List.of(widget.pairings);
    _classId = widget.classes.isNotEmpty
        ? 'grade:${widget.classes.first.gradeId}'
        : null;
  }

  List<ClassBrief> get _selectedClasses => _classId == null
      ? []
      : _classId!.startsWith('grade:')
      ? widget.classes
            .where((item) => item.gradeId == _classId!.substring(6))
            .toList()
      : widget.classes.where((item) => item.id == _classId).toList();

  List<Subject> _eligibleSubjects(WeekMode mode) =>
      widget.subjects.where((subject) {
        final classes = _selectedClasses;
        return classes.isNotEmpty &&
            classes.every((schoolClass) {
              final values =
                  widget.valuesByClassAndSubject[(schoolClass.id, subject.id)];
              return mode == WeekMode.odd
                  ? (values?.odd ?? 0) > 0
                  : (values?.even ?? 0) > 0;
            });
      }).toList();

  List<SubjectPairing> get _visiblePairings {
    final classIds = widget.classes.map((classBrief) => classBrief.id).toSet();
    return _pairings
        .where((pairing) => classIds.contains(pairing.classId))
        .toList();
  }

  String _className(String classId) =>
      widget.classLabels[classId] ??
      widget.classes
          .where((classBrief) => classBrief.id == classId)
          .map((classBrief) => classBrief.name)
          .firstOrNull ??
      classId;

  void _addPairing() {
    final classes = _selectedClasses;
    final oddSubjectId = _oddSubjectId;
    final evenSubjectId = _evenSubjectId;
    if (classes.isEmpty || oddSubjectId == null || evenSubjectId == null) {
      setState(() => _error = '请选择年级或班级与两门科目');
      return;
    }
    if (oddSubjectId == evenSubjectId) {
      setState(() => _error = '两门科目不能相同');
      return;
    }
    final invalid = classes.where((schoolClass) {
      final odd =
          widget.valuesByClassAndSubject[(schoolClass.id, oddSubjectId)]?.odd ??
          0;
      final even =
          widget
              .valuesByClassAndSubject[(schoolClass.id, evenSubjectId)]
              ?.even ??
          0;
      return odd == 0 || odd != even;
    }).toList();
    if (invalid.isNotEmpty) {
      setState(
        () => _error =
            '${invalid.map((item) => _className(item.id)).join('、')}的单周与双周节数须相同且大于 0',
      );
      return;
    }
    final conflicts = classes
        .where(
          (schoolClass) => _pairings.any(
            (pairing) =>
                pairing.classId == schoolClass.id &&
                (pairing.oddSubjectId == oddSubjectId ||
                    pairing.evenSubjectId == evenSubjectId) &&
                (pairing.oddSubjectId != oddSubjectId ||
                    pairing.evenSubjectId != evenSubjectId),
          ),
        )
        .toList();
    if (conflicts.isNotEmpty) {
      setState(
        () => _error =
            '${conflicts.map((item) => _className(item.id)).join('、')}已有占用所选科目的配对，请先解除',
      );
      return;
    }
    final missing = classes
        .where(
          (schoolClass) => !_pairings.any(
            (pairing) =>
                pairing.classId == schoolClass.id &&
                pairing.oddSubjectId == oddSubjectId &&
                pairing.evenSubjectId == evenSubjectId,
          ),
        )
        .toList();
    if (missing.isEmpty) {
      setState(() => _error = '所选范围已存在相同配对');
      return;
    }
    setState(() {
      _error = null;
      for (var index = 0; index < missing.length; index++) {
        _pairings.add(
          SubjectPairing(
            id: 'pairing_${DateTime.now().microsecondsSinceEpoch}_$index',
            classId: missing[index].id,
            oddSubjectId: oddSubjectId,
            evenSubjectId: evenSubjectId,
          ),
        );
      }
      _oddSubjectId = null;
      _evenSubjectId = null;
    });
  }

  void _removePairing(SubjectPairing pairing) {
    setState(() {
      _pairings.remove(pairing);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePairings;
    return AppDialog(
      title: const Text('配对课程'),
      maxWidth: 860,
      content: SizedBox(
        width: 810,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '同班两门（一单一双）共用同一时段；不配对也可由求解器分别安排。',
              style: TextStyle(
                color: context.appColors.inkSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            if (visible.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '还没有配对。新增配对后，两门课将占用同一时段。',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 12,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final pairing in visible)
                        _PairingRow(
                          pairing: pairing,
                          oddName:
                              widget.subjectNames[pairing.oddSubjectId] ??
                              '未知科目',
                          evenName:
                              widget.subjectNames[pairing.evenSubjectId] ??
                              '未知科目',
                          className: _className(pairing.classId),
                          onRemove: () => _removePairing(pairing),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Text(
              '+ 新增配对',
              style: TextStyle(
                color: context.appColors.blue,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 280
                        ? constraints.maxWidth
                        : 280,
                    child: AppSelectField<String>(
                      items: {
                        for (final gradeId
                            in widget.classes
                                .map((item) => item.gradeId)
                                .toSet())
                          '${widget.gradeLabels[gradeId] ?? gradeId} · 全部班级':
                              'grade:$gradeId',
                        for (final classBrief in widget.classes)
                          widget.classLabels[classBrief.id] ?? classBrief.name:
                              classBrief.id,
                      },
                      value: _classId,
                      hint: '年级或班级',
                      onChanged: (value) => setState(() {
                        _classId = value;
                        _oddSubjectId = null;
                        _evenSubjectId = null;
                        _error = null;
                      }),
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth < 210
                        ? constraints.maxWidth
                        : 210,
                    child: AppSelectField<String>(
                      items: {
                        for (final subject in _eligibleSubjects(WeekMode.odd))
                          subject.name: subject.id,
                      },
                      value: _oddSubjectId,
                      hint: '科目 A（单周）',
                      onChanged: (value) =>
                          setState(() => _oddSubjectId = value),
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth < 210
                        ? constraints.maxWidth
                        : 210,
                    child: AppSelectField<String>(
                      items: {
                        for (final subject in _eligibleSubjects(WeekMode.even))
                          subject.name: subject.id,
                      },
                      value: _evenSubjectId,
                      hint: '科目 B（双周）',
                      onChanged: (value) =>
                          setState(() => _evenSubjectId = value),
                    ),
                  ),
                  AppSecondaryButton(
                    onPressed: _addPairing,
                    child: const Text('添加'),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: context.appColors.destructive,
                  fontSize: 11.5,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              '仅显示所选范围内每个班级均有对应单周或双周节数的科目。两门课在各班的单双周节数须相同；完成后仍需点击页面「保存」才会生效。',
              style: TextStyle(
                color: context.appColors.muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                AppPrimaryButton(
                  onPressed: () => Navigator.pop(context, _pairings),
                  child: const Text('完成'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PairingRow extends StatelessWidget {
  const _PairingRow({
    required this.pairing,
    required this.oddName,
    required this.evenName,
    required this.className,
    required this.onRemove,
  });

  final SubjectPairing pairing;
  final String oddName;
  final String evenName;
  final String className;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: context.appColors.selectedBlue,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        _SubjectChip(label: '$oddName（单周）'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(
            Icons.compare_arrows_rounded,
            size: 14,
            color: context.appColors.blue,
          ),
        ),
        _SubjectChip(label: '$evenName（双周）'),
        const SizedBox(width: 8),
        Text(
          '→ $className',
          style: TextStyle(color: context.appColors.inkSecondary, fontSize: 12),
        ),
        AppGhostButton(
          size: f.FButtonSizeVariant.xs,
          onPressed: onRemove,
          child: Text(
            '解除配对',
            style: TextStyle(color: context.appColors.blue, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _SubjectChip extends StatelessWidget {
  const _SubjectChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.appColors.surface,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: context.appColors.blue,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
