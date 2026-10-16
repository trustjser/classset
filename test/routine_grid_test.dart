import 'package:class_set/domain/models/routine_grid.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:flutter_test/flutter_test.dart';

LessonPeriodType _period(
  String id,
  String name,
  int count, {
  int sortOrder = 0,
}) => LessonPeriodType(
  id: id,
  name: name,
  defaultLessonCount: count,
  sortOrder: sortOrder,
  lessonTimes: [
    for (var index = 1; index <= count; index++)
      LessonTime(
        lessonIndex: index,
        label: '',
        startMinute: null,
        endMinute: null,
      ),
  ],
);

/// 设计稿界面 02（小学部）：早读 1 + 上午 4 + 下午 4 + 晚上 2 = 11 节。
List<LessonPeriodType> _primaryPeriods() => [
  _period('p_morning_read', '早读', 1, sortOrder: 0),
  _period('p_am', '上午', 4, sortOrder: 1),
  _period('p_pm', '下午', 4, sortOrder: 2),
  _period('p_night', '晚上', 2, sortOrder: 3),
];

/// 设计稿界面 02b（初中部）：上午 5 + 下午 5 + 晚上 2 = 12 节，早读未启用。
List<LessonPeriodType> _juniorPeriods() => [
  _period('p_morning_read', '早读', 0, sortOrder: 0),
  _period('p_am', '上午', 5, sortOrder: 1),
  _period('p_pm', '下午', 5, sortOrder: 2),
  _period('p_night', '晚上', 2, sortOrder: 3),
];

void main() {
  group('lessonLabels', () {
    test('早读单节为「早读」，多节带序号', () {
      final single = lessonLabels([_period('a', '早读', 1)]);
      expect(single.single.label, '早读');

      final multi = lessonLabels([_period('a', '早读', 3)]);
      expect(multi.map((item) => item.label), ['早读 1', '早读 2', '早读 3']);
    });

    test('晚间时段为「晚自习 N」', () {
      final labels = lessonLabels([_period('a', '晚上', 2)]);
      expect(labels.map((item) => item.label), ['晚自习 1', '晚自习 2']);
      expect(labels.every((item) => item.isEvening), isTrue);
    });

    test('白天时段跨时段全局连续编号', () {
      final labels = lessonLabels(_primaryPeriods());
      expect(
        labels.map((item) => item.label).where((label) => label.startsWith('第')),
        ['第 1 节', '第 2 节', '第 3 节', '第 4 节', '第 5 节', '第 6 节', '第 7 节', '第 8 节'],
      );
      expect(labels.map((item) => item.label).toList(), [
        '早读',
        '第 1 节',
        '第 2 节',
        '第 3 节',
        '第 4 节',
        '第 5 节',
        '第 6 节',
        '第 7 节',
        '第 8 节',
        '晚自习 1',
        '晚自习 2',
      ]);
    });

    test('自定义时段延续全局编号且不视为晚间', () {
      final labels = lessonLabels([
        _period('a', '上午', 2, sortOrder: 0),
        _period('b', '午自习', 1, sortOrder: 1),
        _period('c', '下午', 2, sortOrder: 2),
      ]);
      expect(labels.map((item) => item.label), [
        '第 1 节',
        '第 2 节',
        '第 3 节',
        '第 4 节',
        '第 5 节',
      ]);
      expect(labels.any((item) => item.isEvening), isFalse);
    });

    test('按 sortOrder 排序后再编号', () {
      final labels = lessonLabels([
        _period('b', '下午', 1, sortOrder: 5),
        _period('a', '上午', 1, sortOrder: 1),
      ]);
      expect(labels.map((item) => item.label), ['第 1 节', '第 2 节']);
      expect(labels.map((item) => item.periodName), ['上午', '下午']);
    });

    test('空作息返回空列表', () {
      expect(lessonLabels(const []), isEmpty);
    });
  });

  group('buildRoutineRows', () {
    test('界面 02：早读 + 第 1–5 节平铺，第 6–8 节折叠，晚自习平铺', () {
      final rows = buildRoutineRows(_primaryPeriods());
      expect(rows.map((row) => row.label), [
        '早读',
        '第 1 节',
        '第 2 节',
        '第 3 节',
        '第 4 节',
        '第 5 节',
        '第 6–8 节',
        '晚自习 1',
        '晚自习 2',
      ]);
      final fold = rows.firstWhere((row) => row.isFolded);
      expect(fold.foldedLessons!.map((row) => row.label), ['第 6 节', '第 7 节', '第 8 节']);
      expect(fold.foldedLessons!.every((row) => !row.isEvening), isTrue);
      // 折叠行占位取首个隐藏行的时段。
      expect(fold.periodName, '下午');
    });

    test('界面 02b：第 1–6 节平铺，第 7–10 节折叠', () {
      final rows = buildRoutineRows(_juniorPeriods());
      expect(rows.map((row) => row.label), [
        '第 1 节',
        '第 2 节',
        '第 3 节',
        '第 4 节',
        '第 5 节',
        '第 6 节',
        '第 7–10 节',
        '晚自习 1',
        '晚自习 2',
      ]);
      final fold = rows.firstWhere((row) => row.isFolded);
      expect(fold.foldedLessons!.length, 4);
      expect(fold.foldedLessons!.first.label, '第 7 节');
      expect(fold.foldedLessons!.last.label, '第 10 节');
    });

    test('可折叠行不超过 6 条时不折叠', () {
      final rows = buildRoutineRows([
        _period('a', '上午', 3),
        _period('b', '下午', 3),
      ]);
      expect(rows.length, 6);
      expect(rows.any((row) => row.isFolded), isFalse);
    });

    test('恰好 6 条可折叠行时不折叠', () {
      final rows = buildRoutineRows([
        _period('a', '上午', 3),
        _period('b', '下午', 3),
        _period('c', '晚上', 1, sortOrder: 2),
      ]);
      expect(rows.length, 7);
      expect(rows.any((row) => row.isFolded), isFalse);
    });

    test('展开态返回全部行且无折叠行', () {
      final rows = buildRoutineRows(_juniorPeriods(), expandFolded: true);
      expect(rows.length, 12);
      expect(rows.any((row) => row.isFolded), isFalse);
      expect(rows.last.label, '晚自习 2');
    });

    test('仅有晚间时段时不折叠', () {
      final rows = buildRoutineRows([_period('a', '晚上', 3)]);
      expect(rows.map((row) => row.label), ['晚自习 1', '晚自习 2', '晚自习 3']);
      expect(rows.any((row) => row.isFolded), isFalse);
    });

    test('折叠阈值可配置', () {
      final rows = buildRoutineRows(
        [_period('a', '上午', 4)],
        visibleLessonRows: 2,
      );
      expect(rows.map((row) => row.label), ['第 1 节', '第 2 节', '第 3–4 节']);
    });

    test('空作息返回空列表', () {
      expect(buildRoutineRows(const []), isEmpty);
    });
  });

  group('foldedRowLabel', () {
    test('「第 N 节」区间格式', () {
      final rows = buildRoutineRows(_juniorPeriods());
      final fold = rows.firstWhere((row) => row.isFolded);
      expect(foldedRowLabel(fold.foldedLessons!), '第 7–10 节');
    });

    test('混合标签退化为「起–止」', () {
      final hidden = [
        RoutineRow(periodId: 'a', periodName: '早读', lessonIndex: 2, label: '早读 2', isEvening: false),
        RoutineRow(periodId: 'b', periodName: '上午', lessonIndex: 5, label: '第 5 节', isEvening: false),
      ];
      expect(foldedRowLabel(hidden), '早读 2–第 5 节');
    });
  });

  group('routineGridColumns', () {
    test('周一至周五上课天补出常驻周六列（设计稿界面 02）', () {
      expect(routineGridColumns(const {1, 2, 3, 4, 5}), [1, 2, 3, 4, 5, 6]);
    });

    test('周日启用时网格多出周日列（设计稿界面 02b）', () {
      expect(routineGridColumns(const {1, 2, 3, 4, 5, 7}), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
    });

    test('周六为上课天时不含周日列', () {
      expect(routineGridColumns(const {1, 2, 3, 4, 5, 6}), [1, 2, 3, 4, 5, 6]);
    });

    test('仅周日上课时覆盖整周', () {
      expect(routineGridColumns(const {7}), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('无上课天返回空', () {
      expect(routineGridColumns(const {}), isEmpty);
    });
  });
}
