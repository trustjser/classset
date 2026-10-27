/// 免任课格子：某范围（全校 / 学段 / 年级 / 班级）在具体
/// 「星期 × 时段 × 节次」上标记为不排课，并可指定打印文字。
///
/// 行数据按学段展开存储（[stageId] + [periodTypeId] 均落到具体学段），
/// 以便按学段查询与随时段类型级联清理；「全校」范围的标记在写入时
/// 展开到该学期所有学段（按时段名称匹配）。
class FreeSlot {
  const FreeSlot({
    required this.id,
    required this.scope,
    required this.scopeId,
    required this.stageId,
    required this.periodTypeId,
    required this.weekday,
    required this.lessonIndex,
    required this.label,
  });

  final String id;
  final FreeSlotScope scope;

  /// 范围实体 ID：全校=学期 ID，学段=学段 ID，年级=年级 ID，班级=班级 ID。
  final String scopeId;

  /// 所属学段（冗余存储，便于按学段查询与级联）。
  final String stageId;
  final String periodTypeId;

  /// 1=星期一 … 7=星期日。
  final int weekday;

  /// 时段内的节次序号（从 1 开始）。
  final int lessonIndex;

  /// 打印文字：无课 / 自习 / 劳动 / 教研活动 / 党团活动 / 自定义名称。
  final String label;
}

enum FreeSlotScope {
  school,
  stage,
  grade,
  schoolClass;

  String get storageValue => switch (this) {
    FreeSlotScope.school => 'school',
    FreeSlotScope.stage => 'stage',
    FreeSlotScope.grade => 'grade',
    FreeSlotScope.schoolClass => 'class',
  };

  static FreeSlotScope fromStorage(String value) => switch (value) {
    'stage' => FreeSlotScope.stage,
    'grade' => FreeSlotScope.grade,
    'class' => FreeSlotScope.schoolClass,
    _ => FreeSlotScope.school,
  };
}

/// 预置免任课类型；[FreeSlot.label] 可为自定义文字。
abstract final class FreeSlotLabels {
  static const String noClass = '不上课';
  static const String none = '无课';
  static const String selfStudy = '自习';
  static const String labor = '劳动';
  static const String teachingResearch = '教研活动';
  static const String partyLeague = '党团活动';

  static const List<String> presets = [
    noClass,
    none,
    selfStudy,
    labor,
    teachingResearch,
    partyLeague,
  ];
}
