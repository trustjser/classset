import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/features/routines/routine_page.dart';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

/// 设计稿界面 02b（初中部）：上午 5 + 下午 5 + 晚上 2 = 12 节；
/// 上课天周一至周五 + 周日（晚自习），周日白天节数覆盖为 0。
void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repository;
  late ProviderContainer container;

  Future<void> saveTerm() => repository.saveTerm(
    AcademicTerm(
      id: 't1',
      title: '2026 秋季',
      academicYear: '2026-2027',
      semesterLabel: '秋季学期',
      firstTeachingWeekStart: DateTime(2026, 9, 1),
      teachingWeekCount: 20,
      createdAt: DateTime(2026, 8, 1),
    ),
  );

  LessonTime time(
    int index,
    int startHour,
    int startMinute,
    int endHour,
    int endMinute,
  ) => LessonTime(
    lessonIndex: index,
    label: '',
    startMinute: startHour * 60 + startMinute,
    endMinute: endHour * 60 + endMinute,
  );

  Future<void> saveJuniorRoutine() => repository.saveRoutine(
    StageRoutine(
      stageId: 'jr',
      teachingWeekdays: const {1, 2, 3, 4, 5, 7},
      periodTypes: [
        const LessonPeriodType(
          id: 'jr_read',
          name: '早读',
          defaultLessonCount: 0,
          sortOrder: 0,
          lessonTimes: [],
        ),
        LessonPeriodType(
          id: 'jr_am',
          name: '上午',
          defaultLessonCount: 5,
          sortOrder: 1,
          lessonTimes: [
            time(1, 8, 0, 8, 45),
            time(2, 8, 55, 9, 40),
            time(3, 9, 50, 10, 35),
            time(4, 10, 45, 11, 30),
            time(5, 11, 30, 12, 20),
          ],
        ),
        LessonPeriodType(
          id: 'jr_pm',
          name: '下午',
          defaultLessonCount: 5,
          sortOrder: 2,
          lessonTimes: [
            time(1, 14, 0, 14, 45),
            time(2, 14, 55, 15, 40),
            time(3, 15, 50, 16, 35),
            time(4, 16, 45, 17, 30),
            time(5, 17, 30, 18, 30),
          ],
        ),
        LessonPeriodType(
          id: 'jr_night',
          name: '晚上',
          defaultLessonCount: 2,
          sortOrder: 3,
          lessonTimes: [time(1, 19, 0, 20, 20), time(2, 20, 30, 21, 40)],
        ),
      ],
      overrides: const [
        RoutineOverride(periodTypeId: 'jr_am', weekday: 7, lessonCount: 0),
        RoutineOverride(periodTypeId: 'jr_pm', weekday: 7, lessonCount: 0),
      ],
    ),
  );

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftSchoolRepository(database);
    container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
    );
    await saveTerm();
    await repository.saveStage(
      const SchoolStage(id: 'jr', termId: 't1', name: '初中部', sortOrder: 1),
    );
    await saveJuniorRoutine();
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => f.FTheme(
            data: AppTheme.forui,
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: RoutinePage(termId: 't1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 切换到初中部学段页签。
  Future<void> selectJuniorStage(WidgetTester tester) async {
    await tester.tap(find.text('初中部 · 12 节'));
    await tester.pumpAndSettle();
  }

  testWidgets('网格列按上课天连续区间展示，非上课天为无效列', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);

    // 表头仅上课天有标签；周六列常驻但无标签（设计稿 02b）。
    for (final label in ['周一', '周二', '周三', '周四', '周五', '周日']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('周六'), findsNothing);

    // 第 1–6 节、折叠行与晚自习行：周六均无效（6 + 1 + 2 = 9 个「—」）；
    // 周日白天被「按天差异」覆盖为 0 节，显示红色「无课」（6 个）。
    expect(find.text('—'), findsNWidgets(9));
    expect(find.text('无课'), findsNWidgets(6));

    // 晚自习行周日列有效（可交互）。
    expect(
      find.byKey(const ValueKey('routine-cell-jr_night-7-1')),
      findsOneWidget,
    );
    final matrix = find.byKey(const ValueKey('routine-matrix'));
    expect(
      find.descendant(of: matrix, matching: find.text('晚自习 1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: matrix, matching: find.text('晚自习 2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('超过 6 个白天节次折叠为「第 7–10 节」，可展开收起', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);
    // 标签断言限定在免任课网格内（右侧时间面板也有同名节次行）。
    Finder labelInMatrix(String label) => find.descendant(
      of: find.byKey(const ValueKey('routine-matrix')),
      matching: find.text(label),
    );

    expect(labelInMatrix('第 7–10 节 ▸'), findsOneWidget);
    for (final label in ['第 7 节', '第 8 节', '第 9 节', '第 10 节']) {
      expect(labelInMatrix(label), findsNothing, reason: label);
    }

    await tester.tap(find.byKey(const ValueKey('routine-fold-row')));
    await tester.pumpAndSettle();
    for (final label in ['第 7 节', '第 8 节', '第 9 节', '第 10 节']) {
      expect(labelInMatrix(label), findsOneWidget, reason: label);
    }
    expect(labelInMatrix('第 7–10 节 ▸'), findsNothing);
    expect(find.byKey(const ValueKey('routine-fold-bar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('routine-fold-bar')));
    await tester.pumpAndSettle();
    expect(labelInMatrix('第 7–10 节 ▸'), findsOneWidget);
    expect(labelInMatrix('第 10 节'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未启用时段显示「未启用 + 启用」，可撤销并可保存回写', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);

    expect(find.text('早读（未启用）'), findsOneWidget);
    expect(find.text('+ 启用'), findsOneWidget);

    await tester.tap(find.text('+ 启用'));
    await tester.pumpAndSettle();
    expect(find.text('早读（未启用）'), findsNothing);
    expect(find.text('+ 启用'), findsNothing);
    expect(find.text('早读时段 · 每天 1 节'), findsOneWidget);
    expect(find.text('已启用「早读」'), findsOneWidget);
    expect(find.byKey(const ValueKey('routine-unsaved-bar')), findsOneWidget);

    // 撤销提示条撤销启用。
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('早读（未启用）'), findsOneWidget);
    expect(find.byKey(const ValueKey('routine-unsaved-bar')), findsNothing);

    // 重新启用后保存，写回数据库。
    await tester.tap(find.text('+ 启用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final routine = (await tester.runAsync(
      () => repository.watchRoutine('jr').first,
    ))!;
    final morningRead = routine.periodTypes.firstWhere(
      (period) => period.name == '早读',
    );
    expect(morningRead.defaultLessonCount, 1);
    expect(morningRead.lessonTimes, hasLength(1));
    expect(find.byKey(const ValueKey('routine-unsaved-bar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('范围树标注学段独立与编辑中状态（设计稿 02b）', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);

    expect(find.text('全校'), findsOneWidget);
    expect(find.text('小学部（独立作息）'), findsOneWidget);
    expect(find.text('初中部（编辑中）'), findsOneWidget);
  });

  testWidgets('点击其他学段下的年级/班级自动切换到对应学段并保留选中项', (tester) async {
    await tester.runAsync(() async {
      final stages = await repository.watchStages('t1').first;
      final primaryId = stages.firstWhere((stage) => stage.name == '小学部').id;
      await repository.saveGrade(
        GradeGroup(
          id: 'pr_g1',
          stageId: primaryId,
          name: '一年级',
          sortOrder: 0,
        ),
      );
      await repository.saveGrade(
        const GradeGroup(
          id: 'jr_g1',
          stageId: 'jr',
          name: '七年级',
          sortOrder: 0,
        ),
      );
      await repository.saveClass(
        const ClassGroup(
          id: 'jr_g1_c1',
          gradeId: 'jr_g1',
          name: '七年级 1 班',
          sortOrder: 0,
        ),
      );
    });
    await pumpPage(tester);
    await selectJuniorStage(tester);

    Finder stageTile(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(AppTreeTile),
    );
    Finder gradeTile(String title) => find.ancestor(
      of: find.text(title),
      matching: find.byType(AppTreeTile),
    );
    bool isTileSelected(Finder tile) =>
        tester.widget<AppTreeTile>(tile.first).isSelected;

    // 展开小学部，点击其下的年级：应切到小学部并选中该年级。
    await tester.tap(
      find.descendant(
        of: stageTile('小学部（独立作息）'),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('一年级'), findsOneWidget);

    await tester.tap(find.text('一年级'));
    await tester.pumpAndSettle();

    expect(find.text('小学部（编辑中）'), findsOneWidget);
    expect(find.text('初中部（独立作息）'), findsOneWidget);
    expect(isTileSelected(gradeTile('一年级')), isTrue);

    // 展开初中部的七年级，点击其下的班级：应切回初中部并选中该班级。
    await tester.tap(
      find.descendant(
        of: stageTile('初中部（独立作息）'),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: gradeTile('七年级'),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('七年级 1 班'), findsOneWidget);

    await tester.tap(find.text('七年级 1 班'));
    await tester.pumpAndSettle();

    expect(find.text('初中部（编辑中）'), findsOneWidget);
    expect(find.text('小学部（独立作息）'), findsOneWidget);
    expect(isTileSelected(gradeTile('七年级 1 班')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('每天节数卡片标题标注与其他学段无关', (tester) async {
    await pumpPage(tester);
    // 默认选中小学部（首个学段），另一学段为初中部。
    expect(find.text('每天节数（与初中部无关）'), findsOneWidget);
    expect(find.text('公共时段（小学部独立）'), findsOneWidget);
  });

  testWidgets('按天差异徽章与每周容量', (tester) async {
    // 小学部默认：上午 4 + 下午 4 + 晚上 2，周一至周五上课。
    // 事务写入需在真实异步区执行（fake async 下 drift 事务不会完成）。
    await tester.runAsync(() async {
      await repository.saveRoutine(
        StageRoutine(
          stageId: (await repository.watchStages('t1').first).first.id,
          teachingWeekdays: const {1, 2, 3, 4, 5},
          periodTypes: [
            LessonPeriodType(
              id: 'pm_am',
              name: '上午',
              defaultLessonCount: 4,
              sortOrder: 0,
              lessonTimes: const [],
            ),
            LessonPeriodType(
              id: 'pm_pm',
              name: '下午',
              defaultLessonCount: 4,
              sortOrder: 1,
              lessonTimes: const [],
            ),
            LessonPeriodType(
              id: 'pm_night',
              name: '晚上',
              defaultLessonCount: 2,
              sortOrder: 2,
              lessonTimes: const [],
            ),
          ],
          overrides: const [
            RoutineOverride(
              periodTypeId: 'pm_night',
              weekday: 5,
              lessonCount: 0,
            ),
          ],
        ),
      );
    });
    await pumpPage(tester);

    expect(find.text('星期五 晚上 2→0'), findsOneWidget);
    // 每天 10 节 × 5 天 = 50，周五晚上覆盖 2→0 减去 2 → 48。
    expect(find.text('48 格 / 班'), findsOneWidget);
  });

  testWidgets('右侧分组收起后无时间时显示按天节数概要', (tester) async {
    // 该作息未填起止时间：收起「晚上」分组后显示「周五 0/其余 2」类概要。
    await tester.runAsync(() async {
      await repository.saveRoutine(
        StageRoutine(
          stageId: (await repository.watchStages('t1').first).first.id,
          teachingWeekdays: const {1, 2, 3, 4, 5},
          periodTypes: [
            LessonPeriodType(
              id: 'pm_am',
              name: '上午',
              defaultLessonCount: 2,
              sortOrder: 0,
              lessonTimes: const [],
            ),
            LessonPeriodType(
              id: 'pm_night',
              name: '晚上',
              defaultLessonCount: 2,
              sortOrder: 1,
              lessonTimes: const [],
            ),
          ],
          overrides: const [
            RoutineOverride(
              periodTypeId: 'pm_night',
              weekday: 5,
              lessonCount: 0,
            ),
          ],
        ),
      );
    });
    await pumpPage(tester);

    expect(find.text('晚上时段 · 每天 2 节'), findsOneWidget);
    await tester.tap(find.text('晚上时段 · 每天 2 节'));
    await tester.pumpAndSettle();
    expect(find.text('晚上时段 · 每天 2 节'), findsNothing);
    // 时间未填全 → 退化为按天节数概要（周五被覆盖为 0，不列出）。
    expect(find.text('晚上 · 2 节 周一 2/周二 2/周三 2/周四 2'), findsOneWidget);
    expect(find.text('展开'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('免任课改动在保存前暂存，撤销提示条可撤销', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);
    final saveButton = find.descendant(
      of: find.byTooltip('保存作息设置'),
      matching: find.byType(FilledButton),
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(saveButton).onPressed, isNull);

    const cellKey = ValueKey('routine-cell-jr_am-3-3');

    await tester.tap(find.byKey(cellKey));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('无课')),
      findsOneWidget,
    );
    expect(find.text('已将 星期三 · 第 3 节 设为「无课」'), findsOneWidget);
    final slots = (await tester.runAsync(
      () => repository.watchFreeSlots('jr').first,
    ))!;
    expect(
      slots.where((slot) => slot.weekday == 3 && slot.lessonIndex == 3),
      isEmpty,
    );
    expect(tester.widget<IconButton>(saveButton).onPressed, isNotNull);

    await tester.tap(find.text('撤销'));
    // 撤销提示条回调需真实事件循环处理完成。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('无课')),
      findsNothing,
    );
    expect(find.text('已将 星期三 · 第 3 节 设为「无课」'), findsNothing);
    final afterUndo = (await tester.runAsync(
      () => repository.watchFreeSlots('jr').first,
    ))!;
    expect(
      afterUndo.where((slot) => slot.weekday == 3 && slot.lessonIndex == 3),
      isEmpty,
    );
    expect(tester.widget<IconButton>(saveButton).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置后再次取消免任课恢复原值，保存按钮禁用且数据库不变', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);

    final saveButton = find.descendant(
      of: find.byTooltip('保存作息设置'),
      matching: find.byType(FilledButton),
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(saveButton).onPressed, isNull);

    const cellKey = ValueKey('routine-cell-jr_am-3-3');
    await tester.tap(find.byKey(cellKey));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(saveButton).onPressed, isNotNull);
    expect(
      (await tester.runAsync(() => repository.watchFreeSlots('jr').first))!
          .where((slot) => slot.weekday == 3 && slot.lessonIndex == 3),
      isEmpty,
    );

    await tester.tap(find.byKey(cellKey));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('无课')),
      findsNothing,
    );
    expect(tester.widget<IconButton>(saveButton).onPressed, isNull);
    expect(
      (await tester.runAsync(() => repository.watchFreeSlots('jr').first))!
          .where((slot) => slot.weekday == 3 && slot.lessonIndex == 3),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('撤销免任课修改回到保存基线后保存按钮禁用', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);

    final saveButton = find.descendant(
      of: find.byTooltip('保存作息设置'),
      matching: find.byType(FilledButton),
    );
    // 初始作息含按天差异，先保存归一化后的基线。
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(saveButton).onPressed, isNull);

    const cellKey = ValueKey('routine-cell-jr_am-3-3');
    await tester.tap(find.byKey(cellKey));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(saveButton).onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('无课')),
      findsNothing,
    );
    expect(tester.widget<IconButton>(saveButton).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换学段后撤销重做仍可用并返回操作学段', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);

    const cellKey = ValueKey('routine-cell-jr_am-3-3');
    await tester.tap(find.byKey(cellKey));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('无课')),
      findsOneWidget,
    );

    await tester.tap(find.text('小学部 · 10 节'));
    await tester.pumpAndSettle();

    final undoButton = find.ancestor(
      of: find.byIcon(Icons.undo_rounded),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(undoButton).onPressed, isNotNull);
    await tester.tap(undoButton);
    await tester.pumpAndSettle();

    expect(find.text('初中部 · 12 节'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('无课')),
      findsNothing,
    );

    final redoButton = find.ancestor(
      of: find.byIcon(Icons.redo_rounded),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(redoButton).onPressed, isNotNull);
    await tester.tap(redoButton);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('无课')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('右键格子可选免任课类型并更新提示条', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);
    const cellKey = ValueKey('routine-cell-jr_am-3-3');

    // 网格中「无课」已出现在周日白天覆盖短格；右键菜单会再多一项。
    final noneBefore = find.text('无课').evaluate().length;
    expect(noneBefore, 6);

    await tester.tap(find.byKey(cellKey), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    for (final item in ['自定义名称…', '添加公共时段', '党团活动', '自习', '劳动', '教研活动']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    expect(find.text('无课').evaluate().length, noneBefore + 1);

    await tester.tap(find.text('教研活动'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('教研活动')),
      findsOneWidget,
    );
    expect(find.text('已将 星期三 · 第 3 节 设为「教研活动」'), findsOneWidget);
    final slots = (await tester.runAsync(
      () => repository.watchFreeSlots('jr').first,
    ))!;
    expect(
      slots.any((slot) => slot.label == '教研活动' && slot.weekday == 3),
      isFalse,
    );
    final saveButton = find.descendant(
      of: find.byTooltip('保存作息设置'),
      matching: find.byType(FilledButton),
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    final savedSlots = (await tester.runAsync(
      () => repository.watchFreeSlots('jr').first,
    ))!;
    expect(
      savedSlots.any((slot) => slot.label == '教研活动' && slot.weekday == 3),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    // 桌面平台下 Forui 右键菜单才响应 secondary press（变体在用例结束后复位平台）。
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('勾选上课天后网格新增该列，撤销后恢复', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);

    // 周六初始不在上课天；表头无「周六」标签但存在无效列。
    expect(find.text('周六'), findsNothing);

    await tester.tap(find.text('星期六'));
    await tester.pumpAndSettle();
    expect(find.text('已将 星期六 设为上课天'), findsOneWidget);
    expect(find.text('周六'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('周六'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('插入公共时段后右侧面板显示公共行', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);

    await tester.tap(find.text('+ 插入'));
    await tester.pumpAndSettle();
    // 名称输入框需限定在弹窗内（页面时间字段也是 EditableText）。
    final dialog = find.byType(f.FDialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(EditableText)).first,
      '眼保健操',
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('插入')));
    await tester.pumpAndSettle();

    expect(find.text('眼保健操'), findsOneWidget);
    // 公共行徽章为「名称 · 时长」组合文案（_CommonPeriodChip）。
    expect(find.text('眼保健操 · 10 分钟'), findsOneWidget);
    expect(
      (await tester.runAsync(() => repository.watchCommonPeriods('jr').first))!,
      isEmpty,
    );
    final saveButton = find.descendant(
      of: find.byTooltip('保存作息设置'),
      matching: find.byType(FilledButton),
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    final periods = (await tester.runAsync(
      () => repository.watchCommonPeriods('jr').first,
    ))!;
    expect(periods.single.name, '眼保健操');
    expect(tester.takeException(), isNull);
  });

  testWidgets('位置选择「第 1 节之前」后下拉框正常回显并可插入', (tester) async {
    await pumpPage(tester);
    await selectJuniorStage(tester);

    await tester.tap(find.text('+ 插入'));
    await tester.pumpAndSettle();
    final dialog = find.byType(f.FDialog);

    // 打开「位置」下拉，选择「第 1 节之前」。
    await tester.tap(
      find.descendant(
        of: dialog,
        matching: find.byType(AppSelectField<String?>),
      ).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 1 节之前').last);
    await tester.pumpAndSettle();

    // 回归：此前该选项值为 null，选中后下拉控件回显为空。
    expect(
      find.descendant(of: dialog, matching: find.text('第 1 节之前')),
      findsOneWidget,
    );

    // 哨兵值在提交时映射回 null（插在最前）：插入不抛错且公共行出现。
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(EditableText)).first,
      '眼保健操',
    );
    await tester.tap(find.descendant(of: dialog, matching: find.text('插入')));
    await tester.pumpAndSettle();
    expect(find.text('眼保健操'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧凑窗口下三栏布局不溢出', (tester) async {
    await pumpPage(tester, size: const Size(800, 600));
    await selectJuniorStage(tester);
    expect(find.text('免任课范围'), findsOneWidget);
    expect(find.text('节次与时间'), findsNothing); // 紧凑窗口隐藏时间栏
    expect(tester.takeException(), isNull);
  });
}
