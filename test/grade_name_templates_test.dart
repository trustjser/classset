import 'package:class_set/features/classes/grade_name_templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('中文模板跳过已有名称并填补空缺', () {
    expect(
      generateGradeNames(
        template: '中文数字',
        count: 3,
        existingNames: {'一年级', '三年级'},
      ),
      ['二年级', '四年级', '五年级'],
    );
  });

  test('初一式和自定义前缀生成正确名称', () {
    expect(generateGradeNames(template: '初一式', count: 2, existingNames: {}), [
      '初一',
      '初二',
    ]);
    expect(
      generateGradeNames(
        template: '自定义前缀',
        count: 2,
        prefix: '高',
        existingNames: {},
      ),
      ['高一', '高二'],
    );
  });

  test('数量范围必须为 1 到 9', () {
    expect(
      () => generateGradeNames(template: '中文数字', count: 0, existingNames: {}),
      throwsArgumentError,
    );
    expect(
      () => generateGradeNames(template: '中文数字', count: 10, existingNames: {}),
      throwsArgumentError,
    );
  });
}
