import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/teachers/teachers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) => FTheme(
    data: AppTheme.foruiFor(false),
    child: FToaster(child: child!),
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('范围树按层级展开并回传所选节点', (tester) async {
    String? selected;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 220,
          height: 300,
          child: TeacherPresetScopeTree(
            selectedId: 'primary',
            onSelected: (id) => selected = id,
            nodes: const [
              TeacherPresetScopeNode(
                id: 'primary',
                label: '小学部',
                children: [TeacherPresetScopeNode(id: 'grade-1', label: '一年级')],
              ),
              TeacherPresetScopeNode(
                id: 'junior',
                label: '初中部',
                children: [TeacherPresetScopeNode(id: 'grade-7', label: '七年级')],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('一年级'), findsOneWidget);
    expect(find.text('七年级'), findsNothing);

    await tester.tap(find.text('初中部'));
    await tester.pumpAndSettle();
    expect(selected, 'junior');

    await tester.tap(find.byKey(const ValueKey('scope-expand-junior')));
    await tester.pumpAndSettle();
    expect(find.text('七年级'), findsOneWidget);
  });

  testWidgets('预排单元格菜单展示当前状态并应用显式状态', (tester) async {
    PresetValue? selected;
    await tester.pumpWidget(
      _wrap(
        TeacherPresetValueMenu(
          contextLabel: '第 3 节 · 周三',
          current: PresetValue.forbid,
          onChanged: (value) => selected = value,
          child: const SizedBox(
            width: 120,
            height: 34,
            child: Center(child: Text('不排')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('不排'));
    await tester.pumpAndSettle();
    expect(find.text('第 3 节 · 周三'), findsOneWidget);
    expect(find.text('当前：不排'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('teacher-preset-menu-prefer')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('teacher-preset-menu-prefer')));
    await tester.pumpAndSettle();
    expect(selected, PresetValue.prefer);
  });

  testWidgets('预排单元格菜单的清除动作移除显式状态', (tester) async {
    PresetValue? selected = PresetValue.must;
    await tester.pumpWidget(
      _wrap(
        TeacherPresetValueMenu(
          contextLabel: '第 1 节 · 周一',
          current: selected,
          onChanged: (value) => selected = value,
          child: const SizedBox(
            width: 120,
            height: 34,
            child: Center(child: Text('一定排')),
          ),
        ),
      ),
    );

    await tester.tap(find.text('一定排'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('teacher-preset-menu-clear')));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('窄窗口下学段选择器移到矩阵说明下方', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 320,
          child: TeacherPresetMatrixHeader(
            description: Text('矩阵说明', key: ValueKey('matrix-description')),
            selector: SizedBox(
              height: 40,
              child: Text('学段选择', key: ValueKey('matrix-selector')),
            ),
          ),
        ),
      ),
    );

    final descriptionTop = tester
        .getTopLeft(find.byKey(const ValueKey('matrix-description')))
        .dy;
    final selectorTop = tester
        .getTopLeft(find.byKey(const ValueKey('matrix-selector')))
        .dy;
    expect(selectorTop, greaterThan(descriptionTop));
    expect(tester.takeException(), isNull);
  });
}
