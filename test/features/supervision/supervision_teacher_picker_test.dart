import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'supervision_test_support.dart';

/// 所有窗口宽度共用同一个浮层面板；这里用窄窗口验证贴底形态。
Future<void> openTeacherPicker(WidgetTester tester) async {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final repository = TestSupervisionRepository(database, supervisionSnapshot());
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
  final merged = find.byKey(const ValueKey('duty-post-merged'));
  await tester.ensureVisible(merged);
  await tester.pumpAndSettle();
  await tester.tap(merged);
  await tester.pumpAndSettle();
}

Finder inPicker(Finder finder) => find.descendant(
  of: find.byKey(const ValueKey('duty-teacher-panel')),
  matching: finder,
);

void main() {
  testWidgets('浮层展示岗位上下文、候选池范围、分组与草稿状态', (tester) async {
    await openTeacherPicker(tester);

    expect(inPicker(find.text('选择带班教师')), findsOneWidget);
    expect(inPicker(find.text('带班岗位 · 人员指派')), findsOneWidget);
    expect(inPicker(find.text('阅读合班 · 晚自习')), findsOneWidget);
    expect(inPicker(find.text('周日')), findsOneWidget);
    expect(inPicker(find.text('合班 · 2 个班')), findsOneWidget);
    expect(inPicker(find.text('基础候选池')), findsOneWidget);
    expect(inPicker(find.text('管理 ›')), findsOneWidget);
    expect(inPicker(find.text('推荐与可安排')), findsOneWidget);
    expect(inPicker(find.text('当前指派：李老师 · 无需变更')), findsOneWidget);
    expect(inPicker(find.text('已是指派教师')), findsOneWidget);
    expect(inPicker(find.text('确认指派')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('清除指派与移除岗位各有一次确认，取消可恢复', (tester) async {
    await openTeacherPicker(tester);

    await tester.tap(inPicker(find.text('清除指派')));
    await tester.pumpAndSettle();
    expect(inPicker(find.text('将清除当前指派，岗位变为「待安排」')), findsOneWidget);
    expect(inPicker(find.text('确认清除')), findsOneWidget);

    // 未确认前浮层仍在，不会绕过确认直接落库。
    expect(inPicker(find.text('选择带班教师')), findsOneWidget);
    await tester.tap(inPicker(find.text('确认清除')));
    await tester.pumpAndSettle();
    // 确认后浮层保留，草稿状态行即时反馈（与设计稿一致）。
    expect(inPicker(find.text('当前指派：待安排 · 无需变更')), findsOneWidget);

    // 移除岗位收在 ⋯ 菜单里并需二次确认。
    await tester.tap(inPicker(find.byIcon(Icons.more_horiz)));
    await tester.pumpAndSettle();
    expect(find.text('移除岗位'), findsOneWidget);
    await tester.tap(find.text('移除岗位'));
    await tester.pumpAndSettle();
    expect(inPicker(find.text('移除后该岗位与指派将一并删除')), findsOneWidget);
    expect(inPicker(find.text('确认移除')), findsOneWidget);
    await tester.tap(inPicker(find.text('取消')));
    await tester.pumpAndSettle();
    expect(inPicker(find.text('确认移除')), findsNothing);
    expect(inPicker(find.text('当前指派：待安排 · 无需变更')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索无结果给出空态，清除筛选可恢复候选分组', (tester) async {
    await openTeacherPicker(tester);

    await tester.enterText(inPicker(find.byType(AppTextFormField)), '不存在的教师');
    await tester.pumpAndSettle();
    expect(inPicker(find.text('没有找到匹配的教师')), findsOneWidget);
    expect(inPicker(find.text('清除筛选')), findsOneWidget);
    expect(inPicker(find.text('推荐与可安排')), findsNothing);

    await tester.tap(inPicker(find.text('清除筛选')));
    await tester.pumpAndSettle();
    expect(inPicker(find.text('推荐与可安排')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
