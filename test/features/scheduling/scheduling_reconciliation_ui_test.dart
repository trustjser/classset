import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/schedule_preferences.dart';
import 'package:class_set/domain/models/schedule_condition.dart';
import 'package:class_set/domain/models/schedule_lock.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:class_set/features/scheduling/scheduling_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

class _PendingController extends SchedulingController {
  _PendingController(
    DriftSchoolRepository repository,
    SchedulingSnapshot baseline,
    SchedulingSnapshot current,
  ) : super(repository, baseline.term.id) {
    state = SchedulingState(
      status: SchedulingStatus.ready,
      snapshot: baseline,
      pendingBaseline: baseline,
      currentSnapshot: current,
    );
  }

  @override
  Future<void> refresh({bool preserveHistory = false}) async {}
}

class _ReadyController extends SchedulingController {
  _ReadyController(
    DriftSchoolRepository repository,
    SchedulingSnapshot snapshot,
  ) : super(repository, snapshot.term.id) {
    state = SchedulingState(status: SchedulingStatus.ready, snapshot: snapshot);
  }

  @override
  Future<void> refresh({bool preserveHistory = false}) async {}

  List<ScheduleCondition>? savedConditions;
  ScheduleLock? savedLock;

  @override
  Future<void> setLock(ScheduleLock lock, {required bool enabled}) async {
    savedLock = lock;
  }

  @override
  Future<void> saveConfiguration({
    required List<ScheduleCondition> conditions,
    required SchedulePreferences preferences,
  }) async {
    savedConditions = conditions;
  }
}

class _PublishedVersionController extends _ReadyController {
  _PublishedVersionController(
    super.repository,
    super.snapshot,
    SchedulingSnapshot published,
  ) {
    state = state.copyWith(
      publishedSchedule: PublishedTimetable(
        snapshot: published,
        commonPeriods: const {},
      ),
    );
  }
}

class _PublishController extends _ReadyController {
  _PublishController(
    DriftSchoolRepository repository,
    SchedulingSnapshot snapshot,
  ) : super(repository, snapshot) {
    state = state.copyWith(items: snapshot.existingItems);
  }

  int publishCount = 0;

  @override
  Future<bool> publish({String? expectedFingerprint}) async {
    expect(expectedFingerprint, state.snapshot!.inputFingerprint);
    publishCount++;
    state = state.copyWith(
      publishedSchedule: PublishedTimetable(
        snapshot: state.snapshot!.copyWith(
          existingItems: state.items.where((item) => item.isPlaced).toList(),
        ),
        commonPeriods: const {},
      ),
    );
    return true;
  }
}

void main() {
  testWidgets('正式版与草稿版班级课程表使用相同班级顺序', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    final term = AcademicTerm(
      id: 't',
      title: '学期',
      academicYear: '2026',
      semesterLabel: '秋',
      firstTeachingWeekStart: null,
      teachingWeekCount: 20,
      createdAt: DateTime(2026),
    );
    const stages = [
      SchoolStage(id: 'stage', termId: 't', name: '小学部', sortOrder: 0),
    ];
    const grades = [
      GradeGroup(id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0),
    ];
    const firstClass = ClassGroup(
      id: 'class-1',
      gradeId: 'grade',
      name: '一班',
      sortOrder: 0,
    );
    const secondClass = ClassGroup(
      id: 'class-2',
      gradeId: 'grade',
      name: '二班',
      sortOrder: 1,
    );
    final draft = SchedulingSnapshot(
      term: term,
      inputFingerprint: 'draft',
      stages: stages,
      grades: grades,
      classes: const [secondClass, firstClass],
    );
    final published = SchedulingSnapshot(
      term: term,
      inputFingerprint: 'published',
      stages: stages,
      grades: grades,
      classes: const [firstClass, secondClass],
    );
    final controller = _PublishedVersionController(
      repository,
      draft,
      published,
    );
    final container = ProviderContainer(
      overrides: [
        schoolRepositoryProvider.overrideWithValue(repository),
        schedulingControllerProvider('t').overrideWith((ref) => controller),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => f.FTheme(
            data: AppTheme.foruiFor(false),
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: SchedulingPage(termId: 't')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selector = find.byKey(const ValueKey('schedule-class-selector'));
    List<String> optionIds() =>
        tester.widget<AppSelectField<String>>(selector).items.values.toList();

    expect(optionIds(), ['class-2', 'class-1']);
    await tester.tap(find.text('草稿版'));
    await tester.pumpAndSettle();
    expect(optionIds(), ['class-2', 'class-1']);
  });

  testWidgets('确认发布后切换到只读正式版，草稿仍可继续排课', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    const placed = ScheduleItem(
      id: 'placed',
      termId: 't',
      assignmentId: 'assignment',
      classId: 'class',
      teacherId: 'teacher',
      subjectId: 'subject',
      weekMode: WeekMode.weekly,
      position: SchedulePosition(
        stageId: 'stage',
        weekday: 1,
        periodTypeId: 'period',
        lessonIndex: 1,
      ),
    );
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
      inputFingerprint: 'draft',
      existingItems: [
        placed,
        const ScheduleItem(
          id: 'unplaced',
          termId: 't',
          assignmentId: 'assignment',
          classId: 'class',
          teacherId: 'teacher',
          subjectId: 'subject',
          weekMode: WeekMode.weekly,
        ),
      ],
    );
    final controller = _PublishController(repository, snapshot);
    final container = ProviderContainer(
      overrides: [
        schoolRepositoryProvider.overrideWithValue(repository),
        schedulingControllerProvider('t').overrideWith((ref) => controller),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => f.FTheme(
            data: AppTheme.foruiFor(false),
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: SchedulingPage(termId: 't')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('正式版'));
    await tester.pumpAndSettle();
    expect(find.text('尚未发布正式课表'), findsOneWidget);
    expect(find.text('自动排课'), findsNothing);
    await tester.tap(find.text('前往草稿排课'));
    await tester.pumpAndSettle();
    expect(find.text('自动排课'), findsOneWidget);
    final courseTab = find.text('班级课程表');
    final versionTab = find.text('草稿版');
    final versionControl = find.byKey(
      const ValueKey('schedule-version-control'),
    );
    expect(tester.getSize(versionControl).height, lessThanOrEqualTo(34));
    expect(
      find.ancestor(
        of: find.text('发布为正式版'),
        matching: find.byType(AppGhostButton),
      ),
      findsOneWidget,
    );
    expect(
      tester.getCenter(versionTab).dy,
      closeTo(tester.getCenter(courseTab).dy, 12),
    );
    expect(
      tester.getTopLeft(versionTab).dx,
      greaterThan(tester.getTopRight(courseTab).dx),
    );

    tester.view.physicalSize = const Size(460, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('正式版').hitTestable(), findsOneWidget);
    expect(find.text('发布为正式版').hitTestable(), findsOneWidget);

    await tester.tap(find.text('发布为正式版'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还有 1 节暂放课程'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.publishCount, 0);

    await tester.tap(find.text('发布为正式版'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认发布'));
    await tester.pumpAndSettle();
    expect(controller.publishCount, 1);
    expect(find.text('仅供查看和导出'), findsOneWidget);
    expect(find.text('自动排课'), findsNothing);
    expect(find.text('规则'), findsNothing);
    expect(find.text('导出'), findsOneWidget);

    await tester.tap(find.text('草稿版'));
    await tester.pumpAndSettle();
    expect(find.text('自动排课'), findsOneWidget);
  });

  testWidgets('待协调时可以继续查看和编辑规则，并主动打开或关闭协调', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
    final term = AcademicTerm(
      id: 't',
      title: '学期',
      academicYear: '2026',
      semesterLabel: '秋',
      firstTeachingWeekStart: null,
      teachingWeekCount: 20,
      createdAt: DateTime(2026),
    );
    final baseline = SchedulingSnapshot(term: term, inputFingerprint: 'before');
    final current = SchedulingSnapshot(
      term: term,
      inputFingerprint: 'after',
      preferences: const SchedulePreferences(
        strength: ScheduleStrength.high,
        protectLunchBreak: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        schoolRepositoryProvider.overrideWithValue(repository),
        schedulingControllerProvider('t').overrideWith(
          (ref) => _PendingController(repository, baseline, current),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => f.FTheme(
            data: AppTheme.foruiFor(false),
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: SchedulingPage(termId: 't')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-reconciliation-overlay')),
      findsNothing,
    );
    expect(find.text('班级课程表'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    await tester.tap(find.text('规则'));
    await tester.pumpAndSettle();
    // 规则弹窗已改为右侧抽屉，排课偏好内联展示，不再是二级弹窗。
    expect(find.text('排课偏好与规则'), findsOneWidget);
    expect(find.text('排课策略'), findsOneWidget);
    expect(find.text('附加约束'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('schedule-reconciliation-open')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-reconciliation-overlay')),
      findsOneWidget,
    );
    await tester.tap(find.text('暂不协调'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('schedule-reconciliation-overlay')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('schedule-reconciliation-open')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('排课弹窗按分区展示，窄窗口中仍可操作', (tester) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
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
        SchoolStage(id: 'stage', termId: 't', name: '小学部', sortOrder: 0),
      ],
      grades: const [
        GradeGroup(id: 'grade', stageId: 'stage', name: '一年级', sortOrder: 0),
      ],
      classes: const [
        ClassGroup(id: 'class', gradeId: 'grade', name: '一班', sortOrder: 0),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        schoolRepositoryProvider.overrideWithValue(repository),
        schedulingControllerProvider('t')
            .overrideWith((ref) => _ReadyController(repository, snapshot)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => f.FTheme(
            data: AppTheme.foruiFor(false),
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: SchedulingPage(termId: 't')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自动排课'));
    await tester.pumpAndSettle();
    expect(find.text('排课前检查'), findsOneWidget);
    expect(find.text('排课设置'), findsOneWidget);
    expect(find.text('已选 0 / 1 个班级'), findsOneWidget);
    await tester.tap(find.text('小学部').last);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 / 1 个班级'), findsOneWidget);
    expect(find.text('选择具体班级'), findsOneWidget);
    await tester.tap(find.text('选择具体班级'));
    await tester.pumpAndSettle();
    expect(find.text('逐班选择 · 1/1 个班级'), findsOneWidget);
    await tester.ensureVisible(find.text('取消全选'));
    await tester.tap(find.text('取消全选'));
    await tester.pumpAndSettle();
    expect(find.text('逐班选择 · 0/1 个班级'), findsOneWidget);
    await tester.ensureVisible(find.text('全选'));
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('逐班选择 · 1/1 个班级'), findsOneWidget);
    await tester.ensureVisible(find.text('小学部').last);
    await tester.tap(find.text('小学部').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('取消学段全选'));
    await tester.tap(find.text('取消学段全选'));
    await tester.pumpAndSettle();
    expect(find.text('逐班选择 · 0/1 个班级'), findsOneWidget);
    await tester.ensureVisible(find.text('全选学段'));
    await tester.tap(find.text('全选学段'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('取消年级全选'));
    await tester.tap(find.text('取消年级全选'));
    await tester.pumpAndSettle();
    expect(find.text('逐班选择 · 0/1 个班级'), findsOneWidget);
    await tester.ensureVisible(find.text('全选年级'));
    await tester.tap(find.text('全选年级'));
    await tester.pumpAndSettle();
    expect(find.text('逐班选择 · 1/1 个班级'), findsOneWidget);
    await tester.ensureVisible(find.byType(FilterChip));
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(find.text('逐班选择 · 0/1 个班级'), findsOneWidget);
    tester.view.physicalSize = const Size(640, 650);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('固定随机种子'));
    await tester.tap(find.text('固定随机种子'));
    await tester.pumpAndSettle();
    expect(find.text('随机种子'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(640, 650);
    await tester.pumpAndSettle();
    await tester.tap(find.text('规则'));
    await tester.pumpAndSettle();
    // 偏好已并入抽屉首段，三段分区应在同一浮层内可见。
    expect(find.text('排课偏好与规则'), findsOneWidget);
    expect(find.byType(AppDrawerSurface), findsOneWidget);
    expect(find.text('排课策略'), findsOneWidget);
    expect(find.text('附加约束'), findsOneWidget);
    expect(find.text('自定义硬条件'), findsOneWidget);
    expect(find.text('锁定已有课表'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('添加硬条件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加硬条件'));
    await tester.pumpAndSettle();
    expect(find.text('条件与对象'), findsOneWidget);
    expect(find.text('节数限制'), findsOneWidget);
    expect(find.text('请选择对象'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('硬条件对象及时段可搜索并按学段区分，保存对应标识', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
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
        SchoolStage(id: 'primary', termId: 't', name: '小学部', sortOrder: 0),
        SchoolStage(id: 'middle', termId: 't', name: '初中部', sortOrder: 1),
      ],
      subjects: const [
        Subject(
          id: 'private_subject_0',
          name: '数学',
          shortName: '数',
          sortOrder: 0,
        ),
        Subject(
          id: 'private_subject_1',
          name: '语文',
          shortName: '语',
          sortOrder: 1,
        ),
        Subject(
          id: 'private_subject_2',
          name: '数学',
          shortName: '数',
          sortOrder: 2,
        ),
      ],
      teachers: const [
        Teacher(
          id: 'teacher1',
          name: '王老师',
          shortName: '王',
          sortOrder: 0,
          displayQualifier: '小学',
        ),
        Teacher(
          id: 'teacher2',
          name: '王老师',
          shortName: '王',
          sortOrder: 1,
          displayQualifier: '初中',
        ),
      ],
      routines: const [
        StageRoutine(
          stageId: 'primary',
          teachingWeekdays: {1},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'private_primary_am',
              name: '上午时段',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
        ),
        StageRoutine(
          stageId: 'middle',
          teachingWeekdays: {1},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'private_middle_am',
              name: '上午时段',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        schoolRepositoryProvider.overrideWithValue(repository),
        schedulingControllerProvider('t')
            .overrideWith((ref) => _ReadyController(repository, snapshot)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => f.FTheme(
            data: AppTheme.foruiFor(false),
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: SchedulingPage(termId: 't')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加硬条件'));
    await tester.pumpAndSettle();
    final target = find.byWidgetPredicate(
      (widget) => widget is AppSelectField<String> && widget.label == '对象',
    );
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text('搜索科目或教师'), findsOneWidget);
    expect(find.textContaining('private_subject_0'), findsNothing);
    await tester.tapAt(tester.getCenter(find.text('搜索科目或教师')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.focusNode.hasFocus,
      ),
      '数学',
    );
    await tester.pumpAndSettle();
    expect(find.text('数学（1）'), findsOneWidget);
    expect(find.text('数学（2）'), findsOneWidget);
    await tester.tap(find.text('数学（2）'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppSelectField<String>>(target).value,
      'private_subject_2',
    );
    final period = find.byWidgetPredicate(
      (widget) => widget is AppSelectField<String> && widget.label == '时段',
    );
    await tester.tap(period);
    await tester.pumpAndSettle();
    expect(find.text('搜索学段或时段'), findsOneWidget);
    expect(find.text('小学部 · 上午时段'), findsOneWidget);
    expect(find.text('初中部 · 上午时段'), findsOneWidget);
    expect(find.textContaining('private_middle_am'), findsNothing);
    await tester.tapAt(tester.getCenter(find.text('搜索学段或时段')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.focusNode.hasFocus,
      ),
      '初中',
    );
    await tester.pumpAndSettle();
    expect(find.text('小学部 · 上午时段'), findsNothing);
    await tester.tap(find.text('初中部 · 上午时段').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppSelectField<String>>(period).value,
      'private_middle_am',
    );
    final maximum = find.byWidgetPredicate(
      (widget) =>
          widget is AppTextFormField && widget.decoration.labelText == '最多节数',
    );
    await tester.ensureVisible(maximum);
    await tester.enterText(
      find.descendant(of: maximum, matching: find.byType(EditableText)),
      '2',
    );
    await tester.tap(find.text('添加').last);
    await tester.pumpAndSettle();
    // 草稿态：编辑弹窗只更新抽屉草稿，点「保存」才提交到 controller。
    expect(find.text('有未保存的修改'), findsOneWidget);
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    final saved = (container.read(
      schedulingControllerProvider('t').notifier,
    ) as _ReadyController).savedConditions!.single;
    expect(saved.targetId, 'private_subject_2');
    expect(saved.periodTypeId, 'private_middle_am');
    await tester.tap(find.text('规则'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加硬条件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定时段节数'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教师互斥').last);
    await tester.pumpAndSettle();
    final other = find.byWidgetPredicate(
      (widget) => widget is AppSelectField<String> && widget.label == '对象 B',
    );
    await tester.tap(other);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text('搜索科目或教师')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is EditableText && widget.focusNode.hasFocus,
      ),
      '初中',
    );
    await tester.pumpAndSettle();
    expect(find.text('王老师（小学）'), findsNothing);
    await tester.tap(find.text('王老师（初中）'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppSelectField<String>>(other).value, 'teacher2');
    expect(tester.takeException(), isNull);
  });
  testWidgets('锁定班级和教师可搜索并保存正确对象', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSchoolRepository(database);
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
        SchoolStage(id: 's1', termId: 't', name: '小学部', sortOrder: 0),
        SchoolStage(id: 's2', termId: 't', name: '初中部', sortOrder: 1),
      ],
      grades: const [
        GradeGroup(id: 'g1', stageId: 's1', name: '一年级', sortOrder: 0),
        GradeGroup(id: 'g2', stageId: 's2', name: '七年级', sortOrder: 0),
      ],
      classes: const [
        ClassGroup(
          id: 'private_class_1',
          gradeId: 'g1',
          name: '1 班',
          sortOrder: 0,
        ),
        ClassGroup(
          id: 'private_class_2',
          gradeId: 'g2',
          name: '1 班',
          sortOrder: 0,
        ),
      ],
      teachers: const [
        Teacher(
          id: 'private_teacher_1',
          name: '王老师',
          shortName: '王',
          sortOrder: 0,
          displayQualifier: '小学',
        ),
        Teacher(
          id: 'private_teacher_2',
          name: '王老师',
          shortName: '王',
          sortOrder: 1,
          displayQualifier: '初中',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        schoolRepositoryProvider.overrideWithValue(repository),
        schedulingControllerProvider('t')
            .overrideWith((ref) => _ReadyController(repository, snapshot)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => f.FTheme(
            data: AppTheme.foruiFor(false),
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: SchedulingPage(termId: 't')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('规则'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加锁定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加锁定'));
    await tester.pumpAndSettle();
    expect(find.text('选择要锁定的班级或教师，重新排课时将保留已有课程位置。'), findsOneWidget);
    final selector = find.byWidgetPredicate(
      (w) => w is AppSelectField<String> && w.label == '选择对象',
    );
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.text('搜索班级'), findsOneWidget);
    expect(find.text('小学部 · 一年级 · 1 班'), findsOneWidget);
    expect(find.text('初中部 · 七年级 · 1 班'), findsOneWidget);
    expect(find.textContaining('private_class'), findsNothing);
    await tester.tapAt(tester.getCenter(find.text('搜索班级')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus),
      '七年级',
    );
    await tester.pumpAndSettle();
    expect(find.text('小学部 · 一年级 · 1 班'), findsNothing);
    await tester.tap(find.text('初中部 · 七年级 · 1 班'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('锁定').last);
    await tester.pumpAndSettle();
    // 草稿态：添加锁定先进草稿，点「保存」才提交。
    expect(find.text('有未保存的修改'), findsOneWidget);
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    final controller = container.read(
      schedulingControllerProvider('t').notifier,
    ) as _ReadyController;
    expect(controller.savedLock?.targetId, 'private_class_2');
    expect(controller.savedLock?.scope, ScheduleLockScope.schoolClass);
    // 重新打开抽屉，继续窄窗口下的第二次添加。
    await tester.tap(find.text('规则'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(640, 650);
    await tester.pumpAndSettle();
    // 窄窗口下抽屉内容需要滚动才能操作末段按钮。
    await tester.ensureVisible(find.text('添加锁定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加锁定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('班级').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('教师').last);
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    expect(find.text('搜索教师'), findsOneWidget);
    expect(find.text('王老师（初中）'), findsOneWidget);
    expect(find.textContaining('private_teacher'), findsNothing);
    await tester.tapAt(tester.getCenter(find.text('搜索教师')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus),
      '初中',
    );
    await tester.pumpAndSettle();
    expect(find.text('王老师（小学）'), findsNothing);
    await tester.tap(find.text('王老师（初中）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('锁定').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(controller.savedLock?.targetId, 'private_teacher_2');
    expect(controller.savedLock?.scope, ScheduleLockScope.teacher);
    expect(tester.takeException(), isNull);
  });
}
