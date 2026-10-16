/// 教学日历例外：停课 / 节假日与补课映射。
///
/// 停课日不上课，该日课节不计入容量与统计；补课日明确映射到
/// 「采用哪一天、哪一周的课表」（由 [makeupWeekday] 指定星期几的课表）。
class CalendarException {
  const CalendarException({
    required this.id,
    required this.termId,
    required this.date,
    required this.kind,
    required this.makeupWeekday,
    required this.note,
    this.makeupForDate,
  });

  final String id;
  final String termId;

  /// 仅保留日期部分（年月日）。
  final DateTime date;
  final CalendarExceptionKind kind;

  /// 补课日采用的课表星期（1=星期一 … 7=星期日）；停课日为 null。
  final int? makeupWeekday;

  /// 补课对应的原课日期（被补的是哪一天的课）；停课日为 null。
  final DateTime? makeupForDate;
  final String note;

  bool get isMakeup => kind == CalendarExceptionKind.makeup;

  CalendarException copyWith({
    DateTime? date,
    CalendarExceptionKind? kind,
    int? makeupWeekday,
    DateTime? makeupForDate,
    String? note,
  }) => CalendarException(
    id: id,
    termId: termId,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    makeupWeekday: makeupWeekday ?? this.makeupWeekday,
    makeupForDate: makeupForDate ?? this.makeupForDate,
    note: note ?? this.note,
  );
}

enum CalendarExceptionKind {
  /// 停课 / 节假日：当天不上课。
  holiday,

  /// 补课：当天上课，采用 [makeupWeekday] 对应星期的课表。
  makeup;

  String get storageValue => switch (this) {
    CalendarExceptionKind.holiday => 'holiday',
    CalendarExceptionKind.makeup => 'makeup',
  };

  static CalendarExceptionKind fromStorage(String value) => switch (value) {
    'makeup' => CalendarExceptionKind.makeup,
    _ => CalendarExceptionKind.holiday,
  };

  String get label => switch (this) {
    CalendarExceptionKind.holiday => '停课 / 节假日',
    CalendarExceptionKind.makeup => '补课',
  };
}
