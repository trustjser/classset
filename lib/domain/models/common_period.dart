/// 公共时段（大课间、眼保健操等）：不占授课节次，仅显示于课表与打印。
///
/// 通过 [insertAfterLessonId] 挂在某节次之后；为 null 表示位于
/// 学段时间轴最前面（第 1 节之前）。
class CommonPeriod {
  const CommonPeriod({
    required this.id,
    required this.stageId,
    required this.name,
    required this.insertAfterLessonId,
    required this.durationMinutes,
    required this.startMinute,
    required this.endMinute,
    this.sortOrder = 0,
  });

  final String id;
  final String stageId;
  final String name;

  /// 挂在 `lesson_times.id` 之后；null = 第 1 节之前。
  final String? insertAfterLessonId;

  /// 未填起止时间时用于展示的时长（分钟）。
  final int durationMinutes;
  final int? startMinute;
  final int? endMinute;
  final int sortOrder;

  String? get startLabel =>
      startMinute == null ? null : _formatMinutes(startMinute!);
  String? get endLabel => endMinute == null ? null : _formatMinutes(endMinute!);

  CommonPeriod copyWith({
    String? name,
    String? insertAfterLessonId,
    int? durationMinutes,
    int? startMinute,
    int? endMinute,
    int? sortOrder,
    bool clearInsertAfterLessonId = false,
  }) => CommonPeriod(
    id: id,
    stageId: stageId,
    name: name ?? this.name,
    insertAfterLessonId: clearInsertAfterLessonId
        ? null
        : insertAfterLessonId ?? this.insertAfterLessonId,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}

String _formatMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
