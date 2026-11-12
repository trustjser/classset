/// 课节在某学段作息中的一个具体位置。
///
/// 起止分钟由作息快照填入；同学段可按格子比较，跨学段资源必须按时钟比较。
class SchedulePosition {
  const SchedulePosition({
    required this.stageId,
    required this.weekday,
    required this.periodTypeId,
    required this.lessonIndex,
    this.startMinute,
    this.endMinute,
  });

  final String stageId;
  final int weekday;
  final String periodTypeId;
  final int lessonIndex;
  final int? startMinute;
  final int? endMinute;

  String get cellKey => '$stageId:$weekday:$periodTypeId:$lessonIndex';

  bool get hasClockTime =>
      startMinute != null && endMinute != null && startMinute! < endMinute!;

  bool sameCell(SchedulePosition other) => cellKey == other.cellKey;

  bool overlaps(SchedulePosition other) {
    if (weekday != other.weekday) return false;
    if (stageId == other.stageId) {
      if (hasClockTime && other.hasClockTime) {
        return startMinute! < other.endMinute! &&
            other.startMinute! < endMinute!;
      }
      return sameCell(other);
    }
    return hasClockTime &&
        other.hasClockTime &&
        startMinute! < other.endMinute! &&
        other.startMinute! < endMinute!;
  }

  bool hasSameClock(SchedulePosition other) =>
      weekday == other.weekday &&
      hasClockTime &&
      other.hasClockTime &&
      startMinute == other.startMinute &&
      endMinute == other.endMinute;

  /// Refuse a cross-stage placement when there is no clock to prove that
  /// the teacher can attend both a lesson and a supervision.
  bool conflictsWithSupervision(SchedulePosition other) =>
      weekday == other.weekday &&
      (sameCell(other) ||
          overlaps(other) ||
          (stageId != other.stageId && (!hasClockTime || !other.hasClockTime)));

  Map<String, Object?> toJson() => {
    'stageId': stageId,
    'weekday': weekday,
    'periodTypeId': periodTypeId,
    'lessonIndex': lessonIndex,
    'startMinute': startMinute,
    'endMinute': endMinute,
  };

  factory SchedulePosition.fromJson(Map<String, Object?> json) =>
      SchedulePosition(
        stageId: json['stageId'] as String,
        weekday: (json['weekday'] as num).toInt(),
        periodTypeId: json['periodTypeId'] as String,
        lessonIndex: (json['lessonIndex'] as num).toInt(),
        startMinute: (json['startMinute'] as num?)?.toInt(),
        endMinute: (json['endMinute'] as num?)?.toInt(),
      );
}
