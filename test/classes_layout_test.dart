import 'package:class_set/app.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/features/classes/classes_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repository;
  late ProviderContainer container;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftSchoolRepository(database);
    container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
    );
    await repository.saveTerm(
      AcademicTerm(
        id: 'layout',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    final first = (await repository.watchStages('layout').first).single;
    await repository.saveStage(
      const SchoolStage(
        id: 'second',
        termId: 'layout',
        name: '初中部',
        sortOrder: 1,
      ),
    );
    for (final (id, stageId, name, order) in [
      ('g1', first.id, '一年级', 0),
      ('g2', 'second', '初一', 0),
      ('g3', 'second', '初二', 1),
    ]) {
      await repository.saveGrade(
        GradeGroup(id: id, stageId: stageId, name: name, sortOrder: order),
      );
      for (var index = 1; index <= 2; index++) {
        await repository.saveClass(
          ClassGroup(
            id: '${id}_$index',
            gradeId: id,
            name: '$name（$index）班',
            sortOrder: index,
          ),
        );
      }
    }
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(selectedSectionProvider.notifier).state = AppSection.classes;
    container.read(activeTermIdProvider.notifier).state = 'layout';
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClassSetApp(databasePath: 'school.sqlite'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect dialogContentRect(WidgetTester tester) => tester.getRect(
    find.descendant(
      of: find.byType(AppDialog),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Material && widget.type == MaterialType.transparency,
      ),
    ),
  );

  testWidgets('桌面页面和弹窗遵循设计稿的布局位置', (tester) async {
    await pumpApp(tester, const Size(1440, 900));

    final page = tester.getRect(find.byType(ClassesPage));
    expect(page.left, 220);
    expect(page.top, 56);
    expect(page.height, 844);
    final addStage = tester.getRect(find.byKey(const Key('add-stage-card')));
    expect(addStage.left, closeTo(1252, 2));
    expect(addStage.top, closeTo(130, 2));
    expect(addStage.height, closeTo(104, 2));
    expect(tester.getTopLeft(find.text('学段结构')).dy, closeTo(90, 5));

    await tester.tap(find.byKey(const Key('add-stage-card')));
    await tester.pumpAndSettle();
    var dialog = dialogContentRect(tester);
    expect(dialog.left, closeTo(982, 3));
    expect(dialog.top, closeTo(262, 3));
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑').first);
    await tester.pumpAndSettle();
    dialog = dialogContentRect(tester);
    expect(dialog.left, closeTo(532, 3));
    expect(dialog.top, closeTo(262, 3));
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('批量填充名称').first);
    await tester.pumpAndSettle();
    dialog = dialogContentRect(tester);
    expect(dialog.left, closeTo(284, 3));
    expect(dialog.top, closeTo(194, 3));
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除').at(2));
    await tester.pumpAndSettle();
    dialog = dialogContentRect(tester);
    expect(dialog.left, closeTo(522, 3));
    expect(dialog.top, closeTo(272, 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧凑桌面窗口中页面不溢出', (tester) async {
    await pumpApp(tester, const Size(800, 600));
    final page = tester.getRect(find.byType(ClassesPage));
    expect(page.left, 68);
    expect(page.top, 56);
    expect(tester.takeException(), isNull);
  });
}
