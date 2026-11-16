import 'package:class_set/app.dart';

import 'features/supervision/supervision_test_support.dart';

import 'package:class_set/features/workbench/workbench_page.dart';
import 'package:class_set/features/terms/term_page.dart';
import 'package:class_set/features/classes/classes_page.dart';
import 'package:class_set/features/routines/routine_page.dart';
import 'package:class_set/features/subjects/subjects_page.dart';
import 'package:class_set/features/teachers/teachers_page.dart';
import 'package:class_set/features/public_rooms/public_rooms_page.dart';

import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/database_provider.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('按扣除侧栏的内容宽度统一切换页面与顶部栏边距', (tester) async {
    tester.view.physicalSize = const Size(1123, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    await tester.runAsync(
      () => repository.saveTerm(
        AcademicTerm(
          id: 'gutter-term',
          title: '2026 秋季学期',
          academicYear: '2026',
          semesterLabel: '秋季',
          firstTeachingWeekStart: DateTime(2026, 9, 1),
          teachingWeekCount: 20,
          createdAt: DateTime(2026),
        ),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        schoolRepositoryProvider.overrideWithValue(repository),
        activeTermIdProvider.overrideWith((ref) => 'gutter-term'),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClassSetApp(databasePath: 'preview.sqlite'),
      ),
    );
    await tester.pumpAndSettle();
    for (final (windowWidth, inset) in [(1123.0, 16.0), (1124.0, 32.0)]) {
      tester.view.physicalSize = Size(windowWidth, 900);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('先把新学期的基础搭起来')).dx - 244, inset);
      final toggle = find.byWidgetPredicate(
        (w) => w is AppIconButton && w.tooltip == '收起侧边栏',
      );
      expect(tester.getTopLeft(toggle).dx - 244, inset);
      expect(
        tester.getTopLeft(find.byTooltip('编辑学校名称')).dx,
        inset == 16 ? 12 : 16,
      );
      for (final (section, pageType) in [
        (AppSection.workbench, WorkbenchPage),
        (AppSection.terms, TermPage),
        (AppSection.classes, ClassesPage),
        (AppSection.routines, RoutinePage),
        (AppSection.subjects, SubjectsPage),
        (AppSection.teachers, TeachersPage),
        (AppSection.publicRooms, PublicRoomsPage),
      ]) {
        container.read(selectedSectionProvider.notifier).state = section;
        await tester.pumpAndSettle();
        final firstInset = tester.widget(
          find
              .descendant(
                of: find.byType(pageType),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Padding ||
                      w is SingleChildScrollView ||
                      w is BoxScrollView,
                ),
              )
              .first,
        );
        final EdgeInsetsGeometry? geometry = switch (firstInset) {
          Padding widget => widget.padding,
          SingleChildScrollView widget => widget.padding,
          BoxScrollView widget => widget.padding,
          _ => null,
        };
        final edges = geometry!.resolve(TextDirection.ltr);
        expect(edges.left, inset, reason: '$section left');
        expect(edges.right, inset, reason: '$section right');
        expect(edges.top, 16, reason: '$section top');
        expect(tester.takeException(), isNull, reason: '$section');
      }
      container.read(selectedSectionProvider.notifier).state =
          AppSection.workbench;
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('带班页头与主体在统一断点收放', (tester) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    await tester.runAsync(() => repository.saveTerm(supervisionTerm));
    await openSupervision(tester, repository);
    for (final (width, gutter) in [(879.0, 16.0), (880.0, 32.0)]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpAndSettle();
      final header = tester.getRect(find.byType(AppPageHeader));
      expect(header.left, gutter);
      expect(width - header.right, gutter);
      expect(header.top, 16);
      expect(tester.takeException(), isNull);
    }
  });
}
