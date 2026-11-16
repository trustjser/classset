# 内置主题与外观切换实施计划

目标：内置晴空蓝、海盐青、云白墨灰，各自支持浅色、深色、跟随系统；右上角可直接选择并记住偏好。
架构：继续使用 AppTheme + Stateful 根应用，学校业务 Provider 不变。独立外观模型不依赖 Flutter；本机 JSON 仓库负责偏好加载及原子串行保存，main 注入初始偏好和保存回调。

- [ ] 为真实主题选择、跨重启偏好恢复、损坏配置回退及三套明暗对比度补充测试，先复现缺失功能。
- [ ] 创建外观模型与本机偏好仓库；将三套配色映射为相同语义 token，复用 Material / Forui 构造器。
- [ ] 新建响应式主题与外观对话框；接入根应用、顶部栏和 main 的加载/保存，保留快速明暗切换和草稿页面状态。
- [ ] 更新规范，运行实际 UI 交互、仓库读写、主题、应用框架及视觉检查，完成静态分析和 macOS 构建。

文件：lib/core/theme/app_appearance.dart、app_theme.dart；lib/data/repositories/appearance_preferences_repository.dart；lib/core/widgets/appearance_settings_dialog.dart；lib/app.dart、lib/main.dart；test/appearance_preferences_repository_test.dart、test/appearance_switcher_test.dart、test/design_language_test.dart；design/DESIGN.md。

验证：新的偏好和切换测试需覆盖选择海盐青/云白墨灰、独立明暗、恢复系统跟随、跨应用重新挂载恢复，以及实际 Material 与 Forui 颜色同步。现有学校数据和草稿流程不作业务修改。此前定向 37 项通过，全项目分析 41 项旧警告；本轮重新验证并分别报告。
