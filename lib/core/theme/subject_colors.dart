import 'package:class_set/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// 科目配色：不落库，按科目 ID 稳定散列到固定色板。
///
/// - 同一科目在任何设备、任何会话中颜色一致（FNV-1a 散列，与排序、
///   增删其他科目无关）。
/// - 色板为 10 个鲜亮色相，刻意避开系统语义色的纯色相：品牌蓝
///   （#0075DE，链接/选中）、成功绿（#2BA471，成功提示）、警示金
///   （#C98A2B）、危险红（#D54941），避免科目颜色被误读为状态色。
/// - 浅色模式前景取 600 级饱和色（小字号可读），暗色模式换 400 级
///   亮色；格底用同色低透明度叠加 surface，两种模式下观感一致。
abstract final class SubjectColors {
  /// (浅色模式前景, 暗色模式前景)。
  static const List<(Color, Color)> _palette = [
    (Color(0xFFDB2777), Color(0xFFF472B6)), // 玫红
    (Color(0xFFEA580C), Color(0xFFFB923C)), // 甜橙
    (Color(0xFFCA8A04), Color(0xFFFACC15)), // 明黄
    (Color(0xFF65A30D), Color(0xFFA3E635)), // 青柠
    (Color(0xFF16A34A), Color(0xFF4ADE80)), // 草绿
    (Color(0xFF0D9488), Color(0xFF2DD4BF)), // 青碧
    (Color(0xFF0284C7), Color(0xFF38BDF8)), // 天青
    (Color(0xFF4F46E5), Color(0xFF818CF8)), // 靛蓝
    (Color(0xFF7C3AED), Color(0xFFA78BFA)), // 紫罗兰
    (Color(0xFFC026D3), Color(0xFFE879F9)), // 洋红
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
  /// 浅色模式约 13%、暗色模式约 22%（深底需要更高不透明度才可感知）。
  static Color cellBackground(BuildContext context, String subjectId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Color.alphaBlend(
      of(context, subjectId).withValues(alpha: isDark ? .22 : .13),
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
