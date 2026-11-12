import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' show AppDatabase;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/supervision.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/supervision/supervision_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

void main() {
  testWidgets('正课不可选择，批选跳过正课且增选班级后清理不适用课格', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _Repository(database)..fixture = _regularSnapshot;
    await tester.runAsync(() => repository.saveTerm(_term));
    final container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
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
          home: const Scaffold(
            body: SupervisionPage(
              termId: 't',
              seed: SupervisionSeed(
                stageId: 'stage',
                scope: FreeSlotScope.grade,
                scopeId: 'grade',
                weekday: 7,
                periodTypeId: 'evening',
                lessonIndex: 3,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final day in [1, 5, 7]) {
      expect(
        tester
            .widget<f.FTappable>(
              find.byKey(ValueKey('post-slot-$day-service-1')),
            )
            .onPress,
        isNotNull,
      );
    }
    final regular = find.byKey(const ValueKey('post-slot-7-evening-3'));
    final partial = find.byKey(const ValueKey('post-slot-7-evening-2'));
    for (final key in ['post-slot-1-evening-2', 'post-slot-7-evening-1']) {
      expect(
        tester.widget<f.FTappable>(find.byKey(ValueKey(key))).onPress,
        isNull,
      );
    }
    expect(tester.widget<f.FTappable>(regular).onPress, isNull);
    expect(
      find.descendant(of: regular, matching: find.text('正课')),
      findsOneWidget,
    );
    expect(tester.widget<f.FTappable>(partial).onPress, isNull);
    expect(
      find.descendant(of: partial, matching: find.text('含正课')),
      findsOneWidget,
    );
    final regularSurface = tester.widget<Container>(
      find
          .descendant(
            of: regular,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          )
          .first,
    );
    expect((regularSurface.decoration! as BoxDecoration).color, isNotNull);
    expect(find.text('已选 0 个课格'), findsOneWidget);
    expect(
      tester
          .widget<f.FTappable>(find.byKey(const ValueKey('post-row-evening-3')))
          .onPress,
      isNull,
    );

    // A class-specific self-study marker does not make the cell selectable for other classes.
    await tester.tap(find.byKey(const ValueKey('post-scope-class-c2')));
    await tester.pumpAndSettle();
    await tester.tap(partial);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 个课格'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-scope-class-c2')));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 个课格'), findsOneWidget);

    await tester.tap(find.text('全选课节'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 个课格'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-day-7')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 个课格'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('post-row-service-1')));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 个课格'), findsOneWidget);
    await tester.tap(find.text('添加岗位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(
      () => repository.watchSupervisionDraft('t').first,
    );
    expect(saved?.posts, hasLength(6));
    expect(
      saved?.posts.every((post) => post.periodTypeId == 'service'),
      isTrue,
    );
  });

  testWidgets('创建岗位使用范围树和实际作息周表，按选中课格保存连续岗位', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _Repository(database)..fixture = _gridSnapshot;
    await tester.runAsync(() => repository.saveTerm(_term));
    final container = ProviderContainer(
      overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
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
          home: const Scaffold(body: SupervisionPage(termId: 't')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建岗位'));
    await tester.pumpAndSettle();
    expect(find.text('18:20–19:05'), findsOneWidget);
    expect(find.byKey(const ValueKey('post-slot-7-evening-3')), findsOneWidget);
    final absent = tester.widget<f.FTappable>(
      find.byKey(const ValueKey('post-slot-5-evening-2')),
    );
    expect(absent.onPress, isNull);

    await tester.tap(find.byKey(const ValueKey('post-scope-grade-grade')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-slot-1-evening-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-scope-stage-primary')));
    await tester.pumpAndSettle();
    expect(find.text('作息课节 · 小学'), findsOneWidget);
    expect(find.text('已选 0 个课格'), findsOneWidget);
    // Returning to the stage cannot retain classes or slots from the other routine.
    await tester.tap(find.byKey(const ValueKey('post-scope-stage-stage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-scope-stage-stage')));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 个班级'), findsOneWidget);

    // Selecting an entire grade and then excluding one class keeps a visible subset.
    for (final key in [
      'post-scope-grade-grade',
      'post-scope-class-c1',
      'post-scope-grade-grade2',
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }
    expect(find.text('已选 2 个班级'), findsOneWidget);
    for (final key in [
      '1-evening-1',
      '1-evening-3',
      '7-evening-2',
      '7-evening-3',
      '5-service-1',
    ]) {
      await tester.tap(find.byKey(ValueKey('post-slot-$key')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('连续节次由同一老师负责'));
    await tester.pumpAndSettle();
    expect(find.text('将创建 8 个岗位 · 5 个课格'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('添加岗位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(
      () => repository.watchSupervisionDraft('t').first,
    );
    expect(saved?.posts, hasLength(8));
    expect(saved?.posts.map((post) => post.classIds.single).toSet(), {
      'c2',
      'c3',
    });
    expect(
      saved?.posts
          .where((post) => post.weekday == 1)
          .map((post) => post.lessonIndices),
      [
        [1],
        [1],
        [3],
        [3],
      ],
    );
    expect(
      saved?.posts
          .where((post) => post.weekday == 7)
          .map((post) => post.lessonIndices),
      [
        [2, 3],
        [2, 3],
      ],
    );
    expect(
      saved?.posts
          .where((post) => post.weekday == 5)
          .every((post) => post.periodTypeId == 'service'),
      isTrue,
    );
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('按班级'));
    await tester.pumpAndSettle();
    expect(find.text('班级'), findsOneWidget);
    expect(find.text('本周 5 节'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('duty-day-7')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('duty-class-c2-evening-2,3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('duty-class-c3-evening-2,3')),
      findsOneWidget,
    );
    await tester.tap(find.text('按教师'));
    await tester.pumpAndSettle();
    expect(find.text('教师'), findsOneWidget);
    expect(find.text('待安排教师'), findsOneWidget);
    await tester.tap(find.text('整周网格'));
    await tester.pumpAndSettle();
    expect(find.text('星期'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('周日作息支持一班一岗和实际合班，草稿可保存并重开', (tester) async {
    tester.view.physicalSize = const Size(650, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _Repository(database);
    await tester.runAsync(() => repository.saveTerm(_term));

    Future<void> open({SupervisionSeed? seed}) async {
      final container = ProviderContainer(
        overrides: [schoolRepositoryProvider.overrideWithValue(repository)],
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
            home: Scaffold(
              body: SupervisionPage(termId: 't', seed: seed),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    SupervisionSeed sundaySlot(int lessonIndex) => SupervisionSeed(
      stageId: 'stage',
      scope: FreeSlotScope.grade,
      scopeId: 'grade',
      weekday: DateTime.sunday,
      periodTypeId: 'evening',
      lessonIndex: lessonIndex,
    );

    await open(seed: sundaySlot(1));
    expect(find.text('创建带班岗位'), findsOneWidget);
    await tester.tap(find.byType(AppSelectField<SupervisionKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('早自习').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppSelectField<SupervisionKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('晚自习').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加岗位'));
    await tester.pumpAndSettle();
    expect(find.text('周日'), findsOneWidget);
    expect(find.text('待安排'), findsNWidgets(2));
    await tester.tap(find.text('待安排').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('张老师'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(
      () => repository.watchSupervisionDraft('t').first,
    );
    expect(saved?.posts, hasLength(2));
    expect(saved?.posts.map((post) => post.classIds.single), ['c1', 'c2']);
    expect(saved?.assignments.values, ['teacher']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await open();
    expect(find.text('张老师'), findsOneWidget);
    expect(find.text('待安排'), findsOneWidget);
    expect(find.text('整周网格'), findsOneWidget);
    await tester.tap(find.text('待安排 1'));
    await tester.pumpAndSettle();
    expect(find.text('张老师'), findsNothing);
    expect(find.text('待安排'), findsOneWidget);
    await tester.tap(find.text('全部岗位'));
    await tester.pumpAndSettle();
    expect(find.text('张老师'), findsOneWidget);

    await tester.tap(find.text('候选教师 · 1'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.text('全选搜索结果')).height, lessThan(30));
    await tester.enterText(find.byType(AppTextFormField), '语文组');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(f.FItem, '张老师'), findsNothing);
    expect(find.widgetWithText(f.FItem, '李老师'), findsOneWidget);
    await tester.enterText(find.byType(AppTextFormField), '');
    await tester.pumpAndSettle();
    final liRow = find.widgetWithText(f.FItem, '李老师');
    await tester.tap(find.descendant(of: liRow, matching: find.text('设置')));
    await tester.pumpAndSettle();
    final limit = find.widgetWithText(AppTextFormField, '每周带班上限');
    await tester.enterText(limit, '-1');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppPrimaryButton>(find.widgetWithText(AppPrimaryButton, '应用'))
          .onPressed,
      isNull,
    );
    await tester.enterText(limit, '4');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppPrimaryButton>(find.widgetWithText(AppPrimaryButton, '应用'))
          .onPressed,
      isNotNull,
    );
    final liCheckbox = find.descendant(
      of: liRow,
      matching: find.byType(AppCheckbox),
    );
    await tester.tap(liCheckbox);
    await tester.pumpAndSettle();
    expect(tester.widget<AppCheckbox>(liCheckbox).value, isTrue);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('候选教师 · 2'), findsOneWidget);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.text('待安排'));
    await tester.pumpAndSettle();
    expect(find.text('选择带班教师'), findsOneWidget);
    expect(find.byType(AppDialog), findsNothing);
    for (final height in [900.0, 1200.0, 600.0]) {
      tester.view.physicalSize = Size(1440, height);
      await tester.pumpAndSettle();
      final footerBottom = tester
          .getBottomLeft(find.widgetWithText(AppGhostButton, '保存草稿'))
          .dy;
      expect(
        height - footerBottom,
        inInclusiveRange(16, 32),
        reason: '选中岗位时，周表与教师面板应填满可用高度，底部仅保留正常边距',
      );
      expect(tester.takeException(), isNull);
    }
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(f.FItem, '李老师'));
    await tester.pumpAndSettle();
    expect(find.text('待安排'), findsNothing);
    await tester.tap(find.text('清除指派'));
    await tester.pumpAndSettle();
    expect(find.text('待安排'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await open(seed: sundaySlot(2));
    final merge = find.text('实际合班');
    await tester.ensureVisible(merge);
    await tester.tap(merge);
    await tester.pumpAndSettle();
    for (final (label, value) in [('活动组名称', '阅读组'), ('活动地点', '阅览室')]) {
      final field = find.widgetWithText(AppTextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }
    await tester.tap(find.text('添加岗位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存草稿'));
    await tester.pumpAndSettle();
    final merged = await tester.runAsync(
      () => repository.watchSupervisionDraft('t').first,
    );
    final group = merged?.posts.where((post) => post.groupName == '阅读组').single;
    expect(group?.classIds, ['c1', 'c2']);
    expect(group?.location, '阅览室');
    expect(group?.lessonIndices, [2]);
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    expect(find.text('整周网格'), findsOneWidget);
    // Resolve the real database projection outside the widget test's fake clock.
    repository.previewFixture = await tester.runAsync(
      () => repository.previewSupervisionPublish(
        't',
        _term.teachingWeekStart(2)!,
      ),
    );
    expect(repository.previewFixture, isNotNull);
    await tester.tap(find.text('预览并确认'));
    await tester.pumpAndSettle();
    expect(find.text('预览带班方案'), findsOneWidget);
    expect(find.text('岗位变更'), findsOneWidget);
    expect(find.text('变更前'), findsWidgets);
    expect(find.text('变更后'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('duty-preview-filter-update')));
    await tester.pumpAndSettle();
    expect(find.text('该类型暂无变更。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duty-preview-filter-all')));
    await tester.pumpAndSettle();

    final confirm = tester.widget<AppPrimaryButton>(
      find.widgetWithText(AppPrimaryButton, '确认生效'),
    );
    expect(confirm.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}

class _Repository extends DriftSchoolRepository {
  @override
  Stream<List<TeacherGroup>> watchTeacherGroups(String termId) => Stream.value(
    const [TeacherGroup(id: 'group', termId: 't', name: '语文组', sortOrder: 0)],
  );

  _Repository(super.database);

  SupervisionPreview? previewFixture;
  SchedulingSnapshot? fixture;

  @override
  Future<SupervisionPreview> previewSupervisionPublish(
    String termId,
    DateTime effectiveDate,
  ) {
    final preview = previewFixture;
    return preview != null && preview.effectiveDate == effectiveDate
        ? Future.value(preview)
        : super.previewSupervisionPublish(termId, effectiveDate);
  }

  @override
  Stream<List<SchoolStage>> watchStages(String termId) =>
      Stream.value(const [_stage]);

  @override
  Future<SchedulingSnapshot> loadSchedulingSnapshot(String termId) async =>
      fixture ??
      SchedulingSnapshot(
        term: _term,
        inputFingerprint: 'snapshot',
        teacherGroupMembers: const [
          TeacherGroupMember(
            id: 'member',
            groupId: 'group',
            teacherId: 'second',
          ),
        ],
        freeSlots: [
          for (var index = 1; index <= 2; index++)
            FreeSlot(
              id: 'self-$index',
              scope: FreeSlotScope.stage,
              scopeId: 'stage',
              stageId: 'stage',
              periodTypeId: 'evening',
              weekday: 7,
              lessonIndex: index,
              label: FreeSlotLabels.selfStudy,
            ),
        ],
        stages: const [_stage],
        grades: const [
          GradeGroup(id: 'grade', stageId: 'stage', name: '初一', sortOrder: 0),
        ],
        classes: const [
          ClassGroup(id: 'c1', gradeId: 'grade', name: '初一1班', sortOrder: 0),
          ClassGroup(id: 'c2', gradeId: 'grade', name: '初一2班', sortOrder: 1),
        ],
        teachers: const [
          Teacher(id: 'teacher', name: '张老师', shortName: '张', sortOrder: 0),
          Teacher(id: 'second', name: '李老师', shortName: '李', sortOrder: 1),
        ],
        routines: const [
          StageRoutine(
            stageId: 'stage',
            teachingWeekdays: {7},
            periodTypes: [
              LessonPeriodType(
                id: 'evening',
                name: '晚自习',
                defaultLessonCount: 2,
                sortOrder: 0,
                lessonTimes: [
                  LessonTime(
                    lessonIndex: 1,
                    label: '晚一',
                    startMinute: 1100,
                    endMinute: 1145,
                  ),
                ],
              ),
            ],
            overrides: [],
          ),
        ],
      );

  static const _stage = SchoolStage(
    id: 'stage',
    termId: 't',
    name: '初中',
    sortOrder: 0,
  );
}

final _term = AcademicTerm(
  id: 't',
  title: '学期',
  academicYear: '2026',
  semesterLabel: '秋',
  firstTeachingWeekStart: DateUtils.dateOnly(DateTime.now())
      .subtract(Duration(days: DateTime.now().weekday - DateTime.monday)),
  teachingWeekCount: 20,
  createdAt: DateTime(2026),
);

final _gridSnapshot = SchedulingSnapshot(
  term: _term,
  inputFingerprint: 'grid',
  freeSlots: [
    for (final day in [1, 5, 7])
      for (final period in ['service', 'evening'])
        for (
          var index = 1;
          index <= (period == 'service' || day == 5 ? 1 : 3);
          index++
        )
          FreeSlot(
            id: '$day-$period-$index',
            scope: FreeSlotScope.stage,
            scopeId: 'stage',
            stageId: 'stage',
            periodTypeId: period,
            weekday: day,
            lessonIndex: index,
            label: FreeSlotLabels.selfStudy,
          ),
  ],
  stages: const [
    SchoolStage(id: 'stage', termId: 't', name: '初中', sortOrder: 0),
    SchoolStage(id: 'primary', termId: 't', name: '小学', sortOrder: 1),
  ],
  grades: const [
    GradeGroup(id: 'pgrade', stageId: 'primary', name: '一年级', sortOrder: 0),
    GradeGroup(id: 'grade', stageId: 'stage', name: '初一', sortOrder: 0),
    GradeGroup(id: 'grade2', stageId: 'stage', name: '初二', sortOrder: 1),
  ],
  classes: const [
    ClassGroup(id: 'p1', gradeId: 'pgrade', name: '一年1班', sortOrder: 0),
    ClassGroup(id: 'c1', gradeId: 'grade', name: '初一1班', sortOrder: 0),
    ClassGroup(id: 'c2', gradeId: 'grade', name: '初一2班', sortOrder: 1),
    ClassGroup(id: 'c3', gradeId: 'grade2', name: '初二1班', sortOrder: 0),
  ],
  routines: const [
    StageRoutine(
      stageId: 'primary',
      teachingWeekdays: {2},
      periodTypes: [
        LessonPeriodType(
          id: 'primary-service',
          name: '课后服务',
          defaultLessonCount: 1,
          sortOrder: 0,
          lessonTimes: [],
        ),
      ],
      overrides: [],
    ),
    StageRoutine(
      stageId: 'stage',
      teachingWeekdays: {1, 5, 7},
      periodTypes: [
        LessonPeriodType(
          id: 'service',
          name: '课后服务',
          defaultLessonCount: 1,
          sortOrder: 0,
          lessonTimes: [
            LessonTime(
              lessonIndex: 1,
              label: '托管',
              startMinute: 990,
              endMinute: 1050,
            ),
          ],
        ),
        LessonPeriodType(
          id: 'evening',
          name: '晚自习',
          defaultLessonCount: 3,
          sortOrder: 1,
          lessonTimes: [
            LessonTime(
              lessonIndex: 1,
              label: '晚一',
              startMinute: 1100,
              endMinute: 1145,
            ),
            LessonTime(
              lessonIndex: 2,
              label: '晚二',
              startMinute: 1155,
              endMinute: 1200,
            ),
            LessonTime(
              lessonIndex: 3,
              label: '晚三',
              startMinute: 1210,
              endMinute: 1255,
            ),
          ],
        ),
      ],
      overrides: [
        RoutineOverride(periodTypeId: 'evening', weekday: 5, lessonCount: 1),
      ],
    ),
  ],
);

final _regularSnapshot = SchedulingSnapshot(
  term: _term,
  inputFingerprint: 'regular',
  stages: _gridSnapshot.stages,
  grades: _gridSnapshot.grades,
  classes: _gridSnapshot.classes,
  routines: _gridSnapshot.routines,
  freeSlots: [
    const FreeSlot(
      id: 'no-lesson',
      scope: FreeSlotScope.stage,
      scopeId: 'stage',
      stageId: 'stage',
      periodTypeId: 'evening',
      weekday: 1,
      lessonIndex: 2,
      label: FreeSlotLabels.none,
    ),
    for (final day in [1, 5, 7])
      FreeSlot(
        id: 'service-$day',
        scope: FreeSlotScope.school,
        scopeId: 't',
        stageId: 'stage',
        periodTypeId: 'service',
        weekday: day,
        lessonIndex: 1,
        label: {
          1: '课后服务',
          5: FreeSlotLabels.labor,
          7: FreeSlotLabels.teachingResearch,
        }[day]!,
      ),
    const FreeSlot(
      id: 'only-c1',
      scope: FreeSlotScope.schoolClass,
      scopeId: 'c1',
      stageId: 'stage',
      periodTypeId: 'evening',
      weekday: 7,
      lessonIndex: 2,
      label: FreeSlotLabels.selfStudy,
    ),
    const FreeSlot(
      id: 'grade-self',
      scope: FreeSlotScope.grade,
      scopeId: 'grade',
      stageId: 'stage',
      periodTypeId: 'evening',
      weekday: 7,
      lessonIndex: 1,
      label: FreeSlotLabels.selfStudy,
    ),
    const FreeSlot(
      id: 'c2-no-class',
      scope: FreeSlotScope.schoolClass,
      scopeId: 'c2',
      stageId: 'stage',
      periodTypeId: 'evening',
      weekday: 7,
      lessonIndex: 1,
      label: FreeSlotLabels.noClass,
    ),
  ],
);
