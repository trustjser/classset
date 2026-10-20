import 'package:class_set/domain/models/free_slot.dart';

/// 科目在某个教学范围内的单日课节与连堂限制。
///
/// [weekday] 为 null 表示“每天”默认值；1 到 7 表示对应星期覆盖。
/// 每日连堂字段统计单日相邻双节组数，每周连堂字段统计整周总数。
class SubjectLessonConstraint {
  const SubjectLessonConstraint({
    required this.id,
    required this.subjectId,
    required this.scope,
    required this.scopeId,
    required this.stageId,
    required this.weekday,
    this.minimumDailyLessons,
    this.maximumDailyLessons,
    this.minimumDailyConsecutivePairs,
    this.maximumDailyConsecutivePairs,
    this.minimumWeeklyConsecutivePairs,
    this.maximumWeeklyConsecutivePairs,
  });

  final String id;
  final String subjectId;
  final FreeSlotScope scope;
  final String scopeId;
  final String stageId;
  final int? weekday;
  final int? minimumDailyLessons;
  final int? maximumDailyLessons;
  final int? minimumDailyConsecutivePairs;
  final int? maximumDailyConsecutivePairs;
  final int? minimumWeeklyConsecutivePairs;
  final int? maximumWeeklyConsecutivePairs;

  static void validate(Iterable<SubjectLessonConstraint> constraints) {
    for (final constraint in constraints) {
      if (constraint.scope == FreeSlotScope.school) {
        throw ArgumentError.value(constraint.scope, 'scope', '科目限制不支持全校范围');
      }
      if (constraint.weekday != null &&
          (constraint.weekday! < 1 || constraint.weekday! > 7)) {
        throw ArgumentError.value(constraint.weekday, 'weekday');
      }
      if (constraint.weekday != null &&
          (constraint.minimumWeeklyConsecutivePairs != null ||
              constraint.maximumWeeklyConsecutivePairs != null)) {
        throw ArgumentError('每周连堂限制只能设置在“每天”默认行');
      }
      for (final value in [
        constraint.minimumDailyLessons,
        constraint.maximumDailyLessons,
        constraint.minimumDailyConsecutivePairs,
        constraint.maximumDailyConsecutivePairs,
        constraint.minimumWeeklyConsecutivePairs,
        constraint.maximumWeeklyConsecutivePairs,
      ]) {
        if (value != null && value < 0) {
          throw ArgumentError.value(value, 'constraint value');
        }
      }
      if (_exceeds(
        constraint.minimumDailyLessons,
        constraint.maximumDailyLessons,
      )) {
        throw ArgumentError('单日最少课节数不能大于最多课节数');
      }
      if (_exceeds(
        constraint.minimumDailyConsecutivePairs,
        constraint.maximumDailyConsecutivePairs,
      )) {
        throw ArgumentError('单日最少连堂次数不能大于最多连堂次数');
      }
      if (_exceeds(
        constraint.minimumWeeklyConsecutivePairs,
        constraint.maximumWeeklyConsecutivePairs,
      )) {
        throw ArgumentError('每周最少连堂次数不能大于最多连堂次数');
      }
    }
  }

  static bool _exceeds(int? minimum, int? maximum) =>
      minimum != null && maximum != null && minimum > maximum;
}

/// 某范围、某星期应用继承后的限制值。
class EffectiveSubjectLessonConstraints {
  const EffectiveSubjectLessonConstraints({
    this.minimumDailyLessons,
    this.maximumDailyLessons,
    this.minimumDailyConsecutivePairs,
    this.maximumDailyConsecutivePairs,
    this.minimumWeeklyConsecutivePairs,
    this.maximumWeeklyConsecutivePairs,
  });

  final int? minimumDailyLessons;
  final int? maximumDailyLessons;
  final int? minimumDailyConsecutivePairs;
  final int? maximumDailyConsecutivePairs;
  final int? minimumWeeklyConsecutivePairs;
  final int? maximumWeeklyConsecutivePairs;
}

/// 按范围优先、再按星期覆盖关系逐字段解析限制。
EffectiveSubjectLessonConstraints resolveSubjectLessonConstraints({
  required Iterable<SubjectLessonConstraint> constraints,
  required FreeSlotScope scope,
  required String scopeId,
  required String stageId,
  required int? weekday,
  String? parentGradeId,
}) {
  if (scope == FreeSlotScope.school) {
    throw ArgumentError.value(scope, 'scope', '科目限制不支持全校范围');
  }
  final candidates = <({FreeSlotScope scope, String scopeId})>[
    (scope: scope, scopeId: scopeId),
    if (scope == FreeSlotScope.schoolClass && parentGradeId != null)
      (scope: FreeSlotScope.grade, scopeId: parentGradeId),
    if (scope != FreeSlotScope.stage)
      (scope: FreeSlotScope.stage, scopeId: stageId),
  ];
  final rows = constraints
      .where((row) => row.stageId == stageId)
      .toList(growable: false);

  int? resolveDaily(int? Function(SubjectLessonConstraint) read) {
    for (final candidate in candidates) {
      final candidateRows = rows.where(
        (row) =>
            row.scope == candidate.scope && row.scopeId == candidate.scopeId,
      );
      if (weekday != null) {
        for (final row in candidateRows) {
          if (row.weekday == weekday) {
            final value = read(row);
            if (value != null) return value;
          }
        }
      }
      for (final row in candidateRows) {
        if (row.weekday == null) {
          final value = read(row);
          if (value != null) return value;
        }
      }
    }
    return null;
  }

  int? resolveWeekly(int? Function(SubjectLessonConstraint) read) {
    for (final candidate in candidates) {
      for (final row in rows) {
        if (row.scope == candidate.scope &&
            row.scopeId == candidate.scopeId &&
            row.weekday == null) {
          final value = read(row);
          if (value != null) return value;
        }
      }
    }
    return null;
  }

  return EffectiveSubjectLessonConstraints(
    minimumDailyLessons: resolveDaily((row) => row.minimumDailyLessons),
    maximumDailyLessons: resolveDaily((row) => row.maximumDailyLessons),
    minimumDailyConsecutivePairs: resolveDaily(
      (row) => row.minimumDailyConsecutivePairs,
    ),
    maximumDailyConsecutivePairs: resolveDaily(
      (row) => row.maximumDailyConsecutivePairs,
    ),
    minimumWeeklyConsecutivePairs: resolveWeekly(
      (row) => row.minimumWeeklyConsecutivePairs,
    ),
    maximumWeeklyConsecutivePairs: resolveWeekly(
      (row) => row.maximumWeeklyConsecutivePairs,
    ),
  );
}
