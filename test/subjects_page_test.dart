import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/subjects/dialogs/class_detail_dialog.dart';
import 'package:class_set/features/subjects/subjects_page.dart';
import 'package:class_set/features/subjects/widgets/subject_matrix.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

Widget _wrap(ProviderContainer container, String termId) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => f.FTheme(
          data: AppTheme.forui,
          child: f.FToaster(child: child!),
        ),
        home: Scaffold(body: SubjectsPage(termId: termId)),
      ),
    );

void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repository;
  late ProviderContainer container;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftSchoolRepository(database);
    container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  /// 建学期（自动带默认学段）+ 初中学段（一年级 3 个班，容量 5×4=20）。
  Future<void> seedData({
    AcademicTermCycle cycleMode = AcademicTermCycle.alternating,
  }) async {
    await repository.saveTerm(
      AcademicTerm(
        id: 't1',
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '第一学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        cycleMode: cycleMode,
        createdAt: DateTime(2026, 8, 1),
      ),
    );
    await repository.saveStage(
      const SchoolStage(id: 'jr', termId: 't1', name: '初中部', sortOrder: 1),
    );
    await repository.saveStage(
      const SchoolStage(id: 'gz', termId: 't1', name: '高中部', sortOrder: 2),
    );
    await repository.saveGrade(
      const GradeGroup(id: 'g1', stageId: 'jr', name: '一年级', sortOrder: 0),
    );
    await repository.saveClasses([
      const ClassGroup(id: 'c1', gradeId: 'g1', name: '一（1）班', sortOrder: 0),
      const ClassGroup(id: 'c2', gradeId: 'g1', name: '一（2）班', sortOrder: 1),
    ]);
    await repository.saveRoutine(
      const StageRoutine(
        stageId: 'jr',
        teachingWeekdays: {1, 2, 3, 4, 5},
        periodTypes: [
          LessonPeriodType(
            id: 'p_am',
            name: '上午',
            defaultLessonCount: 4,
            sortOrder: 0,
            lessonTimes: [],
          ),
        ],
        overrides: [],
      ),
    );
    await repository.saveSubjects([
      const Subject(id: 's_chinese', name: '语文', shortName: '语', sortOrder: 0),
      const Subject(id: 's_math', name: '数学', shortName: '数', sortOrder: 1),
    ]);
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(activeTermIdProvider.notifier).state = 't1';
    await tester.pumpWidget(_wrap(container, 't1'));
    await tester.pumpAndSettle();
  }

  /// 切换到初中学段（默认落到自动创建的小学部，无年级列）。
  Future<void> selectJuniorStage(WidgetTester tester) async {
    // 选项标签带年级计数（如「初中部（9 个年级）」）；矩阵分组行是纯
    // 「初中部」，用「初中部（」前缀可唯一定位选项行。
    await tester.tap(find.textContaining('初中部（'));
    await tester.pumpAndSettle();
  }

  testWidgets('矩阵展示科目行与年级列，无需求时显示占位', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    expect(find.text('科目节数'), findsOneWidget);
    expect(find.text('语文'), findsOneWidget);
    expect(find.text('数学'), findsOneWidget);
    // 「一年级」同时出现在矩阵表头、范围树与容量卡。
    expect(find.text('一年级'), findsWidgets);
    // 无需求：单元格「—」+ 容量页脚 0 / 20。
    expect(
      find.byKey(const ValueKey('subject-cell-s_chinese-g1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('subject-cell-s_chinese-g1')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(find.text('0 / 20'), findsOneWidget);
  });

  /// 打开单元格菜单：测试里用长按（触摸设备的触发方式；桌面端为右键，
  /// 两者打开同一菜单）。
  Future<void> openCellMenu(WidgetTester tester, Key cellKey) async {
    await tester.longPress(find.byKey(cellKey));
    await tester.pumpAndSettle();
  }

  /// 右键单元格 → 菜单「编辑」→ 打开设置表单。
  Future<void> openCellDialog(WidgetTester tester, Key cellKey) async {
    await openCellMenu(tester, cellKey);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
  }

  /// 双击单元格进入内联编辑并提交文本。
  Future<void> editCellInline(
    WidgetTester tester,
    Key cellKey,
    String text,
  ) async {
    final cell = find.byKey(cellKey);
    await tester.tap(cell);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('单击选中单元格，双击内联编辑整年级生效并落库', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    final cellKey = const ValueKey('subject-cell-s_chinese-g1');
    // 单击：仅选中，不弹表单。
    await tester.tap(find.byKey(cellKey));
    await tester.pumpAndSettle();
    expect(find.byType(ClassDetailDialog), findsNothing);

    // 双击：内联编辑，3|1|1 = 每周3 单周1 双周1（整年级生效）。
    await editCellInline(tester, cellKey, '3|1|1');

    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('3|1|1')),
      findsOneWidget,
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final requirements = (await tester.runAsync(
      () => repository.watchAllRequirements().first,
    ))!;
    expect(requirements.length, 6); // 2 班 × 3 种周模式
    expect(requirements.every((row) => row.subjectId == 's_chinese'), isTrue);
    expect(
      requirements
          .where((row) => row.weekMode == WeekMode.weekly)
          .map((row) => row.lessonCount),
      everyElement(3),
    );
    expect(
      requirements
          .where((row) => row.weekMode == WeekMode.odd)
          .map((row) => row.lessonCount),
      everyElement(1),
    );
    expect(
      requirements
          .where((row) => row.weekMode == WeekMode.even)
          .map((row) => row.lessonCount),
      everyElement(1),
    );
  });

  testWidgets('内联编辑中点击其它单元格保留已输入内容（不丢失）', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    final cellA = find.byKey(const ValueKey('subject-cell-s_chinese-g1'));
    final cellB = find.byKey(const ValueKey('subject-cell-s_math-g1'));
    // 双击进入内联编辑并输入 5（不按回车提交）。
    await tester.tap(cellA);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(cellA);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5');
    await tester.pumpAndSettle();
    // 直接点击另一个单元格：应把进行中的编辑按回车语义提交，而非清空。
    await tester.tap(cellB);
    await tester.pumpAndSettle();
    // A 格内容保留为 5，而非被清空为「—」。
    expect(
      find.descendant(of: cellA, matching: find.text('5')),
      findsOneWidget,
    );
    expect(find.descendant(of: cellA, matching: find.text('—')), findsNothing);
  });

  testWidgets('未开启单双周的学期，下钻弹窗不显示单/双周列', (tester) async {
    await seedData(cycleMode: AcademicTermCycle.everyWeek);
    await pumpPage(tester);
    await selectJuniorStage(tester);

    await openCellDialog(tester, const ValueKey('subject-cell-s_chinese-g1'));
    // 仅「每周」一列，无「单周」「双周」。
    expect(find.text('每周'), findsWidgets);
    expect(find.text('单周'), findsNothing);
    expect(find.text('双周'), findsNothing);
    // 副标题也不含单双周配置提示。
    expect(find.text('默认录入每周节数；科目预设点击单元格设置。'), findsOneWidget);
  });

  testWidgets('逗号分组按班级顺序设置，各班不同', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    final cellKey = const ValueKey('subject-cell-s_math-g1');
    await editCellInline(tester, cellKey, '3,2');
    // 两个班值不同 → 显示「各班不同」。
    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('各班不同')),
      findsOneWidget,
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final requirements = (await tester.runAsync(
      () => repository.watchAllRequirements().first,
    ))!;
    expect(requirements.length, 2);
    expect(
      requirements
          .where((row) => row.classId == 'c1')
          .map((row) => row.lessonCount),
      everyElement(3),
    );
    expect(
      requirements
          .where((row) => row.classId == 'c2')
          .map((row) => row.lessonCount),
      everyElement(2),
    );
  });

  testWidgets('右键菜单复制与粘贴节数', (tester) async {
    var clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (message) async {
          if (message.method == 'Clipboard.setData') {
            clipboardText =
                (message.arguments as Map<String, Object?>)['text'] as String;
          } else if (message.method == 'Clipboard.getData') {
            return <String, Object?>{'text': clipboardText};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    final chineseKey = const ValueKey('subject-cell-s_chinese-g1');
    final mathKey = const ValueKey('subject-cell-s_math-g1');
    // 语文填 3|1|1，复制。
    await editCellInline(tester, chineseKey, '3|1|1');
    await tester.tap(find.byKey(chineseKey));
    await tester.pumpAndSettle();
    await openCellMenu(tester, chineseKey);
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();

    // 粘贴到数学 → 同值。
    await tester.tap(find.byKey(mathKey));
    await tester.pumpAndSettle();
    await openCellMenu(tester, mathKey);
    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(mathKey), matching: find.text('3|1|1')),
      findsOneWidget,
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final requirements = (await tester.runAsync(
      () => repository.watchAllRequirements().first,
    ))!;
    expect(requirements.length, 12); // 语文 + 数学，各 2 班 × 3 模式
    expect(
      requirements.every(
        (row) =>
            row.weekMode == WeekMode.weekly && row.lessonCount == 3 ||
            row.weekMode == WeekMode.odd && row.lessonCount == 1 ||
            row.weekMode == WeekMode.even && row.lessonCount == 1,
      ),
      isTrue,
    );
  });

  testWidgets('方向键移动选中，Ctrl+C/V 键盘复制粘贴', (tester) async {
    var clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (message) async {
          if (message.method == 'Clipboard.setData') {
            clipboardText =
                (message.arguments as Map<String, Object?>)['text'] as String;
          } else if (message.method == 'Clipboard.getData') {
            return <String, Object?>{'text': clipboardText};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);
    final mathKey = const ValueKey('subject-cell-s_math-g1');
    final chineseKey = const ValueKey('subject-cell-s_chinese-g1');
    // 数学=2，语文=3|1|1。
    await editCellInline(tester, mathKey, '2');
    await editCellInline(tester, chineseKey, '3|1|1');

    // 选中语文 → 方向下移 → 数学被选中（蓝描边）。
    await tester.tap(find.byKey(chineseKey));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final decoration =
        tester.widget<AnimatedContainer>(find.byKey(mathKey)).decoration
            as BoxDecoration;
    expect(decoration.border, Border.all(color: AppTheme.blue));

    // C 复制数学的「2」（选中态裸键 / Ctrl+C 均可）。
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(clipboardText, '2');

    // 方向上移回语文 → Ctrl+V → 语文变「2」。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(chineseKey), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('进入编辑态自动获得焦点（光标在输入框）', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    final cellKey = const ValueKey('subject-cell-s_chinese-g1');
    await tester.tap(find.byKey(cellKey));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byKey(cellKey));
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('选中态 Enter 进入编辑（全选），Delete 清空', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    final cellKey = const ValueKey('subject-cell-s_chinese-g1');
    await editCellInline(tester, cellKey, '3');

    // 单击选中 → Enter 进入内联编辑。
    await tester.tap(find.byKey(cellKey));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // 全选内容被直接输入替换 → 提交显示 5。
    await tester.enterText(find.byType(TextField), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('5')),
      findsOneWidget,
    );

    // Delete 清空 → 「—」，保存后落库为空。
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(cellKey), matching: find.text('—')),
      findsOneWidget,
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final requirements = (await tester.runAsync(
      () => repository.watchAllRequirements().first,
    ))!;
    expect(requirements, isEmpty);
  });

  testWidgets('下钻快速填入节数后矩阵更新并可保存落库', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    await openCellDialog(tester, const ValueKey('subject-cell-s_chinese-g1'));
    expect(find.text('语文 · 一年级'), findsOneWidget);

    // 每周快速填入「3,3」→ 两个班都是每周 3 节（快速填入是弹窗内最后一个输入框）。
    final fields = find.descendant(
      of: find.byType(f.FDialog),
      matching: find.byType(AppTextFormField),
    );
    await tester.enterText(fields.last, '3,3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('填入'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(f.FDialog), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();

    // 草稿生效：矩阵显示 3，页脚 3 / 20。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('subject-cell-s_chinese-g1')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(find.text('3 / 20'), findsOneWidget);

    // 页面保存后落库。
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final requirements = (await tester.runAsync(
      () => repository.watchAllRequirements().first,
    ))!;
    expect(requirements.length, 2);
    expect(
      requirements.every(
        (requirement) =>
            requirement.subjectId == 's_chinese' &&
            requirement.weekMode == WeekMode.weekly &&
            requirement.lessonCount == 3,
      ),
      isTrue,
    );
  });

  testWidgets('各班节数不同时矩阵显示「各班不同」', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    await openCellDialog(tester, const ValueKey('subject-cell-s_math-g1'));
    final fields = find.descendant(
      of: find.byType(f.FDialog),
      matching: find.byType(AppTextFormField),
    );
    // 一（1）班 每周 = fields[0]，一（2）班 每周 = fields[3]。
    await tester.enterText(fields.at(0), '4');
    await tester.enterText(fields.at(3), '2');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(f.FDialog), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('subject-cell-s_math-g1')),
        matching: find.text('各班不同'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('超出容量时保存前弹预警，可继续保存', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    await openCellDialog(tester, const ValueKey('subject-cell-s_chinese-g1'));
    final fields = find.descendant(
      of: find.byType(f.FDialog),
      matching: find.byType(AppTextFormField),
    );
    // 一（1）班每周填 25 节 > 容量 20。
    await tester.enterText(fields.at(0), '25');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(f.FDialog), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('容量超限预警'), findsOneWidget);
    expect(find.textContaining('一（1）班超 5 节'), findsOneWidget);

    await tester.tap(find.text('继续保存'));
    await tester.pumpAndSettle();
    final requirements = (await tester.runAsync(
      () => repository.watchAllRequirements().first,
    ))!;
    expect(requirements.single.lessonCount, 25);
  });

  testWidgets('添加科目后矩阵新增行', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    await tester.tap(find.text('+ 添加科目'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(f.FDialog),
            matching: find.byType(AppTextFormField),
          )
          .first,
      '心理健康',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(f.FDialog), matching: find.text('添加')),
    );
    await tester.pumpAndSettle();

    expect(find.text('心理健康'), findsOneWidget);

    // 保存后科目落库。
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final subjects = (await tester.runAsync(
      () => repository.watchSubjects().first,
    ))!;
    expect(subjects.map((subject) => subject.name), contains('心理健康'));
  });

  testWidgets('窄屏单层滚动：矩阵自然高度、无嵌套滚动异常', (tester) async {
    await seedData();
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(activeTermIdProvider.notifier).state = 't1';
    await tester.pumpWidget(_wrap(container, 't1'));
    await tester.pumpAndSettle();

    // 整页内容可滚动（单一滚动容器），矩阵与容量校验都在页面流里。
    expect(find.text('科目节数'), findsOneWidget);
    expect(find.byType(SubjectMatrix), findsOneWidget);
    expect(find.text('各年级容量校验'), findsOneWidget);
    // 矩阵行自然铺开（不内部滚动）：滚动到最底可见页脚。
    await tester.drag(find.text('各年级容量校验'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('表头/科目行/页脚横向滚动联动', (tester) async {
    await seedData();
    // 8 个年级让矩阵横向溢出（1200 宽视口）。
    for (var index = 2; index <= 9; index++) {
      await repository.saveGrade(
        GradeGroup(
          id: 'g$index',
          stageId: 'jr',
          name: '$index年级',
          sortOrder: index - 1,
        ),
      );
    }
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(activeTermIdProvider.notifier).state = 't1';
    await tester.pumpWidget(_wrap(container, 't1'));
    await tester.pumpAndSettle();
    await selectJuniorStage(tester);

    final chineseCell = find.byKey(const ValueKey('subject-cell-s_chinese-g9'));
    final mathCell = find.byKey(const ValueKey('subject-cell-s_math-g9'));
    final chineseBefore = tester.getRect(chineseCell);
    final mathBefore = tester.getRect(mathCell);

    // 拖动表头横向滚动（拖第一个可见列名，位于表头滚动区内）。
    await tester.drag(
      find.descendant(
        of: find.byType(SubjectMatrix),
        matching: find.text('一年级'),
      ),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();

    final chineseAfter = tester.getRect(chineseCell);
    final mathAfter = tester.getRect(mathCell);
    // 行随表头联动，且行与行位移一致。
    expect(chineseAfter.left, lessThan(chineseBefore.left));
    expect(
      (chineseAfter.left - chineseBefore.left) -
          (mathAfter.left - mathBefore.left),
      closeTo(0, 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('范围单选列表支持全校与学段切换', (tester) async {
    await seedData();
    // 高中部加一个年级，验证全校视图下的学段分组行。
    await repository.saveGrade(
      const GradeGroup(id: 'gh1', stageId: 'gz', name: '高一', sortOrder: 0),
    );
    await pumpPage(tester);
    await selectJuniorStage(tester);

    // 选项行：全校（含计数）与各学段。
    expect(find.textContaining('全校（'), findsOneWidget);
    expect(find.textContaining('小学部'), findsWidgets);
    expect(find.textContaining('初中部'), findsWidgets);

    // 切回全校：矩阵列 = 所有学段的年级并集，年级名按学段着色。
    await tester.tap(find.textContaining('全校'));
    await tester.pumpAndSettle();
    expect(find.text('一年级'), findsWidgets);
    expect(find.text('高一'), findsWidgets);
    // 学段分组行已按用户要求移除（用颜色区分学段），不应再出现组头。
    expect(find.text('初中部'), findsNothing);
    expect(find.text('高中部'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('矮窗口下年级选择面板内部滚动不溢出', (tester) async {
    await seedData();
    // 多加两个年级，让选择面板内容更高，矮窗口下更易触发溢出。
    await repository.saveGrade(
      const GradeGroup(id: 'g2', stageId: 'jr', name: '二年级', sortOrder: 1),
    );
    await repository.saveGrade(
      const GradeGroup(id: 'g3', stageId: 'jr', name: '三年级', sortOrder: 2),
    );
    // 宽度落在宽屏布局（>=1040），高度压到不足以容纳选择面板全部内容。
    tester.view.physicalSize = const Size(1100, 460);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(activeTermIdProvider.notifier).state = 't1';
    await tester.pumpWidget(_wrap(container, 't1'));
    await tester.pumpAndSettle();

    expect(find.text('三年级'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('班级周课时汇总被截断时悬浮显示完整内容', (tester) async {
    await seedData();
    // 一（1）班语文：单周 30 节、双周 8 节 → 汇总「单 30/20 · 双 8/20」
    // 超出 92px 年级列宽被省略号截断。
    await repository.replaceGradeRequirements(
      gradeId: 'g1',
      requirements: const [
        SubjectRequirement(
          id: 'req_odd',
          subjectId: 's_chinese',
          gradeId: 'g1',
          classId: 'c1',
          weekMode: WeekMode.odd,
          lessonCount: 30,
        ),
        SubjectRequirement(
          id: 'req_even',
          subjectId: 's_chinese',
          gradeId: 'g1',
          classId: 'c1',
          weekMode: WeekMode.even,
          lessonCount: 8,
        ),
      ],
    );
    // 高中部加一个无需求的年级：页脚汇总「0 / 20」较短、不截断。
    await repository.saveGrade(
      const GradeGroup(id: 'g2', stageId: 'jr', name: '二年级', sortOrder: 1),
    );
    await repository.saveClass(
      const ClassGroup(id: 'c_g2', gradeId: 'g2', name: '二（1）班', sortOrder: 0),
    );
    await pumpPage(tester);
    await selectJuniorStage(tester);

    // 未截断的汇总不包 Tooltip。
    final short = find.text('0 / 20');
    expect(short, findsOneWidget);
    expect(
      find.ancestor(of: short, matching: find.byType(Tooltip)),
      findsNothing,
    );

    // 被截断的汇总包 Tooltip，悬浮内容为完整文本。
    final truncated = find.text('单 30/20 · 双 8/20');
    expect(truncated, findsOneWidget);
    final tooltip = find.ancestor(
      of: truncated,
      matching: find.byType(Tooltip),
    );
    expect(tooltip, findsOneWidget);
    expect(tester.widget<Tooltip>(tooltip).message, '单 30/20 · 双 8/20');
  });

  testWidgets('科目预设四态循环并保存落库（一定排触发预警）', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    // 打开预设弹窗（默认范围 = 矩阵当前列年级）。
    await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
    await tester.pumpAndSettle();
    expect(find.text('科目预设 · 语文'), findsOneWidget);

    // 第 1 节 × 周一：自动 → 尽量排 → 一定排（两次单击）。
    final cell = find.byKey(const ValueKey('preset-cell-1-p_am-1'));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('尽量排'), findsOneWidget);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('一定排'), findsOneWidget);

    // 一定排 1 格 > 单周需求 0 节 → 保存预警（逐班列出）。
    await tester.tap(find.text('保存预设'));
    await tester.pumpAndSettle();
    expect(find.text('一定排超出需求节数'), findsOneWidget);
    expect(find.textContaining('一定排 1 格'), findsWidgets);
    await tester.tap(find.text('继续保存'));
    await tester.pumpAndSettle();

    // 摘要列更新并落库。
    expect(find.text('1 固定'), findsOneWidget);
    final presets = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(presets.length, 1);
    expect(
      presets.single,
      isA<SubjectPreset>()
          .having((row) => row.subjectId, 'subjectId', 's_chinese')
          .having((row) => row.scope, 'scope', FreeSlotScope.grade)
          .having((row) => row.scopeId, 'scopeId', 'g1')
          .having((row) => row.stageId, 'stageId', 'jr')
          .having((row) => row.weekday, 'weekday', 1)
          .having((row) => row.periodTypeId, 'periodTypeId', 'p_am')
          .having((row) => row.lessonIndex, 'lessonIndex', 1)
          .having((row) => row.value, 'value', PresetValue.must),
    );
  });

  testWidgets('科目预设常驻范围树并按学段作息切换', (tester) async {
    await seedData();
    await repository.saveGrade(
      const GradeGroup(id: 'g_gz', stageId: 'gz', name: '高中一年级', sortOrder: 0),
    );
    await repository.saveClass(
      const ClassGroup(
        id: 'c_gz',
        gradeId: 'g_gz',
        name: '高一（1）班',
        sortOrder: 0,
      ),
    );
    final highRoutine = (await repository.watchRoutine('gz').first)!;
    final highMorning = highRoutine.periodTypes.firstWhere(
      (period) => period.name == '上午',
    );
    await repository.saveRoutine(
      StageRoutine(
        stageId: 'gz',
        teachingWeekdays: const {1, 2, 3, 4, 5, 6},
        periodTypes: highRoutine.periodTypes,
        overrides: [
          RoutineOverride(
            periodTypeId: highMorning.id,
            weekday: 6,
            lessonCount: 1,
          ),
        ],
      ),
    );
    await pumpPage(tester);
    await selectJuniorStage(tester);
    await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('preset-scope-school')), findsNothing);
    expect(find.byKey(const ValueKey('preset-scope-stage-jr')), findsOneWidget);
    expect(find.byKey(const ValueKey('preset-scope-grade-g1')), findsOneWidget);
    expect(find.byKey(const ValueKey('preset-routine-stage-gz')), findsNothing);
    expect(
      tester
          .widget<AppTreeTile>(
            find.byKey(const ValueKey('preset-scope-stage-jr')),
          )
          .height,
      30,
    );
    expect(
      tester
          .widget<AppTreeTile>(
            find.byKey(const ValueKey('preset-scope-grade-g1')),
          )
          .isSelected,
      isTrue,
    );
    expect(
      tester
          .widget<AppTreeTile>(
            find.byKey(const ValueKey('preset-scope-grade-g1')),
          )
          .height,
      28,
    );
    final morningCell = find.byKey(const ValueKey('preset-cell-1-p_am-1'));
    final morningBackground = tester.widget<AnimatedContainer>(
      find.descendant(
        of: morningCell,
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(tester.getSize(morningCell).height, 44);
    expect(
      (morningBackground.decoration! as BoxDecoration).color,
      const Color(0xFFE9F0FF),
    );
    expect(
      (morningBackground.decoration! as BoxDecoration).borderRadius,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('preset-expand-grade-g1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preset-scope-class-c1')), findsOneWidget);
    expect(
      tester
          .widget<AppTreeTile>(
            find.byKey(const ValueKey('preset-scope-class-c1')),
          )
          .height,
      26,
    );

    await tester.tap(find.byKey(const ValueKey('preset-scope-stage-gz')));
    await tester.pumpAndSettle();

    expect(find.text('周六'), findsOneWidget);
    expect(
      find.byKey(ValueKey('preset-cell-6-${highMorning.id}-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('preset-cell-6-${highMorning.id}-2')),
      findsNothing,
    );

    await tester.tap(find.byKey(ValueKey('preset-cell-6-${highMorning.id}-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存预设'));
    await tester.pumpAndSettle();

    final presets = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(presets, hasLength(1));
    expect(
      presets.single,
      isA<SubjectPreset>()
          .having((row) => row.scope, 'scope', FreeSlotScope.stage)
          .having((row) => row.scopeId, 'scopeId', 'gz')
          .having((row) => row.stageId, 'stageId', 'gz')
          .having((row) => row.weekday, 'weekday', 6)
          .having((row) => row.periodTypeId, 'periodTypeId', highMorning.id)
          .having((row) => row.lessonIndex, 'lessonIndex', 1)
          .having((row) => row.value, 'value', PresetValue.prefer),
    );
  });

  testWidgets('隐藏全校入口但继续读取既有全校预设', (tester) async {
    await seedData();
    await repository.replaceSubjectPresets(
      subjectId: 's_chinese',
      termId: 't1',
      scope: FreeSlotScope.school,
      scopeId: 't1',
      stageId: 'jr',
      presets: const [
        SubjectPreset(
          id: '',
          subjectId: 's_chinese',
          scope: FreeSlotScope.school,
          scopeId: 't1',
          stageId: 'jr',
          weekday: 1,
          periodTypeId: 'p_am',
          lessonIndex: 1,
          value: PresetValue.forbid,
        ),
      ],
    );
    await pumpPage(tester);
    await selectJuniorStage(tester);
    await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('preset-scope-school')), findsNothing);
    expect(find.text('不排'), findsOneWidget);
  });

  testWidgets('科目预设在年级和班级范围继承较宽范围设置', (tester) async {
    await seedData();
    await repository.replaceSubjectPresets(
      subjectId: 's_chinese',
      termId: 't1',
      scope: FreeSlotScope.grade,
      scopeId: 'g1',
      stageId: 'jr',
      presets: const [
        SubjectPreset(
          id: '',
          subjectId: 's_chinese',
          scope: FreeSlotScope.grade,
          scopeId: 'g1',
          stageId: 'jr',
          weekday: 1,
          periodTypeId: 'p_am',
          lessonIndex: 1,
          value: PresetValue.prefer,
        ),
      ],
    );
    await pumpPage(tester);
    await selectJuniorStage(tester);
    await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
    await tester.pumpAndSettle();
    expect(find.text('尽量排'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('preset-expand-grade-g1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-scope-class-c1')));
    await tester.pumpAndSettle();
    expect(find.text('尽量排'), findsOneWidget);
  });

  testWidgets('科目预设显示免任课格且不能设置预排', (tester) async {
    await seedData();
    await repository.saveFreeSlot(
      const FreeSlot(
        id: 'free_g1_mon_1',
        scope: FreeSlotScope.grade,
        scopeId: 'g1',
        stageId: 'jr',
        periodTypeId: 'p_am',
        weekday: 1,
        lessonIndex: 1,
        label: FreeSlotLabels.none,
      ),
    );
    await pumpPage(tester);
    await selectJuniorStage(tester);
    await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
    await tester.pumpAndSettle();

    final exemptCell = find.byKey(const ValueKey('preset-cell-1-p_am-1'));
    expect(exemptCell, findsOneWidget);
    expect(find.text(FreeSlotLabels.none), findsOneWidget);
    await tester.tap(exemptCell);
    await tester.pumpAndSettle();
    expect(find.text(FreeSlotLabels.none), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('preset-expand-grade-g1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-scope-class-c1')));
    await tester.pumpAndSettle();
    expect(find.text(FreeSlotLabels.none), findsOneWidget);
    await tester.tap(exemptCell);
    await tester.pumpAndSettle();
    expect(find.text(FreeSlotLabels.none), findsOneWidget);

    await tester.tap(find.text('保存预设'));
    await tester.pumpAndSettle();
    final presets = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(presets, isEmpty);
  });

  testWidgets('班级科目预设可用自动清除继承并用一定排覆盖', (tester) async {
    await seedData();
    await repository.saveGrade(
      const GradeGroup(id: 'g2', stageId: 'jr', name: '二年级', sortOrder: 1),
    );
    await repository.saveClass(
      const ClassGroup(id: 'c3', gradeId: 'g2', name: '二（1）班', sortOrder: 0),
    );
    await repository.replaceSubjectPresets(
      subjectId: 's_chinese',
      termId: 't1',
      scope: FreeSlotScope.grade,
      scopeId: 'g1',
      stageId: 'jr',
      presets: const [
        SubjectPreset(
          id: '',
          subjectId: 's_chinese',
          scope: FreeSlotScope.grade,
          scopeId: 'g1',
          stageId: 'jr',
          weekday: 1,
          periodTypeId: 'p_am',
          lessonIndex: 1,
          value: PresetValue.forbid,
        ),
        SubjectPreset(
          id: '',
          subjectId: 's_chinese',
          scope: FreeSlotScope.grade,
          scopeId: 'g1',
          stageId: 'jr',
          weekday: 2,
          periodTypeId: 'p_am',
          lessonIndex: 1,
          value: PresetValue.prefer,
        ),
      ],
    );
    await repository.replaceSubjectPresets(
      subjectId: 's_chinese',
      termId: 't1',
      scope: FreeSlotScope.grade,
      scopeId: 'g2',
      stageId: 'jr',
      presets: const [
        SubjectPreset(
          id: '',
          subjectId: 's_chinese',
          scope: FreeSlotScope.grade,
          scopeId: 'g2',
          stageId: 'jr',
          weekday: 3,
          periodTypeId: 'p_am',
          lessonIndex: 1,
          value: PresetValue.forbid,
        ),
      ],
    );
    await pumpPage(tester);
    await selectJuniorStage(tester);

    Future<void> openClassPreset() async {
      await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preset-expand-grade-g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preset-scope-class-c1')));
      await tester.pumpAndSettle();
    }

    await openClassPreset();
    final classCell = find.byKey(const ValueKey('preset-cell-1-p_am-1'));
    // 仅继承本年级规则，不应继承同学段另一个年级的“不排”。
    expect(find.text('不排'), findsOneWidget);
    expect(find.text('尽量排'), findsOneWidget);

    // 从继承的“不排”点一次回到“自动”，保存后应显式遮蔽年级规则。
    await tester.tap(classCell);
    await tester.pumpAndSettle();
    expect(find.text('不排'), findsNothing);
    await tester.tap(find.text('保存预设'));
    await tester.pumpAndSettle();
    expect(find.textContaining('各班不同'), findsOneWidget);
    var presets = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(
      presets.any(
        (preset) =>
            preset.scope == FreeSlotScope.grade &&
            preset.scopeId == 'g1' &&
            preset.value == PresetValue.forbid,
      ),
      isTrue,
    );
    expect(
      presets.any(
        (preset) =>
            preset.scope == FreeSlotScope.grade &&
            preset.scopeId == 'g1' &&
            preset.weekday == 2 &&
            preset.value == PresetValue.prefer,
      ),
      isTrue,
    );
    expect(
      presets.any(
        (preset) =>
            preset.scope == FreeSlotScope.schoolClass &&
            preset.scopeId == 'c1' &&
            preset.value == PresetValue.auto,
      ),
      isTrue,
    );
    expect(
      presets.where(
        (preset) =>
            preset.scope == FreeSlotScope.schoolClass && preset.scopeId == 'c1',
      ),
      hasLength(1),
    );

    // 再打开时自动覆盖仍生效，班级可继续改成“一定排”。
    await openClassPreset();
    expect(find.text('不排'), findsNothing);
    expect(find.text('尽量排'), findsOneWidget);
    await tester.tap(classCell);
    await tester.pumpAndSettle();
    await tester.tap(classCell);
    await tester.pumpAndSettle();
    expect(find.text('一定排'), findsOneWidget);
    await tester.tap(find.text('保存预设'));
    await tester.pumpAndSettle();
    if (find.text('一定排超出需求节数').evaluate().isNotEmpty) {
      await tester.tap(find.text('继续保存'));
      await tester.pumpAndSettle();
    }

    presets = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(
      presets.any(
        (preset) =>
            preset.scope == FreeSlotScope.grade &&
            preset.scopeId == 'g1' &&
            preset.value == PresetValue.forbid,
      ),
      isTrue,
    );
    expect(
      presets.where(
        (preset) =>
            preset.scope == FreeSlotScope.schoolClass && preset.scopeId == 'c1',
      ),
      hasLength(1),
    );
    expect(
      presets.any(
        (preset) =>
            preset.scope == FreeSlotScope.schoolClass &&
            preset.scopeId == 'c1' &&
            preset.value == PresetValue.must,
      ),
      isTrue,
    );
  });

  testWidgets('科目预设列表可暂存单条删除，保存后仅删除该预设', (tester) async {
    await seedData();
    await repository.saveTerm(
      AcademicTerm(
        id: 't0',
        title: '2025 春季',
        academicYear: '2024-2025',
        semesterLabel: '第二学期',
        firstTeachingWeekStart: DateTime(2025, 2, 17),
        teachingWeekCount: 18,
        cycleMode: AcademicTermCycle.alternating,
        createdAt: DateTime(2025, 2, 1),
      ),
    );
    await repository.saveStage(
      const SchoolStage(
        id: 'old_jr',
        termId: 't0',
        name: '旧学期初中部',
        sortOrder: 1,
      ),
    );
    await repository.replaceSubjectPresets(
      subjectId: 's_chinese',
      termId: 't1',
      scope: FreeSlotScope.grade,
      scopeId: 'g1',
      stageId: 'jr',
      presets: const [
        SubjectPreset(
          id: '',
          subjectId: 's_chinese',
          scope: FreeSlotScope.grade,
          scopeId: 'g1',
          stageId: 'jr',
          weekday: 1,
          periodTypeId: 'p_am',
          lessonIndex: 1,
          value: PresetValue.prefer,
        ),
      ],
    );
    await repository.replaceSubjectPresets(
      subjectId: 's_chinese',
      termId: 't0',
      scope: FreeSlotScope.stage,
      scopeId: 'old_jr',
      stageId: 'old_jr',
      presets: const [
        SubjectPreset(
          id: '',
          subjectId: 's_chinese',
          scope: FreeSlotScope.stage,
          scopeId: 'old_jr',
          stageId: 'old_jr',
          weekday: 1,
          periodTypeId: 'p_am',
          lessonIndex: 3,
          value: PresetValue.forbid,
        ),
      ],
    );
    await repository.replaceSubjectPresets(
      subjectId: 's_chinese',
      termId: 't1',
      scope: FreeSlotScope.schoolClass,
      scopeId: 'c1',
      stageId: 'jr',
      presets: const [
        SubjectPreset(
          id: '',
          subjectId: 's_chinese',
          scope: FreeSlotScope.schoolClass,
          scopeId: 'c1',
          stageId: 'jr',
          weekday: 2,
          periodTypeId: 'p_am',
          lessonIndex: 2,
          value: PresetValue.must,
        ),
      ],
    );
    await repository.replaceSubjectPresets(
      subjectId: 's_math',
      termId: 't1',
      scope: FreeSlotScope.grade,
      scopeId: 'g1',
      stageId: 'jr',
      presets: const [
        SubjectPreset(
          id: '',
          subjectId: 's_math',
          scope: FreeSlotScope.grade,
          scopeId: 'g1',
          stageId: 'jr',
          weekday: 1,
          periodTypeId: 'p_am',
          lessonIndex: 2,
          value: PresetValue.forbid,
        ),
      ],
    );
    await pumpPage(tester);
    await selectJuniorStage(tester);
    await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
    await tester.pumpAndSettle();

    expect(find.text('当前学期全部预设'), findsOneWidget);
    expect(find.text('清除所有预设'), findsNothing);
    expect(find.text('2 项'), findsOneWidget);
    expect(find.text('一年级'), findsWidgets);
    expect(find.text('初中部 · 一年级 · 一（1）班'), findsOneWidget);

    final beforeDelete = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(beforeDelete, hasLength(4));

    final gradeDelete = find.byKey(
      const ValueKey('preset-delete-grade-g1-jr-1-p_am-1'),
    );
    expect(gradeDelete, findsOneWidget);
    await tester.tap(gradeDelete);
    await tester.pumpAndSettle();
    expect(find.text('2 项'), findsOneWidget);
    expect(find.text('待删除'), findsOneWidget);
    final afterStaging = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(afterStaging, hasLength(4));
    await tester.tap(gradeDelete);
    await tester.pumpAndSettle();
    expect(find.text('待删除'), findsNothing);
    await tester.tap(gradeDelete);
    await tester.pumpAndSettle();
    expect(find.text('待删除'), findsOneWidget);

    // 取消弹窗会丢弃暂存删除。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    var presets = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(presets, hasLength(4));

    await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
    await tester.pumpAndSettle();
    final classDelete = find.byKey(
      const ValueKey('preset-delete-schoolClass-c1-jr-2-p_am-2'),
    );
    expect(classDelete, findsOneWidget);
    await tester.tap(classDelete);
    await tester.pumpAndSettle();
    expect(find.text('2 项'), findsOneWidget);
    await tester.tap(find.text('保存预设'));
    await tester.pumpAndSettle();

    presets = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(presets, hasLength(3));
    expect(
      presets.any(
        (preset) =>
            preset.subjectId == 's_chinese' &&
            preset.stageId == 'jr' &&
            preset.scope == FreeSlotScope.grade,
      ),
      isTrue,
    );
    expect(
      presets.any(
        (preset) =>
            preset.subjectId == 's_chinese' &&
            preset.stageId == 'jr' &&
            preset.scope == FreeSlotScope.schoolClass,
      ),
      isFalse,
    );
    expect(
      presets.any(
        (preset) =>
            preset.subjectId == 's_chinese' && preset.stageId == 'old_jr',
      ),
      isTrue,
    );
    expect(
      presets.any(
        (preset) => preset.subjectId == 's_math' && preset.stageId == 'jr',
      ),
      isTrue,
    );
  });

  testWidgets('切换预排范围保留并保存各范围草稿', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);
    await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
    await tester.pumpAndSettle();

    final gradeCell = find.byKey(const ValueKey('preset-cell-1-p_am-1'));
    await tester.tap(gradeCell);
    await tester.pumpAndSettle();
    expect(find.text('尽量排'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('preset-expand-grade-g1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-scope-class-c1')));
    await tester.pumpAndSettle();
    final classCell = find.byKey(const ValueKey('preset-cell-2-p_am-1'));
    await tester.tap(classCell);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('preset-scope-grade-g1')));
    await tester.pumpAndSettle();
    expect(find.text('尽量排'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('preset-scope-class-c1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preset-cell-2-p_am-1')), findsOneWidget);
    expect(find.text('尽量排'), findsOneWidget);

    await tester.tap(find.text('保存预设'));
    await tester.pumpAndSettle();
    final presets = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(presets, hasLength(2));
    expect(
      presets.any(
        (preset) =>
            preset.scope == FreeSlotScope.grade &&
            preset.scopeId == 'g1' &&
            preset.weekday == 1 &&
            preset.value == PresetValue.prefer,
      ),
      isTrue,
    );
    expect(
      presets.any(
        (preset) =>
            preset.scope == FreeSlotScope.schoolClass &&
            preset.scopeId == 'c1' &&
            preset.weekday == 2 &&
            preset.value == PresetValue.prefer,
      ),
      isTrue,
    );
  });

  testWidgets('班级预设容量警告只检查当前班级', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);
    await tester.tap(find.byKey(const ValueKey('preset-summary-s_chinese')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-expand-grade-g1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset-scope-class-c1')));
    await tester.pumpAndSettle();

    final cell = find.byKey(const ValueKey('preset-cell-1-p_am-1'));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存预设'));
    await tester.pumpAndSettle();

    expect(find.textContaining('一（1）班单周需求'), findsOneWidget);
    expect(find.textContaining('一（2）班单周需求'), findsNothing);
  });

  testWidgets('不排不触发容量预警，摘要显示不排', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    await tester.tap(find.byKey(const ValueKey('preset-summary-s_math')));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('preset-cell-2-p_am-1'));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('不排'), findsOneWidget);

    await tester.tap(find.text('保存预设'));
    await tester.pumpAndSettle();
    expect(find.text('一定排超出需求节数'), findsNothing);
    expect(find.text('1 不排'), findsOneWidget);

    final presets = (await tester.runAsync(
      () => repository.watchAllPresets().first,
    ))!;
    expect(presets.single.value, PresetValue.forbid);
  });

  testWidgets('同名班级（跨学段）下配对课程不崩溃', (tester) async {
    await seedData();
    // 高中部放一个与初中部同名的班级，班级下拉标签需消歧。
    await repository.saveStage(
      const SchoolStage(id: 'gz', termId: 't1', name: '高中部', sortOrder: 2),
    );
    await repository.saveGrade(
      const GradeGroup(id: 'gh1', stageId: 'gz', name: '一年级', sortOrder: 0),
    );
    await repository.saveClasses([
      const ClassGroup(
        id: 'gz_c1',
        gradeId: 'gh1',
        name: '一（1）班',
        sortOrder: 0,
      ),
    ]);
    await pumpPage(tester);

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配对课程'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('还没有配对。新增配对后，两门课将占用同一时段。'), findsOneWidget);
  });

  testWidgets('配对课程可新增并解除，立即落库', (tester) async {
    await seedData();
    await pumpPage(tester);
    await selectJuniorStage(tester);

    // 更多菜单 → 配对课程。
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配对课程'));
    await tester.pumpAndSettle();
    expect(find.text('还没有配对。新增配对后，两门课将占用同一时段。'), findsOneWidget);

    // 直接驱动三个下拉的 onChanged：班级 / 科目A（单周）/ 科目B（双周）。
    final selects = find.descendant(
      of: find.byType(f.FDialog),
      matching: find.byType(AppSelectField<String>),
    );
    tester.widget<AppSelectField<String>>(selects.at(0)).onChanged('c1');
    tester.widget<AppSelectField<String>>(selects.at(1)).onChanged('s_math');
    tester.widget<AppSelectField<String>>(selects.at(2)).onChanged('s_chinese');
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(find.textContaining('数学（单周）'), findsOneWidget);
    expect(find.textContaining('语文（双周）'), findsOneWidget);
    var pairings = (await tester.runAsync(
      () => repository.watchAllPairings().first,
    ))!;
    expect(pairings.length, 1);
    expect(pairings.single.classId, 'c1');
    expect(pairings.single.oddSubjectId, 's_math');
    expect(pairings.single.evenSubjectId, 's_chinese');

    // 解除配对立即落库。
    await tester.tap(find.text('解除配对'));
    await tester.pumpAndSettle();
    pairings = (await tester.runAsync(
      () => repository.watchAllPairings().first,
    ))!;
    expect(pairings, isEmpty);
    expect(find.textContaining('数学（单周）'), findsNothing);
  });
}
