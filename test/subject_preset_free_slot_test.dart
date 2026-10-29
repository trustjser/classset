import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/dialogs/subject_preset_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => FTheme(
      data: AppTheme.foruiFor(false),
      child: FToaster(child: child!),
    ),
    home: Scaffold(body: child),
  ),
);

StageRoutine _routine() => StageRoutine(
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
  overrides: const [RoutineOverride(periodTypeId: 'p_pm', weekday: 5, lessonCount: 0)],
);

SubjectPresetDialog _dialog({required List<FreeSlot> freeSlots}) =>
    SubjectPresetDialog(
      subject: const Subject(
        id: 'pe',
        name: '体育与健康',
        shortName: '体',
        sortOrder: 0,
      ),
      termId: 't1',
      initialStageId: 'st1',
      initialGradeId: 'g1',
      stages: const [
        SchoolStage(id: 'st1', termId: 't1', name: '小学部', sortOrder: 0),
      ],
      grades: const [
        GradeGroup(id: 'g1', stageId: 'st1', name: '一年级', sortOrder: 0),
      ],
      classes: const [
        ClassBrief(
          stageId: 'st1',
          gradeId: 'g1',
          id: 'c1',
          name: '一（1）班',
        ),
      ],
      routines: {'st1': _routine()},
      presets: const [],
      constraints: const [],
      freeSlots: freeSlots,
      classDemands: const {},
    );

void main() {
  testWidgets('学段范围免任课格显示标记且不可循环切换', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _dialog(
          freeSlots: [
            FreeSlot(
              id: 'slot-stage',
              scope: FreeSlotScope.stage,
              scopeId: 'st1',
              stageId: 'st1',
              periodTypeId: 'p_am',
              weekday: 1,
              lessonIndex: 1,
              label: '不上课',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('不上课'), findsOneWidget);
    expect(find.byTooltip('免任课：不上课'), findsOneWidget);

    // 免任课格单击不应切换预设（保持空态）。
    await tester.tap(find.byKey(const ValueKey('preset-cell-1-p_am-1')));
    await tester.pumpAndSettle();
    expect(find.text('尽量排'), findsNothing);
  });

  testWidgets('全校范围免任课格显示标记', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _dialog(
          freeSlots: [
            FreeSlot(
              id: 'slot-school',
              scope: FreeSlotScope.school,
              scopeId: 't1',
              stageId: 'st1',
              periodTypeId: 'p_am',
              weekday: 2,
              lessonIndex: 1,
              label: '不上课',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('不上课'), findsOneWidget);
  });

  testWidgets('当天无课节的空白格同样展示免任课标记', (tester) async {
    // 周五晚上 0 节（override），该格此前渲染为空白、标记被吞掉。
    await tester.pumpWidget(
      _wrap(
        _dialog(
          freeSlots: [
            FreeSlot(
              id: 'slot-blank',
              scope: FreeSlotScope.stage,
              scopeId: 'st1',
              stageId: 'st1',
              periodTypeId: 'p_pm',
              weekday: 5,
              lessonIndex: 1,
              label: '不上课',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('不上课'), findsOneWidget);
    expect(find.byTooltip('免任课：不上课'), findsOneWidget);
  });

  testWidgets('年级与班级范围免任课格在学段视图也显示标记', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _dialog(
          freeSlots: [
            FreeSlot(
              id: 'slot-grade',
              scope: FreeSlotScope.grade,
              scopeId: 'g1',
              stageId: 'st1',
              periodTypeId: 'p_am',
              weekday: 3,
              lessonIndex: 1,
              label: '不上课',
            ),
            FreeSlot(
              id: 'slot-class',
              scope: FreeSlotScope.schoolClass,
              scopeId: 'c1',
              stageId: 'st1',
              periodTypeId: 'p_am',
              weekday: 4,
              lessonIndex: 1,
              label: '不上课',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 当前范围树停在学段（默认），年级 / 班级级免任课也应可见。
    expect(find.text('不上课'), findsNWidgets(2));
  });
}
