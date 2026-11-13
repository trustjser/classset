import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'supervision_test_support.dart';

void main() {
  testWidgets('创建岗位人员设置同行，班级范围填满工作区，底部统计居中', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    await tester.runAsync(() => repository.saveTerm(supervisionTerm));
    await openSupervision(tester, repository);
    await tester.tap(find.text('创建岗位'));
    await tester.pumpAndSettle();
    final kind = tester.getRect(find.byType(AppSelectField<SupervisionKind>));
    final personnel = tester.getRect(find.text('人员设置'));
    expect((kind.center.dy - personnel.center.dy).abs(), lessThan(8));
    final scope = tester.getRect(find.widgetWithText(AppSectionPanel, '班级范围'));
    expect(scope.bottom, greaterThan(tester.getRect(find.text('实际合班')).bottom));
    final summary = tester.getRect(find.text('将创建 0 个岗位 · 0 个课格'));
    final submit = tester.getRect(
      find.widgetWithText(AppPrimaryButton, '添加岗位'),
    );
    expect((summary.center.dy - submit.center.dy).abs(), lessThan(2));
    for (final width in [768.0, 390.0]) {
      tester.view.physicalSize = Size(width, 760);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('实际合班'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('实际合班')).center.dy, lessThan(760));
      final action = tester.getRect(
        find.widgetWithText(AppPrimaryButton, '添加岗位'),
      );
      expect(action.bottom, lessThan(760));
      expect(tester.takeException(), isNull);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('放大字体后作息信息卡可容纳完整内容', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    await tester.runAsync(() async {
      await repository.saveTerm(supervisionTerm);
      await repository.saveSupervisionDraft(
        supervisionDraft,
        expectedRevision: 0,
      );
    });
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openSupervision(tester, repository);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面页头紧凑同行，操作栏固定于工作区底部', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    await tester.runAsync(() async {
      await repository.saveTerm(supervisionTerm);
      await repository.saveSupervisionDraft(
        supervisionDraft,
        expectedRevision: 0,
      );
    });
    await openSupervision(tester, repository);
    final title = tester.getRect(find.text('带班安排'));
    final subtitle = tester.getRect(find.text('为课后时段安排带班教师，与课表协调后生效'));
    expect((title.center.dy - subtitle.center.dy).abs(), lessThan(8));
    expect(subtitle.left, greaterThan(title.right));
    expect(tester.getRect(find.text('预览并确认')).bottom, greaterThan(960));
  });

  testWidgets('窄窗口保留周网格，可滚动并打开周日岗位', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    await tester.runAsync(() async {
      await repository.saveTerm(supervisionTerm);
      await repository.saveSupervisionDraft(
        supervisionDraft,
        expectedRevision: 0,
      );
    });
    await openSupervision(tester, repository);
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    expect(find.text('节次 / 时间'), findsOneWidget);
    final merged = find.byKey(const ValueKey('duty-post-merged'));
    await tester.ensureVisible(merged);
    await tester.pumpAndSettle();
    expect(tester.getRect(merged).width, greaterThanOrEqualTo(116));
    await tester.tap(merged);
    await tester.pumpAndSettle();
    expect(find.text('选择带班教师'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
