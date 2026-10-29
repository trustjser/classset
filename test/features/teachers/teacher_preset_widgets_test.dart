import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/stage_routine.dart';
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

  testWidgets('免任课格锁定展示且不可设置预排', (tester) async {
    final cell = (weekday: 1, periodTypeId: 'p_am', lessonIndex: 1);
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 600,
          height: 300,
          child: TeacherPresetMatrix(
            routine: _presetTestRoutine(),
            values: const {},
            onChanged: (cell, value) {},
            exemptions: {
              cell: FreeSlotViewResolution(
                full: FreeSlot(
                  id: 'slot-1',
                  scope: FreeSlotScope.stage,
                  scopeId: 'st1',
                  stageId: 'st1',
                  periodTypeId: 'p_am',
                  weekday: 1,
                  lessonIndex: 1,
                  label: '不上课',
                ),
              ),
            },
          ),
        ),
      ),
    );

    expect(find.text('不上课'), findsOneWidget);
    expect(find.byTooltip('免任课：不上课'), findsOneWidget);

    // 免任课格没有预排菜单，不可编辑。
    await tester.tap(find.text('不上课'));
    await tester.pumpAndSettle();
    expect(find.text('尽量排'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('当天无课节的空白格同样展示免任课标记且不可编辑', (tester) async {
    // 周五晚上 0 节（override），该格此前渲染为空白、标记被吞掉。
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 600,
          height: 400,
          child: TeacherPresetMatrix(
            routine: _presetTestRoutine(),
            values: const {},
            onChanged: (cell, value) {},
            exemptions: {
              const (
                weekday: 5,
                periodTypeId: 'p_pm',
                lessonIndex: 1,
              ): FreeSlotViewResolution(
                full: FreeSlot(
                  id: 'slot-blank',
                  scope: FreeSlotScope.stage,
                  scopeId: 'st1',
                  stageId: 'st1',
                  periodTypeId: 'p_pm',
                  weekday: 5,
                  lessonIndex: 1,
                  label: '不上课',
                ),
              ),
            },
          ),
        ),
      ),
    );

    expect(find.text('不上课'), findsOneWidget);
    expect(find.byTooltip('免任课：不上课'), findsOneWidget);

    // 无课节格没有预排菜单。
    await tester.tap(find.text('不上课'));
    await tester.pumpAndSettle();
    expect(find.text('尽量排'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('部分班级免任课格展示标记且仍可设置预排', (tester) async {
    final cell = (weekday: 2, periodTypeId: 'p_am', lessonIndex: 1);
    PresetValue? changed;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 600,
          height: 300,
          child: TeacherPresetMatrix(
            routine: _presetTestRoutine(),
            values: const {},
            onChanged: (cell, value) => changed = value,
            exemptions: {
              cell: FreeSlotViewResolution(
                partial: FreeSlot(
                  id: 'slot-2',
                  scope: FreeSlotScope.grade,
                  scopeId: 'g1',
                  stageId: 'st1',
                  periodTypeId: 'p_am',
                  weekday: 2,
                  lessonIndex: 1,
                  label: '不上课',
                ),
              ),
            },
          ),
        ),
      ),
    );

    // 空态显示部分免任课标记。
    expect(find.text('不上课'), findsOneWidget);
    expect(find.byTooltip('部分班级免任课：不上课'), findsOneWidget);

    // 仍可打开菜单设置预排。
    await tester.tap(find.text('不上课'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('teacher-preset-menu-prefer')),
    );
    await tester.pumpAndSettle();
    expect(changed, PresetValue.prefer);
    expect(tester.takeException(), isNull);
  });
}

StageRoutine _presetTestRoutine() => StageRoutine(
  stageId: 'st1',
  teachingWeekdays: const {1, 2, 3, 4, 5},
  periodTypes: [
    LessonPeriodType(
      id: 'p_am',
      name: '上午',
      defaultLessonCount: 2,
      sortOrder: 0,
      lessonTimes: [
        LessonTime(
          lessonIndex: 1,
          label: '第1节',
          startMinute: 480,
          endMinute: 530,
        ),
        LessonTime(
          lessonIndex: 2,
          label: '第2节',
          startMinute: 540,
          endMinute: 590,
        ),
      ],
    ),
    LessonPeriodType(
      id: 'p_pm',
      name: '晚上',
      defaultLessonCount: 2,
      sortOrder: 3,
      lessonTimes: [
        LessonTime(
          lessonIndex: 1,
          label: '晚1',
          startMinute: 1140,
          endMinute: 1190,
        ),
        LessonTime(
          lessonIndex: 2,
          label: '晚2',
          startMinute: 1200,
          endMinute: 1250,
        ),
      ],
    ),
  ],
  // 周五晚上没有课节：该列空白格上的免任课标记也要展示。
  overrides: const [
    RoutineOverride(periodTypeId: 'p_pm', weekday: 5, lessonCount: 0),
  ],
);
