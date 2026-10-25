import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';

/// 固定种子求解的配置与复现参数。
class ScheduleRunConfig {
  const ScheduleRunConfig({
    required this.selectedClassIds,
    required this.seed,
    this.strength = ScheduleStrength.normal,
    this.solverVersion = '1',
  });

  final Set<String> selectedClassIds;
  final int seed;
  final ScheduleStrength strength;
  final String solverVersion;

  Map<String, Object?> toJson() => {
    'selectedClassIds': selectedClassIds.toList()..sort(),
    'seed': seed,
    'strength': strength.name,
    'solverVersion': solverVersion,
  };

  factory ScheduleRunConfig.fromJson(Map<String, Object?> json) =>
      ScheduleRunConfig(
        selectedClassIds: (json['selectedClassIds'] as List)
            .cast<String>()
            .toSet(),
        seed: (json['seed'] as num).toInt(),
        strength: ScheduleStrength.values.firstWhere(
          (value) => value.name == json['strength'],
          orElse: () => ScheduleStrength.normal,
        ),
        solverVersion: json['solverVersion'] as String? ?? '1',
      );
}

/// 一次候选位置检查实际观察到的硬性阻断条件。
class ScheduleBlocker {
  const ScheduleBlocker({
    required this.code,
    required this.message,
    this.conditionId,
    this.position,
    this.relatedIds = const [],
  });

  final String code;
  final String message;
  final String? conditionId;
  final SchedulePosition? position;
  final List<String> relatedIds;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'conditionId': conditionId,
    'position': position?.toJson(),
    'relatedIds': relatedIds,
  };

  factory ScheduleBlocker.fromJson(Map<String, Object?> json) =>
      ScheduleBlocker(
        code: json['code'] as String,
        message: json['message'] as String,
        conditionId: json['conditionId'] as String?,
        position: switch (json['position']) {
          final Map value => SchedulePosition.fromJson(
            value.cast<String, Object?>(),
          ),
          _ => null,
        },
        relatedIds: (json['relatedIds'] as List?)?.cast<String>() ?? const [],
      );
}

/// 一门暂放课及其实际遇到的阻断清单。
class ScheduleUnplacedCourse {
  const ScheduleUnplacedCourse({required this.itemId, required this.blockers});

  final String itemId;
  final List<ScheduleBlocker> blockers;

  Map<String, Object?> toJson() => {
    'itemId': itemId,
    'blockers': [for (final blocker in blockers) blocker.toJson()],
  };

  factory ScheduleUnplacedCourse.fromJson(Map<String, Object?> json) =>
      ScheduleUnplacedCourse(
        itemId: json['itemId'] as String,
        blockers: [
          for (final value in json['blockers'] as List)
            ScheduleBlocker.fromJson((value as Map).cast<String, Object?>()),
        ],
      );
}

/// 一类软偏好的满足实例数与适用实例数。
class SchedulePreferenceScore {
  const SchedulePreferenceScore({
    required this.satisfied,
    required this.applicable,
  });

  final int satisfied;
  final int applicable;
  double? get rate => applicable == 0 ? null : satisfied / applicable;

  Map<String, Object?> toJson() => {
    'satisfied': satisfied,
    'applicable': applicable,
  };

  factory SchedulePreferenceScore.fromJson(Map<String, Object?> json) =>
      SchedulePreferenceScore(
        satisfied: (json['satisfied'] as num).toInt(),
        applicable: (json['applicable'] as num).toInt(),
      );
}

/// 求解报告，硬性总量缺口与暂放课分别列示。
class ScheduleReport {
  const ScheduleReport({
    required this.totalItems,
    required this.placedItems,
    required this.coverage,
    required this.preferenceScores,
    required this.unplaced,
    required this.unmetHardRequirements,
    required this.candidateChecks,
  });

  final int totalItems;
  final int placedItems;
  final int coverage;
  final Map<String, SchedulePreferenceScore> preferenceScores;
  final List<ScheduleUnplacedCourse> unplaced;
  final List<ScheduleBlocker> unmetHardRequirements;
  final int candidateChecks;

  double get preferenceRateSum => preferenceScores.values.fold<double>(
    0,
    (sum, score) => sum + (score.rate ?? 0),
  );

  Map<String, Object?> toJson() => {
    'totalItems': totalItems,
    'placedItems': placedItems,
    'coverage': coverage,
    'preferenceScores': preferenceScores.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'unplaced': [for (final course in unplaced) course.toJson()],
    'unmetHardRequirements': [
      for (final blocker in unmetHardRequirements) blocker.toJson(),
    ],
    'candidateChecks': candidateChecks,
  };

  factory ScheduleReport.fromJson(Map<String, Object?> json) => ScheduleReport(
    totalItems: (json['totalItems'] as num).toInt(),
    placedItems: (json['placedItems'] as num).toInt(),
    coverage: (json['coverage'] as num).toInt(),
    preferenceScores: (json['preferenceScores'] as Map).map(
      (key, value) => MapEntry(
        key as String,
        SchedulePreferenceScore.fromJson(
          (value as Map).cast<String, Object?>(),
        ),
      ),
    ),
    unplaced: [
      for (final value in json['unplaced'] as List)
        ScheduleUnplacedCourse.fromJson((value as Map).cast<String, Object?>()),
    ],
    unmetHardRequirements: [
      for (final value in json['unmetHardRequirements'] as List)
        ScheduleBlocker.fromJson((value as Map).cast<String, Object?>()),
    ],
    candidateChecks: (json['candidateChecks'] as num).toInt(),
  );
}

/// 一次完整求解得到的候选课表；由仓库决定何时原子提交。
class ScheduleRun {
  const ScheduleRun({
    required this.id,
    required this.termId,
    required this.inputFingerprint,
    required this.config,
    required this.report,
    required this.items,
  });

  final String id;
  final String termId;
  final String inputFingerprint;
  final ScheduleRunConfig config;
  final ScheduleReport report;
  final List<ScheduleItem> items;

  Map<String, Object?> toJson() => {
    'id': id,
    'termId': termId,
    'inputFingerprint': inputFingerprint,
    'config': config.toJson(),
    'report': report.toJson(),
    'items': [for (final item in items) item.toJson()],
  };

  factory ScheduleRun.fromJson(Map<String, Object?> json) => ScheduleRun(
    id: json['id'] as String,
    termId: json['termId'] as String,
    inputFingerprint: json['inputFingerprint'] as String,
    config: ScheduleRunConfig.fromJson(
      (json['config'] as Map).cast<String, Object?>(),
    ),
    report: ScheduleReport.fromJson(
      (json['report'] as Map).cast<String, Object?>(),
    ),
    items: [
      for (final value in json['items'] as List)
        ScheduleItem.fromJson((value as Map).cast<String, Object?>()),
    ],
  );
}
