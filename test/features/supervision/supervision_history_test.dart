import 'package:class_set/core/navigation/draft_navigation_guard.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:class_set/domain/models/supervision.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

import 'supervision_test_support.dart';

void main() {
  testWidgets('批量移除一步撤销重做，保存后沿用最新 revision 且脏状态正确', (tester) async {
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
    final container = await openSupervision(tester, repository);
    final guard = container.read(draftNavigationGuardProvider);
    expect(_enabled(tester, 'undo'), isFalse);
    expect(_enabled(tester, 'redo'), isFalse);
    final a = tester.getRect(find.byKey(const ValueKey('duty-post-a')));
    final b = tester.getRect(find.byKey(const ValueKey('duty-post-b')));
    await mouseSelectSupervision(
      tester,
      a.topLeft + const Offset(8, 8),
      b.bottomRight - const Offset(8, 8),
    );
    await tester.tap(find.text('批量移除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除 2 个岗位'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('duty-post-a')), findsNothing);
    expect(guard.hasChangesFor('supervision:t'), isTrue);
    await _history(tester, 'undo');
    expect(find.byKey(const ValueKey('duty-post-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('duty-post-b')), findsOneWidget);
    expect(guard.hasChangesFor('supervision:t'), isFalse);
    await _history(tester, 'redo');
    final removed = await saveSupervisionFromUi(tester, repository);
    expect(removed.posts.map((p) => p.id), ['c', 'merged']);
    expect(guard.hasChangesFor('supervision:t'), isFalse);
    await _history(tester, 'undo');
    expect(guard.hasChangesFor('supervision:t'), isTrue);
    final restored = await saveSupervisionFromUi(tester, repository);
    expect(restored.revision, greaterThan(removed.revision));
    expect(restored.assignments, supervisionDraft.assignments);
    expect(restored.manualPostIds, supervisionDraft.manualPostIds);
    await _history(tester, 'redo');
    final removedAgain = await saveSupervisionFromUi(tester, repository);
    expect(removedAgain.revision, greaterThan(restored.revision));
    expect(removedAgain.posts.map((p) => p.id), ['c', 'merged']);
    await _history(tester, 'undo');
    await tester.tap(find.text('人员匹配'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('均衡优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(_enabled(tester, 'redo'), isFalse);
    final changed = await saveSupervisionFromUi(tester, repository);
    expect(changed.posts, hasLength(4));
    expect(changed.matchingPreferences.mode, SupervisionMatchMode.balanceFirst);
  });

  testWidgets('候选池与岗位设置逐步恢复，未改变内容的应用保留重做', (tester) async {
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
    final container = await openSupervision(tester, repository);
    final guard = container.read(draftNavigationGuardProvider);
    await tester.tap(find.text('人员匹配'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('均衡优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('duty-post-a')));
    await tester.pumpAndSettle();
    await openPostPersonnelSettings(tester);
    await tester.tap(find.byKey(const ValueKey('post-target-math')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    await closeTeacherDrawer(tester);
    await tester.tap(find.byKey(const ValueKey('duty-pool-manager')));
    await _waitForPool(tester);
    final row = find.widgetWithText(f.FItem, '张老师');
    await tester.tap(
      find.descendant(of: row, matching: find.byType(AppCheckbox)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await _history(tester, 'undo');
    }
    expect(_enabled(tester, 'undo'), isFalse);
    expect(guard.hasChangesFor('supervision:t'), isFalse);
    await tester.tap(find.text('人员匹配'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(_enabled(tester, 'redo'), isTrue);
    expect(_enabled(tester, 'undo'), isFalse);
    for (var i = 0; i < 3; i++) {
      await _history(tester, 'redo');
    }
    final saved = await saveSupervisionFromUi(tester, repository);
    expect(saved.matchingPreferences.mode, SupervisionMatchMode.balanceFirst);
    expect(saved.posts.first.targetSubjectIds, {'math'});
    expect(saved.teacherIds, {'second'});
    expect(saved.assignments, supervisionDraft.assignments);
  });
  testWidgets('快捷键支持两种平台，输入框和弹窗不触发页面历史', (tester) async {
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
    final container = await openSupervision(tester, repository);
    final guard = container.read(draftNavigationGuardProvider);
    await _changeMatching(tester, '均衡优先');
    await tester.tap(find.byKey(const ValueKey('duty-post-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(AppTextFormField), '张');
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    expect(guard.hasChangesFor('supervision:t'), isTrue);
    expect(_enabled(tester, 'redo'), isFalse);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is AppIconButton && w.tooltip == '关闭教师面板',
      ),
    );
    await tester.pumpAndSettle();
    final a = tester.getRect(find.byKey(const ValueKey('duty-post-a')));
    await mouseSelectSupervision(
      tester,
      a.topLeft + const Offset(8, 8),
      a.bottomRight - const Offset(8, 8),
    );
    await _shortcut(tester, LogicalKeyboardKey.keyZ, meta: true);
    expect(guard.hasChangesFor('supervision:t'), isFalse);
    await _shortcut(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(guard.hasChangesFor('supervision:t'), isTrue);
    await _shortcut(tester, LogicalKeyboardKey.keyZ);
    await _shortcut(tester, LogicalKeyboardKey.keyY);
    expect(guard.hasChangesFor('supervision:t'), isTrue);
    await tester.tap(find.text('人员匹配'));
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyZ, meta: true);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    final saved = await saveSupervisionFromUi(tester, repository);
    expect(saved.matchingPreferences.mode, SupervisionMatchMode.balanceFirst);
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('创建指派清除和智能补齐各为一步，运行匹配时禁用历史', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    await tester.runAsync(() async {
      await repository.saveTerm(supervisionTerm);
      await repository.saveSupervisionDraft(
        supervisionDraft.copyWith(
          posts: [],
          assignments: {},
          manualPostIds: {},
        ),
        expectedRevision: 0,
      );
    });
    final container = await openSupervision(tester, repository);
    await tester.tap(find.text('创建岗位'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-scope-class-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-slot-1-service-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加岗位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待安排'));
    await tester.pumpAndSettle();
    await pickTeacherInPanel(tester, '张老师');
    await clearAssignmentInPanel(tester);
    await closeTeacherDrawer(tester);
    await tester.tap(find.text('智能补齐'));
    await tester.pump();
    expect(_enabled(tester, 'undo'), isFalse);
    await _pumpUntil(tester, () => find.text('取消补齐').evaluate().isEmpty);
    for (var i = 0; i < 4; i++) {
      await _history(tester, 'undo');
    }
    expect(find.text('周表还是空的。创建岗位后，即可按节次安排老师。'), findsOneWidget);
    expect(
      container
          .read(draftNavigationGuardProvider)
          .hasChangesFor('supervision:t'),
      isFalse,
    );
    for (var i = 0; i < 4; i++) {
      await _history(tester, 'redo');
    }
    final saved = await saveSupervisionFromUi(tester, repository);
    expect(saved.posts, hasLength(1));
    expect(saved.assignments.values, ['teacher']);
    expect(saved.manualPostIds, isEmpty);
  });

  testWidgets('成功发布清空历史，历史版本只读，重新编辑不会撤销正式方案', (tester) async {
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
    await _changeMatching(tester, '均衡优先');
    await tester.tap(find.text('预览并确认'));
    await tester.pump();
    await _pumpUntil(tester, () {
      final button = find.widgetWithText(AppPrimaryButton, '确认生效');
      return button.evaluate().isNotEmpty &&
          tester.widget<AppPrimaryButton>(button).onPressed != null;
    });
    expect(_enabled(tester, 'undo'), isFalse);
    await tester.tap(find.text('确认生效'));
    await tester.pump();
    await _pumpUntil(
      tester,
      () =>
          find.text('创建岗位').evaluate().isEmpty &&
          find.text('确认生效').evaluate().isEmpty,
    );
    expect(_enabled(tester, 'undo'), isFalse);
    expect(_enabled(tester, 'redo'), isFalse);
    await tester.tap(find.byType(AppSelectField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑草稿').last);
    await tester.pumpAndSettle();
    expect(_enabled(tester, 'undo'), isFalse);
    await _changeMatching(tester, '匹配优先');
    await _history(tester, 'undo');
    final published = (await tester.runAsync(
      () => repository.watchSupervisionVersions('t').first,
    ))!;
    expect(
      published.single.draft.matchingPreferences.mode,
      SupervisionMatchMode.balanceFirst,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    var readsComplete = false;
    Future.wait(repository.baselineLoads).then((_) => readsComplete = true);
    await _pumpUntil(tester, () => readsComplete);
  });

  testWidgets('接收外部保存的新草稿后清空旧历史', (tester) async {
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
    final container = await openSupervision(tester, repository);
    await _changeMatching(tester, '均衡优先');
    final saved = await saveSupervisionFromUi(tester, repository);
    expect(_enabled(tester, 'undo'), isTrue);
    await tester.runAsync(
      () => repository.saveSupervisionDraft(
        saved.copyWith(
          posts: saved.posts.skip(1).toList(),
          assignments: {...saved.assignments}..remove('a'),
          manualPostIds: {...saved.manualPostIds}..remove('a'),
        ),
        expectedRevision: saved.revision,
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byKey(const ValueKey('duty-post-a')).evaluate().isEmpty,
    );
    expect(_enabled(tester, 'undo'), isFalse);
    expect(_enabled(tester, 'redo'), isFalse);
    expect(
      container
          .read(draftNavigationGuardProvider)
          .hasChangesFor('supervision:t'),
      isFalse,
    );
  });
  testWidgets('本地脏草稿延后接收外部更新，撤销变干净后采用新版本并可再次保存', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    late SupervisionDraft original;
    await tester.runAsync(() async {
      await repository.saveTerm(supervisionTerm);
      original = await repository.saveSupervisionDraft(
        supervisionDraft,
        expectedRevision: 0,
      );
    });
    final container = await openSupervision(tester, repository);
    await _changeMatching(tester, '均衡优先');
    final external = await tester.runAsync(
      () => repository.saveSupervisionDraft(
        original.copyWith(
          posts: original.posts.skip(1).toList(),
          assignments: {...original.assignments}..remove('a'),
          manualPostIds: {...original.manualPostIds}..remove('a'),
        ),
        expectedRevision: original.revision,
      ),
    );
    await tester.runAsync(() => repository.watchSupervisionDraft('t').first);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('duty-post-a')), findsOneWidget);
    await _history(tester, 'undo');
    expect(find.byKey(const ValueKey('duty-post-a')), findsNothing);
    expect(_enabled(tester, 'redo'), isFalse);
    expect(
      container
          .read(draftNavigationGuardProvider)
          .hasChangesFor('supervision:t'),
      isFalse,
    );
    await _changeMatching(tester, '均衡优先');
    final saved = await saveSupervisionFromUi(tester, repository);
    expect(saved.revision, greaterThan(external!.revision));
    expect(saved.posts, hasLength(3));
  });
  testWidgets('历史按钮可用时为蓝色，悬停显示操作和快捷键提示', (tester) async {
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
    final undo = find.byKey(const ValueKey('duty-undo'));
    final redo = find.byKey(const ValueKey('duty-redo'));
    final colors = Theme.of(tester.element(undo)).extension<AppThemeColors>()!;
    Color? iconColor(Finder button) => tester
        .widget<Icon>(
          find.descendant(of: button, matching: find.byType(Icon)).first,
        )
        .color;
    expect(iconColor(undo), colors.muted);
    await _changeMatching(tester, '均衡优先');
    expect(iconColor(undo), colors.blue);
    expect(iconColor(redo), colors.muted);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(undo));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('撤销：调整人员匹配 · Cmd/Ctrl+Z'), findsOneWidget);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    await _history(tester, 'undo');
    expect(iconColor(undo), colors.muted);
    expect(iconColor(redo), colors.blue);
    await mouse.moveTo(tester.getCenter(redo));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('重做：调整人员匹配 · Cmd/Ctrl+Shift+Z / Ctrl+Y'), findsOneWidget);
    await mouse.moveTo(const Offset(1, 1));
    await mouse.removePointer();
    await tester.pumpAndSettle();
  });
}

bool _enabled(WidgetTester tester, String action) =>
    tester
        .widget<AppIconButton>(find.byKey(ValueKey('duty-$action')))
        .onPressed !=
    null;
Future<void> _history(WidgetTester tester, String action) async {
  await tester.tap(find.byKey(ValueKey('duty-$action')));
  await tester.pumpAndSettle();
}

Future<void> _waitForPool(WidgetTester tester) async {
  for (var i = 0; i < 30 && find.text('新建候选池').evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool shift = false,
}) async {
  final modifier = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _changeMatching(WidgetTester tester, String mode) async {
  await tester.tap(find.text('人员匹配'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode));
  await tester.pumpAndSettle();
  await tester.tap(find.text('应用'));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  expect(done(), isTrue);
}
