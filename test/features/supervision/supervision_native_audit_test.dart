import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:class_set/domain/models/supervision.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

import 'supervision_test_support.dart';

void main() {
  testWidgets('班级和教师当天视角只显示当天存在的节次列', (tester) async {
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
    await tester.tap(find.text('按班级'));
    await tester.pumpAndSettle();
    expect(find.text('晚上 · 第 2–3 节'), findsNothing);
    expect(find.text('课后服务 · 第 1 节'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duty-day-7')));
    await tester.pumpAndSettle();
    expect(find.text('晚上 · 第 2–3 节'), findsOneWidget);
    await tester.tap(find.text('按教师'));
    await tester.pumpAndSettle();
    expect(find.text('晚上 · 第 2–3 节'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duty-day-1')));
    await tester.pumpAndSettle();
    expect(find.text('晚上 · 第 2–3 节'), findsNothing);
  });
  testWidgets('创建岗位禁用已有覆盖课格，切换班级后仍允许空闲课格', (tester) async {
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
    await tester.tap(find.text('创建岗位'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-scope-class-c1')));
    await tester.pumpAndSettle();
    final occupied = find.byKey(const ValueKey('post-slot-1-service-1'));
    expect(tester.widget<f.FTappable>(occupied).onPress, isNull);
    expect(
      find.descendant(of: occupied, matching: find.text('已有岗位')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('post-scope-class-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-scope-class-c2')));
    await tester.pumpAndSettle();
    expect(tester.widget<f.FTappable>(occupied).onPress, isNotNull);
    expect(
      tester
          .widget<f.FTappable>(
            find.byKey(const ValueKey('post-slot-7-evening-2')),
          )
          .onPress,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('post-scope-class-c1')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: occupied, matching: find.text('含已有岗位')),
      findsOneWidget,
    );
  });
  testWidgets('教师池搜索空结果有说明，可一键清空并恢复名单', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    await tester.runAsync(() => repository.saveTerm(supervisionTerm));
    await openSupervision(tester, repository);
    await tester.tap(find.byKey(const ValueKey('duty-pool-manager')));
    for (var i = 0; i < 30 && find.text('新建候选池').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppTextFormField), '无此教师');
    await tester.pumpAndSettle();
    expect(find.text('没有找到教师'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is AppIconButton && w.tooltip == '清空教师搜索',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(f.FItem, '张老师'), findsOneWidget);
    expect(find.widgetWithText(f.FItem, '李老师'), findsOneWidget);
    expect(
      tester
          .widget<AppTextFormField>(find.byType(AppTextFormField))
          .controller!
          .text,
      isEmpty,
    );
  });
  testWidgets('创建岗位校验错误固定可见，不隐藏在作息滚动区底部', (tester) async {
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
    await tester.tap(find.byType(AppSelectField<SupervisionKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-scope-class-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-slot-1-service-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加岗位'));
    await tester.pumpAndSettle();
    expect(find.text('请输入活动名称。'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('请输入活动名称。')).dy,
      lessThan(tester.getTopLeft(find.text('活动类型')).dy),
    );
  });
  testWidgets('新建候选池名称为空时显示明确校验说明', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    await tester.runAsync(() => repository.saveTerm(supervisionTerm));
    await openSupervision(tester, repository);
    await tester.tap(find.byKey(const ValueKey('duty-pool-manager')));
    for (var i = 0; i < 30 && find.text('新建候选池').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建候选池'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('请输入候选池名称'), findsOneWidget);
  });
}
