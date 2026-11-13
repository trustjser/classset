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
  testWidgets('命名候选池与人员匹配可设置、保存重开，岗位可单独覆盖', (tester) async {
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
    await tester.enterText(
      find.widgetWithText(AppTextFormField, '候选池名称'),
      '晚自习教师',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    final teacher = find.widgetWithText(f.FItem, '张老师');
    await tester.tap(
      find.descendant(of: teacher, matching: find.byType(AppCheckbox)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设为默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('人员匹配'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('均衡优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('满足全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    final saved = await saveSupervisionFromUi(tester, repository);
    expect(saved.teacherPools.single.name, '晚自习教师');
    expect(saved.teacherPools.single.teacherIds, {'teacher'});
    expect(saved.defaultTeacherPoolId, saved.teacherPools.single.id);
    expect(saved.matchingPreferences.mode, SupervisionMatchMode.balanceFirst);
    expect(
      saved.matchingPreferences.requirement,
      SupervisionMatchRequirement.all,
    );
    expect(saved.assignments, supervisionDraft.assignments);
    await tester.pumpWidget(const SizedBox.shrink());
    await openSupervision(tester, repository);
    await tester.tap(find.byKey(const ValueKey('duty-post-a')));
    await tester.pumpAndSettle();
    expect(find.textContaining('晚自习教师'), findsWidgets);
    await openPostPersonnelSettings(tester);
    await tester.tap(find.text('单独设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不启用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('匹配优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    final next = await saveSupervisionFromUi(tester, repository);
    expect(
      next.posts
          .firstWhere((p) => p.id == 'a')
          .matchingPreferences
          ?.requirement,
      SupervisionMatchRequirement.none,
    );
    expect(
      next.posts.firstWhere((p) => p.id == 'b').matchingPreferences,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('框选批量设置独立候选池、顺序偏好与目标学科，取消不改草稿', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    final original = supervisionDraft.copyWith(
      teacherPools: const [
        SupervisionTeacherPool(id: 'p', name: '李老师池', teacherIds: {'second'}),
      ],
    );
    await tester.runAsync(() async {
      await repository.saveTerm(supervisionTerm);
      await repository.saveSupervisionDraft(original, expectedRevision: 0);
    });
    await openSupervision(tester, repository);
    final first = tester.getRect(find.byKey(const ValueKey('duty-post-a')));
    final last = tester.getRect(find.byKey(const ValueKey('duty-post-b')));
    await mouseSelectSupervision(
      tester,
      first.topLeft + const Offset(8, 8),
      last.bottomRight - const Offset(8, 8),
    );
    expect(find.text('已选 2 个岗位'), findsOneWidget);
    Future<void> setPool({required bool cancel}) async {
      await tester.tap(find.text('设置候选池'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-teacher-pool')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('李老师池 · 1 人').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(cancel ? '取消' : '应用'));
      await tester.pumpAndSettle();
    }

    await setPool(cancel: true);
    final unchanged = (await tester.runAsync(
      () => repository.watchSupervisionDraft('t').first,
    ))!;
    expect(unchanged.posts.every((post) => post.teacherPoolId == null), isTrue);
    await setPool(cancel: false);
    expect(find.textContaining('个指派不符合当前规则'), findsOneWidget);
    await tester.tap(find.text('匹配偏好'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同时设置目标学科'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-target-math')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('单独设置'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('matching-enable-subjectTeacher')),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(
        find.byKey(const ValueKey('matching-up-subjectTeacher')),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('满足任一项'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    final saved = await saveSupervisionFromUi(tester, repository);
    for (final id in ['a', 'b']) {
      final post = saved.posts.firstWhere((post) => post.id == id);
      expect(post.teacherPoolId, 'p');
      expect(post.targetSubjectIds, {'math'});
      expect(
        post.matchingPreferences?.order.first,
        SupervisionPreference.subjectTeacher,
      );
      expect(
        post.matchingPreferences?.requirement,
        SupervisionMatchRequirement.any,
      );
    }
    expect(
      saved.posts.firstWhere((post) => post.id == 'c').matchingPreferences,
      isNull,
    );
    expect(saved.assignments, original.assignments);
    expect(saved.manualPostIds, original.manualPostIds);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('duty-filter-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('duty-post-a')), findsNothing);
    expect(find.byKey(const ValueKey('duty-post-b')), findsOneWidget);
  });

  testWidgets('创建岗位指定候选池与目标学科后手动选人遵守范围', (tester) async {
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
          teacherPools: const [
            SupervisionTeacherPool(
              id: 'p',
              name: '数学池',
              teacherIds: {'teacher'},
            ),
          ],
        ),
        expectedRevision: 0,
      );
    });
    await openSupervision(tester, repository);
    await tester.tap(find.text('创建岗位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('人员设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-teacher-pool')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('数学池 · 1 人').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-target-math')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-scope-class-c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-slot-1-service-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加岗位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待安排'));
    await tester.pumpAndSettle();
    expect(find.text('数学池'), findsOneWidget);
    // 推荐优先视图隐藏池外教师，李老师不应出现在候选列表。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('duty-teacher-panel')),
        matching: find.text('李老师'),
      ),
      findsNothing,
    );
    expect(find.textContaining('任教数学'), findsOneWidget);
    await pickTeacherInPanel(tester, '张老师');
    final saved = await saveSupervisionFromUi(tester, repository);
    expect(saved.posts.single.teacherPoolId, 'p');
    expect(saved.posts.single.targetSubjectIds, {'math'});
    expect(saved.assignments.values, ['teacher']);
  });
  testWidgets('智能补齐通过实际分配线程使用岗位候选池，全满时可重新匹配手动指派', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    final input = supervisionDraft.copyWith(
      posts: [
        supervisionDraft.posts[0].copyWith(teacherPoolId: 'p'),
        supervisionDraft.posts[1].copyWith(teacherPoolId: 'p'),
      ],
      assignments: {},
      manualPostIds: {},
      teacherPools: const [
        SupervisionTeacherPool(id: 'p', name: '专用教师池', teacherIds: {'teacher'}),
      ],
    );
    await tester.runAsync(() async {
      await repository.saveTerm(supervisionTerm);
      await repository.saveSupervisionDraft(input, expectedRevision: 0);
    });
    await openSupervision(tester, repository);
    Future<void> waitForMatching() async {
      for (var i = 0; i < 150 && find.text('取消补齐').evaluate().isNotEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('取消补齐'), findsNothing);
    }

    await tester.tap(find.text('智能补齐'));
    await tester.pump();
    await waitForMatching();
    final filled = await saveSupervisionFromUi(tester, repository);
    expect(filled.assignments, {'a': 'teacher', 'b': 'teacher'});
    expect(filled.manualPostIds, isEmpty);
    await tester.tap(find.byKey(const ValueKey('duty-post-a')));
    await tester.pumpAndSettle();
    // 当前已是自动补齐的教师，无变更时主按钮禁用；先清除再重新指派，
    // 才能得到一次显式的手动指派标记。
    await clearAssignmentInPanel(tester);
    await pickTeacherInPanel(tester, '张老师');
    final manual = await saveSupervisionFromUi(tester, repository);
    expect(manual.manualPostIds, {'a'});
    await closeTeacherDrawer(tester);
    await tester.tap(find.text('重新匹配'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留手动指派'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始匹配'));
    await tester.pump();
    await waitForMatching();
    final rematched = await saveSupervisionFromUi(tester, repository);
    expect(rematched.assignments, {'a': 'teacher', 'b': 'teacher'});
    expect(rematched.manualPostIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('岗位引用已删除候选池和学科时可在人员设置中修正', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = TestSupervisionRepository(
      database,
      supervisionSnapshot(),
    );
    final post = supervisionDraft.posts.first.copyWith(
      teacherPoolId: 'gone',
      targetSubjectIds: {'removed'},
    );
    await tester.runAsync(() async {
      await repository.saveTerm(supervisionTerm);
      await repository.saveSupervisionDraft(
        supervisionDraft.copyWith(posts: [post]),
        expectedRevision: 0,
      );
    });
    await openSupervision(tester, repository);
    await tester.tap(find.byKey(const ValueKey('duty-post-a')));
    await tester.pumpAndSettle();
    await openPostPersonnelSettings(tester);
    expect(find.text('已删除学科（取消勾选以移除）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-target-removed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-teacher-pool')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('基础候选池 · 2 人').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    final saved = await saveSupervisionFromUi(tester, repository);
    expect(saved.posts.single.teacherPoolId, SupervisionDraft.basePoolId);
    expect(saved.posts.single.targetSubjectIds, isEmpty);
    expect(saved.assignments['a'], 'teacher');
    expect(tester.takeException(), isNull);
  });
}
