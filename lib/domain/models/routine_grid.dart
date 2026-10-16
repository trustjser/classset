import 'dart:math' as math;

import 'package:class_set/domain/models/stage_routine.dart';

/// 一条节次标签：归属时段、节次序号、展示文字与是否晚自习。
class LessonLabel {
  const LessonLabel({
    required this.periodId,
    required this.periodName,
    required this.lessonIndex,
    required this.label,
    required this.isEvening,
  });

  final String periodId;
  final String periodName;
  final int lessonIndex;
  final String label;

  /// 晚间时段（名称含「晚」）：网格中始终平铺显示，不参与折叠。
  final bool isEvening;
}

/// 免任课网格的一行。[foldedLessons] 非空表示这是折叠行，
/// 展开后显示其中隐藏的行；平铺行该字段为 null。
class RoutineRow {
  const RoutineRow({
    required this.periodId,
    required this.periodName,
    required this.lessonIndex,
    required this.label,
    required this.isEvening,
    this.foldedLessons,
  });

  final String periodId;
  final String periodName;
  final int lessonIndex;
  final String label;
  final bool isEvening;

  /// 折叠行隐藏的节次行（平铺行为 null）。
  final List<RoutineRow>? foldedLessons;

  bool get isFolded => foldedLessons != null;
}

/// 设计稿默认平铺的节次行数：超出部分折叠为「第 X–Y 节」一行
/// （界面 02：早读 + 第 1–5 节平铺、第 6–8 节折叠；
/// 界面 02b：第 1–6 节平铺、第 7–10 节折叠）。
const int kRoutineVisibleLessonRows = 6;

/// 按设计稿规则生成节次标签：早读→「早读」，晚上→「晚自习 N」，
/// 其余时段→跨时段全局连续「第 N 节」。
List<LessonLabel> lessonLabels(List<LessonPeriodType> periods) {
  final sorted = [...periods]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final labels = <LessonLabel>[];
  var sequence = 0;
  for (final period in sorted) {
    final isMorning = period.name == '早读';
    final isEvening = period.name.contains('晚');
    for (final time in period.lessonTimes) {
      final label = isMorning
          ? (period.lessonTimes.length == 1 ? '早读' : '早读 ${time.lessonIndex}')
          : isEvening
          ? '晚自习 ${time.lessonIndex}'
          : '第 ${++sequence} 节';
      labels.add(
        LessonLabel(
          periodId: period.id,
          periodName: period.name,
          lessonIndex: time.lessonIndex,
          label: label,
          isEvening: isEvening,
        ),
      );
    }
  }
  return labels;
}

/// 构建免任课网格行：非晚自习行（含早读）仅平铺前 [visibleLessonRows] 条，
/// 其余折叠为一行置于晚自习行之前；晚自习行始终平铺。
///
/// 全部平铺时（含折叠行展开态）直接返回所有行。
List<RoutineRow> buildRoutineRows(
  List<LessonPeriodType> periods, {
  int visibleLessonRows = kRoutineVisibleLessonRows,
  bool expandFolded = false,
}) {
  final labels = lessonLabels(periods);
  if (labels.isEmpty) return const [];
  final foldable = labels.where((item) => !item.isEvening).toList();
  final evening = labels.where((item) => item.isEvening).toList();
  if (expandFolded || foldable.length <= visibleLessonRows) {
    return [for (final item in labels) _row(item)];
  }
  final shown = foldable.take(visibleLessonRows).map(_row).toList();
  final hidden = foldable.skip(visibleLessonRows).map(_row).toList();
  return [
    ...shown,
    RoutineRow(
      periodId: hidden.first.periodId,
      periodName: hidden.first.periodName,
      lessonIndex: hidden.first.lessonIndex,
      label: foldedRowLabel(hidden),
      isEvening: false,
      foldedLessons: hidden,
    ),
    ...evening.map(_row),
  ];
}

/// 折叠行标签：「第 7–10 节」；起止不是「第 N 节」样式时退化为「起–止」。
String foldedRowLabel(List<RoutineRow> hidden) {
  final first = hidden.first.label;
  final last = hidden.last.label;
  final firstMatch = RegExp(r'^第 (\d+) 节$').firstMatch(first);
  final lastMatch = RegExp(r'^第 (\d+) 节$').firstMatch(last);
  if (firstMatch != null && lastMatch != null) {
    return '第 ${firstMatch.group(1)}–${lastMatch.group(1)} 节';
  }
  return '$first–$last';
}

RoutineRow _row(LessonLabel item) => RoutineRow(
  periodId: item.periodId,
  periodName: item.periodName,
  lessonIndex: item.lessonIndex,
  label: item.label,
  isEvening: item.isEvening,
);

/// 网格列：周一至「最晚上课天与周六的较晚者」。
///
/// 周六列常驻（非上课天时置灰显示「—」、表头无标签）；
/// 周日仅在上课天才出现——设计稿注释「周日仅初中部启用 → 网格多出周日列，
/// 切回小学部时该列自动消失」，两屏网格体（小学部 6 列 / 初中部 7 列）均遵此。
List<int> routineGridColumns(Set<int> teachingDays) {
  if (teachingDays.isEmpty) return const [];
  final maxDay = math.max(teachingDays.reduce(math.max), DateTime.saturday);
  return [for (var day = DateTime.monday; day <= maxDay; day++) day];
}
