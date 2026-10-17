/// 年级命名模板占位符：
///   {n} —— 阿拉伯数字（1, 2, 3 …）
///   {N} —— 中文数字（一, 二, 三 …）
/// 模板中可单独或组合使用上述占位符，其余文字原样保留。
/// 例如：'{n} 年级' → 1 年级、2 年级、3 年级；'{N}' → 一、二、三。
const String kArabicTemplate = '{n}';
const String kChineseTemplate = '{N}';

/// 新建年级「命名方式」下拉选项。
const List<String> gradeNamingModes = ['阿拉伯数字', '中文数字', '自定义'];

/// 各内置命名方式对应的默认模板（自定义由用户输入）。
const Map<String, String> gradeNamingTemplates = {
  '阿拉伯数字': kArabicTemplate,
  '中文数字': kChineseTemplate,
};

/// 为指定学段生成不与现有年级重名的连续模板名称。
///
/// [template] 支持占位符 {n} / {N}；若不含任何占位符将抛 [ArgumentError]。
List<String> generateGradeNames({
  required String template,
  required int count,
  required Iterable<String> existingNames,
}) {
  if (count < 1 || count > 9) {
    throw ArgumentError.value(count, 'count', '数量须为 1–9');
  }
  if (!template.contains('{n}') && !template.contains('{N}')) {
    throw ArgumentError.value(
      template,
      'template',
      '模板须包含占位符 {n} 或 {N}',
    );
  }
  final used = existingNames.map((name) => name.trim()).toSet();
  final names = <String>[];
  for (var ordinal = 1; names.length < count; ordinal++) {
    final name = _expandTemplate(template, ordinal);
    if (used.add(name)) names.add(name);
  }
  return names;
}

String _expandTemplate(String template, int ordinal) => template
    .replaceAll('{n}', '$ordinal')
    .replaceAll('{N}', _chineseNumeral(ordinal));

const _digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

String _chineseNumeral(int value) {
  if (value < 10) return _digits[value];
  if (value < 100) {
    final tens = value ~/ 10;
    final units = value % 10;
    return '${tens == 1 ? '' : _digits[tens]}十${units == 0 ? '' : _digits[units]}';
  }
  return '$value';
}
