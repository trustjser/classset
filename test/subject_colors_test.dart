import 'package:class_set/core/theme/subject_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubjectColors', () {
    test('同一科目 ID 颜色稳定，且落在色板范围内', () {
      const ids = [
        'subj-001',
        '9f8b7c6d-5e4f-3a2b-1c0d-e9f8a7b6c5d4',
        '语文',
        '',
        'x',
      ];
      for (final id in ids) {
        final first = SubjectColors.indexOf(id);
        for (var i = 0; i < 5; i++) {
          expect(SubjectColors.indexOf(id), first, reason: 'ID=$id 应稳定');
        }
        expect(first, inInclusiveRange(0, 9), reason: 'ID=$id 应落在色板内');
      }
    });

    test('常见 ID 组合分散到多个颜色，避免全部撞色', () {
      final indices = {
        for (var i = 0; i < 40; i++) SubjectColors.indexOf('subject-$i'),
      };
      expect(indices.length, greaterThanOrEqualTo(8));
    });

    testWidgets('浅色 / 暗色模式返回不同颜色，格底叠在 surface 上', (tester) async {
      final colors = <Color>[];
      final backgrounds = <Color>[];
      Future<void> pump(Brightness brightness) async {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(brightness),
            theme: brightness == Brightness.dark
                ? ThemeData.dark()
                : ThemeData.light(),
            home: Builder(
              builder: (context) => ColoredBox(
                color: SubjectColors.cellBackground(context, 'subject-1'),
                child: SubjectDot(subjectId: 'subject-1'),
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(SubjectDot));
        colors.add(SubjectColors.of(context, 'subject-1'));
        backgrounds.add(
          tester.widget<ColoredBox>(find.byType(ColoredBox).first).color,
        );
      }

      // 两种主题分别挂载（同一 testWidgets 内连续 pump 不会刷新 Theme）。
      await pump(Brightness.light);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await pump(Brightness.dark);
      expect(colors.first, isNot(colors.last), reason: '暗色模式应换更亮的色');
      // 格底 = 同色低透明度叠 surface，必须不是纯 surface 也不是纯前景色。
      for (final background in backgrounds) {
        expect(background, isNot(colors.first));
        expect(background, isNot(colors.last));
      }
    });

    testWidgets('SubjectDot 渲染为科目主色圆点', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SubjectDot(subjectId: 'subject-1')),
        ),
      );
      final dotFinder = find.descendant(
        of: find.byType(SubjectDot),
        matching: find.byType(Container),
      );
      final decoration =
          tester.widget<Container>(dotFinder.first).decoration! as BoxDecoration;
      expect(
        decoration.color,
        SubjectColors.of(tester.element(dotFinder.first), 'subject-1'),
      );
      expect(decoration.shape, BoxShape.circle);
    });
  });
}
