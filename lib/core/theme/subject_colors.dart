import 'package:class_set/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// 科目按 ID 稳定散列到十种清透色；不落库、不改变科目归属。
/// 色名仅帮助辨识，课表始终同时显示科目名称。
abstract final class SubjectColors {
  /// (晴空蓝浅色前景, 夜空蓝深色前景)，配对格底检查普通文字对比度。
  static const List<(Color, Color)> _palette = [
    (Color(0xFFA1396D), Color(0xFFF3ACCE)), // 蔷薇
    (Color(0xFF9B521E), Color(0xFFF1BC92)), // 杏橙
    (Color(0xFF806314), Color(0xFFE6D18D)), // 琥珀
    (Color(0xFF4F7029), Color(0xFFB8D98D)), // 青柠
    (Color(0xFF1F7457), Color(0xFF91DABB)), // 薄荷
    (Color(0xFF117783), Color(0xFF88D7DE)), // 湖青
    (Color(0xFF326CAB), Color(0xFFA1C8FA)), // 晴蓝
    (Color(0xFF5C56AC), Color(0xFFB9B3FA)), // 鸢尾
    (Color(0xFF8253A3), Color(0xFFD2AEED)), // 丁香
    (Color(0xFF9C477D), Color(0xFFE5ABD3)), // 莓粉
  ];

  /// 科目 ID → 色板序号。FNV-1a 32 位散列 + 位移混合，
  /// 让相邻/相似的 ID 也尽量分散。
  static int indexOf(String subjectId) {
    var hash = 0x811C9DC5;
    for (final code in subjectId.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    hash ^= hash >> 15;
    hash = (hash * 0x2545F491) & 0xFFFFFFFF;
    hash ^= hash >> 13;
    return hash % _palette.length;
  }

  /// 科目主色（文字 / 圆点 / 强调）。
  static Color of(BuildContext context, String subjectId) {
    final (light, dark) = _palette[indexOf(subjectId)];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? dark : light;
  }

  /// 课表格 / 科目色块的浅底：同色低透明度叠在 surface 上，
  /// 浅色模式约 8%、暗色模式约 12%（深底需要更高不透明度才可感知）。
  static Color cellBackground(BuildContext context, String subjectId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Color.alphaBlend(
      of(context, subjectId).withValues(alpha: isDark ? .12 : .08),
      context.appColors.surface,
    );
  }
}

/// 科目色标圆点（默认 8×8）：科目节数、教师任课等列表中
/// 标识科目归属，颜色与课表单元格一致。
class SubjectDot extends StatelessWidget {
  const SubjectDot({required this.subjectId, this.size = 8, super.key});

  final String subjectId;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: SubjectColors.of(context, subjectId),
      shape: BoxShape.circle,
    ),
  );
}
