/// 作息模板：源自大陆中小学常见作息安排（教育部睡眠管理通知口径：
/// 小学第一节课一般不早于 8:20、中学不早于 8:00；小学每课时 40 分钟、
/// 初中每课时 45 分钟；下午一般 14:00 前后开始，寄宿制学校增设晚自习）。
///
/// 模板只填充作息页的草稿（节数、上课日、节次时间），点击「保存」后才落库。
class RoutineTemplate {
  const RoutineTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.teachingWeekdays,
    required this.periods,
  });

  final String id;
  final String name;

  /// 适用场景说明，展示在模板选择弹窗中。
  final String description;
  final Set<int> teachingWeekdays;

  /// 按时段名称（与作息页内置时段一致）给出节数与节次时间；
  /// 模板未列出的时段应用后节数清零。
  final List<RoutineTemplatePeriod> periods;

  /// 结构摘要，如「早读 1 节 · 上午 4 节 · 下午 3 节」。
  String get structureSummary {
    const order = ['早上', '上午', '下午', '晚上'];
    final byName = {for (final period in periods) period.periodName: period};
    final parts = <String>[];
    for (final name in order) {
      final period = byName[name];
      if (period == null || period.lessonCount == 0) continue;
      parts.add(
        name == '早上'
            ? '早读 ${period.lessonCount} 节'
            : '$name ${period.lessonCount} 节',
      );
    }
    return parts.isEmpty ? '未设置节次' : parts.join(' · ');
  }
}

class RoutineTemplatePeriod {
  const RoutineTemplatePeriod({
    required this.periodName,
    required this.lessonCount,
    required this.times,
  });

  final String periodName;
  final int lessonCount;

  /// 每节的 (开始, 结束) 时间，数量与 [lessonCount] 一致，格式 HH:mm。
  final List<(String, String)> times;
}

const _weekdaysMonToFri = <int>{1, 2, 3, 4, 5};

/// 内置作息模板，按学段常见程度排序。
final List<RoutineTemplate> routineTemplates = [
  RoutineTemplate(
    id: 'primary_day',
    name: '小学走读',
    description: '40 分钟课时，第一节 8:20 开始，符合小学上课时间不早于 8:20 的要求。',
    teachingWeekdays: _weekdaysMonToFri,
    periods: [
      RoutineTemplatePeriod(
        periodName: '上午',
        lessonCount: 4,
        times: [
          ('08:20', '09:00'),
          ('09:10', '09:50'),
          ('10:20', '11:00'),
          ('11:10', '11:50'),
        ],
      ),
      RoutineTemplatePeriod(
        periodName: '下午',
        lessonCount: 3,
        times: [('14:00', '14:40'), ('14:50', '15:30'), ('15:40', '16:20')],
      ),
    ],
  ),
  RoutineTemplate(
    id: 'junior_day',
    name: '初中走读',
    description: '45 分钟课时，早读 + 上午 4 节 + 下午 3 节，第一节 8:00 开始。',
    teachingWeekdays: _weekdaysMonToFri,
    periods: [
      RoutineTemplatePeriod(
        periodName: '早上',
        lessonCount: 1,
        times: [('07:40', '08:00')],
      ),
      RoutineTemplatePeriod(
        periodName: '上午',
        lessonCount: 4,
        times: [
          ('08:00', '08:45'),
          ('08:55', '09:40'),
          ('10:10', '10:55'),
          ('11:05', '11:50'),
        ],
      ),
      RoutineTemplatePeriod(
        periodName: '下午',
        lessonCount: 3,
        times: [('14:00', '14:45'), ('14:55', '15:40'), ('15:50', '16:35')],
      ),
    ],
  ),
  RoutineTemplate(
    id: 'junior_boarding',
    name: '初中寄宿',
    description: '早读 + 上午 4 节 + 下午 4 节 + 晚自习 2 节，适合寄宿制初中。',
    teachingWeekdays: _weekdaysMonToFri,
    periods: [
      RoutineTemplatePeriod(
        periodName: '早上',
        lessonCount: 1,
        times: [('07:40', '08:00')],
      ),
      RoutineTemplatePeriod(
        periodName: '上午',
        lessonCount: 4,
        times: [
          ('08:00', '08:45'),
          ('08:55', '09:40'),
          ('10:10', '10:55'),
          ('11:05', '11:50'),
        ],
      ),
      RoutineTemplatePeriod(
        periodName: '下午',
        lessonCount: 4,
        times: [
          ('14:00', '14:45'),
          ('14:55', '15:40'),
          ('15:50', '16:35'),
          ('16:45', '17:30'),
        ],
      ),
      RoutineTemplatePeriod(
        periodName: '晚上',
        lessonCount: 2,
        times: [('19:00', '19:45'), ('19:55', '20:40')],
      ),
    ],
  ),
  RoutineTemplate(
    id: 'senior_boarding',
    name: '高中寄宿',
    description: '早读 + 上午 4 节 + 下午 4 节 + 晚自习 3 节，适合寄宿制高中。',
    teachingWeekdays: _weekdaysMonToFri,
    periods: [
      RoutineTemplatePeriod(
        periodName: '早上',
        lessonCount: 1,
        times: [('07:20', '07:50')],
      ),
      RoutineTemplatePeriod(
        periodName: '上午',
        lessonCount: 4,
        times: [
          ('08:00', '08:45'),
          ('08:55', '09:40'),
          ('10:10', '10:55'),
          ('11:05', '11:50'),
        ],
      ),
      RoutineTemplatePeriod(
        periodName: '下午',
        lessonCount: 4,
        times: [
          ('14:10', '14:55'),
          ('15:05', '15:50'),
          ('16:00', '16:45'),
          ('16:55', '17:40'),
        ],
      ),
      RoutineTemplatePeriod(
        periodName: '晚上',
        lessonCount: 3,
        times: [('19:00', '19:45'), ('19:55', '20:40'), ('20:50', '21:35')],
      ),
    ],
  ),
];
