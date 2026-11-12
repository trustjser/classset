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
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/supervision/supervision_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

void main() {
  testWidgets('鼠标框选批量移除可取消、保存重开，并保留生效版本', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _SelectionRepository(database, _snapshot());
    await tester.runAsync(() async {
      await repository.saveTerm(_term);
      await repository.saveSupervisionDraft(_draft, expectedRevision: 0);
      final preview = await repository.previewSupervisionPublish(
        't',
        _term.teachingWeekStart(2)!,
      );
      expect(preview.canPublish, isTrue, reason: preview.errors.join('、'));
      await repository.publishSupervision('t', preview);
      await repository.saveSupervisionDraft(_draft, expectedRevision: 0);
    });
    await _open(tester, repository);
    final a = tester.getRect(find.byKey(const ValueKey('duty-post-a')));
    final b = tester.getRect(find.byKey(const ValueKey('duty-post-b')));
    await _mouseSelect(
      tester,
      a.topLeft + const Offset(8, 8),
      b.bottomRight - const Offset(8, 8),
    );
    expect(find.text('已选 2 个岗位'), findsOneWidget);
    expect(find.text('选择带班教师'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('批量移除'), findsNothing);
    await _mouseSelect(
      tester,
      a.topLeft + const Offset(8, 8),
      b.bottomRight - const Offset(8, 8),
    );
    final c = tester.getRect(find.byKey(const ValueKey('duty-post-c')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _mouseSelect(
      tester,
      c.topLeft + const Offset(8, 8),
      c.bottomRight - const Offset(8, 8),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.text('已选 3 个岗位'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('duty-post-c')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 个岗位'), findsOneWidget);

    await tester.tap(find.text('批量移除'));
    await tester.pumpAndSettle();
    expect(find.text('批量移除带班岗位'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('duty-post-a')), findsOneWidget);
    expect(find.text('已选 2 个岗位'), findsOneWidget);
    await tester.tap(find.text('批量移除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除 2 个岗位'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('duty-post-a')), findsNothing);
    expect(find.byKey(const ValueKey('duty-post-b')), findsNothing);
    expect(find.byKey(const ValueKey('duty-post-c')), findsOneWidget);
    expect(
      (await tester.runAsync(
        () => repository.watchSupervisionDraft('t').first,
      ))!.posts,
      hasLength(4),
    );
    final saved = await _saveFromUi(tester, repository);
    expect(saved.posts.map((post) => post.id).toSet(), {'c', 'merged'});
    expect(saved.assignments, {'c': 'teacher', 'merged': 'second'});
    expect(saved.manualPostIds, {'c', 'merged'});
    final version = (await tester.runAsync(
      () => repository.watchSupervisionVersions('t').first,
    ))!.single;
    expect(version.draft.posts, hasLength(4));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _open(tester, repository);
    expect(find.byKey(const ValueKey('duty-post-a')), findsNothing);
    expect(find.byKey(const ValueKey('duty-post-merged')), findsOneWidget);

    // Published/history views remain read-only even when dragged with a mouse.
    final select = find.byType(AppSelectField<String>);
    final label = tester
        .widget<AppSelectField<String>>(select)
        .items
        .keys
        .firstWhere((label) => label.startsWith('待生效'));
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
    final publishedA = tester.getRect(
      find.byKey(const ValueKey('duty-post-a')),
    );
    final publishedB = tester.getRect(
      find.byKey(const ValueKey('duty-post-b')),
    );
    await _mouseSelect(
      tester,
      publishedA.topLeft + const Offset(8, 8),
      publishedB.bottomRight - const Offset(8, 8),
    );
    expect(find.text('批量移除'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按班级重复展示的合班岗位框选只计一次，切换视角清理选择', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _SelectionRepository(database, _snapshot());
    await tester.runAsync(() async {
      await repository.saveTerm(_term);
      await repository.saveSupervisionDraft(_draft, expectedRevision: 0);
    });
    await _open(tester, repository);
    await tester.tap(find.text('按班级'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('duty-day-7')));
    await tester.pumpAndSettle();
    final first = tester.getRect(
      find.byKey(const ValueKey('duty-class-c1-evening-2,3')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('duty-class-c2-evening-2,3')),
    );
    await _mouseSelect(
      tester,
      first.topLeft + const Offset(8, 8),
      second.bottomRight - const Offset(8, 8),
    );
    expect(find.text('已选 1 个岗位'), findsOneWidget);
    await tester.tap(find.text('按教师'));
    await tester.pumpAndSettle();
    expect(find.text('批量移除'), findsNothing);
    expect(find.text('已选 1 个岗位'), findsNothing);
    await tester.tap(find.text('按班级'));
    await tester.pumpAndSettle();
    final mergedFirst = tester.getRect(
      find.byKey(const ValueKey('duty-class-c1-evening-2,3')),
    );
    final mergedSecond = tester.getRect(
      find.byKey(const ValueKey('duty-class-c2-evening-2,3')),
    );
    await _mouseSelect(
      tester,
      mergedFirst.topLeft + const Offset(8, 8),
      mergedSecond.bottomRight - const Offset(8, 8),
    );
    await tester.tap(find.text('批量移除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除 1 个岗位'));
    await tester.pumpAndSettle();
    final saved = await _saveFromUi(tester, repository);
    expect(saved.posts.map((post) => post.id).toSet(), {'a', 'b', 'c'});
    expect(saved.assignments.containsKey('merged'), isFalse);
    expect(saved.manualPostIds.contains('merged'), isFalse);

    expect(tester.takeException(), isNull);
  });

  testWidgets('框选靠近边缘自动滚动并扩大选择，触屏拖动仍为滚动', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = _SelectionRepository(
      database,
      _snapshot(classCount: 30),
    );
    await tester.runAsync(() async {
      await repository.saveTerm(_term);
      await repository.saveSupervisionDraft(
        SupervisionDraft(
          termId: 't',
          posts: [
            for (var i = 0; i < 30; i++)
              SupervisionPost(
                id: 'many-$i',
                kind: SupervisionKind.afterSchool,
                name: '课后服务',
                stageId: 'stage',
                weekday: 1,
                periodTypeId: 'service',
                lessonIndices: [1],
                classIds: ['c${i + 1}'],
              ),
          ],
        ),
        expectedRevision: 0,
      );
    });
    await _open(tester, repository);
    final region = tester.getRect(
      find.byKey(const ValueKey('duty-selection-region')),
    );
    final first = tester.getRect(
      find.byKey(const ValueKey('duty-post-many-0')),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: first.center);
    await gesture.down(first.topLeft + const Offset(8, 8));
    await gesture.moveTo(Offset(first.center.dx, region.bottom - 8));
    await tester.pump(const Duration(milliseconds: 16));
    int count() => int.parse(
      tester
          .widget<Text>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  RegExp(r'^已选 \d+ 个岗位$').hasMatch(widget.data ?? ''),
            ),
          )
          .data!
          .split(' ')[1],
    );
    final initial = count();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();
    expect(count(), greaterThan(initial));
    await tester.tap(find.text('取消选择'));
    await tester.pumpAndSettle();
    final touch = await tester.createGesture(kind: PointerDeviceKind.touch);
    await touch.down(region.center);
    await touch.moveTo(region.center - const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 16));
    await touch.up();
    await tester.pumpAndSettle();
    expect(find.text('批量移除'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<SupervisionDraft> _saveFromUi(
  WidgetTester tester,
  _SelectionRepository repository,
) async {
  repository.lastSave = null;
  await tester.tap(find.text('保存草稿'));
  await tester.pump();
  expect(repository.lastSave, isNotNull);
  SupervisionDraft? saved;
  Object? failure;
  var completed = false;
  repository.lastSave!.then(
    (value) {
      saved = value;
      completed = true;
    },
    onError: (Object error) {
      failure = error;
      completed = true;
    },
  );
  // A native Drift transaction can need several fake-clock microtask turns.
  // Wait for its actual completion while allowing both queues to progress.
  for (var i = 0; i < 100 && !completed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(completed, isTrue, reason: '保存操作应完成');
  expect(failure, isNull);
  await tester.pumpAndSettle();
  return saved!;
}

Future<void> _mouseSelect(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: from);
  await gesture.down(from);
  await gesture.moveTo(Offset(from.dx + 24, from.dy));
  await tester.pump();
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await gesture.removePointer();
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, _SelectionRepository repository) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
}

class _SelectionRepository extends DriftSchoolRepository {
  _SelectionRepository(super.database, this.fixture);
  final SchedulingSnapshot fixture;
  Future<SupervisionDraft>? lastSave;
  @override
  Future<SupervisionDraft> saveSupervisionDraft(
    SupervisionDraft draft, {
    required int expectedRevision,
  }) {
    return lastSave = super.saveSupervisionDraft(
      draft,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<SchedulingSnapshot> loadSchedulingSnapshot(String termId) async =>
      fixture;
}

final _term = AcademicTerm(
  id: 't',
  title: '学期',
  academicYear: '2026',
  semesterLabel: '秋',
  firstTeachingWeekStart: DateUtils.dateOnly(DateTime.now())
      .subtract(Duration(days: DateTime.now().weekday - 1)),
  teachingWeekCount: 8,
  createdAt: DateTime(2026),
);

SchedulingSnapshot _snapshot({int classCount = 2}) => SchedulingSnapshot(
  term: _term,
  inputFingerprint: 'selection',
  stages: const [
    SchoolStage(id: 'stage', termId: 't', name: '初中', sortOrder: 0),
  ],
  grades: const [
    GradeGroup(id: 'grade', stageId: 'stage', name: '初一', sortOrder: 0),
  ],
  classes: [
    for (var i = 1; i <= classCount; i++)
      ClassGroup(id: 'c$i', gradeId: 'grade', name: '初一$i班', sortOrder: i),
  ],
  teachers: const [
    Teacher(id: 'teacher', name: '张老师', shortName: '张', sortOrder: 0),
    Teacher(id: 'second', name: '李老师', shortName: '李', sortOrder: 1),
  ],
  routines: const [
    StageRoutine(
      stageId: 'stage',
      teachingWeekdays: {1, 5, 7},
      overrides: [],
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
          name: '晚上',
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
    ),
  ],
  freeSlots: [
    for (final day in [1, 5, 7])
      for (final period in ['service', 'evening'])
        for (var i = 1; i <= (period == 'service' ? 1 : 3); i++)
          FreeSlot(
            id: '$day-$period-$i',
            scope: FreeSlotScope.stage,
            scopeId: 'stage',
            stageId: 'stage',
            periodTypeId: period,
            weekday: day,
            lessonIndex: i,
            label: period == 'service' ? '课后服务' : '自习',
          ),
  ],
);
const _draft = SupervisionDraft(
  termId: 't',
  teacherIds: {'teacher', 'second'},
  posts: [
    SupervisionPost(
      id: 'a',
      kind: SupervisionKind.afterSchool,
      name: '课后服务',
      stageId: 'stage',
      weekday: 1,
      periodTypeId: 'service',
      lessonIndices: [1],
      classIds: ['c1'],
    ),
    SupervisionPost(
      id: 'b',
      kind: SupervisionKind.afterSchool,
      name: '课后服务',
      stageId: 'stage',
      weekday: 5,
      periodTypeId: 'service',
      lessonIndices: [1],
      classIds: ['c1'],
    ),
    SupervisionPost(
      id: 'c',
      kind: SupervisionKind.afterSchool,
      name: '课后服务',
      stageId: 'stage',
      weekday: 7,
      periodTypeId: 'service',
      lessonIndices: [1],
      classIds: ['c2'],
    ),
    SupervisionPost(
      id: 'merged',
      kind: SupervisionKind.eveningStudy,
      name: '晚自习',
      groupName: '阅读合班',
      location: '阅览室',
      stageId: 'stage',
      weekday: 7,
      periodTypeId: 'evening',
      lessonIndices: [2, 3],
      classIds: ['c1', 'c2'],
    ),
  ],
  assignments: {
    'a': 'teacher',
    'b': 'second',
    'c': 'teacher',
    'merged': 'second',
  },
  manualPostIds: {'a', 'b', 'c', 'merged'},
);
