import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/theme/subject_colors.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_run.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/domain/scheduling/course_scheduler.dart';
import 'package:class_set/domain/scheduling/problem_builder.dart';
import 'package:class_set/features/temporary_adjustments/temporary_adjustments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:forui/forui.dart' as f;

/// 用应用主题与 Forui 主题包裹页面，与主应用构建方式一致。
Widget _wrap(Widget child, {ThemeData? theme, bool darkMode = false}) =>
    MaterialApp(
      theme: theme ?? AppTheme.light,
      builder: (context, inner) => f.FTheme(
        data: AppTheme.foruiFor(darkMode),
        child: f.FToaster(child: inner!),
      ),
      home: Scaffold(body: child),
    );

/// 课格状态不再渲染成可见文字，改由 Tooltip message 表达；
/// 测试据此断言，避免把「检测中 / 可选」当作交互定位点。
Finder _tooltipWith(String message) => find.byWidgetPredicate(
  (widget) => widget is Tooltip && widget.message == message,
);

void _expectPanelSurface(WidgetTester tester, String key) {
  final panel = find.byKey(ValueKey(key));
  expect(panel, findsOneWidget);
  // Guard the lookup so a missing panel reports the intended stable-key
  // assertion instead of cascading into a tester.element exception.
  if (panel.evaluate().isEmpty) return;
  final surface = tester.element(panel.first).appColors.surface;
  final decorations = tester
      .widgetList<DecoratedBox>(
        find.descendant(of: panel, matching: find.byType(DecoratedBox)),
      )
      .toList();
  expect(decorations, isNotEmpty);
  if (decorations.isEmpty) return;
  final decoration = decorations.first.decoration;
  expect(decoration, isA<BoxDecoration>());
  expect((decoration as BoxDecoration).color, surface);
}

void _expectCourseFill(
  WidgetTester tester,
  Finder gridPanel,
  String subjectId,
) {
  expect(gridPanel, findsOneWidget);
  if (gridPanel.evaluate().isEmpty) return;
  final fill = SubjectColors.cellBackground(
    tester.element(gridPanel.first),
    subjectId,
  );
  final cellDecorations = tester
      .widgetList<Container>(
        find.descendant(of: gridPanel, matching: find.byType(Container)),
      )
      .map((container) => container.decoration)
      .whereType<BoxDecoration>();
  expect(
    cellDecorations.any((decoration) => decoration.color == fill),
    isTrue,
    reason: '至少一个普通课程格应使用科目专属填充色',
  );
}

class _Repository implements SchoolRepository {
  _Repository(this.state);
  final TemporaryTimetableState state;
  @override
  Future<TemporaryTimetableState> loadTemporaryTimetable(String termId) async =>
      state;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('真实数据库：预览不写入，确认移课并取消后恢复', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late db.AppDatabase database;
    late DriftSchoolRepository repository;
    late ActualLesson source;
    late SchedulePosition target;
    late DateTime targetDate;
    await tester.runAsync(() async {
      database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      repository = DriftSchoolRepository(database);
      await repository.saveTerm(
        AcademicTerm(
          id: 't',
          title: '学期',
          academicYear: '2026',
          semesterLabel: '秋',
          firstTeachingWeekStart: DateTime(2026, 9, 7),
          teachingWeekCount: 4,
          createdAt: DateTime(2026),
          cycleMode: AcademicTermCycle.everyWeek,
        ),
      );
      final stage = (await repository.watchStages('t').first).first;
      await repository.saveGrade(
        GradeGroup(id: 'g', stageId: stage.id, name: '一年级', sortOrder: 0),
      );
      await repository.saveClass(
        const ClassGroup(id: 'c', gradeId: 'g', name: '一班', sortOrder: 0),
      );
      await repository.saveSubjects(const [
        Subject(id: 's', termId: 't', name: '数学', shortName: '数', sortOrder: 0),
      ]);
      await repository.saveTeachers(const [
        Teacher(id: 'teacher', name: '李老师', shortName: '李', sortOrder: 0),
      ]);
      await database.customStatement(
        'INSERT INTO subject_requirements (id, subject_id, grade_id, week_mode, lesson_count) VALUES (?, ?, ?, ?, ?)',
        ['req', 's', 'g', 'weekly', 1],
      );
      await repository.addTeacherAssignments(
        termId: 't',
        assignments: const [
          TeacherAssignment(
            id: 'a',
            termId: 't',
            teacherId: 'teacher',
            classId: 'c',
            subjectId: 's',
            weekMode: WeekMode.weekly,
            lessonCount: 1,
          ),
        ],
      );
      final base = await repository.loadSchedulingSnapshot('t');
      final problem = const ProblemBuilder().build(base);
      final run = const CourseScheduler().solve(
        problem,
        config: const ScheduleRunConfig(
          selectedClassIds: {'c'},
          seed: 7,
          strength: ScheduleStrength.fast,
        ),
      );
      await repository.commitScheduleRun(run, selectedClassIds: {'c'});
      final before = await repository.loadTemporaryTimetable('t');
      source = before.lessons.first;
      target = problem.positionsByClass['c']!.firstWhere(
        (position) => !position.sameCell(source.item.position!),
      );
      targetDate = DateTime(2026, 9, 7).add(Duration(days: target.weekday - 1));
    });
    Future<void> waitForDatabase() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    String date(DateTime d) => d.toIso8601String().substring(0, 10);
    String cell(DateTime d, SchedulePosition p) =>
        'temporary-cell-${date(d)}-${p.periodTypeId}-${p.lessonIndex}';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
        child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
      ),
    );
    await waitForDatabase();
    final sourceCell = find.byKey(
      ValueKey(cell(source.date, source.item.position!)),
    );
    final targetCell = find.byKey(ValueKey(cell(targetDate, target)));
    await tester.dragFrom(
      tester.getCenter(sourceCell),
      tester.getCenter(targetCell) - tester.getCenter(sourceCell),
    );
    await tester.pumpAndSettle();
    // 面板按钮点击与提交链放在 runAsync 中，保证数据库事务在真实异步区推进。
    await tester.runAsync(() async {
      await tester.tap(find.text('下一步 · 预览'));
      await tester.pumpAndSettle();
      expect(find.text('预览调整'), findsOneWidget);
      expect((await repository.loadTemporaryTimetable('t')).records, isEmpty);
      await tester.tap(find.text('确认调整（1次）'));
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await waitForDatabase();
    final saved = (await tester.runAsync(
      () => repository.loadTemporaryTimetable('t'),
    ))!;
    expect(
      saved.lessons.firstWhere((lesson) => lesson.key == source.key).date,
      targetDate,
    );
    final regular = (await tester.runAsync(
      () => repository.loadSchedulingSnapshot('t'),
    ))!;
    expect(
      regular.existingItems.single.position!.cellKey,
      source.item.position!.cellKey,
    );
    await tester.tap(find.text('调整记录'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消调整').last);
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await waitForDatabase();
    final cancelled = (await tester.runAsync(
      () => repository.loadTemporaryTimetable('t'),
    ))!;
    expect(
      cancelled.lessons.firstWhere((lesson) => lesson.key == source.key).date,
      source.date,
    );
  });

  testWidgets('实际周表选课后显示可预览的调课方式', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final snapshot = SchedulingSnapshot(
      term: AcademicTerm(
        id: 't',
        title: '学期',
        academicYear: '2026',
        semesterLabel: '秋',
        firstTeachingWeekStart: DateTime(2026, 9, 7, 8, 30),
        teachingWeekCount: 2,
        createdAt: DateTime(2026),
      ),
      inputFingerprint: 'fingerprint',
      grades: const [
        GradeGroup(id: 'g', stageId: 's', name: '一年级', sortOrder: 0),
      ],
      classes: const [
        ClassGroup(id: 'c', gradeId: 'g', name: '一班', sortOrder: 0),
      ],
      routines: const [
        StageRoutine(
          stageId: 's',
          teachingWeekdays: {1, 2},
          periodTypes: [
            LessonPeriodType(
              id: 'p',
              name: '上午',
              defaultLessonCount: 2,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
          overrides: [],
        ),
      ],
      subjects: const [
        Subject(id: 'subject', name: '数学', shortName: '数', sortOrder: 0),
        Subject(id: 'subject2', name: '语文', shortName: '语', sortOrder: 1),
      ],
      teachers: const [
        Teacher(id: 'teacher', name: '李老师', shortName: '李', sortOrder: 0),
        Teacher(id: 'teacher2', name: '王老师', shortName: '王', sortOrder: 1),
      ],
      existingItems: const [
        ScheduleItem(
          id: 'lesson',
          termId: 't',
          assignmentId: 'a',
          classId: 'c',
          teacherId: 'teacher',
          subjectId: 'subject',
          weekMode: WeekMode.weekly,
          position: SchedulePosition(
            stageId: 's',
            weekday: 1,
            periodTypeId: 'p',
            lessonIndex: 1,
          ),
        ),
        ScheduleItem(
          id: 'lesson2',
          termId: 't',
          assignmentId: 'a',
          classId: 'c',
          teacherId: 'teacher2',
          subjectId: 'subject2',
          weekMode: WeekMode.weekly,
          position: SchedulePosition(
            stageId: 's',
            weekday: 2,
            periodTypeId: 'p',
            lessonIndex: 1,
          ),
        ),
      ],
    );
    final state = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: const [],
      records: const [],
      lessons: const ActualTimetable().expand(snapshot, const []),
      revision: 'v',
      reconciliationPending: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schoolRepositoryProvider.overrideWithValue(_Repository(state)),
        ],
        child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('实际课表'), findsOneWidget);
    expect(find.text('调整记录'), findsOneWidget);
    expect(find.text('导出'), findsOneWidget);
    final gridPanel = find.byKey(
      const ValueKey('temporary-adjustments-grid-panel'),
    );
    const gridHint = '点击任意课格发起调整；已生效的变更会标记在课格中。';
    final panelHint = find.descendant(
      of: gridPanel,
      matching: find.text(gridHint),
    );
    expect(panelHint, findsOneWidget, reason: '说明应显示在本周课表标题栏内');
    expect(
      tester.getCenter(panelHint).dx,
      greaterThan(tester.getCenter(find.text('本周课表')).dx),
      reason: '说明应位于标题右侧',
    );
    expect(
      (tester.getCenter(panelHint).dy - tester.getCenter(find.text('本周课表')).dy)
          .abs(),
      lessThan(4),
      reason: '说明应在标题栏内居中对齐',
    );
    final timetableCells = find.descendant(
      of: gridPanel,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is InkWell &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'temporary-cell-',
            ),
      ),
    );
    final cellRects = [
      for (var index = 0; index < timetableCells.evaluate().length; index++)
        tester.getRect(timetableCells.at(index)),
    ];
    final leftmostCell = cellRects.reduce(
      (first, second) => first.left < second.left ? first : second,
    );
    final rightmostCell = cellRects.reduce(
      (first, second) => first.right > second.right ? first : second,
    );
    final timetableCenter = (leftmostCell.left + rightmostCell.right) / 2;
    expect(
      (tester.getCenter(panelHint).dx - timetableCenter).abs(),
      lessThan(12),
      reason: '说明应与下方课程列区域保持居中',
    );
    _expectPanelSurface(tester, 'temporary-adjustments-grid-panel');
    final subject = snapshot.subjects.firstWhere(
      (item) => item.id == 'subject',
    );
    _expectCourseFill(tester, gridPanel, subject.id);

    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('dark-theme-fixture'),
        overrides: [
          schoolRepositoryProvider.overrideWithValue(_Repository(state)),
        ],
        child: _wrap(
          const TemporaryAdjustmentsPage(termId: 't'),
          theme: AppTheme.dark,
          darkMode: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectPanelSurface(tester, 'temporary-adjustments-grid-panel');
    _expectCourseFill(tester, gridPanel, subject.id);
    await tester.tap(find.text('教师视图'));
    await tester.pumpAndSettle();
    _expectCourseFill(tester, gridPanel, subject.id);
    await tester.tap(find.text('班级视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('数学').first);
    await tester.pumpAndSettle();
    _expectPanelSurface(tester, 'temporary-adjustments-adjustment-panel');

    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('light-theme-fixture-restored'),
        overrides: [
          schoolRepositoryProvider.overrideWithValue(_Repository(state)),
        ],
        child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
      ),
    );
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1000, 900);
    await tester.pumpAndSettle();
    expect(
      (tester.getCenter(find.text('本周')).dy -
              tester.getCenter(find.text('导出')).dy)
          .abs(),
      lessThan(10),
      reason: '窗口有足够空间时，周切换和导出应位于同一行',
    );
    expect(
      (tester.getCenter(find.text('实际课表')).dy -
              tester.getCenter(find.text('本周')).dy)
          .abs(),
      lessThan(10),
      reason: '桌面窗口中工具栏应尽量保持一行',
    );
    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.text('教师视图'));
    await tester.pumpAndSettle();
    expect(find.text('李老师'), findsWidgets);
    expect(find.text('数学'), findsWidgets);
    _expectCourseFill(tester, gridPanel, subject.id);
    await tester.tap(find.text('班级视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('数学').first);
    await tester.pumpAndSettle();
    _expectCourseFill(tester, gridPanel, 'subject2');
    expect(find.text('换课'), findsWidgets);
    expect(find.text('移课'), findsWidgets);
    expect(find.text('代课'), findsWidgets);
    expect(find.text('已选课次'), findsOneWidget);
    expect(find.text('调整方式'), findsOneWidget);
    _expectPanelSurface(tester, 'temporary-adjustments-adjustment-panel');
    expect(
      tester.getTopLeft(find.text('换课').last).dy,
      lessThan(tester.getTopLeft(find.text('移课').last).dy),
    );
    expect(
      tester.getTopLeft(find.text('移课').last).dy,
      lessThan(tester.getTopLeft(find.text('代课').last).dy),
    );
    await tester.tap(find.text('代课').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择代课教师'));
    await tester.pumpAndSettle();
    expect(find.text('同科目'), findsOneWidget);
    expect(find.text('同年级'), findsOneWidget);
    expect(find.text('本班优先'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移课').last);
    await tester.pumpAndSettle();
    // 移课需先选择目标空课位，再进入预览弹窗选择日期范围。
    // 用课格 key 定位，不依赖格内状态文案。
    await tester.tap(
      find.byKey(const ValueKey('temporary-cell-2026-09-07-p-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步 · 预览'));
    await tester.pumpAndSettle();
    expect(find.text('仅本次'), findsOneWidget);
    await tester.tap(find.text('日期范围'));
    await tester.pumpAndSettle();
    expect(find.text('开始日期'), findsOneWidget);
    expect(find.text('结束日期'), findsOneWidget);
    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    for (final viewport in [const Size(390, 780), const Size(700, 700)]) {
      tester.view.physicalSize = viewport;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final adjustmentAction = find.text('发起调整');
      await tester.ensureVisible(adjustmentAction);
      await tester.pumpAndSettle();
      final dayHeader = find.text('周二');
      expect(dayHeader, findsWidgets);
      final beforeScroll = tester.getTopLeft(dayHeader.first).dy;
      await tester.drag(adjustmentAction, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(dayHeader.first).dy,
        lessThan(beforeScroll - 100),
        reason: '${viewport.width}×${viewport.height} 下页面应可滚动到课表',
      );
      final reachableCell = find.byKey(
        const ValueKey('temporary-cell-2026-09-07-p-1'),
      );
      expect(reachableCell, findsOneWidget);
      await tester.ensureVisible(reachableCell);
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(reachableCell)
            .overlaps(Rect.fromLTWH(0, 0, viewport.width, viewport.height)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    }

    tester.view.physicalSize = const Size(1400, 900);
    final first = state.lessons.firstWhere(
      (lesson) => lesson.item.id == 'lesson',
    );
    final second = state.lessons.firstWhere(
      (lesson) => lesson.item.id == 'lesson2',
    );
    final swappedFirst = ActualLesson(
      date: second.date,
      item: first.item.at(second.item.position),
      originDate: first.date,
    );
    final swappedSecond = ActualLesson(
      date: first.date,
      item: second.item.at(first.item.position),
      originDate: second.date,
    );
    final recordState = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: const [],
      lessons: state.lessons,
      revision: 'records',
      reconciliationPending: false,
      records: [
        TemporaryAdjustmentRecord(
          id: 'sub',
          kind: 'substitute',
          reason: '',
          createdAt: DateTime(2026),
          changes: [
            ActualLessonChange(
              before: first,
              after: ActualLesson(
                date: first.date,
                item: second.item.at(first.item.position),
                originDate: first.date,
              ),
            ),
          ],
        ),
        TemporaryAdjustmentRecord(
          id: 'swap',
          kind: 'swap',
          reason: '',
          createdAt: DateTime(2026),
          changes: [
            ActualLessonChange(before: first, after: swappedFirst),
            ActualLessonChange(before: second, after: swappedSecond),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('records'),
        overrides: [
          schoolRepositoryProvider.overrideWithValue(_Repository(recordState)),
        ],
        child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整记录'));
    await tester.pumpAndSettle();
    // 记录列表摘要用「·」分隔说明；括号版文案是预览弹窗的格式。
    expect(find.text('数学·李老师 ↔ 语文·王老师 · 互换时间，科目与教师不变'), findsOneWidget);
    expect(find.text('数学·李老师 → 语文·王老师（保留时间）'), findsOneWidget);
    expect(
      (tester.getCenter(find.text('有效').first).dy -
              tester.getCenter(find.text('详情').first).dy)
          .abs(),
      lessThan(3),
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(700, 700);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1400, 900);
    final large = TemporaryTimetableState(
      snapshot: snapshot,
      exceptions: const [],
      records: const [],
      lessons: [for (var i = 0; i < 501; i++) ...state.lessons],
      revision: 'large',
      reconciliationPending: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        key: const ValueKey('large'),
        overrides: [
          schoolRepositoryProvider.overrideWithValue(_Repository(large)),
        ],
        child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('数学').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移课').last);
    await tester.pump();
    // 检测状态不再铺成可见文字，改由课格 Tooltip message 表达。
    expect(_tooltipWith('正在检测'), findsWidgets);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_tooltipWith('正在检测'), findsNothing);
    expect(_tooltipWith('可选'), findsWidgets);
    await tester.tap(find.text('换课').last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pumpAndSettle();
    final swapCell = find.byKey(
      const ValueKey('temporary-cell-2026-09-08-p-1'),
    );
    expect(
      find.ancestor(of: swapCell, matching: _tooltipWith('正在检测')),
      findsNothing,
    );
    expect(
      find.ancestor(of: swapCell, matching: _tooltipWith('可选')),
      findsOneWidget,
    );
    await tester.tap(swapCell);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步 · 预览'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认调整（1次）'), findsOneWidget);
    expect(find.text('数学·李老师 ↔ 语文·王老师（互换时间，各自科目与教师不变）'), findsOneWidget);
  });
}
