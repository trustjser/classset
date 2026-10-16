class AcademicTerm {
  const AcademicTerm({
    required this.id,
    required this.title,
    required this.academicYear,
    required this.semesterLabel,
    required this.firstTeachingWeekStart,
    required this.teachingWeekCount,
    required this.createdAt,
    this.cycleMode = AcademicTermCycle.alternating,
  });

  final String id;
  final String title;
  final String academicYear;
  final String semesterLabel;
  final DateTime? firstTeachingWeekStart;
  final int teachingWeekCount;
  final DateTime createdAt;
  final AcademicTermCycle cycleMode;

  AcademicTerm copyWith({
    String? title,
    String? academicYear,
    String? semesterLabel,
    DateTime? firstTeachingWeekStart,
    bool clearFirstTeachingWeekStart = false,
    int? teachingWeekCount,
    AcademicTermCycle? cycleMode,
  }) => AcademicTerm(
    id: id,
    title: title ?? this.title,
    academicYear: academicYear ?? this.academicYear,
    semesterLabel: semesterLabel ?? this.semesterLabel,
    firstTeachingWeekStart: clearFirstTeachingWeekStart
        ? null
        : firstTeachingWeekStart ?? this.firstTeachingWeekStart,
    teachingWeekCount: teachingWeekCount ?? this.teachingWeekCount,
    createdAt: createdAt,
    cycleMode: cycleMode ?? this.cycleMode,
  );
}

enum AcademicTermCycle {
  everyWeek,
  alternating;

  String get storageValue => switch (this) {
    AcademicTermCycle.everyWeek => 'every_week',
    AcademicTermCycle.alternating => 'alternating',
  };

  static AcademicTermCycle fromStorage(String? value) => switch (value) {
    'every_week' => AcademicTermCycle.everyWeek,
    _ => AcademicTermCycle.alternating,
  };

  String get label => switch (this) {
    AcademicTermCycle.everyWeek => '每周课表',
    AcademicTermCycle.alternating => '单双周交替',
  };
}

/// 教学周历计算：第 1 教学周定义为单周，此后单双周交替。
extension AcademicTermCalendar on AcademicTerm {
  /// 是否已配置教学日历（第 1 教学周起始日期）。
  bool get hasCalendar => firstTeachingWeekStart != null;

  /// 第 [weekNumber] 教学周的起始日期（从 1 开始）；未配置日历时为 null。
  DateTime? teachingWeekStart(int weekNumber) {
    if (firstTeachingWeekStart == null ||
        weekNumber < 1 ||
        weekNumber > teachingWeekCount) {
      return null;
    }
    return DateTime(
      firstTeachingWeekStart!.year,
      firstTeachingWeekStart!.month,
      firstTeachingWeekStart!.day,
    ).add(Duration(days: (weekNumber - 1) * 7));
  }

  /// 第 [weekNumber] 教学周的结束日期；未配置日历时为 null。
  DateTime? teachingWeekEnd(int weekNumber) {
    final start = teachingWeekStart(weekNumber);
    return start?.add(const Duration(days: 6));
  }

  /// 第 [weekNumber] 周是否为单周（第 1 周为单周）。
  bool isOddWeek(int weekNumber) => weekNumber.isOdd;

  /// 周次在当前学期课表周期下的显示标签。
  String weekCycleLabel(int weekNumber) => switch (cycleMode) {
    AcademicTermCycle.everyWeek => '每周',
    AcademicTermCycle.alternating => isOddWeek(weekNumber) ? '单周' : '双周',
  };

  /// [date] 落在第几教学周（从 1 开始）；不在任何教学周内返回 null。
  int? teachingWeekOf(DateTime date) {
    final start = firstTeachingWeekStart;
    if (start == null) return null;
    final normalized = DateTime(date.year, date.month, date.day);
    final first = DateTime(start.year, start.month, start.day);
    final diffDays = normalized.difference(first).inDays;
    if (diffDays < 0) return null;
    final week = diffDays ~/ 7 + 1;
    return week <= teachingWeekCount ? week : null;
  }
}
