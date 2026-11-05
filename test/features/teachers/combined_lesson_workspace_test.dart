import 'dart:async';

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/features/teachers/presentation/dialogs/combined_lesson_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

const _termId = 'term-1';

TeacherAssignment _assignment({
  required String id,
  required String classId,
  String? groupId,
}) => TeacherAssignment(
  id: id,
  termId: _termId,
  teacherId: 't1',
  classId: classId,
  subjectId: 's1',
  weekMode: WeekMode.weekly,
  lessonCount: 2,
  combinedLessonGroupId: groupId,
);

List<TeacherAssignment> get _assignments => [
  _assignment(id: 'a1', classId: 'c1', groupId: 'g1'),
  _assignment(id: 'a2', classId: 'c2', groupId: 'g1'),
  _assignment(id: 'a3', classId: 'c3'),
  _assignment(id: 'a4', classId: 'c4'),
];

Map<String, ClassBrief> get _classById => {
  for (var i = 1; i <= 4; i++)
    'c$i': ClassBrief(
      stageId: 'primary',
      gradeId: 'grade-1',
      id: 'c$i',
      name: '一年级 $i 班',
    ),
};

Future<void> _mount(
  WidgetTester tester, {
  required void Function(List<String> ids) onCombine,
  Future<bool> Function(String groupId)? onSeparate,
  CombinedLessonTab tab = CombinedLessonTab.create,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeFor(false),
      builder: (context, child) => FTheme(
        data: AppTheme.foruiFor(false),
        child: FToaster(child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              key: const ValueKey('open-workspace'),
              onPressed: () => unawaited(
                showCombinedLessonWorkspace(
                  context: context,
                  termId: _termId,
                  assignments: _assignments,
                  classById: _classById,
                  subjectNames: const {'s1': '道德与法治'},
                  teacherNames: const {'t1': '道德与法治教师 6'},
                  initialTeacherId: 't1',
                  initialTab: tab,
                  onCombine: (ids) async {
                    onCombine(ids);
                    return 'g-new';
                  },
                  onSeparate: onSeparate ?? (_) async => true,
                ),
              ),
              child: const Text('打开合班工作台'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-workspace')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('候选行内容在行高内垂直居中', (tester) async {
    await _mount(tester, onCombine: (_) {});
    final row = find
        .ancestor(
          of: find.text('一年级 3 班'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.constraints?.minHeight == 42,
          ),
        )
        .at(0);
    // 内容贴顶时文字中心会比行中心高出约 6px，居中后应几乎重合。
    expect(
      tester.getCenter(find.text('一年级 3 班')).dy,
      closeTo(tester.getCenter(row).dy, 3.0),
    );
  });

  testWidgets('选中候选行不改变 checkbox 左边界（所有行对齐）', (tester) async {
    await _mount(tester, onCombine: (_) {});
    final boxes = find.byType(FCheckbox);
    expect(boxes, findsNWidgets(2));
    final beforeX = tester.getTopLeft(boxes.at(0)).dx;
    await tester.tap(find.text('一年级 3 班'));
    await tester.pumpAndSettle();
    final afterX = tester.getTopLeft(boxes.at(0)).dx;
    // 选中态的左侧强调条必须靠「未选行也预留同样宽度」实现，
    // 否则已选行内容会整体右移，与未选行错开。
    expect(afterX, closeTo(beforeX, 0.5));
  });

  testWidgets('新建合班：带上教师上下文、列出可合并班级与已有合班组', (tester) async {
    await _mount(tester, onCombine: (_) {});

    expect(find.text('合班 · 道德与法治教师 6'), findsOneWidget);
    expect(find.text('道德与法治教师 6'), findsWidgets);
    expect(find.text('道德与法治'), findsWidgets);
    expect(find.text('每周 2 节'), findsWidgets);
    expect(find.text('新建合班'), findsOneWidget);
    expect(find.text('全部合班课'), findsOneWidget);
    expect(find.text('可合并的班级'), findsOneWidget);
    // 已在合班组中的 c1/c2 不应出现在候选里。
    expect(find.text('一年级 3 班'), findsOneWidget);
    expect(find.text('一年级 4 班'), findsOneWidget);
    expect(find.text('一年级 1、2 班合班'), findsOneWidget);
    expect(find.text('还没有选班级'), findsOneWidget);
    expect(find.text('至少选择 2 个班级才能合班'), findsOneWidget);
  });

  testWidgets('勾选两个班级后预览生效并可确认合班', (tester) async {
    List<String>? combined;
    await _mount(tester, onCombine: (ids) => combined = ids);

    await tester.tap(find.text('一年级 3 班'));
    await tester.pumpAndSettle();
    expect(find.text('再选 1 个班级即可合班'), findsOneWidget);

    await tester.tap(find.text('一年级 4 班'));
    await tester.pumpAndSettle();
    expect(find.text('一年级 3、4 班合班'), findsOneWidget);
    expect(find.textContaining('课时数不叠加'), findsOneWidget);
    expect(find.text('合并条件校验'), findsOneWidget);
    expect(find.text('已选 2 个班级，条件全部满足'), findsOneWidget);

    await tester.tap(find.text('确认合班'));
    await tester.pumpAndSettle();
    expect(combined, ['a3', 'a4']);
    // 成功后切到「已有合班组」，并立即显示新组。
    expect(find.text('一年级 3、4 班合班'), findsWidgets);
  });

  testWidgets('拆分合班需要二次确认，取消不保存而确认后才保存', (tester) async {
    var separateCount = 0;
    await _mount(
      tester,
      onCombine: (_) {},
      onSeparate: (_) async {
        separateCount++;
        return true;
      },
      tab: CombinedLessonTab.existing,
    );

    await tester.tap(find.text('拆分'));
    await tester.pumpAndSettle();

    expect(find.text('确认拆分合班'), findsOneWidget);
    expect(separateCount, 0);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(separateCount, 0);
    expect(find.text('一年级 1、2 班合班'), findsOneWidget);

    await tester.tap(find.text('拆分'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认拆分'));
    await tester.pumpAndSettle();

    expect(separateCount, 1);
    expect(find.text('确认拆分合班'), findsNothing);
  });

  testWidgets('全部合班课：按教师汇总并给出查看该教师入口', (tester) async {
    await _mount(tester, onCombine: (_) {}, tab: CombinedLessonTab.all);

    expect(find.text('全部合班课'), findsWidgets);
    expect(find.text('全校合班课'), findsOneWidget);
    expect(find.text('1 组 · 2 个班 · 1 位教师'), findsOneWidget);
    expect(find.text('查看该教师'), findsOneWidget);
    expect(find.text('一年级 1、2 班合班'), findsWidgets);
  });
}
