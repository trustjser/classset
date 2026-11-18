import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/data/providers/school_repository_provider.dart';
import 'package:class_set/data/repositories/school_repository.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/models/school_structure.dart';
import 'package:class_set/domain/models/stage_routine.dart';
import 'package:class_set/domain/models/subject.dart';
import 'package:class_set/domain/models/teacher.dart';
import 'package:class_set/domain/scheduling/actual_timetable.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/temporary_adjustments/temporary_adjustments_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

/// 与应用一致的 Forui / Material 主题外壳。
Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, inner) => f.FTheme(
    data: AppTheme.foruiFor(false),
    child: f.FToaster(child: inner!),
  ),
  home: Scaffold(body: child),
);

class _Repository implements SchoolRepository {
  _Repository(this.state);
  final TemporaryTimetableState state;

  @override
  Future<TemporaryTimetableState> loadTemporaryTimetable(String termId) async =>
      state;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 只够渲染页面，不含调整记录与课程冲突的最小数据。
TemporaryTimetableState _state() {
  final snapshot = SchedulingSnapshot(
    term: AcademicTerm(
      id: 't',
      title: '学期',
      academicYear: '2026',
      semesterLabel: '秋',
      firstTeachingWeekStart: DateTime(2026, 9, 7),
      teachingWeekCount: 2,
      createdAt: DateTime(2026),
    ),
    inputFingerprint: 'toolbar-fixture',
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
    ],
    teachers: const [
      Teacher(id: 'teacher', name: '李老师', shortName: '李', sortOrder: 0),
    ],
    existingItems: const [],
  );
  return TemporaryTimetableState(
    snapshot: snapshot,
    exceptions: const [],
    records: const [],
    lessons: const ActualTimetable().expand(snapshot, const []),
    revision: 'v',
    reconciliationPending: false,
  );
}

void main() {
  testWidgets('调代课页面使用统一的879/880边距断点', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (width, gutter) in [(879.0, 16.0), (880.0, 32.0)]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(width),
          overrides: [
            schoolRepositoryProvider.overrideWithValue(_Repository(_state())),
          ],
          child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
        ),
      );
      await tester.pumpAndSettle();
      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(TemporaryAdjustmentsPage),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(padding.padding, EdgeInsets.fromLTRB(gutter, 16, gutter, gutter));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('统一工具条：模式与操作同排，筛选独立成行且窄屏不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = _state();

    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            schoolRepositoryProvider.overrideWithValue(_Repository(state)),
          ],
          child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 1400：完整日期区间；1080：中等宽度。两档都把「模式 + 操作」放上排，
    // 「查看维度 + 时间范围」放下排，避免控件挤在同一行后换行成阶梯。
    for (final size in const [Size(1400, 900), Size(1080, 700)]) {
      await pumpAt(size);
      final topRow = [find.text('实际课表'), find.text('导出')];
      final filterRow = [find.text('班级视图'), find.textContaining('教学周')];
      for (final group in [...topRow, ...filterRow]) {
        expect(group, findsOneWidget, reason: '$size 下工具条控件缺失');
      }
      final topDy = topRow.map((group) => tester.getCenter(group).dy).toList();
      final filterDy = filterRow
          .map((group) => tester.getCenter(group).dy)
          .toList();
      for (final dy in topDy) {
        expect(
          (dy - topDy.first).abs(),
          lessThan(12),
          reason: '$size 下模式与操作未在同一排',
        );
      }
      for (final dy in filterDy) {
        expect(
          (dy - filterDy.first).abs(),
          lessThan(12),
          reason: '$size 下筛选控件未在同一排',
        );
      }
      expect(
        filterDy.first - topDy.first,
        greaterThan(24),
        reason: '$size 下筛选行应与上排分离',
      );
      expect(tester.takeException(), isNull, reason: '$size 下工具条布局溢出');
    }

    // 窄屏回退为多行，控件仍要齐全且不溢出。
    await pumpAt(const Size(800, 1000));
    expect(find.text('实际课表'), findsOneWidget);
    expect(find.text('班级视图'), findsOneWidget);
    expect(find.text('导出'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('调整记录页头部复用统一工具条，空态居中成组', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schoolRepositoryProvider.overrideWithValue(_Repository(_state())),
        ],
        child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整记录'));
    await tester.pumpAndSettle();

    // 上排：模式 + 操作；下排：筛选。
    final topRow = [find.text('实际课表'), find.text('显示已取消'), find.text('导出')];
    for (final group in topRow) {
      expect(group, findsOneWidget, reason: '调整记录页上排控件缺失');
    }
    final topDy = topRow.map((group) => tester.getCenter(group).dy).toList();
    for (final dy in topDy) {
      expect((dy - topDy.first).abs(), lessThan(12), reason: '调整记录页上排未对齐');
    }
    final filterDy = tester.getCenter(find.text('全部类型')).dy;
    expect(filterDy - topDy.first, greaterThan(24), reason: '筛选行应与上排分离');
    expect(tester.takeException(), isNull, reason: '调整记录页头部布局溢出');

    // 空态应在内容面板中水平居中，不再贴左上角。
    final panel = find.byKey(
      const ValueKey('temporary-adjustments-records-panel'),
    );
    expect(panel, findsOneWidget);
    final panelRect = tester.getRect(panel);
    final titleRect = tester.getRect(find.text('还没有调整记录'));
    expect(
      ((titleRect.left + titleRect.right) / 2 - panelRect.center.dx).abs(),
      lessThan(12),
      reason: '空态标题未水平居中',
    );
    expect(
      titleRect.top,
      greaterThan(panelRect.top + 40),
      reason: '空态标题不应紧贴面板顶部',
    );
    expect(find.text('查看实际课表'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('窄屏未选中课次时课表撑满可用高度', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schoolRepositoryProvider.overrideWithValue(_Repository(_state())),
        ],
        child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
      ),
    );
    await tester.pumpAndSettle();

    final gridPanel = find.byKey(
      const ValueKey('temporary-adjustments-grid-panel'),
    );
    expect(gridPanel, findsOneWidget);
    // 旧逻辑把课表固定为 SizedBox(height: 420)，下方留白且内部出现垂直滚动条。
    expect(
      tester.getRect(gridPanel).height,
      greaterThan(480),
      reason: '课表卡片应撑满 Expanded 区域，而不是固定 420',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('调整记录页窄屏筛选整宽一行，不挤成阶梯', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          schoolRepositoryProvider.overrideWithValue(_Repository(_state())),
        ],
        child: _wrap(const TemporaryAdjustmentsPage(termId: 't')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整记录'));
    await tester.pumpAndSettle();

    // 班级下拉在班级视图下显示具体班级名，这里只断言 hint 固定的四项。
    const filterLabels = ['全部类型', '全部状态', '全部教师', '全部日期'];
    for (final label in filterLabels) {
      expect(find.text(label), findsOneWidget, reason: '$label 筛选器缺失');
    }
    final centers = filterLabels
        .map((label) => tester.getCenter(find.text(label)).dy)
        .toList();
    for (final dy in centers) {
      expect(
        (dy - centers.first).abs(),
        lessThan(12),
        reason: '窄屏下筛选器应整宽排在同一行，而不是挤成阶梯状两行',
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });
}
