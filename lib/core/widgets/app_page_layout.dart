import 'package:class_set/core/theme/app_theme.dart';
import 'package:flutter/widgets.dart';

/// 页面与顶部栏共用的实际工作区宽度，排除侧栏后计算响应式边距。
class AppPageLayout extends InheritedWidget {
  const AppPageLayout({
    required this.availableWidth,
    required super.child,
    super.key,
  });

  final double availableWidth;

  static double widthOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppPageLayout>()
          ?.availableWidth ??
      MediaQuery.sizeOf(context).width;

  static double gutterOf(BuildContext context) =>
      AppTheme.pagePaddingForWidth(widthOf(context));

  static EdgeInsets insetsOf(BuildContext context) =>
      AppTheme.pageInsetsForWidth(widthOf(context));

  @override
  bool updateShouldNotify(AppPageLayout oldWidget) =>
      availableWidth != oldWidget.availableWidth;
}
