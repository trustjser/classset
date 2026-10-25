import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/features/public_rooms/public_rooms_page.dart';
import 'package:class_set/features/subjects/subjects_page.dart';
import 'package:class_set/features/subjects/dialogs/subject_preset_dialog.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

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
    for (final id in ['t1', 't2']) {
      await repository.saveTerm(
        AcademicTerm(
          id: id,
          title: id,
          academicYear: '2026-2027',
          semesterLabel: '第一学期',
          firstTeachingWeekStart: DateTime(2026, 9, 1),
          teachingWeekCount: 20,
          createdAt: DateTime(2026, 8, 1),
        ),
      );
    }
    await repository.saveStage(
      const SchoolStage(id: 'jr', termId: 't1', name: '初中部', sortOrder: 1),
    );
    await repository.saveGrade(
      const GradeGroup(id: 'g1', stageId: 'jr', name: '一年级', sortOrder: 0),
    );
    await repository.saveClasses(const [
      ClassGroup(id: 'c1', gradeId: 'g1', name: '一（1）班', sortOrder: 0),
    ]);
    await repository.saveRoutine(
      const StageRoutine(
        stageId: 'jr',
        teachingWeekdays: {1, 2, 3, 4, 5},
        periodTypes: [
          LessonPeriodType(
            id: 'p_am',
            name: '上午',
            defaultLessonCount: 2,
            sortOrder: 0,
            lessonTimes: [],
          ),
        ],
        overrides: [],
      ),
    );
    await repository.saveSubjects(const [
      Subject(id: 'music', name: '音乐', shortName: '音', sortOrder: 0),
    ]);
    await repository.savePublicRooms(const [
      PublicRoom(
        id: 'room_music',
        name: '音乐室',
        roomCount: 2,
        capacityPerRoom: 1,
        sortOrder: 0,
      ),
      PublicRoom(
        id: 'room_hall',
        name: '礼堂',
        roomCount: 1,
        capacityPerRoom: 3,
        sortOrder: 1,
      ),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    String activeTerm = 't1',
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container.read(activeTermIdProvider.notifier).state = activeTerm;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => f.FTheme(
            data: AppTheme.foruiFor(false),
            child: f.FToaster(child: child!),
          ),
          home: const Scaffold(body: SubjectsPage(termId: 't1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('初中部（'));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    expect(target, findsOneWidget, reason: 'Expected interactive control $key');
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> openRooms(
    WidgetTester tester, {
    String subject = 'music',
  }) async {
    await tapKey(tester, 'preset-summary-$subject');
    await tapKey(tester, 'subject-settings-tab-rooms');
  }

  Future<void> chooseRoom(WidgetTester tester, String label) async {
    await tapKey(tester, 'subject-room-selection');
    await tester.tap(find.text(label == '不设场室' ? label : '$label（公共场室）').last);
    await tester.pumpAndSettle();
  }

  Future<void> setLimit(WidgetTester tester, String value) async {
    final target = find.byKey(const ValueKey('subject-parallel-limit'));
    await tester.ensureVisible(target);
    await tester.enterText(target, value);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'room draft inherits through scopes, explicit no-room suppresses, reset restores, save commits',
    (tester) async {
      await pumpPage(tester);
      await openRooms(tester);
      expect(find.byKey(const ValueKey('preset-scope-school')), findsNothing);
      await chooseRoom(tester, '音乐室');
      await setLimit(tester, '2');
      await tapKey(tester, 'preset-scope-grade-g1');
      expect(find.text('当前场室：音乐室'), findsOneWidget);
      expect(find.text('来源：初中部（学段）'), findsWidgets);
      await chooseRoom(tester, '不设场室');
      await setLimit(tester, '5');
      await tapKey(tester, 'preset-expand-grade-g1');
      await tapKey(tester, 'preset-scope-class-c1');
      expect(find.text('当前场室：不设场室'), findsOneWidget);
      expect(find.text('同科目同时上课上限：5'), findsOneWidget);
      expect(find.text('来源：一年级（年级）'), findsWidgets);
      expect(
        find.byKey(const ValueKey('subject-parallel-limit')),
        findsNothing,
      );
      await chooseRoom(tester, '礼堂');
      await tapKey(tester, 'subject-room-reset');
      expect(find.text('当前场室：不设场室'), findsOneWidget);
      await tapKey(tester, 'preset-scope-grade-g1');
      await tapKey(tester, 'subject-room-reset');
      expect(find.text('当前场室：音乐室'), findsOneWidget);
      await tapKey(tester, 'subject-settings-tab-presets');
      await tapKey(tester, 'preset-cell-1-p_am-1');
      await tapKey(tester, 'subject-settings-tab-rooms');
      expect(find.text('当前场室：音乐室'), findsOneWidget);
      final before = await tester.runAsync(
        () => repository.watchSubjectRoomAssignments('t1').first,
      );
      expect(before, isEmpty);
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      final rows = (await tester.runAsync(
        () => repository.watchSubjectRoomAssignments('t1').first,
      ))!;
      expect(rows, hasLength(1));
      expect(rows.single.scope, FreeSlotScope.stage);
      expect(rows.single.roomId, 'room_music');
      final limits = (await tester.runAsync(
        () => repository.watchSubjectParallelLimits('t1').first,
      ))!;
      expect(limits, hasLength(2));
      expect(
        limits
            .singleWhere((row) => row.scope == FreeSlotScope.grade)
            .maxParallelLessons,
        5,
      );
      final presets = (await tester.runAsync(
        () => repository.watchPresetsForSubject('music').first,
      ))!;
      expect(presets, hasLength(1));
    },
  );

  testWidgets(
    'cancel discards room and limit drafts; saved no-room and limit reset survive reopen',
    (tester) async {
      await pumpPage(tester);
      await openRooms(tester);
      await chooseRoom(tester, '音乐室');
      await setLimit(tester, '2');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => repository.watchSubjectRoomAssignments('t1').first,
        ),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => repository.watchSubjectParallelLimits('t1').first,
        ),
        isEmpty,
      );
      await openRooms(tester);
      expect(find.text('当前场室：不设场室'), findsOneWidget);
      await chooseRoom(tester, '音乐室');
      await setLimit(tester, '2');
      await tapKey(tester, 'preset-scope-grade-g1');
      await chooseRoom(tester, '不设场室');
      await setLimit(tester, '5');
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      var rows = (await tester.runAsync(
        () => repository.watchSubjectRoomAssignments('t1').first,
      ))!;
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((row) => row.scope == FreeSlotScope.grade).roomId,
        isNull,
      );
      await openRooms(tester);
      await tapKey(tester, 'preset-scope-grade-g1');
      expect(find.text('当前场室：不设场室'), findsOneWidget);
      await tapKey(tester, 'subject-room-reset');
      await tapKey(tester, 'subject-parallel-reset');
      await tapKey(tester, 'preset-expand-grade-g1');
      await tapKey(tester, 'preset-scope-class-c1');
      expect(find.text('当前场室：音乐室'), findsOneWidget);
      expect(find.text('同科目同时上课上限：2'), findsOneWidget);
      expect(find.text('来源：初中部（学段）'), findsWidgets);
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      rows = (await tester.runAsync(
        () => repository.watchSubjectRoomAssignments('t1').first,
      ))!;
      expect(rows, hasLength(1));
      expect(
        await tester.runAsync(
          () => repository.watchSubjectParallelLimits('t1').first,
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'quick entry uses page term over active term and push/pop retains all editor drafts',
    (tester) async {
      await pumpPage(tester, activeTerm: 't2');
      await openRooms(tester);
      await chooseRoom(tester, '音乐室');
      await setLimit(tester, '2');
      await tapKey(tester, 'subject-settings-tab-constraints');
      final minimum = find.byKey(
        const ValueKey('constraint-stage-jr-daily-minDaily'),
      );
      await tester.ensureVisible(minimum);
      await tester.enterText(minimum, '1');
      await tapKey(tester, 'subject-settings-tab-presets');
      await tapKey(tester, 'preset-cell-1-p_am-1');
      await tapKey(tester, 'subject-settings-tab-rooms');
      await tapKey(tester, 'subject-public-rooms-entry');
      expect(
        tester.widget<PublicRoomsPage>(find.byType(PublicRoomsPage)).termId,
        't1',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('当前场室：音乐室'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('subject-parallel-limit')),
                    matching: find.byType(TextField),
                  )
                  .first,
            )
            .controller!
            .text,
        '2',
      );
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => repository.watchSubjectRoomAssignments('t1').first,
        ),
        hasLength(1),
      );
      expect(
        await tester.runAsync(
          () => repository.watchSubjectRoomAssignments('t2').first,
        ),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => repository.watchPresetsForSubject('music').first,
        ),
        hasLength(1),
      );
      final constraints = (await tester.runAsync(
        () => repository.watchLessonConstraintsForSubject('music').first,
      ))!;
      expect(constraints.single.minimumDailyLessons, 1);
    },
  );

  testWidgets(
    'unsaved subject settings stay on page until subject save and can be reopened',
    (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('+ 添加科目'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外语'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('点击设置科目高级设置').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'subject-settings-tab-rooms');
      await chooseRoom(tester, '音乐室');
      await setLimit(tester, '3');
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => repository.watchSubjectRoomAssignments('t1').first,
        ),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => repository.watchSubjectParallelLimits('t1').first,
        ),
        isEmpty,
      );
      await tester.tap(find.byTooltip('点击设置科目高级设置').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'subject-settings-tab-rooms');
      expect(find.text('当前场室：音乐室'), findsOneWidget);
      await chooseRoom(tester, '礼堂');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final subject = (await tester.runAsync(
        () => repository.watchSubjects().first,
      ))!.singleWhere((row) => row.name == '外语');
      final rows = (await tester.runAsync(
        () => repository.watchSubjectRoomAssignments('t1').first,
      ))!;
      expect(rows.single.subjectId, subject.id);
      expect(rows.single.roomId, 'room_music');
      final limits = (await tester.runAsync(
        () => repository.watchSubjectParallelLimits('t1').first,
      ))!;
      expect(limits.single.subjectId, subject.id);
      expect(limits.single.maxParallelLessons, 3);
    },
  );

  testWidgets(
    'unchanged reopened new-subject room draft blocks dialog and page save after catalog deletion',
    (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('+ 添加科目'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外语'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('点击设置科目高级设置').last);
      await tester.pumpAndSettle();
      final newSubjectId = tester
          .widget<SubjectPresetDialog>(find.byType(SubjectPresetDialog))
          .subject
          .id;
      await tapKey(tester, 'preset-cell-1-p_am-1');
      await tapKey(tester, 'subject-settings-tab-constraints');
      final minimum = find.byKey(
        const ValueKey('constraint-stage-jr-daily-minDaily'),
      );
      await tester.ensureVisible(minimum);
      await tester.enterText(minimum, '1');
      await tapKey(tester, 'subject-settings-tab-rooms');
      await chooseRoom(tester, '音乐室');
      await setLimit(tester, '3');
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();

      await tapKey(tester, 'preset-summary-$newSubjectId');
      await tapKey(tester, 'subject-settings-tab-rooms');
      expect(find.text('当前场室：音乐室'), findsOneWidget);
      expect(
        tester
            .widget<SubjectPresetDialog>(find.byType(SubjectPresetDialog))
            .roomAssignments
            .single
            .roomId,
        'room_music',
      );
      await tapKey(tester, 'subject-public-rooms-entry');
      await tapKey(tester, 'delete-room-room_music');
      await tester.tap(find.text('删除场室及绑定'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('当前场室：场室已删除，请重置'), findsOneWidget);
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(find.text('所选场室已删除，请重新选择或重置为继承。'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(SubjectPresetDialog), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final before = (await tester.runAsync(
        () => repository.watchSubjects().first,
      ))!;
      expect(before.map((row) => row.name), ['音乐']);
      expect(find.text('外语'), findsOneWidget);
      expect(
        await tester.runAsync(() => repository.watchAllPresets().first),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => repository.watchAllLessonConstraints().first,
        ),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => repository.watchSubjectParallelLimits('t1').first,
        ),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => repository.watchAllRequirements().first),
        isEmpty,
      );

      await tapKey(tester, 'preset-summary-$newSubjectId');
      await tapKey(tester, 'subject-settings-tab-rooms');
      await tapKey(tester, 'subject-room-reset');
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = (await tester.runAsync(
        () => repository.watchSubjects().first,
      ))!;
      final foreignLanguage = saved.singleWhere((row) => row.name == '外语');
      expect(saved, hasLength(2));
      expect(find.text('外语'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => repository.watchPresetsForSubject(foreignLanguage.id).first,
        ),
        hasLength(1),
      );
      final constraints = (await tester.runAsync(
        () => repository
            .watchLessonConstraintsForSubject(foreignLanguage.id)
            .first,
      ))!;
      expect(constraints.single.minimumDailyLessons, 1);
      final limits = (await tester.runAsync(
        () => repository.watchSubjectParallelLimits('t1').first,
      ))!;
      expect(limits.single.maxParallelLessons, 3);
      expect(
        await tester.runAsync(
          () => repository.watchSubjectRoomAssignments('t1').first,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'page preflight checks every new-subject room draft before inserting any subject',
    (tester) async {
      await pumpPage(tester);
      for (final choice in [
        (subject: '外语', room: '礼堂'),
        (subject: '美术', room: '音乐室'),
      ]) {
        await tester.tap(find.text('+ 添加科目'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice.subject));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('点击设置科目高级设置').last);
        await tester.pumpAndSettle();
        await tapKey(tester, 'subject-settings-tab-rooms');
        await chooseRoom(tester, choice.room);
        await tester.tap(find.text('保存设置'));
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() => repository.deletePublicRoom('room_music'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final subjects = (await tester.runAsync(
        () => repository.watchSubjects().first,
      ))!;
      expect(subjects.map((row) => row.name), ['音乐']);
      expect(find.text('外语'), findsOneWidget);
      expect(find.text('美术'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => repository.watchSubjectRoomAssignments('t1').first,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'explicit no-room remains selectable when a catalog room is named no-room',
    (tester) async {
      await repository.savePublicRooms(const [
        PublicRoom(
          id: 'reserved_name',
          name: '不设场室',
          roomCount: 1,
          capacityPerRoom: 1,
          sortOrder: 2,
        ),
      ]);
      await pumpPage(tester);
      await openRooms(tester);
      await chooseRoom(tester, '不设场室');
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      final rows = (await tester.runAsync(
        () => repository.watchSubjectRoomAssignments('t1').first,
      ))!;
      expect(rows.single.roomId, isNull);
    },
  );

  testWidgets(
    'deleted catalog room keeps the dialog draft open until the choice is repaired',
    (tester) async {
      await pumpPage(tester);
      await openRooms(tester);
      await chooseRoom(tester, '音乐室');
      await setLimit(tester, '2');
      await tapKey(tester, 'subject-public-rooms-entry');
      await tapKey(tester, 'delete-room-room_music');
      await tester.tap(find.text('删除场室及绑定'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('当前场室：场室已删除，请重置'), findsOneWidget);
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(find.text('所选场室已删除，请重新选择或重置为继承。'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      await chooseRoom(tester, '礼堂');
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      final rows = (await tester.runAsync(
        () => repository.watchSubjectRoomAssignments('t1').first,
      ))!;
      expect(rows.single.roomId, 'room_hall');
      final limits = (await tester.runAsync(
        () => repository.watchSubjectParallelLimits('t1').first,
      ))!;
      expect(limits.single.maxParallelLessons, 2);
    },
  );

  testWidgets(
    'room settings work in a narrow dialog with one vertical scroll',
    (tester) async {
      await pumpPage(tester);
      await openRooms(tester);
      tester.view.physicalSize = const Size(540, 800);
      await tester.pumpAndSettle();
      final vertical = find.descendant(
        of: find.byType(SubjectPresetDialog),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(vertical, findsOneWidget);
      await chooseRoom(tester, '音乐室');
      await setLimit(tester, '0');
      await tester.tap(find.text('保存设置'));
      await tester.pumpAndSettle();
      expect(find.text('同科目同时上课上限须为正整数'), findsOneWidget);
      expect(
        await tester.runAsync(
          () => repository.watchSubjectParallelLimits('t1').first,
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
