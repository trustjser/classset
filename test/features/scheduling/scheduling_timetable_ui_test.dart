import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:class_set/features/scheduling/scheduling_timetable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;
import 'package:material_ui/material_ui.dart' as material_ui;

void main() {
  Future<void> mount(
    WidgetTester tester, {
    bool withUnplaced = false,
    bool longClassName = false,
    Future<int?> Function(Set<String>)? onPlaceUnplaced,
    void Function(List<ScheduleItem>, String)? onExport,
    VoidCallback? onReport,
  }) async {
    tester.view.physicalSize = const Size(1180, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = [
      for (var i = 0; i < 26; i++)
        ScheduleItem(
          id: 'item$i',
          termId: 't',
          assignmentId: 'a$i',
          classId: 'c$i',
          teacherId: 'teacher1',
          subjectId: 'subject',
          weekMode: WeekMode.weekly,
          position: const SchedulePosition(
            stageId: 's',
            weekday: 1,
            periodTypeId: 'p',
            lessonIndex: 1,
          ),
        ),
    ];
    if (withUnplaced) items[0] = items[0].at(null);
    final snapshot = SchedulingSnapshot(
      term: AcademicTerm(
        id: 't',
        title: '学期',
        academicYear: '2026',
        semesterLabel: '秋',
        firstTeachingWeekStart: null,
        teachingWeekCount: 20,
        createdAt: DateTime(2026),
      ),
      inputFingerprint: 'test',
      stages: const [
        SchoolStage(id: 's', termId: 't', name: '小学', sortOrder: 0),
      ],
      grades: const [
        GradeGroup(id: 'g', stageId: 's', name: '一年级', sortOrder: 0),
      ],
      classes: [
        for (var i = 0; i < 26; i++)
          ClassGroup(
            id: 'c$i',
            gradeId: 'g',
            name: longClassName && i == 0
                ? '一班特别长的班级名称用于显示完整提示'
                : '一年级 ${i + 1} 班',
            sortOrder: i,
          ),
      ],
      routines: const [
        StageRoutine(
          stageId: 's',
          teachingWeekdays: {1, 2, 3, 4, 5},
          periodTypes: [
            LessonPeriodType(
              id: 'p',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [
                LessonTime(
                  lessonIndex: 1,
                  label: '第1节',
                  startMinute: 480,
                  endMinute: 520,
                ),
              ],
            ),
          ],
          overrides: [],
        ),
      ],
      subjects: const [
        Subject(id: 'subject', name: '数学', shortName: '数', sortOrder: 0),
      ],
      teachers: const [
        Teacher(id: 'teacher1', name: '张老师', shortName: '张', sortOrder: 0),
        Teacher(id: 'teacher2', name: '李老师', shortName: '李', sortOrder: 1),
      ],
      rooms: const [
        PublicRoom(
          id: 'room1',
          name: '音乐教室',
          roomCount: 1,
          capacityPerRoom: 1,
          sortOrder: 0,
        ),
        PublicRoom(
          id: 'room2',
          name: '科学实验室',
          roomCount: 1,
          capacityPerRoom: 1,
          sortOrder: 1,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => f.FTheme(
          data: AppTheme.foruiFor(false),
          child: f.FToaster(child: child!),
        ),
        home: Scaffold(
          body: SchedulingTimetable(
            snapshot: snapshot,
            state: SchedulingState(
              items: items,
              status: SchedulingStatus.ready,
            ),
            onStart: () {},
            onRefresh: () {},
            onRules: () {},
            onReport: onReport ?? () {},
            onDetectionReport: () {},
            onCancel: () {},
            onDone: () {},
            onExport: onExport ?? (_, _) {},
            onPreviewMove: (_, _, _) => throw UnimplementedError(),
            onMove: (_, _, _) async => throw UnimplementedError(),
            onPlaceUnplaced: onPlaceUnplaced,
            onUndo: () {},
            onRedo: () {},
            onSetLock: (_, _) async {},
            onSetAllLocks: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('班级选择和节次时间悬停显示完整内容', (tester) async {
    await mount(tester, longClassName: true);
    final selector = find.byKey(const ValueKey('schedule-class-selector'));
    final editable = tester.widget<EditableText>(
      find.descendant(of: selector, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, endsWith('…'));
    final classTooltip = find.byWidgetPredicate(
      (widget) =>
          widget is Tooltip && widget.message == '小学 · 一年级 一班特别长的班级名称用于显示完整提示',
    );
    final timeTooltip = find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == '第 1 节 · 08:00',
    );
    expect(classTooltip, findsOneWidget);
    expect(timeTooltip, findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(selector));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('小学 · 一年级 一班特别长的班级名称用于显示完整提示'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(timeTooltip));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('第 1 节 · 08:00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('暂放区展示可拖动卡片、标题栏切换和一键放入反馈', (tester) async {
    Set<String>? requested;
    await mount(
      tester,
      withUnplaced: true,
      onPlaceUnplaced: (ids) async {
        requested = ids;
        return 1;
      },
    );
    final card = find.byKey(const ValueKey('unplaced-card-item0'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.drag_indicator)),
      findsOneWidget,
    );
    expect(find.text('按科目聚合'), findsOneWidget);
    await tester.tap(find.text('按科目聚合'));
    await tester.pumpAndSettle();
    expect(find.text('按班级排列'), findsOneWidget);
    await tester.ensureVisible(find.text('一键放入'));
    await tester.tap(find.text('一键放入'));
    await tester.pumpAndSettle();
    expect(requested, {'item0'});
    expect(find.textContaining('已放入 1 节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导出入口传入全部课程而非当前班级筛选', (tester) async {
    List<ScheduleItem>? requested;
    await mount(tester, onExport: (items, title) => requested = items);
    await tester.tap(find.text('导出/打印'));
    await tester.pumpAndSettle();
    expect(requested, hasLength(26));
  });

  testWidgets('一键放入失败后仍可查看未排原因报告', (tester) async {
    var reportOpened = false;
    await mount(
      tester,
      withUnplaced: true,
      onPlaceUnplaced: (_) async => 0,
      onReport: () => reportOpened = true,
    );
    await tester.ensureVisible(find.text('一键放入'));
    await tester.tap(find.text('一键放入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请查看未排课程报告中的原因'), findsOneWidget);
    expect(find.byKey(const ValueKey('unplaced-card-item0')), findsOneWidget);
    await tester.tap(find.text('查看未排课程报告'));
    await tester.pumpAndSettle();
    expect(reportOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('总课表窄单元格可展开收起且不溢出', (tester) async {
    await mount(tester);
    await tester.tap(find.text('总课程表'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('查看全部 26 节'), findsOneWidget);
    await tester.tap(find.text('查看全部 26 节'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(find.text('查看全部 26 节'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(820, 850);
    await tester.pumpAndSettle();
    expect(find.text('查看全部 26 节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('班级教师场室选择器支持搜索并选择', (tester) async {
    await mount(tester);
    Future<void> search(
      String key,
      String hint,
      String query,
      String option,
      String expectedId,
    ) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
      await tester.enterText(find.byType(EditableText).last, query);
      await tester.pumpAndSettle();
      expect(find.text(option), findsOneWidget);
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppSelectField<String>>(find.byKey(ValueKey(key))).value,
        expectedId,
      );
      expect(tester.takeException(), isNull);
    }

    await search(
      'schedule-class-selector',
      '搜索班级',
      '26 班',
      '小学 · 一年级 一年级 26 班',
      'c25',
    );
    await tester.tap(find.text('教师课程表'));
    await tester.pumpAndSettle();
    final paintedBackground = find.descendant(
      of: find.descendant(
        of: find.byKey(const ValueKey('schedule-stage-selector')),
        matching: find.byType(material_ui.InputDecorator),
      ),
      matching: find.byType(CustomPaint),
    );
    expect(paintedBackground, findsOneWidget);
    expect(
      (tester.getCenter(find.text('学段')) - tester.getCenter(paintedBackground))
          .dy
          .abs(),
      lessThanOrEqualTo(.5),
    );
    final teacherBackground = find.descendant(
      of: find.descendant(
        of: find.byKey(const ValueKey('schedule-teacher-selector')),
        matching: find.byType(material_ui.InputDecorator),
      ),
      matching: find.byType(CustomPaint),
    );
    expect(teacherBackground, findsOneWidget);
    expect(
      (tester.getCenter(find.text('教师')) - tester.getCenter(teacherBackground))
          .dy
          .abs(),
      lessThanOrEqualTo(.5),
    );
    for (final key in [
      'schedule-stage-selector',
      'schedule-teacher-selector',
    ]) {
      final filter = find.byKey(ValueKey(key));
      final select = tester.widget<f.FSelect<String>>(
        find.descendant(
          of: filter,
          matching: find.byWidgetPredicate(
            (widget) => widget is f.FSelect<String>,
          ),
        ),
      );
      final context = tester.element(filter);
      final style = select
          .style(f.FTheme.of(context).selectStyle)
          .fieldStyles
          .resolve({f.FTextFieldSizeVariant.sm});
      expect(style.border.base, isA<material_ui.OutlineInputBorder>());
      expect(
        (style.border.base as material_ui.OutlineInputBorder).borderRadius,
        BorderRadius.circular(8),
      );
    }
    expect(
      (tester.getCenter(find.text('学段')) -
              tester.getCenter(
                find.byKey(const ValueKey('schedule-stage-selector')),
              ))
          .dy
          .abs(),
      lessThanOrEqualTo(1),
    );
    expect(
      (tester.getCenter(find.text('教师')) -
              tester.getCenter(
                find.byKey(const ValueKey('schedule-teacher-selector')),
              ))
          .dy
          .abs(),
      lessThanOrEqualTo(1),
    );
    expect(
      (tester.getCenter(find.text('学段')) - tester.getCenter(find.text('全部学段')))
          .dy
          .abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('schedule-stage-selector')))
          .height,
      lessThanOrEqualTo(34),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('schedule-teacher-selector')))
          .height,
      lessThanOrEqualTo(34),
    );
    await search('schedule-teacher-selector', '搜索教师', '李', '李老师', 'teacher2');
    await tester.tap(find.text('场室课程表'));
    await tester.pumpAndSettle();
    await search('schedule-room-selector', '搜索场室', '科学', '科学实验室', 'room2');
  });
}
