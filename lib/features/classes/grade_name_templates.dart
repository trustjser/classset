/// 为指定学段生成不与现有年级重名的连续模板名称。
List<String> generateGradeNames({
  required String template,
  required int count,
  required Iterable<String> existingNames,
  String prefix = '',
}) {
  if (count < 1 || count > 9) {
    throw ArgumentError.value(count, 'count', '数量须为 1–9');
  }
  final used = existingNames.map((name) => name.trim()).toSet();
  final names = <String>[];
  for (var ordinal = 1; names.length < count; ordinal++) {
    final numeral = _chineseNumeral(ordinal);
    final name = switch (template) {
      '中文数字' => '$numeral年级',
      '阿拉伯数字' => '$ordinal 年级',
      '初一式' => '初$numeral',
      '自定义前缀' => '${prefix.trim()}$numeral',
      _ => throw ArgumentError.value(template, 'template', '未知命名方式'),
    };
    if (used.add(name)) names.add(name);
  }
  return names;
}

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
