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

/// 免任课标记在某范围视图下的生效方式。
enum FreeSlotViewEffect {
  /// 与当前视图无关。
  none,

  /// 对当前范围整体生效（预排格应锁定并展示标记）。
  full,

  /// 仅对当前范围内部分班级生效（仅展示标记，不锁定）。
  partial,
}

/// 「范围视图 × 单元格」的免任课解析结果。
class FreeSlotViewResolution {
  const FreeSlotViewResolution({this.full, this.partial});

  /// 对当前范围整体生效的最具体标记（null = 无）。
  final FreeSlot? full;

  /// 仅作用于范围内部分班级的最具体标记（null = 无）。
  final FreeSlot? partial;
}

/// 解析某一格上的免任课标记对当前编辑范围的生效方式。
///
/// - [viewScope] / [viewScopeId]：当前编辑范围（与 FreeSlotScope 对应）。
/// - [termId]：全校范围行的 scopeId。
/// - [classGradeId]：仅班级视图需要，该班级所属年级。
/// - [applicableGradeIds] / [applicableClassIds]：当前范围内包含的
///   年级 / 班级，用于判断更细范围的标记是否「部分生效」。
FreeSlotViewResolution resolveFreeSlotsForView(
  List<FreeSlot> slots, {
  required FreeSlotScope viewScope,
  required String viewScopeId,
  required String termId,
  required String stageId,
  required int weekday,
  required String periodTypeId,
  required int lessonIndex,
  String? classGradeId,
  Set<String> applicableGradeIds = const {},
  Set<String> applicableClassIds = const {},
}) {
  FreeSlot? full;
  var fullRank = -1;
  FreeSlot? partial;
  var partialRank = -1;
  for (final slot in slots) {
    if (slot.stageId != stageId ||
        slot.weekday != weekday ||
        slot.periodTypeId != periodTypeId ||
        slot.lessonIndex != lessonIndex) {
      continue;
    }
    final appliesToView = switch (slot.scope) {
      FreeSlotScope.school => slot.scopeId == termId,
      FreeSlotScope.stage => slot.scopeId == stageId,
      FreeSlotScope.grade => switch (viewScope) {
        FreeSlotScope.grade => slot.scopeId == viewScopeId,
        FreeSlotScope.schoolClass => slot.scopeId == classGradeId,
        FreeSlotScope.school || FreeSlotScope.stage => false,
      },
      FreeSlotScope.schoolClass =>
        viewScope == FreeSlotScope.schoolClass && slot.scopeId == viewScopeId,
    };
    if (appliesToView) {
      // 越具体的范围优先展示。
      final rank = switch (slot.scope) {
        FreeSlotScope.schoolClass => 4,
        FreeSlotScope.grade => 3,
        FreeSlotScope.stage => 2,
        FreeSlotScope.school => 1,
      };
      if (rank > fullRank) {
        full = slot;
        fullRank = rank;
      }
      continue;
    }
    final partialHit = switch (slot.scope) {
      FreeSlotScope.grade => applicableGradeIds.contains(slot.scopeId),
      FreeSlotScope.schoolClass => applicableClassIds.contains(slot.scopeId),
      // 全校 / 学段级标记要么整体生效，要么与视图无关，不存在部分生效。
      FreeSlotScope.school || FreeSlotScope.stage => false,
    };
    if (partialHit) {
      final rank = slot.scope == FreeSlotScope.schoolClass ? 2 : 1;
      if (rank > partialRank) {
        partial = slot;
        partialRank = rank;
      }
    }
  }
  return FreeSlotViewResolution(full: full, partial: partial);
}
