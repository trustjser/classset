import 'package:class_set/features/classes/grade_name_templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('阿拉伯数字模板 {n} 生成 1、2、3', () {
    expect(
      generateGradeNames(template: '{n}', count: 3, existingNames: {}),
      ['1', '2', '3'],
    );
  });

  test('中文数字模板 {N} 生成 一、二、三', () {
    expect(
      generateGradeNames(template: '{N}', count: 3, existingNames: {}),
      ['一', '二', '三'],
    );
  });

  test('自定义模板支持 {n} 与 {N} 占位符', () {
    expect(
      generateGradeNames(
        template: '{n} 年级',
        count: 3,
        existingNames: {},
      ),
      ['1 年级', '2 年级', '3 年级'],
    );
    expect(
      generateGradeNames(template: '{N}班', count: 3, existingNames: {}),
      ['一班', '二班', '三班'],
    );
  });

  test('模板跳过已有名称并填补空缺', () {
    expect(
      generateGradeNames(
        template: '{n}',
        count: 3,
        existingNames: {'1', '3'},
      ),
      ['2', '4', '5'],
    );
  });

  test('模板不含占位符时抛错', () {
    expect(
      () => generateGradeNames(template: '年级', count: 3, existingNames: {}),
      throwsArgumentError,
    );
  });

  test('数量范围必须为 1 到 9', () {
    expect(
      () => generateGradeNames(template: '{n}', count: 0, existingNames: {}),
      throwsArgumentError,
    );
    expect(
      () => generateGradeNames(template: '{n}', count: 10, existingNames: {}),
      throwsArgumentError,
    );
  });
}
