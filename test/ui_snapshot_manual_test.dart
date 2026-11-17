import 'dart:io';
import 'dart:ui' as ui;

import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/domain/models/academic_term.dart';
import 'package:class_set/features/setup/setup_wizard_page.dart';
import 'package:class_set/features/terms/dialogs/term_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Future<void> _loadFonts() async {
  final bytes = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
      .readAsBytesSync();
  final loader = FontLoader('ArialUnicode')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _snapshot(WidgetTester tester, String fileName) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('snapshot')),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  final bytes = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  File('/tmp/$fileName').writeAsBytesSync(bytes!.buffer.asUint8List());
  debugPrint('SNAPSHOT_SAVED /tmp/$fileName');
}

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    // 无头测试环境没有系统 CJK 字体，统一映射到本地加载的 ArialUnicode。
    theme: AppTheme.light.copyWith(textTheme: _cjkTextTheme),
    builder: (context, child) =>
        FTheme(data: AppTheme.foruiFor(false), child: child!),
    home: RepaintBoundary(
      key: const ValueKey('snapshot'),
      child: ColoredBox(color: const Color(0xFFF6F7F9), child: child),
    ),
  ),
);

final _cjkTextTheme = ThemeData.light().textTheme.apply(
  fontFamily: 'ArialUnicode',
  fontFamilyFallback: const ['ArialUnicode'],
);

void main() {
  setUpAll(_loadFonts);

  testWidgets('导出空数据向导与编辑弹窗截图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize = const Size(720, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 1) 空数据向导（第二步）。
    await tester.pumpWidget(_wrap(const SetupWizardPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await _snapshot(tester, 'wizard_step2.png');

    // 2) 编辑学期信息弹窗。
    final term = AcademicTerm(
      id: 't1',
      title: '2026 学年 · 秋季学期',
      academicYear: '2026-2027',
      semesterLabel: '秋季学期',
      firstTeachingWeekStart: DateTime(2026, 9, 1),
      teachingWeekCount: 22,
      createdAt: DateTime(2026, 8, 1),
    );
    await tester.pumpWidget(_wrap(TermEditorDialog(term: term)));
    await tester.pumpAndSettle();
    await _snapshot(tester, 'term_editor_dialog.png');
  });
}
