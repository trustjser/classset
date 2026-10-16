import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/calendar_exception.dart';
import 'package:class_set/features/terms/term_page.dart';
import 'package:flutter/material.dart';
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
    home: Scaffold(body: Center(child: child)),
  ),
);

AcademicTerm _term() => AcademicTerm(
  id: 't1',
  title: '2026-2027 学年 · 秋季学期',
  academicYear: '2026-2027',
  semesterLabel: '秋季学期',
  firstTeachingWeekStart: DateTime(2026, 9, 1),
  teachingWeekCount: 20,
  createdAt: DateTime(2026, 8, 1),
);

void main() {
  testWidgets('编辑学期弹窗按设计显示名称、首周日期和周期选项', (tester) async {
    await tester.pumpWidget(_wrap(TermEditorDialog(term: _term())));
    await tester.pumpAndSettle();

    expect(_dialogPanelWidth(tester), 572);
    expect(find.text('编辑学期信息'), findsOneWidget);
    expect(find.text('学期名称'), findsOneWidget);
    expect(find.text('第 1 教学周起始'), findsOneWidget);
    expect(find.text('总周数'), findsOneWidget);
    expect(find.text('课表周期'), findsOneWidget);
    expect(find.text('单双周交替'), findsOneWidget);
    expect(find.text('秋季学期'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('学期表单输入、日期和单选均使用 Forui 组件', (tester) async {
    await tester.pumpWidget(_wrap(TermEditorDialog(term: _term())));
    await tester.pumpAndSettle();

    expect(find.byType(AppTextFormField), findsNWidgets(2));
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(FRadio), findsNWidgets(2));
    expect(
      find.byWidgetPredicate((widget) => widget is FDateField),
      findsOneWidget,
    );
  });

  testWidgets('弹窗内容超高时滚动而不溢出', (tester) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const TermEditorDialog()));
    await tester.pumpAndSettle();

    // 低窗口下弹窗内容可滚动：创建按钮仍可见，无溢出异常。
    expect(find.text('创建'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建学期校验名称、周数和首周日期', (tester) async {
    await tester.pumpWidget(_wrap(const TermEditorDialog()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('请选择第 1 教学周起始日期'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).last, '53');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1–52 之间的周数'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑单双周模式时保留更新后的模式', (tester) async {
    AcademicTerm? result;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final value = await showAppDialog<TermEditorResult>(
                context: context,
                builder: (context) => TermEditorDialog(term: _term()),
              );
              result = value?.term;
            },
            child: const Text('打开编辑'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('单双周交替'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周相同').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result?.cycleMode, AcademicTermCycle.everyWeek);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑学期时阻止例外日期落到学期范围之外', (tester) async {
    final outside = CalendarException(
      id: 'ex1',
      termId: 't1',
      date: DateTime(2026, 9, 9),
      kind: CalendarExceptionKind.holiday,
      makeupWeekday: null,
      makeupForDate: null,
      note: '',
    );
    await tester.pumpWidget(
      _wrap(TermEditorDialog(term: _term(), existingExceptions: [outside])),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).last, '1');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-09-09'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建学期提供复制上学期课表选项', (tester) async {
    await tester.pumpWidget(_wrap(TermEditorDialog(availableTerms: [_term()])));
    await tester.pumpAndSettle();

    await tester.tap(find.text('复制上学期课表（含教学日历）'));
    await tester.pumpAndSettle();

    expect(find.text('创建方式'), findsOneWidget);
    expect(find.text('复制上学期课表（含教学日历）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('补课编辑显示补课日期和原课日期映射字段', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExceptionEditorDialog(
          term: _term(),
          weekNumber: 1,
          existing: const <CalendarException>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_dialogPanelWidth(tester), 496);
    expect(find.text('09/01（周二）'), findsOneWidget);
    expect(find.text('选择被补的原课日期'), findsOneWidget);
    expect(find.text('执行课表'), findsOneWidget);
    final options = tester
        .widgetList<AppRadioOption<CalendarExceptionKind>>(
          find.byType(AppRadioOption<CalendarExceptionKind>),
        )
        .toList();
    expect(options, hasLength(2));
    expect(options.map((option) => option.compact), everyElement(isFalse));
    expect(options.map((option) => option.indicatorSize), everyElement(16));
    expect(options.map((option) => option.fontSize), everyElement(13));
    final dateFields = tester.widgetList<AppDateField>(
      find.byType(AppDateField),
    );
    expect(dateFields, hasLength(2));
    expect(dateFields.map((field) => field.height), everyElement(35));
    expect(tester.takeException(), isNull);
  });

  testWidgets('停课备注使用项目标准 Forui 输入组件', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExceptionEditorDialog(
          term: _term(),
          weekNumber: 1,
          existing: const <CalendarException>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FRadio).last);
    await tester.pumpAndSettle();

    final noteField = tester.widget<AppTextFormField>(
      find.byType(AppTextFormField),
    );
    expect(noteField.dense, isFalse);
    expect(noteField.controller, isNotNull);
    final dateFields = tester.widgetList<AppDateField>(
      find.byType(AppDateField),
    );
    expect(dateFields, hasLength(2));
    expect(dateFields.map((field) => field.height), everyElement(35));
    expect(tester.takeException(), isNull);
  });

  testWidgets('停课日期控件文字在按钮内垂直居中', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExceptionEditorDialog(
          term: _term(),
          weekNumber: 1,
          existing: const <CalendarException>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FRadio).last);
    await tester.pumpAndSettle();

    final field = find.byType(AppDateField).first;
    final dateField = find.byWidgetPredicate((widget) => widget is FDateField);
    final editableText = find.byType(EditableText).first;
    final fieldRect = tester.getRect(
      find.ancestor(of: dateField, matching: find.byType(SizedBox)).first,
    );
    final textRect = tester.getRect(editableText);
    expect(
      (fieldRect.center.dy - textRect.center.dy).abs(),
      lessThanOrEqualTo(0.5),
    );
    expect(tester.getSize(field).height, 35);
    expect(tester.getSize(editableText).height, lessThan(20));
    expect(field, findsOneWidget);
  });
}

double _dialogPanelWidth(WidgetTester tester) => tester
    .getSize(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material && widget.type == MaterialType.transparency,
      ),
    )
    .width;
