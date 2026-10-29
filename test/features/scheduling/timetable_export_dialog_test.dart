import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/scheduling/schedule_export.dart';
import 'package:class_set/features/scheduling/timetable_export_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

void main() {
  testWidgets('导出设置可切换学段时间轴、学段标记及学校按日分表', (tester) async {
    TimetableExportOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) =>
            f.FTheme(data: AppTheme.foruiFor(false), child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showAppDialog<TimetableExportOptions>(
                  context: context,
                  builder: (context) => const TimetableExportDialog(),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('统一时间轴（推荐）'), findsOneWidget);
    await tester.tap(find.text('按学段分别展示'));
    await tester.tap(find.text('跨学段课程显示学段'));
    await tester.tap(find.text('学校总课表按学段汇总整周'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导出'));
    await tester.pumpAndSettle();
    expect(result?.teacherUnified, isFalse);
    expect(result?.showTeacherStage, isFalse);
    expect(result?.schoolWeekly, isFalse);
    expect(tester.takeException(), isNull);
  });
}
