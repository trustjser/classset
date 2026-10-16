import 'package:class_set/app.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/features/routines/routine_page.dart';
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
        id: 'routine-layout',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    final stage = (await repository.watchStages('routine-layout').first).single;
    await repository.saveGrade(
      GradeGroup(id: 'grade-1', stageId: stage.id, name: '一年级', sortOrder: 0),
    );
    await repository.saveClass(
      const ClassGroup(
        id: 'class-1',
        gradeId: 'grade-1',
        name: '一年级（1）班',
        sortOrder: 0,
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> pumpPage(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(selectedSectionProvider.notifier).state =
        AppSection.routines;
    container.read(activeTermIdProvider.notifier).state = 'routine-layout';
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClassSetApp(databasePath: 'school.sqlite'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('作息设置桌面布局与紧凑窗口均无溢出', (tester) async {
    await pumpPage(tester, const Size(1440, 900));
    expect(find.byType(RoutinePage), findsOneWidget);
    expect(find.text('免任课范围'), findsOneWidget);
    expect(find.text('节次与时间'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byKey(const ValueKey('routine-page-snapshot')),
      matchesGoldenFile('goldens/routine_page.png'),
    );
  });

  testWidgets('作息设置紧凑桌面窗口不溢出', (tester) async {
    await pumpPage(tester, const Size(800, 600));
    expect(find.byType(RoutinePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
