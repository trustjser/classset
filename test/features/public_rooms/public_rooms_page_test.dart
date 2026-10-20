import 'package:class_set/app.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/data/database/app_database.dart' as db;
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/free_slot.dart';
import 'package:class_set/domain/models/public_room.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/subject_room_assignment.dart';
import 'package:class_set/features/public_rooms/public_rooms_page.dart';
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

void main() {
  late db.AppDatabase database;
  late DriftSchoolRepository repository;
  late ProviderContainer container;
  List<int>? pickedBytes;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftSchoolRepository(database);
    pickedBytes = null;
    container = ProviderContainer(
      overrides: [
        schoolRepositoryProvider.overrideWithValue(repository),
        publicRoomWorkbookPickerProvider.overrideWithValue(
          () async => pickedBytes,
        ),
      ],
    );
    container.read(activeTermIdProvider.notifier).state = 'a';
    for (final term in ['a', 'b']) {
      await repository.saveTerm(
        AcademicTerm(
          id: term,
          title: term == 'a' ? '2026 秋季' : '2027 春季',
          academicYear: '2026',
          semesterLabel: '第一学期',
          firstTeachingWeekStart: null,
          teachingWeekCount: 20,
          createdAt: DateTime(2026),
        ),
      );
      for (final stage in ['jr', 'sr']) {
        await repository.saveStage(
          SchoolStage(
            id: '$term-$stage',
            termId: term,
            name: stage == 'jr' ? '初中部' : '高中部',
            sortOrder: 1,
          ),
        );
        await repository.saveGrade(
          GradeGroup(
            id: '$term-$stage-g',
            stageId: '$term-$stage',
            name: '一年级',
            sortOrder: 0,
          ),
        );
        await repository.saveClass(
          ClassGroup(
            id: '$term-$stage-c',
            gradeId: '$term-$stage-g',
            name: '一班',
            sortOrder: 0,
          ),
        );
      }
    }
    await repository.saveSubjects([
      const Subject(id: 'music', name: '音乐', shortName: '音', sortOrder: 0),
    ]);
    await repository.savePublicRooms([
      const PublicRoom(
        id: 'room',
        name: '音乐室',
        roomCount: 2,
        capacityPerRoom: 3,
        sortOrder: 0,
      ),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> assign(
    String term,
    String stage,
    FreeSlotScope scope,
    String? room,
  ) async {
    final scopeId =
        '$term-$stage${scope == FreeSlotScope.grade
            ? '-g'
            : scope == FreeSlotScope.schoolClass
            ? '-c'
            : ''}';
    await repository.replaceSubjectRoomAssignments(
      subjectId: 'music',
      termId: term,
      stageId: '$term-$stage',
      scope: scope,
      scopeId: scopeId,
      assignments: [
        SubjectRoomAssignment(
          id: '',
          subjectId: 'music',
          termId: term,
          stageId: '$term-$stage',
          scope: scope,
          scopeId: scopeId,
          roomId: room,
        ),
      ],
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    double width = 1000,
    bool shell = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: shell
            ? const ClassSetApp(databasePath: '/tmp/test.db')
            : MaterialApp(
                theme: AppTheme.light,
                builder: (context, child) => f.FTheme(
                  data: AppTheme.forui,
                  child: f.FToaster(child: child!),
                ),
                home: const Scaffold(body: PublicRoomsPage()),
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'creates and edits immediately, validates fields and derives total capacity',
    (tester) async {
      await pump(tester);
      expect(find.text('总容量 6 班'), findsOneWidget);
      await tester.tap(find.text('添加场室'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('room-name')), '   ');
      await tester.enterText(find.byKey(const ValueKey('room-count')), '0');
      await tester.enterText(
        find.byKey(const ValueKey('room-capacity')),
        '1.5',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入场室名称'), findsOneWidget);
      expect(find.text('请输入正整数'), findsNWidgets(2));
      await tester.enterText(find.byKey(const ValueKey('room-name')), ' 实验室 ');
      await tester.enterText(find.byKey(const ValueKey('room-count')), '3');
      await tester.enterText(find.byKey(const ValueKey('room-capacity')), '2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final created = (await tester.runAsync(
        () => repository.watchPublicRooms().first,
      ))!.singleWhere((r) => r.name == '实验室');
      await tester.tap(find.byKey(ValueKey('edit-room-${created.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('room-name')),
        '  科学室  ',
      );
      await tester.enterText(find.byKey(const ValueKey('room-capacity')), '4');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('总容量 12 班'), findsOneWidget);
      final saved = (await tester.runAsync(
        () => repository.watchPublicRooms().first,
      ))!.singleWhere((r) => r.id == created.id);
      expect(saved.name, '科学室');
      expect(saved.roomCount, 3);
      expect(saved.capacityPerRoom, 4);
    },
  );

  testWidgets(
    'shows direct current-term labels and effective inherited cross-stage use',
    (tester) async {
      await assign('a', 'jr', FreeSlotScope.stage, 'room');
      await assign('a', 'sr', FreeSlotScope.grade, 'room');
      await assign('b', 'jr', FreeSlotScope.schoolClass, 'room');
      await pump(tester);
      expect(find.text('音乐 · 初中部 / 全学段'), findsOneWidget);
      expect(find.text('音乐 · 高中部 / 一年级'), findsOneWidget);
      expect(find.text('跨学段共用'), findsOneWidget);
      expect(find.textContaining('2027 春季'), findsNothing);
      await tester.runAsync(
        () => assign('a', 'sr', FreeSlotScope.schoolClass, null),
      );
      await tester.pumpAndSettle();
      expect(find.text('跨学段共用'), findsNothing);
      expect(find.text('音乐 · 高中部 / 一年级'), findsOneWidget);
    },
  );

  testWidgets(
    'delete lists readable references in all terms before confirmation and supports cancel',
    (tester) async {
      await assign('a', 'jr', FreeSlotScope.stage, 'room');
      await assign('b', 'sr', FreeSlotScope.schoolClass, 'room');
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('delete-room-room')));
      await tester.pumpAndSettle();
      expect(find.text('2026 秋季 · 音乐 · 初中部 / 全学段'), findsOneWidget);
      expect(find.text('2027 春季 · 音乐 · 高中部 / 一年级 / 一班'), findsOneWidget);
      expect(
        await tester.runAsync(() => repository.watchPublicRooms().first),
        hasLength(1),
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => repository.watchPublicRooms().first),
        hasLength(1),
      );
      await tester.tap(find.byKey(const ValueKey('delete-room-room')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除场室及绑定'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => repository.watchPublicRooms().first),
        isEmpty,
      );
      expect(
        await tester.runAsync(
          () => repository.watchRoomReferences('room').first,
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'unreferenced delete still confirms and narrow page stays usable',
    (tester) async {
      await pump(tester, width: 380);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('delete-room-room')));
      await tester.pumpAndSettle();
      expect(find.text('此场室暂无科目绑定。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-room-room')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-name')), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid Excel import leaves catalog unchanged; valid import appends',
    (tester) async {
      List<int> bytes(bool valid) {
        final excel = Excel.createExcel();
        final sheet = excel[excel.getDefaultSheet()!];
        sheet.appendRow([
          TextCellValue('场室'),
          TextCellValue('个数'),
          TextCellValue('容量（班）'),
        ]);
        sheet.appendRow([
          TextCellValue('实验室'),
          const IntCellValue(2),
          const IntCellValue(1),
        ]);
        if (!valid) {
          sheet.appendRow([
            TextCellValue('音乐室'),
            const IntCellValue(0),
            const IntCellValue(1),
          ]);
        }
        return excel.encode()!;
      }

      pickedBytes = bytes(false);
      await pump(tester);
      await tester.tap(find.text('导入 Excel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('第 3 行'), findsWidgets);
      expect(
        await tester.runAsync(() => repository.watchPublicRooms().first),
        hasLength(1),
      );
      pickedBytes = bytes(true);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导入 Excel'));
      await tester.pumpAndSettle();
      expect(find.text('实验室'), findsOneWidget);
      expect(
        await tester.runAsync(() => repository.watchPublicRooms().first),
        hasLength(2),
      );
    },
  );

  testWidgets('sidebar opens the public room catalog', (tester) async {
    await pump(tester, width: 1440, shell: true);
    await tester.tap(find.text('公共场室'));
    await tester.pumpAndSettle();
    expect(find.byType(PublicRoomsPage), findsOneWidget);
    expect(find.text('音乐室'), findsOneWidget);
  });
}
