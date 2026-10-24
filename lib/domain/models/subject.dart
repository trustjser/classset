import 'package:class_set/domain/models/free_slot.dart';

/// 科目属于一个学期，同一学期内各学段共享。
class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.shortName,
    required this.sortOrder,
    this.termId,
  });

  final String id;
  final String? termId;

  /// 全称，如「心理健康」。
  final String name;

  /// 简称，课表与导出使用，如「心」。
  final String shortName;

  final int sortOrder;

  Subject copyWith({String? name, String? shortName, int? sortOrder}) =>
      Subject(
        id: id,
        termId: termId,
        name: name ?? this.name,
        shortName: shortName ?? this.shortName,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// 周模式：每周（默认）/ 单周 / 双周。
/// 录入数字表示该课在「一个实际出现周」要上的节数（US-013 AC1）。
enum WeekMode {
  weekly,
  odd,
  even;

  String get storageValue => switch (this) {
    WeekMode.weekly => 'weekly',
    WeekMode.odd => 'odd',
    WeekMode.even => 'even',
  };

  static WeekMode fromStorage(String? value) => switch (value) {
    'odd' => WeekMode.odd,
    'even' => WeekMode.even,
    _ => WeekMode.weekly,
  };

  String get label => switch (this) {
    WeekMode.weekly => '每周',
    WeekMode.odd => '单周',
    WeekMode.even => '双周',
  };
}

/// 科目节数需求：某科目在某年级（或某班级）在某周模式下的每周节数。
///
/// [classId] 为 null 表示年级默认值；非 null 表示按班覆盖（更具体范围优先）。
class SubjectRequirement {
  const SubjectRequirement({
    required this.id,
    required this.subjectId,
    required this.gradeId,
    required this.weekMode,
    required this.lessonCount,
    this.classId,
  });

  final String id;
  final String subjectId;
  final String gradeId;
  final WeekMode weekMode;
  final int lessonCount;

  /// 非 null = 按班覆盖；null = 年级默认。
  final String? classId;

  bool get isClassOverride => classId != null;

  /// 需求合计键：同学科同范围同周模式唯一。
  String get scopeKey =>
      '${subjectId}_${classId ?? gradeId}_${weekMode.storageValue}';

  SubjectRequirement copyWith({
    String? id,
    int? lessonCount,
    String? classId,
    bool clearClassId = false,
  }) => SubjectRequirement(
    id: id ?? this.id,
    subjectId: subjectId,
    gradeId: gradeId,
    weekMode: weekMode,
    lessonCount: lessonCount ?? this.lessonCount,
    classId: clearClassId ? null : classId ?? this.classId,
  );
}

/// 科目预设的四档状态（US-015 AC1）。
enum PresetValue {
  /// 无偏好（空态）。
  auto,

  /// 软性优先。
  prefer,

  /// 硬性必须。
  must,

  /// 硬性禁止。
  forbid;

  String get storageValue => switch (this) {
    PresetValue.auto => 'auto',
    PresetValue.prefer => 'prefer',
    PresetValue.must => 'must',
    PresetValue.forbid => 'forbid',
  };

  static PresetValue fromStorage(String? value) => switch (value) {
    'prefer' => PresetValue.prefer,
    'must' => PresetValue.must,
    'forbid' => PresetValue.forbid,
    _ => PresetValue.auto,
  };

  String get label => switch (this) {
    PresetValue.auto => '自动',
    PresetValue.prefer => '尽量排',
    PresetValue.must => '一定排',
    PresetValue.forbid => '不排',
  };

  /// 单击循环顺序：自动 → 尽量排 → 一定排 → 不排 → 自动（US-015 AC2）。
  PresetValue get next => switch (this) {
    PresetValue.auto => PresetValue.prefer,
    PresetValue.prefer => PresetValue.must,
    PresetValue.must => PresetValue.forbid,
    PresetValue.forbid => PresetValue.auto,
  };
}

/// 科目预设：某科目在某范围的「星期 × 时段 × 节次」位置偏好。
///
/// 预设不区分单双周（D14 / US-015 AC7）；[scope] 为四级范围
/// （全校 scopeId=学期 ID / 学段 / 年级 / 班级），各范围各存一份，
/// 渲染时更具体的范围优先；「全校」份按学段展开存储（[stageId] +
/// 时段名称匹配），只对未单独设置的范围生效（US-015 AC8）。
class SubjectPreset {
  const SubjectPreset({
    required this.id,
    required this.subjectId,
    required this.scope,
    required this.scopeId,
    required this.stageId,
    required this.weekday,
    required this.periodTypeId,
    required this.lessonIndex,
    required this.value,
  });

  final String id;
  final String subjectId;
  final FreeSlotScope scope;
  final String scopeId;

  /// 所属学段（全校范围行按学段展开存储）。
  final String stageId;
  final int weekday;

  /// 1=星期一 … 7=星期日。
  final String periodTypeId;

  /// 时段内的节次序号（从 1 开始）。
  final int lessonIndex;
  final PresetValue value;

  /// 同一范围同一格唯一。
  String get cellKey =>
      '${scope.storageValue}_${scopeId}_${stageId}_${weekday}_${periodTypeId}_$lessonIndex';
}

/// 课程配对：同班两门课（一单一双）绑定到同一时段（US-013 AC2）。
///
/// 只约束「两门课必须占同一时段」，不改变各自节数与周模式。
class SubjectPairing {
  const SubjectPairing({
    required this.id,
    required this.classId,
    required this.oddSubjectId,
    required this.evenSubjectId,
  });

  final String id;
  final String classId;

  /// 单周科目。
  final String oddSubjectId;

  /// 双周科目。
  final String evenSubjectId;
}
