import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/features/terms/dialogs/exception_editor_dialog.dart';
import 'package:class_set/features/terms/dialogs/term_management_dialog.dart';
import 'package:class_set/features/terms/dialogs/term_editor_dialog.dart';
import 'package:class_set/features/terms/widgets/term_summary_card.dart';
import 'package:class_set/features/terms/widgets/teaching_calendar_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => FTheme(
      data: AppTheme.forui,
      child: FToaster(child: child!),
    ),
    home: Scaffold(body: child),
  ),
);

AcademicTerm _term({
  required String id,
  required String title,
  DateTime? start,
  bool withoutCalendar = false,
  DateTime? created,
  int weeks = 20,
}) => AcademicTerm(
  id: id,
  title: title,
  academicYear: '2026-2027',
  semesterLabel: '秋季学期',
  firstTeachingWeekStart: withoutCalendar
      ? null
      : start ?? DateTime(2026, 9, 1),
  teachingWeekCount: weeks,
  createdAt: created ?? DateTime(2026, 8, 1),
);

void main() {
  testWidgets('学期日期字段使用 Forui 小尺寸并垂直居中', (tester) async {
    const dateLabel = '09/01（周二）';
    await tester.pumpWidget(
      _wrap(
        Center(
          child: SizedBox(
            width: 220,
            child: AppDateField(
              value: DateTime(2026, 9, 1),
              firstDate: DateTime(2026, 9, 1),
              lastDate: DateTime(2026, 9, 7),
              hint: '选择日期',
              format: (_) => dateLabel,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final dateField = tester.widget(
      find.byWidgetPredicate((widget) => widget is FDateField),
    );
    expect((dateField as dynamic).size, FTextFieldSizeVariant.sm);
    expect((dateField as dynamic).textAlignVertical, TextAlignVertical.center);
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.byWidgetPredicate((widget) => widget is FDateField),
                  matching: find.byType(SizedBox),
                )
                .first,
          )
          .height,
      35,
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      dateLabel,
    );
    final fieldRect = tester.getRect(
      find.byWidgetPredicate((widget) => widget is FDateField),
    );
    final textRect = tester.getRect(find.byType(EditableText));
    expect(
      (textRect.center.dy - fieldRect.center.dy).abs(),
      lessThanOrEqualTo(1),
      reason: 'field=$fieldRect text=$textRect',
    );
  });

  testWidgets('Forui 日期选择遵循教学周范围并回传所选日期', (tester) async {
    DateTime? selectedDate;
    final firstDate = DateTime(2026, 9, 1);
    final lastDate = DateTime(2026, 9, 7);
    await tester.pumpWidget(
      _wrap(
        Center(
          child: SizedBox(
            width: 220,
            child: AppDateField(
              value: firstDate,
              firstDate: firstDate,
              lastDate: lastDate,
              hint: '选择日期',
              format: (date) => '${date.month}/${date.day}',
              onChanged: (date) => selectedDate = date,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byWidgetPredicate((widget) => widget is FDateField));
    await tester.pumpAndSettle();

    final calendar = tester.widget<FCalendar>(
      find.byWidgetPredicate((widget) => widget is FCalendar).last,
    );
    final control = calendar.control as FGridCalendarControl;
    final calendarController = control.controller!;
    expect(calendarController.start, DateTime.utc(2026, 9, 1));
    expect(calendarController.end, DateTime.utc(2026, 9, 7));
    await tester.tap(find.text('5').first);
    await tester.pumpAndSettle();

    expect(selectedDate, DateTime.utc(2026, 9, 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('帮助图标颜色比字段标签更浅', (tester) async {
    await tester.pumpWidget(_wrap(const AppHelpTooltip(message: '帮助')));

    final icon = tester.widget<Icon>(find.byIcon(Icons.help_outline));
    expect(icon.color, const Color(0xFFA6A6A6));
    expect(
      icon.color!.computeLuminance(),
      greaterThan(AppTheme.inkSecondary.computeLuminance()),
    );
  });

  testWidgets('窄卡片宽度下学期起始日期仍保持单行', (tester) async {
    tester.view.physicalSize = const Size(916, 707);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        TermSummaryCard(
          selectedTerm: _term(id: 't1', title: '2026-2027 学年 · 秋季学期'),
          onEditTerm: () {},
          onManageTerms: () {},
          onAddTerm: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final startDate = find.text('2026-09-01（周二）');
    expect(startDate, findsOneWidget);
    expect(tester.getSize(startDate).height, lessThanOrEqualTo(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('学期摘要按单行信息展示并将管理与新建放入更多菜单', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TermSummaryCard(
          selectedTerm: _term(id: 't1', title: '2026 学年 · 秋季学期'),
          onEditTerm: () {},
          onManageTerms: () {},
          onAddTerm: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前学期'), findsOneWidget);
    expect(find.text('2026 学年 · 秋季学期'), findsOneWidget);
    expect(find.text('第 1 教学周起始'), findsOneWidget);
    expect(find.text('课表周期'), findsOneWidget);
    expect(find.byType(AppSelectField<String>), findsNothing);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('所有学期'), findsOneWidget);
    expect(find.text('＋ 新建学期'), findsOneWidget);
    expect(find.text('编辑当前学期'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日历默认显示六周，展开和收起可用', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SingleChildScrollView(
          child: TeachingCalendarTable(
            term: _term(id: 't1', title: '2026 秋季', weeks: 20),
            exceptions: const <CalendarException>[],
            onEditWeek: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第 6 周'), findsOneWidget);
    expect(find.text('第 7 周'), findsNothing);
    await tester.tap(find.text('第 7 – 20 周 未展开（单双周自动交替）'));
    await tester.pumpAndSettle();
    expect(find.text('第 7 周'), findsOneWidget);
    expect(find.text('第 20 周'), findsOneWidget);

    await tester.ensureVisible(find.text('收起教学周'));
    await tester.tap(find.text('收起教学周'));
    await tester.pumpAndSettle();
    expect(find.text('第 7 周'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('节假日备注包含补字时仍使用停课颜色', (tester) async {
    final term = _term(id: 't1', title: '2026 秋季', weeks: 1);
    await tester.pumpWidget(
      _wrap(
        TeachingCalendarTable(
          term: term,
          exceptions: [
            CalendarException(
              id: 'holiday',
              termId: term.id,
              date: DateTime(2026, 9, 1),
              kind: CalendarExceptionKind.holiday,
              makeupWeekday: null,
              note: '补休',
            ),
          ],
          onEditWeek: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.textContaining('补休'),
      matching: find.byType(ColoredBox),
    );
    expect(tester.widget<ColoredBox>(row.first).color, const Color(0xFFFFF8F8));
  });

  testWidgets('每周相同标签使用中性色而非链接色', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TeachingCalendarTable(
          term: _term(
            id: 't1',
            title: '2026 秋季',
            weeks: 1,
          ).copyWith(cycleMode: AcademicTermCycle.everyWeek),
          exceptions: const <CalendarException>[],
          onEditWeek: (_) {},
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('每周相同'));
    expect(label.style?.color, AppTheme.inkSecondary);
  });

  testWidgets('补课例外行使用补课颜色', (tester) async {
    final term = _term(id: 't1', title: '2026 秋季', weeks: 1);
    await tester.pumpWidget(
      _wrap(
        TeachingCalendarTable(
          term: term,
          exceptions: [
            CalendarException(
              id: 'makeup',
              termId: term.id,
              date: DateTime(2026, 9, 1),
              kind: CalendarExceptionKind.makeup,
              makeupWeekday: 2,
              note: '',
            ),
          ],
          onEditWeek: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.textContaining('补 星期二课表'),
      matching: find.byType(ColoredBox),
    );
    expect(tester.widget<ColoredBox>(row.first).color, const Color(0xFFFFFDF6));
  });

  testWidgets('较长例外摘要单行省略且悬停提示完整内容', (tester) async {
    final term = _term(id: 't1', title: '2026 秋季', weeks: 1);
    final note = List.filled(8, '国庆调休安排说明').join('，');
    final summary = '09/01 $note';
    await tester.pumpWidget(
      _wrap(
        TeachingCalendarTable(
          term: term,
          exceptions: [
            CalendarException(
              id: 'holiday',
              termId: term.id,
              date: DateTime(2026, 9, 1),
              kind: CalendarExceptionKind.holiday,
              makeupWeekday: null,
              note: note,
            ),
          ],
          onEditWeek: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final summaryText = tester.widget<Text>(find.text(summary));
    expect(summaryText.maxLines, 1);
    expect(summaryText.overflow, TextOverflow.ellipsis);

    final tooltip = find.byTooltip(summary);
    expect(tooltip, findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(tooltip));
    await mouse.moveTo(tester.getCenter(tooltip));
    await tester.pumpAndSettle();
    expect(find.text(summary, skipOffstage: false), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  testWidgets('每周相同模式显示统一周标签且无日历时禁用例外编辑', (tester) async {
    final term = _term(
      id: 't1',
      title: '周模板',
      withoutCalendar: true,
      weeks: 4,
    ).copyWith(cycleMode: AcademicTermCycle.everyWeek);
    await tester.pumpWidget(
      _wrap(
        TeachingCalendarTable(
          term: term,
          exceptions: const <CalendarException>[],
          onEditWeek: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('每周相同'), findsNWidgets(4));
    expect(find.byTooltip('配置第 1 教学周日期后可编辑例外安排'), findsNWidgets(4));
    final editButtons = tester.widgetList<FButton>(find.byType(FButton));
    expect(editButtons, hasLength(4));
    expect(editButtons.every((button) => button.onPress == null), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('学期列表按首周日期倒序并禁用当前学期删除', (tester) async {
    final terms = [
      _term(id: 'old', title: '较早学期', start: DateTime(2025, 9, 1)),
      _term(id: 'current', title: '2026 秋季', start: DateTime(2026, 9, 1)),
      _term(id: 'unset', title: '未配置日期', withoutCalendar: true),
    ];
    await tester.pumpWidget(
      _wrap(
        TermManagementDialog(
          terms: terms,
          activeTermId: 'current',
          onSelect: (_) {},
          onEdit: (_) {},
          onDelete: (_) async => false,
          onCreate: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Material &&
                  widget.type == MaterialType.transparency,
            ),
          )
          .width,
      572,
    );
    final unsetY = tester.getTopLeft(find.text('未配置日期')).dy;
    final currentY = tester.getTopLeft(find.text('2026 秋季')).dy;
    final oldY = tester.getTopLeft(find.text('较早学期')).dy;
    expect(find.text('切换'), findsOneWidget);
    final currentRadio = find.byTooltip('切换到2026 秋季');
    expect(tester.getSize(currentRadio).width, 24);
    expect(
      tester.getTopLeft(currentRadio).dx,
      tester.getTopLeft(find.text('切换')).dx,
    );
    final radios = tester.widgetList<AppRadioIndicator<String>>(
      find.byType(AppRadioIndicator<String>),
    );
    expect(radios, hasLength(3));
    expect(radios.map((radio) => radio.indicatorSize), everyElement(14));
    expect(radios.map((radio) => radio.hitTargetSize), everyElement(24));
    expect(radios.map((radio) => radio.groupValue), everyElement('current'));
    expect(currentY, lessThan(oldY));
    expect(oldY, lessThan(unsetY));
    expect(find.byTooltip('当前学期不可删除'), findsOneWidget);
    final currentDelete = tester.widget<FButton>(
      find.descendant(
        of: find.byTooltip('当前学期不可删除'),
        matching: find.byType(FButton),
      ),
    );
    expect(currentDelete.onPress, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('较窄窗口下学期列表弹窗完整显示编辑和删除操作', (tester) async {
    tester.view.physicalSize = const Size(1184, 707);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        TermManagementDialog(
          terms: [_term(id: 't1', title: '2026-2027 学年 · 秋季学期')],
          activeTermId: null,
          onSelect: (_) {},
          onEdit: (_) {},
          onDelete: (_) async => false,
          onCreate: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tableViewport = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    final deleteAction = find.byTooltip('删除学期');
    expect(tableViewport, findsOneWidget);
    expect(deleteAction, findsOneWidget);
    expect(
      tester.getRect(deleteAction).right,
      lessThanOrEqualTo(tester.getRect(tableViewport).right),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('日历表在窄窗口和矮窗口内可滚动且不溢出', (tester) async {
    tester.view.physicalSize = const Size(480, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        TeachingCalendarTable(
          term: _term(id: 't1', title: '窄窗口', weeks: 8),
          exceptions: const <CalendarException>[],
          onEditWeek: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('教学周操作列居中显示蓝色编辑入口', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TeachingCalendarTable(
          term: _term(id: 't1', title: '2026 秋季', weeks: 1),
          exceptions: const <CalendarException>[],
          onEditWeek: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final actionHeader = tester.getRect(find.text('操作'));
    final editAction = find.byTooltip('编辑本周例外安排');
    final editRect = tester.getRect(editAction);
    expect((editRect.center.dx - actionHeader.center.dx).abs(), lessThan(1));
    expect(editRect.width, greaterThanOrEqualTo(64));
    final editLabel = tester.widget<Text>(
      find.descendant(of: editAction, matching: find.text('编辑')),
    );
    final editParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: editAction, matching: find.text('编辑')),
    );
    expect(
      editParagraph.size.width,
      greaterThanOrEqualTo(
        editParagraph.getMaxIntrinsicWidth(double.infinity) - 1,
      ),
    );
    expect(
      editParagraph.size.height,
      greaterThanOrEqualTo(
        editParagraph.getMaxIntrinsicHeight(double.infinity) - 0.5,
      ),
      reason: '操作按钮内必须留足文字行高，避免底部字形被裁切',
    );
    expect(editLabel.style?.color, AppTheme.blue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('学期列表各列内容与表头左对齐并保留水平间距', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TermManagementDialog(
          terms: [_term(id: 't1', title: '2026 秋季')],
          activeTermId: null,
          onSelect: (_) {},
          onEdit: (_) {},
          onDelete: (_) async => false,
          onCreate: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final termHeader = tester.getRect(find.text('学期'));
    final termValue = tester.getRect(find.text('2026 秋季'));
    final startHeader = tester.getRect(find.text('第 1 教学周起始'));
    final startValue = tester.getRect(find.text('2026-09-01'));
    final cycleHeader = tester.getRect(find.text('总周数 · 课表周期'));
    final cycleValue = tester.getRect(find.text('20 周 · 单双周交替'));
    final operationHeader = tester.getRect(find.text('操作'));
    final editLabel = tester.getRect(find.text('编辑'));
    final deleteLabel = tester.getRect(find.text('删除'));
    for (final pair in [
      (termHeader, termValue),
      (startHeader, startValue),
      (cycleHeader, cycleValue),
      (operationHeader, editLabel),
    ]) {
      expect((pair.$1.left - pair.$2.left).abs(), lessThan(1));
    }
    expect(startValue.left - termValue.right, greaterThanOrEqualTo(12));
    expect(cycleValue.left - startValue.right, greaterThanOrEqualTo(12));
    expect(deleteLabel.left - editLabel.right, greaterThanOrEqualTo(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('学期摘要完整显示课表周期和编辑操作', (tester) async {
    tester.view.physicalSize = const Size(1276, 655);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        TermSummaryCard(
          selectedTerm: _term(id: 't1', title: '2026 秋季'),
          onEditTerm: () {},
          onManageTerms: () {},
          onAddTerm: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cycle = tester.widget<Text>(find.text('20 周 · 单双周交替'));
    expect(cycle.maxLines, 1);
    expect(cycle.overflow, TextOverflow.ellipsis);
    final cycleParagraph = tester.renderObject<RenderParagraph>(
      find.text('20 周 · 单双周交替'),
    );
    expect(
      cycleParagraph.size.width,
      greaterThanOrEqualTo(
        cycleParagraph.getMaxIntrinsicWidth(double.infinity) - 1,
      ),
    );
    expect(find.text('编辑'), findsOneWidget);
    final startDate = tester.renderObject<RenderParagraph>(
      find.text('2026-09-01（周二）'),
    );
    expect(
      startDate.size.width,
      greaterThanOrEqualTo(startDate.getMaxIntrinsicWidth(double.infinity) - 1),
      reason: '首周日期应充分使用摘要卡内的横向空间',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('学期编辑周数步进器靠左紧凑排列且内容水平对齐', (tester) async {
    await tester.pumpWidget(
      _wrap(
        TermEditorDialog(
          term: _term(id: 't1', title: '2026 秋季'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final minus = tester.getCenter(find.byIcon(Icons.remove));
    final plus = tester.getCenter(find.byIcon(Icons.add));
    final countRect = tester.getRect(find.byType(EditableText).last);
    final weekUnit = tester.getRect(find.text('周'));
    final fieldLeft = tester.getRect(find.byType(FTextFormField).first).left;
    expect(minus.dx - fieldLeft, inInclusiveRange(0, 32));
    expect(countRect.center.dx - minus.dx, inInclusiveRange(20, 70));
    expect(plus.dx - countRect.center.dx, lessThan(90));
    expect(plus.dx - minus.dx, lessThan(150));
    expect(
      (minus.dy - countRect.center.dy).abs(),
      lessThanOrEqualTo(2),
      reason:
          'minus=$minus count=$countRect field=${tester.getRect(find.byType(FTextFormField).last)}',
    );
    expect((plus.dy - countRect.center.dy).abs(), lessThanOrEqualTo(2));
    final countField = tester.widget<FTextFormField>(
      find.byType(FTextFormField).last,
    );
    expect(countField.textAlignVertical, TextAlignVertical.center);
    expect(countField.textAlign, TextAlign.center);
    expect(
      (countRect.center.dy - weekUnit.center.dy).abs(),
      lessThanOrEqualTo(2),
      reason: 'count=$countRect weekUnit=$weekUnit',
    );
    for (final label in ['每周相同', '单双周交替']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.size.width,
        closeTo(paragraph.getMaxIntrinsicWidth(double.infinity), 0.5),
      );
      expect(tester.getSize(find.text(label)).height, lessThan(22));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('例外安排类型选项不逐字换行', (tester) async {
    final term = _term(id: 't1', title: '2026 秋季', weeks: 1);
    await tester.pumpWidget(
      _wrap(
        ExceptionEditorDialog(
          term: term,
          weekNumber: 1,
          existing: const <CalendarException>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in ['补课', '停课 / 节假日']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.size.width,
        closeTo(paragraph.getMaxIntrinsicWidth(double.infinity), 0.5),
      );
      expect(tester.getSize(find.text(label)).height, lessThan(22));
    }
    expect(tester.takeException(), isNull);
  });
}
