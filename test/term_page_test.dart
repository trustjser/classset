import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/features/terms/term_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Widget _wrap(
  Widget child,
  ProviderContainer container, {
  TargetPlatform? platform,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: platform == null
        ? AppTheme.light
        : AppTheme.light.copyWith(platform: platform),
    builder: (context, child) => FTheme(
      data: AppTheme.forui,
      child: FToaster(child: child!),
    ),
    home: Scaffold(body: child),
  ),
);

AcademicTerm _term(String id, String title, DateTime date) => AcademicTerm(
  id: id,
  title: title,
  academicYear: '2026-2027',
  semesterLabel: '秋季学期',
  firstTeachingWeekStart: date,
  teachingWeekCount: 8,
  createdAt: date.subtract(const Duration(days: 20)),
);

void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repository;
  late ProviderContainer container;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftSchoolRepository(database);
    container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  testWidgets('空状态能进入新建学期表单', (tester) async {
    await tester.pumpWidget(
      _wrap(const TermPage(databasePath: 'school.sqlite'), container),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有学期资料'), findsOneWidget);
    await tester.tap(find.text('新建第一个学期'));
    await tester.pumpAndSettle();
    expect(find.text('新建学期'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('仅点击学期列表的切换 Radio 才切换当前学期', (tester) async {
    await repository.saveTerm(_term('t1', '2026 秋季学期', DateTime(2026, 9, 1)));
    await repository.saveTerm(_term('t2', '2027 春季学期', DateTime(2027, 2, 1)));
    container.read(activeTermIdProvider.notifier).state = 't1';
    await tester.pumpWidget(
      _wrap(const TermPage(databasePath: 'school.sqlite'), container),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('所有学期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2027 春季学期').last);
    await tester.pumpAndSettle();
    expect(container.read(activeTermIdProvider), 't1');
    expect(find.text('所有学期'), findsOneWidget);

    final targetRadio = find.byWidgetPredicate(
      (widget) => widget is AppRadioIndicator<String> && widget.value == 't2',
    );
    expect(targetRadio, findsOneWidget);
    await tester.tap(targetRadio);
    await tester.pumpAndSettle();

    expect(container.read(activeTermIdProvider), 't2');
    expect(find.text('第 1 周'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄而矮的窗口下学期页面可纵向和横向滚动而不溢出', (tester) async {
    tester.view.physicalSize = const Size(700, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await repository.saveTerm(_term('t1', '2026 秋季学期', DateTime(2026, 9, 1)));
    container.read(activeTermIdProvider.notifier).state = 't1';

    await tester.pumpWidget(
      _wrap(
        const TermPage(databasePath: 'school.sqlite'),
        container,
        platform: TargetPlatform.macOS,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsWidgets);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认后删除非当前学期', (tester) async {
    await repository.saveTerm(_term('t1', '当前秋季学期', DateTime(2026, 9, 1)));
    await repository.saveTerm(_term('t2', '历史春季学期', DateTime(2027, 2, 1)));
    container.read(activeTermIdProvider.notifier).state = 't1';
    await tester.pumpWidget(
      _wrap(const TermPage(databasePath: 'school.sqlite'), container),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('所有学期'));
    await tester.pumpAndSettle();
    final deleteAction = find.byTooltip('删除学期');
    await tester.ensureVisible(deleteAction);
    await tester.pumpAndSettle();
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();
    expect(find.textContaining('确认删除「历史春季学期」'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(await database.select(database.academicTerms).get(), hasLength(1));
    expect(find.text('历史春季学期'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('删除数据库错误会显示提示', (tester) async {
    await repository.saveTerm(_term('t1', '当前秋季学期', DateTime(2026, 9, 1)));
    await repository.saveTerm(_term('t2', '历史春季学期', DateTime(2027, 2, 1)));
    container.read(activeTermIdProvider.notifier).state = 't1';
    await database.customStatement(
      "CREATE TRIGGER reject_term_delete BEFORE DELETE ON academic_terms "
      "WHEN OLD.id = 't2' BEGIN SELECT RAISE(ABORT, 'rejected'); END",
    );
    await tester.pumpWidget(
      _wrap(const TermPage(databasePath: 'school.sqlite'), container),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('所有学期'));
    await tester.pumpAndSettle();
    final deleteAction = find.byTooltip('删除学期');
    await tester.ensureVisible(deleteAction);
    await tester.pumpAndSettle();
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('删除学期失败'), findsOneWidget);
    expect(await database.select(database.academicTerms).get(), hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
