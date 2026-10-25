/// 候选检查预算所用的排课强度。
enum ScheduleStrength { fast, normal, high }

/// 同级同科教学进度规则。
enum ProgressConsistency { prefer, require }

/// 教师当天课程分布偏好。
enum TeacherDistribution { indifferent, spread, concentrate }

/// 非强制连堂课的全局规则。
enum ConsecutiveMode { preferSeparate, requireSeparate, preferTogether }

/// 全局排课规则与偏好。
class SchedulePreferences {
  const SchedulePreferences({
    this.strength = ScheduleStrength.normal,
    this.progressConsistency = ProgressConsistency.prefer,
    this.teacherDistribution = TeacherDistribution.indifferent,
    this.protectLunchBreak = false,
    this.consecutiveMode = ConsecutiveMode.preferSeparate,
    this.checkProgressConsistency = true,
  });

  final ScheduleStrength strength;
  final ProgressConsistency progressConsistency;
  final TeacherDistribution teacherDistribution;
  final bool protectLunchBreak;
  final ConsecutiveMode consecutiveMode;
  final bool checkProgressConsistency;

  Map<String, Object?> toJson() => {
    'strength': strength.name,
    'progressConsistency': progressConsistency.name,
    'teacherDistribution': teacherDistribution.name,
    'protectLunchBreak': protectLunchBreak,
    'consecutiveMode': consecutiveMode.name,
    'checkProgressConsistency': checkProgressConsistency,
  };

  factory SchedulePreferences.fromJson(Map<String, Object?> json) =>
      SchedulePreferences(
        strength: ScheduleStrength.values.firstWhere(
          (value) => value.name == json['strength'],
          orElse: () => ScheduleStrength.normal,
        ),
        progressConsistency: ProgressConsistency.values.firstWhere(
          (value) => value.name == json['progressConsistency'],
          orElse: () => ProgressConsistency.prefer,
        ),
        teacherDistribution: TeacherDistribution.values.firstWhere(
          (value) => value.name == json['teacherDistribution'],
          orElse: () => TeacherDistribution.indifferent,
        ),
        protectLunchBreak: json['protectLunchBreak'] == true,
        consecutiveMode: ConsecutiveMode.values.firstWhere(
          (value) => value.name == json['consecutiveMode'],
          orElse: () => ConsecutiveMode.preferSeparate,
        ),
        checkProgressConsistency: json['checkProgressConsistency'] != false,
      );
}
