import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

/// 「全部日期」筛选弹层（temporary_adjustments_page_common.dart 的
/// _RecordDatesPanel）的核心交互冒烟：Forui FCalendar.grid 在与面板
/// 相同的尺寸/头部/范围约束下做受控范围选择（liftedRange）。
/// 受控模式要点：onChange 后必须用新 value 重建日历，控制器状态才会同步，
/// 否则第二次点击会重新开段而不是延长区间。
void main() {
  testWidgets('FCalendar.grid 范围选择冒烟：选两天得到完整区间', (tester) async {
    (DateTime, DateTime)? picked;
    Widget panel(ValueChanged<(DateTime, DateTime)?> onChange) => SizedBox(
      width: 296,
      height: 340,
      child: FCalendar.grid(
        control: FGridCalendarControl(
          start: DateTime.utc(2026, 9, 7),
          end: DateTime.utc(2027, 1, 31),
          today: DateTime.utc(2026, 11, 17),
          initial: DateTime.utc(2026, 11, 17),
        ),
        selectionControl: FDateSelectionControl.liftedRange(
          value: picked,
          onChange: onChange,
        ),
        headerBuilder: appDateFieldCalendarHeader,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => FTheme(
          data: AppTheme.foruiFor(false),
          child: FToaster(child: child!),
        ),
        home: Scaffold(
          body: Center(
            // 受控模式：与 _RecordDatesPanel 一致，onChange 后 setState 重建。
            child: StatefulBuilder(
              builder: (context, setState) =>
                  panel((value) => setState(() => picked = value)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 点击 11 月 10 日与 11 月 14 日两个日期格。
    Future<void> tapDay(int day) async {
      final target = find.byWidgetPredicate(
        (w) => w is Text && w.data == '$day',
      );
      expect(target, findsOneWidget, reason: '应能找到 11 月 $day 日的单元格');
      await tester.tap(target.first);
      await tester.pumpAndSettle();
    }

    await tapDay(10);
    expect(picked, isNotNull, reason: '第一次点击应返回完整区间 (start, start)');
    expect(picked!.$1.day, 10);
    expect(picked!.$2.day, 10);
    await tapDay(14);
    expect(picked!.$1.day, 10);
    expect(picked!.$2.day, 14);
  });
}
