import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';

/// 某班级某科目的三档周模式节数（草稿值 / 生效值）。
class ClassSubjectValues {
  const ClassSubjectValues({this.weekly = 0, this.odd = 0, this.even = 0});

  final int weekly;
  final int odd;
  final int even;

  int get oddWeekDemand => weekly + odd;
  int get evenWeekDemand => weekly + even;

  bool get isAllZero => weekly == 0 && odd == 0 && even == 0;

  ClassSubjectValues copyWith({int? weekly, int? odd, int? even}) =>
      ClassSubjectValues(
        weekly: weekly ?? this.weekly,
        odd: odd ?? this.odd,
        even: even ?? this.even,
      );

  @override
  bool operator ==(Object other) =>
      other is ClassSubjectValues &&
      other.weekly == weekly &&
      other.odd == odd &&
      other.even == even;

  @override
  int get hashCode => Object.hash(weekly, odd, even);
}

/// 矩阵单元格状态：统一数值 / 各班不同。
class SubjectCellState {
  const SubjectCellState.uniform(this.value) : varies = false;
  const SubjectCellState.varies() : value = 0, varies = true;

  final int value;
  final bool varies;
}

/// 解析单组节数：'3' → 每周 3；'3|1|1' → 每周/单周/双周。非法返回 null。
ClassSubjectValues? parseLessonGroup(String group) {
  final parts = group.trim().split('|');
  int? parse(String raw) {
    final value = int.tryParse(raw.trim());
    return value == null || value < 0 ? null : value;
  }

  if (parts.length == 1) {
    final weekly = parse(parts[0]);
    if (weekly == null) return null;
    return ClassSubjectValues(weekly: weekly, odd: 0, even: 0);
  }
  if (parts.length == 3) {
    final weekly = parse(parts[0]);
    final odd = parse(parts[1]);
    final even = parse(parts[2]);
    if (weekly == null || odd == null || even == null) return null;
    return ClassSubjectValues(weekly: weekly, odd: odd, even: even);
  }
  return null;
}

/// 解析整格输入：半角逗号分隔多组（按班级顺序）。
/// 空串 → 空表（整格清零）；含非法组 → null。
List<ClassSubjectValues>? parseLessonInput(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const [];
  final result = <ClassSubjectValues>[];
  for (final group in trimmed.split(',')) {
    final parsed = parseLessonGroup(group);
    if (parsed == null) return null;
    result.add(parsed);
  }
  return result;
}

/// 单组格式化：无单双周 → 'w'；否则 'w|o|e'。
String formatLessonValues(ClassSubjectValues values) =>
    values.odd == 0 && values.even == 0
    ? '${values.weekly}'
    : '${values.weekly}|${values.odd}|${values.even}';

/// 整格格式化：各班一致 → 单组；否则按班级顺序逗号分隔。
String formatLessonInput(Iterable<ClassSubjectValues> values) {
  final list = values.toList();
  if (list.isEmpty) return '';
  final first = list.first;
  if (list.skip(1).every((value) => value == first)) {
    return formatLessonValues(first);
  }
  return list.map(formatLessonValues).join(',');
}

/// 从需求行集合解析某班级某科目的三档节数。
ClassSubjectValues valuesForClass({
  required String subjectId,
  required String classId,
  required List<SubjectRequirement> requirements,
}) {
  var weekly = 0;
  var odd = 0;
  var even = 0;
  for (final requirement in requirements) {
    if (requirement.subjectId != subjectId || requirement.classId != classId) {
      continue;
    }
    switch (requirement.weekMode) {
      case WeekMode.weekly:
        weekly = requirement.lessonCount;
      case WeekMode.odd:
        odd = requirement.lessonCount;
      case WeekMode.even:
        even = requirement.lessonCount;
    }
  }
  return ClassSubjectValues(weekly: weekly, odd: odd, even: even);
}

/// 某年级某科目的矩阵单元格状态：各班一致显示数值，否则「各班不同」。
SubjectCellState cellStateForGrade({
  required String subjectId,
  required List<ClassBrief> classes,
  required List<SubjectRequirement> requirements,
}) {
  if (classes.isEmpty) return const SubjectCellState.uniform(0);
  final first = valuesForClass(
    subjectId: subjectId,
    classId: classes.first.id,
    requirements: requirements,
  );
  for (final classBrief in classes.skip(1)) {
    final values = valuesForClass(
      subjectId: subjectId,
      classId: classBrief.id,
      requirements: requirements,
    );
    if (values != first) return const SubjectCellState.varies();
  }
  return SubjectCellState.uniform(first.weekly);
}

/// 班级可排容量：单周 / 双周可用格数。
///
/// 结构按周相同，故单双周容量相等；免任课格按范围链
/// （班级 > 年级 > 学段 > 全校）取最具体值后扣除（US-003 AC5）。
class ClassCapacity {
  const ClassCapacity({required this.oddWeek, required this.evenWeek});

  final int oddWeek;
  final int evenWeek;
}

ClassCapacity capacityForClass({
  required StageRoutine routine,
  required List<FreeSlot> freeSlots,
  required String termId,
  required GradeGroup grade,
  required ClassBrief classBrief,
}) {
  var slots = 0;
  for (final weekday in routine.teachingWeekdays) {
    for (final period in routine.periodTypes) {
      slots += routine.effectiveLessonCount(period.id, weekday);
    }
  }
  final free = _freeCellCount(
    freeSlots: freeSlots,
    termId: termId,
    grade: grade,
    classBrief: classBrief,
  );
  final available = (slots - free).clamp(0, slots);
  return ClassCapacity(oddWeek: available, evenWeek: available);
}

/// 免任课格按范围链解析：返回适用于该班级的去重格数。
int _freeCellCount({
  required List<FreeSlot> freeSlots,
  required String termId,
  required GradeGroup grade,
  required ClassBrief classBrief,
}) {
  final winners = <String, int>{};
  for (final slot in freeSlots) {
    // 免任课行按学段展开存储：其他学段的行不作用于本学段班级。
    if (slot.stageId != classBrief.stageId) continue;
    final specificity = switch (slot.scope) {
      FreeSlotScope.schoolClass => slot.scopeId == classBrief.id ? 4 : null,
      FreeSlotScope.grade => slot.scopeId == grade.id ? 3 : null,
      FreeSlotScope.stage => slot.scopeId == classBrief.stageId ? 2 : null,
      FreeSlotScope.school => slot.scopeId == termId ? 1 : null,
    };
    if (specificity == null) continue;
    final key = '${slot.periodTypeId}_${slot.weekday}_${slot.lessonIndex}';
    final existing = winners[key];
    if (existing == null || specificity > existing) winners[key] = specificity;
  }
  return winners.length;
}

/// 某班级在一个周模式下超出课位容量的详情。
class GradeCapacityIssue {
  const GradeCapacityIssue({
    required this.className,
    required this.weekMode,
    required this.demand,
    required this.capacity,
  });

  final String className;
  final WeekMode weekMode;
  final int demand;
  final int capacity;

  int get excess => demand - capacity;
}

/// 年级容量概要：状态逐班校验，页脚展示最紧张班级的完整节数组合。
class GradeCapacitySummary {
  const GradeCapacitySummary({
    required this.gradeId,
    required this.weeklyDemand,
    required this.oddOnlyDemand,
    required this.evenOnlyDemand,
    required this.availableSlots,
    required this.displayClassName,
    required this.issues,
  });

  final String gradeId;

  /// 矩阵页脚使用同一班级的节数组合，避免把不同班的最大值拼在一起。
  final int weeklyDemand;
  final int oddOnlyDemand;
  final int evenOnlyDemand;
  final int availableSlots;
  final String? displayClassName;

  /// 逐班、逐周的全部超量信息，供状态悬停提示使用。
  final List<GradeCapacityIssue> issues;

  bool get isOver => issues.isNotEmpty;

  GradeCapacityIssue? get _worstIssue {
    if (issues.isEmpty) return null;
    var worst = issues.first;
    for (final issue in issues.skip(1)) {
      if (issue.excess > worst.excess) worst = issue;
    }
    return worst;
  }

  /// 超容量班级名与最多超出的节数，供保存预警使用。
  String? get overClassName => _worstIssue?.className;
  int get excess => _worstIssue?.excess ?? 0;
}

/// 汇总某年级容量：逐班计算需求与容量，返回最紧张班级的概要。
GradeCapacitySummary summarizeGradeCapacity({
  required GradeGroup grade,
  required List<ClassBrief> classes,
  required List<SubjectRequirement> requirements,
  required StageRoutine routine,
  required List<FreeSlot> freeSlots,
  required String termId,
}) {
  if (classes.isEmpty) {
    return GradeCapacitySummary(
      gradeId: grade.id,
      weeklyDemand: 0,
      oddOnlyDemand: 0,
      evenOnlyDemand: 0,
      availableSlots: 0,
      displayClassName: null,
      issues: const [],
    );
  }
  var displayPressure = -(1 << 30);
  var displayPeakDemand = -1;
  var displayWeeklyDemand = 0;
  var displayOddOnlyDemand = 0;
  var displayEvenOnlyDemand = 0;
  var displayAvailableSlots = 0;
  String? displayClassName;
  final issues = <GradeCapacityIssue>[];
  for (final classBrief in classes) {
    final capacity = capacityForClass(
      routine: routine,
      freeSlots: freeSlots,
      termId: termId,
      grade: grade,
      classBrief: classBrief,
    );
    var weeklyDemand = 0;
    var oddOnlyDemand = 0;
    var evenOnlyDemand = 0;
    for (final requirement in requirements) {
      if (requirement.classId != classBrief.id) continue;
      if (requirement.weekMode == WeekMode.weekly) {
        weeklyDemand += requirement.lessonCount;
      } else if (requirement.weekMode == WeekMode.odd) {
        oddOnlyDemand += requirement.lessonCount;
      } else {
        evenOnlyDemand += requirement.lessonCount;
      }
    }
    final oddDemand = weeklyDemand + oddOnlyDemand;
    final evenDemand = weeklyDemand + evenOnlyDemand;
    if (oddDemand > capacity.oddWeek) {
      issues.add(
        GradeCapacityIssue(
          className: classBrief.name,
          weekMode: WeekMode.odd,
          demand: oddDemand,
          capacity: capacity.oddWeek,
        ),
      );
    }
    if (evenDemand > capacity.evenWeek) {
      issues.add(
        GradeCapacityIssue(
          className: classBrief.name,
          weekMode: WeekMode.even,
          demand: evenDemand,
          capacity: capacity.evenWeek,
        ),
      );
    }
    final peakDemand = oddDemand >= evenDemand ? oddDemand : evenDemand;
    final pressure = peakDemand - capacity.oddWeek;
    if (pressure > displayPressure ||
        (pressure == displayPressure && peakDemand > displayPeakDemand)) {
      displayPressure = pressure;
      displayPeakDemand = peakDemand;
      displayWeeklyDemand = weeklyDemand;
      displayOddOnlyDemand = oddOnlyDemand;
      displayEvenOnlyDemand = evenOnlyDemand;
      displayAvailableSlots = capacity.oddWeek;
      displayClassName = classBrief.name;
    }
  }
  return GradeCapacitySummary(
    gradeId: grade.id,
    weeklyDemand: displayWeeklyDemand,
    oddOnlyDemand: displayOddOnlyDemand,
    evenOnlyDemand: displayEvenOnlyDemand,
    availableSlots: displayAvailableSlots,
    displayClassName: displayClassName,
    issues: List.unmodifiable(issues),
  );
}

// —— 科目预设（US-015） ——

/// 预设格：星期 × 时段 × 节次 上的一档状态。
class PresetCell {
  const PresetCell({
    required this.weekday,
    required this.periodTypeId,
    required this.lessonIndex,
    required this.value,
  });

  final int weekday;
  final String periodTypeId;
  final int lessonIndex;
  final PresetValue value;
}

/// 预设格键：星期 × 时段 × 节次。
String presetCellKey(int weekday, String periodTypeId, int lessonIndex) =>
    '${weekday}_${periodTypeId}_$lessonIndex';

/// 解析某科目在某范围语境下的生效预设（更具体范围优先）。
///
/// 显式的 [PresetValue.auto] 会覆盖较宽范围的值，用于清除继承预设；
/// 未出现在结果中的格子才表示该范围没有设置。
///
/// [scopeId] 语义随 [scope]：全校 = 学期 ID，学段 = 学段 ID，
/// 年级 = 年级 ID，班级 = 班级 ID；班级范围只解析该班级的行。
Map<String, PresetValue> effectivePresetMap({
  required List<SubjectPreset> presets,
  required String stageId,
  required FreeSlotScope scope,
  required String scopeId,
  String? parentGradeId,
}) {
  final result = <String, PresetValue>{};
  // 优先级低的先写入，优先级高的后写入覆盖（班级 4 > 年级 3 > 学段 2 > 全校 1）。
  final ordered = presets.toList()
    ..sort(
      (a, b) => _scopePriority(a.scope).compareTo(_scopePriority(b.scope)),
    );
  for (final preset in ordered) {
    if (preset.stageId != stageId) continue;
    if (!_scopeMatches(
      preset,
      scope: scope,
      scopeId: scopeId,
      parentGradeId: parentGradeId,
    )) {
      continue;
    }
    final key = presetCellKey(
      preset.weekday,
      preset.periodTypeId,
      preset.lessonIndex,
    );
    result[key] = preset.value;
  }
  return result;
}

int _scopePriority(FreeSlotScope scope) => switch (scope) {
  FreeSlotScope.school => 1,
  FreeSlotScope.stage => 2,
  FreeSlotScope.grade => 3,
  FreeSlotScope.schoolClass => 4,
};

/// 行是否作用于当前范围语境：同级精确匹配，或更宽范围对该范围生效。
bool _scopeMatches(
  SubjectPreset preset, {
  required FreeSlotScope scope,
  required String scopeId,
  required String? parentGradeId,
}) {
  if (preset.scope == scope) return preset.scopeId == scopeId;
  if (scope == FreeSlotScope.schoolClass &&
      preset.scope == FreeSlotScope.grade) {
    return preset.scopeId == parentGradeId;
  }
  // 更宽范围对更具体范围生效；更具体范围不影响更宽范围。
  return _scopePriority(preset.scope) < _scopePriority(scope);
}

/// 矩阵「科目预设」列的显示文本与完整提示。
typedef SubjectPresetSummary = ({String text, String tooltip});

/// 矩阵「科目预设」列摘要：如「5 固定 · 3 不排」；无预设返回 null。
String? presetSummaryText(Map<String, PresetValue> effective) {
  if (effective.isEmpty) return null;
  final must = effective.values.where((v) => v == PresetValue.must).length;
  final forbid = effective.values.where((v) => v == PresetValue.forbid).length;
  final prefer = effective.values.where((v) => v == PresetValue.prefer).length;
  final parts = <String>[
    if (must > 0) '$must 固定',
    if (forbid > 0) '$forbid 不排',
    if (prefer > 0) '$prefer 尽量',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// 某科目在某范围已存在预设行（用于「各范围不同时标注」）。
bool hasPresetsForSubject(List<SubjectPreset> presets) =>
    presets.any((preset) => preset.value != PresetValue.auto);
