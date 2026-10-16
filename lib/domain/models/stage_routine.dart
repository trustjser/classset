class StageRoutine {
  const StageRoutine({
    required this.stageId,
    required this.teachingWeekdays,
    required this.periodTypes,
    required this.overrides,
  });

  final String stageId;
  final Set<int> teachingWeekdays;
  final List<LessonPeriodType> periodTypes;
  final List<RoutineOverride> overrides;

  int effectiveLessonCount(String periodTypeId, int weekday) =>
      _effectiveOverride(periodTypeId, weekday) ??
      periodTypes
          .firstWhere((period) => period.id == periodTypeId)
          .defaultLessonCount;

  int? _effectiveOverride(String periodTypeId, int weekday) {
    for (final override in overrides) {
      if (override.periodTypeId == periodTypeId &&
          override.weekday == weekday) {
        return override.lessonCount;
      }
    }
    return null;
  }
}

class LessonPeriodType {
  const LessonPeriodType({
    required this.id,
    required this.name,
    required this.defaultLessonCount,
    required this.sortOrder,
    required this.lessonTimes,
  });

  final String id;
  final String name;
  final int defaultLessonCount;
  final int sortOrder;
  final List<LessonTime> lessonTimes;
}

class LessonTime {
  const LessonTime({
    required this.lessonIndex,
    required this.label,
    required this.startMinute,
    required this.endMinute,
  });

  final int lessonIndex;
  final String label;
  final int? startMinute;
  final int? endMinute;

  String? get startLabel =>
      startMinute == null ? null : _formatMinutes(startMinute!);
  String? get endLabel => endMinute == null ? null : _formatMinutes(endMinute!);
}

class RoutineOverride {
  const RoutineOverride({
    required this.periodTypeId,
    required this.weekday,
    required this.lessonCount,
  });

  final String periodTypeId;
  final int weekday;
  final int lessonCount;
}

String _formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
