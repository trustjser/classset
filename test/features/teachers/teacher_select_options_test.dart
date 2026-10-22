import 'package:class_set/features/teachers/presentation/teacher_select_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildUniqueSelectOptions', () {
    test('adds context to duplicate labels and keeps every option', () {
      final options =
          buildUniqueSelectOptions<
            ({String id, String name, String grade}),
            String
          >(
            [
              (id: 'class-1', name: '一班', grade: '一年级'),
              (id: 'class-2', name: '一班', grade: '二年级'),
              (id: 'class-3', name: '二班', grade: '一年级'),
            ],
            labelOf: (item) => item.name,
            valueOf: (item) => item.id,
            disambiguatorOf: (item) => item.grade,
            idOf: (item) => item.id,
          );

      expect(options.length, 3);
      expect(options['一班 · 一年级'], 'class-1');
      expect(options['一班 · 二年级'], 'class-2');
      expect(options['二班'], 'class-3');
    });

    test('uses stable ids when duplicate labels have the same context', () {
      final options =
          buildUniqueSelectOptions<
            ({String id, String name, String grade}),
            String
          >(
            [
              (id: 'class-1', name: '一班', grade: '一年级'),
              (id: 'class-2', name: '一班', grade: '一年级'),
            ],
            labelOf: (item) => item.name,
            valueOf: (item) => item.id,
            disambiguatorOf: (item) => item.grade,
            idOf: (item) => item.id,
          );

      expect(options.length, 2);
      expect(options['一班 · 一年级 · class-1'], 'class-1');
      expect(options['一班 · 一年级 · class-2'], 'class-2');
    });

    test('does not collide with a reserved placeholder label', () {
      final options = buildUniqueSelectOptions<String, String>(
        ['未指定', '张老师'],
        labelOf: (name) => name,
        valueOf: (name) => name,
        disambiguatorOf: (name) => '教师',
        idOf: (name) => name,
        reservedLabels: const {'未指定'},
      );

      expect(options.keys, contains('未指定 · 教师'));
      expect(options.length, 2);
    });
  });
}
