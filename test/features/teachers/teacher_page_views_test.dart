import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/models/teacher_assignment.dart';
import 'package:class_set/domain/models/teacher_group.dart';
import 'package:class_set/domain/models/teacher_preset.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/features/teachers/teachers_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' as material;

const _termId = 'term-1';

class _PresetRecordingRepository implements SchoolRepository {
  _PresetRecordingRepository({
    List<TeacherPreset> teacherPresets = const [],
    List<TeacherGroupPreset> teacherGroupPresets = const [],
  }) : teacherPresets = List.unmodifiable(teacherPresets),
       teacherGroupPresets = List.unmodifiable(teacherGroupPresets);

  List<TeacherPreset>? teacherPresets;
  List<TeacherGroupPreset>? teacherGroupPresets;

  @override
  Future<void> replaceTeacherPresets({
    required String termId,
    required String teacherId,
    required List<TeacherPreset> presets,
  }) async {
    teacherPresets = List.unmodifiable(presets);
  }

  @override
  Future<void> replaceTeacherGroupPresets({
    required String groupId,
    required List<TeacherGroupPreset> presets,
  }) async {
    teacherGroupPresets = List.unmodifiable(presets);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mountTeacherPage(
  WidgetTester tester, {
  List<ClassBrief>? classes,
  List<Subject>? subjects,
  List<Teacher>? teachers,
  List<TeacherAssignment>? assignments,
  List<TeacherGroup>? groups,
  List<TeacherGroupMember>? groupMembers,
  List<TeacherPreset>? teacherPresets,
  List<TeacherGroupPreset>? teacherGroupPresets,
  SchoolRepository? repository,
  List<SubjectRequirement>? requirements,
  List<SchoolStage>? stages,
  Map<String, StageRoutine> routines = const {},
  bool useFixtureTeacherDataWithRepository = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repository != null)
          schoolRepositoryProvider.overrideWithValue(repository),
        for (final entry in routines.entries)
          routineProvider(entry.key)
              .overrideWith((ref) => Stream.value(entry.value)),
        if (repository == null || useFixtureTeacherDataWithRepository)
          teacherPresetsProvider(_termId)
              .overrideWith((ref) => Stream.value(teacherPresets ?? const [])),
        if (repository == null || useFixtureTeacherDataWithRepository)
          teacherGroupPresetsProvider(_termId).overrideWith(
            (ref) => Stream.value(teacherGroupPresets ?? const []),
          ),
        classesForTermProvider(_termId)
            .overrideWith((ref) => Stream.value(classes ?? _sampleClasses)),
        subjectsProvider.overrideWith(
          (ref) => Stream.value(subjects ?? _sampleSubjects),
        ),
        if (repository == null || useFixtureTeacherDataWithRepository)
          teachersProvider(_termId)
              .overrideWith((ref) => Stream.value(teachers ?? _sampleTeachers)),
        teacherAssignmentsProvider(_termId).overrideWith(
          (ref) => Stream.value(assignments ?? _sampleAssignments),
        ),
        if (repository == null || useFixtureTeacherDataWithRepository)
          teacherGroupsProvider(_termId)
              .overrideWith((ref) => Stream.value(groups ?? const [])),
        if (repository == null || useFixtureTeacherDataWithRepository)
          teacherGroupMembersProvider(_termId)
              .overrideWith((ref) => Stream.value(groupMembers ?? const [])),
        allRequirementsProvider.overrideWith(
          (ref) => Stream.value(requirements ?? _sampleRequirements),
        ),
        stagesProvider(_termId).overrideWith(
          (ref) => Stream.value(
            stages ??
                const [
                  SchoolStage(
                    id: 'primary',
                    termId: _termId,
                    name: '小学部',
                    sortOrder: 0,
                  ),
                ],
          ),
        ),
        gradesForTermProvider(_termId).overrideWith(
          (ref) => Stream.value(const [
            GradeGroup(
              id: 'grade-1',
              stageId: 'primary',
              name: '初一',
              sortOrder: 0,
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => FTheme(
          data: AppTheme.forui,
          child: FToaster(child: child!),
        ),
        home: const Scaffold(body: TeachersPage(termId: _termId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('分组管理提供独立返回按钮并支持搜索分组成员', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      teachers: const [
        Teacher(id: 'teacher-1', name: '王老师', shortName: '王', sortOrder: 0),
        Teacher(id: 'teacher-2', name: '李老师', shortName: '李', sortOrder: 1),
      ],
      groups: const [
        TeacherGroup(
          id: 'group-1',
          termId: _termId,
          name: '语文教研组',
          description: '负责语文学科教研与排课协调',
          sortOrder: 0,
        ),
      ],
      groupMembers: const [
        TeacherGroupMember(
          id: 'member-1',
          groupId: 'group-1',
          teacherId: 'teacher-1',
        ),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教师分组管理'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('teacher-groups-return')), findsOneWidget);
    expect(find.byKey(const ValueKey('teacher-groups-table')), findsOneWidget);
    expect(find.text('语文教研组'), findsOneWidget);
    expect(find.text('1 名教师'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();
    expect(find.text('返回任课视图'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('teacher-group-members-group-1')),
    );
    await tester.pumpAndSettle();
    final dialog = find.byType(AppDialog);
    expect(dialog, findsOneWidget);
    expect(find.text('维护分组成员 · 语文教研组'), findsOneWidget);
    final firstMemberRow = find.byKey(
      const ValueKey('teacher-group-member-teacher-1'),
    );
    final firstMemberCheckbox = find.descendant(
      of: firstMemberRow,
      matching: find.byType(FCheckbox),
    );
    final firstMemberName = find.descendant(
      of: firstMemberRow,
      matching: find.text('王老师'),
    );
    expect(tester.getSize(firstMemberRow).height, 42);
    expect(
      tester.getCenter(firstMemberCheckbox).dy,
      closeTo(tester.getCenter(firstMemberName).dy, 1),
    );
    await tester.enterText(
      find.byKey(const ValueKey('teacher-group-member-search')),
      '李',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dialog, matching: find.text('李老师')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('王老师')),
      findsNothing,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('teacher-groups-return')));
    await tester.pumpAndSettle();
    expect(find.text('班级视角'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存分组成员后分组列表立即显示成员', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = db.AppDatabase(NativeDatabase.memory());
    final repository = DriftSchoolRepository(database);
    const teachers = [
      Teacher(id: 'teacher-1', name: '王老师', shortName: '王', sortOrder: 0),
      Teacher(id: 'teacher-2', name: '李老师', shortName: '李', sortOrder: 1),
    ];
    const group = TeacherGroup(
      id: 'group-1',
      termId: _termId,
      name: '语文教研组',
      sortOrder: 0,
    );
    await repository.saveTerm(
      AcademicTerm(
        id: _termId,
        title: '2026 秋季',
        academicYear: '2026-2027',
        semesterLabel: '秋季学期',
        firstTeachingWeekStart: DateTime(2026, 9, 1),
        teachingWeekCount: 20,
        createdAt: DateTime(2026),
      ),
    );
    await repository.saveTeachers(teachers);
    await repository.saveTeacherGroup(group);
    await repository.replaceTeacherGroupMembers(
      groupId: group.id,
      members: const [
        TeacherGroupMember(
          id: 'member-1',
          groupId: 'group-1',
          teacherId: 'teacher-1',
        ),
      ],
    );

    await _mountTeacherPage(
      tester,
      teachers: teachers,
      groups: const [group],
      repository: repository,
    );
    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教师分组管理'));
    await tester.pumpAndSettle();
    expect(find.text('王老师'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('teacher-group-members-group-1')),
    );
    await tester.pumpAndSettle();
    final memberRow = find.byKey(
      const ValueKey('teacher-group-member-teacher-2'),
    );
    await tester.tap(
      find.descendant(of: memberRow, matching: find.byType(FCheckbox)),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选 2 名 · 显示 2 名'), findsOneWidget);
    await tester.tap(find.text('保存成员'));
    await tester.pumpAndSettle();

    expect(find.text('2 名教师'), findsOneWidget);
    expect(find.text('王老师、李老师'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('teacher-group-members-group-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选 2 名 · 显示 2 名'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });

  testWidgets('新增教师和分组表单空名称时保留表单并提示', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(tester);
    for (final (action, message) in [
      ('新增教师', '请输入教师姓名'),
      ('新增分组', '请输入分组名称'),
    ]) {
      await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('教师预排入口进入统一页面并预选教师', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      routines: const {
        'primary': StageRoutine(
          stageId: 'primary',
          teachingWeekdays: {1, 2},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'am',
              name: '上午',
              defaultLessonCount: 2,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
        ),
      },
    );
    await tester.tap(find.text('教师视角'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('teacher-row-more-teacher-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教师预排'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('teacher-preset-workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('teacher-view-switcher-block'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('teacher-preset-selected-owner-teacher-teacher-1'),
      ),
      findsOneWidget,
    );
    final tree = find.byType(TeacherPresetScopeTree);
    expect(tree, findsOneWidget);
    expect(
      find.descendant(of: tree, matching: find.textContaining('全校')),
      findsNothing,
    );
    expect(
      find.descendant(of: tree, matching: find.text('小学部')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tree, matching: find.text('初一')),
      findsOneWidget,
    );
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('teacher-preset-workspace')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('teacher-view-switcher-block'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('teacher-row-more-teacher-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('教师任课更多菜单可进入预排并切换到教师分组', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      groups: const [
        TeacherGroup(id: 'group-1', termId: _termId, name: '语文组', sortOrder: 0),
      ],
      routines: const {
        'primary': StageRoutine(
          stageId: 'primary',
          teachingWeekdays: {1},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'am',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
        ),
      },
    );

    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预排'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('teacher-preset-workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('teacher-view-switcher-block'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('teacher-preset-mode-group')));
    await tester.pumpAndSettle();
    expect(find.text('语文组'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('teacher-preset-selected-owner-group-group-1')),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('teacher-preset-workspace')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('teacher-view-switcher-block')),
      findsOneWidget,
    );
    expect(find.text('班级视角'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('教师预排宽屏按左栏范围矩阵和底部汇总布局', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      routines: const {
        'primary': StageRoutine(
          stageId: 'primary',
          teachingWeekdays: {1, 2},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'am',
              name: '上午',
              defaultLessonCount: 2,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
        ),
      },
    );

    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预排'));
    await tester.pumpAndSettle();

    final mode = find.byKey(const ValueKey('teacher-preset-mode-panel'));
    final owners = find.byKey(const ValueKey('teacher-preset-owner-panel'));
    final scopes = find.byKey(const ValueKey('teacher-preset-scope-panel'));
    final matrix = find.byKey(const ValueKey('teacher-preset-matrix-panel'));
    final rules = find.byKey(const ValueKey('teacher-preset-rules-panel'));
    expect(mode, findsOneWidget);
    expect(owners, findsOneWidget);
    expect(scopes, findsOneWidget);
    expect(matrix, findsOneWidget);
    expect(rules, findsOneWidget);

    final modeRect = tester.getRect(mode);
    final ownerRect = tester.getRect(owners);
    final scopeRect = tester.getRect(scopes);
    final matrixRect = tester.getRect(matrix);
    final rulesRect = tester.getRect(rules);
    expect(modeRect.left, closeTo(ownerRect.left, 1));
    expect(modeRect.width, closeTo(ownerRect.width, 1));
    expect(modeRect.bottom, lessThan(ownerRect.top));
    expect(ownerRect.right, lessThan(scopeRect.left));
    expect(scopeRect.right, lessThan(matrixRect.left));
    expect(rulesRect.top, greaterThan(matrixRect.bottom));
    expect(rulesRect.left, closeTo(modeRect.left, 1));
    expect(rulesRect.right, closeTo(matrixRect.right, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('教师预排窄屏保留矩阵操作高度并支持整页滚动', (tester) async {
    tester.view.physicalSize = const Size(820, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      routines: const {
        'primary': StageRoutine(
          stageId: 'primary',
          teachingWeekdays: {1, 2, 3, 4, 5},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'am',
              name: '上午',
              defaultLessonCount: 4,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
        ),
      },
    );

    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预排'));
    await tester.pumpAndSettle();

    final scroll = find.byKey(const ValueKey('teacher-preset-page-scroll'));
    final matrix = find.byKey(const ValueKey('teacher-preset-matrix-panel'));
    final rules = find.byKey(const ValueKey('teacher-preset-rules-panel'));
    expect(scroll, findsOneWidget);
    expect(matrix, findsOneWidget);
    expect(tester.getSize(matrix).height, greaterThanOrEqualTo(320));
    await tester.scrollUntilVisible(
      rules,
      400,
      scrollable: find
          .descendant(of: scroll, matching: find.byType(Scrollable))
          .first,
    );
    expect(rules, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分组预排入口进入统一页面并预选分组', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      groups: const [
        TeacherGroup(id: 'group-1', termId: _termId, name: '语文组', sortOrder: 0),
      ],
      routines: const {
        'primary': StageRoutine(
          stageId: 'primary',
          teachingWeekdays: {1},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'am',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
        ),
      },
    );
    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教师分组管理'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('teacher-group-preset-group-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('teacher-preset-workspace')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('teacher-preset-mode-group')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('teacher-preset-selected-owner-group-group-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('teacher-groups-table'), skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('teacher-groups-table')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('teacher-preset-workspace')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('统一预排页汇总显示教师与分组规则', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      teachers: const [
        Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
      ],
      groups: const [
        TeacherGroup(id: 'group-1', termId: _termId, name: '语文组', sortOrder: 0),
      ],
      teacherPresets: const [
        TeacherPreset(
          id: 'personal-1',
          teacherId: 'teacher-1',
          scope: TeacherPresetScope.stage,
          scopeId: 'primary',
          stageId: 'primary',
          weekday: 1,
          periodTypeId: 'am',
          lessonIndex: 1,
          value: PresetValue.forbid,
        ),
      ],
      teacherGroupPresets: const [
        TeacherGroupPreset(
          id: 'group-rule-1',
          groupId: 'group-1',
          scope: TeacherPresetScope.grade,
          scopeId: 'grade-1',
          stageId: 'primary',
          weekday: 1,
          periodTypeId: 'am',
          lessonIndex: 1,
          value: PresetValue.must,
        ),
      ],
      routines: const {
        'primary': StageRoutine(
          stageId: 'primary',
          teachingWeekdays: {1},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'am',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
        ),
      },
    );

    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预排'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('teacher-preset-rule-teacher-personal-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('teacher-preset-rule-group-group-rule-1')),
      findsOneWidget,
    );
    expect(find.text('张伟'), findsWidgets);
    expect(find.textContaining('语文组'), findsWidgets);
    expect(find.text('不排'), findsWidgets);
    expect(find.text('一定排'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统一预排页分别提交教师和分组删除请求并保留另一类型规则', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const personalRule = TeacherPreset(
      id: 'personal-rule',
      teacherId: 'teacher-1',
      scope: TeacherPresetScope.stage,
      scopeId: 'primary',
      stageId: 'primary',
      weekday: 1,
      periodTypeId: 'am',
      lessonIndex: 1,
      value: PresetValue.forbid,
    );
    const groupRule = TeacherGroupPreset(
      id: 'group-rule',
      groupId: 'group-1',
      scope: TeacherPresetScope.grade,
      scopeId: 'grade-1',
      stageId: 'primary',
      weekday: 1,
      periodTypeId: 'am',
      lessonIndex: 1,
      value: PresetValue.must,
    );
    final repository = _PresetRecordingRepository(
      teacherPresets: const [personalRule],
      teacherGroupPresets: const [groupRule],
    );
    await _mountTeacherPage(
      tester,
      repository: repository,
      useFixtureTeacherDataWithRepository: true,
      teachers: const [
        Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
      ],
      groups: const [
        TeacherGroup(id: 'group-1', termId: _termId, name: '语文组', sortOrder: 0),
      ],
      teacherPresets: const [personalRule],
      teacherGroupPresets: const [groupRule],
      routines: const {
        'primary': StageRoutine(
          stageId: 'primary',
          teachingWeekdays: {1},
          overrides: [],
          periodTypes: [
            LessonPeriodType(
              id: 'am',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
        ),
      },
    );
    await tester.tap(find.byKey(const ValueKey('teacher-header-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预排'));
    await tester.pumpAndSettle();

    for (final id in ['personal-rule', 'group-rule']) {
      await tester.tap(find.byKey(ValueKey('teacher-preset-delete-$id')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('teacher-preset-confirm-delete-$id')),
      );
      await tester.pumpAndSettle();
      if (id == 'personal-rule') {
        expect(repository.teacherPresets, isEmpty);
        expect(repository.teacherGroupPresets, [groupRule]);
      } else {
        expect(repository.teacherPresets, isEmpty);
        expect(repository.teacherGroupPresets, isEmpty);
      }
    }

    expect(repository.teacherPresets, isEmpty);
    expect(repository.teacherGroupPresets, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('教师视角工具栏、摘要和教师入口按设计展示', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      requirements: const [
        SubjectRequirement(
          id: 'req-1',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 8,
        ),
      ],
    );

    expect(find.text('班级视角'), findsOneWidget);
    expect(find.text('教师视角'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('班级视角')).dx,
      lessThan(tester.getTopLeft(find.text('教师视角')).dx),
    );
    expect(find.byType(FTabs), findsOneWidget);
    expect(
      find.byKey(const ValueKey('teacher-class-matrix-border')),
      findsOneWidget,
    );
    expect(find.textContaining('支持拖拽分配'), findsOneWidget);

    await tester.tap(find.text('教师视角'));
    await tester.pumpAndSettle();

    expect(find.text('按姓名查找教师'), findsOneWidget);
    expect(find.text('批量添加任课'), findsOneWidget);
    expect(find.text('导入 Excel'), findsOneWidget);
    expect(find.text('张伟'), findsOneWidget);
    expect(find.text('周均节数'), findsOneWidget);
    expect(find.text('5 节'), findsOneWidget);
    expect(find.text('数学 · 初一（1）班 · 5 节'), findsOneWidget);
    expect(find.text('添加新教师（或从 Excel 名单导入）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('teacher-assignment-table-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('teacher-assignment-row-teacher-1')),
      findsOneWidget,
    );
    expect(find.text('未分配课程'), findsOneWidget);
    expect(find.text('初一（1）班'), findsOneWidget);
    expect(find.text('数学 · 3 节'), findsOneWidget);
    expect(find.text('添加任课'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('teacher-row-more-teacher-1')));
    await tester.pumpAndSettle();
    expect(find.text('添加任课'), findsOneWidget);
    expect(find.text('编辑教师'), findsOneWidget);
    expect(find.text('删除教师'), findsOneWidget);
    await tester.tapAt(const Offset(20, 700));
    await tester.pumpAndSettle();

    await tester.tap(find.text('批量添加任课'));
    await tester.pumpAndSettle();
    expect(find.text('添加一行'), findsOneWidget);
    expect(find.text('添加 1 项'), findsOneWidget);
    await tester.tap(find.text('添加一行'));
    await tester.pumpAndSettle();
    expect(find.text('添加 2 项'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('教师任课页面标题栏和双视角内容布局', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(tester);

    final title = find.text('教师任课');
    final pageDescription = find.textContaining('支持拖拽分配');
    final classTab = find.byKey(const ValueKey('teacher-view-tab-class'));
    final switcherBlock = find.byKey(
      const ValueKey('teacher-view-switcher-block'),
    );
    final classMatrix = find.byKey(
      const ValueKey('teacher-class-matrix-border'),
    );
    final unassignedTitle = find.text('未分配课程');
    final classBatchButton = find.text('批量添加任课');

    expect(title, findsOneWidget);
    expect(find.byType(FTabs), findsOneWidget);
    expect(switcherBlock, findsOneWidget);
    expect(pageDescription, findsOneWidget);
    expect(classBatchButton, findsOneWidget);
    expect(
      find.ancestor(
        of: classBatchButton,
        matching: find.byType(AppPrimaryButton),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: classBatchButton,
        matching: find.byType(AppOutlineButton),
      ),
      findsNothing,
    );
    expect(find.text('导入 Excel'), findsOneWidget);
    expect(
      tester.getTopLeft(classBatchButton).dy,
      lessThan(tester.getTopLeft(classTab).dy),
    );
    expect(
      tester.getTopLeft(classTab).dx,
      lessThan(tester.getTopLeft(classMatrix).dx),
    );
    expect(
      tester.getTopLeft(switcherBlock).dy,
      closeTo(tester.getTopLeft(classMatrix).dy, 0.5),
    );
    expect(
      tester.getTopLeft(switcherBlock).dx +
          tester.getSize(switcherBlock).width +
          12,
      closeTo(tester.getTopLeft(classMatrix).dx, 0.5),
    );
    expect(
      tester.getTopLeft(unassignedTitle).dx,
      lessThan(tester.getTopLeft(classMatrix).dx),
    );

    await tester.tap(find.text('教师视角'));
    await tester.pumpAndSettle();

    final teacherTab = find.byKey(const ValueKey('teacher-view-tab-teacher'));
    final teacherTable = find.byKey(const ValueKey('teacher-assignment-table'));
    expect(
      tester.getTopLeft(teacherTab).dx,
      lessThan(tester.getTopLeft(teacherTable).dx),
    );
    expect(
      tester.getTopLeft(unassignedTitle).dx,
      lessThan(tester.getTopLeft(teacherTable).dx),
    );
    expect(
      tester.getTopLeft(switcherBlock).dy,
      closeTo(tester.getTopLeft(teacherTable).dy, 0.5),
    );
    expect(
      tester.getTopLeft(switcherBlock).dx +
          tester.getSize(switcherBlock).width +
          12,
      closeTo(tester.getTopLeft(teacherTable).dx, 0.5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('班级视角教师面板显示全部教师和紧凑跨学段标签', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      teachers: const [
        Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
        Teacher(id: 'teacher-2', name: '李芳', shortName: '李', sortOrder: 1),
        Teacher(id: 'teacher-3', name: '王敏', shortName: '王', sortOrder: 2),
        Teacher(id: 'teacher-4', name: '赵强', shortName: '赵', sortOrder: 3),
      ],
      classes: const [
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-1',
          name: '一班',
        ),
        ClassBrief(
          stageId: 'middle',
          gradeId: 'grade-2',
          id: 'class-2',
          name: '二班',
        ),
      ],
      stages: const [
        SchoolStage(id: 'primary', termId: _termId, name: '小学部', sortOrder: 0),
        SchoolStage(id: 'middle', termId: _termId, name: '初中部', sortOrder: 1),
      ],
      assignments: const [
        TeacherAssignment(
          id: 'primary-assignment',
          termId: _termId,
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
        TeacherAssignment(
          id: 'middle-assignment',
          termId: _termId,
          teacherId: 'teacher-1',
          classId: 'class-2',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
      ],
    );

    expect(find.text('查看全部 4 名教师'), findsNothing);
    expect(find.text('赵强'), findsOneWidget);
    expect(tester.widget<Text>(find.text('跨学段')).style?.fontSize, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拆分任课 chip 显示协同教师和节数', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      teachers: const [
        Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
        Teacher(id: 'teacher-2', name: '李芳', shortName: '李', sortOrder: 1),
      ],
      assignments: const [
        TeacherAssignment(
          id: 'assignment-1',
          termId: _termId,
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 3,
        ),
        TeacherAssignment(
          id: 'assignment-2',
          termId: _termId,
          teacherId: 'teacher-2',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
      ],
    );

    await tester.tap(find.text('教师视角'));
    await tester.pumpAndSettle();

    expect(find.text('数学 · 初一（1）班 · 3 节'), findsOneWidget);
    expect(find.byTooltip('数学 · 初一（1）班 · 3 节（与李芳 3/2 拆分）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('教师任课多且有拆分时默认折叠，展开后可查看并编辑', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      teachers: const [
        Teacher(
          id: 'teacher-1',
          name: '王老师.的丽热巴.多',
          shortName: '王',
          sortOrder: 0,
        ),
        Teacher(
          id: 'teacher-2',
          name: '李老师.的丽热巴.多',
          shortName: '李',
          sortOrder: 1,
        ),
      ],
      classes: const [
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-1',
          name: '一年级 1 班',
        ),
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-2',
          name: '一年级 2 班',
        ),
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-3',
          name: '一年级 3 班',
        ),
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-4',
          name: '一年级 4 班',
        ),
      ],
      assignments: [
        for (var index = 1; index <= 4; index++) ...[
          TeacherAssignment(
            id: 'own-$index',
            termId: _termId,
            teacherId: 'teacher-1',
            classId: 'class-$index',
            subjectId: 'math',
            weekMode: WeekMode.weekly,
            lessonCount: 1,
          ),
          TeacherAssignment(
            id: 'peer-$index',
            termId: _termId,
            teacherId: 'teacher-2',
            classId: 'class-$index',
            subjectId: 'math',
            weekMode: WeekMode.weekly,
            lessonCount: 1,
          ),
        ],
      ],
    );
    await tester.tap(find.text('教师视角'));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('teacher-assignment-row-teacher-1'));
    expect(tester.getSize(row).height, lessThan(90));
    expect(find.textContaining('（与李老师'), findsNothing);
    expect(find.text('4 项任课'), findsWidgets);
    final expand = find.byKey(
      const ValueKey('teacher-assignment-toggle-teacher-1'),
    );
    expect(expand, findsOneWidget);
    final expandLabel = find.descendant(of: expand, matching: find.text('展开'));
    final workload = find.descendant(of: row, matching: find.text('4 节'));
    expect(expandLabel, findsOneWidget);
    expect(workload, findsOneWidget);
    expect(
      (tester.getCenter(expandLabel).dy - tester.getCenter(workload).dy).abs(),
      lessThanOrEqualTo(1),
    );
    final expandText = tester.widget<Text>(expandLabel);
    expect(expandText.style?.fontSize, 11);
    expect(expandText.style?.color, AppTheme.muted);
    expect(tester.takeException(), isNull);

    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('teacher-assignment-detail-teacher-1')),
      findsOneWidget,
    );
    expect(find.text('收起'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final detail = find.byKey(
      const ValueKey('teacher-assignment-detail-teacher-1'),
    );
    expect(
      tester.getSize(detail).width,
      lessThan(tester.getSize(row).width - 100),
    );
    await tester.tap(
      find.descendant(of: detail, matching: find.text('数学 · 一年级 1 班 · 1 节')),
    );
    await tester.pumpAndSettle();
    expect(find.text('分配 一年级 1 班 数学 5节'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(720, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('教师视角未分配课程按班级收起，展开后仍可查看课程', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      classes: const [
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-1',
          name: '一班',
        ),
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-2',
          name: '二班',
        ),
      ],
      requirements: const [
        SubjectRequirement(
          id: 'req-1',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 5,
        ),
      ],
      assignments: const [],
    );
    await tester.tap(find.text('教师视角'));
    await tester.pumpAndSettle();

    expect(find.text('一班'), findsOneWidget);
    expect(find.text('二班'), findsOneWidget);
    expect(find.text('数学 · 5 节'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('unassigned-class-toggle-class-2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('数学 · 5 节'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('班级视角未分配课程与教师视角使用同一班级分组', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      classes: const [
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-1',
          name: '一班',
        ),
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-2',
          name: '二班',
        ),
      ],
      requirements: const [
        SubjectRequirement(
          id: 'req-1',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 5,
        ),
      ],
      assignments: const [],
    );

    expect(
      find.byKey(const ValueKey('unassigned-class-toggle-class-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('unassigned-class-toggle-class-2')),
      findsOneWidget,
    );
    expect(find.text('数学 · 5 节'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('unassigned-class-toggle-class-2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('数学 · 5 节'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('班级矩阵标签、单元格和视角 tab 按设计稿对齐配色', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      classes: const [
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-1',
          name: '初一（1）班',
        ),
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-2',
          id: 'class-2',
          name: '初一（2）班',
        ),
      ],
      subjects: const [
        Subject(id: 'physical', name: '体育与健康', shortName: '体育', sortOrder: 0),
        Subject(id: 'math', name: '数学', shortName: '数', sortOrder: 1),
      ],
      requirements: const [
        SubjectRequirement(
          id: 'physical-odd',
          subjectId: 'physical',
          gradeId: 'grade-1',
          weekMode: WeekMode.odd,
          lessonCount: 2,
        ),
        SubjectRequirement(
          id: 'physical-even',
          subjectId: 'physical',
          gradeId: 'grade-2',
          weekMode: WeekMode.even,
          lessonCount: 2,
        ),
        SubjectRequirement(
          id: 'math-weekly',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
      assignments: const [
        TeacherAssignment(
          id: 'assignment-1',
          termId: _termId,
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
      ],
    );

    await tester.tap(find.text('班级视角'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('teacher-view-tab-class')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('teacher-view-tab-teacher')),
      findsOneWidget,
    );
    final tabs = tester.widget<FTabs>(find.byType(FTabs));
    expect(tabs.children, hasLength(2));

    final assignmentHint = find.textContaining('支持拖拽分配');
    final subjectHeader = find.text('科目');
    expect(
      tester.getTopLeft(subjectHeader).dx,
      greaterThan(tester.getTopLeft(assignmentHint).dx),
    );
    final subjectInfo = find.byKey(const ValueKey('subject-info-physical'));
    final subjectName = find.descendant(
      of: subjectInfo,
      matching: find.text('体育与健康'),
    );
    expect(
      tester.getTopLeft(subjectName).dx,
      closeTo(tester.getTopLeft(subjectHeader).dx, 0.5),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('teacher-view-tab-class')))
          .dx,
      lessThan(tester.getTopLeft(subjectHeader).dx),
    );
    final oddTag = find.descendant(of: subjectInfo, matching: find.text('单周'));
    final evenTag = find.descendant(of: subjectInfo, matching: find.text('双周'));
    expect(tester.widget<Text>(subjectName).style?.fontSize, 12);
    expect(
      tester.getCenter(subjectName).dy,
      closeTo(tester.getCenter(oddTag).dy, 2),
    );
    expect(
      tester.getCenter(subjectName).dy,
      closeTo(tester.getCenter(evenTag).dy, 2),
    );
    final oddTagBackground = tester.widget<DecoratedBox>(
      find.ancestor(of: oddTag, matching: find.byType(DecoratedBox)).first,
    );
    final evenTagBackground = tester.widget<DecoratedBox>(
      find.ancestor(of: evenTag, matching: find.byType(DecoratedBox)).first,
    );
    expect(
      (oddTagBackground.decoration as BoxDecoration).color,
      AppTheme.warningSurface,
    );
    expect(
      (evenTagBackground.decoration as BoxDecoration).color,
      AppTheme.successSurface,
    );

    final assignedCell = find.byKey(
      const ValueKey('assignment-cell-class-1-math'),
    );
    final assignedName = find.descendant(
      of: assignedCell,
      matching: find.text('张伟(4)'),
    );
    expect(
      tester.getCenter(assignedName).dx,
      closeTo(tester.getCenter(assignedCell).dx, 1),
    );
    expect(
      tester.getCenter(assignedName).dy,
      closeTo(tester.getCenter(assignedCell).dy, 1),
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(
              const ValueKey('assignment-cell-background-class-1-math'),
            ),
          )
          .color,
      Colors.white,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(
              const ValueKey('assignment-cell-background-class-1-physical'),
            ),
          )
          .color,
      AppTheme.warningSurface,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('assignment-cell-class-1-physical')),
        matching: find.text('未分配(单.2)'),
      ),
      findsOneWidget,
    );
    final unassignedLabel = find.descendant(
      of: find.byKey(const ValueKey('assignment-cell-class-1-physical')),
      matching: find.text('未分配(单.2)'),
    );
    expect(tester.widget<Text>(unassignedLabel).style?.color, AppTheme.warning);

    final unassignedCount = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('unassigned-course-count')),
    );
    expect(
      (unassignedCount.decoration as BoxDecoration).color,
      AppTheme.warningSurface,
    );
    final unassignedTileText = find.text('体育与健康（单周） · 2 节');
    expect(unassignedTileText, findsOneWidget);
    expect(
      find.byKey(const ValueKey('unassigned-class-toggle-class-1')),
      findsOneWidget,
    );
    expect(find.byTooltip('初一（1）班 · 体育与健康（单周） · 2 节'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('视角切换使用铺满容器且带明确选中态的动画标签', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(tester);

    final tabsFinder = find.byType(FTabs);
    final tabBarFinder = find.descendant(
      of: tabsFinder,
      matching: find.byType(material.TabBar),
    );
    final tabs = tester.widget<FTabs>(tabsFinder);
    final tabBarBefore = tester.widget<material.TabBar>(tabBarFinder);
    final initialController = tabBarBefore.controller!;

    expect(tabs.scrollable, isFalse);
    expect(tabBarBefore.padding, EdgeInsets.zero);
    expect((tabBarBefore.indicator as ShapeDecoration).color, Colors.white);

    await tester.tap(find.byKey(const ValueKey('teacher-view-tab-teacher')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final tabBarDuringTransition = tester.widget<material.TabBar>(tabBarFinder);
    expect(
      find.byKey(const ValueKey('teacher-assignment-table')),
      findsOneWidget,
    );
    expect(tabBarDuringTransition.controller, same(initialController));
    expect(
      tabBarDuringTransition.controller!.animation!.value,
      allOf(greaterThan(0), lessThan(1)),
    );
    await tester.pumpAndSettle();
    expect(tabBarDuringTransition.controller!.index, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('视角切换边框完整且页头操作在切换后保持对齐', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(tester);

    final switcherBlock = find.byKey(
      const ValueKey('teacher-view-switcher-block'),
    );
    final tabs = find.byType(FTabs);
    final tabBar = find.descendant(
      of: tabs,
      matching: find.byType(material.TabBar),
    );
    final track = tester.widget<DecoratedBox>(
      find.ancestor(of: tabBar, matching: find.byType(DecoratedBox)).first,
    );
    final trackDecoration = track.decoration as ShapeDecoration;
    final trackShape = trackDecoration.shape as RoundedSuperellipseBorder;
    final blockRect = tester.getRect(switcherBlock);
    final tabsRect = tester.getRect(tabs);
    final classViewContentTop = blockRect.top;

    expect(trackDecoration.color, AppTheme.selectedBlue);
    expect(trackShape.side.color, AppTheme.border);
    expect(tabsRect.left - blockRect.left, greaterThanOrEqualTo(3));
    expect(blockRect.right - tabsRect.right, greaterThanOrEqualTo(3));

    await tester.tap(find.byKey(const ValueKey('teacher-view-tab-teacher')));
    await tester.pumpAndSettle();

    final batchAction = find.text('批量添加任课');
    final importAction = find.text('导入 Excel');
    final moreAction = find.byKey(const ValueKey('teacher-header-overflow'));
    final pageHeader = find.byType(AppPageHeader);
    expect(
      find.descendant(of: moreAction, matching: find.text('更多')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(switcherBlock).dy,
      closeTo(classViewContentTop, 0.5),
    );
    expect(
      tester.getCenter(moreAction).dy,
      closeTo(tester.getCenter(batchAction).dy, 0.5),
    );
    expect(
      find.ancestor(of: batchAction, matching: find.byType(AppPrimaryButton)),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: batchAction, matching: find.byType(AppOutlineButton)),
      findsNothing,
    );
    expect(
      tester.getCenter(importAction).dy,
      closeTo(tester.getCenter(batchAction).dy, 0.5),
    );
    expect(
      tester.getRect(moreAction).right,
      closeTo(tester.getRect(pageHeader).right, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('班级矩阵外框和横向单元格分隔线绘制在内容上方', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(tester);
    await tester.tap(find.text('班级视角'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('teacher-class-matrix-border')),
      findsOneWidget,
    );
    final border = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('teacher-class-matrix-border')),
    );
    expect(border.position, DecorationPosition.foreground);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('assignment-cell-divider-class-1-math')),
          )
          .height,
      1,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('subject-cell-divider-math')))
          .height,
      1,
    );
  });

  testWidgets('班级视角与教师视角表格外观匹配科目矩阵', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(tester);

    final matrixBorder = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('teacher-class-matrix-border')),
    );
    expect(
      (matrixBorder.decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(AppTheme.cardRadius),
    );
    expect(
      tester
          .widget<ClipRRect>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('teacher-class-matrix-border')),
                  matching: find.byType(ClipRRect),
                )
                .first,
          )
          .borderRadius,
      BorderRadius.circular(AppTheme.cardRadius),
    );
    final classHeaders = find.byType(AppDataTableHeader);
    expect(classHeaders, findsNWidgets(2));
    for (final headerFinder in [classHeaders.first, classHeaders.last]) {
      final header = tester.widget<AppDataTableHeader>(headerFinder);
      expect(header.height, 40);
      expect(header.backgroundColor, Colors.white);
      expect(header.textColor, AppTheme.muted);
      final textStyle = tester
          .widget<DefaultTextStyle>(
            find
                .descendant(
                  of: headerFinder,
                  matching: find.byType(DefaultTextStyle),
                )
                .first,
          )
          .style;
      expect(textStyle.fontSize, 11);
      expect(textStyle.fontWeight, FontWeight.w600);
      expect(textStyle, AppTheme.matrixHeaderTextStyle);
    }

    await tester.tap(find.byKey(const ValueKey('teacher-view-tab-teacher')));
    await tester.pumpAndSettle();

    final teacherTable = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('teacher-assignment-table')),
    );
    expect(
      (teacherTable.decoration as BoxDecoration).borderRadius,
      BorderRadius.circular(AppTheme.cardRadius),
    );
    expect(
      tester
          .widget<ClipRRect>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('teacher-assignment-table')),
                  matching: find.byType(ClipRRect),
                )
                .first,
          )
          .borderRadius,
      BorderRadius.circular(AppTheme.cardRadius),
    );
    const teacherHeaderKey = ValueKey('teacher-assignment-table-header');
    final teacherHeader = tester.widget<AppDataTableHeader>(
      find.byKey(teacherHeaderKey),
    );
    expect(teacherHeader.height, 40);
    expect(teacherHeader.backgroundColor, Colors.white);
    expect(teacherHeader.textColor, AppTheme.muted);
    final teacherHeaderTextStyle = tester
        .widget<DefaultTextStyle>(
          find
              .descendant(
                of: find.byKey(teacherHeaderKey),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style;
    expect(teacherHeaderTextStyle.fontSize, 11);
    expect(teacherHeaderTextStyle.fontWeight, FontWeight.w600);
    expect(teacherHeaderTextStyle, AppTheme.matrixHeaderTextStyle);
  });

  testWidgets('悬停单元格时只高亮当前单元格', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      classes: const [
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-1',
          name: '初一（1）班',
        ),
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-2',
          name: '初一（2）班',
        ),
      ],
      subjects: const [
        Subject(id: 'math', name: '数学', shortName: '数', sortOrder: 0),
        Subject(id: 'english', name: '英语', shortName: '英', sortOrder: 1),
      ],
      requirements: const [
        SubjectRequirement(
          id: 'math-req',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
        SubjectRequirement(
          id: 'english-req',
          subjectId: 'english',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 2,
        ),
      ],
      assignments: const [],
    );
    await tester.tap(find.text('班级视角'));
    await tester.pumpAndSettle();

    final hoveredCell = find.byKey(
      const ValueKey('assignment-cell-class-1-math'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(hoveredCell));
    await tester.pump();

    Color cellColor(String classId, String subjectId) => tester
        .widget<ColoredBox>(
          find.byKey(
            ValueKey('assignment-cell-background-$classId-$subjectId'),
          ),
        )
        .color;

    expect(cellColor('class-1', 'math'), AppTheme.selectedBlue);
    expect(cellColor('class-2', 'math'), AppTheme.warningSurface);
    expect(cellColor('class-1', 'english'), AppTheme.warningSurface);
    expect(cellColor('class-2', 'english'), AppTheme.warningSurface);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('班级矩阵横向滚动时科目列保持固定', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final classes = [
      for (var index = 0; index < 50; index++)
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-$index',
          name: '测试班级 $index',
        ),
    ];
    await _mountTeacherPage(
      tester,
      classes: classes,
      subjects: const [
        Subject(id: 'fixed', name: '固定科目', shortName: '固', sortOrder: 0),
      ],
      requirements: const [],
      assignments: const [],
      teachers: const [],
    );
    await tester.tap(find.text('班级视角'));
    await tester.pumpAndSettle();

    final subjectLabel = find.text('固定科目');
    final firstClassHeader = find.byKey(
      const ValueKey('teacher-class-header-class-0'),
    );
    final lastClassHeader = find.byKey(
      const ValueKey('teacher-class-header-class-49'),
    );
    final lastClassCell = find.byKey(
      const ValueKey('assignment-cell-class-49-fixed'),
    );
    final subjectXBefore = tester.getTopLeft(subjectLabel).dx;
    expect(lastClassHeader, findsNothing);
    expect(lastClassCell, findsNothing);
    final horizontalScroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('teacher-class-matrix-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    horizontalScroll.position.jumpTo(horizontalScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(subjectLabel).dx, closeTo(subjectXBefore, 0.5));
    expect(horizontalScroll.position.pixels, greaterThan(0));
    expect(firstClassHeader, findsNothing);
    expect(lastClassHeader, findsOneWidget);
    expect(lastClassCell, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('任课单元格单行省略教师课节并悬停展示完整内容', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final classes = [
      for (var index = 0; index < 10; index++)
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-1',
          id: 'class-$index',
          name: '初一（$index）班',
        ),
    ];
    const completeLabel = '王老师(单.3) 李老师(4) 孙老师(双.2)';
    await _mountTeacherPage(
      tester,
      classes: classes,
      teachers: const [
        Teacher(id: 'odd-teacher', name: '王老师', shortName: '王', sortOrder: 0),
        Teacher(
          id: 'weekly-teacher',
          name: '李老师',
          shortName: '李',
          sortOrder: 1,
        ),
        Teacher(id: 'even-teacher', name: '孙老师', shortName: '孙', sortOrder: 2),
      ],
      requirements: const [],
      assignments: const [
        TeacherAssignment(
          id: 'odd-assignment',
          termId: _termId,
          teacherId: 'odd-teacher',
          classId: 'class-0',
          subjectId: 'math',
          weekMode: WeekMode.odd,
          lessonCount: 3,
        ),
        TeacherAssignment(
          id: 'weekly-assignment',
          termId: _termId,
          teacherId: 'weekly-teacher',
          classId: 'class-0',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
        TeacherAssignment(
          id: 'even-assignment',
          termId: _termId,
          teacherId: 'even-teacher',
          classId: 'class-0',
          subjectId: 'math',
          weekMode: WeekMode.even,
          lessonCount: 2,
        ),
      ],
    );

    final cell = find.byKey(const ValueKey('assignment-cell-class-0-math'));
    final content = tester.widget<Text>(
      find.byKey(const ValueKey('assignment-cell-content-class-0-math')),
    );
    expect(content.maxLines, 1);
    expect(content.overflow, TextOverflow.ellipsis);
    expect(content.textSpan!.toPlainText(), completeLabel);
    final tooltip = tester.widget<Tooltip>(
      find.descendant(of: cell, matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, completeLabel);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(cell));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(completeLabel), findsWidgets);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑任课分配实时显示各周模式剩余可分配节数', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      assignments: const [
        TeacherAssignment(
          id: 'weekly-assignment',
          termId: _termId,
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 5,
        ),
        TeacherAssignment(
          id: 'odd-assignment',
          termId: _termId,
          teacherId: 'teacher-1',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.odd,
          lessonCount: 1,
          sortOrder: 1,
        ),
        TeacherAssignment(
          id: 'legacy-unassigned',
          termId: _termId,
          teacherId: '',
          classId: 'class-1',
          subjectId: 'math',
          weekMode: WeekMode.weekly,
          lessonCount: 1,
          sortOrder: 2,
        ),
      ],
      requirements: const [
        SubjectRequirement(
          id: 'weekly-requirement',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 8,
        ),
        SubjectRequirement(
          id: 'odd-requirement',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.odd,
          lessonCount: 3,
        ),
      ],
    );

    await tester.tap(
      find.byKey(const ValueKey('assignment-cell-class-1-math')),
    );
    await tester.pumpAndSettle();

    final firstTeacherSelect = tester.widget<AppSelectField<String>>(
      find.byType(AppSelectField<String>).first,
    );
    expect(firstTeacherSelect.items, contains('请选择教师'));
    expect(firstTeacherSelect.items, isNot(contains('未分配')));

    const initialRemainder = '剩余可分配：每周 3 节 · 单周 2 节';
    expect(find.text(initialRemainder), findsOneWidget);
    final lessonFields = find.byWidgetPredicate(
      (widget) =>
          widget is FTextFormField &&
          widget.keyboardType == TextInputType.number,
    );
    expect(lessonFields, findsNWidgets(2));
    await tester.enterText(
      find.descendant(
        of: lessonFields.first,
        matching: find.byType(EditableText),
      ),
      '7',
    );
    await tester.pumpAndSettle();

    expect(find.text('剩余可分配：每周 1 节 · 单周 2 节'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('任课分配周模式只列出有节数需求的模式', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      assignments: const [],
      requirements: const [
        SubjectRequirement(
          id: 'weekly-requirement',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 8,
        ),
        SubjectRequirement(
          id: 'odd-requirement',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.odd,
          lessonCount: 3,
        ),
        SubjectRequirement(
          id: 'zero-even-requirement',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.even,
          lessonCount: 0,
        ),
      ],
    );

    await tester.tap(
      find.byKey(const ValueKey('assignment-cell-class-1-math')),
    );
    await tester.pumpAndSettle();

    final weekModeSelect = tester.widget<AppSelectField<WeekMode>>(
      find.byType(AppSelectField<WeekMode>).first,
    );
    expect(weekModeSelect.value, WeekMode.weekly);
    expect(weekModeSelect.items, {'每周': WeekMode.weekly, '单周': WeekMode.odd});
    expect(tester.takeException(), isNull);
  });

  testWidgets('班级视角展示矩阵与右侧分配区，长矩阵按需构建', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final classes = [
      for (var index = 0; index < 120; index++)
        ClassBrief(
          stageId: 'primary',
          gradeId: 'grade-${index % 12}',
          id: 'class-$index',
          name: '班级 $index',
        ),
    ];
    final subjects = [
      for (var index = 0; index < 18; index++)
        Subject(
          id: 'subject-$index',
          name: '科目 $index',
          shortName: '科$index',
          sortOrder: index,
        ),
    ];
    final requirements = [
      for (var grade = 0; grade < 12; grade++)
        for (var subject = 0; subject < 18; subject++)
          SubjectRequirement(
            id: 'req-$grade-$subject',
            subjectId: 'subject-$subject',
            gradeId: 'grade-$grade',
            weekMode: WeekMode.weekly,
            lessonCount: 4,
          ),
    ];
    await _mountTeacherPage(
      tester,
      classes: classes,
      subjects: subjects,
      requirements: requirements,
      assignments: const [],
      teachers: const [],
    );

    await tester.tap(find.text('班级视角'));
    await tester.pumpAndSettle();

    expect(find.textContaining('支持拖拽分配'), findsOneWidget);
    expect(find.text('批量添加课'), findsOneWidget);
    expect(find.text('数学'), findsNothing);
    expect(find.text('科目 0'), findsWidgets);
    expect(find.text('未分配课程'), findsOneWidget);
    expect(find.text('教师'), findsOneWidget);
    expect(find.text('科目 17'), findsNothing);
    final rowsScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('teacher-class-matrix-rows')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first,
    );
    rowsScrollable.position.jumpTo(rowsScrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('科目 17'), findsOneWidget);
    await tester.tap(find.text('教师视角'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('班级视角'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有科目节数需求的单元格不能打开任课分配', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      requirements: const [],
      assignments: const [],
    );

    final cell = find.byKey(const ValueKey('assignment-cell-class-1-math'));
    expect(tester.widget<InkWell>(cell).onTap, isNull);
    await tester.tap(cell);
    await tester.pumpAndSettle();

    expect(find.text('编辑任课分配'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量添加任课的周模式随科目需求联动', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      subjects: const [
        Subject(id: 'math', name: '数学', shortName: '数', sortOrder: 0),
        Subject(id: 'music', name: '音乐', shortName: '音', sortOrder: 1),
      ],
      requirements: const [
        SubjectRequirement(
          id: 'math-weekly',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.weekly,
          lessonCount: 4,
        ),
        SubjectRequirement(
          id: 'math-odd',
          subjectId: 'math',
          gradeId: 'grade-1',
          weekMode: WeekMode.odd,
          lessonCount: 2,
        ),
        SubjectRequirement(
          id: 'music-even',
          subjectId: 'music',
          gradeId: 'grade-1',
          weekMode: WeekMode.even,
          lessonCount: 2,
        ),
      ],
      assignments: const [],
    );

    await tester.tap(find.text('批量添加任课'));
    await tester.pumpAndSettle();

    final subjectField = tester.widget<AppSelectField<String>>(
      find.byKey(const ValueKey('batch-assignment-subject-0')),
    );
    final initialWeekModeField = tester.widget<AppSelectField<WeekMode>>(
      find.byKey(const ValueKey('batch-assignment-week-mode-0')),
    );
    expect(subjectField.value, 'math');
    expect(initialWeekModeField.items.values.toList(), [
      WeekMode.weekly,
      WeekMode.odd,
    ]);
    expect(initialWeekModeField.items.values, isNot(contains(WeekMode.even)));

    subjectField.onChanged('music');
    await tester.pumpAndSettle();

    final changedWeekModeField = tester.widget<AppSelectField<WeekMode>>(
      find.byKey(const ValueKey('batch-assignment-week-mode-0')),
    );
    expect(changedWeekModeField.value, WeekMode.even);
    expect(changedWeekModeField.items.values.toList(), [WeekMode.even]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量添加任课每行的节数输入与下拉控件垂直对齐', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(tester);

    await tester.tap(find.text('批量添加任课'));
    await tester.pumpAndSettle();

    final countControl = tester.getRect(
      find.descendant(
        of: find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(AppTextFormField),
        ),
        matching: find.byType(material.InputDecorator),
      ),
    );
    for (final key in [
      'batch-assignment-class-0',
      'batch-assignment-subject-0',
      'batch-assignment-week-mode-0',
    ]) {
      final selectControl = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(material.InputDecorator),
        ),
      );
      expect(selectControl.center.dy, closeTo(countControl.center.dy, 1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量添加任课超出科目需求时在弹窗内提示并保持打开', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(tester);
    await tester.tap(find.byKey(const ValueKey('teacher-view-tab-teacher')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('批量添加任课'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加 1 项'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AppDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.textContaining('超过需求')),
      findsOneWidget,
    );
    expect(find.text('已添加 1 项任课'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有已设置需求的科目不能批量添加任课', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(
      tester,
      requirements: const [],
      assignments: const [],
    );

    await tester.tap(find.text('批量添加任课'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(find.text('请先设置科目节数需求，再添加任课'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('较窄窗口下视角工具栏和分配区可正常布局', (tester) async {
    tester.view.physicalSize = const Size(720, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mountTeacherPage(tester);

    await tester.tap(find.text('班级视角'));
    await tester.pumpAndSettle();

    expect(find.text('批量添加任课'), findsOneWidget);
    expect(find.text('未分配课程'), findsOneWidget);
    await tester.tap(find.text('教师视角'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('teacher-assignment-table-header')),
      findsOneWidget,
    );
    expect(find.text('未分配课程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _sampleClasses = [
  ClassBrief(
    stageId: 'primary',
    gradeId: 'grade-1',
    id: 'class-1',
    name: '初一（1）班',
  ),
];

const _sampleSubjects = [
  Subject(id: 'math', name: '数学', shortName: '数', sortOrder: 0),
];

const _sampleTeachers = [
  Teacher(id: 'teacher-1', name: '张伟', shortName: '张', sortOrder: 0),
];

const _sampleAssignments = [
  TeacherAssignment(
    id: 'assignment-1',
    termId: _termId,
    teacherId: 'teacher-1',
    classId: 'class-1',
    subjectId: 'math',
    weekMode: WeekMode.weekly,
    lessonCount: 5,
  ),
];

const _sampleRequirements = [
  SubjectRequirement(
    id: 'req-1',
    subjectId: 'math',
    gradeId: 'grade-1',
    weekMode: WeekMode.weekly,
    lessonCount: 5,
  ),
];
