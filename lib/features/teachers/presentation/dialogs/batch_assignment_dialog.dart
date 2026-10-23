part of '../teachers_page.dart';

class _BatchAssignmentSelection {
  const _BatchAssignmentSelection({
    required this.teacherId,
    required this.assignments,
  });

  final String? teacherId;
  final List<_NewAssignmentSelection> assignments;
}

class _BatchAssignmentDraft {
  _BatchAssignmentDraft({
    required this.classId,
    required this.subjectId,
    required this.weekMode,
    int lessonCount = 1,
  }) : lessonCount = TextEditingController(text: '$lessonCount');

  String classId;
  String subjectId;
  WeekMode weekMode;
  final TextEditingController lessonCount;

  void dispose() => lessonCount.dispose();
}

Future<_BatchAssignmentSelection?> _showBatchAssignmentEditor(
  BuildContext context, {
  required List<Teacher> teachers,
  required List<ClassBrief> classes,
  required List<Subject> subjects,
  required Map<String, Set<String>> subjectIdsByClass,
  required Map<String, String> gradeNames,
  required Map<String, String> stageNames,
  required List<SubjectRequirement> requirements,
  required List<TeacherAssignment> existingAssignments,
  Teacher? initialTeacher,
}) async {
  if (teachers.isEmpty || classes.isEmpty || subjects.isEmpty) return null;

  var teacherId = initialTeacher?.id ?? teachers.first.id;
  var errorText = '';
  final subjectOptionsByClass = {
    for (final schoolClass in classes)
      schoolClass.id: buildUniqueSelectOptions<Subject, String>(
        subjects
            .where(
              (subject) =>
                  subjectIdsByClass[schoolClass.id]?.contains(subject.id) ??
                  false,
            )
            .toList(),
        labelOf: (subject) => subject.name,
        valueOf: (subject) => subject.id,
        disambiguatorOf: (subject) => subject.shortName,
        idOf: (subject) => subject.id,
      ),
  };
  final firstClassId = classes.first.id;
  final firstSubjectId = subjectOptionsByClass[firstClassId]!.values.first;
  final classesById = {for (final item in classes) item.id: item};
  List<WeekMode> weekModesFor(String classId, String subjectId) {
    final schoolClass = classesById[classId]!;
    final effectiveRequirements = _effectiveTeacherAssignmentRequirements(
      requirements,
      classId: classId,
      gradeId: schoolClass.gradeId,
      subjectId: subjectId,
    );
    final demandedModes = effectiveRequirements
        .where((requirement) => requirement.lessonCount > 0)
        .map((requirement) => requirement.weekMode)
        .toSet();
    return WeekMode.values
        .where(demandedModes.contains)
        .toList(growable: false);
  }

  final drafts = [
    _BatchAssignmentDraft(
      classId: firstClassId,
      subjectId: firstSubjectId,
      weekMode: weekModesFor(firstClassId, firstSubjectId).first,
    ),
  ];
  final result = await showAppDialog<_BatchAssignmentSelection>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final classOptions = buildUniqueSelectOptions<ClassBrief, String>(
          classes,
          labelOf: (item) => item.name,
          valueOf: (item) => item.id,
          disambiguatorOf: (item) => [
            stageNames[item.stageId],
            gradeNames[item.gradeId],
          ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
          idOf: (item) => item.id,
        );
        return AppDialog(
          title: Text(
            initialTeacher == null
                ? '批量添加任课'
                : '为${initialTeacher.displayName}添加任课',
          ),
          maxWidth: 980,
          content: SizedBox(
            width: 900,
            height: 470,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (initialTeacher == null) ...[
                  AppSelectField<String>(
                    value: teacherId,
                    label: '教师',
                    items: buildUniqueSelectOptions<Teacher, String>(
                      teachers,
                      labelOf: (teacher) => teacher.displayName,
                      valueOf: (teacher) => teacher.id,
                      disambiguatorOf: (teacher) => teacher.shortName,
                      idOf: (teacher) => teacher.id,
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        teacherId = value;
                        errorText = '';
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  '可跨学段添加；只显示已设置需求的科目。同班、同科目、同周模式的分配节数不能超过科目需求。',
                  style: TextStyle(
                    color: context.appColors.muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.appColors.tableHeader,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      children: [
                        Expanded(flex: 4, child: Text('班级')),
                        SizedBox(width: 8),
                        Expanded(flex: 3, child: Text('科目')),
                        SizedBox(width: 8),
                        Expanded(flex: 2, child: Text('周模式')),
                        SizedBox(width: 8),
                        SizedBox(width: 92, child: Text('分担节数')),
                        SizedBox(width: 36),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.separated(
                    itemCount: drafts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      return Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: AppSelectField<String>(
                              value: draft.classId,
                              key: ValueKey('batch-assignment-class-$index'),
                              items: classOptions,
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  draft.classId = value;
                                  final nextSubjectOptions =
                                      subjectOptionsByClass[value]!;
                                  if (!nextSubjectOptions.values.contains(
                                    draft.subjectId,
                                  )) {
                                    draft.subjectId =
                                        nextSubjectOptions.values.first;
                                  }
                                  final nextWeekModes = weekModesFor(
                                    draft.classId,
                                    draft.subjectId,
                                  );
                                  if (!nextWeekModes.contains(draft.weekMode)) {
                                    draft.weekMode = nextWeekModes.first;
                                  }
                                  errorText = '';
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: AppSelectField<String>(
                              value: draft.subjectId,
                              key: ValueKey('batch-assignment-subject-$index'),
                              items: subjectOptionsByClass[draft.classId]!,
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  draft.subjectId = value;
                                  final nextWeekModes = weekModesFor(
                                    draft.classId,
                                    draft.subjectId,
                                  );
                                  if (!nextWeekModes.contains(draft.weekMode)) {
                                    draft.weekMode = nextWeekModes.first;
                                  }
                                  errorText = '';
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: AppSelectField<WeekMode>(
                              key: ValueKey(
                                'batch-assignment-week-mode-$index',
                              ),
                              value: draft.weekMode,
                              items: {
                                for (final mode in weekModesFor(
                                  draft.classId,
                                  draft.subjectId,
                                ))
                                  mode.label: mode,
                              },
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  draft.weekMode = value;
                                  errorText = '';
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 92,
                            child: AppTextFormField(
                              controller: draft.lessonCount,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '节数',
                                isDense: true,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 36,
                            child: AppIconButton(
                              tooltip: '删除此行',
                              onPressed: drafts.length <= 1
                                  ? null
                                  : () => setState(() {
                                      drafts.removeAt(index).dispose();
                                      errorText = '';
                                    }),
                              icon: Icons.close,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText,
                    style: TextStyle(color: context.appColors.destructive),
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppGhostButton.icon(
                    onPressed: () => setState(() {
                      drafts.add(
                        _BatchAssignmentDraft(
                          classId: firstClassId,
                          subjectId: firstSubjectId,
                          weekMode: weekModesFor(
                            firstClassId,
                            firstSubjectId,
                          ).first,
                        ),
                      );
                      errorText = '';
                    }),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('添加一行'),
                  ),
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
              onPressed: () {
                final rows = <_NewAssignmentSelection>[];
                for (final draft in drafts) {
                  final count = int.tryParse(draft.lessonCount.text.trim());
                  if (count == null || count <= 0) {
                    setState(() => errorText = '请为每行填写大于 0 的节数');
                    return;
                  }
                  rows.add(
                    _NewAssignmentSelection(
                      classId: draft.classId,
                      subjectId: draft.subjectId,
                      weekMode: draft.weekMode,
                      lessonCount: count,
                    ),
                  );
                }
                final validationError = _batchAssignmentValidationError(
                  rows: rows,
                  requirements: requirements,
                  existingAssignments: existingAssignments,
                  classesById: classesById,
                  subjectsById: {
                    for (final subject in subjects) subject.id: subject,
                  },
                );
                if (validationError != null) {
                  setState(() => errorText = validationError);
                  return;
                }
                Navigator.pop(
                  context,
                  _BatchAssignmentSelection(
                    teacherId: teacherId,
                    assignments: rows,
                  ),
                );
              },
              child: Text('添加 ${drafts.length} 项'),
            ),
          ],
        );
      },
    ),
  );
  for (final draft in drafts) {
    draft.dispose();
  }
  return result;
}

typedef _BatchDemandKey = ({
  String classId,
  String subjectId,
  WeekMode weekMode,
});
typedef _BatchCellKey = ({String classId, String subjectId});

String? _batchAssignmentValidationError({
  required List<_NewAssignmentSelection> rows,
  required List<SubjectRequirement> requirements,
  required List<TeacherAssignment> existingAssignments,
  required Map<String, ClassBrief> classesById,
  required Map<String, Subject> subjectsById,
}) {
  final currentTotals = <_BatchDemandKey, int>{};
  for (final assignment in existingAssignments) {
    if (assignment.teacherId.isEmpty) continue;
    final key = (
      classId: assignment.classId,
      subjectId: assignment.subjectId,
      weekMode: assignment.weekMode,
    );
    currentTotals.update(
      key,
      (total) => total + assignment.lessonCount,
      ifAbsent: () => assignment.lessonCount,
    );
  }

  final additions = <_BatchDemandKey, int>{};
  final cells = <_BatchCellKey>{};
  for (final row in rows) {
    final key = (
      classId: row.classId,
      subjectId: row.subjectId,
      weekMode: row.weekMode,
    );
    additions.update(
      key,
      (total) => total + row.lessonCount,
      ifAbsent: () => row.lessonCount,
    );
    cells.add((classId: row.classId, subjectId: row.subjectId));
  }

  for (final cell in cells) {
    final schoolClass = classesById[cell.classId]!;
    final subject = subjectsById[cell.subjectId]!;
    final effectiveRequirements = _effectiveTeacherAssignmentRequirements(
      requirements,
      classId: cell.classId,
      gradeId: schoolClass.gradeId,
      subjectId: cell.subjectId,
    );
    final demandedRequirements = effectiveRequirements
        .where((requirement) => requirement.lessonCount > 0)
        .toList(growable: false);
    if (demandedRequirements.isEmpty) {
      return '${schoolClass.name} · ${subject.name}尚未设置节数需求，不能分配任课';
    }

    final demandedModes = demandedRequirements
        .map((requirement) => requirement.weekMode)
        .toSet();
    final cellRows = rows
        .where(
          (row) =>
              row.classId == cell.classId && row.subjectId == cell.subjectId,
        )
        .toList(growable: false);
    if (cellRows.any((row) => !demandedModes.contains(row.weekMode))) {
      final invalidMode = cellRows
          .firstWhere((row) => !demandedModes.contains(row.weekMode))
          .weekMode;
      return '${schoolClass.name} · ${subject.name}未设置${invalidMode.label}需求，不能分配任课';
    }

    for (final requirement in demandedRequirements) {
      final key = (
        classId: cell.classId,
        subjectId: cell.subjectId,
        weekMode: requirement.weekMode,
      );
      final total = (currentTotals[key] ?? 0) + (additions[key] ?? 0);
      if (total > requirement.lessonCount) {
        return '${schoolClass.name} · ${subject.name} · ${requirement.weekMode.label}分配共 $total 节，超过需求 ${requirement.lessonCount} 节';
      }
    }
  }
  return null;
}
