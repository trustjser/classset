import 'package:class_set/app.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/features/school/school_name_dialog.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('切换学期会保存，学校名称可编辑且可清空', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    await tester.runAsync(() async {
      for (final (id, title, date) in [
        ('old', '2026 学年 · 秋季学期', DateTime(2026, 9, 1)),
        ('new', '2027 学年 · 春季学期', DateTime(2027, 3, 1)),
      ]) {
        await repository.saveTerm(
          AcademicTerm(
            id: id,
            title: title,
            academicYear: id == 'old' ? '2026' : '2027',
            semesterLabel: id == 'old' ? '秋季学期' : '春季学期',
            firstTeachingWeekStart: date,
            teachingWeekCount: 20,
            createdAt: date,
          ),
        );
      }
    });

    final container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClassSetApp(databasePath: 'school.sqlite'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未命名学校'), findsOneWidget);
    await tester.tap(find.text('未命名学校'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(SchoolNameDialog),
        matching: find.byType(AppTextFormField),
      ),
      '青木实验学校',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(SchoolNameDialog),
        matching: find.text('保存'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('青木实验学校'), findsOneWidget);
    expect(
      await tester.runAsync(() => repository.watchSchoolName().first),
      '青木实验学校',
    );

    await tester.tap(
      find.descendant(
        of: find.byType(AppMenuButton).first,
        matching: find.text('2027 学年 · 春季学期'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026 学年 · 秋季学期').last);
    await tester.pumpAndSettle();
    expect(container.read(activeTermIdProvider), 'old');
    expect(await tester.runAsync(repository.loadActiveTermId), 'old');

    await tester.tap(find.text('青木实验学校').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(SchoolNameDialog),
        matching: find.byType(AppTextFormField),
      ),
      '  ',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(SchoolNameDialog),
        matching: find.text('保存'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('未命名学校'), findsOneWidget);
  });
}
