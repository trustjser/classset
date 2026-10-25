/// 自定义排课条件的五种硬约束类型。
enum ScheduleConditionType {
  periodLimit,
  dailyLimit,
  teacherMutualExclusion,
  subjectMutualExclusion,
  forbiddenAdjacency,
}

/// 数量限制作用于科目或教师。
enum ScheduleConditionTarget { subject, teacher }

/// 不区分单双周配置、按实际出现周次检查的自定义条件。
///
/// 科目数量条件逐班计算。互斥条件使用 [targetId] 与 [otherTargetId]。
/// 禁止相邻条件禁止 [targetId] 所指科目紧排在另一科之前。
class ScheduleCondition {
  const ScheduleCondition({
    required this.id,
    required this.termId,
    required this.type,
    this.targetType,
    this.targetId,
    this.otherTargetId,
    this.periodTypeId,
    this.weekday,
    this.minimum,
    this.maximum,
    this.exact,
    this.name,
  });

  final String id;
  final String termId;
  final ScheduleConditionType type;
  final ScheduleConditionTarget? targetType;
  final String? targetId;
  final String? otherTargetId;
  final String? periodTypeId;

  /// `null` 表示每天。
  final int? weekday;
  final int? minimum;
  final int? maximum;
  final int? exact;
  final String? name;

  /// Rejects incomplete or contradictory persisted hard conditions.
  void validate() {
    if (id.isEmpty ||
        termId.isEmpty ||
        (weekday != null && (weekday! < 1 || weekday! > 7)) ||
        [minimum, maximum, exact].whereType<int>().any((value) => value < 0) ||
        (minimum != null && maximum != null && minimum! > maximum!)) {
      throw ArgumentError('排课条件的标识、星期或节数范围无效');
    }
    final target = targetId;
    if (target == null || target.isEmpty) {
      throw ArgumentError('排课条件缺少目标');
    }
    switch (type) {
      case ScheduleConditionType.periodLimit:
      case ScheduleConditionType.dailyLimit:
        if (targetType == null ||
            (type == ScheduleConditionType.periodLimit &&
                (periodTypeId == null || periodTypeId!.isEmpty)) ||
            (minimum == null && maximum == null && exact == null)) {
          throw ArgumentError('节数限制缺少对象、时段或数值');
        }
      case ScheduleConditionType.teacherMutualExclusion:
      case ScheduleConditionType.subjectMutualExclusion:
      case ScheduleConditionType.forbiddenAdjacency:
        if (otherTargetId == null ||
            otherTargetId!.isEmpty ||
            otherTargetId == target ||
            (targetType != null &&
                targetType !=
                    (type == ScheduleConditionType.teacherMutualExclusion
                        ? ScheduleConditionTarget.teacher
                        : ScheduleConditionTarget.subject))) {
          throw ArgumentError('互斥或相邻条件的两个目标无效');
        }
    }
  }
}
