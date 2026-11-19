import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:class_set/features/scheduling/schedule_export.dart';
import 'package:class_set/features/scheduling/timetable_export_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' as f;

void main() {
  for (final dark in [false, true]) {
    testWidgets('导出设置可切换并提交（${dark ? '窄窗深色' : '桌面浅色'}）', (tester) async {
      if (dark) {
        await tester.binding.setSurfaceSize(const Size(390, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      TimetableExportOptions? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) =>
              f.FTheme(data: AppTheme.foruiFor(dark), child: child!),
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
      expect(find.text('10 磅'), findsOneWidget);
      final slider = find.byType(f.FSlider);
      final track = tester.getRect(slider);
      await tester.tapAt(Offset(track.center.dx, track.bottom - 18));
      await tester.pumpAndSettle();
      expect(find.text('13 磅'), findsWidgets);
      await tester.ensureVisible(find.text('课节起止时间'));
      await tester.tap(find.text('课节起止时间'));
      await tester.ensureVisible(find.text('打印设置'));
      await tester.tap(find.text('打印设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('原始比例（Excel 默认）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一页宽，高度自动分页').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('分表方式'));
      await tester.pumpAndSettle();
      expect(find.text('统一时间轴（推荐）'), findsOneWidget);
      await tester.tap(find.text('按学段分别展示'));
      await tester.ensureVisible(find.text('跨学段课程显示学段'));
      await tester.tap(find.text('跨学段课程显示学段'));
      await tester.ensureVisible(find.text('学校总课表按学段汇总整周'));
      await tester.tap(find.text('学校总课表按学段汇总整周'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认导出'));
      await tester.pumpAndSettle();
      expect(result?.teacherUnified, isFalse);
      expect(result?.showTeacherStage, isFalse);
      expect(result?.schoolWeekly, isFalse);
      expect(result?.showTime, isFalse);
      expect(result?.fontSize, 13);
      expect(result?.printFit, TimetablePrintFit.width);
      expect(tester.takeException(), isNull);
    });
  }
}
