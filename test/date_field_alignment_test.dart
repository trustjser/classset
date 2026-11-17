import 'package:class_set/core/format/date_format.dart';
import 'package:class_set/core/theme/app_theme.dart';
import 'package:class_set/core/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) =>
        FTheme(data: AppTheme.foruiFor(false), child: child!),
    home: Scaffold(body: Center(child: child)),
  ),
);

double _leadingInset(WidgetTester tester, Key fieldKey) {
  final fieldRect = tester.getRect(find.byKey(fieldKey).first);
  final editable = find
      .descendant(of: find.byKey(fieldKey), matching: find.byType(EditableText))
      .first;
  final editableRect = tester.getRect(editable);
  return editableRect.left - fieldRect.left;
}

double _trailingInset(WidgetTester tester, Key fieldKey) {
  final fieldRect = tester.getRect(find.byKey(fieldKey).first);
  final editable = find
      .descendant(of: find.byKey(fieldKey), matching: find.byType(EditableText))
      .first;
  final editableRect = tester.getRect(editable);
  return fieldRect.right - editableRect.right;
}

void main() {
  testWidgets('日期框文字左右间距与文本框一致', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 300,
              child: AppTextFormField(
                key: const ValueKey('text-field'),
                size: .sm,
                controller: TextEditingController(text: '2026-09-01'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 300,
              child: AppDateField(
                key: const ValueKey('date-field'),
                value: DateTime(2026, 9, 1),
                hint: '选择日期',
                firstDate: DateTime(2026, 1, 1),
                lastDate: DateTime(2027, 1, 1),
                format: formatDateYmdWithWeekday,
                onChanged: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
    // 向导/弹窗表单中两种控件上下相邻，文字内缩必须一致（实测均为 14px）。
    expect(
      _leadingInset(tester, const ValueKey('date-field')),
      moreOrLessEquals(
        _leadingInset(tester, const ValueKey('text-field')),
        epsilon: 1,
      ),
    );
    expect(
      _trailingInset(tester, const ValueKey('date-field')),
      moreOrLessEquals(
        _trailingInset(tester, const ValueKey('text-field')),
        epsilon: 1,
      ),
    );
  });
}
