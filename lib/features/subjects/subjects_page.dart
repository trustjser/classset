import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/dialogs/add_subject_dialog.dart';
import 'package:class_set/features/subjects/dialogs/class_detail_dialog.dart';
import 'package:class_set/features/subjects/dialogs/pairing_dialog.dart';
import 'package:class_set/features/subjects/dialogs/subject_preset_dialog.dart';
import 'package:class_set/features/subjects/subjects_data.dart';
import 'package:class_set/features/subjects/widgets/capacity_summary_section.dart';
import 'package:class_set/features/subjects/widgets/subject_matrix.dart';
import 'package:class_set/features/subjects/widgets/subject_scope_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 科目节数：科目 × 年级矩阵 + 按班下钻 + 容量校验（US-012/013）。
class SubjectsPage extends ConsumerStatefulWidget {
  const SubjectsPage({required this.termId, super.key});

  final String termId;

  @override
  ConsumerState<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends ConsumerState<SubjectsPage> {
  /// 当前范围：null = 全校，否则学段 ID。
  String? _scopeStageId;

  /// 「科目预设」列的上下文年级（最近点击的矩阵列；默认首个可见年级）。
  String? _presetGradeId;

  /// 可见年级列；空 = 全部显示。
  final Set<String> _visibleGradeIds = {};

  /// 草稿：scopeKey → 节数；未命中时回退到流数据。
  final Map<String, int> _draft = {};

  /// 当前学期是否开启单双周交替（build 时随学期刷新）。
  bool _alternatingWeeks = true;

  /// 暂存的新增科目（保存时落库）。
  final List<Subject> _newSubjects = [];

  bool _saving = false;

  static String _scopeKey(
    String subjectId,
    String classId,
    WeekMode mode,
  ) => '${subjectId}_${classId}_${mode.storageValue}';

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(termsProvider);
    return terms.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          _ErrorPanel(message: '读取本地学期数据失败：$error'),
      data: (items) {
        final selected = items.where((item) => item.id == widget.termId);
        final term = selected.isEmpty ? items.first : selected.first;
        return _buildContent(term);
      },
    );
  }

  Widget _buildContent(AcademicTerm term) {
    // 未开启单双周交替的学期只提供每周节数配置。
    _alternatingWeeks = term.cycleMode == AcademicTermCycle.alternating;
    final stages = ref.watch(stagesProvider(term.id)).valueOrNull ?? const [];
    if (stages.isEmpty) {
      return _NoStages(
        onGoToClasses: () =>
            ref.read(selectedSectionProvider.notifier).state =
                AppSection.classes,
      );
    }
    final allGrades =
        ref.watch(gradesForTermProvider(term.id)).valueOrNull ??
        const <GradeGroup>[];
    final classBriefs =
        ref.watch(classesForTermProvider(term.id)).valueOrNull ??
        const <ClassBrief>[];
    final streamSubjects =
        ref.watch(subjectsProvider).valueOrNull ?? const <Subject>[];
    final subjects = [...streamSubjects, ..._newSubjects];
    final requirements =
        ref.watch(allRequirementsProvider).valueOrNull ??
        const <SubjectRequirement>[];
    final presets =
        ref.watch(allPresetsProvider).valueOrNull ?? const <SubjectPreset>[];
    final routines =
        ref.watch(routinesForTermProvider(term.id)).valueOrNull ??
        const <String, StageRoutine>{};
    final freeSlots =
        ref.watch(freeSlotsForTermProvider(term.id)).valueOrNull ??
        const <FreeSlot>[];

    final gradeCountByStage = <String, int>{
      for (final stage in stages)
        stage.id: allGrades
            .where((grade) => grade.stageId == stage.id)
            .length,
    };
    final scopeGrades = _scopeStageId == null
        ? allGrades
        : allGrades
              .where((grade) => grade.stageId == _scopeStageId)
              .toList();
    final visibleGrades = scopeGrades
        .where(
          (grade) =>
              _visibleGradeIds.isEmpty || _visibleGradeIds.contains(grade.id),
        )
        .toList();
    final classesByGrade = <String, List<ClassBrief>>{
      for (final grade in visibleGrades)
        grade.id: classBriefs
            .where((classBrief) => classBrief.gradeId == grade.id)
            .toList(),
    };
    final contextGrade = _resolveContextGrade(
      allGrades: allGrades,
      visibleGrades: visibleGrades,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.pagePaddingForWidth(
          MediaQuery.sizeOf(context).width,
        ),
        vertical: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: '科目节数',
            subtitle: _alternatingWeeks
                ? '默认录入每周节数；单双周与科目预设点击单元格设置。'
                : '默认录入每周节数；科目预设点击单元格设置。',
            actions: [
              AppGhostButton(
                onPressed: _openAddSubject,
                child: const Text(
                  '+ 添加科目',
                  style: TextStyle(
                    color: AppTheme.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AppMenuButton(
                items: [
                  AppMenuItem(
                    label: '配对课程',
                    onPressed: _openPairing,
                  ),
                  AppMenuItem(
                    label: '生成模板',
                    onPressed: _showComingSoon,
                  ),
                  AppMenuItem(
                    label: '导入 Excel',
                    onPressed: _showComingSoon,
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '更多',
                        style: TextStyle(
                          color: AppTheme.inkSecondary,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.expand_more_rounded,
                        size: 15,
                        color: AppTheme.muted,
                      ),
                    ],
                  ),
                ),
              ),
              AppPrimaryButton(
                onPressed:
                    (_draft.isEmpty && _newSubjects.isEmpty) || _saving
                    ? null
                    : _save,
                child: Text(_saving ? '保存中' : '保存'),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.pageSectionGap),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scope = SubjectScopeSelector(
                  stages: stages,
                  gradeCountByStage: gradeCountByStage,
                  totalGradeCount: allGrades.length,
                  selectedScopeStageId: _scopeStageId,
                  grades: scopeGrades,
                  visibleGradeIds: _visibleGradeIds.isEmpty
                      ? scopeGrades.map((grade) => grade.id).toSet()
                      : _visibleGradeIds,
                  // 学段选项与矩阵列头同色：按全局学段序号取强调色。
                  accentForStage: (stage) => AppTheme.stageAccent(
                    stages.indexWhere((item) => item.id == stage.id),
                  ),
                  onSelectStage: (value) => setState(() {
                    _scopeStageId = value;
                    _visibleGradeIds.clear();
                  }),
                  onToggleGrade: (gradeId) => setState(() {
                    if (!_visibleGradeIds.remove(gradeId)) {
                      _visibleGradeIds.add(gradeId);
                    }
                  }),
                  onSelectAllGrades: () => setState(() {
                    _visibleGradeIds.addAll(
                      scopeGrades.map((grade) => grade.id),
                    );
                  }),
                  onClearGrades: () => setState(_visibleGradeIds.clear),
                );
                final matrix = SubjectMatrix(
                  subjects: subjects,
                  visibleGrades: visibleGrades,
                  classesByGrade: classesByGrade,
                  visibleStages: stages
                      .where(
                        (stage) => visibleGrades.any(
                          (grade) => grade.stageId == stage.id,
                        ),
                      )
                      .toList(),
                  // 按全局学段序号取色：单学段视图下颜色不漂移。
                  accentForStage: (stage) => AppTheme.stageAccent(
                    stages.indexWhere((item) => item.id == stage.id),
                  ),
                  valuesFor: (subjectId, classId) =>
                      _effectiveValues(subjectId, classId, requirements),
                  summaries: _summaries(
                    grades: visibleGrades,
                    classBriefs: classBriefs,
                    subjects: subjects,
                    requirements: requirements,
                    routines: routines,
                    freeSlots: freeSlots,
                    termId: term.id,
                  ),
                  presetSummaries: _presetSummaries(
                    subjects: subjects,
                    presets: presets,
                    allGrades: allGrades,
                    contextGrade: contextGrade,
                    classBriefs: classBriefs,
                  ),
                  onCellTap: (subject, grade) {
                    // 单击仅选中；表单改为右键「编辑」进入。
                    setState(() => _presetGradeId = grade.id);
                  },
                  onCellCommit: _applyCellInput,
                  onEditRequest: _openClassDetail,
                  onMessage: _showMessage,
                  alternatingWeeks: _alternatingWeeks,
                  onPresetTap: (subject, grade) {
                    setState(() => _presetGradeId = grade.id);
                    _openSubjectPreset(subject, grade);
                  },
                  scrollable: constraints.maxWidth >= 1040,
                );
                final capacity = CapacitySummarySection(
                  grades: visibleGrades,
                  summaries: _summaries(
                    grades: visibleGrades,
                    classBriefs: classBriefs,
                    subjects: subjects,
                    requirements: requirements,
                    routines: routines,
                    freeSlots: freeSlots,
                    termId: term.id,
                  ),
                );
                if (constraints.maxWidth >= 1040) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 252, child: scope),
                            const SizedBox(width: AppTheme.pageSectionGap),
                            Expanded(child: matrix),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppTheme.pageSectionGap),
                      capacity,
                    ],
                  );
                }
                // 窄屏：整页单层滚动；矩阵自然高度（不内部滚动），
                // 避免嵌套滚动导致的双滚动条与滚动卡住。
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      scope,
                      const SizedBox(height: AppTheme.pageSectionGap),
                      matrix,
                      const SizedBox(height: AppTheme.pageSectionGap),
                      capacity,
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 生效值：草稿优先，否则取流数据。
  ClassSubjectValues _effectiveValues(
    String subjectId,
    String classId,
    List<SubjectRequirement> requirements,
  ) {
    final weekly = _draft[_scopeKey(subjectId, classId, WeekMode.weekly)];
    final odd = _draft[_scopeKey(subjectId, classId, WeekMode.odd)];
    final even = _draft[_scopeKey(subjectId, classId, WeekMode.even)];
    if (weekly != null || odd != null || even != null) {
      return ClassSubjectValues(
        weekly: weekly ?? 0,
        odd: odd ?? 0,
        even: even ?? 0,
      );
    }
    return valuesForClass(
      subjectId: subjectId,
      classId: classId,
      requirements: requirements,
    );
  }

  Map<String, GradeCapacitySummary> _summaries({
    required List<GradeGroup> grades,
    required List<ClassBrief> classBriefs,
    required List<Subject> subjects,
    required List<SubjectRequirement> requirements,
    required Map<String, StageRoutine> routines,
    required List<FreeSlot> freeSlots,
    required String termId,
  }) {
    final effective = _effectiveRequirements(
      subjects: subjects,
      classBriefs: classBriefs,
      baseRequirements: requirements,
    );
    return {
      for (final grade in grades)
        if (routines[grade.stageId] != null)
          grade.id: summarizeGradeCapacity(
            grade: grade,
            classes: classBriefs
                .where((classBrief) => classBrief.gradeId == grade.id)
                .toList(),
            requirements: effective,
            routine: routines[grade.stageId]!,
            freeSlots: freeSlots,
            termId: termId,
          ),
    };
  }

  /// 草稿合并后的全量需求（供容量校验与保存使用）。
  List<SubjectRequirement> _effectiveRequirements({
    required List<Subject> subjects,
    required List<ClassBrief> classBriefs,
    required List<SubjectRequirement> baseRequirements,
  }) {
    final result = <SubjectRequirement>[];
    for (final subject in subjects) {
      for (final classBrief in classBriefs) {
        final values = _effectiveValues(
          subject.id,
          classBrief.id,
          baseRequirements,
        );
        for (final mode in WeekMode.values) {
          final count = switch (mode) {
            WeekMode.weekly => values.weekly,
            WeekMode.odd => values.odd,
            WeekMode.even => values.even,
          };
          if (count <= 0) continue;
          result.add(
            SubjectRequirement(
              id: _scopeKey(subject.id, classBrief.id, mode),
              subjectId: subject.id,
              gradeId: classBrief.gradeId,
              weekMode: mode,
              lessonCount: count,
              classId: classBrief.id,
            ),
          );
        }
      }
    }
    return result;
  }

  /// 内联编辑 / 粘贴提交：单组 = 整年级生效；多组按班级顺序写入草稿。
  void _applyCellInput(
    Subject subject,
    GradeGroup grade,
    List<ClassBrief> classes,
    List<ClassSubjectValues> values,
  ) {
    // 未开启单双周交替的学期不接受单 / 双周节数（w|o|e 格式）。
    if (!_alternatingWeeks &&
        values.any((value) => value.odd != 0 || value.even != 0)) {
      _showMessage('当前学期未开启单双周交替，请直接填写每周节数');
      return;
    }
    setState(() {
      void apply(ClassBrief classBrief, ClassSubjectValues value) {
        _draft[_scopeKey(subject.id, classBrief.id, WeekMode.weekly)] =
            value.weekly;
        _draft[_scopeKey(subject.id, classBrief.id, WeekMode.odd)] =
            value.odd;
        _draft[_scopeKey(subject.id, classBrief.id, WeekMode.even)] =
            value.even;
      }

      if (values.isEmpty) {
        // 空输入 → 整年级清零。
        for (final classBrief in classes) {
          apply(classBrief, const ClassSubjectValues(weekly: 0, odd: 0, even: 0));
        }
      } else if (values.length == 1) {
        for (final classBrief in classes) {
          apply(classBrief, values.single);
        }
      } else {
        for (
          var index = 0;
          index < classes.length && index < values.length;
          index++
        ) {
          apply(classes[index], values[index]);
        }
      }
      _presetGradeId = grade.id;
    });
  }

  Future<void> _openClassDetail(Subject subject, GradeGroup grade) async {
    final classBriefs =
        ref.read(classesForTermProvider(widget.termId)).valueOrNull ??
        const <ClassBrief>[];
    final classes = classBriefs
        .where((classBrief) => classBrief.gradeId == grade.id)
        .toList();
    final requirements =
        ref.read(allRequirementsProvider).valueOrNull ??
        const <SubjectRequirement>[];
    final routines =
        ref.read(routinesForTermProvider(widget.termId)).valueOrNull ??
        const <String, StageRoutine>{};
    final routine = routines[grade.stageId];
    final freeSlots =
        ref.read(freeSlotsForTermProvider(widget.termId)).valueOrNull ??
        const <FreeSlot>[];
    final termId = ref.read(activeTermIdProvider) ?? widget.termId;
    final initialValues = <String, ClassSubjectValues>{
      for (final classBrief in classes)
        classBrief.id: _effectiveValues(subject.id, classBrief.id, requirements),
    };
    final capacities = <String, ClassCapacity>{
      for (final classBrief in classes)
        classBrief.id: routine == null
            ? const ClassCapacity(oddWeek: 0, evenWeek: 0)
            : capacityForClass(
                routine: routine,
                freeSlots: freeSlots,
                termId: termId,
                grade: grade,
                classBrief: classBrief,
              ),
    };
    final result = await showAppDialog<Map<String, ClassSubjectValues>>(
      context: context,
      builder: (context) => ClassDetailDialog(
        subject: subject,
        gradeName: grade.name,
        classes: classes,
        initialValues: initialValues,
        capacities: capacities,
        alternatingWeeks: _alternatingWeeks,
      ),
    );
    if (result == null) return;
    setState(() {
      for (final entry in result.entries) {
        final values = entry.value;
        _draft[_scopeKey(subject.id, entry.key, WeekMode.weekly)] =
            values.weekly;
        _draft[_scopeKey(subject.id, entry.key, WeekMode.odd)] = values.odd;
        _draft[_scopeKey(subject.id, entry.key, WeekMode.even)] = values.even;
      }
    });
  }

  /// 「科目预设」列的上下文年级：最近点击的矩阵列；已被隐藏/删除时
  /// 回落到首个可见年级。
  GradeGroup? _resolveContextGrade({
    required List<GradeGroup> allGrades,
    required List<GradeGroup> visibleGrades,
  }) {
    final pinned = _presetGradeId;
    if (pinned != null) {
      final inVisible = visibleGrades.where((grade) => grade.id == pinned);
      if (inVisible.isNotEmpty) return inVisible.first;
    }
    return visibleGrades.isEmpty ? null : visibleGrades.first;
  }

  /// 矩阵「科目预设」列摘要：科目 ID → 摘要文本（null = 无预设）。
  /// 按上下文年级所在学段的预设行解析。
  Map<String, String?> _presetSummaries({
    required List<Subject> subjects,
    required List<SubjectPreset> presets,
    required List<GradeGroup> allGrades,
    required GradeGroup? contextGrade,
    required List<ClassBrief> classBriefs,
  }) {
    if (contextGrade == null) return const {};
    final gradeClassIds = classBriefs
        .where((classBrief) => classBrief.gradeId == contextGrade.id)
        .map((classBrief) => classBrief.id)
        .toSet();
    return {
      for (final subject in subjects)
        subject.id: () {
          final subjectPresets = presets
              .where((preset) => preset.subjectId == subject.id)
              .toList();
          final summary = presetSummaryText(
            effectivePresetMap(
              presets: subjectPresets,
              stageId: contextGrade.stageId,
              scope: FreeSlotScope.grade,
              scopeId: contextGrade.id,
            ),
          );
          if (summary == null) return null;
          // 各范围不同时标注：当前年级有班级级预设。
          final hasClassPresets = subjectPresets.any(
            (preset) =>
                preset.scope == FreeSlotScope.schoolClass &&
                gradeClassIds.contains(preset.scopeId) &&
                preset.value != PresetValue.auto,
          );
          return hasClassPresets ? '$summary · 各班不同' : summary;
        }(),
    };
  }

  /// 打开科目预设弹窗（US-015；范围默认矩阵当前列）。
  /// 预设网格与保存都使用年级所在学段的作息。
  Future<void> _openSubjectPreset(Subject subject, GradeGroup grade) async {
    final stage =
        (ref.read(stagesProvider(widget.termId)).valueOrNull ??
                const <SchoolStage>[])
            .where((item) => item.id == grade.stageId)
            .firstOrNull;
    final routines =
        ref.read(routinesForTermProvider(widget.termId)).valueOrNull ??
        const <String, StageRoutine>{};
    final routine = routines[grade.stageId];
    if (stage == null || routine == null) {
      _showMessage('该年级所在学段暂无作息，无法编辑科目预设');
      return;
    }
    final classBriefs =
        ref.read(classesForTermProvider(widget.termId)).valueOrNull ??
        const <ClassBrief>[];
    final classes = classBriefs
        .where((classBrief) => classBrief.gradeId == grade.id)
        .toList();
    final requirements =
        ref.read(allRequirementsProvider).valueOrNull ??
        const <SubjectRequirement>[];
    final subjectPresets =
        (ref.read(allPresetsProvider).valueOrNull ?? const <SubjectPreset>[])
            .where((preset) => preset.subjectId == subject.id)
            .toList();
    final termId = ref.read(activeTermIdProvider) ?? widget.termId;
    final classDemands = <String, ClassSubjectValues>{
      for (final classBrief in classes)
        classBrief.id: valuesForClass(
          subjectId: subject.id,
          classId: classBrief.id,
          requirements: requirements,
        ),
    };
    final result =
        await showAppDialog<({FreeSlotScope scope, String scopeId, List<PresetCell> cells})>(
          context: context,
          builder: (context) => SubjectPresetDialog(
            subject: subject,
            termId: termId,
            stage: stage,
            grade: grade,
            classes: classes,
            routine: routine,
            presets: subjectPresets,
            classDemands: classDemands,
          ),
        );
    if (result == null) return;
    try {
      final repository = ref.read(schoolRepositoryProvider);
      await repository.replaceSubjectPresets(
        subjectId: subject.id,
        termId: termId,
        scope: result.scope,
        scopeId: result.scopeId,
        stageId: grade.stageId,
        presets: [
          for (final cell in result.cells)
            SubjectPreset(
              id: '',
              subjectId: subject.id,
              scope: result.scope,
              scopeId: result.scopeId,
              stageId: grade.stageId,
              weekday: cell.weekday,
              periodTypeId: cell.periodTypeId,
              lessonIndex: cell.lessonIndex,
              value: cell.value,
            ),
        ],
      );
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      _showMessage('科目预设已保存');
    } on Object catch (error) {
      _showMessage('保存科目预设失败：$error');
    }
  }

  /// 打开配对课程弹窗（US-013 AC2）。
  Future<void> _openPairing() async {
    final classBriefs =
        ref.read(classesForTermProvider(widget.termId)).valueOrNull ??
        const <ClassBrief>[];
    if (classBriefs.isEmpty) {
      _showMessage('暂无班级，请先在「班级与学段」添加');
      return;
    }
    // 同名班级（跨学段/年级常见）会令 FSelect 的 label→value 映射去重，
    // 导致选中值不在选项里而崩溃；重名时用「学段 年级」前缀消歧。
    final nameCounts = <String, int>{};
    for (final classBrief in classBriefs) {
      nameCounts[classBrief.name] = (nameCounts[classBrief.name] ?? 0) + 1;
    }
    final gradeById = {
      for (final grade
          in ref.read(gradesForTermProvider(widget.termId)).valueOrNull ??
              const <GradeGroup>[])
        grade.id: grade,
    };
    final stageById = {
      for (final stage
          in ref.read(stagesProvider(widget.termId)).valueOrNull ??
              const <SchoolStage>[])
        stage.id: stage,
    };
    final classLabels = <String, String>{
      for (final classBrief in classBriefs)
        classBrief.id:
            (nameCounts[classBrief.name] ?? 0) > 1
                ? '${stageById[classBrief.stageId]?.name ?? ''}'
                    ' ${gradeById[classBrief.gradeId]?.name ?? ''}'
                    ' ${classBrief.name}'
                : classBrief.name,
    };
    final subjects = [
      ...ref.read(subjectsProvider).valueOrNull ?? const <Subject>[],
      ..._newSubjects,
    ];
    final stageClassIds = classBriefs.map((classBrief) => classBrief.id).toSet();
    final pairings =
        (ref.read(allPairingsProvider).valueOrNull ?? const <SubjectPairing>[])
            .where((pairing) => stageClassIds.contains(pairing.classId))
            .toList();
    await showAppDialog<void>(
      context: context,
      builder: (context) => PairingDialog(
        classes: classBriefs,
        subjects: subjects,
        pairings: pairings,
        subjectNames: {
          for (final subject in subjects) subject.id: subject.name,
        },
        classLabels: classLabels,
        onReplacePairings: (classId, pairingsForClass) async {
          try {
            final repository = ref.read(schoolRepositoryProvider);
            await repository.replaceClassPairings(
              classId: classId,
              pairings: pairingsForClass,
            );
            ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
          } on Object catch (error) {
            if (!mounted) return;
            _showMessage('保存配对失败：$error');
          }
        },
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAddSubject() async {
    final existing =
        (ref.read(subjectsProvider).valueOrNull ?? const <Subject>[])
            .map((subject) => subject.name)
            .toSet();
    final result = await showAppDialog<({String name, String shortName})>(
      context: context,
      builder: (context) => AddSubjectDialog(existingNames: existing),
    );
    if (result == null) return;
    setState(() {
      _newSubjects.add(
        Subject(
          id: 'subject_${DateTime.now().microsecondsSinceEpoch}_${_newSubjects.length}',
          name: result.name,
          shortName: result.shortName,
          sortOrder: existing.length + _newSubjects.length,
        ),
      );
    });
  }

  Future<void> _save() async {
    final allGrades =
        ref.read(gradesForTermProvider(widget.termId)).valueOrNull ??
        const <GradeGroup>[];
    final scopeGrades = _scopeStageId == null
        ? allGrades
        : allGrades
              .where((grade) => grade.stageId == _scopeStageId)
              .toList();
    // 只保存当前可见的年级列（编辑所见即所存）。
    final grades = scopeGrades
        .where(
          (grade) =>
              _visibleGradeIds.isEmpty || _visibleGradeIds.contains(grade.id),
        )
        .toList();
    final allClasses =
        ref.read(classesForTermProvider(widget.termId)).valueOrNull ??
        const <ClassBrief>[];
    final visibleGradeIds = grades.map((grade) => grade.id).toSet();
    final classBriefs = allClasses
        .where((classBrief) => visibleGradeIds.contains(classBrief.gradeId))
        .toList();
    final subjects = [
      ...ref.read(subjectsProvider).valueOrNull ?? const <Subject>[],
      ..._newSubjects,
    ];
    final requirements =
        ref.read(allRequirementsProvider).valueOrNull ??
        const <SubjectRequirement>[];
    final routines =
        ref.read(routinesForTermProvider(widget.termId)).valueOrNull ??
        const <String, StageRoutine>{};
    final freeSlots =
        ref.read(freeSlotsForTermProvider(widget.termId)).valueOrNull ??
        const <FreeSlot>[];
    final termId = ref.read(activeTermIdProvider) ?? widget.termId;
    final effective = _effectiveRequirements(
      subjects: subjects,
      classBriefs: classBriefs,
      baseRequirements: requirements,
    );

    // 保存前容量预警（US-012 AC3），按各年级所在学段的作息计算。
    final over = <String>[];
    for (final grade in grades) {
      final routine = routines[grade.stageId];
      if (routine == null) continue;
      final summary = summarizeGradeCapacity(
        grade: grade,
        classes: classBriefs
            .where((classBrief) => classBrief.gradeId == grade.id)
            .toList(),
        requirements: effective,
        routine: routine,
        freeSlots: freeSlots,
        termId: termId,
      );
      if (summary.isOver) {
        over.add('${grade.name} ${summary.overClassName}超 ${summary.excess} 节');
      }
    }
    if (over.isNotEmpty) {
      final proceed = await showAppDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          title: const Text('容量超限预警'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '以下班级的需求节数超出可排容量，自动排课可能无法全部排入：',
                  style: TextStyle(fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 8),
                for (final item in over)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '· $item',
                      style: const TextStyle(
                        color: AppTheme.destructive,
                        fontSize: 12,
                      ),
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
            AppPrimaryButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续保存'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      final repository = ref.read(schoolRepositoryProvider);
      if (_newSubjects.isNotEmpty) {
        await repository.saveSubjects(_newSubjects);
      }
      for (final grade in grades) {
        final rows = effective
            .where((requirement) => requirement.gradeId == grade.id)
            .toList();
        await repository.replaceGradeRequirements(
          gradeId: grade.id,
          requirements: rows,
        );
      }
      ref.read(lastPersistedAtProvider.notifier).state = DateTime.now();
      if (!mounted) return;
      setState(() {
        _draft.clear();
        _newSubjects.clear();
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('科目节数已保存')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    }
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('该功能将在后续版本提供')),
    );
  }
}

class _NoStages extends StatelessWidget {
  const _NoStages({required this.onGoToClasses});

  final VoidCallback onGoToClasses;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.account_tree_outlined, size: 42, color: AppTheme.muted),
        const SizedBox(height: 12),
        const Text(
          '请先添加学段',
          style: TextStyle(
            color: AppTheme.ink,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '科目节数按年级录入，需要先在「班级与学段」搭好学段与年级。',
          style: TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        AppPrimaryButton(
          onPressed: onGoToClasses,
          child: const Text('前往班级与学段'),
        ),
      ],
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: SelectableText(
        message,
        style: const TextStyle(color: AppTheme.destructive, fontSize: 13),
      ),
    ),
  );
}
