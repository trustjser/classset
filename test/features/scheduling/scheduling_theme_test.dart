import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/domain/scheduling/scheduling_snapshot.dart';
import 'package:class_set/features/scheduling/scheduling_controller.dart';
import 'package:class_set/features/scheduling/scheduling_timetable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

void main() {
  testWidgets('课表切换暗色主题时使用暗色画布和卡片', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final snapshot = SchedulingSnapshot(
      term: AcademicTerm(
        id: 't',
        title: '学期',
        academicYear: '2026',
        semesterLabel: '秋季',
        firstTeachingWeekStart: null,
        teachingWeekCount: 20,
        createdAt: DateTime(2026),
      ),
      inputFingerprint: 'test',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => FTheme(
          data: AppTheme.foruiFor(true),
          child: FToaster(child: child!),
        ),
        home: Scaffold(
          body: SchedulingTimetable(
            snapshot: snapshot,
            state: const SchedulingState(),
            onStart: () {},
            onRefresh: () {},
            onRules: () {},
            onReport: () {},
            onDetectionReport: () {},
            onCancel: () {},
            onDone: () {},
            onExport: (_, _) {},
            onPreviewMove: (_, _, _) => throw UnimplementedError(),
            onMove: (_, _, _) async => throw UnimplementedError(),
            onUndo: () {},
            onRedo: () {},
            onSetLock: (_, _) async {},
            onSetAllLocks: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == AppThemeColors.dark.canvas,
      ),
      findsWidgets,
    );
    final title = find.text('课表安排');
    expect(title, findsOneWidget);
    final card = tester.widget<Container>(
      find
          .ancestor(
            of: title,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).boxShadow != null,
            ),
          )
          .first,
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, AppThemeColors.dark.surface);
    expect(decoration.border, isNull);
    expect(decoration.boxShadow, AppThemeColors.dark.cardShadow);
    for (final (width, gutter) in [
      (879.0, 16.0),
      (880.0, 32.0),
      (1800.0, 32.0),
    ]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(
        find
            .ancestor(
              of: title,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.decoration is BoxDecoration &&
                    (w.decoration! as BoxDecoration).boxShadow != null,
              ),
            )
            .first,
      );
      expect(bounds.left, gutter);
      final scroll = tester.widget<ListView>(
        find
            .descendant(
              of: find.byType(SchedulingTimetable),
              matching: find.byType(ListView),
            )
            .first,
      );
      expect(scroll.padding, EdgeInsets.fromLTRB(gutter, 16, gutter, gutter));
      expect(tester.takeException(), isNull);
    }
  });
}
