# ClassSet 纸感日程设计语言实施计划

**目标：** 重构项目设计规范与主题基础，明暗成对，形成亲和、克制的排课工具体验。
**架构：** 继续使用 Flutter / Riverpod / Forui；`design/DESIGN.md` 为规范入口，`AppTheme` 为运行时 token 来源。保持现有业务、数据与导航流程。

- [x] 1. 用对比度和窄屏大字测试明确可读性要求，验证现有缺口。
- [x] 2. 更新暖纸 / 暮林双主题、Material 与 Forui 映射、科目色及公共控件；默认跟随系统，尊重减少动态效果。
- [x] 3. 重写设计规范，明确色彩、排版、布局、组件、课表、交互与迁移边界，提供可审阅的视觉样张。
- [x] 4. 运行主题、公共组件、导航与相关页面检查、静态分析和 macOS 构建；审查最终差异，记录未覆盖范围。

验证：`flutter test --no-pub test/design_language_test.dart test/subject_colors_test.dart test/features/scheduling/scheduling_theme_test.dart`，相关现有组件与页面测试，`flutter analyze --no-pub`，`flutter build macos --debug --no-pub`，`git diff --check`。

## 验证记录

- 新增 `design_language_test.dart` 10 项通过：真实应用随系统主题、手动切换、减少动态效果、明暗文本与状态对比度、实际 Forui 字段边界、十种科目格底、375 宽及 200% 文字操作。
- 所选 10 个测试文件：48 通过、7 失败。HEAD 临时快照相同旧测试原有 37 通过、8 失败；本轮刷新作息页视觉基准后该项通过。其余失败为班级页旧布局尺寸、旧提示/统计文案、撤销/排序断言和带班人员设置布局定位；未修改这些业务。
- `flutter analyze --no-pub`：41 项警告，与 HEAD 快照逐项比较无新增；因此不记为静态分析全通过。
- `flutter build macos --debug --no-pub` 通过；`git diff --check` 通过。未运行完整 `flutter test` 全套。
- 本地 Chrome 实际渲染明暗 HTML 样张：1440、1040、375 与 812×375，页面无水平溢出；窄屏仅课表内部横向滚动。主题、课程详情和示例反馈可用，减少动态效果生效，无 JS 异常。样张不是 Flutter 页面截图。
- Flutter MCP 未连接，未热重载；CUA 预览连接超时，改用本地无头 Chrome。
- 独立审查提出的 Forui 输入边界映射缺口已修复，补测先红后绿，复查无新增问题。

## 晴空蓝配色落地（用户选定方案）

- [x] 将全局浅色主色设为 `#2864DC`、画布 `#F4F7FC`、纯白面板；深色主色 `#97BAFF`、画布 `#111722`、面板 `#1B2433`。
- [x] 同步辅助文字、选中态、控件边界、状态色与 Material 高层级表面；十种科目色使用更清透的配对色，保留稳定 ID 映射。
- [x] 更新 `design/DESIGN.md` 与 `design/design-language.html`，采用晴空蓝 / 夜空蓝命名。
- [x] 刷新作息页视觉基准，运行定向测试、静态分析、macOS 构建及明暗样张检查。

本次结果：37 项定向测试通过，macOS debug 构建通过；分析仍为 41 项既有警告，无新增。样张明暗与多窗口交互检查通过，规范色值与代码一致；未重跑全套测试，之前记录的业务旧失败不计为已修复。
