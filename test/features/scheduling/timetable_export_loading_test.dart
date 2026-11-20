import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/common_period.dart';
import 'package:class_set/domain/models/schedule_item.dart';
import 'package:class_set/domain/models/schedule_position.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:class_set/features/scheduling/scheduling_page.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

class _Repository implements SchoolRepository {
  @override
  Stream<String> watchSchoolName() => Stream.value('阳光学校');
  @override
  Stream<List<CommonPeriod>> watchCommonPeriods(String stageId) =>
      Stream.value([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends SchedulingController {
  _Controller(
    SchoolRepository repository,
    SchedulingSnapshot snapshot,
    List<ScheduleItem> items,
  ) : super(repository, snapshot.term.id) {
    state = SchedulingState(
      status: SchedulingStatus.ready,
      snapshot: snapshot,
      items: items,
    );
  }
  @override
  Future<void> refresh({bool preserveHistory = false}) async {}
}

void main() {
  testWidgets('导出显示加载状态，取消保存后恢复并传入学校学期文件名', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _Repository();
    final term = AcademicTerm(
      id: 't',
      title: '2027秋季学期',
      academicYear: '2027',
      semesterLabel: '秋季',
      firstTeachingWeekStart: null,
      teachingWeekCount: 20,
      createdAt: DateTime(2027),
    );
    final snapshot = SchedulingSnapshot(
      term: term,
      inputFingerprint: 'test',
      stages: const [
        SchoolStage(id: 's', termId: 't', name: '小学', sortOrder: 0),
      ],
      grades: const [
        GradeGroup(id: 'g', stageId: 's', name: '一年级', sortOrder: 0),
      ],
      classes: const [
        ClassGroup(id: 'c', gradeId: 'g', name: '一班', sortOrder: 0),
      ],
      routines: const [
        StageRoutine(
          stageId: 's',
          teachingWeekdays: {1},
          periodTypes: [
            LessonPeriodType(
              id: 'p',
              name: '上午',
              defaultLessonCount: 1,
              sortOrder: 0,
              lessonTimes: [],
            ),
          ],
          overrides: [],
        ),
      ],
    );
    const items = [
      ScheduleItem(
        id: 'a',
        termId: 't',
        assignmentId: 'x',
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
    ];
    var pending = Completer<FileSaveLocation?>();
    String? suggested;
    final container = ProviderContainer(
      overrides: [
        schoolRepositoryProvider.overrideWithValue(repository),
        schedulingControllerProvider('t')
            .overrideWith((ref) => _Controller(repository, snapshot, items)),
        timetableExportSaveLocationProvider.overrideWithValue((name) {
          suggested = name;
          return pending.future;
        }),
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
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(suggested, '阳光学校_2027秋季学期_课表.zip');
    expect(find.text('正在导出课表，请稍候…'), findsOneWidget);
    expect(find.byType(ModalBarrier), findsWidgets);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('正在导出课表，请稍候…'), findsNothing);

    pending = Completer<FileSaveLocation?>();
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    pending.completeError(StateError('磁盘不可用'));
    await tester.pumpAndSettle();
    expect(find.textContaining('导出课表失败'), findsOneWidget);
    expect(find.text('正在导出课表，请稍候…'), findsNothing);
    ScaffoldMessenger.of(tester.element(find.byType(SchedulingPage)))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    final directory = Directory.systemTemp.createTempSync(
      'timetable-export-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final outputFile = File.fromUri(directory.uri.resolve('export.zip'));
    pending = Completer<FileSaveLocation?>();
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打印设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原始比例（Excel 默认）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每张表缩放至一页').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('横向打印'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('正在导出课表，请稍候…'), findsOneWidget);
    pending.complete(FileSaveLocation(outputFile.path));
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.text('课表压缩包已导出').evaluate().isNotEmpty) break;
    }
    expect(find.text('课表压缩包已导出'), findsOneWidget);
    expect(find.text('正在导出课表，请稍候…'), findsNothing);
    expect(outputFile.existsSync(), isTrue);
    final archive = ZipDecoder().decodeBytes(outputFile.readAsBytesSync());
    expect(archive.files.map((file) => file.name).toSet(), {
      '阳光学校_2027秋季学期_班级课表.xlsx',
      '阳光学校_2027秋季学期_教师课表.xlsx',
      '阳光学校_2027秋季学期_学校总课表.xlsx',
    });
    for (final workbook in archive.files) {
      final sheets = ZipDecoder()
          .decodeBytes(workbook.content as List<int>)
          .files
          .where((file) => file.name.startsWith('xl/worksheets/sheet'));
      expect(sheets, isNotEmpty);
      for (final sheet in sheets) {
        final xml = utf8.decode(sheet.content as List<int>);
        expect(xml, contains('orientation="portrait"'));
        expect(xml, contains('fitToWidth="1" fitToHeight="1"'));
      }
    }
    expect(tester.takeException(), isNull);
  });
}
